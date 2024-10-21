macro tcstatus(message)
    if haskey(ENV, "TEAMCITY_VERSION")
        return :(println("##teamcity[message text='", $message, "']"))
    else
        return :(println($message))
    end
end

macro tcstatistic(key, value)
    if haskey(ENV, "TEAMCITY_VERSION")
        return :(println(
            "##teamcity[buildStatisticValue key='",
            $key,
            "' value='",
            $value,
            "']",
        ))
    else
        return :(println($key, "=", $value))
    end
end
