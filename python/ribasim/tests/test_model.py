from matplotlib import axes


def test(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"

    # Plotting
    ax = basic.plot()
    assert isinstance(ax, axes._axes.Axes)
