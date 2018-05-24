include("unit_test_helper.jl")
include("simple_gauss.jl")

include("nuts.jl")

# Turing

mf = simple_gauss()
chn = sample(mf, HMC(2000, 0.05, 5))

println("mean of m: $(mean(chn[:m][1000:end]))")

# Plain Julia

M_adapt = 1000
ϵ0 = 0.05
logϵ = log(ϵ0)
μ = log(10 * ϵ0)
logϵbar = log(1)
Hbar = 0

δ = 0.75

stds = ones(θ_dim)
θ = randn(θ_dim)
lj = lj_func(θ)

chn = Dict(:θ=>Vector{Vector{Float64}}(), :logϵ=>Vector{Float64}())

function dummy_print(args...)
  nothing
end

println("Start to run NUTS")

totla_num = 5000
for iter = 1:totla_num
  
  θ, da_stat = _nuts_step(θ, exp(logϵ), lj_func, stds)
  logϵ, Hbar, logϵbar = _adapt_ϵ(logϵ, Hbar, logϵbar, da_stat, iter, M_adapt, δ, μ)

  push!(chn[:θ], θ)
  push!(chn[:logϵ], logϵ)
  # if (iter % 50 == 0) println(θ) end
end

@show mean(chn[:θ])
samples_first_dim = map(x -> x[1], chn[:θ])
@show std(samples_first_dim)
@show mean(exp.(chn[:logϵ]))