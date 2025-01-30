@testitem "regression_ode_solvers_trivial" begin
    using SciMLBase: successful_retcode
    import Arrow
    using Ribasim

    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)

    solver_list =
        ["QNDF", "Rosenbrock23", "TRBDF2", "Rodas5P", "KenCarp4", "Tsit5", "ImplicitEuler"]
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

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))
                # subgrid_bytes = read(normpath(dirname(toml_path), "results/subgrid_level.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)
                # subgrid = Arrow.Table(subgrid_bytes)

                @testset "Results values" begin
                    @test basin.storage[1] ≈ 1.0f0
                    @test basin.level[1] ≈ 0.044711584f0
                    @test basin.storage[end] ≈ 16.530443267f0
                    @test basin.level[end] ≈ 0.181817438
                    @test flow.flow_rate[1] ≈ basin.outflow_rate[1]
                    @test all(q -> abs(q) < 1e-7, basin.balance_error)
                    @test all(err -> abs(err) < 0.01, basin.relative_error)
                end
            end
        end
    end
end

@testitem "regression_ode_solvers_basic" begin
    using SciMLBase: successful_retcode
    import Arrow
    using Ribasim
    using Statistics
    include(joinpath(@__DIR__, "../test/utils.jl"))

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)

    flow_bytes_bench = read(normpath(@__DIR__, "../../models/benchmark/basic/flow.arrow"))
    basin_bytes_bench = read(normpath(@__DIR__, "../../models/benchmark/basic/basin.arrow"))
    flow_bench = Arrow.Table(flow_bytes_bench)
    basin_bench = Arrow.Table(basin_bytes_bench)

    solver_list = ["QNDF"]
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

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.link_id == flow_bench.edge_id
                @test flow.from_node_id == flow_bench.from_node_id
                @test flow.to_node_id == flow_bench.to_node_id
                @test all(q -> abs(q) < 0.01, flow.flow_rate - flow_bench.flow_rate)

                # Testbench for basin.arrow
                @test basin.time == basin_bench.time
                @test basin.node_id == basin_bench.node_id

                # The storage seems to failing the most, so let's report it for now
                sdiff = basin.storage - basin_bench.storage
                key = "basic.$solver.$sparse_on_off.$autodiff_on_off"
                @tcstatistic "$key.min_diff" minimum(sdiff)
                @tcstatistic "$key.max_diff" maximum(sdiff)
                @tcstatistic "$key.med_diff" median(sdiff)

                @test all(q -> abs(q) < 1.0, basin.storage - basin_bench.storage)
                @test all(q -> abs(q) < 0.5, basin.level - basin_bench.level)
                @test all(q -> abs(q) < 1e-3, basin.balance_error)
                @test all(err -> abs(err) < 2.5, basin.relative_error)
            end
        end
    end
end

@testitem "regression_ode_solvers_pid_control" begin
    using SciMLBase: successful_retcode
    import Arrow
    using Ribasim

    toml_path = normpath(@__DIR__, "../../generated_testmodels/pid_control/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)

    flow_bytes_bench =
        read(normpath(@__DIR__, "../../models/benchmark/pid_control/flow.arrow"))
    basin_bytes_bench =
        read(normpath(@__DIR__, "../../models/benchmark/pid_control/basin.arrow"))
    flow_bench = Arrow.Table(flow_bytes_bench)
    basin_bench = Arrow.Table(basin_bytes_bench)

    # TODO "Rosenbrock23" and "Rodas5P" solver are resulting unsolvable gradients
    solver_list = ["QNDF"]
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

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.link_id == flow_bench.edge_id
                @test flow.from_node_id == flow_bench.from_node_id
                @test flow.to_node_id == flow_bench.to_node_id
                @test all(q -> abs(q) < 0.01, flow.flow_rate - flow_bench.flow_rate)

                # Testbench for basin.arrow
                @test basin.time == basin_bench.time
                @test basin.node_id == basin_bench.node_id
                @test all(q -> abs(q) < 100.0, basin.storage - basin_bench.storage)
                @test all(q -> abs(q) < 0.5, basin.level - basin_bench.level)
                @test all(err -> abs(err) < 1e-3, basin.balance_error)
            end
        end
    end
end

@testitem "regression_ode_solvers_allocation" begin
    using SciMLBase: successful_retcode
    import Arrow
    using Ribasim

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/subnetworks_with_sources/ribasim.toml",
    )
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)

    flow_bytes_bench = read(
        normpath(@__DIR__, "../../models/benchmark/subnetworks_with_sources/flow.arrow"),
    )
    basin_bytes_bench = read(
        normpath(@__DIR__, "../../models/benchmark/subnetworks_with_sources/basin.arrow"),
    )
    flow_bench = Arrow.Table(flow_bytes_bench)
    basin_bench = Arrow.Table(basin_bytes_bench)

    solver_list = ["QNDF"]
    # false sparse or autodiff can cause large differences in result, thus removed
    sparse_on = [true]
    autodiff_on = [true]

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

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.link_id == flow_bench.edge_id
                @test flow.from_node_id == flow_bench.from_node_id
                @test flow.to_node_id == flow_bench.to_node_id

                # Testbench for basin.arrow
                @test basin.time == basin_bench.time
                @test basin.node_id == basin_bench.node_id
            end
        end
    end
end
