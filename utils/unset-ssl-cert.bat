rem Workaround a conflict between conda openssl activation and julia,
rem until these two PRs are released:
rem https://github.com/JuliaLang/NetworkOptions.jl/pull/37
rem https://github.com/JuliaLang/julia/pull/56924
set SSL_CERT_FILE=
set SSL_CERT_DIR=
