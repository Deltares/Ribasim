using Ribasim

toml_path = normpath(@__DIR__, "../generated_testmodels/pump_discrete_control/ribasim.toml")

model_1 = Ribasim.run(toml_path)
