"""Shared node icon metadata and Matplotlib rendering utilities.

This module is the single source of truth for Ribasim node icon definitions
(color/shape metadata) and for drawing those icons with Matplotlib, including
helpers used by runtime plotting and QGIS icon generation scripts.
"""

from dataclasses import dataclass
from typing import Any

import matplotlib.patches as mpatches
import numpy as np
from matplotlib.axes import Axes
from matplotlib.legend import Legend
from matplotlib.legend_handler import HandlerBase
from matplotlib.lines import Line2D
from matplotlib.markers import MarkerStyle
from matplotlib.offsetbox import DrawingArea
from matplotlib.patches import PathPatch
from matplotlib.path import Path as MplPath
from matplotlib.transforms import Affine2D

# ── Drawing constants ─────────────────────────────────────────────
STROKE_COLOR = "black"
STROKE_WIDTH_FILE = 1.5  # linewidth for SVG / PNG file export
STROKE_WIDTH_PLOT = 0.5  # linewidth for interactive matplotlib plots


@dataclass(frozen=True)
class NodeIconSpec:
    """Icon metadata for a single Ribasim node type."""

    node_type: str
    color: str
    shape_code: str
    shape_description: str


NODE_ICON_DATA: tuple[NodeIconSpec, ...] = (
    NodeIconSpec("Basin", "#0072B2", "trapezium", "Trapezium"),
    NodeIconSpec("ManningResistance", "#F0E442", "v", "Down triangle"),
    NodeIconSpec("LinearResistance", "#009E73", "^", "Up triangle"),
    NodeIconSpec("FlowBoundary", "#FF7F00", "o", "Filled circle"),
    NodeIconSpec("LevelBoundary", "#FFFFFF", "o", "Empty circle"),
    NodeIconSpec("TabulatedRatingCurve", "#CC79A7", "D", "Diamond"),
    NodeIconSpec("Pump", "#999999", "H", "Hexagon (flat top)"),
    NodeIconSpec("Outlet", "#D55E00", "pentagon", "Pentagon"),
    NodeIconSpec("UserDemand", "#E41A1C", "s", "Square"),
    NodeIconSpec("LevelDemand", "#E69F00", "half_square_t", "Top half-filled square"),
    NodeIconSpec("FlowDemand", "#228B22", "half_square_b", "Bottom half-filled square"),
    NodeIconSpec("DiscreteControl", "#984EA3", "star5", "5-point star"),
    NodeIconSpec("PidControl", "#006400", "star6", "6-point star"),
    NodeIconSpec("ContinuousControl", "#999999", "star4", "4-point star"),
    NodeIconSpec("Terminal", "#000000", "rectangle", "Horizontal rectangle"),
    NodeIconSpec("Junction", "#000000", "o", "Filled circle"),
    NodeIconSpec("Observation", "#000000", "staff_gauge", "Staff gauge"),
)


NODE_ICON_BY_PASCAL: dict[str, NodeIconSpec] = {
    item.node_type: item for item in NODE_ICON_DATA
}

# Scale factor per shape, applied to patch coordinates directly.
# fmt: off
ICON_SCALE = {
    "rectangle":      2.4,
    "trapezium":      1.1,
    "pentagon":       1.2,
    "star5":          1.8,
    "star6":          1.8,
    "star4":          1.8,
    "half_square_t":  1.2,
    "half_square_b":  1.2,
    "D":              1.8,
    "^":              2.1,
    "v":              2.1,
    "s":              2.35,
    "o":              2.2,
    "H":              2.4,
    "staff_gauge":    1.0,
}
# fmt: on

# Star inner-radius per shape code (num_points derived from the trailing digit).
_STAR_INNER_RADIUS: dict[str, float] = {
    "star4": 0.14,
    "star5": 0.12,
    "star6": 0.12,
}


# ── Low-level patch builders ─────────────────────────────────────
def _stroke(linewidth: float = STROKE_WIDTH_FILE, **overrides: Any) -> dict[str, Any]:
    """Return default stroke kwargs, with optional overrides."""
    return {"edgecolor": STROKE_COLOR, "linewidth": linewidth, **overrides}


def _regular_polygon_verts(n: int, radius: float) -> list[tuple[float, float]]:
    """Return *n* vertices of a regular polygon centered at the origin."""
    return [
        (
            radius * np.cos(i * 2 * np.pi / n - np.pi / 2),
            radius * np.sin(i * 2 * np.pi / n - np.pi / 2),
        )
        for i in range(n)
    ]


def _create_star_patch(
    num_points: int,
    color: str,
    inner_radius: float = 0.1,
    outer_radius: float = 0.25,
    linewidth: float = STROKE_WIDTH_FILE,
) -> PathPatch:
    """Create a star PathPatch centered at the origin."""
    angle_step = 2 * np.pi / (num_points * 2)
    verts = []
    codes = [MplPath.MOVETO]
    for i in range(num_points * 2):
        r = outer_radius if i % 2 == 0 else inner_radius
        verts.append(
            (
                r * np.cos(i * angle_step - np.pi / 2),
                r * np.sin(i * angle_step - np.pi / 2),
            )
        )
        codes.append(MplPath.LINETO)
    verts.append(verts[0])
    codes[-1] = MplPath.CLOSEPOLY
    return PathPatch(MplPath(verts, codes), facecolor=color, **_stroke(linewidth))


def _create_marker_patch(
    marker: str, scale: float, color: str, linewidth: float = STROKE_WIDTH_FILE
) -> PathPatch:
    """Create a scaled PathPatch from a standard Matplotlib marker code."""
    style = MarkerStyle(marker)
    path = style.get_path().transformed(style.get_transform())
    path = path.transformed(Affine2D().scale(0.25 * scale))
    return PathPatch(path, facecolor=color, **_stroke(linewidth))


# ── High-level icon assembly ─────────────────────────────────────
def _create_icon_patches(
    shape: str, color: str, linewidth: float = STROKE_WIDTH_FILE
) -> list[mpatches.Patch]:
    """Return patches for *shape* centered at the origin in [-0.5, 0.5] space."""
    s = ICON_SCALE[shape]
    sk = _stroke(linewidth)

    if shape == "rectangle":
        w, h = 0.4 * s, 0.2 * s
        return [mpatches.Rectangle((-w / 2, -h / 2), w, h, facecolor=color, **sk)]

    if shape == "trapezium":
        tw, bw, hh = 0.3 * s, 0.15 * s, 0.25 * s
        verts = [(-tw, hh), (tw, hh), (bw, -hh), (-bw, -hh)]
        return [mpatches.Polygon(verts, closed=True, facecolor=color, **sk)]

    if shape == "pentagon":
        verts = _regular_polygon_verts(5, radius=0.25 * s)
        return [mpatches.Polygon(verts, closed=True, facecolor=color, **sk)]

    if shape in _STAR_INNER_RADIUS:
        num_points = int(shape[-1])
        return [
            _create_star_patch(
                num_points,
                color,
                inner_radius=_STAR_INNER_RADIUS[shape] * s,
                outer_radius=0.25 * s,
                linewidth=linewidth,
            )
        ]

    if shape in ("half_square_t", "half_square_b"):
        half = 0.25 * s
        bg = mpatches.Rectangle(
            (-half, -half), 2 * half, 2 * half, facecolor="white", **sk
        )
        # Colored half: top (y=0..half) or bottom (y=-half..0)
        y0 = 0.0 if shape.endswith("_t") else -half
        fg = mpatches.Rectangle(
            (-half, y0), 2 * half, half, facecolor=color, edgecolor=STROKE_COLOR
        )
        return [bg, fg]

    if shape == "staff_gauge":
        # Water level staff gauge: vertical post with alternating black/white bands
        w = 0.22  # width of the gauge
        h = 0.80  # total height
        n_bands = 5
        band_h = h / n_bands
        y_bottom = -h / 2
        patches: list[mpatches.Patch] = []
        # Outer border
        patches.append(
            mpatches.Rectangle(
                (-w / 2, y_bottom),
                w,
                h,
                facecolor="white",
                **sk,
            )
        )
        # Alternating black bands (odd bands are black)
        patches.extend(
            mpatches.Rectangle(
                (-w / 2, y_bottom + i * band_h),
                w,
                band_h,
                facecolor="black",
                edgecolor=STROKE_COLOR,
                linewidth=linewidth * 0.5,
            )
            for i in range(n_bands)
            if i % 2 == 0
        )
        return patches

    # Fallback: standard Matplotlib marker (o, s, D, ^, v, H, ...)
    return [_create_marker_patch(shape, s, color, linewidth=linewidth)]


def draw_icon(ax: Axes, shape: str, color: str) -> None:
    """Draw a single node icon centered at (0, 0) on the provided axes."""
    for patch in _create_icon_patches(shape, color):
        ax.add_patch(patch)
    ax.set_xlim(-0.5, 0.5)
    ax.set_ylim(-0.5, 0.5)
    ax.set_aspect("equal", adjustable="box")
    ax.axis("off")


def _icon_shape_and_color(node_type: str) -> tuple[str, str]:
    """Return the icon shape code and color of *node_type*, a black dot if unknown."""
    spec = NODE_ICON_BY_PASCAL.get(node_type)
    if spec is None:
        return "o", "k"
    return spec.shape_code, spec.color


def make_icon_box(node_type: str, size: float = 12.0) -> DrawingArea:
    """Create a vector OffsetBox containing the node icon as patches.

    Returns a ``DrawingArea`` suitable for use inside an ``AnnotationBbox``.
    The patches are the same as those drawn by ``draw_icon`` but scaled to
    *size* points, so they keep the same physical size regardless of zoom and
    figure DPI.

    Parameters
    ----------
    node_type : str
        PascalCase node type name (e.g. ``"Basin"``).
    size : float
        Box width/height in points.
    """
    shape_code, color = _icon_shape_and_color(node_type)
    box = DrawingArea(size, size)
    # Patches are defined around the origin in [-0.5, 0.5] space, the
    # DrawingArea spans [0, size] points.
    to_box = Affine2D().scale(size).translate(size / 2, size / 2) + box.get_transform()
    for patch in _create_icon_patches(shape_code, color, linewidth=STROKE_WIDTH_PLOT):
        patch.set_transform(to_box)
        box.add_artist(patch)
    return box


class NodeIconLegendEntry(Line2D):
    """Invisible stand-in that adds a node type with its icon to the legend.

    Node icons are drawn as ``AnnotationBbox`` artists, which Matplotlib does not
    collect for the legend. Adding this empty line to the axes makes
    ``ax.legend()`` and ``ax.get_legend_handles_labels()`` list the node type,
    drawn by `HandlerNodeIcon`.
    """

    def __init__(self, node_type: str):
        super().__init__([], [], label=node_type)
        self.node_type = node_type


class HandlerNodeIcon(HandlerBase):
    """Legend handler that draws the icon of a `NodeIconLegendEntry`."""

    def create_artists(
        self, legend, orig_handle, xdescent, ydescent, width, height, fontsize, trans
    ):
        """Return the icon patches, centered in the legend handle box."""
        shape_code, color = _icon_shape_and_color(orig_handle.node_type)
        size = 1.5 * height
        transform = (
            Affine2D()
            .scale(size)
            .translate(width / 2 - xdescent, height / 2 - ydescent)
            + trans
        )
        patches = _create_icon_patches(shape_code, color, linewidth=STROKE_WIDTH_PLOT)
        for patch in patches:
            patch.set_transform(transform)
        return patches


Legend.update_default_handler_map({NodeIconLegendEntry: HandlerNodeIcon()})
