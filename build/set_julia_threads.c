#include <julia.h>
#include <stdint.h>

#ifdef _WIN32
#define RIBASIM_DLLEXPORT __declspec(dllexport)
#else
#define RIBASIM_DLLEXPORT __attribute__((visibility("default")))
#endif

static int16_t threads_per_pool[1];

RIBASIM_DLLEXPORT int ribasim_set_julia_threads(int32_t threads)
{
    // Julia reads jl_options once, while initializing the runtime.
    if (jl_is_initialized())
    {
        return 1;
    }
    if (threads < 1 || threads > INT16_MAX)
    {
        return 2;
    }

    // JuliaC already parsed --threads=1, so update all fields read by jl_init_threading.
    threads_per_pool[0] = (int16_t)threads;
    jl_options.nthreadpools = 1;
    jl_options.nthreads = (int16_t)threads;
    jl_options.nthreads_per_pool = threads_per_pool;

    // Julia's GC requires signal-based safepoints when multiple threads are active.
    jl_options.handle_signals =
        threads > 1 ? JL_OPTIONS_HANDLE_SIGNALS_ON : JL_OPTIONS_HANDLE_SIGNALS_OFF;
    return 0;
}
