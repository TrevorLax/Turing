using Test, ForwardDiff, Distributions, FDM, Flux.Tracker
using StatsFuns: binomlogpdf

# Real

x_real = randn(5)

dists = [Normal(0, 1)]

for dist in dists

    f(x::Vector) = sum(logpdf.(Ref(dist), x))

    ForwardDiff.gradient(f, x_real)

end

# Postive

x_positive = randn(5).^2

dists = [Gamma(2, 3)]

for dist in dists

    f(x::Vector) = sum(logpdf.(Ref(dist), x))

    g = x -> ForwardDiff.gradient(f, x)

end

let
    foo = p->binomlogpdf(10, p, 3)
    @test isapprox(
        Tracker.gradient(foo, 0.5)[1],
        central_fdm(5, 1)(foo, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(foo, 0.5)[1],
        ForwardDiff.derivative(foo, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )

    bar = p->logpdf(Binomial(10, p), 3)
    @test isapprox(
        Tracker.gradient(bar, 0.5)[1],
        central_fdm(5, 1)(bar, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(bar, 0.5)[1],
        ForwardDiff.derivative(bar, 0.5),
        rtol=1e-8,
        atol=1e-8,
    )
end

let
    foo = p->Turing.poislogpdf(p, 1)
    @test isapprox(
        Tracker.gradient(foo, 0.5)[1],
        central_fdm(5, 1)(foo, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(foo, 0.5)[1],
        ForwardDiff.derivative(foo, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )

    bar = p->logpdf(Poisson(p), 3)
    @test isapprox(
        Tracker.gradient(bar, 0.5)[1],
        central_fdm(5, 1)(bar, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(bar, 0.5)[1],
        ForwardDiff.derivative(bar, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
end

let
    foo = p->Turing.nbinomlogpdf(5, p, 1)
    @test isapprox(
        Tracker.gradient(foo, 0.5)[1],
        central_fdm(5, 1)(foo, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(foo, 0.5)[1],
        ForwardDiff.derivative(foo, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )

    bar = p->logpdf(NegativeBinomial(5, p), 3)
    @test isapprox(
        Tracker.gradient(bar, 0.5)[1],
        central_fdm(5, 1)(bar, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(bar, 0.5)[1],
        ForwardDiff.derivative(bar, 0.5);
        rtol=1e-8,
        atol=1e-8,
    )
end

let
    foo = r->Turing.nbinomlogpdf(r, 0.5, 1)
    @test isapprox(
        Tracker.gradient(foo, 3.5)[1],
        central_fdm(5, 1)(foo, 3.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(foo, 3.5)[1],
        ForwardDiff.derivative(foo, 3.5);
        rtol=1e-8,
        atol=1e-8,
    )

    bar = r->logpdf(NegativeBinomial(r, 0.5), 3)
    @test isapprox(
        Tracker.gradient(bar, 3.5)[1],
        central_fdm(5, 1)(bar, 3.5);
        rtol=1e-8,
        atol=1e-8,
    )
    @test isapprox(
        Tracker.gradient(bar, 3.5)[1],
        ForwardDiff.derivative(bar, 3.5);
        rtol=1e-8,
        atol=1e-8,
    )
end

let 
    foo = x -> Turing.nbinomlogpdf(x[1], x[2], 1)
    @test isapprox(
        Tracker.gradient(foo, [3.5, 0.5])[1],
        ForwardDiff.gradient(foo, [3.5, 0.5]);
        rtol=1e-8,
        atol=1e-8,
    )
end
