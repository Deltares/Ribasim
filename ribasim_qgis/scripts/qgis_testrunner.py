#!/usr/bin/env python

"""
***************************************************************************
    Launches a unit test inside QGIS and exit the application.

    Arguments:

    accepts a single argument with the package name in python dotted notation,
    the program tries first to load the module and launch the `run_all`
    function of the module, if that fails it considers the last part of
    the dotted path to be the function name and the previous part to be the
    module.

    Extra options for QGIS command line can be passed in the env var
    QGIS_EXTRA_OPTIONS

    Example run:

    # Will load geoserverexplorer.test.catalogtests and run `run_all`
    QGIS_EXTRA_OPTIONS='--optionspath .' \
        GSHOSTNAME=localhost \
        python qgis_testrunner.py geoserverexplorer.test.catalogtests


    GSHOSTNAME=localhost \
         python qgis_testrunner.py geoserverexplorer.test.catalogtests.run_my


    ---------------------
    Date                 : May 2016
    Copyright            : (C) 2016 by Alessandro Pasotti
    Email                : apasotti at boundlessgeo dot com
***************************************************************************
*                                                                         *
*   This program is free software; you can redistribute it and/or modify  *
*   it under the terms of the GNU General Public License as published by  *
*   the Free Software Foundation; either version 2 of the License, or     *
*   (at your option) any later version.                                   *
*                                                                         *
***************************************************************************
"""

__author__ = "Alessandro Pasotti"
__date__ = "May 2016"

import importlib
import logging
import os
import signal
import sys
import traceback

from qgis.utils import iface

assert iface is not None


def __get_test_function(test_module_name):
    """Load the test module and return the test function"""
    print(f"QGIS Test Runner - Trying to import {test_module_name}")
    try:
        test_module = importlib.import_module(test_module_name)
        function_name = "run_all"
    except ImportError as e:
        # traceback.print_exc(file=sys.stdout)
        # Strip latest name
        pos = test_module_name.rfind(".")
        if pos <= 0:
            raise e
        test_module_name, function_name = (
            test_module_name[:pos],
            test_module_name[pos + 1 :],
        )
        print(f"QGIS Test Runner - Trying to import {test_module_name}")
        sys.stdout.flush()
        try:
            test_module = importlib.import_module(test_module_name)
        except ImportError as e:
            # traceback.print_exc(file=sys.stdout)
            raise e
    return getattr(test_module, function_name, None)


# Start as soon as the initializationCompleted signal is fired
from qgis.core import QgsApplication, QgsProject, QgsProjectBadLayerHandler
from qgis.PyQt.QtCore import QDir


class QgsProjectBadLayerDefaultHandler(QgsProjectBadLayerHandler):
    def handleBadLayers(self, layers, dom):
        pass


# Monkey patch QGIS Python console
from console.console_output import writeOut


def _write(self, m):
    sys.stdout.write(m)


writeOut.write = _write

# Add current working dir to the python path
sys.path.append(QDir.current().path())


def __exit_qgis(error_code: int):
    app = QgsApplication.instance()
    os.kill(app.applicationPid(), error_code)


def __run_test():
    """Run the test specified as last argument in the command line."""
    # Disable modal handler for bad layers
    QgsProject.instance().setBadLayerHandler(QgsProjectBadLayerDefaultHandler())
    print("QGIS Test Runner Inside - starting the tests ...")
    try:
        test_module_name = QgsApplication.instance().arguments()[-1]
        function_name = __get_test_function(test_module_name)
        print(f"QGIS Test Runner Inside - executing function {function_name}")
        function_name()
        __exit_qgis(signal.SIG_DFL)
    except Exception as e:
        logging.error(f"QGIS Test Runner Inside - [FAILED] Exception: {e}")
        # Print tb
        traceback.print_exc(file=sys.stderr)
        __exit_qgis(signal.SIGTERM)


iface.initializationCompleted.connect(__run_test)
