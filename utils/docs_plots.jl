using Plots

# Quarto prefers text/html, for which Plots writes an <img> tag at the full resolution of the PNG,
# without a size and without the classes that fit it to the page.
# Hide it so Quarto writes the plot to a separate image file like any other figure.
Base.showable(::MIME"text/html", ::Plots.Plot{Plots.GRBackend}) = false
