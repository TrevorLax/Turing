using Distributions
using Turing
using Mamba: describe

TPATH = Pkg.dir("Turing")

include(TPATH*"/example-models/nips-2017/sv.model.jl")

using HDF5, JLD
sv_data = load(TPATH*"/example-models/nips-2017/sv-data.jld.data")["data"]

model_f = sv_model(data=sv_data[1])
sample_n = 500

# setchunksize(550)
# chain_nuts = sample(model_f, NUTS(sample_n, 0.65))
# describe(chain_nuts)

# setchunksize(5)
# chain_gibbs = sample(model_f, Gibbs(sample_n, PG(50,1,:h), NUTS(1000,0.65,:ϕ,:σ,:μ)))
# describe(chain_gibbs)

chain_nuts = sample(model_f, HMC(2000, 0.05, 10))