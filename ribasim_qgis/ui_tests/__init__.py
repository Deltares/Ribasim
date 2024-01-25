import sys

from qgis.testing import unittest


def run_all():
    test_loader = unittest.defaultTestLoader
    test_suite = test_loader.discover(".", pattern="test_*.py")
    unittest.TextTestRunner(verbosity=3, stream=sys.stdout).run(test_suite)
