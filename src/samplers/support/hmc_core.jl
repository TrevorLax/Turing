# Ref: https://github.com/stan-dev/stan/blob/develop/src/stan/mcmc/hmc/hamiltonians/diag_e_metric.hpp
global Δ_max = 1000

runmodel(model::Function, vi::VarInfo, spl::Union{Void,Sampler}) = begin
  dprintln(4, "run model...")
  setlogp!(vi, zero(Real))
  if spl != nothing spl.info[:total_eval_num] += 1 end
  # model(vi=vi, sampler=spl) # run model
  Base.invokelatest(model, vi, spl)
end

sample_momentum(vi::VarInfo, spl::Sampler) = begin
  dprintln(2, "sampling momentum...")
  randn(length(getranges(vi, spl))) ./ spl.info[:wum][:stds]
end

# Leapfrog step
# NOTE: leapfrog() doesn't change θ in place!
leapfrog(_θ::Union{Vector,SubArray}, p::Vector{Float64}, τ::Int, ϵ::Float64,
          model::Function, vi::VarInfo, spl::Sampler) = begin

  θ = realpart(_θ)
  if ADBACKEND == :forward_diff
    vi[spl] = θ
    grad = gradient(vi, model, spl)
  elseif ADBACKEND == :reverse_diff
    grad = gradient_r(θ, vi, model, spl)
  end
  verifygrad(grad) || (return θ, p, 0)

  τ_valid = 0
  for t in 1:τ
    # NOTE: we dont need copy here becase arr += another_arr
    #       doesn't change arr in-place
    p_old = p; θ_old = copy(θ); old_logp = getlogp(vi)

    p -= ϵ .* grad / 2
    θ += ϵ .* p  # full step for state
    spl.info[:lf_num] += 1
    spl.info[:total_lf_num] += 1  # record leapfrog num

    if ADBACKEND == :forward_diff
      vi[spl] = θ
      grad = gradient(vi, model, spl)
    elseif ADBACKEND == :reverse_diff
      grad = gradient_r(θ, vi, model, spl)
    end
    # verifygrad(grad) || (vi[spl] = θ_old; setlogp!(vi, old_logp); θ = θ_old; p = p_old; break)
    if ~verifygrad(grad)
      if ADBACKEND == :forward_diff
        vi[spl] = θ_old
      elseif ADBACKEND == :reverse_diff
        vi_spl = vi[spl]
        for i = 1:length(θ_old)
          if isa(vi_spl[i], ReverseDiff.TrackedReal)
            vi_spl[i].value = θ_old[i]
          else
            vi_spl[i] = θ_old[i]
          end
        end
      end
      setlogp!(vi, old_logp)
      θ = θ_old
      p = p_old
      break
    end

    p -= ϵ * grad / 2

    τ_valid += 1
  end

  θ, p, τ_valid
end

# Compute Hamiltonian
find_H(p::Vector, model::Function, vi::VarInfo, spl::Sampler) = begin
  # NOTE: getlogp(vi) = 0 means the current vals[end] hasn't been used at all.
  #       This can be a result of link/invlink (where expand! is used)
  if getlogp(vi) == 0 vi = runmodel(model, vi, spl) end

  p_orig = p .* spl.info[:wum][:stds]

  H = dot(p_orig, p_orig) / 2 + realpart(-getlogp(vi))
  if isnan(H) H = Inf else H end

  H
end

# Ref: https://github.com/stan-dev/stan/blob/develop/src/stan/mcmc/hmc/base_hmc.hpp
find_good_eps{T}(model::Function, vi::VarInfo, spl::Sampler{T}) = begin
  println("[Turing] looking for good initial eps...")
  ϵ = 0.1

  p = sample_momentum(vi, spl)
  H0 = find_H(p, model, vi, spl)

  θ = realpart(vi[spl])
  θ_prime, p_prime, τ = leapfrog(θ, p, 1, ϵ, model, vi, spl)
  h = τ == 0 ? Inf : find_H(p_prime, model, vi, spl)

  delta_H = H0 - h
  direction = delta_H > log(0.8) ? 1 : -1

  iter_num = 1

  # Heuristically find optimal ϵ
  while (iter_num <= 12)

    p = sample_momentum(vi, spl)
    H0 = find_H(p, model, vi, spl)

    θ_prime, p_prime, τ = leapfrog(θ, p, 1, ϵ, model, vi, spl)
    h = τ == 0 ? Inf : find_H(p_prime, model, vi, spl)
    dprintln(1, "direction = $direction, h = $h")

    delta_H = H0 - h

    if ((direction == 1) && !(delta_H > log(0.8)))
      break;
    elseif ((direction == -1) && !(delta_H < log(0.8)))
      break;
    else
      ϵ = direction == 1 ? 2.0 * ϵ : 0.5 * ϵ
    end

    iter_num += 1
  end

  while h == Inf  # revert if the last change is too big
    ϵ = ϵ / 2               # safe is more important than large
    θ_prime, p_prime, τ = leapfrog(θ, p, 1, ϵ, model, vi, spl)
    h = τ == 0 ? Inf : find_H(p_prime, model, vi, spl)
  end
  println("\r[$T] found initial ϵ: ", ϵ)
  ϵ
end
