#####################################
# Helper functions for Dual numbers #
#####################################

@inline realpart(r::Real)             = r
@inline realpart(d::ForwardDiff.Dual) = d.value
@inline realpart(ds::Union{Vector,SubArray}) = Float64[realpart(d) for d in ds] # NOTE: the function below is assumed to return a Vector now
@inline realpart!(arr::Union{Array,SubArray}, ds::Union{Array,SubArray}) = for i = 1:length(ds) arr[i] = realpart(ds[i]) end
@inline realpart(ds::Matrix{T}) where {T <: Real} = Float64[realpart(col) for col in ds]
@inline realpart(ds::Matrix{Any}) = [realpart(col) for col in ds]
@inline realpart(ds::Array)  = map(d -> realpart(d), ds)  # NOTE: this function is not optimized
# @inline realpart(ds::TArray) = realpart(Array(ds))    # TODO: is it disabled temporary
@inline realpart(ta::Tracker.TrackedReal) = ta.data

@inline dualpart(d::ForwardDiff.Dual)       = d.partials.values
@inline dualpart(ds::Union{Array,SubArray}) = map(d -> dualpart(d), ds)

# Base.promote_rule(D1::Type{Real}, D2::Type{ForwardDiff.Dual}) = D2
import Base: <=
<=(a::Tracker.TrackedReal, b::Tracker.TrackedReal) = a.data <= b.data

#####################################################
# Helper functions for vectorize/reconstruct values #
#####################################################

vectorize(d::UnivariateDistribution, r::Real) = Vector{Real}([r])
vectorize(d::MultivariateDistribution, r::AbstractVector{<:Real}) = Vector{Real}(r)
vectorize(d::MatrixDistribution, r::AbstractMatrix{<:Real}) = Vector{Real}(vec(r))

# NOTE:
# We cannot use reconstruct{T} because val is always Vector{Real} then T will be Real.
# However here we would like the result to be specifric type, e.g. Array{Dual{4,Float64}, 2},
# otherwise we will have error for MatrixDistribution.
# Note this is not the case for MultivariateDistribution so I guess this might be lack of
# support for some types related to matrices (like PDMat).
@inline reconstruct(d::Distribution, val::Union{Vector,SubArray}) = reconstruct(d, val, typeof(val[1]))
# NOTE: the implementation below was: `T(val[1])`; it is changed to `val[1]` due to the need of ReverseDiff.jl, no side effect found yet
@inline reconstruct(d::UnivariateDistribution,   val::Union{Vector,SubArray}, T::Type) = val[1]
@inline reconstruct(d::MultivariateDistribution, val::Union{Vector,SubArray}, T::Type) = Array{T, 1}(val)
@inline reconstruct(d::MatrixDistribution,       val::Union{Vector,SubArray}, T::Type) = Array{T, 2}(reshape(val, size(d)...))


@inline reconstruct!(r, d::Distribution, val::Union{Vector,SubArray}) = reconstruct!(r, d, val, typeof(val[1]))
@inline reconstruct!(r, d::MultivariateDistribution, val::Union{Vector,SubArray}, T::Type) = (r[:] = val; r)


@inline reconstruct(d::Distribution, val::Union{Vector,SubArray}, n::Int) = reconstruct(d, val, typeof(val[1]), n)
@inline reconstruct(d::UnivariateDistribution,   val::Union{Vector,SubArray}, T::Type, n::Int) = Array{T, 1}(val)
@inline reconstruct(d::MultivariateDistribution, val::Union{Vector,SubArray}, T::Type, n::Int) = Array{T, 2}(reshape(val, size(d)[1], n))

@inline reconstruct(d::MatrixDistribution,       val::Union{Vector,SubArray}, T::Type, n::Int) = begin
  orig = Vector{Matrix{T}}(undef, n)
  tmp = Array{T, 3}(reshape(val, size(d)[1], size(d)[2], n))
  for i = 1:n
    orig[i] = tmp[:,:,i]
  end
  orig
end

@inline reconstruct!(r, d::Distribution, val::Union{Vector,SubArray}, n::Int) = reconstruct!(r, d, val, typeof(val[1]), n)
@inline reconstruct!(r, d::MultivariateDistribution, val::Union{Vector,SubArray}, T::Type, n::Int) = (r[:] = val; r)
