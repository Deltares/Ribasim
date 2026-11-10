@testmodule JunctionValidation begin
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

@testitem "Junction missing fractions" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_missing_fractions",
        "Errors encountered when parsing Junction data."
    )
    @test messages == [
        "Junction #7 can have at most one outflow link with an unspecified fraction.",
    ]
end

@testitem "Junction fraction sum" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_fraction_sum",
        "Errors encountered when parsing Junction data."
    )
    @test messages == [
        "The fractions of the outflow links of Junction #7 must sum to at most 1 when one fraction is unspecified (got 1.25).",
    ]
end

@testitem "Junction divides without rows" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_divides_without_rows",
        "Errors encountered when parsing Junction data."
    )
    @test messages == [
        "These rows name a Junction without rows in Junction / static that divides the flow over several nodes. Give that Junction rows with fractions as well, or name those nodes in these rows.",
    ]
end

@testitem "Junction with rows into Junctions without rows" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_into_junction/ribasim.toml")
    model = Ribasim.run(toml_path)
    @test success(model)

    flow_data = Ribasim.flow_data(model) |> DataFrame
    flow_rates(from_node_id, to_node_id) =
        filter(row -> row.from_node_id == from_node_id && row.to_node_id == to_node_id, flow_data).flow_rate

    # The rows of Junction #2 name Junctions #4 and #5, which have no rows and were replaced by
    # links to Basin #6 and Basin #7
    @test flow_rates(2, 4) ≈ fill(0.4e-2, 9)
    @test flow_rates(2, 5) ≈ fill(0.6e-2, 9)
    # Junction #4 joins the flow of Junction #2 with FlowBoundary #3
    @test flow_rates(4, 6) ≈ flow_rates(2, 4) .+ flow_rates(3, 4)
    # Junction #5 is a group around Basin #7, which drains via the LinearResistance, so its
    # link to the Basin reports the net flow through the group
    @test flow_rates(5, 7) ≈ flow_rates(2, 5) .- flow_rates(5, 8)
    @test all(>(0), flow_rates(5, 8))
end

@testitem "Junction connector split" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_connector_split",
        "Invalid number of connections for certain node types."
    )
    @test messages == ["Pump #2 can have at most 1 flow outneighbor(s) (got 2)."]
end

@testitem "Junction multiple UserDemands" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_multiple_user_demands",
        "Invalid number of connections for certain node types."
    )
    @test messages == ["Junction #3 cannot have more than one UserDemand outflow."]
end

@testitem "Junction only UserDemand" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_only_user_demand",
        "Invalid number of connections for certain node types."
    )
    @test messages == [
        "Junction #3 cannot only flow out into a UserDemand node, the remainder flow needs somewhere to go.",
    ]
end

@testitem "Junction tracers" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_tracer/ribasim.toml")
    model = Ribasim.run(toml_path)

    substances = String.(model.integrator.p.p_independent.basin.concentration_data.substances)
    concentration = Ribasim.concentration_data(model; table = false).concentration
    basin_data = Ribasim.basin_data(model) |> DataFrame

    # The mass of a tracer in a Basin that only receives water via the Junction nodes is the
    # concentration of the water that flows in times the volume that flowed in. The concentration is given at
    # the end of each period, so the storage of the next saved time is used.
    function mass_per_inflow_volume(node_id, basin_idx, substance)
        storage = filter(:node_id => ==(node_id), basin_data).storage
        inflow_volume = storage[2:end] .- storage[1]
        c = concentration[basin_idx, findfirst(==(substance), substances), 1:(end - 1)]
        return c .* storage[2:end] ./ inflow_volume
    end

    # FlowBoundary #1 (0.04 m³/s, Foo = 2) and #2 (0.02 m³/s, no Foo) are mixed in Junction #3
    # UserDemand #4 abstracts 0.01 m³/s and returns half of it to Basin #6, the remaining
    # 0.05 m³/s flows into Basin #7
    c_foo = 2.0 * 0.04 / 0.06
    @test mass_per_inflow_volume(7, 2, "Foo") ≈ fill(c_foo, 59) rtol = 1.0e-8
    @test mass_per_inflow_volume(7, 2, "FlowBoundary") ≈ fill(1.0, 59) rtol = 1.0e-8

    # The return flow has the concentration of the abstracted water, like for a UserDemand
    # abstracting from a Basin, so the mass in the consumed half leaves the model
    @test mass_per_inflow_volume(6, 1, "Foo") ≈ fill(c_foo, 59) rtol = 1.0e-8
    @test mass_per_inflow_volume(6, 1, "FlowBoundary") ≈ fill(1.0, 59) rtol = 1.0e-8
    # The Continuity tracer stays 1, as the initial water has it as well
    @test concentration[1, findfirst(==("Continuity"), substances), :] ≈ fill(1.0, 60) rtol = 1.0e-8
end

@testitem "Junction tracers in all configurations" begin
    model = Ribasim.run(normpath(@__DIR__, "../../generated_testmodels/junction_fraction/ribasim.toml"))
    @test success(model)

    substances = String.(model.integrator.p.p_independent.basin.concentration_data.substances)
    concentration = Ribasim.concentration_data(model; table = false).concentration
    @test all(isfinite, concentration)
    @test all(>=(-1.0e-12), concentration)

    # Basin #4 only receives water from FlowBoundary #1 via Junction #22, so
    # the water in it comes from either the initial state or the FlowBoundary
    basin_idx = 2
    @test all(isapprox.(concentration[basin_idx, findfirst(==("Continuity"), substances), :], 1.0))
    initial = concentration[basin_idx, findfirst(==("Initial"), substances), :]
    flow_boundary = concentration[basin_idx, findfirst(==("FlowBoundary"), substances), :]
    @test all(isapprox.(initial + flow_boundary, 1.0))
    @test last(flow_boundary) > 0
end

@testitem "Junction confluence" begin
    using DataFrames: DataFrame

    model = Ribasim.run(normpath(@__DIR__, "../../generated_testmodels/junction_fraction/ribasim.toml"))
    @test success(model)

    flow_data = Ribasim.flow_data(model) |> DataFrame
    flow_rates(from_node_id, to_node_id) =
        filter(row -> row.from_node_id == from_node_id && row.to_node_id == to_node_id, flow_data).flow_rate

    # Junction #25 receives the flow from Junction #23 and #6 and passes all of it on to Basin #11
    @test flow_rates(25, 11) ≈ flow_rates(23, 25) .+ flow_rates(6, 25)
    @test all(>(0), flow_rates(25, 11))

    # Junction #22 divides the flow of FlowBoundary #1 over Basin #4 and #3 by the fractions of these links
    @test flow_rates(22, 4) ≈ 0.75 .* flow_rates(1, 22)
    @test flow_rates(22, 3) ≈ 0.25 .* flow_rates(1, 22)

    # Junction #23 divides the flow of Pump #5 over Junction #6 and #25
    @test flow_rates(23, 6) ≈ 0.6 .* flow_rates(5, 23)
    @test flow_rates(23, 25) ≈ 0.4 .* flow_rates(5, 23)
end

@testitem "FlowBoundary time series through Junction" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_flow_boundary/ribasim.toml")
    model = Ribasim.run(toml_path)
    @test success(model)
    # The Basin behind the Junction gets its share of the exact cumulative boundary flow,
    # so the block interpolated series costs no more steps than straight into a Basin.
    # When the flow into the Junction was a state, it took about 130 accepted and 90 rejected steps.
    @test model.integrator.stats.naccept < 60
    @test model.integrator.stats.nreject < 10

    # A flow rate set via BMI takes precedence over the time series
    model = BMI.initialize(Ribasim.Model, toml_path)
    storage = BMI.get_value_ptr(model, "basin.storage")
    storage_start = only(storage)
    BMI.get_value_ptr(model, "flow_boundary.flow_rate") .= 5.0e-3
    BMI.update_until(model, 86400.0)
    @test only(storage) - storage_start ≈ 5.0e-3 * 86400.0
end

@testitem "Junction chain without Basin" begin
    using DataFrames: DataFrame
    using Statistics: mean

    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_no_basin/ribasim.toml")
    model = Ribasim.run(toml_path)
    @test success(model)
    @test isempty(model.integrator.p.p_independent.basin.node_id)

    flow_data = Ribasim.flow_data(model) |> DataFrame
    mean_flow_rate(from_node_id, to_node_id) = mean(
        filter(row -> row.from_node_id == from_node_id && row.to_node_id == to_node_id, flow_data).flow_rate,
    )
    # Without allocation the upstream UserDemand #3 takes its full demand first, although
    # UserDemand #6 downstream has the higher demand priority
    @test mean_flow_rate(1, 2) ≈ 1.0e-3
    @test mean_flow_rate(2, 3) ≈ 1.0e-3
    @test mean_flow_rate(5, 6) ≈ 0.0 atol = 1.0e-12
    @test mean_flow_rate(5, 9) ≈ 0.0 atol = 1.0e-12

    # Allocation needs a Basin in the subnetwork
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/invalid_junction_no_basin_allocation/ribasim.toml",
    )
    @test_throws "Allocation subnetwork 2 has no Basin, which is not supported." Ribasim.Model(toml_path)
end

@testitem "Downstream level through Junction nodes" begin
    using DataFrames: DataFrame
    using Statistics: mean

    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_level/ribasim.toml")
    model = Ribasim.run(toml_path)
    @test success(model)
    flow_data = Ribasim.flow_data(model) |> DataFrame
    mean_flow_rate(from_node_id, to_node_id) = mean(
        filter(row -> row.from_node_id == from_node_id && row.to_node_id == to_node_id, flow_data).flow_rate,
    )

    # Outlet #2 sees the level of Basin #4 behind Junction #3, which is above its max_downstream_level
    @test mean_flow_rate(2, 3) ≈ 0.0 atol = 1.0e-10
    # Outlet #5 has free outflow, since Junction #6 divides the flow over two Basins
    @test mean_flow_rate(5, 6) ≈ 1.0e-3
    @test mean_flow_rate(6, 7) ≈ 0.5e-3
    @test mean_flow_rate(6, 8) ≈ 0.5e-3
end

@testitem "Junction at subnetwork boundary" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_junction_subnetwork_boundary",
        "Errors detected in connections between primary network and subnetworks."
    )
    @test messages == ["Junction nodes at the boundary between subnetworks are not supported."]
end

@testitem "Subnetwork flows into primary network" setup = [JunctionValidation] begin
    messages = JunctionValidation.error_messages(
        "invalid_subnetwork_to_primary",
        "Errors detected in connections between primary network and subnetworks."
    )
    @test messages ==
        ["This node flows from a subnetwork into the primary network, which is not supported."]
end

@testitem "Junction allocation" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_allocation/ribasim.toml")
    model = Ribasim.run(toml_path)
    @test success(model)

    allocation_flow_data = Ribasim.allocation_flow_data(model) |> DataFrame
    flow_data = Ribasim.flow_data(model) |> DataFrame
    mean_flow_rate(df, from_node_id, to_node_id) = begin
        rates = filter(row -> row.from_node_id == from_node_id && row.to_node_id == to_node_id, df).flow_rate
        sum(rates) / length(rates)
    end

    # FlowBoundary #3 (3e-3 m³/s) and Pump #2 (2e-3 m³/s) flow into Junction #4. UserDemand #5
    # abstracts its full demand of 4e-3 m³/s, and the remaining 1e-3 m³/s is divided 70% / 30%
    # over Basin #8 and #9. Half of the abstraction returns via Junction #10
    expected = Dict(
        (2, 4) => 2.0e-3,
        (3, 4) => 3.0e-3,
        (4, 5) => 4.0e-3,
        (4, 8) => 0.7e-3,
        (4, 9) => 0.3e-3,
        (5, 10) => 2.0e-3,
        (10, 11) => 2.0e-3,
    )
    for ((from_node_id, to_node_id), flow_rate) in expected
        # The allocation problem
        @test mean_flow_rate(allocation_flow_data, from_node_id, to_node_id) ≈ flow_rate rtol = 1.0e-5
        # The physical layer, which follows the allocated UserDemand flow
        @test mean_flow_rate(flow_data, from_node_id, to_node_id) ≈ flow_rate rtol = 1.0e-5
    end

    # With a demand of 8e-3 m³/s UserDemand #5 gets at most the 5e-3 m³/s inflow of Junction #4,
    # without negative flows to Basin #8 and #9
    toml_path = normpath(@__DIR__, "../../generated_testmodels/junction_allocation_shortage/ribasim.toml")
    model = Ribasim.run(toml_path)
    @test success(model)
    allocation_data = Ribasim.allocation_data(model) |> DataFrame
    @test all(allocation_data.allocated .≈ 5.0e-3)
    allocation_flow_data = Ribasim.allocation_flow_data(model) |> DataFrame
    @test all(>=(0), allocation_flow_data.flow_rate)
    @test mean_flow_rate(allocation_flow_data, 4, 5) ≈ 5.0e-3 rtol = 1.0e-5
end
