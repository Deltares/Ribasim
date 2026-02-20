import io
import sys
from pathlib import Path

import pytest

testfolder = Path(__file__).parent


def run_all():
    """Run all tests via pytest. Called by qgis_testrunner.py inside a QGIS process."""
    # QGIS sets sys.stdin to None, which crashes some pytest plugins (e.g. teamcity).
    if sys.stdin is None:
        sys.stdin = io.StringIO()

    pytest.main(
        [
            str(testfolder),
            "-v",
            "--tb=short",
            "--no-header",
            "-p",
            "no:teamcity",
        ]
    )
