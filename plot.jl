# Plotting functions

using PlotUtils
using Makie

"Create a time axis"
function time!(ax, time)
    # note that the used x values must also be in unix time
    dateticks = optimize_ticks(time[begin], time[end])[1]
    ax.xticks[] = (datetime2unix.(dateticks), Dates.format.(dateticks, "yyyy-mm-dd"))
    ax.xlabel = "time"
    ax.xticklabelrotation = π / 4
    return ax
end

"Plot the results of a single reservoir"
function plot_reservoir(sol, prec, curve; combine_flows = false)

    storage = first.(sol.u)
    outflow_m3s = discharge.(Ref(curve), storage)

    # convert [m³/s] to [m³/day]
    inflows = net_prec.(prec.unixtime) .* 86400
    vad_discharge_m3d = curve.q .* 86400
    outflow = outflow_m3s .* 86400

    fig = Figure(resolution = (1900, 1000))

    # outflow
    ax_q = Axis(fig[1, 1], ylabel = "[m³/day]", xminorgridvisible = true)
    scatterlines!(
        ax_q,
        sol.t,
        outflow,
        label = "outflow",
        color = :black,
        markercolor = :black,
        markersize = 3,
    )

    # inflow
    ax_i = Axis(fig[2, 1], height = 200, ylabel = "[m³/day]")
    if combine_flows
        stairs!(ax_q, prec.unixtime, inflows, color = :blue, step = :post, label = "inflow")
    end
    stairs!(ax_i, prec.unixtime, inflows, color = :black, step = :post, label = "inflow")

    time!(ax_q, period)
    time!(ax_i, period)
    hidexdecorations!(ax_q, grid = false)
    hidexdecorations!(ax_i, grid = false)
    axislegend(ax_q)
    axislegend(ax_i)

    # storage
    ax_v = Axis(fig[3, 1], height = 200, ylabel = "[m³]")
    scatterlines!(
        ax_v,
        sol.t,
        storage,
        label = "storage",
        color = :black,
        markercolor = :black,
        markersize = 3,
    )
    axislegend(ax_v)

    time!(ax_v, period)
    linkxaxes!(ax_q, ax_i, ax_v)

    # discharge-storage relation
    ax_qv =
        Axis(fig[1, 2], width = 400, xlabel = "storage [m³]", ylabel = "discharge [m³/day]")
    scatterlines!(ax_qv, curve.s, vad_discharge_m3d)
    linkyaxes!(ax_q, ax_qv)

    DataInspector(fig)
    return fig
end

nothing
