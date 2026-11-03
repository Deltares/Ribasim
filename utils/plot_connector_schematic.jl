using Plots

function plot_connector_schematic(node_type::Symbol)
    node_type in (:Pump, :Outlet, :TabulatedRatingCurve, :LinearResistance, :ManningResistance) ||
        throw(ArgumentError("Unsupported connector node type: $node_type"))
    is_rating_curve = node_type == :TabulatedRatingCurve
    is_manning = node_type == :ManningResistance
    is_resistance = node_type in (:LinearResistance, :ManningResistance)
    gravity_driven = node_type != :Pump
    upstream_level, downstream_level = gravity_driven ? (7.1, 6.3) : (6.3, 7.1)
    diagram = plot(;
        xlims = (0, 12), ylims = (3.4, 9), size = (768, 520),
        axis = false, ticks = false, grid = false, legend = :outerbottom,
        margin = 5Plots.mm,
    )

    basin_left(left, height) = left + 0.6 * (8.4 - height) / (8.4 - 4.6)
    basin_right(right, height) = right - 0.6 * (8.4 - height) / (8.4 - 4.6)

    for (left, right, level) in [
            (0.5, 4.5, upstream_level),
            (7.5, 11.5, downstream_level),
        ]
        water_left = basin_left(left, level)
        water_right = basin_right(right, level)
        plot!(
            diagram,
            Shape([left + 0.6, right - 0.6, water_right, water_left], [4.6, 4.6, level, level]);
            fillcolor = :lightblue, fillalpha = 0.5, linecolor = :transparent, label = "",
        )
        plot!(
            diagram, [water_left, water_right], [level, level];
            color = :steelblue, linewidth = 2, label = "",
        )
        plot!(
            diagram, [left, left + 0.6, right - 0.6, right], [8.4, 4.6, 4.6, 8.4];
            color = :black, linewidth = 2, label = "",
        )
    end

    bands = [(7.5, 11.5, 7.6, 7.9, "max_downstream_level")]
    if is_resistance
        empty!(bands)
    elseif !is_rating_curve
        pushfirst!(bands, (0.5, 4.5, 5.3, 5.6, "min_upstream_level"))
    end
    if gravity_driven && !is_resistance
        push!(bands, (0.5, 4.5, downstream_level, downstream_level + 0.3, ""))
        plot!(
            diagram, [basin_left(0.5, downstream_level), basin_left(7.5, downstream_level)],
            [downstream_level, downstream_level];
            color = :steelblue, linestyle = :dot, label = "",
        )
    end
    for (i, (left, right, lower, upper, label)) in enumerate(bands)
        plot!(
            diagram,
            Shape(
                [
                    basin_left(left, lower), basin_right(right, lower),
                    basin_right(right, upper), basin_left(left, upper),
                ],
                [lower, lower, upper, upper],
            );
            fillcolor = :orange, fillalpha = 0.3, linecolor = :transparent,
            label = i == 1 ? "level_difference_threshold (global)" : "",
        )
        isempty(label) && continue
        limit = label == "min_upstream_level" ? lower : upper
        plot!(
            diagram, [basin_left(left, limit), basin_right(right, limit)], [limit, limit];
            color = label == "min_upstream_level" ? :darkorange : :purple,
            linestyle = :dash, linewidth = 2, label = "$label (local)",
        )
    end

    for (i, left) in enumerate(is_resistance ? (0.5, 7.5) : (0.5,))
        right = left + 4
        plot!(
            diagram,
            Shape(
                [left + 0.6, right - 0.6, basin_right(right, 4.9), basin_left(left, 4.9)],
                [4.6, 4.6, 4.9, 4.9],
            );
            fillcolor = :teal, fillalpha = 0.8, linecolor = :transparent,
            label = i == 1 ? "depth_threshold (global)" : "",
        )
    end

    connector_level = min(upstream_level, downstream_level)
    plot!(
        diagram, [basin_right(4.5, connector_level), basin_left(7.5, connector_level)],
        [connector_level, connector_level];
        color = "#3690c0", linewidth = 2, arrow = is_resistance ? :both : true,
        label = is_manning ? "length (local)" : "",
    )
    scatter!(
        diagram, [6], [connector_level];
        markershape = is_manning ? :dtriangle : (is_resistance ? :utriangle : (is_rating_curve ? :diamond : (gravity_driven ? :pentagon : :hexagon))),
        markersize = 18,
        color = is_manning ? "#F0E442" : (is_resistance ? "#009E73" : (is_rating_curve ? "#CC79A7" : (gravity_driven ? :chocolate : :grey))),
        label = "",
    )
    if is_manning
        return plot(
            diagram, plot_manning_profile();
            layout = (2, 1), size = (768, 900),
        )
    end
    return diagram
end

function plot_manning_profile()
    profile = plot(;
        xlims = (-4, 4), ylims = (-1, 3.2), size = (768, 380),
        aspect_ratio = :equal,
        axis = false, ticks = false, grid = false, legend = :outerbottom,
        margin = 5Plots.mm,
    )
    width = 2.0
    slope = 1.2
    depth = 1.8
    surface_half_width = width / 2 + slope * depth
    plot!(
        profile,
        Shape(
            [-width / 2, width / 2, surface_half_width, -surface_half_width],
            [0, 0, depth, depth],
        );
        fillcolor = :lightblue, fillalpha = 0.5, linecolor = :transparent, label = "",
    )
    plot!(
        profile, [-surface_half_width, surface_half_width], [depth, depth];
        color = :steelblue, linewidth = 2, label = "",
    )
    plot!(
        profile,
        [-width / 2 - slope * 2.5, -width / 2, width / 2, width / 2 + slope * 2.5],
        [2.5, 0, 0, 2.5];
        color = :black, linewidth = 2, label = "",
    )
    plot!(
        profile, [-surface_half_width, -width / 2, width / 2, surface_half_width],
        [depth, 0, 0, depth];
        color = :saddlebrown, linewidth = 4, label = "manning_n (local)",
    )
    plot!(
        profile, [-width / 2, width / 2], [-0.4, -0.4];
        color = :darkorange, linewidth = 2, label = "profile_width (local)",
    )
    for x in (-width / 2, width / 2)
        plot!(profile, [x, x], [-0.5, -0.3]; color = :darkorange, label = "")
    end
    plot!(
        profile, [width / 2, width / 2 + slope], [1, 1];
        color = :purple, linewidth = 2, label = "profile_slope (local)",
    )
    plot!(
        profile, [width / 2, width / 2], [0, 1];
        color = :purple, linestyle = :dot, label = "",
    )
    annotate!(profile, width / 2 - 0.2, 0.5, text("1", 10))
    return profile
end
