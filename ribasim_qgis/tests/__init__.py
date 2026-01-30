import sys
from pathlib import Path

from qgis.testing import unittest

testfolder = Path(__file__).parent


def run_all():
    test_loader = unittest.defaultTestLoader
    test_suite = test_loader.discover(".", pattern="test_*.py")

    # Coverage is optional - may not work in all environments (e.g., Docker)
    cov = None
    try:
        import coverage

        cov = coverage.Coverage(config_file=testfolder.parent / ".coveragerc")
        cov.start()
    except Exception:  # noqa: S110
        pass

    unittest.TextTestRunner(verbosity=3, stream=sys.stdout).run(test_suite)

    if cov is not None:
        try:
            cov.stop()
            cov.save()
            cov.xml_report(outfile=testfolder / "coverage.xml")
        except Exception as e:
            print(f"Coverage report skipped: {e}")
