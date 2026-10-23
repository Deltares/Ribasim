# Entry point of the trimmed Ribasim executable, see build/trim/README.md
import Ribasim
using Ribasim: SolverTypes
using SciMLBase: FullSpecialize
using OrdinaryDiffEqBDF: NordsieckBDF

"""
The solver types compiled into this binary, see `Ribasim.SolverTypes`. A TOML with other
type-selecting solver settings gives an error. Since everything is compiled ahead of time,
the binary always specializes fully, which does not change the results.
"""
const SOLVER_TYPES = SolverTypes{
    NordsieckBDF, # algorithm
    true, # sparse
    true, # autodiff
    1, # chunksize, as without `specialize`
    true, # reduced_implicit_solve
    FullSpecialize,
}()

# Allocation (JuMP and HiGHS) is not trim compatible, so it is left out of this binary
Ribasim.allocation_compiled() = false

# Distributed, a dependency of SciMLBase, starts a task in its `__init__` that prints errors
# with `errormonitor`, which is not trim compatible. Like the patches of JuliaC for other
# standard libraries, it is not initialized, since it is not used.
let Distributed = Base.maybe_root_module(
        Base.PkgId(Base.UUID("8ba89e20-285c-5b6f-9357-94700520ee1b"), "Distributed"),
    )
    if Distributed !== nothing
        # Like in JuliaC, an empty method would not be compiled
        @eval Distributed __init__() = rand()
    end
end

# OrdinaryDiffEqCore formats indices in the Jacobian diagnostics with `string(::Vector)`,
# which is not trim compatible
import OrdinaryDiffEqCore
@eval OrdinaryDiffEqCore function format_indices(idxs::Vector{Int})::String
    n = length(idxs)
    shown = join(map(string, first(idxs, 10)), ", ")
    return n <= 10 ? string("[", shown, "]") : string("[", shown, ", and ", n - 10, " more]")
end

"Error message for common exception types, `showerror` needs dynamic dispatch."
function error_message(@nospecialize(e))::String
    return if e isa SystemError
        string(e.prefix, ": errno ", e.errnum)
    elseif e isa Ribasim.NC.NetCDFError
        string("NetCDF error code ", e.code, ": ", e.msg)
    else
        Ribasim.error_message(e)
    end
end

include("trim_logging.jl")

function (@main)(args::Vector{String})::Cint
    if length(args) != 1
        println(Core.stdout, "Usage: ribasim_trim path/to/ribasim.toml")
        return 1
    end
    toml_path = only(args)
    # The Ribasim logger setup (TerminalLoggers, LoggingExtras) is not trim compatible, it
    # is replaced by the `TrimLogger`, see trim_logging.jl.
    retcode = try
        config = Ribasim.Config(toml_path)
        init_trim_logger(config)
        Ribasim.log_startup(config, toml_path; logo_io = Core.stderr)
        model = Ribasim.Model(config, SOLVER_TYPES; logger = LOGGER[])
        try
            Ribasim.solve!(model)
        catch e
            # Like `Ribasim.main`, write the results up to a crash during the simulation
            t = Ribasim.datetime_since(model.integrator.t, config.starttime)
            @warn "Simulation crashed or interrupted at $(Ribasim.datetime_string(t))."
            Ribasim.log_bottlenecks(model)
            Ribasim.write_results(model)
            rethrow()
        end
        Ribasim.write_results(model)
        Ribasim.log_finalize(model)
    catch e
        message = error_message(e)
        @error "Ribasim simulation failed" exception = message
        println(Core.stderr, "Ribasim simulation failed: ", message)
        Cint(1)
    end
    close_trim_logger()
    return retcode
end
