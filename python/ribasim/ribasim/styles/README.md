# Ribasim QGIS Styles

Ribasim Python always adds layer styles to the GeoPackage, such that the node types can be recognized also without the Ribasim QGIS plugin installed.

One can update the Ribasim styles in QGIS itself, saving the style to the GeoPackage or disk, and retrieve it from there.
See https://github.com/Deltares/Ribasim/issues/610#issuecomment-1729511312.

Here we store the Node, Basin / area and Link styles, saved in the QML format, from the `styleQML` attribute in the `layer_styles` in the GeoPackage.
