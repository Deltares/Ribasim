"Print the Ribasim Unicode logo with version info to the terminal."
function print_logo(io::IO = stderr)::Nothing
    b = "\e[38;2;80;130;210m"
    bold = "\e[1m"
    d = "\e[2m"
    r = "\e[0m"

    v = RIBASIM_VERSION

    # runic: off
    logo = """
    ⠀⠀⠀⠀⠀⠀⠀⠀⢀⣶⣶⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠈⠿⠿⠟⣠⣶⣄⡀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣶⣿⣿⣿⠿⣫⣶⣿⣿⠠⣿⣿⣿⠀⠀⠀⠀
    ⠀⠀⠀⠀⣀⣴⣾⡼⣿⡏⠀⠀⠀$(b)⡀$(r)⢾⠟⠉⠙⢿⣧⣍⣉⠁⠀⠀⠀⠀
    ⢠⣶⣷⣦⢹⣿⣿⠃⢻⡇⠀$(b)⢠⣾⣿⣦$(r)⠀⠀⠀⠈⢿⣿⣿⡇⠀⠀⠀⠀
    ⠈⠿⠿⢏⣼⣿⠃⠀⠀⠑$(b)⣰⣿⣿⣿⣿⣷⡀$(r)⠴⢶⣦⣭⣟⡃$(r)⠀⠀⠀⠀⠀  $(bold)$(b)Ribasim$(r) $(d)v$v$(r)
    ⠀⠀⠀⢿⣿⣧⣀⠀⠀⠀$(b)⣿⣿⣿⣿⣿⣿⡇$(r)⠀⠀⠈⠙⣿⣿⡆$(r)⠀⠀⠀⠀  $(d)Water resources modeling$(r)
    ⠀⠀⠀⠀⣭⣟⡛⠿⠖⠂$(b)⠙⢿⣿⣿⣿⠟$(r)⢠⡀⠀⢀⣼⡿⢫⣶⣶⣄⠀
    ⠀⠀⠀⠀⣿⣿⣿⣆⠀⠀⠀⠀⣠$(b)⠉$(r)⠀⠀⠀⣿⡀⣾⣿⣷⠘⢿⡿⠏⠀
    ⠀⠀⠀⠀⣨⣍⡛⣿⣦⣀⣤⣾⠋⠀⠀⠀⢀⣿⣧⠿⠟⠋⠀⠀⠀⠀⠀
    ⠀⠀⠀⢸⣿⣿⡗⢸⣿⡿⢻⣵⣿⣿⣿⠿⢿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠉⠉⠀⠀⠀⠀⠀⠉⠻⠟⣡⣶⣶⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠿⠿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀
    """
    # runic: on

    println(io, logo)
    return nothing
end
