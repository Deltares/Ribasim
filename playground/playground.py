# %%
import shutil
from pathlib import Path

from matplotlib import pyplot as plt
from ribasim.config import Node
from ribasim.model import Model
from ribasim.nodes import basin
from shapely.geometry import Point

# %%
output_dir = Path(__file__).parent / "output"
shutil.rmtree(output_dir, ignore_errors=True)
# %%
model = Model(starttime="2020-01-01 00:00:00", endtime="2021-01-01 00:00:00")
# %%
model.basin.add(
    Node(2, Point(2.0, 3.6)),
    [basin.Profile(area=[1.0, 3.0], level=[1.1, 2.2]), basin.State(level=[1.0])],
)
# %%
model.basin.add(
    Node(1, Point(5.0, 3.6)),
    [basin.Profile(area=[2.0, 4.0], level=[6.1, 7.2]), basin.State(level=[1.0])],
)

# %%
model.edge.add(
    from_node=model.basin[2],
    to_node=model.basin[1],
    edge_type="flow",
)
# %%
_, ax = plt.subplots()
ax.axis("off")
model.basin.node.plot(ax)
model.plot(ax)

# %%
toml_path = output_dir / "ribasim.toml"
model.write(toml_path)
