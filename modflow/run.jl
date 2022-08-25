using TOML
include("run-mf6.jl")

cd("c:/src/bach/modflow")
config = TOML.parsefile("c:/src/bach/modflow/couple.toml")
bach_ids = [151358, 151371, 151309]
bach = BachModel()#BMI.initialize(Bach.Register, config)
bme = BachModflowExchange(config, bach_ids);

start_time = BMI.get_start_time(bme.modflow.bmi)
current_time = BMI.get_current_time(bme.modflow.bmi)
end_time = BMI.get_end_time(bme.modflow.bmi)

while current_time < end_time
    update!(bme.modflow)
    current_time = BMI.get_current_time(bme.modflow.bmi)
end
BMI.finalize(bme.modflow.bmi)
