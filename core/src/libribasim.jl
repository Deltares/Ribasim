module libribasim

import BasicModelInterface as BMI
import ..Ribasim
using SciMLBase: successful_retcode

# globals
model::Union{Ribasim.Model, Nothing} = nothing
last_error_message::String = ""

# After update and update_until we need to return an integer status code
# indicating success (zero) or failure (nonzero)
update_retcode(model)::Cint = !successful_retcode(model.integrator.sol)

"""
    @try_c(ex)

The `try_c` macro adds boilerplate around the body of a C callable function.
Specifically, it wraps the body in a try-catch, which returns 1 on failure.
On failure, it also prints the stacktrace.
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
    model === nothing && error("Model not initialized")
    BMI.update(model)
catch
    Base.invokelatest(Base.display_error, current_exceptions())
    return 1
end
```
"""
macro try_c(ex)
    return quote
        try
            global model
            model === nothing && error("Model not initialized")
            $(esc(ex))
        catch e
            global last_error_message
            last_error_message = sprint(showerror, e)
            return 1
        end
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
        catch e
            global last_error_message
            last_error_message = sprint(showerror, e)
            return 1
        end
    end
end

# all exported C callable functions

Base.@ccallable function initialize(path::Cstring)::Cint
    @try_c_uninitialized begin
        config_path = unsafe_string(path)
        model = BMI.initialize(Ribasim.Model, config_path)
    end
    return 0
end

Base.@ccallable function finalize()::Cint
    @try_c_uninitialized begin
        if model !== nothing
            BMI.finalize(model)
        end
        model = nothing
    end
    return 0
end

Base.@ccallable function update()::Cint
    @try_c begin
        BMI.update(model)
    end
    return update_retcode(model)
end

Base.@ccallable function update_until(time::Cdouble)::Cint
    @try_c begin
        BMI.update_until(model, time)
    end
    return update_retcode(model)
end

Base.@ccallable function update_subgrid_level()::Cint
    @try_c begin
        Ribasim.update_subgrid_level(model)
    end
    return 0
end

Base.@ccallable function get_current_time(time::Ptr{Cdouble})::Cint
    @try_c begin
        t = BMI.get_current_time(model)
        unsafe_store!(time, t)
    end
    return 0
end

Base.@ccallable function get_start_time(time::Ptr{Cdouble})::Cint
    @try_c begin
        t = BMI.get_start_time(model)
        unsafe_store!(time, t)
    end
    return 0
end

Base.@ccallable function get_end_time(time::Ptr{Cdouble})::Cint
    @try_c begin
        t = BMI.get_end_time(model)
        unsafe_store!(time, t)
    end
    return 0
end

Base.@ccallable function get_time_step(time_step::Ptr{Cdouble})::Cint
    @try_c begin
        t = BMI.get_time_step(model)
        unsafe_store!(time_step, t)
    end
    return 0
end

Base.@ccallable function get_var_type(name::Cstring, var_type::Cstring)::Cint
    @try_c begin
        value = BMI.get_value_ptr(model, unsafe_string(name))
        ctype = c_type_name(value)
        unsafe_write_to_cstring!(var_type, ctype)
    end
    return 0
end

Base.@ccallable function get_var_rank(name::Cstring, rank::Ptr{Cint})::Cint
    @try_c begin
        value = BMI.get_value_ptr(model, unsafe_string(name))
        n = ndims(value)
        unsafe_store!(rank, n)
    end
    return 0
end

Base.@ccallable function get_value_ptr(name::Cstring, value_ptr::Ptr{Ptr{Cvoid}})::Cint
    @try_c begin
        # the type of `value` depends on the variable name
        value = BMI.get_value_ptr(model, unsafe_string(name))
        unsafe_store!(value_ptr, pointer(value), 1)
    end
    return 0
end

Base.@ccallable function get_var_shape(name::Cstring, shape_ptr::Ptr{Cint})::Cint
    @try_c begin
        # the type of `value` depends on the variable name
        value = BMI.get_value_ptr(model, unsafe_string(name))
        shape = collect(Cint, size(value))
        unsafe_copyto!(shape_ptr, pointer(shape), length(shape))
    end
    return 0
end

Base.@ccallable function get_component_name(error_message::Cstring)::Cint
    @try_c_uninitialized begin
        unsafe_write_to_cstring!(error_message, "Ribasim")
    end
    return 0
end

Base.@ccallable function get_version(version::Cstring)::Cint
    @try_c_uninitialized begin
        unsafe_write_to_cstring!(version, RIBASIM_VERSION)
    end
    return 0
end

Base.@ccallable function get_last_bmi_error(error_message::Cstring)::Cint
    @try_c_uninitialized begin
        unsafe_write_to_cstring!(error_message, last_error_message)
    end
    return 0
end

Base.@ccallable function execute(toml_path::Cstring)::Cint
    Ribasim.main(unsafe_string(toml_path))
end

Base.@ccallable function get_value_ptr_double(
    name::Cstring,
    value_ptr::Ptr{Ptr{Cvoid}},
)::Cint
    get_value_ptr(name, value_ptr)
end

# supporting code

c_type_name(v::AbstractVector)::String = c_type_name(eltype(v))
c_type_name(v::Number)::String = c_type_name(typeof(v))
c_type_name(type::Type{Float64})::String = "double"

"""
    unsafe_write_to_cstring!(dest::Cstring, src::String)::Nothing

Write a String to the address of a Cstring, ending with a null byte.
The caller must ensure that this is safe to do.
"""
function unsafe_write_to_cstring!(dest::Cstring, src::String)::Nothing
    dest_ptr = pointer(dest)
    for (i, char) in enumerate(ascii(src))
        unsafe_store!(dest_ptr, char, i)
    end
    unsafe_store!(dest_ptr, '\0', length(src) + 1)
    return nothing
end

end # module libribasim
