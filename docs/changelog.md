# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),

## [Unreleased]

### Added
- Support for concentration state and time for Delwaq coupling.

### Changed
- Documentation has been overhauled to be more user-friendly.


### Fixed

## [v2024.8.0] - 2024-05-14

### Added

- There is more validation on the edges. #1434
- If the model does not converge and the used algorithm supports it, we log which Basins don't converge. #1440

### Changed

- If negative storages inadvertently happen, we now throw an error. #1425
- Users of the QGIS plugin need to remove the old version to avoid two copies due to #1453.

### Fixed

- Performance improvements have been a focus of this release, giving up to 10x faster runs. #1433, #1436, #1438, #1448, #1457
- The CLI exe is now always in the root of the zip and makes use of the libribasim shared library. #1415
