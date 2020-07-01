# Most of this file was copied from the PProf.jl package, and then adapted to
# export a profile of the current memory usage for a given object, via
# `MemorySummarySize.summarysize()` from this package.
# This code is pretty hacky, and I could probably do a better job re-using
# logic from the PProf package, but :shrug:.


# Import the PProf generated protobuf types from the PProf package:
import PProf
import PProf.perftools.profiles: ValueType, Sample, Function, Location, Line, Label
const PProfile = PProf.perftools.profiles.Profile

using ProtoBuf
using OrderedCollections

using MemoryInspector.MemorySummarySize: FieldResult


struct FieldTraversalNode
    path::String
    parent_field::Union{Nothing,FieldResult}
    name::String
    field::FieldResult
end


# Resolves from `key` to the index (zero-based) in the dict.
# Useful for the Strings table
# 
# NOTE: We must use Int64 throughout this package (regardless of system word-size) b/c the
# proto file specifies 64-bit integers.
function _enter!(dict::OrderedDict{T, Int64}, key::T) where T
    if haskey(dict, key)
        return dict[key]
    else
        l = Int64(length(dict))
        dict[key] = l
        return l
    end
end

using Base.StackTraces: StackFrame

# TODO:
# - Mappings

"""
    @pprof [kwargs...] object
    @pprof webport=62261 out="mem-inspect-profile" [...] object

Collects detailed breakdown of the recursive size information for `object`, via
the functionality provided by MemoryInspector.jl, and exports it to a profile in the
`pprof` format, and (optionally) opens a `pprof` web-server for interactively
viewing the results using the PProf.jl package.

The following flags are available, copied from the PProf.jl package:

If `web=true`, the web-server is opened in the background. Re-running `@pprof()` will refresh
the web-server to use the new output.

If you manually edit the output file or want to point at an existing profile object,
`PProf.refresh()` will refresh the server without overwriting the output file.
`PProf.kill()` will kill the server.

# Arguments:
- `object`: The object (or expression) whose size information you want to profile.

# Keyword Arguments
- `web::Bool`: Whether to launch the `go tool pprof` interactive webserver for viewing results.
- `webhost::AbstractString`: If using `web`, which host to launch the webserver on.
- `webport::Integer`: If using `web`, which port to launch the webserver on.
- `out::String`: Filename for output.
- `drop_frames`: frames with function_name fully matching regexp string will be dropped from the samples,
                 along with their successors.
- `keep_frames`: frames with function_name fully matching regexp string will be kept, even if it matches drop_functions.
- `ui_relative_percentages`: Passes `-relative_percentages` to pprof. Causes nodes
  ignored/hidden through the web UI to be ignored from totals when computing percentages.
"""
macro pprof(exs...)
    args = exs[1:end-1]
    e = exs[end]
    :(_pprof($(string(e)), $(esc(e)); $((esc(a) for a in args)...)))
end

function _pprof(top_level_path::String, @nospecialize(obj),
               ;
               web::Bool = true,
               webhost::AbstractString = "localhost",
               webport::Integer = 62261,  # Use a different port than PProf (chosen via rand(33333:99999))
               out::AbstractString = "mem-inspect-profile.pb.gz",
               #from_c::Bool = true,
               drop_frames::Union{Nothing, AbstractString} = nothing,
               keep_frames::Union{Nothing, AbstractString} = nothing,
               ui_relative_percentages::Bool = true,
            )
    field_summary = MemorySummarySize.summarysize(obj, parentname=top_level_path)

    period = UInt64(0x1)

    @assert !isempty(basename(out)) "`out=` must specify a file path to write to. Got unexpected: '$out'"
    if !endswith(out, ".pb.gz")
        out = "$out.pb.gz"
        @info "Writing output to $out"
    end

    string_table = OrderedDict{AbstractString, Int64}()
    enter!(string) = _enter!(string_table, string)
    enter!(::Nothing) = _enter!(string_table, "nothing")
    ValueType!(_type, unit) = ValueType(_type = enter!(_type), unit = enter!(unit))

    # Setup:
    enter!("")  # NOTE: pprof requires first entry to be ""
    # Functions need a uid, we'll use the pointer for the method instance
    seen_funcs = Set{UInt64}()
    funcs = Dict{UInt64, Function}()

    seen_locs = Set{UInt64}()
    locs  = Dict{UInt64, Location}()

    sample_type = [
        ValueType!("instances", "count"), # Mandatory
        ValueType!("size", "bytes")
    ]

    prof = PProfile(
        sample = [], location = [], _function = [],
        mapping = [], string_table = [],
        sample_type = sample_type, default_sample_type = 2, # size
        period = period, period_type = ValueType!("heap", "bytes")
    )

    if drop_frames !== nothing
        prof.drop_frames = enter!(drop_frames)
    end
    if keep_frames !== nothing
        prof.keep_frames = enter!(keep_frames)
    end

    # Mappings to PProf:
    #  Type of the element => Function
    #  instance objectid => IP
    #  path to the element => Stack Trace

    # start decoding backtraces
    location_ids = Vector{UInt64}()
    nodes_stack = Vector{Union{Nothing,FieldTraversalNode}}()
    # start with the root node argument.
    push!(nodes_stack, FieldTraversalNode("", nothing, top_level_path, field_summary))

    while !isempty(nodes_stack)
        node = pop!(nodes_stack)
        if node === nothing
            # nothing means we've finished iterating all children of a node, and are popping
            # up to the parent.
            pop!(location_ids)
            continue
        end
        field = node.field

        # At each node in the tree, we create an entry for that element
        if node.parent_field === nothing  # Special-case the first node
            path = node.name
        else
            path = MemoryInspector._path_str(node.path, node.parent_field, node.name)
        end

        ip = field.objectid

        # A backtrace consists of a set of IP (Instruction Pointers), each IP points
        # a single line of code and `litrace` has the necessary information to decode
        # that IP to a specific frame (or set of frames, if inlining occured).

        # if we have already seen this IP avoid decoding it again
        #if ip in seen_locs
        #    push!(location_ids, ip)
        #    continue
        #end
        #push!(seen_locs, ip)

        # Decode the IP into information about this stack frame (or frames given inlining)
        location = Location(;line=[])

        # Record a new frame for this object instance
        begin
            frame = field.type

            if ip == 0
                ip = UInt64(frame.uid)
            end
            location.address = UInt64(frame.uid)
            location.id = ip
            # TODO: Line numbers? (A line number is required, so we use fake number here)
            push!(location.line, Line(function_id = ip, line = 1))

            # Store the function in our functions dict
            funcProto = Function()
            funcProto.id = ip
            funcProto.name = enter!(string(frame))
            # TODO: Line numbers?
            funcProto.start_line = convert(Int64, 1)
            # TODO: File names?
            # TODO: We could consider generating temp files with the `dump()` of the
            # type? :/ that's not ideal...
            # Or maybe we can find the file from the method table for the type?
            #file = Base.find_source_file(file)
            file = "<nofile>"
            funcProto.filename   = enter!(file)
            funcProto.system_name = funcProto.name
            funcs[ip] = funcProto
        end

        locs[ip] = location
        push!(location_ids, ip)

        begin
            # Record for this element in the struct tree.
            flat_size = field.size - sum([0, (c.size for (_,c) in field.children)...])
            value = [
                1,              # events  TODO: should we actually put the size here instead?
                flat_size,     # size of the element
            ]
            push!(prof.sample, Sample(;
                    label= [Label(key=enter!(""), str=enter!(path))],
                    location_id = reverse(location_ids),
                    value = value,
                ))
        end


        push!(nodes_stack, nothing)
        for (name, child_field) in field.children
            push!(nodes_stack, FieldTraversalNode(path, field, name, child_field))
        end
    end

    # Build Profile
    prof.string_table = collect(keys(string_table))
    # If from_c=false funcs and locs should NOT contain C functions
    prof._function = collect(values(funcs))
    prof.location  = collect(values(locs))

    # Write to disk
    open(out, "w") do io
        writeproto(io, prof)
    end

    if web
        PProf.refresh(webhost = webhost, webport = webport, file = out,
                      ui_relative_percentages = ui_relative_percentages,
        )
    end

    out
end
