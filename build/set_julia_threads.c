#include <getopt.h>
#include <julia.h>
#include <stdint.h>
#include <stdio.h>

#ifdef _WIN32
#define RIBASIM_DLLEXPORT __declspec(dllexport)
#else
#define RIBASIM_DLLEXPORT __attribute__((visibility("default")))
#endif

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

    char threads_option[32];
    snprintf(threads_option, sizeof(threads_option), "--threads=%d", threads);

    // jl_parse_opts mutates process-global getopt state and the selected sysimage.
    int saved_optind = optind;
    int saved_opterr = opterr;
    int saved_optopt = optopt;
    char *saved_optarg = optarg;
    const char *saved_image_file = jl_options.image_file;

    // Julia's GC requires signal-based safepoints when multiple threads are active.
    int enable_signals = threads > 1;
    char *argv[] = {
        "ribasim",
        threads_option,
        enable_signals ? "--handle-signals=yes" : NULL,
        NULL,
    };
    int argc = enable_signals ? 3 : 2;
    char **argvp = argv;
    optind = 0;

    jl_parse_opts(&argc, &argvp);

    // Preserve JuliaC's sysimage and avoid disturbing argument parsing in the host.
    jl_options.image_file = saved_image_file;
    optind = saved_optind;
    opterr = saved_opterr;
    optopt = saved_optopt;
    optarg = saved_optarg;
    return 0;
}
