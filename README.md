# MemoryExaminer

[![Build Status](https://travis-ci.com/nhdaly/MemoryExaminer.jl.svg?branch=master)](https://travis-ci.com/nhdaly/MemoryExaminer.jl)

- `MemoryExaminer.@inspect x`

A simple julia REPL tool for examining the sizes of in-memory objects:
```julia
julia> d = Dict(1=>(1,2), 2=>3)
Dict{Int64,Any} with 2 entries:
  2 => 3
  1 => (1, 2)

julia> MemoryExaminer.@inspect d
——————————————————————————————————————————————————————————————————————————————————————
(d)::Dict{Int64,Any} => 480.0 B
Item indices:
   1::Pair{Int64,Any} => 24.0 B
 → 2::Pair{Int64,Any} => 32.0 B
   ↩
——————————————————————————————————————————————————————————————————————————————————————
(d[2])::Pair{Int64,Any} => 32.0 B
Fields:
   first::Int64 => 8.0 B
 → second::Tuple{Int64,Int64} => 16.0 B
   ↩
——————————————————————————————————————————————————————————————————————————————————————
(d[2].second)::Tuple{Int64,Int64} => 16.0 B
Fields:
 → 1::Int64 => 8.0 B
   2::Int64 => 8.0 B
   ↩
```

## Desired Feature Goals
- In-memory deduplication so that internal references don't inflate memory sizes, and each byte is only counted once.
    - Julia's `Base.summarysize()` does this, so we just need to share that logic.
