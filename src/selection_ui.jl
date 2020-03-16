module SelectionUI

import TerminalMenus
import TerminalMenus: request

using ..MemoryInspector: SelectionOptions

mutable struct InspectMenu <: TerminalMenus.AbstractMenu
    options::Vector{String}
    pagesize::Int
    pageoffset::Int
    selected::Int
    toggle::Union{Nothing, Symbol}
    selected_command::Union{Nothing, SelectionOptions.Option}
    scroll_horizontal::Int
end

function show_as_line(el)
    reduced_displaysize = displaysize(stdout) .- (0, 3)
    buf = IOBuffer()
    show(IOContext(buf, :limit=>true, :displaysize=>reduced_displaysize), el)
    String(take!(buf))
end


function InspectMenu(options; pagesize::Int=10)
    #options = vcat(map(show_as_line, callsites), ["↩"])
    length(options) < 1 && error("InspectMenu must have at least one option")

    # if pagesize is -1, use automatic paging
    pagesize = pagesize == -1 ? length(options) : pagesize
    # pagesize shouldn't be bigger than options
    pagesize = min(length(options), pagesize)
    # after other checks, pagesize must be greater than 1
    pagesize < 1 && error("pagesize must be >= 1")

    pageoffset = 0
    selected = -1 # none

    scroll_horizontal = 0

    InspectMenu(options, pagesize, pageoffset, selected, nothing, nothing, scroll_horizontal)
end

TerminalMenus.options(m::InspectMenu) = m.options
TerminalMenus.cancel(m::InspectMenu) = m.selected = -1

# We don't use header() since we're manually printing a header before invoking the menu.
TerminalMenus.header(m::InspectMenu) = ""

function TerminalMenus.keypress(m::InspectMenu, key::UInt32)
    #if key == UInt32('w')
    #    m.toggle = :warn
    #    return true
    if key == Int(TerminalMenus.ARROW_RIGHT)
        m.scroll_horizontal -= 1
    elseif key == Int(TerminalMenus.ARROW_LEFT)
        m.scroll_horizontal += 1
    elseif key == Int('J')
        m.selected_command = SelectionOptions.JUMP
        return true
    end
    return false
end

function TerminalMenus.pick(menu::InspectMenu, cursor::Int)
    menu.selected = cursor
    return true #break out of the menu
end

function TerminalMenus.writeLine(buf::IOBuffer, menu::InspectMenu, idx::Int, cursor::Bool, term_width::Int)
    cursor_len = length(TerminalMenus.CONFIG[:cursor])
    # print a ">" on the selected entry
    cursor ? print(buf, TerminalMenus.CONFIG[:cursor]) : print(buf, repeat(" ", cursor_len))
    print(buf, " ") # Space between cursor and text

    line = replace(menu.options[idx], "\n" => "\\n")
    line,menu.scroll_horizontal = _custom_trimWidth(line, term_width, cursor, cursor_len, menu.scroll_horizontal)

    print(buf, line)
end

function _custom_trimWidth(str::String, term_width::Int, highlighted=false, pad::Int=2, scroll::Int=0)
    max_str_len = term_width - pad - 5
    str_len = length(str)
    if highlighted
        scroll = min(max(scroll, 0), min(str_len, str_len-max_str_len-pad))
    end
    if str_len <= max_str_len || str_len < 6
        return str, scroll
    end
    if !highlighted
        return string(str[1:max_str_len], ".."), scroll
    else
        if scroll > 0
            return string(str[max(1,end-max_str_len-scroll):max(max_str_len,end-scroll)], ".."), scroll
        else
            return string("..", str[length(str) - max_str_len-scroll:end]), scroll
        end
    end
end

end
