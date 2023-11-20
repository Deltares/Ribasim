using ReTestItems, Ribasim

runtests(Ribasim; nworkers = min(4, Sys.CPU_THREADS))
