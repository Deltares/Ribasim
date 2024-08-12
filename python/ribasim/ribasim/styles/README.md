# Ribasim QGIS Styles

One can update the Ribasim styles in QGIS itself, saving the style to the geopackage, and retrieve it from there.
See https://github.com/Deltares/Ribasim/issues/610#issuecomment-1729511312.

Here we store the Node and Edge styles, saved in both the qml and sld format, from the `styleQML` and `styleSLD` attributes in the `layer_styles` in the geopackage, respectively.
