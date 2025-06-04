using TestItemRunner: @testmodule

@testmodule Teamcity begin
    import Test: Test, record, finish
    using Test: AbstractTestSet, Result, Pass, Fail, Error
    using Test: get_testset_depth, get_testset
    struct TeamcityTestSet <: Test.AbstractTestSet
        description::AbstractString
        teamcity::Bool
        results::Vector
        # constructor takes a description string and options keyword arguments
        function TeamcityTestSet(desc; teamcity = haskey(ENV, "TEAMCITY_VERSION"))
            teamcity && println("##teamcity[testSuiteStarted name='$desc']")
            new(desc, teamcity, [])
        end
    end

    function record(ts::TeamcityTestSet, child::AbstractTestSet)
        push!(ts.results, child)
    end
    function record(ts::TeamcityTestSet, res::Result)
        ts.teamcity && println("##teamcity[testStarted name='$(res.orig_expr)']")
        ts.teamcity && printtcresult(res)
        ts.teamcity && println("##teamcity[testFinished name='$(res.orig_expr)']")
        push!(ts.results, res)
    end
    function finish(ts::TeamcityTestSet)
        # just record if we're not the top-level parent
        if get_testset_depth() > 0
            record(get_testset(), ts)
            ts.teamcity && println("##teamcity[testSuiteFinished name='$(ts.description)']")
            return ts
        end

        # so the results are printed if we are at the top level
        Test.print_test_results(ts)
        return ts
    end

    printtcresult(_::Test.Pass) = nothing
    printtcresult(_::Test.Broken) = nothing  # Teamcity does not support broken tests
    printtcresult(res::Test.Fail) =
        println("##teamcity[testFailed name='$(res.orig_expr)' message='$(res)']")
    printtcresult(res::Test.Error) =
        println("##teamcity[testFailed name='$(res.orig_expr)' message='$(res)']")
end

macro tcstatus(message)
    if haskey(ENV, "TEAMCITY_VERSION")
        return esc(:(println("##teamcity[buildStatus text='", $message, "']")))
    else
        return esc(:(println($message)))
    end
end

macro tcstatistic(key, value)
    if haskey(ENV, "TEAMCITY_VERSION")
        return esc(
            :(println(
                "##teamcity[buildStatisticValue key='",
                $key,
                "' value='",
                $value,
                "']",
            )),
        )
    else
        return esc(:(println($key, '=', $value)))
    end
end
