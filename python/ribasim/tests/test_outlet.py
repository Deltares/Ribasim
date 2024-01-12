import pandas as pd
import ribasim

static_data = pd.DataFrame(data={"node_id": [1, 3, 2]})
outletje = ribasim.Terminal(static=static_data)
outletje.static.sort()
outletje.static
