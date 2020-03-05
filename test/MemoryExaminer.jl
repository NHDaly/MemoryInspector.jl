module MemoryExaminerTest
import ..MemoryExaminer

mutable struct StringHolder
    a::String
    b::String
end

s = join(rand('a':'z', 1024*1024)); # 1 MiB string
sh = StringHolder(s, s);

MemoryExaminer.@inspect(sh)
MemoryExaminer.MemorySummarySize.summarysize(sh)

# Humanize.datasize(Base.summarysize(sh), style=:bin)
#
# serialize("/tmp/sh", sh)
# run(`ls -lh /tmp/sh`)  # Size on disk *IS 2MiB!*
#
# sh_deserialized = deserialize("/tmp/sh");  # But somehow the strings are deduplicated when deserialized
# Humanize.datasize(Base.summarysize(sh), style=:bin)

end
