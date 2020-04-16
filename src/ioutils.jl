module IOUtils

"""
    WriteBlockingIO(buf=0; spawn=false) do io ... end
    WriteBlockingIO(buf=0)

Create a blocking IO object which blocks character entry (when the buffer is full). This is
useful if you have a function that may take a really long time to potentially write
thousands or millions of characters, but you only want the first 10.

If you create the WriteBlockingIO object with an associated function, that function will be
spawned concurrently. If you close the io object, an exception will be thrown on subsequent
writes, killing the spawned Task if unhandled.

# Example
```julia-repl
julia> io = WriteBlockingIO() do io
           println(io, collect(1:1_000_000))
       end
WriteBlockingIO(Channel{UInt8}(sz_max:0,sz_curr:1))

julia> String(take_up_to_n!(io, 10))
"[1, 2, 3, "

julia> close(io)

julia> String(take_up_to_n!(io, 10))
ERROR: ArgumentError: read failed, WriteBlockingIO is already closed.
```
"""
struct WriteBlockingIO <: IO
    ch :: Channel{UInt8}
    WriteBlockingIO(buf=0) = new(Channel{UInt8}(buf))
    function WriteBlockingIO(f::Function, buf=0; spawn=false)
        new(Channel{UInt8}(ch -> f(new(ch)), buf; spawn=spawn))
    end
end

Base.write(io::WriteBlockingIO, c::UInt8) = put!(io.ch, c)
Base.close(io::WriteBlockingIO) = close(io.ch)
Base.isopen(io::WriteBlockingIO) = isopen(io.ch)

Base.take!(io::WriteBlockingIO) = collect(io.ch)
function take_up_to_n!(io::WriteBlockingIO, n)
    if !isopen(io.ch) && !isready(io.ch)
        throw(ArgumentError("read failed, WriteBlockingIO is already closed."))
    end
    out = UInt8[]
    for i in 1:n
        if !isopen(io.ch) && !isready(io.ch) break end
        try
            push!(out, take!(io.ch))
        catch e
            if e isa InvalidStateException
                break
            else
                rethrow()
            end
        end
    end
    out
end

end # module IOUtils
