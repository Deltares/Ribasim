module libribasim

import BasicModelInterface as BMI
using Ribasim

model = nothing

Base.@ccallable function initialize(path::Cstring)::Cint
    global model
    try
        config_path = unsafe_string(path)
        model = BMI.initialize(Register, config_path)
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

end # module libribasim
