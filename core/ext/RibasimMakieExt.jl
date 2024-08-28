module RibasimMakieExt
using DataFrames: DataFrame
using Makie: Figure, Axis, lines!, scatter!, axislegend
using Ribasim: Ribasim, Model

function Ribasim.plot_basin_data!(model::Model, ax::Axis, column::Symbol)
    basin_data = DataFrame(Ribasim.basin_table(model))
    for node_id in unique(basin_data.node_id)
        group = filter(:node_id => ==(node_id), basin_data)
        lines!(ax, group.time, getproperty(group, column); label = "Basin #$node_id")
        scatter!(ax, group.time, getproperty(group, column))
    end

    axislegend(ax)
    return nothing
end

function Ribasim.plot_basin_data(model::Model)
    f = Figure()
    ax1 = Axis(f[1, 1]; ylabel = "level [m]")
    ax2 = Axis(f[2, 1]; xlabel = "time", ylabel = "storage [m³]")
    Ribasim.plot_basin_data!(model, ax1, :level)
    Ribasim.plot_basin_data!(model, ax2, :storage)
    f
end

function Ribasim.plot_flow!(model::Model, ax::Axis, edge_metadata::Ribasim.EdgeMetadata)
    flow_data = DataFrame(Ribasim.flow_table(model))
    flow_data = filter(:edge_id => ==(edge_metadata.id), flow_data)
    label = "$(edge_metadata.edge[1]) → $(edge_metadata.edge[2])"
    lines!(ax, flow_data.time, flow_data.flow_rate; label)
    scatter!(ax, flow_data.time, flow_data.flow_rate)
    return nothing
end

function Ribasim.plot_flow(model::Model; skip_conservative_out = true)
    f = Figure()
    ax = Axis(f[1, 1]; xlabel = "time", ylabel = "flow rate [m³s⁻¹]")
    for edge_metadata in values(model.integrator.p.graph.edge_data)
        if skip_conservative_out &&
           edge_metadata.edge[1].type in Ribasim.conservative_nodetypes
            continue
        end
        Ribasim.plot_flow!(model, ax, edge_metadata)
    end
    axislegend(ax)
    f
end

end # module RibasimMakieExt
