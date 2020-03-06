# This file was modified from part of Julia's Base:
# `base/summarysize.jl`

module MemorySummarySize

using Core: SimpleVector
using Base: unsafe_convert, isbitsunion

Base.@kwdef mutable struct FieldResult
    size::Int = 0
    type::Type
    is_collection::Bool = false
    skipped_self_reference::Bool = false
    children::Dict{String, FieldResult} = Dict()
    parent::Union{FieldResult,Nothing} = nothing
end
function Base.show(io::IO, fr::FieldResult)
    # Print everything but parent
    print(io,"FieldResult($(fr.size), $(fr.type), $(fr.is_collection), $(fr.children))")
end

mutable struct FrontierNode
    x
    i::Int
    parent_result::FieldResult
end

struct SummarySize
    seen::IdDict{Any,Any}
    fieldresult::FieldResult
    frontier::Vector{FrontierNode}
    exclude::Any
    chargeall::Any
    SummarySize(obj, exclude, chargeall) = new(IdDict(), FieldResult(type=typeof(obj)), [], exclude, chargeall)
end

"""
    Base.summarysize(obj; exclude=Union{...}, chargeall=Union{...}) -> Int

Compute the amount of memory, in bytes, used by all unique objects reachable from the argument.

# Keyword Arguments
- `exclude`: specifies the types of objects to exclude from the traversal.
- `chargeall`: specifies the types of objects to always charge the size of all of their
  fields, even if those fields would normally be excluded.
"""
function summarysize(obj;
                     parentname="obj",
                     exclude = Union{DataType, Core.TypeName, Core.MethodInstance},
                     chargeall = Union{Core.TypeMapEntry, Method})
    @nospecialize obj exclude chargeall
    ss = SummarySize(obj, exclude, chargeall)
    parent = ss.fieldresult
    size::Int = ss(parent,obj)
    while !isempty(ss.frontier)
        # DFS heap traversal of everything without a specialization
        # BFS heap traversal of anything with a specialization
        node = ss.frontier[end]
        x = node.x
        i = node.i
        parent_result = node.parent_result
        val = nothing
        name = parentname
        if isa(x, SimpleVector)
            nf = length(x)
            if isassigned(x, i)
                val = x[i]
                name = "$i"
            end
        elseif isa(x, Array)
            nf = length(x)
            if ccall(:jl_array_isassigned, Cint, (Any, UInt), x, i - 1) != 0
                val = x[i]
                name = "$i"
            end
        else
            nf = nfields(x)
            ft = typeof(x).types
            if !isbitstype(ft[i]) && isdefined(x, i)
                val = getfield(x, i)
                name = "$(fieldname(typeof(x), i))"
            end
        end
        if nf > i
            ss.frontier[end].i = i + 1
        else
            pop!(ss.frontier)
        end
        if val !== nothing && !isa(val, Module) && (!isa(val, ss.exclude) || isa(x, ss.chargeall))
            fieldresult = get!(parent_result.children, name, FieldResult(type=typeof(val),parent=parent_result))
            valsize = ss(fieldresult, val)::Int
            _finish_fieldresult(fieldresult, val, valsize)
            p = fieldresult.parent
            while p !== nothing
                p.size += valsize
                p = p.parent
            end
            size += valsize
        end
    end
    _finish_fieldresult(ss.fieldresult, obj, size)
    return ss.fieldresult
end
function _finish_fieldresult(fieldresult, val, size)
    fieldresult.size = size
    # Mark Collection types not handled below
    if val isa Tuple
        fieldresult.is_collection = true
    end
end

(ss::SummarySize)(fieldresult, @nospecialize obj) = _summarysize(ss, fieldresult, obj)
# define the general case separately to make sure it is not specialized for every type
@noinline function _summarysize(ss::SummarySize, fieldresult, @nospecialize obj)
    isdefined(typeof(obj), :instance) && return 0
    # NOTE: this attempts to discover multiple copies of the same immutable value,
    # and so is somewhat approximate.
    key = ccall(:jl_value_ptr, Ptr{Cvoid}, (Any,), obj)
    if handle_seen(fieldresult, ss, key) return 0 end
    if nfields(obj) > 0
        push!(ss.frontier, FrontierNode(obj, 1, fieldresult))
    end
    if isa(obj, UnionAll) || isa(obj, Union)
        # black-list of items that don't have a Core.sizeof
        sz = 2 * sizeof(Int)
    else
        sz = Core.sizeof(obj)
    end
    if sz == 0
        # 0-field mutable structs are not unique
        return gc_alignment(0)
    end
    return sz
end
function handle_seen(fieldresult, ss, obj)
    if haskey(ss.seen, obj)
        fieldresult.skipped_self_reference = true
        return true
    else
        ss.seen[obj] = true
        return false
    end
end

(::SummarySize)(fieldresult, obj::Symbol) = 0
(::SummarySize)(fieldresult, obj::SummarySize) = 0

function (ss::SummarySize)(f, obj::String)
    key = ccall(:jl_value_ptr, Ptr{Cvoid}, (Any,), obj)
    if handle_seen(f, ss, obj) return 0 end
    return Core.sizeof(Int) + Core.sizeof(obj)
end

function (ss::SummarySize)(f, obj::DataType)
    key = pointer_from_objref(obj)
    if handle_seen(f, ss, obj) return 0 end
    size::Int = 7 * Core.sizeof(Int) + 6 * Core.sizeof(Int32)
    size += 4 * nfields(obj) + ifelse(Sys.WORD_SIZE == 64, 4, 0)
    size += ss(obj.parameters)::Int
    if isdefined(obj, :types)
        size += ss(obj.types)::Int
    end
    return size
end

function (ss::SummarySize)(fieldresult, obj::Core.TypeName)
    key = pointer_from_objref(obj)
    if handle_seen(f, ss, obj) return 0 end
    return Core.sizeof(obj) + (isdefined(obj, :mt) ? ss(obj.mt) : 0)
end

function (ss::SummarySize)(fieldresult, obj::Array)
    fieldresult.is_collection = true
    if handle_seen(fieldresult, ss, obj) return 0 end
    headersize = 4*sizeof(Int) + 8 + max(0, ndims(obj)-2)*sizeof(Int)
    size::Int = headersize
    datakey = unsafe_convert(Ptr{Cvoid}, obj)
    if !haskey(ss.seen, datakey)
        ss.seen[datakey] = true
        dsize = Core.sizeof(obj)
        if isbitsunion(eltype(obj))
            # add 1 union selector byte for each element
            dsize += length(obj)
        end
        size += dsize
        if !isempty(obj) && !Base.allocatedinline(eltype(obj))
            push!(ss.frontier, FrontierNode(obj, 1, fieldresult))
        end
    end
    return size
end

function (ss::SummarySize)(fieldresult, obj::SimpleVector)
    fieldresult.is_collection = true
    key = pointer_from_objref(obj)
    if handle_seen(fieldresult, ss, obj) return 0 end
    size::Int = Core.sizeof(obj)
    if !isempty(obj)
        push!(ss.frontier, FrontierNode(obj, 1, fieldresult))
    end
    return size
end

function (ss::SummarySize)(fieldresult, obj::Module)
    if handle_seen(fieldresult, ss, obj) return 0 end
    size::Int = Core.sizeof(obj)
    for binding in names(obj, all = true)
        if isdefined(obj, binding) && !isdeprecated(obj, binding)
            value = getfield(obj, binding)
            if !isa(value, Module) || parentmodule(value) === obj
                size += ss(value)::Int
                if isa(value, UnionAll)
                    value = unwrap_unionall(value)
                end
                if isa(value, DataType) && value.name.module === obj && value.name.name === binding
                    # charge a TypeName to its module (but not to the type)
                    size += ss(value.name)::Int
                end
            end
        end
    end
    return size
end

function (ss::SummarySize)(fieldresult, obj::Task)
    if handle_seen(fieldresult, ss, obj) return 0 end
    size::Int = Core.sizeof(obj)
    if isdefined(obj, :code)
        size += ss(obj.code)::Int
    end
    size += ss(obj.storage)::Int
    size += ss(obj.backtrace)::Int
    size += ss(obj.donenotify)::Int
    size += ss(obj.exception)::Int
    size += ss(obj.result)::Int
    # TODO: add stack size, and possibly traverse stack roots
    return size
end

end # module
