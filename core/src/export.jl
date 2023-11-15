# This module exports a water level:
#
# * the water level of the original hydrodynamic model before lumping.
# * a differently aggregated water level, used for e.g. coupling to MODFLOW.
#
# The second is arguably easier to interpret.

"""
basin_level: a view on Ribasim's basin level.
level: the interpolated water level
tables: the interpolator callables

All members of this struct have length n_elem.
"""
struct LevelExporter
    basin_index::Vector{Int}
    interpolations::Vector{ScalarInterpolation}
    level::Vector{Float64}
end

function LevelExporter(tables, node_to_basin::Dict{Int, Int})::LevelExporter
    basin_ids = Int[]
    interpolations = ScalarInterpolation[]

    for group in IterTools.groupby(row -> row.element_id, tables)
        node_id = first(getproperty.(group, :node_id))
        basin_level = getproperty.(group, :basin_level)
        element_level = getproperty.(group, :level)
        # Ensure it doesn't extrapolate before the first value.
        new_interp = LinearInterpolation(
            [element_level[1], element_level...],
            [prevfloat(basin_level[1]), basin_level...],
        )
        push!(basin_ids, node_to_basin[node_id])
        push!(interpolations, new_interp)
    end

    return LevelExporter(basin_ids, interpolations, fill(NaN, length(basin_ids)))
end

function create_level_exporters(
    db::DB,
    config::Config,
    basin::Basin,
)::Dict{String, LevelExporter}
    node_to_basin = Dict(node_id => index for (index, node_id) in enumerate(basin.node_id))
    tables = load_structvector(db, config, LevelExporterStaticV1)
    level_exporters = Dict{String, LevelExporter}()
    if !isempty(tables) > 0
        for group in IterTools.groupby(row -> row.name, tables)
            name = first(getproperty.(group, :name))
            level_exporters[name] = LevelExporter(group, node_to_basin)
        end
    end
    return level_exporters
end

"""
Compute a new water level for each external element.
"""
function update!(exporter::LevelExporter, basin_level)::Nothing
    for (i, (index, interp)) in
        enumerate(zip(exporter.basin_index, exporter.interpolations))
        exporter.level[i] = interp(basin_level[index])
    end
end
