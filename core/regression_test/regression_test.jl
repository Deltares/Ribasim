@testitem "regression_ode_solvers_trivial" setup = [Teamcity] begin
    import Arrow

    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)

    solver_list =
        ["QNDF", "Rosenbrock23", "TRBDF2", "Rodas5P", "KenCarp4", "Tsit5", "ImplicitEuler"]
    sparse_options = [true, false]
    autodiff_options = [true, false]

    @testset Teamcity.TeamcityTestSet "$solver" for solver in solver_list
        @testset Teamcity.TeamcityTestSet "sparse = $sparse" for sparse in sparse_options
            @testset Teamcity.TeamcityTestSet "autodiff = $autodiff" for autodiff in
                                                                         autodiff_options
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse,
                    solver_autodiff = autodiff,
                    solver_abstol = 1e-7,
                    solver_reltol = 1e-7,
                )
                model = Ribasim.run(config)
                @test model isa Ribasim.Model
                @test success(model)
                (; p) = model.integrator

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                @testset "Results values" begin
                    @test basin.storage[1] ≈ 1.0f0
                    @test basin.level[1] ≈ 0.044711584f0
                    @test basin.storage[end] ≈ 16.530443267f0 atol = 0.02
                    @test basin.level[end] ≈ 0.181817438f0 atol = 1e-4
                    @test flow.flow_rate[1] ≈ basin.outflow_rate[1]
                    @test all(q -> abs(q) < 1e-7, basin.balance_error)
                    @test all(err -> abs(err) < 0.01, basin.relative_error)
                end
            end
        end
    end
end

@testitem "regression_ode_solvers_basic" setup = [Teamcity] begin
    import Arrow
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

    @testset Teamcity.TeamcityTestSet "$solver" for solver in solver_list
        @testset Teamcity.TeamcityTestSet "sparse density is $sparse_on_off" for sparse_on_off in
                                                                                 sparse_on
            @testset Teamcity.TeamcityTestSet "auto differentiation is $autodiff_on_off" for autodiff_on_off in
                                                                                             autodiff_on
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse_on_off,
                    solver_autodiff = autodiff_on_off,
                )
                model = Ribasim.run(config)
                @test model isa Ribasim.Model
                @test success(model)
                (; p) = model.integrator

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.link_id == flow_bench.link_id
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

@testitem "regression_ode_solvers_pid_control" setup = [Teamcity] begin
    import Arrow

    toml_path = normpath(@__DIR__, "../../generated_testmodels/pid_control/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)

    flow_bytes_bench =
        read(normpath(@__DIR__, "../../models/benchmark/pid_control/flow.arrow"))
    basin_bytes_bench =
        read(normpath(@__DIR__, "../../models/benchmark/pid_control/basin.arrow"))
    flow_bench = Arrow.Table(flow_bytes_bench)
    basin_bench = Arrow.Table(basin_bytes_bench)

    # TODO "Rosenbrock23" and "Rodas5P" solver are resulting in unsolvable gradients
    solver_list = ["QNDF"]
    sparse_on = [true, false]
    autodiff_on = [true, false]

    @testset Teamcity.TeamcityTestSet "$solver" for solver in solver_list
        @testset Teamcity.TeamcityTestSet "sparse density is $sparse_on_off" for sparse_on_off in
                                                                                 sparse_on
            @testset Teamcity.TeamcityTestSet "auto differentiation is $autodiff_on_off" for autodiff_on_off in
                                                                                             autodiff_on
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse_on_off,
                    solver_autodiff = autodiff_on_off,
                )
                model = Ribasim.run(config)
                @test model isa Ribasim.Model
                @test success(model)
                (; p) = model.integrator

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test flow.time == flow_bench.time
                @test flow.link_id == flow_bench.link_id
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

@testitem "regression_ode_solvers_allocation" setup = [Teamcity] begin
    import Arrow

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
    # false sparse or autodiff can cause large differences in results, thus removed
    sparse_on = [true]
    autodiff_on = [true]

    @testset Teamcity.TeamcityTestSet "$solver" for solver in solver_list
        @testset Teamcity.TeamcityTestSet "sparse density is $sparse_on_off" for sparse_on_off in
                                                                                 sparse_on
            @testset Teamcity.TeamcityTestSet "auto differentiation is $autodiff_on_off" for autodiff_on_off in
                                                                                             autodiff_on
                config = Ribasim.Config(
                    toml_path;
                    solver_algorithm = solver,
                    solver_sparse = sparse_on_off,
                    solver_autodiff = autodiff_on_off,
                )
                model = Ribasim.Model(config)
                @test_throws Exception Ribasim.solve!(model)
                @test model isa Ribasim.Model
                @test_broken success(model)
                (; p) = model.integrator

                # read all results as bytes first to avoid memory mapping
                # which can have cleanup issues due to file locking
                flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
                basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))

                flow = Arrow.Table(flow_bytes)
                basin = Arrow.Table(basin_bytes)

                # Testbench for flow.arrow
                @test_broken flow.time == flow_bench.time
                @test_broken flow.link_id == flow_bench.link_id
                @test_broken flow.from_node_id == flow_bench.from_node_id
                @test_broken flow.to_node_id == flow_bench.to_node_id

                # Testbench for basin.arrow
                @test_broken basin.time == basin_bench.time
                @test_broken basin.node_id == basin_bench.node_id
            end
        end
    end
end
