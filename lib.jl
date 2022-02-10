# reusable components that can be included in application scripts

struct VolumeAreaDischarge
    volume::Vector{Float64}
    area::Vector{Float64}
    discharge::Vector{Float64}
    dvdq::Vector{Float64}
    function VolumeAreaDischarge(v, a, d, dvdq)
        n = length(v)
        n <= 1 && error("VolumeAreaDischarge needs at least two data points")
        if n != length(a) || n != length(d)
            error("VolumeAreaDischarge vectors are not of equal length")
        end
        if !issorted(v) || !issorted(a) || !issorted(d)
            error("VolumeAreaDischarge vectors are not sorted")
        end
        new(v, a, d, dvdq)
    end
end

function VolumeAreaDischarge(vol, area, q)
    dvdq = diff(vol) ./ diff(q)
    VolumeAreaDischarge(vol, area, q, dvdq)
end

function Δvolume(vad::VolumeAreaDischarge, q)
    (; discharge, dvdq) = vad
    i = searchsortedlast(discharge, q)
    # constant extrapolation
    i = clamp(i, 1, length(dvdq))
    return dvdq[i]
end

function volume(vad::VolumeAreaDischarge, q)
    (; volume, discharge) = vad
    i = searchsortedlast(discharge, q)
    # constant extrapolation
    i = clamp(i, 1, length(volume))
    return volume[i]
end

nothing
