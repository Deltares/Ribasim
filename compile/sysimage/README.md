Code to create a system image using PackageCompiler directly, as opposed to
[using VS Code](https://www.julia-vscode.org/docs/dev/userguide/compilesysimage/)

```julia
using TOML
using PackageCompiler

d = TOML.parsefile("Project.toml")
pkgs = collect(filter(k -> !(k in ["Bach", "AxisKeys"]), keys(d["deps"])))
create_sysimage(pkgs; sysimage_path="sysimage.dll")
```
