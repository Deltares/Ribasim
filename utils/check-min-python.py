"""Check that Python is the lowest version that the Python packages support.

This runs in the min environment, which tests the lower bounds of the dependencies.
"""

import sys
import tomllib
from pathlib import Path

from packaging.specifiers import SpecifierSet
from packaging.version import Version

root = Path(__file__).parent.parent
python = Version(f"{sys.version_info.major}.{sys.version_info.minor}")

for path in sorted(root.glob("python/*/pyproject.toml")):
    requires_python = tomllib.loads(path.read_text())["project"]["requires-python"]
    lower_bounds = [
        Version(spec.version)
        for spec in SpecifierSet(requires_python)
        if spec.operator == ">="
    ]
    if lower_bounds != [python]:
        sys.exit(
            f"Python {python} doesn't match requires-python {requires_python!r} in "
            f"{path.relative_to(root)}, update python in [feature.min.dependencies]"
        )

print(f"Python {python} is the minimum supported version")
