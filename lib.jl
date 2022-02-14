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

function decay(vad::VolumeAreaDischarge, q)
    # output is in [s] == [m3 / (m3s⁻¹)]
    (; discharge, dvdq) = vad
    i = searchsortedlast(discharge, q)
    # constant extrapolation
    i = clamp(i, 1, length(dvdq))
    return dvdq[i]
end

function volume(vad::VolumeAreaDischarge, q)
    i = searchsortedlast(vad.discharge, q)
    # linear extrapolation
    i = clamp(i, 1, length(vad.volume))
    slope = decay(vad, q)
    v0 = vad.volume[i]
    q0 = vad.discharge[i]
    v = v0 + (q - q0) * slope
    # TODO add the empty reservoir condition to the calculation
    return max(v, 0.0)
end

nothing
