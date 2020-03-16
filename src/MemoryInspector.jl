module MemoryInspector

# Use README as module docstring
@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    read(path, String)
end MemoryInspector

using TerminalMenus
using Humanize

module SelectionOptions
    @enum Option begin
        UP
        JUMP
    end
end

include("summarysize.jl")
include("selection_ui.jl")

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
# A user input error, which will be printed and then the UI will continue.
struct UserError
    err
end
function interactive_inspect_results(field_summary, path)
    println("—"^(displaysize(stdout)[2]*2÷3))
    println("""
        Select a field to recurse into or ↩ to ascend. [q]uit.

        Commands: [J]ump to field path.
        """)
    #=
    Toggles: [v]alue (of the current field).
    Show: [S]ource code, [A]ST, [L]LVM IR, [N]ative code
    Advanced: dump [P]arams cache.
    =#
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
    try
        choice = _get_next_field_from_user(request_str, options)
        if choice isa Integer
            (name,field) = children[choice]
            newpath = is_collection ? "$path[$name]" : "$path.$name"
            interactive_inspect_results(field, newpath)
        elseif choice isa SelectionOptions.Option
            if choice === SelectionOptions.UP
                return
            elseif choice === SelectionOptions.JUMP
                _command_jump(path, field_summary)
            else
                error("PROGRAMMING ERROR: Unexpected command: $(menu.selected_command)")
            end
        end
        # When you return Up from choice, rerun this pane
        interactive_inspect_results(field_summary, path)
    catch e
        # If we need to print a user error, do so, and then re-run this pane.
        if e isa UserError
            # Display as if it was an ErrorException
            Base.display_error(e.err)
            println(stdout, "Press enter to continue: ")
            # Enter (or ctrl-c) to continue
            try readline(stdin) catch e; if e isa InterruptException; end end
            interactive_inspect_results(field_summary, path)
        else
            rethrow()
        end
    end
end
_field_size(f) = f.skipped_self_reference ? "<self-reference>" : Humanize.datasize(f.size, style=:bin)

struct FieldError end
const fielderror = FieldError()
_trygetfield(o, f) = try getfield(o, f) catch; fielderror end


function _get_next_field_from_user(request_str, option_strings)
    option_strings = [option_strings..., "↩"]
    height = displaysize(stdout)[1]
    menu = SelectionUI.InspectMenu(option_strings, pagesize=min(20, height-3))

    choice = SelectionUI.request(request_str, menu)

    if choice == -1
        if menu.selected_command !== nothing
            return menu.selected_command
        end
        println("Exiting $(nameof(@__MODULE__))")
        throw(ExitUIException())
    elseif choice == length(option_strings)
        SelectionOptions.UP
    else
        return choice
    end
end

function _command_jump(current_path, field)
    current_path = String(current_path)  # might be a symbol
    println("""Enter the complete path to jump to (e.g. `parent.arr[2].keys[2].foo.bar`).
            (Press Ctrl-c to cancel)""")
    print("Path: ")
    try
        path = readline(stdin)
    catch e
        if e isa InterruptException
            println()
            return
        end
    end

    if !startswith(path, current_path)
        throw(UserError(ErrorException("Provided path must be COMPLETE; i.e. must start with `$current_path`")))
    end
    fullpath = path
    path = path[length(current_path)+1:end]
    try
        while !isempty(path)
            #@show path
            childname,subpath_len = if path[1] == '.'
                get_childname(path[2:end], in_index=false)
            elseif path[1] == '['
                get_childname(path[2:end], in_index=true)
            else
                throw(ErrorException("Invalid path starting at `$path`"))
            end
            #@show childname, subpath_len
            matches = [f for (name,f) in field.children if name == childname]
            if isempty(matches)
                throw(ArgumentError("No field on `$current_path` matching $childname"))
            end
            field = first(matches)
            current_path = fullpath[1:length(current_path)+subpath_len+1]
            path = path[length(current_path):end]
        end
    catch e
        rethrow(UserError(e))
    end

    interactive_inspect_results(field, current_path)
end

function get_childname(subpath; in_index=false)
    endchars = in_index ? (']',) : ('.','[')
    endidx = findfirst(c->c in endchars, subpath)
    if endidx === nothing
        return subpath, length(subpath)
    else
        return subpath[1:endidx-1], in_index ? endidx : endidx-1
    end
end

end  # module
