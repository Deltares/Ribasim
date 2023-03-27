module libribasim

import BasicModelInterface as BMI
using Ribasim

model = nothing

Base.@ccallable function initialize(path::Cstring)::Cint
    global model
    try
        config_path = unsafe_string(path)
        model = BMI.initialize(Ribasim.Model, config_path)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

Base.@ccallable function finalize()::Cint
    global model
    try
        model = nothing
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

Base.@ccallable function update()::Cint
    try
        BMI.update(model)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

Base.@ccallable function update_until(time::Cdouble)::Cint
    try
        BMI.update_until(model, time)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

# TODO should receive a double that needs to get updated
Base.@ccallable function get_current_time()::Cint
    try
        BMI.get_current_time(model)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

Base.@ccallable function get_var_type(name::Cstring, var_type::Cstring)::Cint
    value = BMI.get_value_ptr(model, unsafe_string(name))
    dtype = if value isa Vector
        julia_type_to_numpy(eltype(value))
    elseif value isa Number
        julia_type_to_numpy(typeof(value))
    else
        error("Unsupported value type $(typeof(value))")
    end

    @assert isascii(dtype)
    var_type_ptr = pointer(var_type)
    for (i, char) in enumerate(dtype)
        unsafe_store!(var_type_ptr, char, i)
    end
    unsafe_store!(var_type_ptr, '\0', length(dtype) + 1)

    return 0
end

function julia_type_to_numpy(type)::String
    if type == Float64
        "float64"
    else
        error("Unsupported type $type")
    end
end

end # module libribasim
