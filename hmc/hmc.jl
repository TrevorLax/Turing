###############################################
###############################################
## implementation of Hamiltonian Monte Carlo ##
###############################################
###############################################

using Distributions         # for distribution
using Gadfly, Cairo         # for plotting
import ForwardDiff          # for graident

#########################
# implementation of HMC #
#########################

function HMCStepper(x::Vector, E::Function, ∇E::Function, ϵ::Float64, τ::Int64)
  """
  @input
    x       -   current state
    E       -   the negative log-probablity of the traget density
    ∇E      -   the graident of the target density
    ϵ       -   'leapfrog' step size
    τ       -   'leapfrog' step number
  @output
    x       -   next state
  """
  p = randn(length(x))      # generate random momentum

  oldH = p' * p / 2 + E(x)  # record old Hamiltonian
  oldx = x                  # record old state
  val∇E = ∇E(x)

  for t in 1:τ              # make τ ‘leapfrog’ steps
    p -= ϵ * val∇E / 2      # make a half step for momentum
    x += ϵ * p              # make a full step for state
    val∇E = ∇E(x)           # this can save evaluating the gradient by half times
    p -= ϵ * val∇E / 2      # make a half step for momentum
  end

  H = p' * p / 2 + E(x)     # claculate the new Hamiltonian
  ΔH = H - oldH             # calculate the difference in Hamiltonian

  ΔH = ΔH[1]                # Vector{Float64, 1} -> Float64

  if ΔH < 0                 # decide wether to accept of not
    acc = true
  elseif rand() < exp(-ΔH)
    acc = true
  else
    acc = false
  end

  if ~acc                   # rewind of rejected
    x = oldx
  end

  return x
end

function HMCSampler(Q::Function, sampleNum::Int64, ϵ::Float64, τ::Int64, dim::Int64, verbose::Bool=false)
  """
  @input
    Q         -   the target density
    sampleNum -   number of samples to generate
    ϵ         -   'leapfrog' step size
    τ         -   'leapfrog' step number
    dim       -   dimension of states
  @output
    samples   -   samples
  """
  E = x -> -log(Q(x))                 # we assume Q(x) = 1 / Z * e ^ (-E(x))
  ∇E = ForwardDiff.gradient(E)

  x = zeros(dim)
  samples = []
  push!(samples, x)

  acceptCount = 0
  for i in 1:sampleNum
    xNew = HMCStepper(x, E, ∇E, ϵ, τ)

    # log
    if verbose
      if xNew != x
        acceptCount += 1
      end
      if i % 100 == 0
        @printf "i = %d, accept rate = %f\n" i acceptCount / i
      end
    end

    x = xNew
    push!(samples, x)
  end
  return samples
end

#############################################
# Task -1 - implement MH to sample from f() #
#############################################

function MHStepper(x::Vector, logQ::Function, stepSize::Float64)
  """
  @input
    x         -   current state
    Q         -   the target density
    stepSize  -   step size
  @output
    x         -   next state
  """
  xNew = x + randn(length(x)) * stepSize
  if logQ(xNew) - logQ(x) > log(rand())
    x = xNew
  end
  return x
end

function MHSampler(Q::Function, sampleNum::Int64, stepSize::Float64, dim::Int64)
  """
  @input
    Q         -   target density
    sampleNum -   number of samples to generate
    stepSize  -   step size
    dim       -   dimension of states
  @output
    samples   -   samples
  """
  logQ = x -> log(Q(x))       # need the log-probablity to do inference

  x = zeros(dim)
  samples = []
  push!(samples, x)

  for _ in 1:sampleNum
    x = MHStepper(x, logQ, stepSize)
    push!(samples, x)
  end
  return samples
end

######################
######################
## Helper Functions ##
######################
######################

function eval1DSamples(samples)
  μ = mean(Float64[x[1] for x in samples])  # inference μ
  σ = var(Float64[x[1] for x in samples])   # inference σ
  @printf "μ = %f, σ = %f" μ σ              # output estimates
end

function eval2DSamples(samples)
  μ1 = mean(Float64[x[1] for x in samples])  # inference μ1
  σ1 = var(Float64[x[1] for x in samples])   # inference σ1
  μ2 = mean(Float64[x[2] for x in samples])  # inference μ2
  σ2 = var(Float64[x[2] for x in samples])   # inference σ2

  # output estimates
  @printf "μ1 = %f, σ1 = %f, μ2 = %f, σ2 = %f" μ1 σ1 μ2 σ2

  # plot the 2D example
  sampleLayer = layer(x=Float64[x[1] for x in samples], y=Float64[x[2] for x in samples], Geom.point)
  plot(sampleLayer, Guide.xlabel("x"), Guide.ylabel("-"), Guide.title("Samples"), Coord.cartesian(xmin=-3, xmax=9, ymin=-3, ymax=9))
end

###############
###############
## Reference ##
###############
###############

#########################################
# Octave source code for the HMC method #
#   from Information theory by Mackay   #
#########################################

# g = gradE ( x ) ;                 # set gradient using initial x
# E = findE ( x ) ;                 # set objective function too
#
# for l = 1:L                       # loop L times
#   p = randn ( size(x) ) ;         # initial momentum is Normal(0,1)
#   H = p’ * p / 2 + E ;            # evaluate H(x,p)
#
#   xnew = x ; gnew = g ;
#   for tau = 1:Tau                 # make Tau ‘leapfrog’ steps
#
#     p = p - epsilon * gnew / 2 ;  # make half-step in p
#     xnew = xnew + epsilon * p ;   # make step in x
#     gnew = gradE ( xnew ) ;       # find new gradient
#     p = p - epsilon * gnew / 2 ;  # make half-step in p
#
#   endfor
#
#   Enew = findE ( xnew ) ;         # find new value of H
#   Hnew = p’ * p / 2 + Enew ;
#   dH = Hnew - H ;                 # Decide whether to accept
#
#   if ( dH < 0 )                accept = 1 ;
#   elseif ( rand() < exp(-dH) ) accept = 1 ;
#   else                         accept = 0 ;
#
#   if ( accept )
#     g = gnew ; x = xnew ; E = Enew ;
#   endif
# endfor
