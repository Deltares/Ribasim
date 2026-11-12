"""The irrigation loop works: demand from Wflow, allocated by Ribasim, realized back to Wflow.

Shows one UserDemand (#53) of the coupled Piave run. Its source Basin and allocation come
from the Ribasim results; the demand is the Wflow irrigation demand passed to Ribasim.
"""

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import xarray as xr
from common import RESULTS, C, save, setup_style, slide_title
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

USER_DEMAND = 53

setup_style()
allocation = xr.open_dataset(RESULTS / "allocation.nc").sum("demand_priority")
node = allocation.sel(node_id=USER_DEMAND)
time = pd.to_datetime(allocation.time.values)
edges = np.r_[time.values, (time[-1] + (time[1] - time[0])).to_datetime64()]
demand = node.demand.values
allocated = node.allocated.values
realized = node.supplied.values

fig, ax = plt.subplots(figsize=(16, 6.5))
slide_title(
    fig,
    "The irrigation loop works",
    f"Irrigation of UserDemand #{USER_DEMAND}, Piave, July 2010: every day from Wflow to Ribasim and back",
)
ax.stairs(realized, edges, fill=True, color=C["irrigation"], alpha=0.85)
ax.stairs(demand, edges, color=C["dark"], lw=3, ls=":")
ax.stairs(allocated, edges, color=C["ribasim"], lw=2.5, ls="--")
ax.set_ylabel("irrigation  [m³/s]")
ax.set_ylim(0, max(demand.max(), allocated.max()) * 1.12)
ax.grid(axis="y", color=C["light"])
ax.set_xticks(pd.date_range(time[0], time[-1], freq="7D"))
ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter("%d %b"))
ax.legend(
    handles=[
        Line2D([], [], color=C["dark"], ls=":", lw=3, label="demand, computed by Wflow"),
        Line2D(
            [], [], color=C["ribasim"], ls="--", lw=2.5, label="allocated by Ribasim"
        ),
        Patch(
            facecolor=C["irrigation"],
            alpha=0.85,
            label="realized, abstracted by Ribasim and applied by Wflow",
        ),
    ],
    loc="upper right",
    fontsize=15,
)
fig.tight_layout()

save(fig, "07_irrigation_loop.png")
