@testitem "Allocation solve" begin
    using PreallocationTools: get_tmp
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    close(db)

    flow = get_tmp(p.connectivity.flow, 0)
    flow[1, 2] = 4.5 # Source flow
    allocation_model = p.connectivity.allocation_models[1]
    Ribasim.allocate!(p, allocation_model, 0.0)

    F = JuMP.value.(allocation_model.problem[:F])
    @test F ≈ [0.0, 4.0, 0.0, 0.0, 0.0, 4.0]

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 4.0]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]
end

@testitem "Allocation objective types" begin
    using DataFrames: DataFrame
    import JuMP
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.connectivity.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(F[2], F[2]) in keys(objective.terms) # F[2]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(F[3], F[3]) in keys(objective.terms) # F[3]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.connectivity.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    @test objective.aff.constant == 2.0
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(F[2], F[2]) in keys(objective.terms) # F[2]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(F[3], F[3]) in keys(objective.terms) # F[3]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.connectivity.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs in keys(problem.obj_dict)
    F_abs = problem[:F_abs]
    @test objective == F_abs[3] + F_abs[2]

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.connectivity.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs in keys(problem.obj_dict)
    F_abs = problem[:F_abs]
    @test objective == F_abs[3] + F_abs[2]
end
