@testitem "Allocation solve" begin
    using PreallocationTools: get_tmp
    using Ribasim: NodeID
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    close(db)

    graph = p.graph
    Ribasim.set_flow!(graph, NodeID(1), NodeID(2), 4.5) # Source flow
    allocation_model = p.allocation_models[1]
    Ribasim.allocate!(p, allocation_model, 0.0)

    F = JuMP.value.(allocation_model.problem[:F])
    @test F.data ≈ [0.0, 0.5, 0.0, 0.5, 0.0, 0.0]

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 0.5]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]
end

@testitem "Allocation objective types" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(5))],
        F[(NodeID(4), NodeID(5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(6))],
        F[(NodeID(4), NodeID(6))],
    ) in keys(objective.terms) # F[4,6]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    @test objective.aff.constant == 2.0
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(5))],
        F[(NodeID(4), NodeID(5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(6))],
        F[(NodeID(4), NodeID(6))],
    ) in keys(objective.terms) # F[4,6]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs in keys(problem.obj_dict)
    F_abs = problem[:F_abs]
    @test string(objective) == string(
        0.125 * F[(NodeID(4), NodeID(6))] +
        0.125 * F[(NodeID(1), NodeID(2))] +
        0.125 * F[(NodeID(4), NodeID(5))] +
        0.125 * F[(NodeID(2), NodeID(4))] +
        F_abs[NodeID(5)] +
        F_abs[NodeID(6)],
    )

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs in keys(problem.obj_dict)
    F_abs = problem[:F_abs]
    @test string(objective) == string(
        62.585499316005475 * F[(NodeID(4), NodeID(6))] +
        62.585499316005475 * F[(NodeID(1), NodeID(2))] +
        62.585499316005475 * F[(NodeID(4), NodeID(5))] +
        62.585499316005475 * F[(NodeID(2), NodeID(4))] +
        F_abs[NodeID(5)] +
        F_abs[NodeID(6)],
    )
end
