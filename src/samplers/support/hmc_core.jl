# Ref: https://github.com/stan-dev/stan/blob/develop/src/stan/mcmc/hmc/hamiltonians/diag_e_metric.hpp

"""
    gen_grad_func(vi::VarInfo, sampler::Sampler, model)

Generate a function that takes a vector of reals `θ` and compute the logpdf and
gradient at `θ` for the model specified by `(vi, sampler, model)`.
"""
function gen_grad_func(vi::VarInfo, sampler::Sampler, model)
    return θ::AbstractVector{<:Real}->gradient(θ, vi, model, sampler)
end

"""
    gen_lj_func(vi::VarInfo, sampler::Sampler, model)

Generate a function that takes `θ` and returns logpdf at `θ` for the model specified by
`(vi, sampler, model)`.
"""
function gen_lj_func(vi::VarInfo, sampler::Sampler, model)
    return function(θ::AbstractVector{<:Real})
        vi[sampler] .= θ
        return runmodel!(model, vi, sampler).logp
    end
end

"""
  gen_rev_func(vi::VarInfo, sampler::Sampler)

Generate a function on `(θ, logp)` that sets the variables referenced by `sampler` to `θ`
and the current `vi.logp` to `logp`.
"""
function gen_rev_func(vi::VarInfo, sampler::Sampler)
    return function(θ::AbstractVector{<:Real}, logp::Real)
        vi[sampler] = θ
        setlogp!(vi, logp)
    end
end

"""
    gen_log_func(sampler::Sampler)

Generate a function that takes no argument and performs logging for the number of leapfrog
steps used in `sampler`.
"""
function gen_log_func(sampler::Sampler)
    return function()
        sampler.info[:lf_num] += 1
        sampler.info[:total_lf_num] += 1
    end
end

function sample_momentum(vi::VarInfo, sampler::Sampler)
    d = length(getranges(vi, sampler))
    stds = sampler.info[:wum][:stds]
    return _sample_momentum(d, stds)
end

_sample_momentum(d::Int, stds::Vector) = randn(d) ./ stds

function runmodel!(model::Function, vi::VarInfo, spl::Union{Nothing,Sampler}) 
    setlogp!(vi, zero(Real))
    if spl != nothing 
        spl.info[:total_eval_num] += 1 
    end
    Base.invokelatest(model, vi, spl)
    return vi
end

function leapfrog(
    θ::AbstractVector{<:Real},
    p::AbstractVector{<:Real},
    τ::Int,
    ϵ::Real,
    model::Function,
    vi::VarInfo,
    sampler::Sampler,
)
    lp_grad = gen_grad_func(vi, sampler, model)
    rev = gen_rev_func(vi, sampler)
    logger = gen_log_func(sampler)
    return _leapfrog(θ, p, τ, ϵ, lp_grad; rev_func=rev, log_func=logger)
end

function _leapfrog(
    θ::AbstractVector{<:Real},
    p::AbstractVector{<:Real},
    τ::Int,
    ϵ::Real,
    lp_grad_func::Function;
    rev_func=nothing,
    log_func=nothing,
)
    _, grad = lp_grad_func(θ)
    verifygrad(grad) || (return θ, p, 0)

    p, θ, τ_valid = deepcopy(p), deepcopy(θ), 0

    p .-= ϵ .* grad ./ 2
    for t in 1:τ

        log_func != nothing && log_func()

        θ .+= ϵ .* p
        logp, grad = lp_grad_func(θ)

        # If gradients explode, tidy up and return.
        if ~verifygrad(grad)
            θ .-= ϵ .* p
            rev_func != nothing && rev_func(θ, logp)
            break
        end

        p .-= ϵ .* grad
        τ_valid += 1
    end

    # Undo half a step in the momenta.
    p .+= ϵ .* grad ./ 2

    return θ, p, τ_valid
end

# Compute the Hamiltonian
function find_H(p::AbstractVector{<:Real}, model::Function, vi::VarInfo, sampler::Sampler)
    logpdf_func_float = gen_lj_func(vi, sampler, model)
    return _find_H(vi[sampler], p, logpdf_func_float, sampler.info[:wum][:stds])
end

function _find_H(
    θ::AbstractVector{<:Real},
    p::AbstractVector{<:Real},
    logpdf_func_float::Function,
    stds::AbstractVector{<:Real},
)
    return _find_H(θ, p, logpdf_func_float(θ), stds)
end

function _find_H(
    θ::AbstractVector{<:Real},
    p::AbstractVector{<:Real},
    logp::Real,
    stds::AbstractVector{<:Real},
)
    H = sum(abs2, p .* stds) / 2 - logp
    return isnan(H) ? Inf : H
end

# TODO: remove used Turing-wrapper functions

# Ref: https://github.com/stan-dev/stan/blob/develop/src/stan/mcmc/hmc/base_hmc.hpp
function find_good_eps(model::Function, vi::VarInfo, sampler::Sampler{T}) where T
    println("[Turing] looking for good initial eps...")
    ϵ = 0.1

    p = sample_momentum(vi, sampler)
    H0 = find_H(p, model, vi, sampler)

    θ = vi[sampler]
    θ_prime, p_prime, τ = leapfrog(θ, p, 1, ϵ, model, vi, sampler)
    h = τ == 0 ? Inf : find_H(p_prime, model, vi, sampler)

    delta_H = H0 - h
    direction = delta_H > log(0.8) ? 1 : -1

    iter_num = 1

    # Heuristically find optimal ϵ
    while (iter_num <= 12)

        p = sample_momentum(vi, sampler)
        H0 = find_H(p, model, vi, sampler)

        θ_prime, p_prime, τ = leapfrog(θ, p, 1, ϵ, model, vi, sampler)
        h = τ == 0 ? Inf : find_H(p_prime, model, vi, sampler)
        @debug "direction = $direction, h = $h"

        delta_H = H0 - h

        if ((direction == 1) && !(delta_H > log(0.8)))
            break
        elseif ((direction == -1) && !(delta_H < log(0.8)))
            break
        else
            ϵ = direction == 1 ? 2.0 * ϵ : 0.5 * ϵ
        end

        iter_num += 1
    end

    while h == Inf  # revert if the last change is too big
        ϵ = ϵ / 2               # safe is more important than large
        θ_prime, p_prime, τ = leapfrog(θ, p, 1, ϵ, model, vi, sampler)
        h = τ == 0 ? Inf : find_H(p_prime, model, vi, sampler)
    end
    println("\r[$T] found initial ϵ: ", ϵ)
    return ϵ
end

"""
    mh_accept(H::Real, H_new::Real)
    mh_accept(H::Real, H_new::Real, log_proposal_ratio::Real)

Peform MH accept criteria. Returns a boolean for whether or not accept and the 
acceptance ratio in log space.
"""
mh_accept(H::Real, H_new::Real) = log(rand()) + H_new < min(H_new, H), min(0, -(H_new - H))
function mh_accept(H::Real, H_new::Real, log_proposal_ratio::Real)
    return log(rand()) + H_new < H + log_proposal_ratio, min(0, -(H_new - H))
end
