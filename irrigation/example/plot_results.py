"""
Python/matplotlib port of the ``plot_results`` function from ``run_irrigation.jl``.

The function signature mirrors the Julia original:

    plot_results(results, nsteps, initial_total_storage, file, *, icol=0)

Parameters
----------
results : dict
    Dict of 2-D numpy arrays (shape ``n x nsteps``) and a 1-D array for
    ``rec_precip`` (shape ``nsteps``).  Matches the fields of
    ``IrrigationLogger`` in ``irrigation_utils.jl``:

        rec_wt_depth, rec_sat_storage, rec_unsat_storage, rec_actual_et,
        rec_interception, rec_infiltration, rec_infiltration_excess,
        rec_saturated_excess, rec_net_runoff_soil, rec_storage, rec_leakage,
        rec_demand, rec_irrigation, rec_canopy_storage,
        rec_precip   ← 1-D (uniform forcing, same for every cell)

nsteps : int
    Number of time steps that were simulated.
initial_total_storage : float or array-like of float
    Initial combined soil + canopy storage [mm] for each cell (or a single
    float for the single-column case).
file : str or Path
    Output image path (e.g. ``"single_column_no_allocation.png"``).
icol : int, optional
    Zero-based column index to plot.  Default 0 (first / only cell).
"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import netCDF4 as nc
import numpy as np


def read_logger(
    path: str | Path,
) -> tuple[dict, int, np.ndarray, np.ndarray | None, np.ndarray]:
    """Read an ``IrrigationLogger`` NetCDF file written by ``Irrigation.finalize!``.

    Returns
    -------
    results : dict
    nsteps : int
    initial_total_storage : np.ndarray  shape ``(n,)``
    ribasim_node_ids : np.ndarray or None
    irrigated_area_m2 : np.ndarray  shape ``(n,)``
    """
    with nc.Dataset(path, "r") as ds:
        results = {
            name: (
                np.array(
                    ds[name][:]
                ).T  # Julia writes (cell, time) col-major → Python reads (time, cell); transpose back
                if ds[name].ndim == 2
                else np.array(ds[name][:])
            )
            for name in ds.variables
            if name not in ("initial_total_storage", "ribasim_node_id")
        }
        initial_total_storage = np.array(ds["initial_total_storage"][:])
        ribasim_node_ids = (
            np.array(ds["ribasim_node_id"][:])
            if "ribasim_node_id" in ds.variables
            else None
        )
        irrigated_area_m2 = (
            np.array(ds["irrigated_area_m2"][:])
            if "irrigated_area_m2" in ds.variables
            else np.ones(initial_total_storage.shape)
        )
    nsteps = results["rec_precip"].shape[0]
    return results, nsteps, initial_total_storage, ribasim_node_ids, irrigated_area_m2


def read_allocation(path: str | Path) -> dict:
    """Read Ribasim's ``allocation.nc`` result file.

    Returns a dict keyed by ``node_id`` (int), each value being a dict with:
    - ``demand``    : np.ndarray shape ``(ntsteps,)`` [m³/s], summed over priorities
    - ``allocated`` : np.ndarray shape ``(ntsteps,)`` [m³/s], summed over priorities
    - ``supplied``  : np.ndarray shape ``(ntsteps,)`` [m³/s], summed over priorities
    """
    with nc.Dataset(path, "r") as ds:
        node_ids = np.array(ds["node_id"][:])  # (nnodes,)
        # Julia wrote (nprio, nnodes, ntsteps) col-major → Python reads (ntsteps, nnodes, nprio)
        demand = np.array(ds["demand"][:])
        allocated = np.array(ds["allocated"][:])
        supplied = np.array(ds["supplied"][:])

    # Sum over the last axis (demand_priority) to get (ntsteps, nnodes)
    # Replace NaN (unused priority slots) with 0 before summing
    def _sum_prio(arr):
        arr = np.where(np.isnan(arr), 0.0, arr)
        return arr.sum(axis=-1)  # (ntsteps, nnodes)

    demand_sum = _sum_prio(demand)
    allocated_sum = _sum_prio(allocated)
    supplied_sum = _sum_prio(supplied)

    return {
        int(node_ids[j]): {
            "demand": demand_sum[:, j],
            "allocated": allocated_sum[:, j],
            "supplied": supplied_sum[:, j],
        }
        for j in range(len(node_ids))
    }


def plot_results(
    results: dict,
    nsteps: int,
    initial_total_storage: float | list[float] | np.ndarray,
    file: str | Path,
    *,
    icol: int = 0,
    ribasim_node_id: int | None = None,
    allocation: dict | None = None,
    irrigated_area_m2: float = 1.0,
) -> None:
    # ── unpack logger arrays ──────────────────────────────────────────────────
    rec_precip = np.asarray(results["rec_precip"])  # (nsteps,)
    rec_actual_et = np.asarray(results["rec_actual_et"])  # (n, nsteps)
    rec_interception = np.asarray(results["rec_interception"])  # (n, nsteps)
    rec_net_runoff_soil = np.asarray(results["rec_net_runoff_soil"])  # (n, nsteps)
    rec_storage = np.asarray(results["rec_storage"])  # (n, nsteps)
    rec_leakage = np.asarray(results["rec_leakage"])  # (n, nsteps)
    rec_demand = np.asarray(results["rec_demand"])  # (n, nsteps)
    rec_irrigation = np.asarray(results["rec_irrigation"])  # (n, nsteps)
    rec_canopy_storage = np.asarray(results["rec_canopy_storage"])  # (n, nsteps)
    rec_wt_depth = np.asarray(results["rec_wt_depth"])  # (n, nsteps)

    # column slice (Julia uses 1-based; Python uses 0-based icol)
    rec_demand_plot = rec_demand[icol, :]
    rec_irrigation_plot = rec_irrigation[icol, :]
    rec_wt_depth_plot = rec_wt_depth[icol, :]
    rec_actual_et_plot = rec_actual_et[icol, :]
    rec_interception_plot = rec_interception[icol, :]
    rec_net_runoff_plot = rec_net_runoff_soil[icol, :]
    rec_storage_plot = rec_storage[icol, :]
    rec_leakage_plot = rec_leakage[icol, :]
    rec_canopy_storage_plot = rec_canopy_storage[icol, :]

    days = np.arange(1, nsteps + 1)

    # ── derived quantities ────────────────────────────────────────────────────
    initial_storage_col = (
        float(initial_total_storage)
        if np.ndim(initial_total_storage) == 0
        else np.asarray(initial_total_storage)[icol]
    )

    total_storage = rec_storage_plot + rec_canopy_storage_plot  # mm
    delta_storage = np.diff(np.concatenate([[initial_storage_col], total_storage]))

    rec_total_et = rec_actual_et_plot + rec_interception_plot
    rec_net_runoff = rec_net_runoff_plot

    balance_error = (
        (rec_precip + rec_irrigation_plot)
        - rec_total_et
        - rec_net_runoff
        - rec_leakage_plot
        - delta_storage
    )
    print(
        f"\nBalance error (mm/day): "
        f"min={balance_error.min():.3f}  "
        f"max={balance_error.max():.3f}  "
        f"mean={balance_error.mean():.3f}"
    )

    # ── stacked bar components ────────────────────────────────────────────────
    stor_release = np.maximum(-delta_storage, 0.0)
    stor_gain = np.maximum(delta_storage, 0.0)

    # positive side (above zero)
    pos1_top = stor_release
    pos2_top = pos1_top + rec_precip
    pos3_top = pos2_top + rec_irrigation_plot

    # negative side (below zero)
    neg1_bot = -rec_interception_plot
    neg2_bot = neg1_bot - rec_actual_et_plot
    neg3_bot = neg2_bot - rec_net_runoff
    neg4_bot = neg3_bot - rec_leakage_plot
    neg5_bot = neg4_bot - stor_gain

    zeros = np.zeros(nsteps)

    # ── figure layout ─────────────────────────────────────────────────────────
    fig, axes = plt.subplots(4, 1, figsize=(10, 11), sharex=False)
    fig.subplots_adjust(hspace=0.45)

    # ── Panel 1: daily water budget stacked bars ──────────────────────────────
    ax = axes[0]
    ax.set_title("Daily water budget  [+ in / - out]  - land balance")
    ax.set_xlabel("Day")
    ax.set_ylabel("mm/day")
    ax.set_xticks(range(1, nsteps + 1, 5))

    def _bar(ax, bottom, top, color, label=None):
        ax.bar(
            days,
            top - bottom,
            bottom=bottom,
            color=color,
            label=label,
            width=0.8,
            align="center",
        )

    _bar(ax, zeros, pos1_top, (0.855, 0.647, 0.125, 0.85), "Storage release")
    _bar(ax, pos1_top, pos2_top, (0.275, 0.510, 0.706, 0.85), "Precipitation")
    _bar(ax, pos2_top, pos3_top, (0.118, 0.565, 1.000, 0.85), "Irrigation (external)")
    _bar(ax, neg1_bot, zeros, (0.529, 0.808, 0.922, 0.85), "Interception ET")
    _bar(ax, neg2_bot, neg1_bot, (0.180, 0.545, 0.341, 0.85), "Soil AET")
    _bar(
        ax,
        neg3_bot,
        neg2_bot,
        (1.000, 0.647, 0.000, 0.85),
        "Net runoff (infil + sat excess)",
    )
    _bar(ax, neg4_bot, neg3_bot, (0.576, 0.439, 0.859, 0.85), "Leakage")
    _bar(
        ax, neg5_bot, neg4_bot, (0.855, 0.647, 0.125, 0.85)
    )  # stor gain (no legend entry)
    ax.axhline(0, color="black", linewidth=1)
    ax.legend(loc="upper left", fontsize=7)

    # ── Panel 2: water table depth ────────────────────────────────────────────
    ax2 = axes[1]
    ax2.set_title("Water table depth below surface")
    ax2.set_xlabel("Day")
    ax2.set_ylabel("depth [m]")
    ax2.set_xticks(range(1, nsteps + 1, 5))
    ax2.invert_yaxis()
    ax2.plot(days, rec_wt_depth_plot, color="steelblue", linewidth=2)
    ax2.scatter(days, rec_wt_depth_plot, color="steelblue", s=5)

    # ── Panel 3: irrigation demand vs allocation ───────────────────────────────
    ax3 = axes[2]
    ax3.set_title("Irrigation: demand vs allocation")
    ax3.set_xlabel("Day")
    ax3.set_ylabel("mm/day")
    ax3.set_xticks(range(1, nsteps + 1, 5))
    ax3.bar(
        days,
        rec_irrigation_plot,
        color=(0.118, 0.565, 1.000, 0.85),
        label="Allocation (external)",
        width=0.8,
    )
    # stairs: extend last value one step, shift x by -0.5 to match Julia barplot alignment
    stair_x = np.concatenate([days - 0.5, [nsteps + 0.5]])
    stair_y = np.concatenate([rec_demand_plot, [rec_demand_plot[-1]]])
    ax3.step(
        stair_x,
        stair_y,
        where="post",
        color="navy",
        linewidth=2,
        label="Demand (soil moisture deficit)",
    )
    ax3.legend(loc="upper right", fontsize=7)

    # ── Panel 4: cumulative fluxes ────────────────────────────────────────────
    ax4 = axes[3]
    ax4.set_title("Cumulative fluxes")
    ax4.set_xlabel("Day")
    ax4.set_ylabel("mm")
    ax4.set_xticks(range(1, nsteps + 1, 5))
    ax4.plot(
        days,
        np.cumsum(rec_precip),
        color="steelblue",
        linewidth=2,
        label="Precipitation",
    )
    ax4.plot(
        days,
        np.cumsum(rec_irrigation_plot),
        color="dodgerblue",
        linewidth=2,
        label="Irrigation",
    )
    ax4.plot(
        days, np.cumsum(rec_total_et), color="seagreen", linewidth=2, label="Total ET"
    )
    ax4.plot(
        days, np.cumsum(rec_net_runoff), color="orange", linewidth=2, label="Net runoff"
    )
    ax4.plot(
        days,
        np.cumsum(rec_leakage_plot),
        color="mediumpurple",
        linewidth=2,
        label="Leakage",
    )
    ax4.legend(loc="upper left", fontsize=7)

    # ── Panel 5 (optional): Ribasim allocation results ────────────────────────
    if (
        allocation is not None
        and ribasim_node_id is not None
        and ribasim_node_id in allocation
    ):
        fig.set_size_inches(10, 14)  # taller to fit 5th panel
        ax5 = fig.add_subplot(5, 1, 5)
        # reposition existing axes to fit 5 panels
        for i, ax in enumerate(axes):
            ax.set_position([0.125, 0.79 - i * 0.185, 0.775, 0.15])
        ax5.set_position([0.125, 0.79 - 4 * 0.185, 0.775, 0.15])

        node_data = allocation[ribasim_node_id]
        # convert m³/s → mm/day
        area = irrigated_area_m2 if irrigated_area_m2 > 0 else 1.0
        to_mm_day = 1000.0 * 86400.0 / area
        alloc_days = np.arange(1, len(node_data["demand"]) + 1)
        ax5.set_title(f"Ribasim allocation — UserDemand node {ribasim_node_id}")
        ax5.set_xlabel("Day")
        ax5.set_ylabel("mm/day")
        ax5.set_xticks(range(1, nsteps + 1, 5))

        supplied_mm = node_data["supplied"] * to_mm_day
        demand_mm = node_data["demand"] * to_mm_day
        allocated_mm = node_data["allocated"] * to_mm_day

        # bar: supplied (matches the allocation bar in panel 3)
        ax5.bar(
            alloc_days,
            supplied_mm,
            color=(0.118, 0.565, 1.000, 0.85),
            width=0.8,
            label="Supplied",
        )

        # stepped lines: demand and allocated
        stair_x = np.concatenate([alloc_days - 0.5, [len(alloc_days) + 0.5]])
        ax5.step(
            stair_x,
            np.concatenate([demand_mm, [demand_mm[-1]]]),
            where="post",
            color="navy",
            linewidth=2,
            label="Demand",
        )
        ax5.step(
            stair_x,
            np.concatenate([allocated_mm, [allocated_mm[-1]]]),
            where="post",
            color="dodgerblue",
            linewidth=1.5,
            linestyle="--",
            label="Allocated",
        )

        ax5.legend(loc="upper right", fontsize=7)

    fig.savefig(file, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot saved to: {Path(file).resolve()}")
