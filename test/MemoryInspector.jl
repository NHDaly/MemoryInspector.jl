module MemoryInspectorTest
import MemoryInspector
using Test

mutable struct Obj{T1,T2}
    a::T1
    b::T2
    Obj{A,B}(a::A,b::B) where {A,B} = new{A,B}(a,b)
    Obj{A,B}(a::A) where {A,B} = new{A,B}(a) # Allow partial construction
    Obj{A,B}() where {A,B} = new{A,B}() # Allow partial construction
    Obj(a::A,b::B) where {A,B} = Obj{A,B}(a,b)
end

@testset "self-references" begin
    s = join(rand('a':'z', 1024*1024)); # 1 MiB string
    multistring = Obj(s,s);   # Shared references to large object
    selfie = Obj{Obj,Obj}(multistring);
    selfie.b = selfie;    # Self-reference

    # Not sure how to test an interactive UI like this.
    #MemoryInspector.@inspect selfie
    result = MemoryInspector.MemorySummarySize.summarysize(selfie)

    @test result.size == Base.summarysize(selfie)
    @test length(result.children) == 2

    child_sizes = [v.size for (k,v) in result.children]
    # Test that all the bytes are accounted for: the multistring child and the self-reference.
    @test sum(child_sizes) + sizeof(selfie) == result.size  # allocated children + pointers.
    @test Base.summarysize(selfie.a) in child_sizes
    @test 0 in child_sizes  # selfie.b is a self-reference so adds no size besides its pointers.
end

@testset "handles distinct mutable structs with same value" begin
    double_arr = Obj([1,2], [1,2])

    result = MemoryInspector.MemorySummarySize.summarysize(double_arr)
    @test result.size == Base.summarysize(double_arr)
end
@testset "handles distinct immutable structs with same value" begin
    double_arr = Obj((1,2), (1,2))

    result = MemoryInspector.MemorySummarySize.summarysize(double_arr)
    @test result.size == Base.summarysize(double_arr)
end

@testset "Complex Object" begin
    result = MemoryInspector.MemorySummarySize.summarysize(Base)
    # I'm undercounting some things here... I think I'm being over-generous with self-references, 
    # counting things that have the same _value_ but aren't _actually_ self references? I'm not
    # sure though.
    @test_broken result.size == Base.summarysize(Base)
end

end
