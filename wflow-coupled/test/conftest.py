"""Make the coupling scripts importable in the tests."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
