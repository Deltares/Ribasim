# this script is run during app creation to precompile the code executed in this script
# that way the app will have less latency

using Bach

Bach.run("../../../run/run.toml")
