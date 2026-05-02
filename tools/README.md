# Real-Event Scenario Pipeline

This game can use real reanalysis data to create authentic forecasting scenarios.
The pipeline has three steps:

## 1. Download reanalysis data

The preprocessor uses NCEP/NCAR Reanalysis 1 data (free, available since 1948).

For a given year (e.g. 2011), download these eight files into a directory:

```
hgt.2011.nc          - Geopotential heights at all pressure levels
uwnd.2011.nc         - Zonal winds at pressure levels
vwnd.2011.nc         - Meridional winds at pressure levels
air.sig995.2011.nc   - Near-surface temperature
rhum.sig995.2011.nc  - Near-surface relative humidity
uwnd.10m.gauss.2011.nc - 10m zonal winds
vwnd.10m.gauss.2011.nc - 10m meridional winds
prmsl.2011.nc        - Mean sea level pressure
```

Direct download URLs:

```
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/pressure/hgt.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/pressure/uwnd.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/pressure/vwnd.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface/air.sig995.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface/rhum.sig995.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface_gauss/uwnd.10m.gauss.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface_gauss/vwnd.10m.gauss.2011.nc
https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface/slp.2011.nc
```

Replace `2011` with the year you need. Each file is roughly 5–50 MB.

## 2. Run the preprocessor

Install Python dependencies once:

```bash
pip install numpy netCDF4
```

Then run the preprocessor for a specific date and time:

```bash
cd tools
python3 preprocess_reanalysis.py 2011-04-27 12 april_27_2011_12z
```

Arguments:
- `2011-04-27` — date (YYYY-MM-DD)
- `12` — hour in UTC (0, 6, 12, or 18)
- `april_27_2011_12z` — output scenario directory name

By default the script looks for NetCDF files in `./reanalysis_data/`. To use a
different directory, set the environment variable:

```bash
REANALYSIS_DATA_DIR=/path/to/data python3 preprocess_reanalysis.py 2011-04-27 12 april_27_2011_12z
```

The script outputs a directory `scenarios/april_27_2011_12z/` containing one
`.gridf` file per atmospheric field.

## 3. Move the scenario into the game

Copy the output directory into the game's project under `scenarios/`:

```
spc_game/
  scenarios/
    april_27_2011_12z/
      height_200MB.gridf
      height_300MB.gridf
      ...
      wind_SFC.gridf
```

## 4. Add the scenario to scenario_data.gd

Add a new entry to the `get_scenario_list()` and `get_scenario()` functions.
Use the existing April 27 entry as a template — for a real scenario, you only
need a name, description, type ("real"), and data_path.

## .gridf file format

For reference, .gridf is a simple binary format:

```
Offset  Size  Description
------  ----  ------------------------------------
0       4     Magic "GRDF"
4       1     Version (1)
5       1     has_vector (0 or 1)
6       2     grid_width (uint16, little-endian)
8       2     grid_height (uint16)
10      4     value_min (float32)
14      4     value_max (float32)
18      N*4   values (float32 array, row-major)
+       N*4   u_values (only if has_vector)
+       N*4   v_values (only if has_vector)
```

Where N = grid_width * grid_height. Default game grid is 80×45.
