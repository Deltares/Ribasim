"""
A widget that displays the available input layers in the GeoPackage.

It also allows enabling or disabling individual elements for a computation.
"""

from __future__ import annotations

from collections.abc import Callable
from contextvars import ContextVar
from datetime import datetime
from functools import partial
from pathlib import Path
from typing import Any, cast

import pandas as pd
from osgeo import ogr
from PyQt5.QtCore import QDateTime, QVariant
from PyQt5.QtWidgets import (
    QFileDialog,
    QHBoxLayout,
    QLineEdit,
    QMenu,
    QPushButton,
    QVBoxLayout,
    QWidget,
)
from qgis.core import (
    Qgis,
    QgsDateTimeRange,
    QgsEditorWidgetSetup,
    QgsExpressionContextUtils,
    QgsFeatureRequest,
    QgsField,
    QgsInterval,
    QgsLayerTreeGroup,
    QgsMapLayer,
    QgsProject,
    QgsRelation,
    QgsTemporalNavigationObject,
    QgsVectorLayer,
    QgsVectorLayerTemporalProperties,
)

from ribasim_qgis.core.model import (
    get_database_path_from_model_file,
    get_directory_path_from_model_file,
    get_toml_dict,
)
from ribasim_qgis.core.nodes import (
    STYLE_DIR,
    load_nodes_from_geopackage,
)

group_position_var: ContextVar[int] = ContextVar("group_position", default=0)


class DatasetWidget(QWidget):
    def __init__(self, parent: QWidget):
        from ribasim_qgis.widgets.ribasim_widget import RibasimWidget

        super().__init__(parent)

        self.ribasim_widget = cast(RibasimWidget, parent)
        self.dataset_line_edit = QLineEdit()
        self.dataset_line_edit.setEnabled(False)  # Just used as a viewing port
        self.open_model_button = QPushButton("Open")
        self.open_model_button.clicked.connect(self.open_model)
        self.link_layer: QgsVectorLayer | None = None
        self.node_layer: QgsVectorLayer | None = None

        # Results
        self.flow_layer: QgsVectorLayer | None = None
        self.basin_layer: QgsVectorLayer | None = None
        self.concentration_layer: QgsVectorLayer | None = None
        self.allocation_layer: QgsVectorLayer | None = None
        self.allocation_flow_layer: QgsVectorLayer | None = None
        self.results: dict[str, pd.DataFrame] = {}

        # Remove our references to layers when they are about to be deleted
        instance = QgsProject.instance()
        if instance is not None:
            instance.layersWillBeRemoved.connect(self.remove_results)

        # Layout
        dataset_layout = QVBoxLayout()
        dataset_row = QHBoxLayout()
        dataset_row.addWidget(self.dataset_line_edit)
        dataset_row.addWidget(self.open_model_button)
        dataset_layout.addLayout(dataset_row)
        self.setLayout(dataset_layout)
        self.add_reload_context()

    def remove_results(self, layer_ids: list[str]) -> None:
        """Remove Python references to layers that will be deleted."""
        for attr, layer in self._layers():
            if layer is not None and layer.id() in layer_ids:
                setattr(self, attr, None)

    def _layers(self) -> list[tuple[str, QgsVectorLayer | None]]:
        """Return a list of tuples with layer names and their references."""
        return [
            ("link_layer", self.link_layer),
            ("node_layer", self.node_layer),
            ("flow_layer", self.flow_layer),
            ("basin_layer", self.basin_layer),
            ("concentration_layer", self.concentration_layer),
            ("allocation_layer", self.allocation_layer),
            ("allocation_flow_layer", self.allocation_flow_layer),
        ]

    @property
    def path(self) -> Path:
        """Returns currently active path to Ribasim model (.toml)."""
        return Path(self.dataset_line_edit.text())

    def add_layer(
        self,
        layer: Any,
        destination: Any,
        on_top: bool = False,
        labels: Any = None,
    ) -> QgsMapLayer | None:
        self.ribasim_widget.add_layer(
            layer,
            destination,
            on_top,
            labels,
        )
        layer.setCustomProperty("ribasim_path", self.path.as_posix())
        return layer

    def add_item_to_qgis(self, item) -> None:
        layer, labels = item.from_geopackage()
        self.add_layer(layer, "Input", labels=labels)

        item.set_editor_widget()
        item.set_read_only()
        return

    @staticmethod
    def add_relationship(from_layer, to_layer_id, name, fk="node_id") -> None:
        rel = QgsRelation()
        rel.setReferencingLayer(from_layer.id())
        rel.setReferencedLayer(to_layer_id)
        rel.setName(name)
        rel.setStrength(rel.RelationStrength.Composition)  # type: ignore
        rel.addFieldPair(fk, "node_id")
        rel.generateId()
        instance = QgsProject.instance()
        assert instance is not None
        rel_manager = instance.relationManager()
        assert rel_manager is not None
        rel_manager.addRelation(rel)

        # Also use the relationship as an editor widget
        field_index = from_layer.fields().indexFromName(fk)
        setup = QgsEditorWidgetSetup(
            "RelationReference",
            {
                "Relation": rel.id(),
                "MapIdentification": True,
            },
        )
        from_layer.setEditorWidgetSetup(field_index, setup)

    def load_geopackage(self) -> None:
        """Load the layers of a GeoPackage into the Layers Panel."""
        geo_path = get_database_path_from_model_file(self.path)
        nodes = load_nodes_from_geopackage(geo_path)

        name = self.path.stem
        parent = self.path.parent.stem
        self.ribasim_widget.create_groups(f"{parent}/{name}")

        # Make sure "Node", "Link", "Basin / area" are the top three layers
        node = nodes.pop("Node")
        self.add_item_to_qgis(node)
        # Make sure node_id shows up in relationships
        node.layer.setDisplayExpression("node_id")

        link = nodes.pop("Link")
        self.add_item_to_qgis(link)
        self.add_relationship(
            link.layer, node.layer.id(), "LinkFromNode", "from_node_id"
        )
        self.add_relationship(link.layer, node.layer.id(), "LinkToNode", "to_node_id")

        basin_area_layer = nodes.pop("Basin / area", None)
        if basin_area_layer is not None:
            self.add_item_to_qgis(basin_area_layer)
            self.add_relationship(
                basin_area_layer.layer, node.layer.id(), "Basin / area"
            )

        # Add the remaining layers
        for table_name, node_layer in nodes.items():
            self.add_item_to_qgis(node_layer)
            self.add_relationship(node_layer.layer, node.layer.id(), table_name)

        # Connect node and link layer to derive connectivities.
        self.node_layer = node.layer
        assert self.node_layer is not None
        self.link_layer = link.layer

        def filterbyrel(relationships, feature_ids):
            """Filter all related tables by the selected features in the node table."""
            ids = []
            selection = QgsFeatureRequest().setFilterFids(feature_ids)
            for rel in relationships:
                for feature in rel.referencedLayer().getFeatures(selection):
                    ids.extend(f.id() for f in rel.getRelatedFeatures(feature))

            rel.referencingLayer().selectByIds(ids)

        # When the Node selection changes, filter all related tables
        link_rels = []
        instance = QgsProject.instance()
        assert instance is not None
        rel_manager = instance.relationManager()
        assert rel_manager is not None
        for rel in rel_manager.relations().values():
            # Link relations are special, they have two references to the Node table
            referencing = rel.referencingLayer()
            referenced = rel.referencedLayer()
            assert referencing is not None
            assert referenced is not None

            if referencing.name() == "Link":
                link_rels.append(rel)
            else:
                referenced.selectionChanged.connect(partial(filterbyrel, [rel]))

        self.node_layer.selectionChanged.connect(partial(filterbyrel, link_rels))
        return

    def open_model(self) -> None:
        """Open a Ribasim model file."""
        path, _ = QFileDialog.getOpenFileName(self, "Select file", "", "*.toml")
        self._open_model(path)

    def _open_model(self, path: str) -> None:
        if path != "":  # Empty string in case of cancel button press
            self.dataset_line_edit.setText(path)
            self.set_current_time_extent()
            self.load_geopackage()
            self.add_topology_context()
            self.refresh_results()

    @staticmethod
    def activeGroup(iface):
        ltv = iface.layerTreeView()

        i = ltv.selectionModel().currentIndex()
        if not i.isValid():
            return
        group = ltv.index2node(i)
        if isinstance(group, QgsLayerTreeGroup):
            return group

    def add_reload_context(self) -> None:
        """Connect to the layer context (right-click) menu opening."""
        ltv = self.ribasim_widget.iface.layerTreeView()
        if ltv is not None:
            ltv.contextMenuAboutToShow.connect(self.generate_reload_action)

    def generate_reload_action(self, menu: QMenu) -> None:
        """Generate reload action in the context menu."""
        print("Generating reload action in context menu...")
        for action in menu.actions():
            if action.text() == "Ribasim: Reload":
                return

        group = self.activeGroup(self.ribasim_widget.iface)
        if not group or group.name() in ("Input", "Results"):
            return

        path = None
        for child in group.findLayers():
            path = child.layer().customProperty("ribasim_path")
            if path is not None:
                break
        if path is None:
            return

        # Always add action, as it lives only during this context menu
        menu.addSeparator()
        action = menu.addAction("Reload Ribasim model")
        action.triggered.connect(partial(self.reload_action, path, group))

    def reload_action(self, path, group) -> None:
        """Remove group, and (re)load the model in the same position."""
        parent = group.parent()
        position = parent.children().index(group)
        parent.removeChildNode(group)
        token = group_position_var.set(position)
        self._open_model(path)
        group_position_var.reset(token)

    def add_topology_context(self) -> None:
        """Connect to the layer context (right-click) menu opening."""
        ltv = self.ribasim_widget.iface.layerTreeView()
        if ltv is not None:
            ltv.contextMenuAboutToShow.connect(self.generate_topology_action)

    def generate_topology_action(self, menu: QMenu) -> None:
        """Generate checkable show topology action in the context menu."""
        for action in menu.actions():
            if action.text() == "Show topology":
                return

        layer = self.ribasim_widget.iface.activeLayer()
        if (
            not layer
            or layer.type() != Qgis.LayerType.Vector
            or ("Link" not in layer.name() and "Flow" not in layer.name())
        ):
            return

        # We store the state as a variable in the layer context (properties->variables)
        # This variable can be used by the layers style to show the topology.
        scope = QgsExpressionContextUtils.layerScope(layer)
        checked = scope is not None and scope.variable("layer_topology") == "True"

        # Always add action, as it lives only during this context menu
        menu.addSeparator()
        action = menu.addAction("Show topology")
        action.setCheckable(True)
        action.setChecked(checked)
        action.triggered.connect(self.show_topology)

    def show_topology(self, checked: bool) -> None:
        """Set the topology switch variable and redraw the layer."""
        layer = self.ribasim_widget.iface.activeLayer()
        if layer is None:
            return

        value = "True" if checked else "False"
        QgsExpressionContextUtils.setLayerVariable(
            layer,
            "layer_topology",
            value,
        )
        layer.triggerRepaint()

    def refresh_results(self) -> None:
        self._set_node_results()
        self._set_link_results()
        canvas = self.ribasim_widget.iface.mapCanvas()
        assert canvas is not None
        temporalController = canvas.temporalController()
        assert temporalController is not None
        temporalController.updateTemporalRange.connect(self._update_arrow_layers)

    def get_current_time(self) -> datetime:
        """Retrieve the current (frame) time from the temporal controller."""
        canvas = self.ribasim_widget.iface.mapCanvas()
        assert canvas is not None
        temporalController = canvas.temporalController()
        assert temporalController is not None
        temporalController = cast(QgsTemporalNavigationObject, temporalController)
        f = temporalController.currentFrameNumber()
        currentDateTimeRange = temporalController.dateTimeRangeForFrameNumber(f)
        return currentDateTimeRange.begin().toPyDateTime()

    def set_current_time_extent(self) -> None:
        """Set the current time extent and interval of the temporal controller."""
        toml = get_toml_dict(self.path)

        canvas = self.ribasim_widget.iface.mapCanvas()
        assert canvas is not None
        temporalController = canvas.temporalController()
        assert temporalController is not None
        temporalController = cast(QgsTemporalNavigationObject, temporalController)

        trange = QgsDateTimeRange(
            QDateTime(toml["starttime"]), QDateTime(toml["endtime"])
        )
        canvas.setTemporalRange(trange)
        temporalController.setTemporalExtents(trange)
        temporalController.setFrameDuration(
            QgsInterval(toml.get("solver", {}).get("timestep", 86400))
        )
        canvas.setTemporalController(temporalController)

    def _set_node_results(self) -> None:
        node_layer = self.ribasim_widget.node_layer
        assert node_layer is not None
        path = self._set_results(node_layer, "node_id", "basin.arrow")
        if path.exists():
            df = self._add_arrow_layer(path)
            self.basin_layer = self._duplicate_layer(
                node_layer, "Basin", "node_id", "node_type", "Basin"
            )
            assert self.basin_layer is not None
            self._edit_arrow_layer(df, self.basin_layer, "node_id")

        # Add the concentration output
        path = (
            get_directory_path_from_model_file(
                self.ribasim_widget.path, property="results_dir"
            )
            / "concentration.arrow"
        )
        if path.exists():
            df = self._add_arrow_layer(path, postprocess_concentration_arrow)
            self.concentration_layer = self._duplicate_layer(
                node_layer, "Concentration", "node_id", "node_type", "Basin"
            )
            assert self.concentration_layer is not None
            self._edit_arrow_layer(
                df,
                self.concentration_layer,
                "node_id",
            )

        # Add the allocation output
        path = (
            get_directory_path_from_model_file(
                self.ribasim_widget.path, property="results_dir"
            )
            / "allocation.arrow"
        )
        if path.exists():
            df = self._add_arrow_layer(path, postprocess_allocation_arrow)
            self.allocation_layer = self._duplicate_layer(
                node_layer, "Allocation", "node_id", fids=list(df["node_id"].unique())
            )
            assert self.allocation_layer is not None
            self._edit_arrow_layer(df, self.allocation_layer, "node_id")

    def _set_link_results(self) -> None:
        link_layer = self.ribasim_widget.link_layer
        assert link_layer is not None
        path = self._set_results(link_layer, "link_id", "flow.arrow")
        if path.exists():
            df = self._add_arrow_layer(path, postprocess_flow_arrow)
            self.flow_layer = self._duplicate_layer(
                link_layer, "Flow", "link_id", "link_type", "flow"
            )
            assert self.flow_layer is not None
            self._edit_arrow_layer(df, self.flow_layer, "link_id")

        # Add the allocation flow output
        path = (
            get_directory_path_from_model_file(
                self.ribasim_widget.path, property="results_dir"
            )
            / "allocation_flow.arrow"
        )
        if path.exists():
            df = self._add_arrow_layer(path, postprocess_allocation_flow_arrow)
            self.allocation_flow_layer = self._duplicate_layer(
                link_layer,
                "AllocationFlow",
                "link_id",
                fids=list(df["link_id"].unique()),
            )
            assert self.allocation_flow_layer is not None
            self._edit_arrow_layer(
                df,
                self.allocation_flow_layer,
                "link_id",
            )

    def _duplicate_layer(
        self, layer, name, fid_column, filterkey=1, filtervalue=1, fids=None
    ):
        """Duplicate a layer for use with output data."""
        if fids is None:
            duplicate = layer.materialize(
                QgsFeatureRequest().setFilterExpression(
                    f"{filterkey} = '{filtervalue}'"
                )
            )
        else:
            duplicate = layer.materialize(QgsFeatureRequest().setFilterFids(fids))

        duplicate.setName(name)
        fn = STYLE_DIR / f"{name}Style.qml"
        if fn.exists():
            duplicate.loadNamedStyle(str(fn))

        # The fids of a duplicated layer in memory are not the same
        # as our node/link_ids anymore, and can't be set as such.
        # To update the layer with arrow data we need to guarantee
        # both types of ids are sorted, so we can use the new fids.
        fids = []
        rids = []
        for feature in duplicate.getFeatures():
            fids.append(feature.id())
            rids.append(feature[fid_column])
        if sorted(fids) != fids or sorted(rids) != rids:
            self.ribasim_widget.iface.messageBar().pushMessage(
                "Ribasim",
                "Cannot duplicate layer, fids are not sorted",
                level=Qgis.Critical,
                duration=3,
            )
            return

        maplayer = self.add_layer(duplicate, "Results", False, labels=None)

        toml = get_toml_dict(self.path)
        trange = QgsDateTimeRange(
            QDateTime(toml["starttime"]), QDateTime(toml["endtime"])
        )
        tprop = maplayer.temporalProperties()
        tprop.setMode(QgsVectorLayerTemporalProperties.ModeFixedTemporalRange)
        tprop.setFixedTemporalRange(trange)
        tprop.setIsActive(True)

        return duplicate

    def _add_arrow_layer(
        self,
        path: Path,
        postprocess: Callable[[pd.DataFrame], pd.DataFrame] = lambda df: df.set_index(
            pd.DatetimeIndex(df["time"])
        ),
    ) -> pd.DataFrame:
        """Add arrow output data to the layer and setup its update mechanism."""
        try:
            from pyarrow.feather import read_feather

            df = read_feather(path, memory_map=True)
        except ImportError:
            dataset = ogr.Open(path)
            dlayer = dataset.GetLayer(0)
            stream = dlayer.GetArrowStreamAsNumPy()
            data = stream.GetNextRecordBatch()
            if data is None:
                # No rows, but we still need the columns so we can groupby
                # Get column names from the layer definition
                # Correct dtypes don't matter, object is fine
                layer_defn = dlayer.GetLayerDefn()
                columns = [
                    layer_defn.GetFieldDefn(i).GetName()
                    for i in range(layer_defn.GetFieldCount())
                ]
                df = pd.DataFrame(columns=columns)
            else:
                df = pd.DataFrame(data=data)

            # The OGR path introduces strings columns as bytes
            for column in df.columns:
                if df.dtypes[column] == object:  # noqa: E721
                    df[column] = df[column].str.decode("utf-8")

        df = postprocess(df)
        self.results[path.stem] = df
        return df

    def _edit_arrow_layer(
        self,
        df: pd.DataFrame,
        layer: QgsVectorLayer,
        fid_column: str,
        postprocess: Callable[[pd.DataFrame], pd.DataFrame] = lambda df: df.set_index(
            pd.DatetimeIndex(df["time"])
        ),
    ) -> None:
        """Add arrow output data to the layer and setup its update mechanism."""
        # Add the arrow fields to the layer if they doesn't exist
        layer.startEditing()
        for column in df.columns.tolist():
            if (
                column == fid_column or column == "time"
            ):  # skip the fid (link/node_id) column
                continue
            dataprovider = layer.dataProvider()
            if dataprovider is not None and dataprovider.fieldNameIndex(column) == -1:
                dataprovider.addAttributes([QgsField(column, QVariant.Double)])
            layer.updateFields()
        layer.commitChanges()

        self._update_arrow_layer(
            layer, df, fid_column, self.get_current_time(), force=True
        )

    def _update_arrow_layer(
        self,
        layer: QgsVectorLayer | None,
        df: pd.DataFrame | None,
        fid_column: str,
        time: datetime,
        force: bool = False,
    ) -> None:
        """Update the layer with the current arrow time slice."""
        if layer is None or df is None:
            return

        # If we're out of bounds, do nothing, assuming
        # the previous time slice is most valid, unless forced
        # to update on initial load (without a valid datetime).
        if time not in df.index:
            if force and len(df.index) > 0:
                time = df.index[-1]
            else:
                print(f"Skipping update, out of bounds for {time}")
                return

        timeslice = df.loc[[time], :]

        layer.startEditing()
        layer.beginEditCommand("Group all undos for performance.")

        fids = sorted(layer.allFeatureIds())
        if not len(fids) == len(timeslice):
            print(
                f"Can't join data at {time}, shapes of Link and Allocation tables differ."
            )
            layer.endEditCommand()
            layer.commitChanges()
            return

        for column in df.columns.tolist():
            if (
                column == fid_column or column == "time"
            ):  # skip the fid (link/node_id) column
                continue
            dataprovider = layer.dataProvider()
            assert dataprovider is not None
            column_id = dataprovider.fieldNameIndex(column)
            for fid, variable in zip(fids, timeslice[column]):
                layer.changeAttributeValue(
                    fid,
                    column_id,
                    variable,
                )

        layer.endEditCommand()
        layer.commitChanges()

    def _update_arrow_layers(self, timerange: QgsDateTimeRange) -> None:
        """Update the result layers with the current arrow time slice."""
        # Handle edge case when disabling the temporal controller
        if timerange.isEmpty() or timerange.isInfinite():
            return

        time = timerange.begin().toPyDateTime()
        self._update_arrow_layer(
            self.basin_layer, self.results.get("basin"), "node_id", time
        )
        self._update_arrow_layer(
            self.flow_layer, self.results.get("flow"), "link_id", time
        )
        self._update_arrow_layer(
            self.concentration_layer,
            self.results.get("concentration"),
            "node_id",
            time,
        )
        self._update_arrow_layer(
            self.allocation_layer,
            self.results.get("allocation"),
            "node_id",
            time,
        )
        self._update_arrow_layer(
            self.allocation_flow_layer,
            self.results.get("allocation_flow"),
            "link_id",
            time,
        )

    def _set_results(
        self,
        layer: QgsVectorLayer,
        column: str,
        output_file_name: str,
    ) -> Path:
        path = (
            get_directory_path_from_model_file(
                self.ribasim_widget.path, property="results_dir"
            )
            / output_file_name
        )
        if layer is not None:
            layer.setCustomProperty("arrow_type", "timeseries")
            layer.setCustomProperty("arrow_path", str(path))
            layer.setCustomProperty("arrow_fid_column", column)

        return path


def postprocess_concentration_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the concentration arrow data to a wide format."""
    ndf = pd.pivot_table(df, columns="substance", index=["time", "node_id"])
    ndf.columns = ndf.columns.droplevel(0)
    ndf.reset_index("node_id", inplace=True)
    return ndf


def postprocess_allocation_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the allocation arrow data to a wide format by summing over priorities."""
    ndf = df.groupby(["time", "node_id"]).aggregate(
        {"demand": "sum", "allocated": "sum", "realized": "sum"}
    )
    ndf.reset_index("node_id", inplace=True)
    return ndf


def postprocess_allocation_flow_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the allocation flow arrow data to a wide format by summing over priorities."""
    ndf = df.groupby(["time", "link_id"]).aggregate({"flow_rate": "sum"})
    # Drop Basin to Basin flows, as we can't join/visualize them
    ndf.drop(ndf[ndf.index.get_level_values("link_id") == 0].index, inplace=True)
    ndf.reset_index("link_id", inplace=True)
    return ndf


def postprocess_flow_arrow(df: pd.DataFrame) -> pd.DataFrame:
    """Postprocess the allocation flow arrow data to a wide format by summing over priorities."""
    ndf = df.set_index(pd.DatetimeIndex(df["time"]))
    ndf.drop(columns=["time", "from_node_id", "to_node_id"], inplace=True)
    return ndf
