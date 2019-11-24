###
### Particle Filtering and Particle MCMC Samplers.
###

#######################
# Particle Transition #
#######################

"""
    ParticleTransition{T, F<:AbstractFloat} <: AbstractTransition

Fields:
- `θ`: The parameters for any given sample.
- `lp`: The log pdf for the sample's parameters.
- `le`: The log evidence retrieved from the particle.
- `weight`: The weight of the particle the sample was retrieved from.
"""
struct ParticleTransition{T, F<:AbstractFloat} <: AbstractTransition
    θ::T
    lp::F
    le::F
    weight::F
end

transition_type(spl::Sampler{<:ParticleInference}) = ParticleTransition

function additional_parameters(::Type{<:ParticleTransition})
    return [:lp,:le, :weight]
end

####
#### Generic Sequential Monte Carlo sampler.
####

"""
    SMC()

Sequential Monte Carlo sampler.

Note that this method is particle-based, and arrays of variables
must be stored in a [`TArray`](@ref) object.

Fields: 
- `resampler`: A function used to sample particles from the particle container. 
  Defaults to `resample_systematic`.
- `resampler_threshold`: The threshold at which resampling terminates -- defaults to 0.5. If 
  the `ess` <= `resampler_threshold` * `n_particles`, the resampling step is completed.

  Usage:

```julia
SMC()
```
"""
struct SMC{space, RT<:AbstractFloat} <: ParticleInference
    resampler             ::  Function
    resampler_threshold   ::  RT
end

function SMC(
    resampler::Function,
    resampler_threshold::RT,
    space::Tuple
) where {RT<:AbstractFloat}
    return SMC{space, RT}(resampler, resampler_threshold)
end
SMC() = SMC(resample_systematic, 0.5, ())
SMC(::Tuple{}) = SMC()
function SMC(space::Symbol...)
    SMC(resample_systematic, 0.5, space)
end

mutable struct SMCState{V<:VarInfo, F<:AbstractFloat} <: AbstractSamplerState
    vi                   ::   V
    # The logevidence after aggregating all samples together.
    average_logevidence  ::   F
    particles            ::   ParticleContainer
end

function SMCState(
    model::M, 
) where {
    M<:Model
}
    vi = VarInfo(model)
    particles = ParticleContainer{Trace}(model)

    return SMCState(vi, 0.0, particles)
end

function Sampler(alg::T, model::Model, s::Selector) where T<:SMC
    dict = Dict{Symbol, Any}()
    state = SMCState(model)
    return Sampler(alg, dict, s, state)
end

function sample_init!(
    ::AbstractRNG, 
    model::Turing.Model,
    spl::Sampler{<:SMC},
    N::Integer;
    kwargs...
)
    # Set the parameters to a starting value.
    initialize_parameters!(spl; kwargs...)

    # Update the particle container now that the sampler type
    # is defined.
    spl.state.particles = ParticleContainer{Trace{typeof(spl),
        typeof(spl.state.vi), typeof(model)}}(model)

    spl.state.vi.num_produce = 0;  # Reset num_produce before new sweep\.
    set_retained_vns_del_by_spl!(spl.state.vi, spl)
    resetlogp!(spl.state.vi)

    push!(spl.state.particles, N, spl, empty!(spl.state.vi))

    while consume(spl.state.particles) != Val{:done}
        ess = effectiveSampleSize(spl.state.particles)
        if ess <= spl.alg.resampler_threshold * length(spl.state.particles)
            resample!(spl.state.particles, spl.alg.resampler)
        end
    end
end

function step!(
    ::AbstractRNG, 
    model::Turing.Model,
    spl::Sampler{<:SMC},
    ::Integer;
    iteration=-1,
    kwargs...
)
    # Check that we received a real iteration number.
    @assert iteration >= 1 "step! needs to be called with an 'iteration' keyword argument."

    ## Grab the weights.
    Ws = weights(spl.state.particles)

    # update the master vi.
    particle = spl.state.particles.vals[iteration]
    params = tonamedtuple(particle.vi)
    lp = getlogp(particle.vi)

    return ParticleTransition(params, lp, spl.state.particles.logE, Ws[iteration])
end

####
#### Particle Gibbs sampler.
####

"""
    PG(n_particles::Int)

Particle Gibbs sampler.

Note that this method is particle-based, and arrays of variables
must be stored in a [`TArray`](@ref) object.

Usage:

```julia
PG(100, 100)
```
"""
struct PG{space} <: ParticleInference
  n_particles           ::    Int         # number of particles used
  resampler             ::    Function    # function to resample
end
function PG(n_particles::Int, resampler::Function, space::Tuple)
    return PG{space}(n_particles, resampler)
end
PG(n1::Int, ::Tuple{}) = PG(n1)
function PG(n1::Int, space::Symbol...)
    PG(n1, resample_systematic, space)
end

mutable struct PGState{V<:VarInfo, F<:AbstractFloat} <: AbstractSamplerState
    vi                   ::   V
    # The logevidence after aggregating all samples together.
    average_logevidence  ::   F
end

function PGState(model::M) where {M<:Model}
    vi = VarInfo(model)
    return PGState(vi, 0.0)
end

const CSMC = PG # type alias of PG as Conditional SMC

"""
    Sampler(alg::PG, model::Model, s::Selector)

Return a `Sampler` object for the PG algorithm.
"""
function Sampler(alg::T, model::Model, s::Selector) where T<:PG
    info = Dict{Symbol, Any}()
    state = PGState(model)
    return Sampler(alg, info, s, state)
end

function step!(
    ::AbstractRNG,
    model::Turing.Model,
    spl::Sampler{<:PG},
    ::Integer;
    kwargs...
)
    particles = ParticleContainer{Trace{typeof(spl), typeof(spl.state.vi), typeof(model)}}(model)

    spl.state.vi.num_produce = 0;  # Reset num_produce before new sweep.
    ref_particle = isempty(spl.state.vi) ?
              nothing :
              forkr(Trace(model, spl, spl.state.vi))

    set_retained_vns_del_by_spl!(spl.state.vi, spl)
    resetlogp!(spl.state.vi)

    if ref_particle === nothing
        push!(particles, spl.alg.n_particles, spl, spl.state.vi)
    else
        push!(particles, spl.alg.n_particles-1, spl, spl.state.vi)
        push!(particles, ref_particle)
    end

    while consume(particles) != Val{:done}
        resample!(particles, spl.alg.resampler, ref_particle)
    end

    ## pick a particle to be retained.
    Ws = weights(particles)
    indx = randcat(Ws)

    # Extract the VarInfo from the retained particle.
    params = tonamedtuple(spl.state.vi)
    spl.state.vi = particles[indx].vi
    lp = getlogp(spl.state.vi)

    # update the master vi.
    return ParticleTransition(params, lp, particles.logE, 1.0)
end

function sample_end!(
    ::AbstractRNG,
    ::Model,
    spl::Sampler{<:ParticleInference},
    N::Integer,
    ts::Vector{ParticleTransition};
    kwargs...
)
    # Set the default for resuming the sampler.
    resume_from = get(kwargs, :resume_from, nothing)

    # Exponentiate the average log evidence.
    # loge = exp(mean([t.le for t in ts]))
    loge = mean(t.le for t in ts)

    # If we already had a chain, grab the logevidence.
    if resume_from !== nothing   # concat samples
        @assert resume_from isa Chains "resume_from needs to be a Chains object."
        # pushfirst!(samples, resume_from.info[:samples]...)
        pre_loge = resume_from.logevidence
        # Calculate new log-evidence
        pre_n = length(resume_from)
        loge = (pre_loge * pre_n + loge * N) / (pre_n + N)
    end

    # Store the logevidence.
    spl.state.average_logevidence = loge
end

function assume(spl::Sampler{<:Union{PG,SMC}}, dist::Distribution, vn::VarName, ::VarInfo)
    vi = current_trace().vi
    if isempty(getspace(spl.alg)) || vn.sym in getspace(spl.alg)
        if ~haskey(vi, vn)
            r = rand(dist)
            push!(vi, vn, r, dist, spl)
        elseif is_flagged(vi, vn, "del")
            unset_flag!(vi, vn, "del")
            r = rand(dist)
            vi[vn] = vectorize(dist, r)
            setgid!(vi, spl.selector, vn)
            setorder!(vi, vn, vi.num_produce)
        else
            updategid!(vi, vn, spl)
            r = vi[vn]
        end
    else # vn belongs to other sampler <=> conditionning on vn
        if haskey(vi, vn)
            r = vi[vn]
        else
            r = rand(dist)
            push!(vi, vn, r, dist, Selector(:invalid))
        end
        acclogp!(vi, logpdf_with_trans(dist, r, istrans(vi, vn)))
    end
    return r, zero(Real)
end

function assume(
    spl::Sampler{<:Union{PG,SMC}},
    ::Vector{<:Distribution},
    ::VarName,
    ::Any,
    ::VarInfo
)
    error("[Turing] $(alg_str(spl)) doesn't support vectorizing assume statement")
end

function observe(spl::Sampler{<:Union{PG,SMC}}, dist::Distribution, value, vi)
    produce(logpdf(dist, value))
    return zero(Real)
end

function observe(spl::Sampler{<:Union{PG,SMC}}, ::Vector{<:Distribution}, ::Any, ::VarInfo)
    error("[Turing] $(alg_str(spl)) doesn't support vectorizing observe statement")
end

####
#### Resampling schemes for particle filters
####

# Some references
#  - http://arxiv.org/pdf/1301.4019.pdf
#  - http://people.isy.liu.se/rt/schon/Publications/HolSG2006.pdf
# Code adapted from: http://uk.mathworks.com/matlabcentral/fileexchange/24968-resampling-methods-for-particle-filtering

# Default resampling scheme
function resample(w::AbstractVector{<:Real}, num_particles::Integer=length(w))
    return resample_systematic(w, num_particles)
end

# More stable, faster version of rand(Categorical)
function randcat(p::AbstractVector{T}) where T<:Real
    r, s = rand(T), 1
    for j in eachindex(p)
        r -= p[j]
        if r <= zero(T)
            s = j
            break
        end
    end
    return s
end

function resample_multinomial(w::AbstractVector{<:Real}, num_particles::Integer)
    return rand(Distributions.sampler(Categorical(w)), num_particles)
end

function resample_residual(w::AbstractVector{<:Real}, num_particles::Integer)

    M = length(w)

    # "Repetition counts" (plus the random part, later on):
    Ns = floor.(length(w) .* w)

    # The "remainder" or "residual" count:
    R = Int(sum(Ns))

    # The number of particles which will be drawn stocastically:
    M_rdn = num_particles - R

    # The modified weights:
    Ws = (M .* w - floor.(M .* w)) / M_rdn

    # Draw the deterministic part:
    indx1, i = Array{Int}(undef, R), 1
    for j in 1:M
        for k in 1:Ns[j]
            indx1[i] = j
            i += 1
        end
    end

    # And now draw the stocastic (Multinomial) part:
    return append!(indx1, rand(Distributions.sampler(Categorical(w)), M_rdn))
end

"""
    resample_stratified(weights, n)

Return a vector of `n` samples `x₁`, ..., `xₙ` from the numbers 1, ..., `length(weights)`,
generated by stratified resampling.

In stratified resampling `n` ordered random numbers `u₁`, ..., `uₙ` are generated, where
``uₖ \\sim U[(k - 1) / n, k / n)``. Based on these numbers the samples `x₁`, ..., `xₙ`
are selected according to the multinomial distribution defined by the normalized `weights`,
i.e., `xᵢ = j` if and only if
``uᵢ \\in [\\sum_{s=1}^{j-1} weights_{s}, \\sum_{s=1}^{j} weights_{s})``.
"""
function resample_stratified(weights::AbstractVector{<:Real}, n::Integer)
    # check input
    m = length(weights)
    m > 0 || error("weight vector is empty")

    # pre-calculations
    @inbounds v = n * weights[1]

    # generate all samples
    samples = Array{Int}(undef, n)
    sample = 1
    @inbounds for i in 1:n
        # sample next `u` (scaled by `n`)
        u = oftype(v, i - 1 + rand())

        # as long as we have not found the next sample
        while v < u
            # increase and check the sample
            sample += 1
            sample > m &&
                error("sample could not be selected (are the weights normalized?)")

            # update the cumulative sum of weights (scaled by `n`)
            v += n * weights[sample]
        end

        # save the next sample
        samples[i] = sample
    end

    return samples
end

"""
    resample_systematic(weights, n)

Return a vector of `n` samples `x₁`, ..., `xₙ` from the numbers 1, ..., `length(weights)`,
generated by systematic resampling.

In systematic resampling a random number ``u \\sim U[0, 1)`` is used to generate `n` ordered
numbers `u₁`, ..., `uₙ` where ``uₖ = (u + k − 1) / n``. Based on these numbers the samples
`x₁`, ..., `xₙ` are selected according to the multinomial distribution defined by the
normalized `weights`, i.e., `xᵢ = j` if and only if
``uᵢ \\in [\\sum_{s=1}^{j-1} weights_{s}, \\sum_{s=1}^{j} weights_{s})``.
"""
function resample_systematic(weights::AbstractVector{<:Real}, n::Integer)
    # check input
    m = length(weights)
    m > 0 || error("weight vector is empty")

    # pre-calculations
    @inbounds v = n * weights[1]
    u = oftype(v, rand())

    # find all samples
    samples = Array{Int}(undef, n)
    sample = 1
    @inbounds for i in 1:n
        # as long as we have not found the next sample
        while v < u
            # increase and check the sample
            sample += 1
            sample > m &&
                error("sample could not be selected (are the weights normalized?)")

            # update the cumulative sum of weights (scaled by `n`)
            v += n * weights[sample]
        end

        # save the next sample
        samples[i] = sample

        # update `u`
        u += one(u)
    end

    return samples
end
