"""Generate all presentation figures into figures/."""

import runpy
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))

for script in [*sorted(HERE.glob("[0-9][0-9]_*.py")), *sorted(HERE.glob("b[0-9]_*.py"))]:
    print(f"--- {script.name}")
    runpy.run_path(str(script), run_name="__main__")
