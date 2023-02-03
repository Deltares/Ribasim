# Starting from a GeoPackage with node and edge layers, add non-spatial tables from
# the Arrow files to the new layout from https://github.com/Deltares/Ribasim.jl/issues/54

# The initial GeoPackage was created with these commands
# ogr2ogr -f GPKG -a_srs EPSG:28992 lhm.gpkg Ribasim\test\data\lhm\node.arrow -nln ribasim_node
# ogr2ogr -append -a_srs EPSG:28992 lhm.gpkg Ribasim\test\data\lhm\edge.arrow -nln ribasim_edge

using Dates, Arrow, SQLite, DataFrames, DBInterface, Tables, Dictionaries

add_forcing = false
db = SQLite.DB("lhm.gpkg")
tables = SQLite.tables(db)
foreach(println, [t.name for t in tables])

datadir = raw"d:\visser_mn\.julia\dev\Ribasim\test\data\lhm"

read_arrow(path) = DataFrame(Arrow.Table(read(path)))

"Create empty tables based on schemas"
function create_tables!(db)
    # create an empty table based on a schema
    schema_state = Tables.Schema((:id, :S, :C), (Int, Float64, Float64))
    SQLite.createtable!(db, "ribasim_state_LSW", schema_state)

    schema_static_levelcontrol = Tables.Schema((:id, :target_volume), (Int, Float64))
    SQLite.createtable!(db, "ribasim_static_LevelControl", schema_static_levelcontrol)
    schema_static_bifurcation =
        Tables.Schema((:id, :fraction_1, :fraction_2), (Int, Float64, Float64))
    SQLite.createtable!(db, "ribasim_static_Bifurcation", schema_static_bifurcation)

    schema_lookup_lsw =
        Tables.Schema((:id, :volume, :area, :level), (Int, Float64, Float64, Float64))
    SQLite.createtable!(db, "ribasim_lookup_LSW", schema_lookup_lsw)
    schema_lookup_outflowtable =
        Tables.Schema((:id, :level, :discharge), (Int, Float64, Float64))
    SQLite.createtable!(db, "ribasim_lookup_OutflowTable", schema_lookup_outflowtable)

    schema_forcing_lsw = Tables.Schema(
        (
            :time,
            :id,
            :demand,
            :drainage,
            :E_pot,
            :infiltration,
            :P,
            :priority,
            :urban_runoff,
        ),
        (
            DateTime,
            Int,
            Union{Missing,Float64},
            Union{Missing,Float64},
            Union{Missing,Float64},
            Union{Missing,Float64},
            Union{Missing,Float64},
            Union{Missing,Float64},
            Union{Missing,Float64},
        ),
    )
    SQLite.createtable!(db, "ribasim_forcing_LSW", schema_forcing_lsw)
    return db
end

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

if add_forcing
    # load forcing (all forcing is currently on LSW)
    forcing = read_arrow(joinpath(datadir, "forcing.arrow"))
    forcing_lsw = disallowmissing(unstack(forcing); error = false)
    SQLite.load!(forcing_lsw, db, "ribasim_forcing_LSW")
end

# drop tables
# DBInterface.execute(DataFrame, db, "drop table ribasim_state_LSW")

# get the table from the database
DBInterface.execute(DataFrame, db, "select * from ribasim_state_LSW")

close(db)
