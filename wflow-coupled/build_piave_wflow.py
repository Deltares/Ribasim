"""Build a runnable Wflow Piave model from the HydroMT artifact data catalog."""

from pathlib import Path

from hydromt_wflow import WflowSbmModel

MODEL_ROOT = Path("models/wflow_piave")
REGION = {
    "subbasin": [12.2051, 45.8331],
    "strord": 4,
    "bounds": [11.70, 45.35, 12.95, 46.70],
}

CONSTANT_PARAMETERS = {
    "subsurface_water__horizontal_to_vertical_saturated_hydraulic_conductivity_ratio": 100,
    "snowpack__degree_day_coefficient": 3.75,
    "soil_surface_water__infiltration_reduction_parameter": 0.038,
    "vegetation_canopy_water__mean_evaporation_to_mean_precipitation_ratio": 0.11,
    "compacted_soil_surface_water__infiltration_capacity": 10,
    "soil_water_saturated_zone_bottom__max_leakage_volume_flux": 0,
    "soil_wet_root__sigmoid_function_shape_parameter": -500,
    "atmosphere_air__snowfall_temperature_threshold": 0,
    "atmosphere_air__snowfall_temperature_interval": 1,
    "snowpack__melting_temperature_threshold": 0,
    "snowpack__liquid_water_holding_capacity": 0.1,
}


def main() -> None:
    """Build and write the complete Wflow SBM model."""
    model = WflowSbmModel(root=str(MODEL_ROOT), mode="w+", data_libs=["artifact_data","deltares_data"])
    model.build(
        steps=[
            {
                "setup_config": {
                    "data": {
                        "wflow_version": "1.1",
                        "time.starttime": "2010-01-01T00:00:00",
                        "time.endtime": "2014-12-31T00:00:00",
                        "time.timestepsecs": 86400,
                        "model.reservoir__flag": False,
                        "model.glacier__flag": False,
                    }
                }
            },
            {
                "setup_basemaps": {
                    "region": REGION,
                    "hydrography_fn": "merit_hydro",
                    "basin_index_fn": "merit_hydro_index",
                    "res": 1 / 120,
                    "upscale_method": "ihu",
                }
            },
            {
                "setup_rivers": {
                    "hydrography_fn": "merit_hydro",
                    "river_geom_fn": "hydro_rivers_lin",
                    "river_upa": 30,
                    "rivdph_method": "powlaw",
                    "river_routing": "kinematic_wave",
                }
            },
            {
                "setup_outlets": {
                    "river_only": True,
                    "toml_output": "csv",
                    "gauge_toml_header": ["river_q"],
                    "gauge_toml_param": ["river_water__volume_flow_rate"],
                }
            },
            {"setup_river_roughness": {}},
            {
                "setup_lulcmaps": {
                    "lulc_fn": "globcover_2009",
                    "lulc_mapping_fn": "globcover_mapping_default",
                }
            },
            {"setup_laimaps": {"lai_fn": "modis_lai"}},
            {
                "setup_soilmaps": {
                    "soil_fn": "soilgrids",
                    "ptf_ksatver": "brakensiek",
                }
            },
            {"setup_precip_forcing": {"precip_fn": "era5"}},
            {
                "setup_temp_pet_forcing": {
                    "temp_pet_fn": "era5",
                    "dem_forcing_fn": "era5_orography",
                    "pet_method": "debruin",
                }
            },
            {"setup_constant_pars": CONSTANT_PARAMETERS},
        ]
    )
    migrate_config(MODEL_ROOT / "wflow_sbm.toml")


# hydromt_wflow 1.1.0 writes standard names that were changed on Wflow main.
# The subsurface flow slope is new, and set to the land slope that was used before.
# TODO: remove once hydromt_wflow writes the new standard names.
CONFIG_MIGRATIONS = {
    'river__slope = "river_slope"\n': (
        'river_bottom_surface__slope = "river_slope"\n'
        'subsurface_bottom_surface__slope = "land_slope"\n'
    ),
    'subsurface_water__volume_flow_rate = "subsurface_q"\n': (
        'subsurface_water__instantaneous_volume_flow_rate = "subsurface_q"\n'
    ),
}


def migrate_config(toml_path: Path) -> None:
    """Rename standard names in the Wflow TOML to the ones used by Wflow main."""
    text = toml_path.read_text()
    for old, new in CONFIG_MIGRATIONS.items():
        if old not in text:
            raise ValueError(f"Expected {old!r} in {toml_path}.")
        text = text.replace(old, new)
    toml_path.write_text(text)


if __name__ == "__main__":
    main()
