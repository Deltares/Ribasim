# convert the simplified schematization from netCDF back into Arrow

using NCDatasets, Arrow, DataFrames, DataFrameMacros, Dates, Dictionaries

output_dir = normpath(@__DIR__, "../data/input/7")
nc_path = normpath(@__DIR__, "../data/input/vanHuite/simplified.nc")

nc = NCDataset(nc_path)

lsw_ids = Int.(nc["node"][:])
@assert issorted(lsw_ids)

edge = DataFrame(Arrow.Table(read(normpath(output_dir, "edge.arrow"))))
nodes = DataFrame(Arrow.Table(read(normpath(output_dir, "node.arrow"))))
types = collect(
    DataFrame(
        Arrow.Table(read(normpath(output_dir, "static-mozart.arrow"))),
    ).local_surface_water_type,
)

# not the LSW IDs but IDs that are unique to the node
ids_lsw = @subset(nodes, :node == "LSW").id
ids_levelcontrol = @subset(nodes, :node == "LevelControl").id
ids_weir = @subset(nodes, :node == "OutflowTable").id
@assert length(ids_levelcontrol) == count(!=('V'), types)
@assert length(ids_weir) == count(==('V'), types)
@assert nodes.id == 1:nrow(nodes)

# node ID to LSW ID
idmap = Dictionary(nodes.id, nodes.org_id)
# LSW ID to node ID
rev_idmap = Dictionary(lsw_ids, ids_lsw)
# lsw ID to connected weir ID
edges_lsw_outflowtable = @subset(edge, :to_node == "OutflowTable", :to_connector == "a")
idmap_outflowtable =
    Dictionary(edges_lsw_outflowtable.from_id, edges_lsw_outflowtable.to_id)

# state
begin
    volume = Float64.(nc["volume"][:])
    salinity = similar(volume)
    salinity .= 0.1
    state = DataFrame(; id = ids_lsw, S = volume, C = salinity)
    Arrow.write(normpath(output_dir, "state.arrow"), state)
end

# static
# To keep it simple, for now we create a long static.arrow, which is like forcing.arrow
# without timestamps. This file is used to create the components, and forcing.arrow is
# used to update from t0 onwards. This means that a monthly forcing that is on the 15th
# of every month, from a simulation that starts the 1st, from day 1 to 15, either the
# hardcoded default parameter value or if it exists the static value will be used, not
# the forcing value from the 15th of the last month. This would be nice to have, but
# is harder to implement without having to look through a lot of the forcing data.
begin
    # target_volume for each level controlled LSW
    target_volume = Float64.(nc["target_volume"][:])[findall(!=('V'), types)]
    static = DataFrame(;
        id = ids_levelcontrol,
        variable = "target_volume",
        value = target_volume,
    )

    lswrouting = read_lswrouting(
        normpath(normpath(@__DIR__, "../data/lhm-output/mozart"), "lswrouting.dik"),
    )

    # fraction_{i} for each bifurcation outflow
    fractional_edges = @subset(edge, :from_node == "Bifurcation")
    for fractional_edge in eachrow(fractional_edges)
        # get 2 from "dst_2", since that will become parameter "fraction_2"
        i = parse(Int, rsplit(fractional_edge.from_connector, '_'; limit = 2)[2])
        id = fractional_edge.from_id
        from_lsw = idmap[id]
        to_lsw = idmap[fractional_edge.to_id]
        subrouting = @subset(lswrouting, :lsw_from == from_lsw, :lsw_to == to_lsw)
        if nrow(subrouting) != 1
            value = 1.0
        else
            value = only(subrouting).fraction
        end
        push!(static, (; id, variable = string("fraction_", i), value))
    end
    # Sort by ID, so we can searchsorted to find each node's data
    sort!(static, [:id, :variable])
    Arrow.write(normpath(output_dir, "static.arrow"), static)
end

# profile
begin
    profile_3d = Float64.(nc["profile"][:])
    @assert Char.(nc["profile_col"][:]) == ['S', 'A', 'Q', 'h']
    @assert !any(isnan.(profile_3d))
    n_prof = length(nc["profile_row"])

    profiles = DataFrame(;
        id = Int[],
        volume = Float64[],
        area = Float64[],
        discharge = Float64[],
        level = Float64[],
    )
    for (id, profile_2d, type) in zip(ids_lsw, eachslice(profile_3d; dims = 3), types)
        append!(profiles.id, fill(id, n_prof))
        append!(profiles.volume, profile_2d[:, 1])
        append!(profiles.area, profile_2d[:, 2])
        append!(profiles.discharge, profile_2d[:, 3])
        append!(profiles.level, profile_2d[:, 4])
        if type == 'V'
            # This is wasteful double storage, but both LSW and OutflowTable need the
            # profile, so to be able to construct these nodes individually they need to
            # appear under both IDs. They do need different columns, but both need volume,
            # so perhaps we can lay it out differently later.
            id_weir = idmap_outflowtable[id]
            append!(profiles.id, fill(id_weir, n_prof))
            append!(profiles.volume, profile_2d[:, 1])
            append!(profiles.area, profile_2d[:, 2])
            append!(profiles.discharge, profile_2d[:, 3])
            append!(profiles.level, profile_2d[:, 4])
        end
    end

    Arrow.write(normpath(output_dir, "profile.arrow"), profiles)
end

# forcing
begin
    forcing = DataFrame(Arrow.Table(read(normpath(output_dir, "forcing-old.arrow"))))

    # TODO support priority_watermanagement
    forcing = @subset(forcing, :variable != Symbol("priority_watermanagement"))

    varmap = Dict{Symbol, String}(
        :demand_agriculture => "demand",
        :drainage => "drainage",
        :evaporation => "E_pot",
        :infiltration => "infiltration",
        :precipitation => "P",
        :priority_agriculture => "priority",
        :urban_runoff => "urban_runoff",
    )

    forcing[!, :id] = [rev_idmap[id] for id in forcing.location]
    forcing[!, :variable] = [varmap[id] for id in forcing.variable]
    forcing = forcing[:, [:time, :id, :variable, :value]]
    forcing.variable = Arrow.DictEncode(forcing.variable)
    # optionally we could add the node type here, such that the file is easier to understand
    # by itself, since now two variables with the same name Q can be for different node types
    Arrow.write(normpath(output_dir, "forcing.arrow"), forcing)
end
