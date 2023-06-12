import Ribasim

toml_path = normpath(@__DIR__, "../../data/pump_control/control.toml")

@testset "pump control" begin
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p

    pump_control_mapping::Dict{Tuple{Int64, String}, NamedTuple} =
        Dict((4, "off") => (flow_rate = 0.0,), (4, "on") => (flow_rate = 1.0e-5,))

    logic_mapping::Dict{Tuple{Int64, String}, String} =
        Dict((5, "TT") => "on", (5, "TF") => "off", (5, "FF") => "on", (5, "FT") => "off")

    @test p.pump.control_mapping == pump_control_mapping
    @test p.control.logic_mapping == logic_mapping
end
