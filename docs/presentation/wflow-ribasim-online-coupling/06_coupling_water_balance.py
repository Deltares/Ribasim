"""Water balance of the coupling: everything Wflow exports arrives in Ribasim.

Uses `coupling_diagnostics.csv` written by online.jl, with one row per coupled timestep.
"""

import matplotlib.pyplot as plt
import pandas as pd
from common import DIAGNOSTICS, START, C, badge, save, setup_style, slide_title

setup_style()
diag = pd.read_csv(DIAGNOSTICS)
diag["date"] = (
    START + pd.to_timedelta(diag.time_seconds, unit="s") - pd.Timedelta(days=1)
)
dt = float(diag.time_seconds.diff().dropna().iloc[0])
max_error = diag.error_m3s.abs().max()
relative_error = diag.error_m3s.abs().sum() / diag.wflow_export_m3s.sum()

fig, (ax_runoff, ax_irrigation) = plt.subplots(
    1, 2, figsize=(19, 8.8), gridspec_kw={"width_ratios": [1.35, 1]}
)
fig.subplots_adjust(left=0.06, right=0.98, top=0.78, bottom=0.12, wspace=0.18)
slide_title(
    fig,
    "Is water conserved across the coupling?",
    "Daily exchange in the Piave run (July 2010)",
)

# Runoff exchange: Wflow export (bars) vs Ribasim injected (dots)
ax = ax_runoff
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
    label="received by Ribasim Basins + FlowBoundaries",
)
ax.set_ylabel("runoff  [m³/s]")
ax.set_title("Wflow → Ribasim runoff", loc="left", color=C["wflow"])
ax.legend(loc="upper right", fontsize=13)
ax.grid(axis="y", color=C["light"])
ax.set_ylim(0, diag.wflow_export_m3s.max() * 1.3)
badge(
    ax,
    0.03,
    0.9,
    f"conserved: max mismatch {max_error:.0e} m³/s",
    C["ribasim"],
    fontsize=15,
    ha="left",
    transform=ax.transAxes,
)

# Irrigation: cumulative demand vs supply
ax = ax_irrigation
demand = (diag.irrigation_demand_m3s * dt).cumsum() / 1e3
supplied = (diag.irrigation_supplied_m3s * dt).cumsum() / 1e3
ax.fill_between(
    diag.date,
    0,
    supplied,
    color=C["irrigation"],
    alpha=0.85,
    label="supplied to Wflow cells",
)
ax.fill_between(
    diag.date,
    supplied,
    demand,
    facecolor="none",
    edgecolor=C["shortage"],
    hatch="////",
    lw=0,
    label="shortage",
)
ax.plot(
    diag.date, demand, color=C["dark"], lw=2.5, ls=":", label="demanded by Wflow cells"
)
ax.set_ylabel("cumulative volume  [thousand m³]")
ax.set_title("Ribasim → Wflow irrigation", loc="left", color=C["irrigation"])
ax.legend(loc="upper left", fontsize=13)
ax.grid(axis="y", color=C["light"])
ax.set_ylim(0, demand.max() * 1.25)
share = supplied.iloc[-1] / demand.iloc[-1]
ax.annotate(
    f"{share:.0%} met",
    (diag.date.iloc[-1], supplied.iloc[-1]),
    xytext=(-15, -70),
    textcoords="offset points",
    ha="right",
    fontsize=24,
    fontweight="bold",
    color="white",
)

for ax in (ax_runoff, ax_irrigation):
    ax.xaxis.set_major_locator(
        plt.matplotlib.dates.DayLocator(bymonthday=[1, 8, 15, 22, 29])
    )
    ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter("%d %b"))

fig.text(
    0.06,
    0.03,
    f"Summed over the run, the exchange error is {relative_error:.0e} of the exported runoff (floating-point precision).",
    fontsize=13,
    color=C["muted"],
)

save(fig, "06_coupling_water_balance.png")
