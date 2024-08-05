using ReTestItems, Ribasim

if in("integration", ARGS)
    test_type = "../integration_test"
elseif in("regression", ARGS)
    test_type = "../regression_test"
else
    test_type = "."
end

runtests(test_type; nworkers = min(4, Sys.CPU_THREADS ÷ 2), nworker_threads = 2)
