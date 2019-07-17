module Inference

using ..Core, ..Core.RandomVariables, ..Utilities
using ..Core.RandomVariables: Metadata, _tail, TypedVarInfo
using Distributions, Libtask, Bijectors
using ProgressMeter, LinearAlgebra
using ..Turing: PROGRESS, CACHERESET, AbstractSampler
using ..Turing: Model, runmodel!, get_pvars, get_dvars,
    Sampler, SampleFromPrior, SampleFromUniform,
    Selector, SamplerState
using ..Turing: in_pvars, in_dvars, Turing
using StatsFuns: logsumexp
using Random: GLOBAL_RNG, AbstractRNG
using ..Interface
import MCMCChains: Chains
import AdvancedHMC; const AHMC = AdvancedHMC

import ..Turing: getspace
import Distributions: sample
import ..Core: getchunksize, getADtype
import ..Core.RandomVariables: getparams
import ..Utilities: Sample, save, resume, set_resume!
import ..Interface: AbstractTransition, step!, sample_init!,
    transitions_init, sample_end!

export  InferenceAlgorithm,
        Hamiltonian,
        AbstractGibbs,
        GibbsComponent,
        StaticHamiltonian,
        AdaptiveHamiltonian,
        SampleFromUniform,
        SampleFromPrior,
        MH,
        Gibbs,      # classic sampling
        HMC,
        SGLD,
        SGHMC,
        HMCDA,
        NUTS,       # Hamiltonian-like sampling
        DynamicNUTS,
        IS,
        SMC,
        CSMC,
        PG,
        PIMH,
        PMMH,
        IPMCMC,  # particle-based sampling
        assume,
        observe,
        step,
        WelfordVar,
        WelfordCovar,
        NaiveCovar,
        get_var,
        get_covar,
        add_sample!,
        reset!,
        step!

#######################
# Sampler abstraction #
#######################
abstract type AbstractAdapter end
abstract type InferenceAlgorithm end
abstract type Hamiltonian{AD} <: InferenceAlgorithm end
abstract type StaticHamiltonian{AD} <: Hamiltonian{AD} end
abstract type AdaptiveHamiltonian{AD} <: Hamiltonian{AD} end

getchunksize(::T) where {T <: Hamiltonian} = getchunksize(T)
getchunksize(::Type{<:Hamiltonian{AD}}) where AD = getchunksize(AD)
getADtype(alg::Hamiltonian) = getADtype(typeof(alg))
getADtype(::Type{<:Hamiltonian{AD}}) where {AD} = AD

"""
    mh_accept(H::T, H_new::T, log_proposal_ratio::T) where {T<:Real}

Peform MH accept criteria with log acceptance ratio. Returns a `Bool` for acceptance.

Note: This function is only used in PMMH.
"""
function mh_accept(H::T, H_new::T, log_proposal_ratio::T) where {T<:Real}
    return log(rand()) + H_new < H + log_proposal_ratio, min(0, -(H_new - H))
end

# Internal variables for MCMCChains.
const INTERNAL_VARS =
    Dict(:internals => ["elapsed", "eval_num", "lf_eps", "lp", "weight", "le"])

###########################
# Generic Transition type #
###########################

struct Transition{T} <: AbstractTransition
    θ  :: T
    lp :: Float64
end

function transition(spl::Sampler)
    theta = getparams(spl.state.vi, spl)
    lp = getlogp(spl.state.vi)
    return Transition{typeof(theta)}(theta, lp)
end

function additional_parameters(::Type{Transition})
    return [:lp]
end

function transitions_init(
    ::AbstractRNG,
    model::Model,
    spl::Sampler,
    N::Integer;
    kwargs...
)
    ttype = transition_type(spl)
    return Vector{ttype}(undef, N)
end

#########################
# Default sampler state #
#########################

"""
A blank `SamplerState` that contains only `VarInfo` information.
"""
mutable struct BlankState{VIType<:VarInfo} <: SamplerState
    vi :: VIType
end

#######################################
# Concrete algorithm implementations. #
#######################################

include("hmc.jl")
include("mh.jl")
include("is.jl")
include("AdvancedSMC.jl")
include("gibbs.jl")
include("../contrib/inference/sghmc.jl")
include("../contrib/inference/AdvancedSMCExtensions.jl")

for alg in (:SMC, :PG, :PMMH, :IPMCMC, :MH, :IS)
    @eval getspace(::$alg{space}) where {space} = space
    @eval getspace(::Type{<:$alg{space}}) where {space} = space
end
for alg in (:HMC, :HMCDA, :NUTS, :SGLD, :SGHMC)
    @eval getspace(::$alg{<:Any, space}) where {space} = space
    @eval getspace(::Type{<:$alg{<:Any, space}}) where {space} = space
end
getspace(::Gibbs) = Tuple{}()
getspace(::Type{<:Gibbs}) = Tuple{}()

@inline floatof(::Type{T}) where {T <: Real} = typeof(one(T)/one(T))
@inline floatof(::Type) = Real

@inline Turing.Core.get_matching_type(spl::Turing.Sampler, vi::Turing.RandomVariables.VarInfo, ::Type{T}) where {T <: AbstractFloat} = floatof(eltype(vi, spl))
@inline Turing.Core.get_matching_type(spl::Turing.Sampler{<:Hamiltonian}, vi::Turing.RandomVariables.VarInfo, ::Type{TV}) where {T, N, TV <: Array{T, N}} = Array{Turing.Core.get_matching_type(spl, vi, T), N}
@inline Turing.Core.get_matching_type(spl::Turing.Sampler{<:Union{PG, SMC}}, vi::Turing.RandomVariables.VarInfo, ::Type{TV}) where {T, N, TV <: Array{T, N}} = TArray{T, N}

## Fallback functions

# utility funcs for querying sampler information
require_gradient(spl::Sampler) = false
require_particles(spl::Sampler) = false

assume(spl::Sampler, dist::Distribution) =
error("Turing.assume: unmanaged inference algorithm: $(typeof(spl))")

observe(spl::Sampler, weight::Float64) =
error("Turing.observe: unmanaged inference algorithm: $(typeof(spl))")

## Default definitions for assume, observe, when sampler = nothing.
function assume(spl::A,
    dist::Distribution,
    vn::VarName,
    vi::VarInfo) where {A<:Union{SampleFromPrior, SampleFromUniform}}

    if haskey(vi, vn)
        r = vi[vn]
    else
        r = isa(spl, SampleFromUniform) ? init(dist) : rand(dist)
        push!(vi, vn, r, dist, spl)
    end
    # NOTE: The importance weight is not correctly computed here because
    #       r is genereated from some uniform distribution which is different from the prior
    # acclogp!(vi, logpdf_with_trans(dist, r, istrans(vi, vn)))

    r, logpdf_with_trans(dist, r, istrans(vi, vn))

end

function assume(spl::A,
    dists::Vector{T},
    vn::VarName,
    var::Any,
    vi::VarInfo) where {T<:Distribution, A<:Union{SampleFromPrior, SampleFromUniform}}

    @assert length(dists) == 1 "Turing.assume only support vectorizing i.i.d distribution"
    dist = dists[1]
    n = size(var)[end]

    vns = map(i -> VarName(vn, "[$i]"), 1:n)

    if haskey(vi, vns[1])
        rs = vi[vns]
    else
        rs = isa(spl, SampleFromUniform) ? init(dist, n) : rand(dist, n)

        if isa(dist, UnivariateDistribution) || isa(dist, MatrixDistribution)
            for i = 1:n
                push!(vi, vns[i], rs[i], dist, spl)
            end
            @assert size(var) == size(rs) "Turing.assume: variable and random number dimension unmatched"
            var = rs
        elseif isa(dist, MultivariateDistribution)
            for i = 1:n
                push!(vi, vns[i], rs[:,i], dist, spl)
            end
            if isa(var, Vector)
                @assert length(var) == size(rs)[2] "Turing.assume: variable and random number dimension unmatched"
                for i = 1:n
                    var[i] = rs[:,i]
                end
            elseif isa(var, Matrix)
                @assert size(var) == size(rs) "Turing.assume: variable and random number dimension unmatched"
                var = rs
            else
                @error("Turing.assume: unsupported variable container"); error()
            end
        end
    end

    # acclogp!(vi, sum(logpdf_with_trans(dist, rs, istrans(vi, vns[1]))))

    var, sum(logpdf_with_trans(dist, rs, istrans(vi, vns[1])))

end


observe(::Nothing,
        dist::T,
        value::Any,
        vi::VarInfo) where T = observe(SampleFromPrior(), dist, value, vi)

function observe(spl::A,
    dist::Distribution,
    value::Any,
    vi::VarInfo) where {A<:Union{SampleFromPrior, SampleFromUniform}}

    vi.num_produce += one(vi.num_produce)
    Turing.DEBUG && @debug "dist = $dist"
    Turing.DEBUG && @debug "value = $value"

    # acclogp!(vi, logpdf(dist, value))
    logpdf(dist, value)

end

function observe(spl::A,
    dists::Vector{T},
    value::Any,
    vi::VarInfo) where {T<:Distribution, A<:Union{SampleFromPrior, SampleFromUniform}}

    @assert length(dists) == 1 "Turing.observe only support vectorizing i.i.d distribution"
    dist = dists[1]
    @assert isa(dist, UnivariateDistribution) || isa(dist, MultivariateDistribution) "Turing.observe: vectorizing matrix distribution is not supported"
    if isa(dist, UnivariateDistribution)  # only univariate distributions support broadcast operation (logpdf.) by Distributions.jl
        # acclogp!(vi, sum(logpdf.(Ref(dist), value)))
        sum(logpdf.(Ref(dist), value))
    else
        # acclogp!(vi, sum(logpdf(dist, value)))
        sum(logpdf(dist, value))
    end

end

#########################################
# Default definitions for the interface #
#########################################
function sample(
    model::ModelType,
    alg::AlgType,
    N::Integer;
    kwargs...
) where {
    ModelType<:Sampleable,
    SamplerType<:AbstractSampler,
    AlgType<:InferenceAlgorithm
}
    return sample(model, Sampler(alg, model), N; kwargs...)
end

function sample(
    rng::AbstractRNG,
    model::ModelType,
    alg::AlgType,
    N::Integer;
    kwargs...
) where {
    ModelType<:Sampleable,
    SamplerType<:AbstractSampler,
    AlgType<:InferenceAlgorithm
}
    return sample(rng, model, Sampler(alg, model), N; kwargs...)
end

function sample_init!(
    ::AbstractRNG,
    model::Model,
    spl::Sampler,
    N::Integer;
    kwargs...
)
    # Resume the sampler.
    set_resume!(spl; kwargs...)
end

function sample_end!(
    ::AbstractRNG,
    ::Model,
    ::AbstractSampler,
    ::Integer,
    ::Vector{TransitionType};
    kwargs...
) where {TransitionType<:AbstractTransition}
    # Silence the default API function.
end

function _params_to_array(ts::Vector{T}) where {T<:Union{ParticleTransition,Transition}}
    local names
    vals  = Vector{Vector{Float64}}()
    for t in ts
        names, v = flatten_namedtuple(t.θ)
        push!(vals, v)
    end

    return names, vals
end

function flatten_namedtuple(nt::NamedTuple{pnames}) where pnames
    vals  = Vector{Float64}()
    names = Vector{AbstractString}()
    for k in pnames
        v = nt[k]
        flatten_namedtuple(names, vals, string(k), v)
    end
    return names, vals
end

function flatten_namedtuple(names, value :: Array{Float64}, k :: String, v)
    if isa(v, Number)
        name = k
        push!(value, v)
        push!(names, name)
    elseif isa(v, Array)
        for i = eachindex(v)
            if isa(v[i], Number)
                name = string(Turing.Utilities.ind2sub(size(v), i))
                name = replace(name, "(" => "[");
                name = replace(name, ",)" => "]");
                name = replace(name, ")" => "]");
                name = k * name
                isa(v[i], Nothing) && println(v, i, v[i])
                push!(value, Float64(v[i]))
                push!(names, name)
            elseif isa(v[i], Array)
                name = k * string(ind2sub(size(v), i))
                flatten(names, value, name, v[i])
            else
                error("Unknown var type: typeof($v[i])=$(typeof(v[i]))")
            end
        end
    else
        error("Unknown var type: typeof($v)=$(typeof(v))")
    end
    return
end

# Default Chains constructor.
function Chains(
    ::AbstractRNG,
    ::ModelType,
    spl::Sampler,
    N::Integer,
    ts::Vector{T};
    discard_adapt::Bool = true,
    kwargs...
) where {ModelType<:Sampleable, T<:AbstractTransition}
    # Check if we have adaptation samples.
    if discard_adapt && :n_adapts in fieldnames(typeof(spl.alg))
        ts = ts[(spl.alg.n_adapts+1):end]
    end

    # Convert transitions to array format.
    # Also retrieve the variable names.
    nms, vals = _params_to_array(ts)

    # Get the extra field names from the sampler state type.
    # This handles things like :lp or :weight.
    extra_params = additional_parameters(T)

    # Get the values of the extra parameters.
    extra_values = vcat(map(t -> [getproperty(t, p) for p in extra_params], ts))

    # Extract names & construct param array.
    nms = string.(vcat(nms..., string.(extra_params)...))
    parray = vcat([hcat(vals[i]..., extra_values[i]...) for i in 1:length(ts)]...)

    # If the state field has final_logevidence, grab that.
    le = :final_logevidence in fieldnames(typeof(spl.state)) ?
        getproperty(spl.state, :final_logevidence) :
        missing

    # Chain construction.
    return Chains(
        parray,
        string.(nms),
        INTERNAL_VARS,
        evidence = le
    )
end

##############
# Utilities  #
##############

# VarInfo to Sample
Sample(vi::VarInfo) = Sample(0.0, todict(vi))
function todict(vi::VarInfo)
    value = todict(vi.metadata, vi)
    value[:lp] = getlogp(vi)
    return value
end
function todict(md::Metadata, vi::VarInfo)
    value = Dict{Symbol, Any}() # value is named here because of Sample has a field called value
    for vn in keys(md.idcs)
        value[Symbol(vn)] = vi[vn]
    end
    return value
end
function todict(metadata::NamedTuple{names}, vi::VarInfo) where {names}
    length(names) === 0 && return Dict{Symbol, Any}()
    f = names[1]
    mdf = getfield(metadata, f)
    return merge(todict(mdf, vi), todict(_tail(metadata), vi))
end

# VarInfo, combined with spl.info, to Sample
function Sample(vi::AbstractVarInfo, spl::Sampler)
    s = Sample(vi)
    if haskey(spl.info, :adaptor)
        s.value[:lf_eps] = AHMC.getϵ(spl.info[:adaptor])
    end
    if haskey(spl.info, :eval_num)
        s.value[:eval_num] = spl.info[:eval_num]
    end
    return s
end

getspace(spl::Sampler) = getspace(typeof(spl))
getspace(::Type{<:Sampler{Talg}}) where {Talg} = getspace(Talg)

end # module
