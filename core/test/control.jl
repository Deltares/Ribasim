import Ribasim

@testset "pump discrete control" begin
    toml_path = normpath(@__DIR__, "../../data/pump_control/pump_control.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    control = model.integrator.p.control

    # Control input
    pump_control_mapping::Dict{Tuple{Int64, String}, NamedTuple} =
        Dict((4, "off") => (flow_rate = 0.0,), (4, "on") => (flow_rate = 1.0e-5,))

    logic_mapping::Dict{Tuple{Int64, String}, String} =
        Dict((5, "TT") => "on", (5, "TF") => "off", (5, "FF") => "on", (5, "FT") => "off")

    @test p.pump.control_mapping == pump_control_mapping
    @test p.control.logic_mapping == logic_mapping

    # Control result
    @test control.record.truth_state == ["TF", "FF", "FT"]
    @test control.record.control_state == ["off", "on", "off"]

    level = Ribasim.get_storages_and_levels(model).level
    timesteps = Ribasim.timesteps(model)

    # Control times
    t_1 = control.record.time[2]
    t_1_index = findfirst(timesteps .≈ t_1)
    @test level[1, t_1_index] ≈ control.greater_than[1]

    t_2 = control.record.time[3]
    t_2_index = findfirst(timesteps .≈ t_2)
    @test level[2, t_2_index] ≈ control.greater_than[2]
end

@testset "PID control" begin
    toml_path = normpath(@__DIR__, "../../data/pid_1/pid_1.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    timesteps = Ribasim.timesteps(model) / (60 * 60 * 24)
    level = Ribasim.get_storages_and_levels(model).level[1, :]
    bound = 5 .* exp.(-0.03 .* timesteps)
    @test all(abs.(level .- 5.0) .< bound)
end