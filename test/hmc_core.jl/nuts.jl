using Turing: _find_H, _leapfrog

"""
    build_tree(θ::T, r::Vector, logu::Float64, v::Int, j::Int, ϵ::Float64, H0::Float64,
               lj_func::Function, grad_func::Function, stds::Vector) where {T<:Union{Vector,SubArray}}

Recursively build balanced tree.

Ref: Algorithm 6 on http://www.stat.columbia.edu/~gelman/research/published/nuts.pdf
"""
function _build_tree(θ::T, r::Vector, logu::Float64, v::Int, j::Int, ϵ::Float64, H0::Float64,
                    lj_func::Function, grad_func::Function, stds::Vector; Δ_max=1000) where {T<:Union{Vector,SubArray}}
    doc"""
      - θ           : model parameter
      - r           : momentum variable
      - logu        : slice variable (in log scale)
      - v           : direction ∈ {-1, 1}
      - j           : depth of tree
      - ϵ           : leapfrog step size
      - H0          : initial H
      - lj_func     : function for log-joint
      - grad_func   : function for the gradient of log-joint
    """
    if j == 0
      # Base case - take one leapfrog step in the direction v.
      θ′, r′, τ_valid = _leapfrog(θ, r, 1, v * ϵ, grad_func)
      # Use old H to save computation
      H′ = τ_valid == 0 ? Inf : _find_H(θ′, r′, lj_func, stds)
      n′ = (logu <= -H′) ? 1 : 0
      s′ = (logu < Δ_max + -H′) ? 1 : 0
      α′ = exp(min(0, -H′ - (-H0)))

      return θ′, r′, θ′, r′, θ′, n′, s′, α′, 1
    else
      # Recursion - build the left and right subtrees.
      θm, rm, θp, rp, θ′, n′, s′, α′, n′α = _build_tree(θ, r, logu, v, j - 1, ϵ, H0, lj_func, grad_func, stds)

      if s′ == 1
        if v == -1
          θm, rm, _, _, θ′′, n′′, s′′, α′′, n′′α = _build_tree(θm, rm, logu, v, j - 1, ϵ, H0, lj_func, grad_func, stds)
        else
          _, _, θp, rp, θ′′, n′′, s′′, α′′, n′′α = _build_tree(θp, rp, logu, v, j - 1, ϵ, H0, lj_func, grad_func, stds)
        end
        if rand() < n′′ / (n′ + n′′)
          θ′ = θ′′
        end
        α′ = α′ + α′′
        n′α = n′α + n′′α
        s′ = s′′ * (dot(θp - θm, rm) >= 0 ? 1 : 0) * (dot(θp - θm, rp) >= 0 ? 1 : 0)
        n′ = n′ + n′′
      end

      θm, rm, θp, rp, θ′, n′, s′, α′, n′α
    end
  end

function _nuts_step(θ, ϵ, lj_func, stds)

  d = length(θ)
  r0 = randn(d)
  H0 = _find_H(θ, r0, lj_func, stds)
  logu = log(rand()) + -H0

  θm = θ; θp = θ; rm = r0; rp = r0; j = 0; θ_new = θ; n = 1; s = 1
  da_stat = nothing

  while s == 1

    v = rand([-1, 1])

    if v == -1

        θm, rm, _, _, θ′, n′, s′, α, nα = _build_tree(θm, rm, logu, v, j, ϵ, H0, lj_func, grad_func, stds)

    else

        _, _, θp, rp, θ′, n′, s′, α, nα = _build_tree(θp, rp, logu, v, j, ϵ, H0, lj_func, grad_func, stds)

    end

    if s′ == 1

        if rand() < min(1, n′ / n)

            θ_new = θ′

        end

    end

    n = n + n′
    s = s′ * (dot(θp - θm, rm) >= 0 ? 1 : 0) * (dot(θp - θm, rp) >= 0 ? 1 : 0)
    j = j + 1

    da_stat = α / nα

  end

  return θ_new, da_stat

end

function _adapt_ϵ(logϵ, Hbar, logϵbar, da_stat, m, M_adapt, δ, μ;
                  γ=0.05, t0=10, κ=0.75)

    if m <= M_adapt

        Hbar = (1.0 - 1.0 / (m + t0)) * Hbar + (1 / (m + t0)) * (δ - da_stat)
        logϵ = μ - sqrt(m) / γ * Hbar
        logϵbar = m^(-κ) * logϵ + (1 - m^(-κ)) * logϵbar

    else

        logϵ = logϵbar

    end

    return logϵ, Hbar, logϵbar

end