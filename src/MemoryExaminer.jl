module MemoryExaminer

# Use README as module docstring
@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    read(path, String)
end MemoryExaminer

using TerminalMenus
using Humanize

include("summarysize.jl")
include("ui.jl")

"""
    @inspect x

Open an interactive window to explore the sizes of the fields of `x`.
"""
macro inspect(obj)
    :($inspect($(esc(obj)), $(QuoteNode(obj))))
end

inspect(@nospecialize obj) = inspect(obj, "obj")
function inspect(@nospecialize(obj), name)
    TerminalMenus.config(scroll=:wrap,cursor='→')

    field_summary = MemorySummarySize.summarysize(obj, parentname=name)
    try
        interactive_inspect_results(field_summary, name)
    catch e
        e isa ExitUIException || rethrow()
    end
    nothing
end
struct ExitUIException end
function interactive_inspect_results(field_summary, path)
    println("—"^(displaysize(stdout)[2]*2÷3))
    type = field_summary.type
    println("($path)::$type => $(_field_size(field_summary))")

    children = sort(collect(field_summary.children), by=pair->pair[2].size, rev=true)
    options = [
        "$name::$(f.type) => $(_field_size(f))"
        for (name,f) in children
    ]

    is_collection = field_summary.is_collection
    num_children = length(field_summary.children)
    if num_children > 0
        total_allocated = sum(f.size for (_,f) in field_summary.children)
        internal_bytes = field_summary.size - total_allocated
        println("   $(Humanize.datasize(internal_bytes, style=:bin)) internal")
    end
    request_str = is_collection ? "$num_children Allocated Indexes:" : "$num_children Allocated Fields:"
    choice = _get_next_field_from_user(request_str, options)
    if choice == UP
        return
    else
        (name,field) = children[choice]
        newpath = is_collection ? "$path[$name]" : "$path.$name"
        interactive_inspect_results(field, newpath)
        # When you return Up from choice, rerun this pane
        interactive_inspect_results(field_summary, path)
    end
end
_field_size(f) = f.skipped_self_reference ? "<self-reference>" : Humanize.datasize(f.size, style=:bin)

struct FieldError end
const fielderror = FieldError()
_trygetfield(o, f) = try getfield(o, f) catch; fielderror end


const UP = -2
function _get_next_field_from_user(request_str, option_strings)
    option_strings = [option_strings..., "↩"]
    height = displaysize(stdout)[1]
    menu = InspectMenu(option_strings, pagesize=min(20, height-3))

    choice = request(request_str, menu)

    if choice == -1
        println("Exiting $(nameof(@__MODULE__))")
        throw(ExitUIException())
    elseif choice == length(option_strings)
        UP
    else
        return choice
    end
end

end  # module
