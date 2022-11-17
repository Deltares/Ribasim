# Backported from Julia 1.9
function pkgversion(m::Module)
    rootmodule = Base.moduleroot(m)
    pkg = Base.PkgId(rootmodule)
    pkgorigin = get(Base.pkgorigins, pkg, nothing)
    return pkgorigin === nothing ? nothing : pkgorigin.version
end
