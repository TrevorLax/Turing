module Essential

using DistributionsAD, Bijectors
using Libtask, ForwardDiff, Random
using Distributions, LinearAlgebra
using Reexport
using ..Turing: Turing
using DynamicPPL: Model, AbstractSampler, Sampler, SampleFromPrior
using LinearAlgebra: copytri!
using Bijectors: PDMatDistribution
using AdvancedVI
using StatsFuns: logsumexp, softmax
@reexport using DynamicPPL
using ADTypes: ADTypes, AutoForwardDiff, AutoTracker, AutoReverseDiff, AutoZygote

import AdvancedPS

include("container.jl")

export  @model,
        @varname,
        generate_observe,
        translate_tilde!,
        get_vars,
        get_data,
        get_default_values,
        ParticleContainer,
        Particle,
        Trace,
        fork,
        forkr,
        current_trace,
        getweights,
        getweight,
        effectiveSampleSize,
        sweep!,
        ResampleWithESSThreshold,
        AutoForwardDiff,
        AutoTracker,
        AutoZygote,
        AutoReverseDiff,
        value,
        @logprob_str,
        @prob_str

# AutoTapir is only supported by ADTypes v1.0 and above.
@static if VERSION >= v"1.10" && pkgversion(ADTypes) >= v"1"
    using ADTypes: AutoTapir
    export AutoTapir
end

end # module
