@testmodule PassDownValidation begin
    using Ribasim
    using Logging
    using Test

    "Construct the model and return the error messages logged during construction."
    function error_messages(model_name::String)::Vector{String}
        toml_path = normpath(@__DIR__, "../../generated_testmodels/$model_name/ribasim.toml")
        @assert ispath(toml_path)
        logger = TestLogger()
        with_logger(logger) do
            @test_throws "Errors encountered when parsing PassDown data." Ribasim.Model(toml_path)
        end
        return [string(log.message) for log in logger.logs if log.level == Logging.Error]
    end
end

@testitem "PassDown missing fractions" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages("invalid_pass_down_missing_fractions")
    @test messages ==
        ["At most one PassDown node downstream of Pump #2 can have an unspecified fraction."]
end

@testitem "PassDown fraction sum" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages("invalid_pass_down_fraction_sum")
    @test messages == [
        "The fractions of the PassDown nodes downstream of Pump #2 must sum to at most 1 when one fraction is unspecified (got 1.25).",
    ]
end

@testitem "PassDown multiple UserDemands" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages("invalid_pass_down_multiple_user_demands")
    @test messages == ["PassDown #3 can have at most 1 UserDemand flow outneighbor (got 2)."]
end

@testitem "PassDown only UserDemand" setup = [PassDownValidation] begin
    messages = PassDownValidation.error_messages("invalid_pass_down_only_user_demand")
    @test messages == [
        "PassDown #3 has only a UserDemand flow outneighbor, but needs another flow outneighbor for the flow that is not abstracted.",
    ]
end
