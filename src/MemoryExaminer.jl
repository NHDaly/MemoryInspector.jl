module MemoryExaminer

using TerminalMenus
using Humanize

"""
    @inspect x

Open an interactive window to explore the sizes of the fields of `x`.
"""
macro inspect(obj)
    :($inspect($(esc(obj)), $(QuoteNode(obj))))
end

inspect(obj) = inspect(obj, "obj")
function inspect(obj, path)
    sz = Base.summarysize(obj)
    println("($path)::$(typeof(obj)) => $(Humanize.datasize(sz))")

    fieldnames = propertynames(obj)
    fields = [_trygetfield(obj, n) for n in fieldnames]
    fieldsizes = ["$fieldname::$(typeof(f)) => $(Humanize.datasize(Base.summarysize(f)))"
        for fieldname in fieldnames
        for f in (fields,)
    ]

    options = fieldsizes
    choice = _get_next_field_from_user(options)
    if choice == UP
        return
    else
        inspect(fields[choice], "$path.$(fieldnames[choice])")
        # When you return Up from choice, rerun this pane
        inspect(obj, path)
    end
end

struct FieldError end
const fielderror = FieldError()
_trygetfield(o, f) = try getfield(o, f) catch; fielderror end


const UP = -2
function _get_next_field_from_user(option_strings)
    option_strings = [option_strings..., "↩"]
    menu = RadioMenu(option_strings, pagesize=4)

    choice = request("Fields:", menu)

    if choice == -1
        println("Menu canceled.")
    elseif choice == length(option_strings)
        UP
    else
        return choice
    end
end


end  # module
