# convert the simplified schematization from netCDF back into Arrow
# includes state, static, forcing
# excludes forcing

using NCDatasets, Arrow, DataFrames, Dates

output_dir = normpath(@__DIR__, "../data/input/6")
nc_path = normpath(@__DIR__, "../data/input/vanHuite/simplified.nc")

nc = NCDataset(nc_path)

lsw_ids = Int.(nc["node"][:])
@assert issorted(lsw_ids)

# state
begin
    volume = Float64.(nc["volume"][:])
    salinity = similar(volume)
    salinity .= 0.1
    state = DataFrame(; location = lsw_ids, volume, salinity)
    Arrow.write(normpath(output_dir, "state.arrow"), state)
end

# static
begin
    depth_surface_water = Float64.(nc["depth_surface_water"][:])
    target_level = Float64.(nc["target_level"][:])
    target_volume = Float64.(nc["target_volume"][:])
    local_surface_water_type = Arrow.DictEncode(Char.(nc["local_surface_water_type"][:]))

    static = DataFrame(; location = lsw_ids, target_level, target_volume,
                       depth_surface_water, local_surface_water_type)
    Arrow.write(normpath(output_dir, "static.arrow"), static)
end

# profile
begin
    profile_3d = Float64.(nc["profile"][:])
    @assert Char.(nc["profile_col"][:]) == ['S', 'A', 'Q', 'h']
    @assert !any(isnan.(profile_3d))
    n_prof = length(nc["profile_row"])

    profiles = DataFrame(location = Int[], volume = Float64[], area = Float64[],
                         discharge = Float64[], level = Float64[])
    for (lsw_id, profile_2d) in zip(lsw_ids, eachslice(profile_3d; dims = 3))
        append!(profiles.location, fill(lsw_id, n_prof))
        append!(profiles.volume, profile_2d[:, 1])
        append!(profiles.area, profile_2d[:, 2])
        append!(profiles.discharge, profile_2d[:, 3])
        append!(profiles.level, profile_2d[:, 4])
    end

    Arrow.write(normpath(output_dir, "profile.arrow"), profiles)
end
