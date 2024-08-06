module RibasimMakieExt
using DataFrames: DataFrame
using Makie: Figure, Axis, lines!, axislegend
using Ribasim: Ribasim, Model

function Ribasim.plot_basin_data!(model::Model, ax::Axis, column::Symbol)
    basin_data = DataFrame(Ribasim.basin_table(model))
    for node_id in unique(basin_data.node_id)
        group = filter(:node_id => ==(node_id), basin_data)
        lines!(ax, group.time, getproperty(group, column); label = "Basin #$node_id")
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

function Ribasim.plot_flow!(
    model::Model,
    ax::Axis,
    edge_id::Int32;
    skip_conservative_out = false,
)
    flow_data = DataFrame(Ribasim.flow_table(model))
    flow_data = filter(:edge_id => ==(edge_id), flow_data)
    first_row = first(flow_data)
    # Skip outflows of conservative nodes because these are the same as the inflows
    if skip_conservative_out &&
       Ribasim.NodeType.T(first_row.from_node_type) in Ribasim.conservative_nodetypes
        return nothing
    end
    label = "$(first_row.from_node_type) #$(first_row.from_node_id) → $(first_row.to_node_type) #$(first_row.to_node_id)"
    lines!(ax, flow_data.time, flow_data.flow_rate; label)
    return nothing
end

function Ribasim.plot_flow(model::Model)
    f = Figure()
    ax = Axis(f[1, 1]; xlabel = "time", ylabel = "flow rate [m³s⁻¹]")
    edge_ids = unique(Ribasim.flow_table(model).edge_id)
    for edge_id in edge_ids
        Ribasim.plot_flow!(model, ax, edge_id; skip_conservative_out = true)
    end
    axislegend(ax)
    f
end

end # module RibasimMakieExt
