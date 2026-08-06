using TestItemRunner

include("utils.jl")

function test_type(item)::Bool
    dir = basename(dirname(item.filename))
    is_integration = dir == "integration_test"
    is_regression = dir == "regression_test"

    # Allow selecting individual test items by name: pass "names" followed by the
    # names of the test items to run.
    names_idx = findfirst(==("names"), ARGS)
    if !isnothing(names_idx)
        return item.name in ARGS[(names_idx + 1):end]
    end

    return if in("integration", ARGS)
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
