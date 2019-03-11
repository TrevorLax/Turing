using Turing
using Test
using Random

Random.seed!(125)

x = [1.5 2.0]

@model gdemo(x) = begin
  s ~ InverseGamma(2,3)
  m ~ Normal(0,sqrt(s))
  for i in 1:length(x)
    x[i] ~ Normal(m, sqrt(s))
  end
  s, m
end

alg = IPMCMC(30, 500, 4)
chain = sample(gdemo(x), alg)
@test mean(chain[:s].value) ≈ 49/24 atol=0.1
@test mean(chain[:m].value) ≈ 7/6 atol=0.1
