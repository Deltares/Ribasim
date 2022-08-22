[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) is used to investigate
the possibilties for low-latency binaries. A simple model based on
https://mtk.sciml.ai/dev/tutorials/acausal_components/ is used. In a new julia session, it
can take about 1 minute to get to the first solution, with time spent in the following way:

    ────────────────────────────────────────────────────────────────────────────────
                                           Time                    Allocations
                                  ───────────────────────   ────────────────────────
          Tot / % measured:            90.2s /  91.5%           8.92GiB /  93.4%
    
    Section               ncalls     time    %tot     avg     alloc    %tot      avg
    ────────────────────────────────────────────────────────────────────────────────
    structural_simplify        1    33.8s   41.0%   33.8s   3.18GiB   38.1%  3.18GiB
    create system              1    17.1s   20.7%   17.1s   1.72GiB   20.7%  1.72GiB
    load modules               1    14.3s   17.3%   14.3s   1.52GiB   18.2%  1.52GiB
    create ODAEProblem         1    13.0s   15.7%   13.0s   1.52GiB   18.3%  1.52GiB
    define components          1    2.39s    2.9%   2.39s    222MiB    2.6%   222MiB
    solve                      1    2.00s    2.4%   2.00s    178MiB    2.1%   178MiB
    ────────────────────────────────────────────────────────────────────────────────

Once the model is frozen, we'd like to avoid these latencies as much as possible. In the
first experiment, an rc_model.exe is created. It takes a single argument, which sets the
capacitance parameter. As you can see almost all the latency for this simple model is gone.

    .\rc_model.exe 1.2
    Solver return code: Success
    
    ────────────────────────────────────────────────────────────────────────────────
                                           Time                    Allocations
                                  ───────────────────────   ────────────────────────
          Tot / % measured:            1.78s /  99.6%            153MiB / 100.0%
    
    Section               ncalls     time    %tot     avg     alloc    %tot      avg
    ────────────────────────────────────────────────────────────────────────────────
    solve                      1    1.44s   81.3%   1.44s    108MiB   71.0%   108MiB
    structural_simplify        1    143ms    8.1%   143ms   24.1MiB   15.8%  24.1MiB
    create ODAEProblem         1    120ms    6.8%   120ms   15.3MiB   10.0%  15.3MiB
    create system              1   67.1ms    3.8%  67.1ms   4.84MiB    3.2%  4.84MiB
    ────────────────────────────────────────────────────────────────────────────────

For a larger model, it is possible that, even with compilation out of the way, setting up
the problem, and specifically `structural_simplify` still have to do quite some work, which
will always be the same for a frozen model.

Therefore a second experiment was done, in which the `ODAEProblem` was serialized to a file,
`prob.jls`. This file can be deserialized quickly, and then directly run. This approach
reduces latency considerably more still. It is not yet fully known if and how parameters or
other input data can still be modified after the fact using this approach, though there is
`ModelingToolkit.remake` for reconstructing objects with new field values.

    .\rc_deserialize.exe prob.jls
    Solver return code: Success
    
    ────────────────────────────────────────────────────────────────────
                               Time                    Allocations
                      ───────────────────────   ────────────────────────
    Tot / % measured:     13.3ms /  73.4%           1.63MiB /  99.6%
    
    Section   ncalls     time    %tot     avg     alloc    %tot      avg
    ────────────────────────────────────────────────────────────────────
    solve          1   9.74ms  100.0%  9.74ms   1.63MiB  100.0%  1.63MiB
    ────────────────────────────────────────────────────────────────────

## Use

There are two folders with each their own projects, `mtkbin` and `create_app`. `mtkbin` is a
module, with C-callable functions `julia_main` and `julia_deserialize`, that will each be
turned into an executable by PackageCompiler.jl.

`create_app.jl` contains the call to PackageCompiler. The other julia files contain code
that will be included into the system image to reduce latency further. This code therefore
create and solves the same system that we want to run in the executable. (Probably we should
refactor this to use the `mktbin` module to avoid code duplication.) It also writes the
`prob.jls` serialized problem to disk, for use with `rc_deserialize`.
