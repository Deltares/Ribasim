const teamcity_presence_env_var = "TEAMCITY_VERSION"

is_running_under_teamcity() = haskey(ENV, teamcity_presence_env_var)

function teamcity_message(name, value)
    println("##teamcity['$name' '$value']")
end

function teamcity_message(name, d::Dict)
    println(
        "##teamcity[$name " *
        string(collect(("'$(key)'='$value' " for (key, value) in pairs(d)))...) *
        "]",
    )
end

# Taken from Julia's testsuite
macro capture_stdout(ex)
    quote
        mktemp() do fname, f
            result = redirect_stdout(f) do
                $(esc(ex))
            end
            seekstart(f)
            output = read(f, String)
            result, output
        end
    end
end

macro capture_stderr(ex)
    quote
        mktemp() do fname, f
            result = redirect_stderr(f) do
                $(esc(ex))
            end
            seekstart(f)
            output = read(f, String)
            result, output
        end
    end
end

nothing
