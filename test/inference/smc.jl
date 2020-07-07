using Turing, Random, Test
using Turing.Inference: getspace
using AdvancedPS # TODO: maybe use import instead?
# import AdvancedPS

dir = splitdir(splitdir(pathof(Turing))[1])[1]
include(dir*"/test/test_utils/AllUtils.jl")

@testset "SMC" begin
    @turing_testset "constructor" begin
        s = SMC()
        @test s.resampler == AdvancedPS.ResampleWithESSThreshold()
        @test getspace(s) === ()

        s = SMC(:x)
        @test s.resampler == AdvancedPS.ResampleWithESSThreshold()
        @test getspace(s) === (:x,)

        s = SMC((:x,))
        @test s.resampler == AdvancedPS.ResampleWithESSThreshold()
        @test getspace(s) === (:x,)

        s = SMC(:x, :y)
        @test s.resampler == AdvancedPS.ResampleWithESSThreshold()
        @test getspace(s) === (:x, :y)

        s = SMC((:x, :y))
        @test s.resampler == AdvancedPS.ResampleWithESSThreshold()
        @test getspace(s) === (:x, :y)

        s = SMC(0.6)
        @test s.resampler === AdvancedPS.ResampleWithESSThreshold(AdvancedPS.resample_systematic, 0.6)
        @test getspace(s) === ()

        s = SMC(0.6, (:x,))
        @test s.resampler === AdvancedPS.ResampleWithESSThreshold(AdvancedPS.resample_systematic, 0.6)
        @test getspace(s) === (:x,)

        s = SMC(AdvancedPS.resample_multinomial, 0.6)
        @test s.resampler === AdvancedPS.ResampleWithESSThreshold(AdvancedPS.resample_multinomial, 0.6)
        @test getspace(s) === ()

        s = SMC(AdvancedPS.resample_multinomial, 0.6, (:x,))
        @test s.resampler === AdvancedPS.ResampleWithESSThreshold(AdvancedPS.resample_multinomial, 0.6)
        @test getspace(s) === (:x,)

        s = SMC(AdvancedPS.resample_systematic)
        @test s.resampler === AdvancedPS.resample_systematic
        @test getspace(s) === ()

        s = SMC(AdvancedPS.resample_systematic, (:x,))
        @test s.resampler === AdvancedPS.resample_systematic
        @test getspace(s) === (:x,)
    end

    @turing_testset "models" begin
        @model function normal()
            a ~ Normal(4,5)
            3 ~ Normal(a,2)
            b ~ Normal(a,1)
            1.5 ~ Normal(b,2)
            a, b
        end

        tested = sample(normal(), SMC(), 100);

        # failing test
        @model function fail_smc()
            a ~ Normal(4,5)
            3 ~ Normal(a,2)
            b ~ Normal(a,1)
            if a >= 4.0
                1.5 ~ Normal(b,2)
            end
            a, b
        end

        @test_throws ErrorException sample(fail_smc(), SMC(), 100)
    end

    @turing_testset "logevidence" begin
        Random.seed!(100)

        @model function test()
            a ~ Normal(0, 1)
            x ~ Bernoulli(1)
            b ~ Gamma(2, 3)
            1 ~ Bernoulli(x / 2)
            c ~ Beta()
            0 ~ Bernoulli(x / 2)
            x
        end

        chains_smc = sample(test(), SMC(), 100)

        @test all(isone, chains_smc[:x].value)
        @test chains_smc.logevidence ≈ -2 * log(2)
    end
end

