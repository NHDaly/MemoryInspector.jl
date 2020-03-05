module MemoryExaminer

# Use README as module docstring
@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    read(path, String)
end MemoryExaminer

using TerminalMenus
using Humanize

"""
    @inspect x

Open an interactive window to explore the sizes of the fields of `x`.
"""
macro inspect(obj)
    :($inspect($(esc(obj)), $(QuoteNode(obj))))
end

probably_a_collection(x::T) where T = probably_a_collection(T)
probably_a_collection(x::Type{T}) where T = false
const _collection_types = (AbstractArray, AbstractDict, AbstractSet)
probably_a_collection(x::Type{<:Union{_collection_types...}}) = true


inspect(@nospecialize obj) = inspect(obj, "obj")
function inspect(@nospecialize(obj), path)
    println("—"^(displaysize(stdout)[2]*2÷3))
    sz = Base.summarysize(obj)
    println("($path)::$(typeof(obj)) => $(Humanize.datasize(sz))")

    is_collection, fieldnames, fields, options = if probably_a_collection(typeof(obj))
        fields = collect(obj)
        fieldnames = 1:length(fields)
        options = [
            "$i::$(typeof(f)) => $(Humanize.datasize(Base.summarysize(f)))"
            for (i,f) in enumerate(fields)
        ]
        true, fieldnames, fields, options
    else
        fieldnames = propertynames(obj)
        fields = [_trygetfield(obj, n) for n in fieldnames]
        options = [
            "$fieldname::$(typeof(f)) => $(Humanize.datasize(Base.summarysize(f)))"
            for i in 1:length(fields)
            for (f,fieldname) in ((fields[i],fieldnames[i]),)
        ]
        false, fieldnames, fields, options
    end

    request_str = is_collection ? "Item indices:" : "Fields:"
    choice = _get_next_field_from_user(request_str, options)
    if choice == UP
        return
    else
        newpath = is_collection ? "$path[$(fieldnames[choice])]" : "$path.$(fieldnames[choice])"
        inspect(fields[choice], newpath)
        # When you return Up from choice, rerun this pane
        inspect(obj, path)
    end
end

struct FieldError end
const fielderror = FieldError()
_trygetfield(o, f) = try getfield(o, f) catch; fielderror end


TerminalMenus.config(scroll=:wrap,cursor='→')

const UP = -2
function _get_next_field_from_user(request_str, option_strings)
    option_strings = [option_strings..., "↩"]
    menu = RadioMenu(option_strings, pagesize=8)

    choice = request(request_str, menu)

    if choice == -1
        println("Menu canceled.")
    elseif choice == length(option_strings)
        UP
    else
        return choice
    end
end

end  # module
