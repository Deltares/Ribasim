# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

Use Pixi for environment management and task execution:

```bash
# Environment setup
pixi run install                  # Install and configure all dependencies
pixi run install-julia           # Install Julia 1.11.6
pixi run initialize-julia        # Update registry and instantiate Julia project

# Building
pixi run build                    # Build Ribasim executable (requires testmodels)
pixi run generate-testmodels      # Generate test models (prerequisite for build/tests)

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

# Running models
pixi run ribasim-core             # Run Julia core with command line args
pixi run ribasim-core-testmodels  # Run all testmodels with core
```

## Project Architecture

**Ribasim** is a multi-language water resources modeling system with these main components:

### Core Structure
- **`core/`** - Julia simulation engine (main computational core)
  - Uses OrdinaryDiffEq.jl for differential equation solving
  - JuMP.jl + HiGHS.jl for optimization problems
  - MetaGraphsNext.jl for network topology
  - Arrow.jl for high-performance I/O

- **`python/ribasim/`** - Python model building and data processing
  - Pandas/GeoPandas for data manipulation
  - Pydantic for data validation and schemas
  - PyArrow for data exchange with Julia core

- **`python/ribasim_api/`** - Python API for model interaction
  - Provides programmatic interface to Ribasim models

- **`ribasim_qgis/`** - QGIS plugin for model visualization
  - GUI for model creation and visualization
  - Generates compatible model files

### Key Data Formats
- **SQLite/GeoPackage** - Model database storage
- **Arrow** - High-performance data exchange and large results
- **TOML** - Configuration files
- **NetCDF** - Conversion target for external tools

### Network Architecture
Models are represented as directed graphs where:
- **Nodes** represent physical components (basins, pumps, outlets, etc.)
- **Links** represent water connections between nodes
- **Control logic** governs dynamic behavior (PID controllers, discrete control)
- **Allocation** handles water distribution optimization

## Development Patterns

### Julia Code (core/)
- Follow Julia community conventions and multiple dispatch
- Use `@kwdef` for struct definitions with defaults
- Avoid allocations during simulation loops
- Profile performance with `@benchmark` and `@code_warntype`
- Core solver logic in `core/src/solve.jl`

### Python Code (python/)
- Follow PEP 8 and use type hints extensively
- Use Pydantic models for data structures
- Pandas-style method chaining for data processing
- Comprehensive docstrings (used by quartodoc for API docs)

### Adding New Node Types
1. Define Julia struct in `core/src/`
2. Add Python Pydantic model in `python/ribasim/nodes/`
3. Update schema validation
4. Add network topology handling
5. Update tests and documentation

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

## Important Files
- `pixi.toml` - Main development environment and task definitions
- `core/src/Ribasim.jl` - Julia module entry point
- `python/ribasim/ribasim/model.py` - Core Python model class
- `core/Project.toml` - Julia package dependencies
- `Project.toml` - Julia development dependencies
- `.github/copilot-instructions.md` - Additional development context
