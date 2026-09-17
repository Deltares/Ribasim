@testitem "UnitRange" begin
    using Ribasim.CVectors: CVector, getdata, getaxes
    data = [1.0, 2.0, 3.0]
    axes = (a = 1:1, b = 2:3)
    x = CVector(data, axes)
    @test x isa CVector{Float64}
    @test x isa DenseVector{Float64}
    @test length(x) == 3
    @test size(x) == (3,)
    @test x[1] == 1.0
    @test x[2] == 2.0
    @test x[3] == 3.0
    @test x.a isa SubArray
    @test x.b isa SubArray
    @test getdata(x) === data
    @test getaxes(x) === axes
    @test keys(x) === (:a, :b)
    @inferred getproperty(x, :a)
    @test similar(x) isa CVector{Float64}
    @test similar(x, Int) isa CVector{Int}
    @test similar(x, 2, 3) isa Matrix{Float64}
    @test similar(x, Int, 2, 3) isa Matrix{Int}
    @test iterate(x) === (1.0, 2)

    @test map(identity, x) isa CVector{Float64}
    @test map!(identity, similar(data), x) isa Vector{Float64}
    @test map!(identity, similar(x), x) isa CVector{Float64}
end

@testitem "Int" begin
    using Ribasim.CVectors: CVector
    data = [1.0, 2.0, 3.0]
    axes = (a = 1, b = 2:3)
    x = CVector(data, axes)
    @test x.a === 1.0
    @test x.b isa SubArray
    @test x.b == [2.0, 3.0]
    FloatView = SubArray{Float64, 1, Vector{Float64}, Tuple{UnitRange{Int64}}, true}
    @inferred Union{Float64, FloatView} getproperty(x, :a)
    @inferred Union{Float64, FloatView} getproperty(x, :b)
end

@testitem "Nested" begin
    using Ribasim.CVectors: CVector, getdata, getaxes
    data = [1.0, 2.0, 3.0]
    axes = (; a = (; b = 1, c = 2:3))
    x = CVector(data, axes)
    xa = x.a
    @test xa isa CVector
    @test length(xa) == 3
    @test getdata(xa) === data
    @test getaxes(xa) === axes.a
    error = @test_throws ErrorException x.b
    @test sprint(showerror, error) == "CVector has no component named :b"
    @test x.a.b === 1.0
    @test x.a.c isa SubArray
    @test x.a.c == [2.0, 3.0]
    @inferred getproperty(x, :a)
    FloatView = SubArray{Float64, 1, Vector{Float64}, Tuple{UnitRange{Int64}}, true}
    @inferred Union{Float64, FloatView} getproperty(xa, :b)
    @inferred Union{Float64, FloatView} getproperty(xa, :c)

    # Test that nested axes with offset ranges have correct length and values
    data2 = collect(1.0:10.0)
    axes2 = (; foo = 1:5, bar = (; a = 6:7, b = 8:10))
    v = CVector(data2, axes2)
    @test length(v.foo) == 5
    @test v.foo == [1.0, 2.0, 3.0, 4.0, 5.0]
    @test length(v.bar) == 5
    @test v.bar isa CVector
    @test getdata(v.bar) === data2
    @test getaxes(v.bar) === axes2.bar
    @test v.bar.a == [6.0, 7.0]
    @test v.bar.b == [8.0, 9.0, 10.0]
    @test length(v.bar.a) == 2
    @test length(v.bar.b) == 3
    # Offset-aware indexing
    @test v.bar[1] == 6.0
    @test v.bar[5] == 10.0
end

@testitem "Contiguity" begin
    using Ribasim.CVectors: CVector
    data = [1.0, 2.0, 3.0, 4.0, 5.0]
    # Gap between 1:2 and 4:5
    @test_throws AssertionError CVector(data, (; a = 1:2, b = 4:5))
    # Overlap between 1:3 and 3:5
    @test_throws AssertionError CVector(data, (; a = 1:3, b = 3:5))
end

@testitem "Construct from axes" begin
    using Ribasim.CVectors: cvector_from_axes, getdata

    axes = (; a = 2:3, b = 4:5)
    x = cvector_from_axes(axes; data_type = Vector{Int})

    @test getdata(x) isa Vector{Int}
    @test length(getdata(x)) == 5
    @test length(x) == 4
end

@testitem "Concatenate axes" begin
    using Ribasim.CVectors: concatenate_axes

    axes = concatenate_axes(
        (; a = 3:4, nested = (; b = 5:6)),
        (; c = 1:2, d = 3:5),
    )

    @test axes == (; a = 1:2, nested = (; b = 3:4), c = 5:6, d = 7:9)
    @test_throws ArgumentError concatenate_axes((; a = 1:2), (; a = 1:3))
    @test concatenate_axes() == NamedTuple()
end
