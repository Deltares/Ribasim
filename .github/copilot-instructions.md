# Copilot instructions

This document provides essential information for AI coding assistants working on the Ribasim project.

See also the developer docs at `docs/dev`.

## Project Overview

**Ribasim** is a water resources modeling system. It's a multi-language project with components in Julia (core), Python (utilities/API), and QGIS integration.

- **Primary Language**: Julia (core simulation engine)
- **Secondary Languages**: Python (model building, QGIS plugin)
- **Domain**: Water resources modeling, hydrology, scientific computing
- **Architecture**: Modular system with CLI, Python API, and QGIS plugin

## Repository Structure

```
├── core/                   # Julia core engine (main simulation code)
│   ├── src/                # Core Julia source code
│   ├── test/               # Julia unit tests
│   └── Project.toml        # Julia package configuration
├── python/                 # Python components
│   ├── ribasim/            # Main Python package (model building)
│   ├── ribasim_api/        # Python API for model interaction
│   └── ribasim_testmodels/ # Test model generation
├── ribasim_qgis/           # QGIS plugin for model visualization
├── docs/                   # Documentation (Quarto-based)
├── build/                  # Build scripts for CLI
├── generated_testmodels/   # Generated test models
├── models/                 # Working directory for models, ignored by git
└── utils/                  # Utility scripts
```

## Key Technologies & Dependencies

### Julia Stack (Core)
- **OrdinaryDiffEq.jl**: Differential equation solving (primary solver)
- **JuMP.jl**: Mathematical optimization modeling
- **HiGHS.jl**: Linear/mixed-integer programming solver
- **Arrow.jl**: Columnar data format for I/O
- **SQLite.jl**: Database operations
- **MetaGraphsNext.jl**: Graph data structures for network topology
- **SciML ecosystem**: Scientific machine learning tools

### Python Stack
- **Pandas/GeoPandas**: Data manipulation and geospatial processing
- **PyArrow**: Arrow format integration with Julia
- **Pydantic/Pandera**: Data modeling and validation
- **Matplotlib**: Visualization and plotting

### Build & Development
- **Pixi**: Primary package/environment manager, also used to run e.g. tests via tasks. (see `pixi.toml`)
- **Julia Package Manager**: For Julia dependencies. `Project.toml` has all dev dependencies and `core/Project.toml` the Ribasim core dependencies.
- **Pre-commit**: Code quality hooks
- **Pytest**: Python testing
- **Quarto**: Documentation generation

## Development Workflow

### Environment Setup
```bash
# Use Pixi for environment management
pixi run install                  # Install and configure all dependencies
pixi run install-julia           # Install Julia 1.11.6
pixi run initialize-julia        # Update registry and instantiate Julia project
```

### Development Commands

```bash
# Building
pixi run build                    # Build Ribasim executable (requires testmodels)

# Testing
pixi run test-ribasim-core        # Run Julia core tests
pixi run test-ribasim-python      # Run Python tests (excluding regression)
pixi run test-ribasim-api         # Run Python API tests
pixi run test-ribasim-qgis        # Run QGIS plugin tests
pixi run tests                    # Run lint + Python + core tests

# Linting and Code Quality
pixi run lint                     # Run all linters (pre-commit + mypy)
pixi run pre-commit               # Run pre-commit hooks on all files
pixi run mypy-ribasim-python      # Type check Python package
pixi run mypy-ribasim-api         # Type check API package
pixi run mypy-ribasim-qgis        # Type check QGIS plugin

# Documentation
pixi run docs                     # Preview documentation locally
pixi run quarto-preview           # Preview Quarto documentation
pixi run quartodoc-build          # Build Python API docs

# Model Generation
pixi run generate-testmodels      # Generate test models

# Running models
pixi run ribasim-core             # Run Julia core with command line args
pixi run ribasim-core-testmodels  # Run all testmodels with core
```

## Code Architecture Patterns

### Julia Core (`core/src/`)
- **Solver integration**: Built around OrdinaryDiffEq.jl patterns with callbacks
- **Graph representation**: Network topology using MetaGraphsNext.jl

### Python Components
- **Pydantic (pandera) models**: Data validation and serialization
- **Pandas workflows**: Data processing pipelines
- **Geospatial integration**: Heavy use of GeoPandas for spatial operations
- **Arrow**: Seamless data exchange with Julia core

## Common Patterns & Conventions

We use the `GitHub` repository https://github.com/Deltares/Ribasim for issues and PRs.

### Julia Code Style
- Follow Julia community conventions
- Use multiple dispatch extensively
- Prefer immutable structs where possible
- Use `@kwdef` for struct definitions with defaults
- Avoid allocations during simulation loops
- Profile performance with `@benchmark` and `@code_warntype`
- Core solver logic in `core/src/solve.jl`

### Python Code Style
- Follow PEP 8
- Use ruff
- Use type hints extensively
- Pydantic models for data structures
- Pandas-style method chaining where appropriate
- Comprehensive docstrings (used by quartodoc for API docs)

### File Naming
- Julia: `snake_case.jl`
- Python: `snake_case.py`
- Tests: `test_*.py` (Python), `*_test.jl` (Julia)

## Data Flow & Formats

### Primary Data Formats
- **SQLite/GeoPackage**: Model database storage
- **Arrow**: Results or tables too large for SQLite
- **TOML**: Configuration files
- **NetCDF**: Conversion to NetCDF for interop

### Network Architecture
Models are represented as directed graphs where:
- **Nodes** represent physical components (basins, pumps, outlets, etc.)
- **Links** represent water connections between nodes
- **Control logic** governs dynamic behavior (PID controllers, discrete control)
- **Allocation** handles water distribution optimization

### Key Data Structures
- **Network Graph**: Node-link representation of water system
- **TimeSeries**: Time-dependent boundary conditions
- **Spatial Geometries**: Basin area polygons, link linestrings
- **Control Logic**: Rules for pumps, gates, etc.

## Common Tasks & Helpers

### When Adding New Node Types:
1. Define Julia struct in `core/src/`
2. Add Python Pydantic model in `python/ribasim/`
3. Update schema validation
4. Add to network topology handling
5. Update documentation and tests

### When Modifying Solvers:
- Core solver logic in `core/src/solve.jl`
- Integration tests in `core/integration_test/`
- Regression tests for numerical stability

### When Adding New Python Features:
- Follow the pattern in `python/ribasim/`
- Add comprehensive docstrings (used by quartodoc)
- Include examples in docstrings
- Add tests in `python/ribasim/tests/`

## Testing Strategy

### Test Generation
Most tests use generated models from `python/ribasim_testmodels/`. Always run `pixi run generate-testmodels` before running tests.

### Test Types
- **Unit tests** - `core/test/` (Julia), `python/*/tests/` (Python)
- **Integration tests** - `core/integration_test/`
- **Regression tests** - `core/regression_test/`, marked with `@pytest.mark.regression`

### Running Single Tests
```bash
# Julia single test file
julia --project=core --check-bounds=yes core/test/specific_test.jl

# Python single test
pytest python/ribasim/tests/test_specific.py
```

## Performance Considerations

### Julia Core
- Avoid allocations during simulation
- Aim towards making it statically compilable
- Profile with `@profile` and `@benchmark`
- PrecompileTools.jl for reducing startup time
- Avoid type instabilities (use `@code_warntype`)

### Python Components
- Use vectorized pandas operations

## Debugging Tips

### Julia
- `@show` for quick variable inspection
- Julia debugger for step-through debugging

### Python
- Standard Python debugging tools work
- Use `breakpoint()` for PDB
- Rich error messages from Pydantic validation

## Integration Points

### Julia ↔ Python
- SQLite database and Arrow files for model storage
- Arrow format for data exchange
- Subprocess calls from Python to Julia CLI

### QGIS Plugin
- Reads/writes same formats as Python components
- Provides GUI for model visualization
- Generates compatible model files

## Documentation

- **User docs**: `docs/` (Quarto-based, published to ribasim.org)
- **API docs**: Auto-generated from docstrings
- **Code comments**: Focus on *why*, not *what*
- **Examples**: Include runnable examples in docstrings

## Common Gotchas

1. **Julia compilation**: First run is slow due to compilation
2. **Table schema**: Ensure compatibility between Julia and Python table schemas
3. **Coordinate systems**: Be explicit about CRS in geospatial operations
4. **Numerical precision**: Water balance calculations require careful numerical handling

## Getting Help

- **Documentation**: https://ribasim.org/
- **Issues**: GitHub issues for bugs and feature requests
- **Code patterns**: Look at existing similar components for patterns
- **Tests**: Existing tests show expected usage patterns

## Key Files to Understand

- `core/src/Ribasim.jl`: Main Julia module entry point
- `python/ribasim/ribasim/model.py`: Core Python model class
- `pixi.toml`: Development environment and task definitions
- `Project.toml`: Julia development dependencies
- `core/Project.toml`: Julia package dependencies
- `python/ribasim/pyproject.toml`: Python package configuration
