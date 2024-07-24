@testitem "regression_ode_solvers_trivial" begin
    using SciMLBase: successful_retcode
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: get_tstops, tsaves

    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)

    # There is no control. That means we don't write the control.arrow,
    # and we remove it if it exists.
    control_path = normpath(dirname(toml_path), "results/control.arrow")
    mkpath(dirname(control_path))
    touch(control_path)
    @test ispath(control_path)
    config = Ribasim.Config(toml_path)

    solver_list =
        ["QNDF", "Rosenbrock23", "TRBDF2", "Rodas5", "KenCarp4", "Tsit5", "ImplicitEuler"]
    sparse_on = [true, false]
    autodiff_on = [true, false]

    @testset "$solver" for solver in solver_list
        @testset "sparse density is $sparse_on_off" for sparse_on_off in sparse_on
            @testset "auto differentiation is $autodiff_on_off" for autodiff_on_off in
                                                                    autodiff_on
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse_on_off,
                    solver_autodiff = autodiff_on_off,
                )
                model = Ribasim.run(config)
                @test model isa Ribasim.Model
                @test successful_retcode(model)
                (; p) = model.integrator

                @test !ispath(control_path)

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))
                # subgrid_bytes = read(normpath(dirname(toml_path), "results/subgrid_level.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)
                # subgrid = Arrow.Table(subgrid_bytes)

                @testset "Results values" begin
                    @test basin.storage[1] ≈ 1.0
                    @test basin.level[1] ≈ 0.044711584
                    @test basin.storage[end] ≈ 16.530443267
                    @test basin.level[end] ≈ 0.181817438
                    @test flow.flow_rate[1] == basin.outflow_rate[1]
                    @test all(q -> abs(q) < 1e-7, basin.balance_error)
                    @test all(q -> abs(q) < 0.01, basin.relative_error)
                end
            end
        end
    end
end

@testitem "regression_ode_solvers_basic" begin
    using SciMLBase: successful_retcode
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: get_tstops, tsaves

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)

    # There is no control. That means we don't write the control.arrow,
    # and we remove it if it exists.
    control_path = normpath(dirname(toml_path), "results/control.arrow")
    mkpath(dirname(control_path))
    touch(control_path)
    @test ispath(control_path)
    config = Ribasim.Config(toml_path)

    flow_bytes_bench = read(normpath(@__DIR__, "../../benchmark/basic/flow.arrow"))
    basin_bytes_bench = read(normpath(@__DIR__, "../../benchmark/basic/basin.arrow"))
    flow_bench = Arrow.Table(flow_bytes_bench)
    basin_bench = Arrow.Table(basin_bytes_bench)

    solver_list =
        ["QNDF", "Rosenbrock23", "TRBDF2", "Rodas5", "KenCarp4", "Tsit5", "ImplicitEuler"]
    sparse_on = [true, false]
    autodiff_on = [true, false]

    @testset "$solver" for solver in solver_list
        @testset "sparse density is $sparse_on_off" for sparse_on_off in sparse_on
            @testset "auto differentiation is $autodiff_on_off" for autodiff_on_off in
                                                                    autodiff_on
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse_on_off,
                    solver_autodiff = autodiff_on_off,
                )
                model = Ribasim.run(config)
                @test model isa Ribasim.Model
                @test successful_retcode(model)
                (; p) = model.integrator

                @test !ispath(control_path)

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.edge_id == flow_bench.edge_id
                @test flow.from_node_type == flow_bench.from_node_type
                @test flow.from_node_id == flow_bench.from_node_id
                @test flow.to_node_type == flow_bench.to_node_type
                @test flow.to_node_id == flow_bench.to_node_id
                @test all(q -> abs(q) < 0.01, flow.flow_rate - flow_bench.flow_rate)

                # Testbench for basin.arrow
                @test basin.time == basin_bench.time
                @test basin.node_id == basin_bench.node_id
                @test all(q -> abs(q) < 1.0, basin.storage - basin_bench.storage)
                @test all(q -> abs(q) < 0.5, basin.level - basin_bench.level)
                @test all(q -> abs(q) < 1e-3, basin.balance_error)
                @test all(q -> abs(q) < 2.5, basin.relative_error)
            end
        end
    end
end

@testitem "regression_ode_solvers_pid_control" begin
    using SciMLBase: successful_retcode
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: get_tstops, tsaves

    toml_path = normpath(@__DIR__, "../../generated_testmodels/pid_control/ribasim.toml")
    @test ispath(toml_path)

    # There is no control. That means we don't write the control.arrow,
    # and we remove it if it exists.
    control_path = normpath(dirname(toml_path), "results/control.arrow")
    mkpath(dirname(control_path))
    touch(control_path)
    @test ispath(control_path)
    config = Ribasim.Config(toml_path)

    flow_bytes_bench = read(normpath(@__DIR__, "../../benchmark/pid_control/flow.arrow"))
    basin_bytes_bench = read(normpath(@__DIR__, "../../benchmark/pid_control/basin.arrow"))
    flow_bench = Arrow.Table(flow_bytes_bench)
    basin_bench = Arrow.Table(basin_bytes_bench)

    #"Rosenbrock23" and "Rodas5" solver are removed due to unsolvable gradients
    solver_list = ["QNDF", "TRBDF2", "KenCarp4", "Tsit5", "ImplicitEuler"]
    sparse_on = [true, false]
    autodiff_on = [true, false]

    @testset "$solver" for solver in solver_list
        @testset "sparse density is $sparse_on_off" for sparse_on_off in sparse_on
            @testset "auto differentiation is $autodiff_on_off" for autodiff_on_off in
                                                                    autodiff_on
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse_on_off,
                    solver_autodiff = true,
                )
                model = Ribasim.run(config)
                @test model isa Ribasim.Model
                @test successful_retcode(model)
                (; p) = model.integrator

                @test !ispath(control_path)

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.edge_id == flow_bench.edge_id
                @test flow.from_node_type == flow_bench.from_node_type
                @test flow.from_node_id == flow_bench.from_node_id
                @test flow.to_node_type == flow_bench.to_node_type
                @test flow.to_node_id == flow_bench.to_node_id
                @test all(q -> abs(q) < 0.01, flow.flow_rate - flow_bench.flow_rate)

                # Testbench for basin.arrow
                @test basin.time == basin_bench.time
                @test basin.node_id == basin_bench.node_id
                @test all(q -> abs(q) < 9.0, basin.storage - basin_bench.storage)
                @test all(q -> abs(q) < 0.5, basin.level - basin_bench.level)
                @test all(q -> abs(q) < 1e-3, basin.balance_error)
                @test all(q -> abs(q) < 2.5, basin.relative_error)
            end
        end
    end
end
