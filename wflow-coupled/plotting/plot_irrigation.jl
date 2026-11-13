# Plot the irrigation demand, allocated and realized supply per Ribasim UserDemand, from the
# Ribasim allocation results of a coupled run. Run online.jl first.

using CairoMakie
using Dates: DateTime
using NCDatasets: NCDataset
using TOML

"Locate the Ribasim allocation results of the coupled run."
function allocation_results_path(config_path::AbstractString)::String
    config = TOML.parsefile(config_path)
    ribasim_toml = normpath(dirname(abspath(config_path)), config["ribasim_toml"])
    results_dir = get(TOML.parsefile(ribasim_toml), "results_dir", "results")
    path = normpath(dirname(ribasim_toml), results_dir, "allocation.nc")
    isfile(path) || error("Allocation results not found at $path. Run online.jl first.")
    return path
end

"Read the UserDemand irrigation flows (m3/s), summed over the demand priorities."
function read_irrigation(path::AbstractString)::NamedTuple
    return NCDataset(path) do ds
        user_demand = ds["node_type"][:] .== "UserDemand"
        any(user_demand) || error("No UserDemand nodes in $path.")
        # Dimensions are (demand_priority, node_id, time)
        flow(name) = dropdims(sum(ds[name][:, user_demand, :]; dims = 1); dims = 1)
        return (;
            time = DateTime.(ds["time"][:]),
            node_id = ds["node_id"][user_demand],
            demand = flow("demand"),
            allocated = flow("allocated"),
            realized = flow("supplied"),
        )
    end
end

"Plot the demand, allocated and realized irrigation with a panel per UserDemand."
function plot_irrigation(irrigation::NamedTuple)::Figure
    (; time, node_id, demand, allocated, realized) = irrigation
    # Results are written at the start of each allocation interval
    x = [time; time[end] + (time[end] - time[end - 1])]
    extend(values) = [values; values[end]]
    n_nodes = length(node_id)
    figure = Figure(; size = (900, 250 * n_nodes))
    axes = map(eachindex(node_id)) do i
        axis = Axis(
            figure[i, 1];
            title = "UserDemand #$(node_id[i])",
            ylabel = "flow [m³/s]",
            xlabel = i == n_nodes ? "time" : "",
        )
        colors = Makie.wong_colors()
        stairs!(axis, x, extend(realized[i, :]); step = :post, label = "realized", color = colors[1], linewidth = 3)
        stairs!(axis, x, extend(demand[i, :]); step = :post, label = "demand", color = colors[3], linestyle = :dot, linewidth = 4)
        stairs!(axis, x, extend(allocated[i, :]); step = :post, label = "allocated", color = colors[2], linestyle = :dash)
        return axis
    end
    linkxaxes!(axes...)
    Legend(figure[0, 1], first(axes); orientation = :horizontal, framevisible = false)
    return figure
end

"Plot from command-line arguments: the coupling configuration and the output figure."
function (@main)(args)::Nothing
    config_path = isempty(args) ? joinpath(@__DIR__, "..", "coupling.toml") : args[1]
    figure_path = length(args) >= 2 ? args[2] : joinpath(@__DIR__, "irrigation.png")
    irrigation = read_irrigation(allocation_results_path(config_path))
    save(figure_path, plot_irrigation(irrigation))
    @info "Saved irrigation plot" figure_path
    return nothing
end
