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
programs. It can be compiled using [JuliaC.jl](https://github.com/JuliaLang/JuliaC.jl), which is set
up in this directory. The C API that is offered to control Ribasim is the C API of the
[Basic Model Interface](https://bmi.readthedocs.io/en/latest/), also known as BMI.

Not all BMI functions are implemented yet.
Couplings to other models are implemented in [`imod_coupler`](https://github.com/Deltares/imod_coupler).

Here is an example of using libribasim from Python:

```python
In [1]: from ctypes import CDLL, c_int, c_char_p, create_string_buffer, byref

In [2]: c_dll = CDLL("libribasim", winmode=0x08)  # winmode for Windows

In [3]: c_dll.ribasim_set_julia_threads.argtypes = [c_int]

In [4]: c_dll.ribasim_set_julia_threads.restype = c_int

In [5]: c_dll.ribasim_set_julia_threads(2)
Out[5]: 0

In [6]: config_path = "ribasim.toml"

In [7]: c_dll.initialize(c_char_p(config_path.encode()))
Out[7]: 0

In [8]: c_dll.update()
Out[8]: 0
```

`ribasim_set_julia_threads` accepts a positive integer and must be called before any function that
initializes Julia. It returns zero on success, one if Julia was already initialized, and two if the
thread count is invalid.

A value larger than one enables Julia's process-wide signal handlers. Julia requires these handlers
for garbage collection safepoints when using multiple Julia threads, but they can conflict with
signal handling in the embedding application. The default is one thread with Julia signal handling
disabled.

## Trimming

libribasim is built with `juliac --trim=safe`, which only compiles the code reachable from the
C callable functions in `libribasim.jl`, and fails the build if any reachable call needs runtime
compilation. This gives a much smaller library, which starts and runs short simulations much
faster. The Ribasim CLI and the C API stay the same. Linking needs `gcc` or `clang` on the
`PATH`, or a compiler in `JULIA_CC`. Set `RIBASIM_TRIM_CPU_TARGET`, e.g. to `native`, for a
faster build that only runs on this CPU.

### Build profile

Some settings select types, and with trimming every combination of types must be known at
compile time. These are fixed in `trim_profile.jl`:

- `SOLVER_TYPES`: the algorithm and how its Jacobian is computed, see `Ribasim.SolverTypes`.
  It matches the default TOML: `NordsieckBDF`, sparse, automatic differentiation with chunk
  size 1, and the reduced implicit solve. A TOML with other values for these settings gives
  an error. The binary always specializes fully, since it is compiled ahead of time, so the
  TOML `specialize` setting has no effect. This does not change the results.
- Allocation is left out by redefining `Ribasim.allocation_compiled() = false`, since JuMP
  and HiGHS are not trim compatible. A TOML with allocation enabled gives an error.

Everything else is supported: all node types and input tables, NetCDF input, all result
files, DiscreteControl, PidControl, ContinuousControl, concentrations, subgrid levels, the
solver diagnostics after a failure, and multiple threads.

### Verification

The trimmed binary gives results identical to the untrimmed Ribasim (all variables, attributes and
types of all NetCDF result files, and `basin_profiles.csv`) for all 47 test models in
`generated_testmodels` that fit the build profile, and for the HWS and Limburg models over a
year. The other test models either use allocation (24) or another solver (2), which give
an error saying they are not compiled in, or are invalid on purpose (7), which give the
same error as untrimmed Ribasim. In normal Julia, all test models give results identical
to `main`, and the core tests pass.

The CLI tests in `build/tests` skip the test models outside the build profile, and the BMI
tests in `python/ribasim_api/tests` test the trimmed library. Due to the type piracy in the
entry point, `libribasim.jl` cannot be loaded in a normal Julia session.

### Workarounds in the entry point

These are in `trim_profile.jl` and `trim_logging.jl`. They are type piracy, only acceptable in the
entry point of the binary, and mostly fix trim
compatibility of dependencies, so they could move upstream.

- Logging (`trim_logging.jl`): JuliaC disables the logging macros under trim by overriding
  `Base.CoreLogging.current_logger_for_env(level, group, _module) = nothing`, and the macros
  call the logger via `@nospecialize` and `@invokelatest`. The entry point adds more
  specific methods for one concrete `TrimLogger`, which makes `@info` and friends dispatch
  statically again. It writes to the terminal and to `results/ribasim.log`, and respects the
  TOML `verbosity`. Log statements of dependencies, such as the progress bar, stay disabled.
  This approach comes from the trimmed Wflow proof of concept.
- `String(::LazyString)`: Base prints the untyped parts by dynamic dispatch, and several
  dependencies create `lazy"..."` messages.
- `Distributed.__init__`: Distributed, a dependency of SciMLBase, starts a task in its
  `__init__` that reports errors with `errormonitor`, which is not trim compatible. Like
  JuliaC does for other standard libraries, it is not initialized.
- `OrdinaryDiffEqCore.format_indices`: formats indices with `string(::Vector)`.

### Working on trim compatibility

- On failure, the build prints `Trim verify finished with N errors` and a stack trace per
  error. The first frame in Ribasim shows the culprit. The verifier stops following a call
  it cannot resolve, so fixing errors uncovers new ones further down.
- To check results, run the same TOML with normal Julia (`Ribasim.run`) and compare the
  output files.
- The verifier checks all C callable functions of `libribasim.jl`, not just the ones used by
  the CLI.
- JuliaC instantiates `core/Project.toml` in a new environment, rather than using the
  `Manifest.toml` of the repository, so it can use newer package versions.

Patterns that work under `--trim=safe`:

- Settings that select types are type parameters, see `SolverTypes`. Taking them from the
  TOML is not type stable, but a single dynamic dispatch in normal Julia.
- Values from a parsed TOML are `Any`: dispatch on the target type only, mark the value
  `@nospecialize` and branch with `isa`, see `parse_value` in `config.jl`.
- Struct fields must be concrete: add type parameters, or use small `Union`s like
  `FlowBoundaryRate`. Defaults like `[]` or `OrderedDict()` give `Any` element types.
- Field or column names that are only known at runtime, like `getfield(p, type)`, need a
  static dispatch: `Val` names, `with_node`, `typed_field` or `static_dispatch`. A
  `@generated` function can generate the if-chain or the per-column code, but its body may
  not contain closures or comprehensions, and the globals it reads must be defined before it.
- Read typed columns from SQLite (`query_columns`) and NetCDF (`NC`), since the `Tables.jl`
  interface of SQLite.jl and the API of NCDatasets are not type stable.
- Julia does not specialize on a `Function` or `Type` argument that is only passed through.
  DiffEqCallbacks and SciMLBase constructors do this, so callback functions are wrapped in
  `Specialized`, and the ODE functions in `InPlace`, which also tells SciMLBase that they are
  in-place, since it otherwise uses method reflection. Helper functions that take a type
  need `::Type{T} where {T}`.
- Keyword arguments need concretely inferred values, a `Union` makes the whole keyword call
  unresolved. See the separate `init` calls for `dt = nothing` and a fixed `dt`.
- Union splitting only works for up to 4 combinations, so avoid several `Union{Nothing, T}`
  arguments in one call.
- Functions with long varargs do not specialize: long string interpolations need to be
  built in parts, and DiffEqBase's recursion over the callbacks is replaced by a recursion
  over the tuple, see `initialize_callbacks!`.
- Avoid `show` of arrays, `NamedTuple`s and `DateTime` in messages, see `format_vector`,
  `format_key` and `datetime_string`. Also `canonicalize` (`format_duration`), `join` of an
  empty tuple, `lpad`, `rpad`, `sprint(showerror, e)` (`error_message`) and `deepcopy`.
- `OrderedDict` builds an error message with the key in `setindex!`, which is not trim
  compatible for keys like `Vector{Bool}`, so the logic mapping is a `Dict`.
- `Threads.@spawn` works, but `waitall` does not, see `wait_all`.
- Some types depend on runtime values inside dependencies. Ribasim methods for its own types
  avoid this: `+(::UniformScaling, ::RibasimJacobian)`, `pick_batchsize` for `RibasimTag`,
  and `saving_callback` and `saving_initialize`, which construct the saving callbacks like
  DiffEqCallbacks without the backward time direction.

Known not to trim: JuMP and HiGHS (allocation), NCDatasets, the SQLite.jl `Tables.jl`
interface, Configurations.jl `from_toml`, TerminalLoggers and LoggingExtras,
DelimitedFiles, `IterTools.groupby` for keys of a `Union` type, and the NoSpecialize
`ODEFunction`, which has untyped fields.
