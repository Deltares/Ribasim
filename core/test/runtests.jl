using ReTestItems, Ribasim

path = pwd()
print(path)
if in("integration", ARGS)
    runtests(
        "../integration_test";
        nworkers = min(4, Sys.CPU_THREADS ÷ 2),
        nworker_threads = 2,
    )
else
    runtests("../test"; nworkers = min(4, Sys.CPU_THREADS ÷ 2), nworker_threads = 2)
end
