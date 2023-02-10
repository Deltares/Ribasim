# Create a GeoPackage from Arrow files according to the new layout from
# https://github.com/Deltares/Ribasim.jl/issues/54

using Dates, Arrow, SQLite, DataFrames, DBInterface, Tables, Dictionaries, GDAL_jll

datadir = "test/data/lhm"
path_node = normpath(datadir, "node.arrow")
path_edge = normpath(datadir, "edge.arrow")
path_arrow = "data/lhm/forcing.arrow"
forcing_in_geopackage = false

path_gpkg = if forcing_in_geopackage
    "data/lhm/model_with_forcing.gpkg"
else
    "data/lhm/model.gpkg"
end

# Create a new GeoPackage with node and edge layers from existing Arrow tables
run(
    `$(ogr2ogr_path()) -f GPKG -overwrite -a_srs EPSG:28992 $path_gpkg $path_node -nln ribasim_node`,
)
run(`$(ogr2ogr_path()) -append -a_srs EPSG:28992 $path_gpkg $path_edge -nln ribasim_edge`)

db = SQLite.DB(path_gpkg)

read_arrow(path) = DataFrame(Arrow.Table(read(path)))

# create map from ID to node type
node = DBInterface.execute(DataFrame, db, "select id,node from ribasim_node")
nodemap = Dictionary(node.id, node.node)

# load state
state = read_arrow(joinpath(datadir, "state.arrow"))
SQLite.load!(state, db, "ribasim_state_LSW")

# load static (split LevelControl and Bifurcation)
static = read_arrow(joinpath(datadir, "static.arrow"))
static_levelcontrol =
    disallowmissing(unstack(filter(row -> row.variable == "target_volume", static)))
static_bifurcation =
    disallowmissing(unstack(filter(row -> startswith(row.variable, "fraction_"), static)))
SQLite.load!(static_levelcontrol, db, "ribasim_static_LevelControl")
SQLite.load!(static_bifurcation, db, "ribasim_static_Bifurcation")

# load profile (rename to lookup, split LSW and OutflowTable)
profile = read_arrow(joinpath(datadir, "profile.arrow"))
lookup_lsw =
    filter(row -> nodemap[row.id] == "LSW", profile)[:, [:id, :volume, :area, :level]]
lookup_outflowtable =
    filter(row -> nodemap[row.id] == "OutflowTable", profile)[:, [:id, :level, :discharge]]
SQLite.load!(lookup_lsw, db, "ribasim_lookup_LSW")
SQLite.load!(lookup_outflowtable, db, "ribasim_lookup_OutflowTable")

# load forcing (all forcing is currently on LSW)
forcing = read_arrow(joinpath(datadir, "forcing.arrow"))
forcing_lsw = disallowmissing(unstack(forcing); error = false)

if forcing_in_geopackage
    SQLite.load!(forcing_lsw, db, "ribasim_forcing_LSW")
else
    Arrow.write(path_arrow, forcing_lsw; compress = :lz4)
end

# get the table from the database
DBInterface.execute(DataFrame, db, "select * from ribasim_state_LSW")

close(db)
