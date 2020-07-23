# TODO: fix convention to refer to MCMC steps within a transition, and independent AISTransition transitions ie particles...

## A. Sampler

# A.1. algorithm

# simple version of AIS (not fully general): 
# - sequence of num_steps distributions defined by tempering
# - list of num_steps proposals Markov kernels
# - MCMC acceptance ratios enforce invariance of kernels wrt intermediate distributions

struct AIS <: InferenceAlgorithm 
    "array of `num_steps` AdvancedMH proposals"
    proposals :: Array{<:Proposal{P}}
    "array of `num_steps` inverse temperatures"
    schedule :: Array{<:Integer}
end

# A.2. state: same as for vanilla IS

mutable struct AISState{V<:VarInfo, F<:AbstractFloat} <: AbstractSamplerState
    vi                 ::  V # reset for every step ie particle
    "log of the average of the particle weights: estimator of the log evidence"
    final_logevidence  ::  F
end

AISState(model::Model) = AISState(VarInfo(model), 0.0)

# A.3. Sampler constructor: same as for vanilla IS

function Sampler(alg::AIS, model::Model, s::Selector)
    @assert length(alg.schedule) == length(alg.proposals)
    info = Dict{Symbol, Any}()
    state = AISState(model)
    return Sampler(alg, info, s, state)
end


## B. Implement AbstractMCMC

# each time we call step!, we create a new particle as a transition like in is.jl

# B.1. new transition type AISTransition, with an additional attribute accum_logweight

struct AISTransition{T, F<:AbstractFloat}
    "parameter"
    θ  :: T
    "logjoint evaluated at θ"
    lp :: F
    "logarithm of the particle's AIS weight - accumulated during annealing run"
    accum_logweight :: F
end

function AISTransition(spl::Sampler, accum_logweight::F<:AbstractFloat, nt::NamedTuple=NamedTuple())
    theta = merge(tonamedtuple(spl.state.vi), nt)
    lp = getlogp(spl.state.vi)
    return AISTransition{typeof(theta), typeof(lp)}(theta, lp, accum_logweight)
end

# idk what this function is for
function additional_parameters(::Type{<:AISTransition})
    return [:lp, :accum_logweight]
end


# B.2. sample_init! function

function AbstractMCMC.sample_init!(
    rng::AbstractRNG,
    model::Model,
    spl::Sampler{<:AIS},
    N::Integer;
    verbose::Bool=true,
    resume_from=nothing,
    kwargs...
)
    log_prior = gen_log_prior(spl.state.vi, model)
    log_joint = gen_log_joint(spl.state.vi, model)
    for i in 1:length(spl.alg.proposals)
        beta = spl.alg.schedule[i]
        log_unnorm_tempered = gen_log_unnorm_tempered(log_prior, log_joint, beta)
        densitymodel = AdvancedMH.DensityModel(log_unnorm_tempered)
        
        proposal = spl.alg.proposals[i]
        mh_sampler = AMH.MetropolisHastings(proposal) # maybe use RWMH(d) with d the associated distribution
end

# B.3. step function 


function AbstractMCMC.step!(
    rng::AbstractRNG,
    model::Model,
    spl::Sampler{<:AIS},
    ::Integer,
    transition;
    kwargs...
)
    empty!(spl.state.vi) # particles are independent: previous step doesn't matter
    
    # TODO: sample from prior and initialize accum_logweight as minus log the prior evaluated at the sample

    # for every intermediate distribution:
    # - we have the associated mh_sampler and densitymodel
    # - we have access to the previous sample (with AMH.Transition(vals, getlogp(spl.state.vi))?)
    # - do pretty much what is done there https://github.com/TuringLang/AdvancedMH.jl/blob/master/src/mh-core.jl#L195 AND update accum_logweight

    # do a last accum_logweight update
end

# B.4. sample_end! combines the individual accum_logweights to obtain final_logevidence, as in vanilla IS 

function AbstractMCMC.sample_end!(
    ::AbstractRNG,
    ::Model,
    spl::Sampler{<:IS},
    N::Integer,
    ts::Vector;
    kwargs...
)
    # use AISTransition accum_logweight attribute
    spl.state.final_logevidence = logsumexp(map(x->x.accum_logweight, ts)) - log(N)
end


## C. overload assume and observe: same as for MH, so that gen_log_joint and gen_log_prior work

function DynamicPPL.assume(
    rng,
    spl::Sampler{<:MH},
    dist::Distribution,
    vn::VarName,
    vi,
)
    updategid!(vi, vn, spl)
    r = vi[vn]
    return r, logpdf_with_trans(dist, r, istrans(vi, vn))
end

function DynamicPPL.dot_assume(
    rng,
    spl::Sampler{<:MH},
    dist::MultivariateDistribution,
    vn::VarName,
    var::AbstractMatrix,
    vi,
)
    @assert dim(dist) == size(var, 1)
    getvn = i -> VarName(vn, vn.indexing * "[:,$i]")
    vns = getvn.(1:size(var, 2))
    updategid!.(Ref(vi), vns, Ref(spl))
    r = vi[vns]
    var .= r
    return var, sum(logpdf_with_trans(dist, r, istrans(vi, vns[1])))
end
function DynamicPPL.dot_assume(
    rng,
    spl::Sampler{<:MH},
    dists::Union{Distribution, AbstractArray{<:Distribution}},
    vn::VarName,
    var::AbstractArray,
    vi,
)
    getvn = ind -> VarName(vn, vn.indexing * "[" * join(Tuple(ind), ",") * "]")
    vns = getvn.(CartesianIndices(var))
    updategid!.(Ref(vi), vns, Ref(spl))
    r = reshape(vi[vec(vns)], size(var))
    var .= r
    return var, sum(logpdf_with_trans.(dists, r, istrans(vi, vns[1])))
end

function DynamicPPL.observe(
    spl::Sampler{<:MH},
    d::Distribution,
    value,
    vi,
)
    return DynamicPPL.observe(SampleFromPrior(), d, value, vi)
end

function DynamicPPL.dot_observe(
    spl::Sampler{<:MH},
    ds::Union{Distribution, AbstractArray{<:Distribution}},
    value::AbstractArray,
    vi,
)
    return DynamicPPL.dot_observe(SampleFromPrior(), ds, value, vi)
end

# D. helper functions


function gen_log_joint(v, model)
    function log_joint(z)::Float64
        z_old, lj_old = v[spl], getlogp(v)
        v[spl] = z
        model(v, spl)
        lj = getlogp(v)
        v[spl] = z_old
        setlogp!(v, lj_old)
        return lj
    end
    return log_joint
end

function gen_log_prior(v, model)
    function log_prior(z)::Float64
        z_old, lj_old = v[spl], getlogp(v)
        v[spl] = z
        model(v, SampleFromPrior(), PriorContext())
        lj = getlogp(v)
        v[spl] = z_old
        setlogp!(v, lj_old)
        return lj
    end
    return log_prior
end

function gen_log_unnorm_tempered(log_prior, log_joint, beta)
    function log_unnorm_tempered(z)
        return (1 - beta) * log_prior(z) + beta * log_joint(z)
    end
    return log_unnorm_tempered
end

