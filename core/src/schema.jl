# These schemas define the name of database tables and the configuration file structure

"Convert a string from CamelCase to snake_case."
function snake_case(str::AbstractString)::String
    under_scored = replace(str, r"(?<!^)(?=[A-Z])" => "_")
    return lowercase(under_scored)
end

snake_case(sym::Symbol)::Symbol = Symbol(snake_case(String(sym)))

"Convert a string from snake_case to CamelCase."
function camel_case(snake_case::AbstractString)::String
    camel_case = replace(snake_case, r"_([a-z])" => s -> uppercase(s[2]))
    camel_case = uppercase(first(camel_case)) * camel_case[2:end]
    return camel_case
end

camel_case(sym::Symbol)::Symbol = Symbol(camel_case(String(sym)))

"Get the full table name from the database, like `Basin / state`."
tablename(node_type::Symbol, table::Symbol) = string(camel_case(node_type), " / ", table)

const schemas = (;
    pump = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            flow_rate = Float64,
            min_flow_rate = Union{Missing, Float64},
            max_flow_rate = Union{Missing, Float64},
            min_upstream_level = Union{Missing, Float64},
            max_downstream_level = Union{Missing, Float64},
            control_state = Union{Missing, String},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            flow_rate = Float64,
            min_flow_rate = Union{Missing, Float64},
            max_flow_rate = Union{Missing, Float64},
            min_upstream_level = Union{Missing, Float64},
            max_downstream_level = Union{Missing, Float64},
        ),
    ),
    outlet = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            flow_rate = Float64,
            min_flow_rate = Union{Missing, Float64},
            max_flow_rate = Union{Missing, Float64},
            min_upstream_level = Union{Missing, Float64},
            max_downstream_level = Union{Missing, Float64},
            control_state = Union{Missing, String},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            flow_rate = Float64,
            min_flow_rate = Union{Missing, Float64},
            max_flow_rate = Union{Missing, Float64},
            min_upstream_level = Union{Missing, Float64},
            max_downstream_level = Union{Missing, Float64},
        ),
    ),
    basin = (;
        static = (;
            node_id = Int32,
            drainage = Union{Missing, Float64},
            potential_evaporation = Union{Missing, Float64},
            infiltration = Union{Missing, Float64},
            precipitation = Union{Missing, Float64},
            surface_runoff = Union{Missing, Float64},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            drainage = Union{Missing, Float64},
            potential_evaporation = Union{Missing, Float64},
            infiltration = Union{Missing, Float64},
            precipitation = Union{Missing, Float64},
            surface_runoff = Union{Missing, Float64},
        ),
        concentration = (;
            node_id = Int32,
            time = DateTime,
            substance = String,
            drainage = Union{Missing, Float64},
            precipitation = Union{Missing, Float64},
            surface_runoff = Union{Missing, Float64},
        ),
        concentration_external = (;
            node_id = Int32,
            time = DateTime,
            substance = String,
            concentration = Union{Missing, Float64},
        ),
        profile = (;
            node_id = Int32,
            area = Union{Missing, Float64},
            level = Float64,
            storage = Union{Missing, Float64},
        ),
        state = (;
            node_id = Int32,
            level = Float64,
        ),
        concentration_state = (;
            node_id = Int32,
            substance = String,
            concentration = Union{Missing, Float64},
        ),
        subgrid = (;
            subgrid_id = Int32,
            node_id = Int32,
            basin_level = Float64,
            subgrid_level = Float64,
        ),
        subgrid_time = (;
            subgrid_id = Int32,
            node_id = Int32,
            time = DateTime,
            basin_level = Float64,
            subgrid_level = Float64,
        ),
    ),
    level_boundary = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            level = Float64,
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            level = Float64,
        ),
        concentration = (;
            node_id = Int32,
            time = DateTime,
            substance = String,
            concentration = Float64,
        ),
    ),
    flow_boundary = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            flow_rate = Float64,
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            flow_rate = Float64,
        ),
        concentration = (;
            node_id = Int32,
            time = DateTime,
            substance = String,
            concentration = Float64,
        ),
    ),
    linear_resistance = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            resistance = Float64,
            max_flow_rate = Union{Missing, Float64},
            control_state = Union{Missing, String},
        ),
    ),
    manning_resistance = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            length = Float64,
            manning_n = Float64,
            profile_width = Float64,
            profile_slope = Float64,
            control_state = Union{Missing, String},
        ),
    ),
    tabulated_rating_curve = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            level = Float64,
            flow_rate = Float64,
            max_downstream_level = Union{Missing, Float64},
            control_state = Union{Missing, String},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            level = Float64,
            flow_rate = Float64,
            max_downstream_level = Union{Missing, Float64},
        ),
    ),
    discrete_control = (;
        variable = (;
            node_id = Int32,
            compound_variable_id = Int32,
            listen_node_id = Int32,
            variable = String,
            weight = Union{Missing, Float64},
            look_ahead = Union{Missing, Float64},
        ),
        condition = (;
            node_id = Int32,
            compound_variable_id = Int32,
            condition_id = Int32,
            greater_than = Float64,
            time = Union{Missing, DateTime},
        ),
        logic = (;
            node_id = Int32,
            truth_state = String,
            control_state = String,
        ),
    ),
    continuous_control = (;
        variable = (;
            node_id = Int32,
            listen_node_id = Int32,
            variable = String,
            weight = Union{Missing, Float64},
            look_ahead = Union{Missing, Float64},
        ),
        var"function" = (;
            node_id = Int32,
            input = Float64,
            output = Float64,
            controlled_variable = String,
        ),
    ),
    pid_control = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            listen_node_id = Int32,
            target = Float64,
            proportional = Float64,
            integral = Float64,
            derivative = Float64,
            control_state = Union{Missing, String},
        ),
        time = (;
            node_id = Int32,
            listen_node_id = Int32,
            time = DateTime,
            target = Float64,
            proportional = Float64,
            integral = Float64,
            derivative = Float64,
        ),
    ),
    user_demand = (;
        static = (;
            node_id = Int32,
            active = Union{Missing, Bool},
            demand = Union{Missing, Float64},
            return_factor = Float64,
            min_level = Float64,
            demand_priority = Union{Missing, Int32},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            demand = Float64,
            return_factor = Float64,
            min_level = Float64,
            demand_priority = Union{Missing, Int32},
        ),
        concentration = (;
            node_id = Int32,
            time = DateTime,
            substance = String,
            concentration = Float64,
        ),
    ),
    level_demand = (;
        static = (;
            node_id = Int32,
            min_level = Union{Missing, Float64},
            max_level = Union{Missing, Float64},
            demand_priority = Union{Missing, Int32},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            min_level = Union{Missing, Float64},
            max_level = Union{Missing, Float64},
            demand_priority = Union{Missing, Int32},
        ),
    ),
    flow_demand = (;
        static = (;
            node_id = Int32,
            demand = Float64,
            demand_priority = Union{Missing, Int32},
        ),
        time = (;
            node_id = Int32,
            time = DateTime,
            demand = Float64,
            demand_priority = Union{Missing, Int32},
        ),
    ),
    terminal = (;),
    junction = (;),
)

const nodetypes = collect(keys(schemas))

get_schema(node_type::Symbol, table::Symbol)::NamedTuple = schemas[node_type][table]
