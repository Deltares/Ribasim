# This runs all testmodels and logs many performance related variables into a table.
# It can be used to track performance over time, or determine the most efficient solver
# settings for a particular model.
# Right now it runs all the generated_testmodels, however running larger models that are
# more typical of real usage is probably more useful.

# TODO look into
# https://github.com/SciML/SciMLBenchmarks.jl
# https://github.com/JuliaCI/PkgBenchmark.jl

import Arrow
import Tables
using Ribasim
using Configurations: to_dict
using DataStructures: OrderedDict
using Dates
using LibGit2

include("utils.jl")

"Add key config settings like solver settings to a dictionary"
function add_config!(dict, config::Ribasim.Config)
    confdict = to_dict(getfield(config, :toml))
    for (k, v) in confdict["solver"]
        if k == "saveat"
            # convert possible vector to scalar
            if isempty(v)
                v = 0.0
            elseif v isa AbstractVector
                v = missing
            end
        end
        dict[string("solver_", k)] = something(v, missing)
    end
    dict["starttime"] = confdict["starttime"]
    dict["endtime"] = confdict["endtime"]
    return dict
end

"Add solver statistics of the Model to a dictionary, with stats_ prefix"
function add_stats!(dict, model::Ribasim.Model)
    stats = model.integrator.sol.stats
    for prop in propertynames(stats)
        dict[string("stats_", prop)] = getproperty(stats, prop)
    end
    return dict
end

"Add @timed running time information of the Model to a dictionary, with timed_ prefix"
function add_timed!(dict, timed::NamedTuple)
    dict["timed_retcode"] = string(timed.value.integrator.sol.retcode)
    dict["timed_time"] = timed.time
    dict["timed_bytes"] = timed.bytes
    dict["timed_gctime"] = timed.gctime
    # timed.gcstats has a Base.GC_Diff
    return dict
end

"Add Julia and host information to a dictionary, with julia_ and host_ prefixes"
function add_env!(dict)
    dict["time"] = now()
    dict["date"] = today()
    dict["julia_version"] = VERSION
    dict["julia_nthreads"] = Threads.nthreads()
    dict["host_cpu"] = Sys.cpu_info()[1].model
    dict["host_kernel"] = Sys.KERNEL
    dict["host_machine"] = Sys.MACHINE
    dict["host_total_memory_gb"] = Sys.total_memory() / 2^30
    dict["host_free_memory_gb"] = Sys.free_memory() / 2^30
    return dict
end

"Add the Ribasim version, commit and branch name"
function add_git!(dict)
    dict["git_ribasim"] = Ribasim.RIBASIM_VERSION
    git_repo = normpath(@__DIR__, "..")
    repo = GitRepo(git_repo)
    branch = LibGit2.head(repo)
    commit = LibGit2.peel(LibGit2.GitCommit, branch)
    short_name = LibGit2.shortname(branch)
    short_commit = string(LibGit2.GitShortHash(LibGit2.GitHash(commit), 10))
    url = "https://github.com/Deltares/Ribasim/tree"
    dict["git_commit"] = short_commit
    dict["git_name"] = short_name
    dict["git_commit_url"] = "$url/$short_commit"
    dict["git_name_url"] = "$url/$short_name"
    return dict
end

"Create a flat OrderedDict of a run with metadata"
function run_dict(toml_path, config, timed)
    model = timed.value
    dict = OrderedDict{String, Any}()

    dict["directory"] = basename(dirname(toml_path))
    dict["toml_name"] = basename(toml_path)
    add_timed!(dict, timed)
    add_stats!(dict, model)
    add_git!(dict)
    add_config!(dict, config)
    add_env!(dict)
    return dict
end

toml_paths = get_testmodels()
runs = OrderedDict{String, Any}[]
for toml_path in toml_paths
    config = Ribasim.Config(toml_path)
    println(basename(dirname(toml_path)))
    # run first to compile, if this takes too long perhaps we can shorten the duration
    Ribasim.run(config)
    timed = @timed Ribasim.run(config)
    model = timed.value
    dict = run_dict(toml_path, config, timed)
    push!(runs, dict)
end

tbl = Tables.columntable(runs)

# Arrow.append("runs.arrow", tbl)
Arrow.write("runs.arrow", tbl)
