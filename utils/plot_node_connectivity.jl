using PythonCall

function plot_node_connectivity(node_type::AbstractString)
    pyimport("matplotlib").use("Agg")
    plt = pyimport("matplotlib.pyplot")
    plotting = pyimport("runpy").run_path(joinpath(@__DIR__, "plot_node_connectivity.py"))
    figure = plotting["plot_node_connectivity"](node_type)
    plt.close(figure)
    return figure
end
