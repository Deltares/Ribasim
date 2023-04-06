module libribasim

import BasicModelInterface as BMI
using Ribasim

model = nothing

"""
    @try_c(ex)

The `try_c` macro adds boilerplate around the body of a C callable function.
Specifically, it wraps the body in a try-catch,
which always returns 0 on success and 1 on failure.
On failure, it prints the stacktrace.
It makes the `model` from the global scope available, and checks if it is initialized.

# Usage
```
@try_c begin
    BMI.update(model)
end
```

This expands to
```
try
    global model
    isnothing(model) && error("Model not initialized")
    BMI.update(model)
catch
    Base.invokelatest(Base.display_error, current_exceptions())
    return 1
end
return 0
```
"""
macro try_c(ex)
    return quote
        try
            global model
            isnothing(model) && error("Model not initialized")
            $(esc(ex))
        catch
            Base.invokelatest(Base.display_error, current_exceptions())
            return 1
        end
        return 0
    end
end

"""
    try_c_uninitialized(ex)

Identical to `@try_c(ex)`, except it does not assert that the model is initialized.
"""
macro try_c_uninitialized(ex)
    return quote
        try
            global model
            $(esc(ex))
        catch
            Base.invokelatest(Base.display_error, current_exceptions())
            return 1
        end
        return 0
    end
end

Base.@ccallable function initialize(path::Cstring)::Cint
    @try_c_uninitialized begin
        config_path = unsafe_string(path)
        model = BMI.initialize(Ribasim.Model, config_path)
    end
end

Base.@ccallable function finalize()::Cint
    @try_c_uninitialized begin
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

Base.@ccallable function get_current_time(time::Ptr{Cdouble})::Cint
    @try_c begin
        t = BMI.get_current_time(model)
        unsafe_store!(time, t)
    end
end

Base.@ccallable function get_var_type(name::Cstring, var_type::Cstring)::Cint
    @try_c begin
        value = BMI.get_value_ptr(model, unsafe_string(name))
        dtype = if value isa Vector
            julia_type_to_numpy(eltype(value))
        elseif value isa Number
            julia_type_to_numpy(typeof(value))
        else
            error("Unsupported value type $(typeof(value))")
        end

        var_type_ptr = pointer(var_type)
        for (i, char) in enumerate(ascii(dtype))
            unsafe_store!(var_type_ptr, char, i)
        end
        unsafe_store!(var_type_ptr, '\0', length(dtype) + 1)
    end
end

Base.@ccallable function get_var_rank(name::Cstring, rank::Ptr{Cdouble})::Cint
    @try_c begin
        value = BMI.get_value_ptr(model, unsafe_string(name))
        n = ndims(value)
        unsafe_store!(rank, n)
    end
end

Base.@ccallable function get_value_ptr(name::Cstring, value_ptr::Ptr{Ptr{Cvoid}})::Cint
    @try_c begin
        value = BMI.get_value_ptr(model, unsafe_string(name))
        n = length(value)
        core_ptr = Base.unsafe_convert(Ptr{Ptr{Cvoid}}, value)
        unsafe_copyto!(value_ptr, core_ptr, length(value))
    end
end

Base.@ccallable function get_value_ptr_double(
    name::Cstring,
    value_ptr::Ptr{Ptr{Cvoid}},
)::Cint
    get_value_ptr(name, value_ptr)
end

function julia_type_to_numpy(type)::String
    if type == Float64
        "double"
    else
        error("Unsupported type $type")
    end
end

end # module libribasim
