This folder is a Julia project meant for running Ribasim simulations and post-processing.

Assuming your working directory is the root of the repository, you can activate this project
by entering the Pkg mode of the REPL with `]` and running `activate run`.
The first time you do this, you will also have to tell it where it can find the Ribasim module itself.
This can be done with `dev .` to tell it to develop the module in the current directory.

```julia
(Ribasim) pkg> activate run
  Activating project at `path/to/Ribasim/run`

(run) pkg> dev .
```
