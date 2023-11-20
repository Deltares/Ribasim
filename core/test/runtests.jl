using ReTestItems, Ribasim

runtests(Ribasim; nworkers = min(4, Sys.CPU_THREADS / 2), nworker_threads = 2)
