#########################
# Sampler I/O Interface #
#########################

##########
# Sample #
##########

mutable struct Sample
    weight :: Float64     # particle weight
    value :: Dict{Symbol,Any}
end

Base.getindex(s::Sample, v::Symbol) = getjuliatype(s, v)

function parse_inds(inds)
    p_inds = [parse(Int, m.captures[1]) for m in eachmatch(r"(\d+)", inds)]
    if length(p_inds) == 1
        return p_inds[1]
    else
        return Tuple(p_inds)
    end
end

function getjuliatype(s::Sample, v::Symbol, cached_syms=nothing)
    # NOTE: cached_syms is used to cache the filter entiries in svalue. This is helpful when the dimension of model is huge.
    if cached_syms == nothing
        # Get all keys associated with the given symbol
        syms = collect(Iterators.filter(k -> occursin(string(v)*"[", string(k)), keys(s.value)))
    else
        syms = collect((Iterators.filter(k -> occursin(string(v), string(k)), cached_syms)))
    end

    # Map to the corresponding indices part
    idx_str = map(sym -> replace(string(sym), string(v) => ""), syms)
    # Get the indexing component
    idx_comp = map(idx -> collect(Iterators.filter(str -> str != "", split(string(idx), [']','[']))), idx_str)

    # Deal with v is really a symbol, e.g. :x
    if isempty(idx_comp)
        @assert haskey(s.value, v)
        return Base.getindex(s.value, v)
    end

    # Construct container for the frist nesting layer
    dim = length(split(idx_comp[1][1], ','))
    if dim == 1
        sample = Vector(undef, length(unique(map(c -> c[1], idx_comp))))
    else
        d = max(map(c -> parse_inds(c[1]), idx_comp)...)
        sample = Array{Any, length(d)}(undef, d)
    end

    # Fill sample
    for i = 1:length(syms)
        # Get indexing
        idx = parse_inds(idx_comp[i][1])
        # Determine if nesting
        nested_dim = length(idx_comp[1]) # how many nested layers?
        if nested_dim == 1
            setindex!(sample, getindex(s.value, syms[i]), idx...)
        else  # nested case, iteratively evaluation
            v_indexed = Symbol("$v[$(idx_comp[i][1])]")
            setindex!(sample, getjuliatype(s, v_indexed, syms), idx...)
        end
    end
    return sample
end

#########
# Chain #
#########

# Variables to put in the Chains :internal section.
const _internal_vars = ["elapsed", "eval_num", "lf_eps", "lp"]

# ind2sub is deprecated in Julia 1.0
ind2sub(v, i) = Tuple(CartesianIndices(v)[i])

function save(c::Chains, spl::AbstractSampler, model, vi, samples)
    nt = NamedTuple{(:spl, :model, :vi, :samples)}((spl, model, deepcopy(vi), samples))
    return setinfo(c, merge(nt, c.info))
end

function resume(c::Chains, n_iter::Int)
    @assert !isempty(c.info) "[Turing] cannot resume from a chain without state info"
    return sample(
        c.info[:model],
        c.info[:spl].alg;    # this is actually not used
        resume_from=c,
        reuse_spl_n=n_iter
    )
end

function set_resume!(s::Sampler; kwargs...)
    # Set reuse_spl_n if not given.
    reuse_spl_n = get(kwargs, :reuse_spl_n, 0)
    @assert reuse_spl_n isa Integer "reuse_spl_n must be an Integer."

    # Set the default for resuming the sampler.
    resume_from = get(kwargs, :resume_from, nothing)
    @assert resume_from isa Union{Chains, Nothing}
        "resume_from must be a MCMCChains.Chains object."

    # Grab the sampler if we're reusing it.
    s = reuse_spl_n > 0 ?
        resume_from.info[:spl] :
        s

    # If we're resuming, grab the selector.
    if resume_from != nothing
        s.selector = resume_from.info[:spl].selector
    end

    # Pull in the vi if we're resuming.
    s.state.vi = resume_from == nothing ?
        s.state.vi :
        resume_from.info[:vi]
end

function split_var_str(var_str)
    ind = findfirst(c -> c == '[', var_str)
    inds = Vector{String}[]
    if ind == nothing
        return var_str, inds
    end
    sym = var_str[1:ind-1]
    ind = length(sym)
    while ind < length(var_str)
        ind += 1
        @assert var_str[ind] == '['
        push!(inds, String[])
        while var_str[ind] != ']'
            ind += 1
            if var_str[ind] == '['
                ind2 = findnext(c -> c == ']', var_str, ind)
                push!(inds[end], strip(var_str[ind:ind2]))
                ind = ind2+1
            else
                ind2 = findnext(c -> c == ',' || c == ']', var_str, ind)
                push!(inds[end], strip(var_str[ind:ind2-1]))
                ind = ind2
            end
        end
    end
    return sym, inds
end
