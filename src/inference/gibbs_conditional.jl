"""
    GibbsConditional(sym, conditional)

A "pseudo-sampler" to manually provide analytical Gibbs conditionals to `Gibbs`.
`GibbsConditional(:x, cond)` will sample the variable `x` according to the conditional `cond`, which
must therefore be a function from a `NamedTuple` of the conditioned variables to a `Distribution`.


The `NamedTuple` that is passed in contains all random variables from the model in an unspecified
order, taken from the [`VarInfo`](@ref) object over which the model is run.  Scalars and vectors are
stored as their respective types, but all as floats.  The tuple also contains the value of the
conditioned variable itself, which can be useful, but using it creates something that is not a Gibbs
sampler anymore (see
[here](https://github.com/TuringLang/Turing.jl/pull/1275#discussion_r434240387)).

# Examples

```julia
α_0 = 2.0
θ_0 = inv(3.0)

x = [1.5, 2.0]

function gdemo_statistics(x)
    # The conditionals and posterior can be formulated in terms of the following statistics:
    N = length(x) # number of samples
    x_bar = mean(x) # sample mean
    s2 = var(x; mean=x_bar, corrected=false) # sample variance
    return N, x_bar, s2
end

function gdemo_cond_m(c)
    N, x_bar, s2 = gdemo_statistics(x)
    m_n = N * x_bar / (N + 1)
    λ_n = c.λ * (N + 1)
    σ_n = sqrt(1 / λ_n)
    return Normal(m_n, σ_n)
end

function gdemo_cond_λ(c)
    N, x_bar, s2 = gdemo_statistics(x)
    α_n = α_0 + (N - 1) / 2 + 1
    β_n = s2 * N / 2 + c.m^2 / 2 + inv(θ_0)
    return Gamma(α_n, inv(β_n))
end

@model gdemo(x) = begin
    λ ~ Gamma(α_0, θ_0)
    m ~ Normal(0, √(1 / λ))
    x .~ Normal(m, √(1 / λ))
end

m = gdemo(x)

sample(m, Gibbs(GibbsConditional(:λ, gdemo_cond_λ), GibbsConditional(:m, gdemo_cond_m)), 10)
```
"""
struct GibbsConditional{S, C}
    conditional::C

    function GibbsConditional(sym::Symbol, conditional::C) where {C}
        return new{sym, C}(conditional)
    end
end

DynamicPPL.getspace(::GibbsConditional{S}) where {S} = (S,)
DynamicPPL.alg_str(::GibbsConditional) = "GibbsConditional"
isgibbscomponent(::GibbsConditional) = true


function Sampler(
    alg::GibbsConditional,
    model::Model,
    s::Selector=Selector()
)
    return Sampler(alg, Dict{Symbol, Any}(), s, SamplerState(VarInfo(model)))
end


function AbstractMCMC.step!(
    rng::AbstractRNG,
    model::Model,
    spl::Sampler{<:GibbsConditional{S}},
    N::Integer,
    transition;
    kwargs...
) where {S}
    if spl.selector.rerun # Recompute joint in logp
        model(spl.state.vi)
    end

    condvals = conditioned(tonamedtuple(spl.state.vi))
    conddist = spl.alg.conditional(condvals)
    updated = rand(rng, conddist)
    spl.state.vi[VarName(S)] = [updated;]  # setindex allows only vectors in this case...
    
    return transition
end


"""
    conditioned(θ::NamedTuple)

Extract a `NamedTuple` of the values in `θ`; i.e., all names of `θ`, mapping to their respective
values.

`θ` is assumed to come from `tonamedtuple(vi)`, which returns a `NamedTuple` of the form

```julia
t = (m = ([0.234, -1.23], ["m[1]", "m[2]"]), λ = ([1.233], ["λ"])
```

and this function implements the cleanup of indexing. `conditioned(t)` will therefore return

```julia
(λ = 1.233, m = [0.234, -1.23])
```
"""
@generated function conditioned(θ::NamedTuple{names}) where {names}
    condvals = [:($n = extractparam(θ.$n)) for n in names]
    return Expr(:tuple, condvals...)
end


"""Takes care of removing the `tonamedtuple` indexing form."""
extractparam(p::Tuple{Vector{<:Array{<:Real}}, Vector{String}}) = foldl(vcat, p[1])
function extractparam(p::Tuple{Vector{<:Real}, Vector{String}})
    values, strings = p
    if length(values) == length(strings) == 1 && !occursin(r".\[.+\]$", strings[1])
        # if m ~ MVNormal(1, 1), we could have have ([1], ["m[1]"])!
        return values[1]
    else
        return values
    end
end
