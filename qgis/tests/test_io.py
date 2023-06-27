import sys

from qgis.testing import unittest


class TestIO(unittest.TestCase):
    def test_passes(self):
        self.assertTrue(True)

    # TODO Open actual geopackage
    def test_open_geopackage(self):
        pass


def run_all():
    suite = unittest.TestSuite()
    suite.addTests(unittest.makeSuite(TestIO, "test"))
    unittest.TextTestRunner(verbosity=3, stream=sys.stdout).run(suite)


if __name__ == "__main__":
    unittest.main()
