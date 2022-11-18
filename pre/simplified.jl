# convert the simplified schematization from netCDF back into Arrow
# includes state, static, forcing
# excludes forcing

using NCDatasets, Arrow, DataFrames, DataFrameMacros, Dates

output_dir = normpath(@__DIR__, "../data/input/7")
nc_path = normpath(@__DIR__, "../data/input/vanHuite/simplified.nc")

nc = NCDataset(nc_path)

lsw_ids = Int.(nc["node"][:])
@assert issorted(lsw_ids)

nodes = DataFrame(Arrow.Table(read(normpath(output_dir, "node.arrow"))))
# not the LSW IDs but IDs that are unique to the node
ids = @subset(nodes, :node=="LSW").id

# state
begin
    volume = Float64.(nc["volume"][:])
    salinity = similar(volume)
    salinity .= 0.1
    state = DataFrame(; id = ids, volume, salinity)
    Arrow.write(normpath(output_dir, "state.arrow"), state)
end

# static
begin
    depth_surface_water = Float64.(nc["depth_surface_water"][:])
    target_level = Float64.(nc["target_level"][:])
    target_volume = Float64.(nc["target_volume"][:])

    static = DataFrame(; id = ids, target_level, target_volume, depth_surface_water)
    Arrow.write(normpath(output_dir, "static.arrow"), static)
end

# profile
begin
    profile_3d = Float64.(nc["profile"][:])
    @assert Char.(nc["profile_col"][:]) == ['S', 'A', 'Q', 'h']
    @assert !any(isnan.(profile_3d))
    n_prof = length(nc["profile_row"])

    profiles = DataFrame(id = Int[], volume = Float64[], area = Float64[],
                         discharge = Float64[], level = Float64[])
    for (id, profile_2d) in zip(ids, eachslice(profile_3d; dims = 3))
        append!(profiles.id, fill(id, n_prof))
        append!(profiles.volume, profile_2d[:, 1])
        append!(profiles.area, profile_2d[:, 2])
        append!(profiles.discharge, profile_2d[:, 3])
        append!(profiles.level, profile_2d[:, 4])
    end

    Arrow.write(normpath(output_dir, "profile.arrow"), profiles)
end

# forcing
begin
    forcing = DataFrame(Arrow.Table(read(normpath(output_dir, "forcing-old.arrow"))))

    # TODO support priority_watermanagement
    forcing = @subset(forcing, :variable!=Symbol("priority_watermanagement"))

    idmap = Dict{Int, Int}(lsw_id => id for (lsw_id, id) in zip(lsw_ids, ids))
    varmap = Dict{Symbol, String}(:demand_agriculture => "demand",
                                  :drainage => "drainage",
                                  :evaporation => "E_pot",
                                  :infiltration => "infiltration",
                                  :precipitation => "P",
                                  :priority_agriculture => "priority",
                                  :urban_runoff => "urban_runoff")

    forcing[!, :id] = [idmap[id] for id in forcing.location]
    forcing[!, :variable] = [varmap[id] for id in forcing.variable]
    forcing = forcing[:, [:time, :id, :variable, :value]]
    forcing.variable = Arrow.DictEncode(forcing.variable)
    # optionally we could add the node type here, such that the file is easier to understand
    # by itself, since now two variables with the same name Q can be for different node types
    Arrow.write(normpath(output_dir, "forcing.arrow"), forcing)
end
