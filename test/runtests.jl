##########################################
# Master file for running all test cases #
##########################################

using Turing; turnprogress(false)

println("[runtests.jl] runtests.jl loaded")

# NOTE: please keep this test list structured when adding new test cases
# so that we can tell which test case is for which .jl file

testcases = Dict(
# Turing.jl/
#   src/
#     core/
        "ad.jl"        => ["ad1", "ad2", "ad3", "pass_dual_to_dists",],
        "compiler.jl"  => ["assume", "observe", "predict", "sample",
                           "beta_binomial", "noparam",
                          #  "opt_param_of_dist",
                          #  "explicit_ret",
                           "new_grammar", "newinterface", "noreturn", "forbid_global",],
        "container.jl" => ["copy_particle_container",],
        "varinfo.jl"   => ["replay", "test_varname", "varinfo", "orders", "is_inside",],
        "io.jl"        => ["chain_utility",], # "save_resume_chain",],
        "util.jl"      => ["util",],
#     distributions/
        "transform.jl" => ["transform",],
#     samplers/
#       support/
          "resample.jl" => ["resample", "particlecontainer",],
        "sampler.jl" => ["vectorize_observe", "vec_assume", "vec_assume_mv",],
        "gibbs.jl" => ["gibbs", "gibbs2", "gibbs_constructor",],
        "nuts.jl"  => ["nuts_cons", "nuts",
                      #  "nuts_geweke",
                      ],
        "hmcda.jl" => ["hmcda_cons", "hmcda",
                      #  "hmcda_geweke",
                      ],
        "hmc.jl"   => ["multivariate_support", "matrix_support",
                       "constrained_bounded", "constrained_simplex",],
        "sghmc.jl" => ["sghmc_cons", "sghmc_cons",],
        "sgld.jl"  => ["sgld_cons", "sgld_cons",],
        "is.jl"    => ["importance_sampling",],
        "mh.jl"    => ["mh_cons", "mh", "mh2",],
        # "pmmh.jl"  => ["pmmh_cons", "pmmh", "pmmh2",],
        "pmmh.jl"  => ["pmmh_cons", "pmmh2",],
        "ipmcmc.jl"=> ["ipmcmc_cons", "ipmcmc", "ipmcmc2",],
#       pgibbs.jl
#       sampler.jl
#       smc.jl
#     trace/
        "tarray.jl"   => ["tarray", "tarray2", "tarray3",],
        "taskcopy.jl" => ["clonetask",],
        "trace.jl"    => ["trace",],
#   Turing.jl
      # "normal_loc",
      # "normal_mixture",
      # "naive_bayes"
)

# NOTE: put test cases which only want to be check in version 0.4.x here
testcases_v04 = [
  "beta_binomial",
  "tarray"
]

# NOTE: put test cases which want to be excluded here
testcases_excluded = [
  "tarray2",
  "predict"
]

# Run tests
path = dirname(@__FILE__)
cd(path)
println("[runtests.jl] CDed test path")
include("utility.jl")
println("[runtests.jl] utility.jl loaded")
println("[runtests.jl] testing starts")
for (target, list) in testcases
  for t in list
    if ~ (t in testcases_excluded)
      if t in testcases_v04
        if VERSION < v"0.5"
          println("[runtests.jl] \"$target/$t.jl\" is running")
          include(target*"/"t*".jl");
          # readstring(`julia $t.jl`)
          println("[runtests.jl] \"$target/$t.jl\" is successful")
        end
      else
        println("[runtests.jl] \"$target/$t.jl\" is running")
        include(target*"/"t*".jl");
        # readstring(`julia $t.jl`)
        println("[runtests.jl] \"$target/$t.jl\" is successful")
      end
    end
  end
end
println("[runtests.jl] all tests pass")
