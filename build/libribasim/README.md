# Libribasim

Libribasim is a shared library that exposes Ribasim functionality to external (non-Julian)
programs. It can be compiled using [PackageCompiler's
create_lib](https://julialang.github.io/PackageCompiler.jl/stable/libs.html) , which is set
up in this directory. The C API that is offered to control Ribasim is the C API of the [Basic
Model Interface](https://bmi.readthedocs.io/en/latest/), also known as BMI.

Not all BMI functions are implemented yet, this has been set up as a proof of concept to
demonstrate that we could use other software such as
[`imod_coupler`](https://github.com/Deltares/imod_coupler) to control Ribasim and couple it to
other models.

Here is an example of using libribasim from Python:

```python
In [1]: from ctypes import CDLL, c_int, c_char_p, create_string_buffer, byref

In [2]: c_dll = CDLL("libribasim", winmode=0x08)  # winmode for Windows

In [3]: argument = create_string_buffer(0)
   ...: c_dll.init_julia(c_int(0), byref(argument))
Out[3]: 1

In [4]: config_path = "ribasim.toml"

In [5]: c_dll.initialize(c_char_p(config_path.encode()))
Out[5]: 0

In [6]: c_dll.update()
Out[6]: 0
```
