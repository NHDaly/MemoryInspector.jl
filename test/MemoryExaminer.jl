module MemoryExaminerTest
import ..MemoryExaminer

mutable struct Obj{T1,T2}
    a::T1
    b::T2
    Obj{A,B}(a::A,b::B) where {A,B} = new{A,B}(a,b)
    Obj{A,B}(a::A) where {A,B} = new{A,B}(a) # Allow partial construction
    Obj{A,B}() where {A,B} = new{A,B}() # Allow partial construction
    Obj(a::A,b::B) where {A,B} = Obj{A,B}(a,b)
end

s = join(rand('a':'z', 1024*1024)); # 1 MiB string
multistring = Obj(s,s);   # Shared references to large object
selfie = Obj{Obj,Obj}(multistring);
selfie.b = selfie;    # Self-reference

# Not sure how to test an interactive UI like this.
#MemoryExaminer.@inspect selfie
result = MemoryExaminer.MemorySummarySize.summarysize(selfie)

# Humanize.datasize(Base.summarysize(sh), style=:bin)
#
# serialize("/tmp/sh", sh)
# run(`ls -lh /tmp/sh`)  # Size on disk *IS 2MiB!*
#
# sh_deserialized = deserialize("/tmp/sh");  # But somehow the strings are deduplicated when deserialized
# Humanize.datasize(Base.summarysize(sh), style=:bin)

end
