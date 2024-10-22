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
