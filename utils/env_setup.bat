set QUARTO_PYTHON=python

setlocal EnableDelayedExpansion
set "current_dir=%CD%\"
set "conda_prefix=%CONDA_PREFIX%\"
set "relative_conda_prefix=!conda_prefix:%CD%=.!"
endlocal & set MYPYPATH="%relative_conda_prefix%Library\python"
