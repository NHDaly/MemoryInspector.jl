# MemoryInspector.jl

[![Build Status](https://travis-ci.com/nhdaly/MemoryInspector.jl.svg?branch=master)](https://travis-ci.com/nhdaly/MemoryInspector.jl)

- `MemoryInspector.@inspect x`

An interactive tool for exploring the sizes of julia objects:
```julia
julia> d = Dict(1=>(1,2), 2=>3)
Dict{Int64,Any} with 2 entries:
  2 => 3
  1 => (1, 2)

julia> MemoryInspector.@inspect d
—————————————————————————————————————————————————————————————————————————————————————————————————————————
Select a field to recurse into or ↩ to ascend. [q]uit.

Commands: [J]ump to field path.
Toggles: [v]alue of the current field.

(d)::Dict{Int64,Any} => 480.0 B
   64.0 B internal
3 Allocated Fields:
 → vals::Array{Any,1} => 192.0 B
   keys::Array{Int64,1} => 168.0 B
   slots::Array{UInt8,1} => 56.0 B
   ↩
—————————————————————————————————————————————————————————————————————————————————————————————————————————
Select a field to recurse into or ↩ to ascend. [q]uit.

Commands: [J]ump to field path.
Toggles: [v]alue of the current field.

(d.vals)::Array{Any,1} => 192.0 B
   168.0 B internal
2 Allocated Indexes:
 → 16::Tuple{Int64,Int64} => 16.0 B
   6::Int64 => 8.0 B
   ↩
—————————————————————————————————————————————————————————————————————————————————————————————————————————
Select a field to recurse into or ↩ to ascend. [q]uit.

Commands: [J]ump to field path.
Toggles: [v]alue of the current field.

(d.vals[16])::Tuple{Int64,Int64} => 16.0 B
0 Allocated Indexes:
 → ↩

—————————————————————————————————————————————————————————————————————————————————————————————————————————
Select a field to recurse into or ↩ to ascend. [q]uit.

Commands: [J]ump to field path.
Toggles: [v]alue of the current field.

(1, 2) => 16.0 B
0 Allocated Indexes:
 → ↩

```

## Featuring *True Size Accounting!*
Importantly (like `Base.summarysize(x)`) `@inspect x` is able to account for self-references
and shared references inside of objects, so that only the true sizes of fields are
displayed! This allows you to correctly investigate the size of truly complex objects.

For example:
```julia
julia> mutable struct Obj{T1,T2}
           a::T1
           b::T2
           Obj{A,B}(a::A,b::B) where {A,B} = new{A,B}(a,b)
           Obj{A,B}(a::A) where {A,B} = new{A,B}(a) # Allow partial construction
           Obj{A,B}() where {A,B} = new{A,B}() # Allow partial construction
           Obj(a::A,b::B) where {A,B} = Obj{A,B}(a,b)
       end

julia> s = join(rand('a':'z', 1024*1024)); # 1 MiB string

julia> multistring = Obj(s,s);   # Shared references to large object

julia> selfie = Obj{Obj,Obj}(multistring);

julia> selfie.b = selfie;    # Self-reference

julia> MemoryInspector.@inspect selfie
———————————————————————————————————————————————————
(selfie)::Obj{Obj,Obj} => 1.0 MiB
2 Fields:
   a::Obj{String,String} => 1.0 MiB
 → b::Obj{Obj,Obj} => <self-reference>
   ↩
———————————————————————————————————————————————————
(selfie.b)::Obj{Obj,Obj} => <self-reference>
0 Fields:
 → ↩

———————————————————————————————————————————————————
(selfie)::Obj{Obj,Obj} => 1.0 MiB
2 Fields:
 → a::Obj{String,String} => 1.0 MiB
   b::Obj{Obj,Obj} => <self-reference>
   ↩
———————————————————————————————————————————————————
(selfie.a)::Obj{String,String} => 1.0 MiB
2 Fields:
 → a::String => 1.0 MiB
   b::String => <self-reference>
   ↩
———————————————————————————————————————————————————
(selfie.a.a)::String => 1.0 MiB
0 Fields:
 → ↩
```

Note that this does mean that sometimes the bytes may be accounted for in a sub-reference
that may not match your expectations. This tradeoff between breadth-first and depth-first
searching is something we should investigate tuning in the future!

## Inspecting Memory via graph and flamegraph layouts:

We support exporting to a PProf profile, via `MemoryInspector.@mem_pprof`:

```julia
julia> d = Dict(1=>2, 2=>"hello", 3=>"hi", ("hi",2)=>3)
Dict{Any,Any} with 4 entries:
  2         => "hello"
  3         => "hi"
  ("hi", 2) => 3
  1         => 2

julia> MemoryInspector.@mem_pprof web=true webport=23222 d
"mem-inspect-profile.pb.gz"

Serving web UI on http://localhost:23222
```

Graph:

<img width="435" alt="Screen Shot 2020-06-03 at 9 00 58 PM" src="https://user-images.githubusercontent.com/1582097/83703382-70f9dc80-a5dd-11ea-978a-b6f962bab4ed.png">

Flamegraph:

<img width="980" alt="Screen Shot 2020-06-03 at 9 05 35 PM" src="https://user-images.githubusercontent.com/1582097/83703573-01d0b800-a5de-11ea-8e8b-dcddc479b4da.png">



## Desired Features
See this GitHub Issue for some desired features: [#1](https://github.com/NHDaly/MemoryInspector.jl/issues/1)
