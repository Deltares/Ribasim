# Read daily KNMI precipitation into a forcing Arrow table for Ribasim.

using TOML, Arrow, CSV, Dates, DataFrames

config = TOML.parsefile("run.toml")
lsw_ids = config["lsw_ids"]
df = CSV.read("data/input/vanHuite/hupsel_2019-2020.csv", DataFrame, copycols = true)
time = DateTime.(df.time)
# RH and EV24 are in meters per day, and need to be converted to meters per second
precipitation = df.RH ./ 86400
evaporation = df.EV24 ./ 86400
nloc = length(lsw_ids)
ntime = length(time)

# Per timestep, put all locations together. They all share the same values, so there
# is 130x repetition here.
df_precipitation = DataFrame(time = repeat(time; inner = nloc), variable = :precipitation,
                             location = repeat(lsw_ids; outer = ntime),
                             value = repeat(precipitation; inner = nloc))
df_evaporation = DataFrame(time = repeat(time; inner = nloc), variable = :evaporation,
                           location = repeat(lsw_ids; outer = ntime),
                           value = repeat(evaporation; inner = nloc))
forcing = vcat(df_precipitation, df_evaporation)
sort!(forcing, :time)

forcing.variable = Arrow.DictEncode(forcing.variable)
forcing.location = Arrow.DictEncode(forcing.location)
Arrow.write("data/input/vanHuite/forcing-hupsel_2019-2020.arrow", forcing)
