# path = raw"c:\projects\NHI-prototype\data\test-models\Joeri\f01_basic_tests\c21_Hooghoudt_bare_soil\RCHINDEX2SVAT.DXC"
# path = raw"c:\projects\NHI-prototype\data\test-models\Joeri\f01_basic_tests\c21_Hooghoudt_bare_soil\NODENR2SVAT.DXC"

read_exchange(path) = readdlm(path, Int)

##
using Sparse

const solution_id = 1
const Float = Float64

@enum METHOD sum=1 average=2

function normalize_columns!(S::SparseCSCMatrix)
    for (column, summed) in enumerate(sum(S, 1))
        summed == 0 && continue
        S[:, column] = S[:, column] / summed
    end
    return
end

"""
Create a sparse array, which can be easily used to aggregate values from one
model to the other.
"""
function create_mapping(src_index, dst_index, method)
    I = src_index
    J = dst_index
    V = ones(Float, I.size)
    S = sparse(I, J, V)
    if method == METHOD.average
        normalize_columns!(S)
    end
    mask = (diff(S.colptr) .== 0)
    return S, mask
end

struct Exchange
    mf_to_msw::Any
    msw_to_mf::Any
end

function Exchange(path_mod2svat, path_nodenr2svat, path_rchindex2svat)
end

struct MetaMod
    mf6::String
    msw::String
    mf6modelname::String
    maxiter::Int
    head::Array{Float}
    recharge::Array{Float}
    storage::Array{Float}
    area::Array{Float}
    top::Array{Float}
    bot::Array{Float}
    msw_head::Array{Float}
    msw_volume::Array{Float}
    msw_storage::Array{Float}
    exchange::Exchange
end

function get_mf6_value_ptr(metamod::MetaMod, varname, subcomponent)
    component = metamod.mf6modelname
    headtag = MFI.get_var_address(metamod.mf6, varname, component, subcomponent)
    return BMI.get_value_ptr(mf, headtag)
end

function MetaMod(mf6, msw, mf6modelname)
    initialize(metamod.mf6)
    initialize(metamod.msw)

    head = get_value_ptr(mf6, "$(metamod.mf6modelname)/X")
    recharge = get_mf6_value_ptr(mf6, "BOUND", "RCH_MSW")[1, :]
    storage = get_mf6_value_ptr(mf6, "SS", "STO")
    area = get_mf6_value_ptr(mf6, "AREA", "DIS")
    top = get_mf6_value_ptr(mf6, "TOP", "DIS")
    bot = get_mf6_value_ptr(mf6, "BOT", "DIS")
    maxiter = Int(get_value_ptr(mf6, "SLN_1/MXITER")[1])

    msw_head = get_value_ptr(msw, "dhgwmod")
    msw_volume = get_value_ptr(msw, "dvsim")
    msw_storage = get_value_ptr(msw, "dsc1sim")
    msw_time = get_value_ptr(msw, "currenttime")

    return MetaMod(mf6,
                   msw,
                   mf6modelname,
                   maxiter,
                   head,
                   recharge,
                   storage,
                   area,
                   top,
                   bot,
                   maxiter,
                   msw_head,
                   msw_volume,
                   msw_storage,
                   msw_time)
end

function update!(metamod::MetaMod)
    mf6 = metamod.mf6
    msw = metamod.msw

    exchange_mf_to_msw!(metamod)
    MFI.prepare_time_step(0.0)
    Δt = MFI.get_time_step(mf6)

    MSI.prepare_time_step(msw, Δt)
    MFI.prepare_solve(mf6, solution_id)

    converged = false
    iter = 1
    while iter <= metamod.maxiter && !converged
        converged = do_iter(metamod, solution_id)
    end

    MFI.finalize_solve(mf6, solution_id)
    MFI.finalize_time_step(mf6)
    current_time = MFI.get_current_time(mf6)
    metamod.msw_time = current_time
    MSI.finalize_timestep(msw)

    return current_time
end

function do_iter(metamod::MetaMod, solution_id::Int)
    msw = metamod.msw
    mf6 = metamod.mf6

    MSI.prepare_solve(msw, 0)
    MSI.solve(msw, 0)
    exchange_msw_to_mf6(metamod)
    converged = solve(mf6, solution_id)
    exchange_mf6_to_msw(metamod)
    MSI.finalize_solve(msw, 0)
    return converged
end

function finalize!(metamod::MetaMod)
    finalize(metamod.mf6)
    finalize(metamod.msw)
    return
end

function exchange_mf_to_msw!(metamod::MetaMod) end

function exchange_msw_to_mf!(metamod::MetaMod) end
