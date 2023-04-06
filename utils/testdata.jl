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

nothing
