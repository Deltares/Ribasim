import sys
from pathlib import Path

import coverage
from qgis.testing import unittest

testfolder = Path(__file__).parent


def run_all():
    test_loader = unittest.defaultTestLoader
    test_suite = test_loader.discover(".", pattern="test_*.py")

    cov = coverage.Coverage(config_file=testfolder.parent / ".coveragerc")
    cov.start()
    unittest.TextTestRunner(verbosity=3, stream=sys.stdout).run(test_suite)

    cov.stop()
    cov.save()
    cov.xml_report(outfile=testfolder / "coverage.xml")
