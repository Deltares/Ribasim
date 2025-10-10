# Create Binaries

Build the app and shared library with:

```sh
pixi run build
```

> :warning: If the build is failing, because it cannot find certain files, chances are high that you need to enable long paths in Windows.

## Ribasim CLI

In order to find out about it's usage call `ribasim --help`

## Libribasim

Libribasim is a shared library that exposes Ribasim functionality to external (non-Julian)
programs. It can be compiled using [PackageCompiler's
create_lib](https://julialang.github.io/PackageCompiler.jl/stable/libs.html), which is set
up in this directory. The C API that is offered to control Ribasim is the C API of the
[Basic Model Interface](https://bmi.readthedocs.io/en/latest/), also known as BMI.

Not all BMI functions are implemented yet.
Couplings to other models are implemented in [`imod_coupler`](https://github.com/Deltares/imod_coupler).

Here is an example of using libribasim from Python:

```python
In [1]: from ctypes import CDLL, c_int, c_char_p, create_string_buffer, byref

In [2]: c_dll = CDLL("libribasim", winmode=0x08)  # winmode for Windows

In [3]: config_path = "ribasim.toml"

In [4]: c_dll.initialize(c_char_p(config_path.encode()))
Out[4]: 0

In [5]: c_dll.update()
Out[5]: 0
```
