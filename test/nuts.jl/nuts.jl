include("../utility.jl")
using Test
using Turing

@model gdemo(x) = begin
  s ~ InverseGamma(2, 3)
  m ~ Normal(0, sqrt(s))
  x[1] ~ Normal(m, sqrt(s))
  x[2] ~ Normal(m, sqrt(s))
  return s, m
end

model_f = gdemo([1.5, 2.0])

alg = NUTS(5000, 1000, 0.65)
res = sample(model_f, alg)

v = get(res, [:s, :m])
@info(mean(v.s[1000:end])," ≈ ", 49/24, "?")
@info(mean(v.m[1000:end])," ≈ ", 7/6, "?")
@test mean(v.s[1000:end]) ≈ 49/24 atol=0.2
@test mean(v.m[1000:end]) ≈ 7/6 atol=0.2
