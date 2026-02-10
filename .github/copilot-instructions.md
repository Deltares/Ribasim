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
- **Prek**: Code quality hooks
- **Pytest**: Python testing
- **Quarto**: Documentation generation

## Development Workflow

### Environment Setup
```bash
# Use Pixi for environment management
pixi run install            # Install and configure all dependencies
```

### Key Commands
```bash
# Testing
pixi run test-ribasim-python     # Python tests
pixi run test-ribasim-core       # Julia tests

# Documentation
pixi run quarto-preview          # Preview docs locally

# Model Generation
pixi run generate-testmodels     # Generate test models
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

### Python Code Style
- Follow PEP 8
- Use ruff
- Use type hints extensively
- Pydantic models for data structures
- Pandas-style method chaining where appropriate

### File Naming
- Julia: `snake_case.jl`
- Python: `snake_case.py`
- Tests: `test_*.py` (Python), `*_test.jl` (Julia)

## Data Flow & Formats

### Primary Data Formats
- **SQLite/GeoPackage**: Model database storage
- **Arrow**: Results or tables too large for SQLite
- **TOML**: Configuration file
- **NetCDF**: Conversion to NetCDF for interop

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

### Julia Tests
- Unit tests in `core/test/`
- Integration tests in `core/integration_test/`
- Regression tests in `core/regression_test/`

### Python Tests
- Unit tests in `python/*/tests/`
- Mark regression tests with `@pytest.mark.regression`

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
