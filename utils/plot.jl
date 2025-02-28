# Utility functions to plot Ribasim results.

using DataFrames: DataFrame
using Makie: Figure, Axis, scatterlines!, axislegend
using Ribasim: Ribasim, Model

function plot_basin_data!(model::Model, ax::Axis, column::Symbol)
    basin_data = DataFrame(Ribasim.basin_table(model))
    for node_id in unique(basin_data.node_id)
        group = filter(:node_id => ==(node_id), basin_data)
        scatterlines!(ax, group.time, getproperty(group, column); label = "Basin #$node_id")
    end

    axislegend(ax)
    return nothing
end

function plot_basin_data(model::Model)
    f = Figure()
    ax1 = Axis(f[1, 1]; ylabel = "level [m]")
    ax2 = Axis(f[2, 1]; xlabel = "time", ylabel = "storage [m³]")
    plot_basin_data!(model, ax1, :level)
    plot_basin_data!(model, ax2, :storage)
    f
end

function plot_flow!(model::Model, ax::Axis, link_metadata::Ribasim.LinkMetadata)
    flow_data = DataFrame(Ribasim.flow_table(model))
    flow_data = filter(:link_id => ==(link_metadata.id), flow_data)
    label = "$(link_metadata.link[1]) → $(link_metadata.link[2])"
    scatterlines!(ax, flow_data.time, flow_data.flow_rate; label)
    return nothing
end

function plot_flow(model::Model; skip_conservative_out = true)
    f = Figure()
    ax = Axis(f[1, 1]; xlabel = "time", ylabel = "flow rate [m³s⁻¹]")
    for link_metadata in values(model.integrator.p.graph.edge_data)
        if skip_conservative_out &&
           link_metadata.link[1].type in Ribasim.conservative_nodetypes
            continue
        end
        plot_flow!(model, ax, link_metadata)
    end
    axislegend(ax)
    f
end
