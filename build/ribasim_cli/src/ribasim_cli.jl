module ribasim_cli

using Ribasim

julia_main()::Cint = Ribasim.main(ARGS)

end # module
