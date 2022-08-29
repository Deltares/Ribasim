# Plotting functions

"Create a time axis with Unix time values and date formatted labels"
function time!(ax, xmin::DateTime, xmax::DateTime)
    # note that the used x values must also be in unix time
    dateticks = optimize_ticks(xmin, xmax)[1]
    ax.xticks[] = (datetime2unix.(dateticks), Dates.format.(dateticks, "yyyy-mm-dd"))
    ax.xlabel = "time"
    ax.xticklabelrotation = π / 4
    return ax
end

time!(ax, xmin::Real, xmax::Real) = time!(ax, unix2datetime(xmin), unix2datetime(xmax))

unixtimespan(timespan::ClosedInterval{Float64}) = timespan
function unixtimespan(timespan::ClosedInterval{DateTime})
    datetime2unix(timespan.left) .. datetime2unix(timespan.right)
end

"""
    reconstruct_graph(systems::Set{ODESystem}, eqs::Vector{Equation})

Based on a list of systems and their connections, construct a graph that shows the connections between the systems, through their connectors.
Both systems and connectors are separately included in the graph.

Returns the graph, as well as the names of the systems and connectors:
    g, component_names, connector_names
"""
function reconstruct_graph(systems::Set{ODESystem}, eqs::Vector{Equation})
    # get the names and number of connectors
    connector_names_set = Set{Symbol}()
    for eq in eqs
        for connector in eq.rhs.systems
            push!(connector_names_set, nameof(connector))
        end
    end
    connector_names = collect(connector_names_set)
    component_names = nameof.(systems)
    n_component = length(systems)
    n_connector = length(connector_names)

    # the first n_component nodes are reserved for the components, the rest for the connectors
    g = Graph(n_component + n_connector)
    # add edges of the connetions
    for eq in eqs
        from, tos = Iterators.peel(eq.rhs.systems)
        i_from = findfirst(==(nameof(from)), connector_names) + n_component
        for to in tos
            i_to = findfirst(==(nameof(to)), connector_names) + n_component
            add_edge!(g, i_from, i_to)
        end
    end

    # add edges of the components to their own connectors
    for (i_from, component_name) in enumerate(component_names)
        for (i_to, connector_name) in enumerate(connector_names)
            parent_name = parentname(connector_name)
            if component_name == parent_name
                add_edge!(g, i_from, i_to + n_component)
            end
        end
    end

    return g, component_names, connector_names
end

"""
    graph_system(systems::Set{ODESystem}, eqs::Vector{Equation}, reg::Register)

Based on a list of systems and their connections, create an interactive graph plot
that shows the components and their values over time.
"""
function graph_system(systems::Set{ODESystem}, eqs::Vector{Equation}, reg::Bach.Register)
    g, component_names, connector_names = reconstruct_graph(systems, eqs)
    n_component = length(component_names)
    n_connector = length(connector_names)
    n = n_component + n_connector

    # different edge color for inside and outside components
    node_color = fill(colorant"black", n)
    edge_color = RGB{N0f8}[]
    for edge in edges(g)
        colour = if src(edge) <= n_component
            colorant"black"
        else
            colorant"blue"
        end
        push!(edge_color, colour)
    end

    vars = ["h", "S", "Q", "C"]
    var = "Q"

    times = reg.integrator.sol.t  # TODO remove
    starttime = first(times)
    endtime = last(times)
    t = starttime .. endtime
    ts = lastindex(times)  # TODO remove
    fig = Figure()

    layout_graph = fig[1, 1]
    layout_time = fig[1, 2]

    # left column: graph
    menu = Menu(fig, options = vars)
    layout_graph[1, 1] = menu
    sg = SliderGrid(layout_graph[2, 1],
                    (label = "time:",
                     range = times,
                     format = x -> @sprintf("%.1f s", x),
                     startvalue = times[end]))
    ax = Axis(layout_graph[3, 1])

    # create labels for each node
    labelnames = String.(vcat(component_names, connector_names))
    # not all states have all variables

    # TODO pre calculate all interpolation functions?
    # TODO rename col (no dataframe columns)
    # ts does not need to interpolate perhaps, do that only for the time plots?
    # e.g. labels don't need to be interpolated
    function create_nlabels(var, ts)
        labelvars = string.(labelnames, "₊$var")
        return [string(col, @sprintf(": %.2f", savedvalue_nan(reg, Symbol(col), ts)))
                for
                col in labelvars]
    end

    nlabels = create_nlabels(var, ts)
    nlabels_textsize = 15.0

    # needed for hover interactions to work
    node_size = fill(14.0, nv(g))
    edge_width = fill(2.0, ne(g))
    # layout of the graph (replace with geolocation when they have one)
    # layout = NetworkLayout.Spring() # ok
    layout = NetworkLayout.Stress() # good (doesn't seem to work for disconnected graphs)

    p = graphplot!(ax,
                   g;
                   nlabels,
                   nlabels_textsize,
                   node_size,
                   node_color,
                   edge_width,
                   edge_color,
                   layout)

    # right column: timeseries
    h = Axis(layout_time[1, 1], ylabel = "h [m]")
    hidexdecorations!(h, grid = false)
    # axislegend()
    s = Axis(layout_time[2, 1], ylabel = "S [m³]")
    hidexdecorations!(s, grid = false)
    # axislegend()
    q = Axis(layout_time[3, 1], ylabel = "Q [m³s⁻¹]")
    hidexdecorations!(q, grid = false)
    # axislegend()
    c = Axis(layout_time[4, 1], ylabel = "C [kg m⁻³]")
    hidexdecorations!(c, grid = false)
    # axislegend()

    linkxaxes!(h, s, q, c)

    # state of which timeseries to draw
    draw_timeseries = fill(false, n)

    # interactions
    function node_click_action(idx, args...)
        # flip the switch
        oldstate = draw_timeseries[idx]
        draw_timeseries[idx] = !oldstate
        idxs = findall(draw_timeseries)
        # color = p.node_color[][idx]
        black, red = colorant"black", colorant"red"
        if !oldstate
            p.node_color[][idx] = red
        else
            p.node_color[][idx] = black
        end
        p.node_color[] = p.node_color[]

        label_sels = labelnames[idxs]
        empty!(h)
        empty!(s)
        empty!(q)
        empty!(c)
        for label_sel in label_sels
            col = Symbol(string(label_sel, "₊h"))
            ifunc = interpolator(reg, col)
            lines!(h, t, ifunc, label = label_sel)

            # storage is not always defined
            col = Symbol(string(label_sel, "₊S"))
            if haskey(reg, col)
                ifunc = interpolator(reg, col)
                lines!(s, t, ifunc, label = label_sel)
            end

            col = Symbol(string(label_sel, "₊Q"))
            ifunc = interpolator(reg, col)
            lines!(q, t, ifunc, label = label_sel)

            col = Symbol(string(label_sel, "₊C"))
            ifunc = interpolator(reg, col)
            lines!(c, t, ifunc, label = label_sel)
        end

        # TODO remove the old lines
        # axislegend(h)
    end

    on(menu.selection) do var
        p.nlabels[] = create_nlabels(var, ts)
        # https://github.com/JuliaPlots/GraphMakie.jl/issues/66
        p.nlabels_distance[] = p.nlabels_distance[]
    end

    lift(only(sg.sliders).value) do t
        # TODO slider resets to initial var
        ts = searchsortedlast(times, t)
        p.nlabels[] = create_nlabels(var, ts)
        p.nlabels_distance[] = p.nlabels_distance[]
    end

    deregister_interaction!(ax, :rectanglezoom)
    # register_interaction!(ax, :nhover, NodeHoverHighlight(p))
    # register_interaction!(ax, :ehover, EdgeHoverHighlight(p))
    # register_interaction!(ax, :ndrag, NodeDrag(p))
    # register_interaction!(ax, :edrag, EdgeDrag(p))
    register_interaction!(ax, :nclick, NodeClickHandler(node_click_action))

    return fig
end

"""
    node_coords(topology)

Get the location of the nodes of a UGRID topology.
Useful for plotting the graph using the example below:

    GraphMakie.graphplot(; layout = g -> node_coords(topology))
    hidespines!(ax)
    ax.aspect = DataAspect()
"""
node_coords(topology) = Point2f.(zip(topology.node_x, topology.node_y))

# 10 color palette by Wong (Makie.wong_colors() doesn't have black)
wong_colors = [
    colorant"rgb(0,114,178)",
    colorant"rgb(230,159,0)",
    colorant"rgb(0,158,115)",
    colorant"rgb(204,121,167)",
    colorant"rgb(86,180,233)",
    colorant"rgb(213,94,0)",
    colorant"rgb(240,228,66)",
    colorant"black",
    colorant"rgb(255,160,122)",
    colorant"rgb(192,192,192)",
]

"Plot timeseries of several key variables."
function plot_series(reg::Bach.Register,
                     lsw_id::Int,
                     timespan::ClosedInterval{Float64};
                     level = true)
    fig = Figure()
    ylabel = "flow rate / m³ s⁻¹"
    ax1 = time!(Axis(fig[1, 1]; ylabel), timespan.left, timespan.right)
    ylabel = level ? "water level / m + NAP" : "storage volume / m³"
    ax2 = time!(Axis(fig[2, 1]; ylabel), timespan.left, timespan.right)

    # TODO plot users/agriculture
    name = Symbol(:sys_, lsw_id, :₊lsw₊)
    lines!(ax1, timespan, interpolator(reg, Symbol(name, :Q_prec)), label = "precipitation")
    lines!(ax1, timespan, interpolator(reg, Symbol(name, :Q_eact), -1),
           label = "evaporation")
    haskey(reg, Symbol(:sys_, lsw_id, :₊weir₊, :Q)) && lines!(ax1,
           timespan,
           interpolator(reg, Symbol(:sys_, lsw_id, :₊weir₊, :Q)),
           label = "outflow")
    haskey(reg, Symbol(:sys_, lsw_id, :₊link₊a₊, :Q)) && lines!(ax1,
           timespan,
           interpolator(reg, Symbol(:sys_, lsw_id, :₊link₊a₊, :Q)),
           label = "link")
    haskey(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊a₊, :Q)) && lines!(ax1,
           timespan,
           interpolator(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊a₊, :Q), -1),
           label = "watermanagement")
    lines!(ax1, timespan, interpolator(reg, Symbol(name, :drainage)), label = "drainage")
    lines!(ax1,
           timespan,
           interpolator(reg, Symbol(name, :infiltration), -1),
           label = "infiltration")
    lines!(ax1,
           timespan,
           interpolator(reg, Symbol(name, :urban_runoff)),
           label = "urban_runoff")

    fig[1, 2] = Legend(fig, ax1, "", framevisible = true)
    #axislegend(ax1, position = :rt)
    
    hidexdecorations!(ax1, grid = false)
    if level
        lines!(ax2, timespan, interpolator(reg, Symbol(name, :h)))
        target_level = Symbol(:sys_, lsw_id, :₊levelcontrol₊, :target_level)
        if haskey(reg, target_level)
            lines!(ax2, timespan, interpolator(reg, target_level))
        end
    else
        lines!(ax2, timespan, interpolator(reg, Symbol(name, :S)))
        target_volume = Symbol(:sys_, lsw_id, :₊levelcontrol₊, :target_volume)
        if haskey(reg, target_volume)
            lines!(ax2, timespan, interpolator(reg, target_volume))
        end
    end
    linkxaxes!(ax1, ax2)
    return fig
end

function plot_series(reg::Bach.Register, lsw_id::Int; level = false)
    plot_series(reg,
                lsw_id,
                reg.integrator.sol.t[begin] .. reg.integrator.sol.t[end];
                level)
end

"Plot timeseries of wm external and LSW source allocation"
function plot_wm_source(reg::Bach.Register,
                     lsw_id::Int,
                     timespan::ClosedInterval{Float64};
                     level = true)
    fig = Figure()
    ylabel = "flow rate / m³ s⁻¹"
    ax1 = time!(Axis(fig[1, 1]; ylabel), timespan.left, timespan.right)

    # TODO plot users/agriculture
    name = Symbol(:sys_, lsw_id, :₊lsw₊)

    haskey(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊a₊, :Q)) && lines!(ax1,
           timespan,
           interpolator(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊a₊, :Q), -1),
           label = "total watermanagement")

    haskey(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊, :alloc_a)) && lines!(ax1,
        timespan,
        interpolator(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊, :alloc_a), -1),
        label = "LSW sources")

    haskey(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊, :alloc_b)) && lines!(ax1,
           timespan,
           interpolator(reg, Symbol(:sys_, lsw_id, :₊levelcontrol₊, :alloc_b), -1),
           label = "externally sourced")
    fig[1, 2] = Legend(fig, ax1, "", framevisible = true)

    #axislegend(ax1)
    hidexdecorations!(ax1, grid = false)
    return fig
end

function plot_wm_source(reg::Bach.Register, lsw_id::Int; level = false)
    plot_wm_source(reg,
                lsw_id,
                reg.integrator.sol.t[begin] .. reg.integrator.sol.t[end];
                level)
end

"long format daily waterbalance dataframe for comparing mozart and bach"
function combine_waterbalance(mzwb, bachwb)
    time_start = intersect(mzwb.time_start, bachwb.time_start)
    mzwb = @subset(mzwb, :time_start in time_start)
    bachwb = @subset(bachwb, :time_start in time_start)

    wb = vcat(stack(bachwb), stack(mzwb))
    wb = @subset(wb, !(:variable in ("balancecheck", "upstream")))
    return wb
end

function plot_waterbalance_comparison(wb::DataFrame)
    # use days since start as x
    startdate, enddate = extrema(wb.time_start)
    x = Dates.value.(Day.(wb.time_start .- startdate))
    # map each variable to an integer
    type = only(wb[1, :type])::Char
    allvars = type == 'V' ? vcat(vars, "todownstream") : vcat(vars, "watermanagement")
    stacks = [findfirst(==(v), allvars) for v in wb.variable]

    if any(isnothing, stacks)
        for v in wb.variable
            if !(v in allvars)
                @error "nothing found" v allvars
                error("nothing found")
            end
        end
    end
    dodge = [x == "mozart" ? 1 : 2 for x in wb.model]

    fig = Figure()
    ax = Axis(fig[1, 1],
              # label the first and last day
              xticks = (collect(extrema(x)), string.([startdate, enddate])),
              xlabel = "time / day",
              ylabel = "volume / m³",
              title = "Mozart and Bach daily water balance")

    barplot!(ax,
             x,
             wb.value;
             dodge,
             stack = stacks,
             color = stacks,
             colormap = Duet.wong_colors)

    elements = vcat([MarkerElement(marker = 'L'), MarkerElement(marker = 'R')],
                    [PolyElement(polycolor = Duet.wong_colors[i])
                     for i in 1:length(allvars)])
    Legend(fig[1, 2], elements, vcat("mozart", "bach", allvars))

    return fig
end

function plot_series_comparison(reg::Bach.Register,
                                type::Char,
                                mz_lswval::DataFrame,
                                bachvar::Symbol,
                                mzvar::Symbol,
                                timespan::ClosedInterval{Float64},
                                target = nothing)
    fig = Figure()
    ax = time!(Axis(fig[1, 1]), timespan.left, timespan.right)

    # plot all the calculated data points
    scatter!(ax,
             Bach.timesteps(reg),
             Bach.savedvalues(reg, bachvar);
             markersize = 4,
             color = :blue,
             label = "$bachvar bach")
    stairs!(ax,
            datetime2unix.(mz_lswval.time_start),
            mz_lswval[!, mzvar];
            color = :black,
            step = :post,
            label = "$mzvar mozart")
    if type == 'P' && target !== nothing
        hlines!(ax, target, label = "target")
    end
    axislegend(ax)
    return fig
end

function plot_series_comparison(reg::Bach.Register)
    plot_series_comparison(reg, reg.integrator.sol.t[begin] .. reg.integrator.sol.t[end])
end

function plot_series_comparison(reg::Bach.Register, timespan::ClosedInterval{DateTime})
    plot_series_comparison(reg, unixtimespan(timespan))
end

"Plot timeseries of key variables related to user allocation and demand"
function plot_Qavailable_series(reg::Bach.Register, timespan::ClosedInterval{Float64}, mzwb)
    fig = Figure()
    ax1 = time!(Axis(fig[1, 1], ylabel = "m³/s"), timespan.left, timespan.right)
    ax2 = time!(Axis(fig[2, 1], ylabel = "m³/s"), timespan.left, timespan.right)
    ax3 = time!(Axis(fig[3, 1], ylabel = "m³/s"), timespan.left, timespan.right)
    ax4 = time!(Axis(fig[4, 1], ylabel = "m³/s"), timespan.left, timespan.right)

    lines!(ax1, timespan, interpolator(reg, :Q_avail_vol), label = "Bach Q_avail_vol")
    #lines!(ax1, timespan, interpolator(reg, :abs_agric), label = "Bach Agric_use")
    lines!(ax1, timespan, interpolator(reg, :alloc_agric), label = "Bach Agric_alloc")
    lines!(ax1, timespan, interpolator(reg, :dem_agric), label = "Mz Agric_demand")

    stairs!(ax2,
            timespan,
            mzwb.dem_agric / 864000;
            color = :black,
            step = :post,
            label = "Mz Agric_demamd")
    stairs!(ax2,
            timespan,
            mzwb.alloc_agric / 864000;
            color = :red,
            step = :post,
            label = "Mz Agric_alloc")

    lines!(ax2, timespan, interpolator(reg, :alloc_agric), label = "Bach Agric_alloc")

    lines!(ax3, timespan, interpolator(reg, :infiltration), label = "Bach Infiltration")
    lines!(ax3, timespan, interpolator(reg, :drainage), label = "Bach Drainage")
    lines!(ax3, timespan, interpolator(reg, :urban_runoff), label = "Bach runoff")

    lines!(ax4, timespan, interpolator(reg, :P), label = "Bach Precip")
    lines!(ax4, timespan, interpolator(reg, :E_pot), label = "Bach Evap")

    axislegend(ax1)
    axislegend(ax2)
    axislegend(ax3)
    axislegend(ax4)

    return fig
end

"Plot timeseries of key variables related to user allocation and demand -- to check if multiple users can be modelled correctly
Industry data is made up"
function plot_Qavailable_dummy_series(reg::Bach.Register, timespan::ClosedInterval{Float64})
    fig = Figure()
    ax1 = time!(Axis(fig[1, 1], ylabel = "m³/s"), timespan.left, timespan.right)
    ax2 = time!(Axis(fig[2, 1], ylabel = "m³/s"), timespan.left, timespan.right)

    lines!(ax1, timespan, interpolator(reg, :Q_avail_vol), label = "Bach Q_avail_vol")
    lines!(ax1, timespan, interpolator(reg, :alloc_agric), label = "Bach Agric_alloc")
    lines!(ax1, timespan, interpolator(reg, :alloc_indus), label = "Bach Indus_alloc")

    lines!(ax2, timespan, interpolator(reg, :dem_agric), label = "Bach Agric_dem")
    lines!(ax2, timespan, interpolator(reg, :dem_indus), label = "Bach Indus_dem")
    lines!(ax2, timespan, interpolator(reg, :alloc_agric), label = "Bach Agric_alloc")
    lines!(ax2, timespan, interpolator(reg, :alloc_indus), label = "Bach Indus_alloc")

    axislegend(ax1)
    axislegend(ax2)

    return fig
end

"Plot user total demand and shortage"
function plot_user_demand(reg::Bach.Register,
                          timespan::ClosedInterval{Float64},
                          bachwb::DataFrame,
                          mzwb::DataFrame,
                          lsw_id)
    fig = Figure()
    ax1 = time!(Axis(fig[1, 1], ylabel = "m³/s"), timespan.left, timespan.right)
    lines!(ax1, timespan, interpolator(reg, :dem_agric), label = "Bach Agric_dem")
    lines!(ax1, timespan, interpolator(reg, :dem_indus), label = "Bach Indus_dem")
    lines!(ax1, timespan, interpolator(reg, :alloc_agric), label = "Bach Agric_alloc")
    lines!(ax1, timespan, interpolator(reg, :alloc_indus), label = "Bach Indus_alloc")

    axislegend(ax1)

    # long format daily waterbalance dataframe for bach
    mzwblsw = @subset(mzwb, :lsw==lsw_id)
    time_start = intersect(mzwblsw.time_start, bachwb.time_start)
    mzwblsw = @subset(mzwblsw, :time_start in time_start)
    bachwb = @subset(bachwb, :time_start in time_start)
    bachwb.dem_agric = mzwblsw.dem_agric
    bachwb.dem_indus = mzwblsw.dem_agric * 1.3 # as in one.jl. needs updating
    wb = vcat(stack(bachwb))
    wb = @subset(wb, :variable!="balancecheck")

    vars_user = ["alloc_agric", "alloc_indus", "dem_agric", "dem_indus"]

    for v in wb.variable
        if !(v in vars_user)
            wb = @subset(wb, :variable!=v)
        end
    end
    # TODO - update script to automatically detect part of string
    wb.shortage .= ""
    wb.user .= ""
    for i in 1:nrow(wb)
        if wb.variable[i] == "alloc_agric"
            wb.shortage[i] = "supply"
            wb.user[i] = "agri"
        elseif wb.variable[i] == "alloc_indus"
            wb.shortage[i] = "supply"
            wb.user[i] = "indus"
        elseif wb.variable[i] == "dem_indus"
            wb.shortage[i] = "demand"
            wb.user[i] = "indus"
        else
            wb.shortage[i] = "demand"
            wb.user[i] = "agri"
        end
    end
    users = ["agri", "indus"]
    stacks = [findfirst(==(v), users) for v in wb.user]

    if any(isnothing, stacks)
        for v in wb.variable
            if !(v in user)
                @error "nothing found" v users
                error("nothing found")
            end
        end
    end

    startdate, enddate = extrema(wb.time_start)
    x = Dates.value.(Day.(wb.time_start .- startdate))
    dodge = [x == "demand" ? 1 : 2 for x in wb.shortage]
    # use days since start as x
    wb.value = wb.value .* -1

    ax2 = Axis(fig[2, 1],
               # label the first and last day
               xticks = (collect(extrema(x)), string.([startdate, enddate])),
               xlabel = "time / day",
               ylabel = "volume / m³",
               title = "Bach user supply-demand water balance")
    # TO DO - fix x axis time
    cols = Duet.wong_colors[1:2]

    barplot!(ax2, x, wb.value; dodge, stack = stacks, color = stacks, colormap = cols)
    elements = vcat([MarkerElement(marker = 'L'), MarkerElement(marker = 'R')],
                    [PolyElement(polycolor = cols[i]) for i in 1:length(users)])
    Legend(fig[2, 2], elements, vcat("Demand", "Supply", users))

    return fig
end
