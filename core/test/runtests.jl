using ReTestItems, Ribasim

name_regex = ifelse("coverage" in ARGS, r"^(?!integration_).*", nothing)

runtests(
    Ribasim;
    name = name_regex,
    nworkers = min(4, Sys.CPU_THREADS ÷ 2),
    nworker_threads = 2,
)
