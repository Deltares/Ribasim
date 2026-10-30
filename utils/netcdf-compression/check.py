"""Compare each compression variant with the uncompressed results, see issue #3358."""

import sys
from pathlib import Path

import numpy as np
import xarray as xr

root = Path(sys.argv[1])
ref = root / "results_uncompressed"
failed = False
for variant in sorted(root.glob("results_*")):
    if variant == ref:
        continue
    worst = 0.0
    for path in sorted(ref.glob("*.nc")):
        a = xr.open_dataset(path).load()
        b = xr.open_dataset(variant / path.name).load()
        for name in a.variables:
            x, y = a[name].values, b[name].values
            if name == "computation_time":
                continue
            if x.dtype.kind == "f":
                mask = np.isfinite(x) & (x != 0)
                worst = max(
                    worst, float(np.max(np.abs(y[mask] / x[mask] - 1), initial=0))
                )
            elif not np.array_equal(x, y):
                print(f"{variant.name} {path.name} {name} differs")
                failed = True
    print(f"{variant.name:28} max relative error {worst:.2e}")
    failed |= worst > 2.0**-21
sys.exit(failed)
