"""Slides with the original figures from PR #3324 and PR #3333, with numbered callouts.

Run 00_download_source_images.py first. Callout positions are in pixels of the source image:
a dot marks the target and a numbered circle is placed at an offset, connected by a line.
"""

import matplotlib.pyplot as plt
from common import SOURCE_IMAGES, C, save, setup_style, slide_title

# image, output, title, subtitle, callouts [(target_x, target_y, dx, dy, colour, text)]
SLIDES = [
    (
        "pr3324_qgis_mapping.png",
        "09a_pr3324_mapping.png",
        "Mapping Wflow river cells to Ribasim",
        "QGIS view of the Piave proof of concept (PR #3324)",
        [
            (
                303,
                347,
                -75,
                -30,
                C["dark"],
                "Each dot is a Wflow river cell.\nIts label is the Ribasim node\nthat receives its runoff.",
            ),
            (
                311,
                404,
                55,
                45,
                C["water_dark"],
                "Blue areas: Ribasim Basins.\nRiver cells inside add runoff\nto the Basin storage.",
            ),
            (
                560,
                75,
                35,
                -40,
                "#7B4FA0",
                "Purple areas: FlowBoundaries.\nHeadwater runoff enters the\nnetwork as a boundary inflow.",
            ),
        ],
    ),
    (
        "pr3333_schematization.png",
        "09b_pr3333_schematization.png",
        "Irrigation in the coupled model",
        "Test schematization in Ribasim's QGIS plugin (PR #3333)",
        [
            (
                562,
                392,
                45,
                50,
                C["irrigation"],
                "Bright cells: irrigated\nWflow cells with a demand.",
            ),
            (
                425,
                378,
                -50,
                -40,
                C["shortage"],
                "Red squares: one UserDemand per\nBasin ∩ Wflow allocation area.",
            ),
            (
                478,
                452,
                -60,
                30,
                C["water_dark"],
                "The UserDemand abstracts\nfrom its Basin and gives the\nwater to its Wflow cells.",
            ),
            (
                618,
                315,
                50,
                -35,
                C["muted"],
                "Irrigated cells in FlowBoundary\nareas are not coupled (yet).",
            ),
        ],
    ),
    (
        "pr3333_userdemand_results.png",
        "09c_pr3333_results.png",
        "Demand, allocated and realized irrigation",
        "Result of the coupled Piave run, July 2010 (PR #3333)",
        [
            (
                282,
                415,
                238,
                -115,
                C["shortage"],
                "Realized < allocated: the source\nBasin falls below its minimum\nlevel, abstraction stops.",
            ),
            (
                330,
                868,
                270,
                -108,
                C["shortage"],
                "Early July: UserDemand #54\ngets almost nothing although\nits demand is allocated.",
            ),
            (
                960,
                404,
                0,
                -105,
                C["ribasim"],
                "Most days: the demand is\nfully allocated and realized.",
            ),
        ],
    ),
]

setup_style()
for image_name, output, title, subtitle, callouts in SLIDES:
    path = SOURCE_IMAGES / image_name
    if not path.exists():
        print(f"skipping {output}: {path} not found, run 00_download_source_images.py")
        continue
    image = plt.imread(path)

    fig = plt.figure(figsize=(19, 10))
    slide_title(fig, title, subtitle)
    ax = fig.add_axes([0.02, 0.03, 0.62, 0.82])
    ax.imshow(image)
    ax.set_axis_off()
    for k, (tx, ty, dx, dy, color, _) in enumerate(callouts, start=1):
        x, y = tx + dx, ty + dy
        ax.plot([tx, x], [ty, y], color="white", lw=5, zorder=4, solid_capstyle="round")
        ax.plot([tx, x], [ty, y], color=color, lw=2.5, zorder=4, solid_capstyle="round")
        ax.scatter([tx], [ty], s=60, color=color, edgecolor="white", lw=1.5, zorder=5)
        ax.scatter([x], [y], s=1100, color=color, edgecolor="white", lw=3, zorder=6)
        ax.text(
            x,
            y,
            str(k),
            ha="center",
            va="center",
            color="white",
            fontsize=17,
            fontweight="bold",
            zorder=7,
        )

    side = fig.add_axes([0.66, 0.03, 0.33, 0.82])
    side.set_xlim(0, 1)
    side.set_ylim(0, 1)
    side.set_axis_off()
    step = 1.0 / max(len(callouts), 3)
    for k, (*_, color, text) in enumerate(callouts, start=1):
        y = 0.92 - (k - 1) * step
        side.scatter([0.06], [y], s=1300, color=color, clip_on=False)
        side.text(
            0.06,
            y,
            str(k),
            ha="center",
            va="center",
            color="white",
            fontsize=17,
            fontweight="bold",
        )
        side.text(
            0.15, y, text, va="center", fontsize=16, color=C["dark"], linespacing=1.3
        )

    save(fig, output)
