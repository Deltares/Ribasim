module libribasim

import BasicModelInterface as BMI
using Ribasim

model = nothing

"""
    @try_c(ex)

The `try_c` macro adds boilerplate around the body of a C callable function.
Specifically, it wraps the body in a try-catch,
which always returns 0 on success and 1 on failure.
On failure, it also prints the stacktrace.
Also it makes the `model` from the global scope available.

# Usage
```
@try_c begin
    model = nothing
end
```

This expands to
```
try
    global model
    model = nothing
catch
    Base.invokelatest(Base.display_error, Base.catch_stack())
    return 1
end
return 0
```
"""
macro try_c(ex)
    return quote
        try
            global model
            $(esc(ex))
        catch
            Base.invokelatest(Base.display_error, Base.catch_stack())
            return 1
        end
        return 0
    end
end

Base.@ccallable function initialize(path::Cstring)::Cint
    @try_c begin
        config_path = unsafe_string(path)
        model = BMI.initialize(Ribasim.Model, config_path)
    end
end

Base.@ccallable function finalize()::Cint
    @try_c begin
        model = nothing
    end
end

Base.@ccallable function update()::Cint
    @try_c begin
        BMI.update(model)
    end
end

Base.@ccallable function update_until(time::Cdouble)::Cint
    @try_c begin
        BMI.update_until(model, time)
    end
end

# TODO should receive a double that needs to get updated
Base.@ccallable function get_current_time()::Cint
    @try_c begin
        BMI.get_current_time(model)
    end
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
