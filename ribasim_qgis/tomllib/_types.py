# Copied from https://github.com/python/cpython/blob/v3.12.0/Lib/tomllib/_types.py
# QGIS does not guarantee a toml reader

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2021 Taneli Hukkinen
# Licensed to PSF under a Contributor Agreement.

from typing import Any, Callable, Tuple

# Type annotations
ParseFloat = Callable[[str], Any]
Key = Tuple[str, ...]
Pos = int
