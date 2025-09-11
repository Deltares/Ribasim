using TestItemRunner

include("utils.jl")

function test_type(item)::Bool
    dir = basename(dirname(item.filename))
    is_integration = dir == "integration_test"
    is_regression = dir == "regression_test"
    if in("integration", ARGS)
        is_integration
    elseif in("regression", ARGS)
        is_regression
    elseif in("skip", ARGS)
        false
    else
        !is_integration && !is_regression
    end
end

@run_package_tests filter = test_type
