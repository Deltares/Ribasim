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

end # module libribasim
