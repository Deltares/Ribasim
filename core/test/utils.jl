using TestItemRunner: @testmodule

@testmodule Teamcity begin
    using Dates: DateTime, value, now, canonicalize

    using Test:
        Test,
        AbstractTestSet,
        DefaultTestSet,
        Result,
        Pass,
        Fail,
        Error,
        Broken,
        get_testset,
        get_testset_depth,
        scrub_backtrace
    import Test: finish, record

    mutable struct TeamcityTestSet <: Test.AbstractTestSet
        description::AbstractString
        teamcity::Bool
        time_start::DateTime
        time_end::Union{Nothing, DateTime}
        results::Vector
        showtiming::Bool
        # constructor takes a description string and options keyword arguments
        function TeamcityTestSet(desc; teamcity = haskey(ENV, "TEAMCITY_VERSION"))
            if teamcity
                println("##teamcity[testSuiteStarted name='$desc']")
                flush(stdout)
            end
            new(desc, teamcity, now(), nothing, [], true)
        end
    end
    Base.show(io::IO, ts::TeamcityTestSet) =
        print(io, "TeamcityTestSet(", ts.description, ", teamcity=", ts.teamcity, ")")

    function record(ts::TeamcityTestSet, child::Test.AbstractTestSet)
        push!(ts.results, child)
    end
    function record(ts::TeamcityTestSet, res::Test.Result)
        if ts.teamcity
            println(
                "##teamcity[testStarted name='$(gettctestname(ts))' captureStandardOutput='true']",
            )
            flush(stdout)
            println("##teamcity[testFinished name='$(gettctestname(ts))']")
            flush(stdout)
        end
        push!(ts.results, res)
        res
    end
    function record(ts::TeamcityTestSet, res::Union{Test.Fail, Test.Error})
        if ts.teamcity
            println(
                "##teamcity[testStarted name='$(gettctestname(ts))' captureStandardOutput='true']",
            )
            flush(stdout)
            printtcresult(ts, res)
        end
        print(ts.description, ": ")
        # don't print for interrupted tests
        if !(res isa Test.Error) || res.test_type !== :test_interrupted
            print(res)
            if !isa(res, Test.Error) # if not gets printed in the show method
                Base.show_backtrace(
                    stdout,
                    Test.scrub_backtrace(
                        backtrace(),
                        nothing,
                        Test.extract_file(res.source),
                    ),
                )
            end
            println()
        end
        if ts.teamcity
            println("##teamcity[testFinished name='$(gettctestname(ts))']")
            flush(stdout)
        end
        push!(ts.results, res)
        res
    end

    function finish(ts::TeamcityTestSet)
        # just record if we're not the top-level parent
        ts.time_end = now()
        if ts.teamcity
            println(
                "##teamcity[testSuiteFinished name='$(ts.description)' duration='$(value(now()-ts.time_start))']",
            )
            flush(stdout)
        end
        depth = Test.get_testset_depth()
        if depth != 0
            parent_ts = Test.get_testset()
            Test.record(parent_ts, ts)
            return ts
        end

        # so the results are printed if we are at the top level
        Test.print_test_results(ts)
        ts
    end

    function Test.get_test_counts(ts::TeamcityTestSet)
        passes, fails, errors, broken = 0, 0, 0, 0
        # cumulative results
        c_passes, c_fails, c_errors, c_broken = 0, 0, 0, 0

        for t in ts.results
            # count up results
            isa(t, Pass) && (passes += 1)
            isa(t, Fail) && (fails += 1)
            isa(t, Error) && (errors += 1)
            isa(t, Broken) && (broken += 1)
            # handle children
            if isa(t, AbstractTestSet)
                tc = Test.get_test_counts(t)::TestCounts
                c_passes += tc.passes + tc.cumulative_passes
                c_fails += tc.fails + tc.cumulative_fails
                c_errors += tc.errors + tc.cumulative_errors
                c_broken += tc.broken + tc.cumulative_broken
            end
        end
        # get a duration, if we have one
        duration = Test.format_duration(ts)
        tc = Test.TestCounts(
            true,
            passes,
            fails,
            errors,
            broken,
            c_passes,
            c_fails,
            c_errors,
            c_broken,
            duration,
        )
        return tc
    end
    printtcresult(ts, _::Test.Pass) = nothing
    printtcresult(ts, _::Test.Broken) = nothing  # Teamcity does not support broken tests
    function printtcresult(ts, res::Test.Fail)
        println("##teamcity[testFailed name='$(gettctestname(ts))' message='$(res)']")
        flush(stdout)
    end
    function printtcresult(ts, res::Test.Error)
        println("##teamcity[testFailed name='$(gettctestname(ts))' message='$(res)']")
        flush(stdout)
    end
    gettctestname(ts) = "$(ts.description).$(string(length(ts.results) + 1))"

    Test.results(ts::TeamcityTestSet) = ts.results
    Test.print_verbose(ts::TeamcityTestSet) = true

    function Test.format_duration(ts::TeamcityTestSet)
        (; time_start, time_end) = ts
        isnothing(time_end) && return ""
        string(canonicalize(time_end - time_start))
    end
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
