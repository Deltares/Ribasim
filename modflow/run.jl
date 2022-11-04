using TOML
include("../Ribasim/src/modflow.jl")
import BasicModelInterface as BMI

# Standard run
cd("c:/src/ribasim/modflow")
config = TOML.parsefile("c:/src/ribasim/modflow/couple.toml")
#ribasim_ids = [151358]#, 151371, 151309]
ribasim_ids = [200164]
rme = RibasimModflowExchange(config["modflow6"], ribasim_ids);
start_time = BMI.get_start_time(rme.modflow.bmi)
current_time = BMI.get_current_time(rme.modflow.bmi)
end_time = BMI.get_end_time(rme.modflow.bmi)

firststep = true
while current_time < end_time
    update!(rme.modflow, firststep)
    firststep = false
    current_time = BMI.get_current_time(rme.modflow.bmi)
end
BMI.finalize(rme.modflow.bmi)

# Run, but with volumes of 0: should result in no infiltration
cd("c:/src/ribasim/modflow")
config = TOML.parsefile("c:/src/ribasim/modflow/couple.toml")
ribasim_ids = [151358]#, 151371, 151309]
ribasim = RibasimModel()#BMI.initialize(Ribasim.Register, config)
rme = RibasimModflowExchange(config, ribasim_ids);
start_time = BMI.get_start_time(rme.modflow.bmi)
current_time = BMI.get_current_time(rme.modflow.bmi)
end_time = BMI.get_end_time(rme.modflow.bmi)

firststep = true
while current_time < end_time
    exchange_ribasim_to_modflow!(rme)
    update!(rme.modflow, firststep)
    firststep = false
    current_time = BMI.get_current_time(rme.modflow.bmi)
end
BMI.finalize(rme.modflow.bmi)
