# Test the coupling scripts. The test items tagged `:model` need the models built by
# `pixi run wflow-coupled-prepare`, pass the argument `unit` to skip them.

using TestItemRunner

TestItemRunner.run_tests(
    dirname(@__DIR__);
    filter = item -> !("unit" in ARGS && :model in item.tags),
)
