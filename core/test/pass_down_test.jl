@testmodule PassDownValidation begin
    using Ribasim
    using Logging
    using Test

    "Construct the model and return the error messages logged during construction."
    function error_messages(model_name::String, error_message::String)::Vector{String}
        toml_path = normpath(@__DIR__, "../../generated_testmodels/$model_name/ribasim.toml")
        @assert ispath(toml_path)
        logger = TestLogger()
        with_logger(logger) do
            @test_throws error_message Ribasim.Model(toml_path)
        end
        return [string(log.message) for log in logger.logs if log.level == Logging.Error]
    end
end

@testitem "PassDown missing fractions" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages(
        "invalid_pass_down_missing_fractions",
        "Errors encountered when parsing PassDown data."
    )
    @test messages ==
        ["At most one PassDown node downstream of Pump #2 can have an unspecified fraction."]
end

@testitem "PassDown fraction sum" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages(
        "invalid_pass_down_fraction_sum",
        "Errors encountered when parsing PassDown data."
    )
    @test messages == [
        "The fractions of the PassDown nodes downstream of Pump #2 must sum to at most 1 when one fraction is unspecified (got 1.25).",
    ]
end

@testitem "PassDown multiple UserDemands" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages(
        "invalid_pass_down_multiple_user_demands",
        "Invalid number of connections for certain node types."
    )
    @test messages == ["PassDown #3 cannot have more than one UserDemand outflow."]
end

@testitem "PassDown only UserDemand" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages(
        "invalid_pass_down_only_user_demand",
        "Invalid number of connections for certain node types."
    )
    @test messages == [
        "PassDown #3 cannot just flow out into a PassDown node, the remainder flow needs somewhere to go.",
    ]
end

@testitem "PassDown UserDemand and other outflow" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages(
        "invalid_pass_down_user_demand_and_other",
        "Invalid number of connections for certain node types."
    )
    @test messages == [
        "PassDown #3 cannot have both a UserDemand outflow and an outflow into a node that is not a PassDown node, the remainder flow must be passed down to PassDown nodes.",
    ]
end

@testitem "PassDown tracers" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/pass_down_tracer/ribasim.toml")
    model = Ribasim.run(toml_path)

    substances = String.(model.integrator.p.p_independent.basin.concentration_data.substances)
    concentration = Ribasim.concentration_data(model; table = false).concentration
    basin_data = Ribasim.basin_data(model) |> DataFrame

    # The mass of a tracer in a Basin that only receives water via the PassDown nodes is the
    # concentration of the water that flows in times the volume that flowed in. The concentration is given at
    # the end of each period, so the storage of the next saved time is used.
    function mass_per_inflow_volume(node_id, basin_idx, substance)
        storage = filter(:node_id => ==(node_id), basin_data).storage
        inflow_volume = storage[2:end] .- storage[1]
        c = concentration[basin_idx, findfirst(==(substance), substances), 1:(end - 1)]
        return c .* storage[2:end] ./ inflow_volume
    end

    # FlowBoundary #1 (0.04 m³/s, Foo = 2) and #2 (0.02 m³/s, no Foo) are mixed in PassDown #3
    # UserDemand #4 abstracts 0.01 m³/s and returns half of it to Basin #6, the remaining
    # 0.05 m³/s flows via PassDown #5 into Basin #7
    c_foo = 2.0 * 0.04 / 0.06
    @test mass_per_inflow_volume(7, 2, "Foo") ≈ fill(c_foo, 59) rtol = 1.0e-8
    @test mass_per_inflow_volume(7, 2, "FlowBoundary") ≈ fill(1.0, 59) rtol = 1.0e-8
    @test all(isapprox.(mass_per_inflow_volume(7, 2, "UserDemand"), 0.0; atol = 1.0e-12))

    # All the mass of the abstracted water is in the return flow, which is only half of the volume
    @test mass_per_inflow_volume(6, 1, "Foo") ≈ fill(2 * c_foo, 59) rtol = 1.0e-8
    @test mass_per_inflow_volume(6, 1, "FlowBoundary") ≈ fill(2.0, 59) rtol = 1.0e-8
    @test mass_per_inflow_volume(6, 1, "UserDemand") ≈ fill(1.0, 59) rtol = 1.0e-8
end

@testitem "PassDown tracers in all configurations" begin
    model = Ribasim.run(normpath(@__DIR__, "../../generated_testmodels/pass_down/ribasim.toml"))
    @test success(model)

    substances = String.(model.integrator.p.p_independent.basin.concentration_data.substances)
    concentration = Ribasim.concentration_data(model; table = false).concentration
    @test all(isfinite, concentration)
    @test all(>=(-1.0e-12), concentration)

    # Basin #4 only receives water from FlowBoundary #1 via PassDown nodes #2 and #3, so
    # the water in it comes from either the initial state or the FlowBoundary
    basin_idx = 1
    @test all(isapprox.(concentration[basin_idx, findfirst(==("Continuity"), substances), :], 1.0))
    initial = concentration[basin_idx, findfirst(==("Initial"), substances), :]
    flow_boundary = concentration[basin_idx, findfirst(==("FlowBoundary"), substances), :]
    @test all(isapprox.(initial + flow_boundary, 1.0))
    @test last(flow_boundary) > 0
end
