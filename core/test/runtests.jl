using ReTestItems, Ribasim

name_regex = ifelse("regression" in ARGS, r"^(regression_).*", r"^(?!regression_).*")

runtests(
    Ribasim;
    name = name_regex,
    nworkers = min(4, Sys.CPU_THREADS ÷ 2),
    nworker_threads = 2,
)
