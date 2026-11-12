"""The river coupling works: every day, the runoff Wflow exports arrives in Ribasim.

Uses `coupling_diagnostics.csv` written by online.jl, with one row per coupled timestep.
Drawn for the right half of the results slide; the left half holds the outflow comparison.
"""

import matplotlib.pyplot as plt
import pandas as pd
from common import (
    DIAGNOSTICS,
    HALF_CONTENT_BOX,
    START,
    C,
    badge,
    save,
    setup_style,
    slide_title,
)

setup_style()
diag = pd.read_csv(DIAGNOSTICS)
diag["date"] = (
    START + pd.to_timedelta(diag.time_seconds, unit="s") - pd.Timedelta(days=1)
)
max_error = diag.error_m3s.abs().max()

fig, ax = plt.subplots(figsize=(8, 7))
slide_title(
    fig,
    "The river coupling works",
    "Daily runoff exchange Wflow → Ribasim, Piave, July 2010",
)
ax.bar(
    diag.date,
    diag.wflow_export_m3s,
    width=0.8,
    color=C["wflow"],
    alpha=0.85,
    label="exported by Wflow river cells",
)
ax.scatter(
    diag.date,
    diag.ribasim_injected_m3s,
    s=70,
    color=C["ribasim"],
    edgecolor="white",
    lw=1.5,
    zorder=3,
    label="received by Ribasim",
)
ax.set_ylabel("runoff  [m³/s]")
ax.set_ylim(0, diag.wflow_export_m3s.max() * 1.6)
ax.legend(loc="upper right", bbox_to_anchor=(1.0, 0.86), fontsize=14)
ax.grid(axis="y", color=C["light"])
ax.xaxis.set_major_locator(plt.matplotlib.dates.DayLocator(bymonthday=[1, 15, 29]))
ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter("%d %b"))
badge(
    ax,
    0.03,
    0.93,
    f"water conserved: max mismatch {max_error:.0e} m³/s",
    C["ribasim"],
    fontsize=15,
    ha="left",
    transform=ax.transAxes,
)
fig.tight_layout()

save(fig, "06_river_exchange.png", box=HALF_CONTENT_BOX)
