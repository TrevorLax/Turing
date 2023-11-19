# Basically like a `DynamicPPL.FixedContext` but
# 1. Hijacks the tilde pipeline to fix variables.
# 2. Computes the log-probability of the fixed variables.
struct GibbsContext{Values,Ctx<:DynamicPPL.AbstractContext} <: DynamicPPL.AbstractContext
    values::Values
    context::Ctx
end

Gibbscontext(values) = GibbsContext(values, DynamicPPL.DefaultContext())

DynamicPPL.NodeTrait(::GibbsContext) = DynamicPPL.IsParent()
DynamicPPL.childcontext(context::GibbsContext) = context.context
DynamicPPL.setchildcontext(context::GibbsContext, childcontext) = GibbsContext(context.values, childcontext)

# has and get
has_conditioned_gibbs(context::GibbsContext, vn::VarName) = DynamicPPL.hasvalue(context.values, vn)
function has_conditioned_gibbs(context::GibbsContext, vns::AbstractArray{<:VarName})
    return all(Base.Fix1(has_conditioned_gibbs, context), vns)
end

get_conditioned_gibbs(context::GibbsContext, vn::VarName) = DynamicPPL.getvalue(context.values, vn)
function get_conditioned_gibbs(context::GibbsContext, vns::AbstractArray{<:VarName})
    return map(Base.Fix1(get_conditioned_gibbs, context), vns)
end

# Tilde pipeline
function DynamicPPL.tilde_assume(context::GibbsContext, right, vn, vi)
    # Short-circuits the tilde assume if `vn` is present in `context`.
    if has_conditioned_gibbs(context, vn)
        value = get_conditioned_gibbs(context, vn)
        return value, logpdf(right, value), vi
    end

    # Otherwise, falls back to the default behavior.
    return DynamicPPL.tilde_assume(DynamicPPL.childcontext(context), right, vn, vi)
end

function DynamicPPL.tilde_assume(rng::Random.AbstractRNG, context::GibbsContext, sampler, right, vn, vi)
    # Short-circuits the tilde assume if `vn` is present in `context`.
    if has_conditioned_gibbs(context, vn)
        value = get_conditioned_gibbs(context, vn)
        return value, logpdf(right, value), vi
    end

    # Otherwise, falls back to the default behavior.
    return DynamicPPL.tilde_assume(rng, DynamicPPL.childcontext(context), sampler, right, vn, vi)
end

function DynamicPPL.dot_tilde_assume(context::GibbsContext, right, left, vns, vi)
    # Short-circuits the tilde assume if `vn` is present in `context`.
    # FIXME: This probably won't work as is.
    @info "dot_tilde_assume" vns value
    if has_conditioned_gibbs(context, vns)
        value = get_conditioned_gibbs(context, vns)
        return value, sum(logpdf.(right, value)), vi
    end

    # Otherwise, falls back to the default behavior.
    return DynamicPPL.dot_tilde_assume(DynamicPPL.childcontext(context), right, left, vns, vi)
end

function DynamicPPL.dot_tilde_assume(
    rng::Random.AbstractRNG, context::GibbsContext, sampler, right, left, vns, vi
)
    # Short-circuits the tilde assume if `vn` is present in `context`.
    if has_conditioned_gibbs(context, vns)
        values = get_conditioned_gibbs(context, vns)
        return values, sum(logpdf.(right, values)), vi
    end

    # Otherwise, falls back to the default behavior.
    return DynamicPPL.dot_tilde_assume(rng, DynamicPPL.childcontext(context), sampler, right, left, vns, vi)
end


preferred_value_type(::AbstractVarInfo) = OrderedDict
preferred_value_type(::SimpleVarInfo{<:NamedTuple}) = NamedTuple
function preferred_value_type(varinfo::DynamicPPL.TypedVarInfo)
    # We can only do this in the scenario where all the varnames are `Setfield.IdentityLens`.
    namedtuple_compatible = all(varinfo.metadata) do md
        eltype(md.vns) <: VarName{<:Any,DynamicPPL.Setfield.IdentityLens}
    end
    return namedtuple_compatible ? NamedTuple : OrderedDict
end

# No-op if no values are provided.
condition_gibbs(context::DynamicPPL.AbstractContext) = context
# For `NamedTuple` and `AbstractDict` we just construct the context.
function condition_gibbs(context::DynamicPPL.AbstractContext, values::Union{NamedTuple,AbstractDict})
    return GibbsContext(values, context)
end
# If we get more than one argument, we just recurse.
function condition_gibbs(context::DynamicPPL.AbstractContext, value, values...)
    return condition_gibbs(
        condition_gibbs(context, value),
        values...
    )
end
# For `AbstractVarInfo` we just extract the values.
function condition_gibbs(context::DynamicPPL.AbstractContext, varinfo::AbstractVarInfo)
    # TODO: Determine when it's okay to use `NamedTuple` and use that instead.
    return condition_gibbs(context, DynamicPPL.values_as(varinfo, preferred_value_type(varinfo)))
end
# Allow calling this on a `Model` directly.
function condition_gibbs(model::Model, values...)
    return DynamicPPL.contextualize(model, condition_gibbs(model.context, values...))
end


"""
    make_conditional_model(model, varinfo, varinfos)

Construct a conditional model from `model` conditioned `varinfos`, excluding `varinfo` if present.

# Examples
```julia-repl
julia> model = DynamicPPL.TestUtils.demo_assume_dot_observe();

julia> # A separate varinfo for each variable in `model`.
       varinfos = (DynamicPPL.SimpleVarInfo(s=1.0), DynamicPPL.SimpleVarInfo(m=10.0));

julia> # The varinfo we want to NOT condition on.
       target_varinfo = first(varinfos);

julia> # Results in a model with only `m` conditioned.
       conditioned_model = Turing.Inference.make_conditional(model, target_varinfo, varinfos);

julia> result = conditioned_model();

julia> result.m == 10.0  # we conditioned on varinfo with `m = 10.0`
true

julia> result.s != 1.0  # we did NOT want to condition on varinfo with `s = 1.0`
true
```
"""
function make_conditional(model::Model, target_varinfo::AbstractVarInfo, varinfos)
    # TODO: Check if this is known at compile-time if `varinfos isa Tuple`.
    return condition_gibbs(
        model,
        filter(Base.Fix1(!==, target_varinfo), varinfos)...
    )
end

wrap_algorithm_maybe(x) = x
wrap_algorithm_maybe(x::InferenceAlgorithm) = Sampler(x)

struct GibbsV2{V,A} <: InferenceAlgorithm
    varnames::V
    samplers::A
end

# NamedTuple
GibbsV2(; algs...) = GibbsV2(NamedTuple(algs))
function GibbsV2(algs::NamedTuple)
    return GibbsV2(
        map(s -> VarName{s}(), keys(algs)),
        map(wrap_algorithm_maybe, values(algs)),
    )
end

# AbstractDict
function GibbsV2(algs::AbstractDict)
    return GibbsV2(keys(algs), map(wrap_algorithm_maybe, values(algs)))
end
function GibbsV2(algs::Pair...)
    return GibbsV2(map(first, algs), map(wrap_algorithm_maybe, map(last, algs)))
end

struct GibbsV2State{V<:AbstractVarInfo,S}
    vi::V
    states::S
end

_maybevec(x) = vec(x)  # assume it's iterable
_maybevec(x::Tuple) = [x...]
_maybevec(x::VarName) = [x]

function DynamicPPL.initialstep(
    rng::Random.AbstractRNG,
    model::Model,
    spl::Sampler{<:GibbsV2},
    vi_base::AbstractVarInfo;
    kwargs...,
)
    alg = spl.alg
    varnames = alg.varnames
    samplers = alg.samplers

    # 1. Run the model once to get the varnames present + initial values to condition on.
    vi_base = DynamicPPL.VarInfo(model)
    varinfos = map(Base.Fix1(DynamicPPL.subset, vi_base) ∘ _maybevec, varnames)

    # 2. Construct a varinfo for every vn + sampler combo.
    states_and_varinfos = map(samplers, varinfos) do sampler_local, varinfo_local
        # Construct the conditional model.
        model_local = make_conditional(model, varinfo_local, varinfos)

        # Take initial step.
        new_state_local = last(AbstractMCMC.step(rng, model_local, sampler_local; kwargs...))

        # Return the new state and the invlinked `varinfo`.
        vi_local_state = varinfo(new_state_local)
        vi_local_state_linked = if DynamicPPL.istrans(vi_local_state)
            DynamicPPL.invlink(vi_local_state, sampler_local, model_local)
        else
            vi_local_state
        end
        return (new_state_local, vi_local_state_linked)
    end

    states = map(first, states_and_varinfos)
    varinfos = map(last, states_and_varinfos)

    # Update the base varinfo from the first varinfo and replace it.
    varinfos_new = DynamicPPL.setindex!!(varinfos, vi_base, 1)
    # Merge the updated initial varinfo with the rest of the varinfos + update the logp.
    vi = DynamicPPL.setlogp!!(
        reduce(merge, varinfos_new),
        DynamicPPL.getlogp(last(varinfos)),
    )

    return Transition(model, vi), GibbsV2State(vi, states)
end

function AbstractMCMC.step(
    rng::Random.AbstractRNG,
    model::Model,
    spl::Sampler{<:GibbsV2},
    state::GibbsV2State;
    kwargs...,
)
    alg = spl.alg
    samplers = alg.samplers
    states = state.states
    varinfos = map(varinfo, state.states)
    @assert length(samplers) == length(state.states)

    # TODO: move this into a recursive function so we can unroll when reasonable?
    for index = 1:length(samplers)
        # Take the inner step.
        new_state_local, new_varinfo_local = gibbs_step_inner(
            rng,
            model,
            samplers,
            states,
            varinfos,
            index;
            kwargs...,
        )

        # Update the `states` and `varinfos`.
        states = Setfield.setindex(states, new_state_local, index)
        varinfos = Setfield.setindex(varinfos, new_varinfo_local, index)
    end

    # Combine the resulting varinfo objects.
    # The last varinfo holds the correctly computed logp.
    vi_base = state.vi

    # Update the base varinfo from the first varinfo and replace it.
    varinfos_new = DynamicPPL.setindex!!(
        varinfos,
        merge(vi_base, first(varinfos)),
        firstindex(varinfos),
    )
    # Merge the updated initial varinfo with the rest of the varinfos + update the logp.
    vi = DynamicPPL.setlogp!!(
        reduce(merge, varinfos_new),
        DynamicPPL.getlogp(last(varinfos)),
    )

    return Transition(model, vi), GibbsV2State(vi, states)
end

function make_rerun_sampler(model::DynamicPPL.Model, sampler::DynamicPPL.Sampler, sampler_previous::DynamicPPL.Sampler)
    selector = DynamicPPL.Selector(
        Symbol(typeof(sampler.alg)),
        gibbs_rerun(sampler_previous.alg, sampler.alg)
    )
    return DynamicPPL.Sampler(sampler.alg, model, selector)
end

function gibbs_step_inner(
    rng::Random.AbstractRNG,
    model::Model,
    samplers,
    states,
    varinfos,
    index;
    kwargs...,
)
    # Needs to do a a few things.
    sampler_local = samplers[index]
    state_local = states[index]
    varinfo_local = varinfos[index]

    # We need the previous sampler to determine whether we'll need to rerun.
    sampler_previous = samplers[index == 1 ? length(samplers) : index - 1]
    # 1. Create conditional model.
    # Construct the conditional model.
    # NOTE: Here it's crucial that all the `varinfos` are in the constrained space,
    # otherwise we're conditioning on values which are not in the support of the
    # distributions.
    model_local = make_conditional(model, varinfo_local, varinfos)

    # NOTE: We use `logjoint` instead of `evaluate!!` and capturing the resulting varinfo because
    # the resulting varinfo might be in un-transformed space even if `varinfo_local`
    # is in transformed space. This can occur if we hit `maybe_invlink_before_eval!!`.

    # Re-run the sampler if needed.
    if gibbs_rerun(sampler_local, sampler_previous)
        # Make the re-run sampler.
        # NOTE: Need to do this because some samplers might need some other quantity than the log-joint,
        # e.g. log-likelihood in the scenario of `ESS`.
        # TODO: Check if `sampler_rerun` should be replacing `sampler_local` or not.
        sampler_rerun = make_rerun_sampler(model_local, sampler_local, sampler_previous)
        varinfo_local = last(DynamicPPL.evaluate!!(
            model_local,
            varinfo_local,
            DynamicPPL.SamplingContext(rng, sampler_rerun)
        ))
    end
    # 2. Take step with local sampler.
    # Update the state we're about to use if need be.
    # If the sampler requires a linked varinfo, this should be done in `gibbs_state`.
    current_state_local = gibbs_state(
        model_local, sampler_local, state_local, varinfo_local
    )

    # Take a step.
    new_state_local = last(
        AbstractMCMC.step(
            rng,
            model_local,
            sampler_local,
            current_state_local;
            kwargs...,
        ),
    )

    # 3. Extract the new varinfo.
    # Return the resulting state and invlinked `varinfo`.
    varinfo_local_state = varinfo(new_state_local)
    varinfo_local_state_invlinked = if DynamicPPL.istrans(varinfo_local_state)
        DynamicPPL.invlink(varinfo_local_state, sampler_local, model_local)
    else
        varinfo_local_state
    end

    # TODO: alternatively, we can return `states_new, varinfos_new, index_new`
    return (new_state_local, varinfo_local_state_invlinked)
end
