#!/usr/bin/env python3
"""
ERA5 reanalysis preprocessor for the SPC forecast game.

Downloads ERA5 data from the Copernicus Climate Data Store and converts
it to .gridf files for Godot.

SETUP:
    1. Register at https://cds.climate.copernicus.eu
    2. Create ~/.cdsapirc with your API token (see README.md)
    3. Accept ERA5 terms at:
       https://cds.climate.copernicus.eu/datasets/reanalysis-era5-pressure-levels
       https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels
    4. pip install cdsapi netCDF4 numpy scipy

USAGE:
    python3 preprocess_era5.py YYYY-MM-DD HH OUTPUT_NAME
    Example: python3 preprocess_era5.py 2011-04-27 12 april_27_2011_12z
"""

import sys
import os
import struct
from pathlib import Path
from datetime import datetime

try:
    import numpy as np
    from netCDF4 import Dataset
    from scipy.ndimage import gaussian_filter
except ImportError as e:
    print(f"ERROR: Missing required package: {e}")
    print("Install with: pip install numpy netCDF4 scipy cdsapi")
    sys.exit(1)

try:
    import cdsapi
except ImportError:
    print("ERROR: cdsapi not installed. Run: pip install cdsapi")
    sys.exit(1)

# ── Game grid configuration ──────────────────────────────────
GRID_W = 80
GRID_H = 45
MAP_MIN_X = 50.0
MAP_MIN_Y = 50.0
MAP_MAX_X = 1550.0
MAP_MAX_Y = 842.0

LON_MIN, LON_MAX = -124.7, -67.0
LAT_MIN, LAT_MAX = 25.1, 49.4

# CONUS bounding box for ERA5 requests (with margin)
ERA5_NORTH = 52.0
ERA5_SOUTH = 22.0
ERA5_WEST  = -128.0
ERA5_EAST  = -64.0

# Pressure levels to download and process
UA_LEVELS_MB = [200, 300, 500, 700, 850, 925]

# All pressure levels needed for CAPE computation
CAPE_LEVELS_MB = [1000, 975, 950, 925, 900, 875, 850, 825, 800,
                  775, 750, 700, 650, 600, 550, 500, 450, 400,
                  350, 300, 250, 200]

def download_era5(
    client: cdsapi.Client,
    date_str: str,
    hour: int,
    variables: list,
    pressure_levels: list,
    output_path: str,
    single_level: bool = False
) -> None:
    """Download ERA5 fields for a single time step."""
    if Path(output_path).exists():
        print(f"  {Path(output_path).name} already exists, skipping.")
        return

    dataset = ("reanalysis-era5-single-levels"
               if single_level else
               "reanalysis-era5-pressure-levels")

    request = {
        "product_type": ["reanalysis"],
        "variable": variables,
        "year": [date_str[:4]],
        "month": [date_str[5:7]],
        "day": [date_str[8:10]],
        "time": [f"{hour:02d}:00"],
        "area": [ERA5_NORTH, ERA5_WEST, ERA5_SOUTH, ERA5_EAST],
        "data_format": "netcdf",
        "download_format": "unarchived",
    }
    if not single_level:
        request["pressure_level"] = [str(p) for p in pressure_levels]

    print(f"  Requesting {Path(output_path).name} from CDS...")
    client.retrieve(dataset, request, output_path)
    size_mb = Path(output_path).stat().st_size / (1024 * 1024)
    print(f"  Downloaded ({size_mb:.1f} MB)")

def project_to_game_grid(
    field: np.ndarray,
    lats: np.ndarray,
    lons: np.ndarray
) -> np.ndarray:
    """Project a lat/lon field onto the game's CONUS grid."""
    # ERA5 data is already in -180 to 180
    # Sort lons ascending just in case
    sort_idx = np.argsort(lons)
    lons = lons[sort_idx]
    field = field[:, sort_idx]

    center_lat = (LAT_MIN + LAT_MAX) / 2
    cos_correction = np.cos(np.radians(center_lat))
    lon_range = (LON_MAX - LON_MIN) * cos_correction
    lat_range = LAT_MAX - LAT_MIN
    map_w = MAP_MAX_X - MAP_MIN_X
    map_h = MAP_MAX_Y - MAP_MIN_Y
    scale = min(map_w / lon_range, map_h / lat_range)

    out = np.zeros((GRID_H, GRID_W), dtype=np.float32)

    for gy in range(GRID_H):
        for gx in range(GRID_W):
            map_x = MAP_MIN_X + (gx / (GRID_W - 1)) * (MAP_MAX_X - MAP_MIN_X)
            map_y = MAP_MIN_Y + (gy / (GRID_H - 1)) * (MAP_MAX_Y - MAP_MIN_Y)
            lon = LON_MIN + (map_x - MAP_MIN_X) / (cos_correction * scale)
            lat = LAT_MAX - (map_y - MAP_MIN_Y) / scale

            lat_decreasing = lats[0] > lats[-1]
            if lat_decreasing:
                lat_idx_f = (lats[0] - lat) / (lats[0] - lats[-1]) * (len(lats) - 1)
            else:
                lat_idx_f = (lat - lats[0]) / (lats[-1] - lats[0]) * (len(lats) - 1)
            lon_idx_f = (lon - lons[0]) / (lons[-1] - lons[0]) * (len(lons) - 1)

            lat_idx_f = max(0.0, min(len(lats) - 1.001, lat_idx_f))
            lon_idx_f = max(0.0, min(len(lons) - 1.001, lon_idx_f))

            i0, j0 = int(lat_idx_f), int(lon_idx_f)
            i1, j1 = i0 + 1, j0 + 1
            fi, fj = lat_idx_f - i0, lon_idx_f - j0

            top = field[i0, j0] * (1 - fj) + field[i0, j1] * fj
            bot = field[i1, j0] * (1 - fj) + field[i1, j1] * fj
            out[gy, gx] = top * (1 - fi) + bot * fi

    return out

def write_gridf(
    path: str,
    values: np.ndarray,
    u: np.ndarray = None,
    v: np.ndarray = None
) -> None:
    """Write a binary .gridf file."""
    has_vector = u is not None and v is not None
    flat_values = values.flatten().astype('<f4')

    with open(path, 'wb') as f:
        f.write(b'GRDF')
        f.write(struct.pack('<B', 1))
        f.write(struct.pack('<B', 1 if has_vector else 0))
        f.write(struct.pack('<H', GRID_W))
        f.write(struct.pack('<H', GRID_H))
        f.write(struct.pack('<f', float(flat_values.min())))
        f.write(struct.pack('<f', float(flat_values.max())))
        f.write(flat_values.tobytes())
        if has_vector:
            f.write(u.flatten().astype('<f4').tobytes())
            f.write(v.flatten().astype('<f4').tobytes())

def ms_to_knots(ms: np.ndarray) -> np.ndarray:
    return ms * 1.94384

def get_var(nc: Dataset, *names) -> np.ndarray:
    """Try multiple variable name candidates."""
    for name in names:
        if name in nc.variables:
            data = nc.variables[name][0]
            # Handle masked arrays — replace masked values with 0
            if hasattr(data, 'filled'):
                data = data.filled(0.0)
            return np.array(data, dtype=np.float32)
    raise KeyError(f"None of {names} found in {list(nc.variables.keys())}")

def get_var_level(nc: Dataset, varname: str, level_mb: int) -> np.ndarray:
    """Extract a single pressure level from a multi-level ERA5 file."""
    levels = np.array(nc.variables['pressure_level'][:])
    idx = int(np.argmin(np.abs(levels - level_mb)))
    return np.array(nc.variables[varname][0, idx, :, :], dtype=np.float32)

def get_lats_lons(nc: Dataset):
    lats = np.array(nc.variables['latitude'][:])
    lons = np.array(nc.variables['longitude'][:])
    return lats, lons

def compute_mlcape(temp_pl: np.ndarray, q_pl: np.ndarray,
                   pressure_levels: np.ndarray) -> np.ndarray:
    """
    Compute Mixed-Layer CAPE using the lowest 100 hPa mixed-layer parcel.
    Applies virtual temperature correction (Tv = T * (1 + 0.608*q)).
    temp_pl, q_pl: (n_levels, GRID_H, GRID_W)
    """
    nlat, nlon = temp_pl.shape[1], temp_pl.shape[2]
    cape = np.zeros((nlat, nlon), dtype=np.float32)

    A = 17.625
    B = 243.04
    Rd = 287.05
    Cp = 1005.7
    g = 9.81
    Lv = 2.501e6

    sort_idx = np.argsort(pressure_levels)[::-1]
    pressure_levels = pressure_levels[sort_idx]
    temp_pl = temp_pl[sort_idx]
    q_pl = q_pl[sort_idx]

    surface_p = 1000.0
    ml_top_p = surface_p - 100.0

    for j in range(nlat):
        for i in range(nlon):
            # Average T and q over lowest 100 hPa for mixed-layer parcel
            ml_temps = []
            ml_qs = []
            for lev_idx in range(len(pressure_levels)):
                p = float(pressure_levels[lev_idx])
                if ml_top_p <= p <= surface_p:
                    ml_temps.append(float(temp_pl[lev_idx, j, i]))
                    ml_qs.append(float(q_pl[lev_idx, j, i]))

            if not ml_temps:
                continue

            t_parcel = float(np.mean(ml_temps))
            q_parcel = float(np.mean(ml_qs))
            q_parcel = max(q_parcel, 0.0)

            # Virtual temperature of parcel (Tv = T * (1 + 0.608*q))
            tv_parcel = t_parcel * (1.0 + 0.608 * q_parcel)

            # Dewpoint from q and surface pressure
            e = q_parcel * surface_p / (0.622 + q_parcel)
            e = max(e, 0.001)
            td_c = (B * np.log(e / 6.112)) / (A - np.log(e / 6.112))
            td_k = td_c + 273.15

            # LCL
            tlcl = 56.0 + 1.0 / (1.0 / (td_k - 56.0) + np.log(t_parcel / td_k) / 800.0)
            plcl = surface_p * (tlcl / t_parcel) ** (Cp / Rd)

            prev_p = surface_p
            prev_t_parcel = t_parcel
            prev_q_parcel = q_parcel
            cape_val = 0.0

            for lev_idx in range(len(pressure_levels)):
                p = float(pressure_levels[lev_idx])
                if p >= surface_p:
                    continue
                if p < 100.0:
                    break

                t_env = float(temp_pl[lev_idx, j, i])
                q_env = max(float(q_pl[lev_idx, j, i]), 0.0)
                # Virtual temperature of environment
                tv_env = t_env * (1.0 + 0.608 * q_env)

                dp = prev_p - p
                if dp <= 0:
                    continue

                if prev_p > plcl:
                    # Dry adiabatic lift
                    t_parcel = prev_t_parcel * (p / prev_p) ** (Rd / Cp)
                    q_parcel = prev_q_parcel  # q conserved below LCL
                else:
                    # Moist pseudo-adiabatic lift
                    t_c_parcel = t_parcel - 273.15
                    es = 6.112 * np.exp(A * t_c_parcel / (B + t_c_parcel))
                    ws = 0.622 * es / max(p - es, 0.001)
                    q_parcel = ws  # Saturated above LCL
                    numer = Rd * t_parcel + Lv * ws
                    denom = Cp + (Lv ** 2 * ws * 0.622) / (Rd * t_parcel ** 2)
                    gamma_s = numer / (denom * p)
                    t_parcel = t_parcel - gamma_s * dp

                # Virtual temperature correction for buoyancy
                tv_parcel = t_parcel * (1.0 + 0.608 * q_parcel)

                if tv_parcel > tv_env:
                    buoy = g * (tv_parcel - tv_env) / tv_env
                    tv_avg = (tv_parcel + tv_env) / 2.0
                    dz = (Rd * tv_avg / g) * np.log(prev_p / p)
                    cape_val += buoy * dz

                prev_p = p
                prev_t_parcel = t_parcel
                prev_q_parcel = q_parcel

            cape[j, i] = cape_val

    return np.clip(cape, 0.0, 10000.0)

def compute_srh03(
    u_levels: dict, v_levels: dict,
    u_sfc: np.ndarray, v_sfc: np.ndarray
) -> np.ndarray:
    """Compute 0-3km SRH on the game grid. All winds in m/s."""
    hodo_levels_mb = [925, 850, 700]
    bunkers_levels = [925, 850, 700, 500]
    nlat, nlon = u_sfc.shape
    srh = np.zeros((nlat, nlon), dtype=np.float32)

    for j in range(nlat):
        for i in range(nlon):
            hodo_u = [float(u_sfc[j, i])]
            hodo_v = [float(v_sfc[j, i])]
            for mb in hodo_levels_mb:
                if mb in u_levels:
                    hodo_u.append(float(u_levels[mb][j, i]))
                    hodo_v.append(float(v_levels[mb][j, i]))
            if len(hodo_u) < 2:
                continue

            sum_u = float(u_sfc[j, i])
            sum_v = float(v_sfc[j, i])
            count = 1
            for mb in bunkers_levels:
                if mb in u_levels:
                    sum_u += float(u_levels[mb][j, i])
                    sum_v += float(v_levels[mb][j, i])
                    count += 1
            mean_u = sum_u / count
            mean_v = sum_v / count

            if 500 in u_levels:
                shear_u = float(u_levels[500][j, i]) - float(u_sfc[j, i])
                shear_v = float(v_levels[500][j, i]) - float(v_sfc[j, i])
            else:
                shear_u = hodo_u[-1] - hodo_u[0]
                shear_v = hodo_v[-1] - hodo_v[0]

            shear_mag = float(np.sqrt(shear_u**2 + shear_v**2))
            if shear_mag < 0.001:
                continue

            rm_u = mean_u + 7.5 * (shear_v / shear_mag)
            rm_v = mean_v - 7.5 * (shear_u / shear_mag)

            srh_val = 0.0
            for k in range(len(hodo_u) - 1):
                sr_u0 = hodo_u[k]     - rm_u
                sr_v0 = hodo_v[k]     - rm_v
                sr_u1 = hodo_u[k + 1] - rm_u
                sr_v1 = hodo_v[k + 1] - rm_v
                srh_val -= (sr_u0 * sr_v1 - sr_v0 * sr_u1)
            srh[j, i] = max(0.0, srh_val)

    return srh

def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 1

    date_str = sys.argv[1]
    hour = int(sys.argv[2])
    output_name = sys.argv[3]

    data_dir = Path(os.environ.get('ERA5_DATA_DIR', './era5_data')) / output_name
    data_dir.mkdir(parents=True, exist_ok=True)
    output_dir = Path(f'./scenarios/{output_name}')
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Processing ERA5: {date_str} {hour:02d}Z")
    print(f"Cache: {data_dir}/")
    print(f"Output: {output_dir}/")

    client = cdsapi.Client()

    # ── Download ERA5 fields ─────────────────────────────────

    pl_wind_hgt_file = str(data_dir / 'pl_wind_hgt.nc')
    download_era5(client, date_str, hour,
        variables=["geopotential", "u_component_of_wind", "v_component_of_wind"],
        pressure_levels=UA_LEVELS_MB,
        output_path=pl_wind_hgt_file
    )

    cape_pl_file = str(data_dir / 'pl_cape.nc')
    download_era5(client, date_str, hour,
        variables=["temperature", "specific_humidity"],
        pressure_levels=CAPE_LEVELS_MB,
        output_path=cape_pl_file
    )

    srh_pl_file = str(data_dir / 'pl_srh.nc')
    download_era5(client, date_str, hour,
        variables=["u_component_of_wind", "v_component_of_wind"],
        pressure_levels=[925, 850, 700, 500],
        output_path=srh_pl_file
    )

    sfc_file = str(data_dir / 'sfc.nc')
    download_era5(client, date_str, hour,
        variables=[
            "mean_sea_level_pressure",
            "2m_temperature",
            "2m_dewpoint_temperature",
            "10m_u_component_of_wind",
            "10m_v_component_of_wind",
            "convective_available_potential_energy",
            "convective_inhibition",
        ],
        pressure_levels=[],
        output_path=sfc_file,
        single_level=True
    )

    # ── Load pressure-level temperatures first (needed for SBCAPE + MLCAPE) ──

    print("\nLoading pressure-level data for CAPE computation...")
    pressure_level_list = [1000, 925, 850, 700, 600, 500, 400, 300, 250, 200]
    with Dataset(cape_pl_file, 'r') as nc:
        pl_lats_cape, pl_lons_cape = get_lats_lons(nc)
        temp_pl_game = []
        q_pl_game = []
        for mb in pressure_level_list:
            t_raw = get_var_level(nc, 't', mb)
            q_raw = get_var_level(nc, 'q', mb)
            temp_pl_game.append(project_to_game_grid(t_raw, pl_lats_cape, pl_lons_cape))
            q_pl_game.append(project_to_game_grid(q_raw, pl_lats_cape, pl_lons_cape))
        temp_pl_arr = np.array(temp_pl_game)
        q_pl_arr = np.array(q_pl_game)

    # ── Process pressure level heights and winds ─────────────

    print("Processing pressure levels...")
    with Dataset(pl_wind_hgt_file, 'r') as nc:
        lats, lons = get_lats_lons(nc)
        for mb in UA_LEVELS_MB:
            print(f"  {mb}mb...")
            z = get_var_level(nc, 'z', mb)
            hgt_dam = z / (9.80665 * 10.0)
            hgt_grid = project_to_game_grid(hgt_dam, lats, lons)
            write_gridf(str(output_dir / f'height_{mb}MB.gridf'), hgt_grid)

            u_ms = get_var_level(nc, 'u', mb)
            v_ms = get_var_level(nc, 'v', mb)
            u_kt = project_to_game_grid(ms_to_knots(u_ms), lats, lons)
            v_kt = -project_to_game_grid(ms_to_knots(v_ms), lats, lons)
            speed_kt = np.sqrt(u_kt**2 + v_kt**2)
            write_gridf(str(output_dir / f'wind_{mb}MB.gridf'), speed_kt, u_kt, v_kt)

    # ── Process surface fields ───────────────────────────────

    print("Processing surface fields...")
    with Dataset(sfc_file, 'r') as nc:
        lats, lons = get_lats_lons(nc)

        mslp = get_var(nc, 'msl', 'mean_sea_level_pressure') / 100.0
        write_gridf(str(output_dir / 'pressure_SFC.gridf'),
                    project_to_game_grid(mslp, lats, lons))

        td2m_k = get_var(nc, 'd2m', '2m_dewpoint_temperature')
        td2m_f = (td2m_k - 273.15) * 9.0 / 5.0 + 32.0
        write_gridf(str(output_dir / 'dewpoint_SFC.gridf'),
                    project_to_game_grid(td2m_f, lats, lons))

        u10 = get_var(nc, 'u10', '10m_u_component_of_wind')
        v10 = get_var(nc, 'v10', '10m_v_component_of_wind')
        u10_kt = project_to_game_grid(ms_to_knots(u10), lats, lons)
        v10_kt = -project_to_game_grid(ms_to_knots(v10), lats, lons)
        speed10 = np.sqrt(u10_kt**2 + v10_kt**2)
        write_gridf(str(output_dir / 'wind_SFC.gridf'), speed10, u10_kt, v10_kt)

        # Native ERA5 SBCAPE
        cape = get_var(nc, 'cape', 'convective_available_potential_energy')
        cape = np.clip(cape, 0.0, 10000.0).astype(np.float32)
        cape_grid = project_to_game_grid(cape, lats, lons)
        cape_grid = gaussian_filter(cape_grid, sigma=0.8).astype(np.float32)
        write_gridf(str(output_dir / 'sbcape.gridf'), cape_grid)

        # Native ERA5 CIN
        cin = get_var(nc, 'cin', 'convective_inhibition')
        # ERA5 assigns large fill values where CIN is undefined (no CAPE).
        # Mask anything more negative than -1000 J/kg as zero before abs().
        cin = np.where(cin < -1000.0, 0.0, cin)
        cin = np.abs(cin).astype(np.float32)
        cin = np.clip(cin, 0.0, 1000.0).astype(np.float32)
        cin_grid = project_to_game_grid(cin, lats, lons)
        cin_grid = gaussian_filter(cin_grid, sigma=0.8).astype(np.float32)
        write_gridf(str(output_dir / 'cinh.gridf'), cin_grid)

        # Surface winds in m/s for SRH computation
        u10_ms_game = project_to_game_grid(u10, lats, lons)
        v10_ms_game = project_to_game_grid(v10, lats, lons)

    # ── MLCAPE — computed from pressure-level temps ──────────

    print("  Computing MLCAPE...")
    mlcape_grid = compute_mlcape(temp_pl_arr, q_pl_arr,
                                 np.array(pressure_level_list, dtype=np.float32))
    mlcape_grid = gaussian_filter(mlcape_grid, sigma=0.8).astype(np.float32)
    write_gridf(str(output_dir / 'mlcape.gridf'), mlcape_grid)

    # ── SRH — load wind profiles once, compute both layers ───

    print("  Computing SRH...")
    with Dataset(srh_pl_file, 'r') as nc_srh:
        pl_lats, pl_lons = get_lats_lons(nc_srh)
        u_lvl = {}
        v_lvl = {}
        for mb in [925, 850, 700, 500]:
            u_lvl[mb] = project_to_game_grid(
                get_var_level(nc_srh, 'u', mb), pl_lats, pl_lons)
            v_lvl[mb] = project_to_game_grid(
                get_var_level(nc_srh, 'v', mb), pl_lats, pl_lons)

    # 0-3km SRH (surface, 925, 850, 700mb)
    srh_grid = compute_srh03(u_lvl, v_lvl, u10_ms_game, v10_ms_game)
    write_gridf(str(output_dir / 'srh03.gridf'), srh_grid)

    # 0-1km SRH (surface + 925mb only)
    u_lvl_01 = {925: u_lvl[925]}
    v_lvl_01 = {925: v_lvl[925]}
    srh01_grid = compute_srh03(u_lvl_01, v_lvl_01, u10_ms_game, v10_ms_game)
    write_gridf(str(output_dir / 'srh01.gridf'), srh01_grid)

    # ── Bulk shear ───────────────────────────────────────────

    print("Processing bulk shear...")
    with Dataset(pl_wind_hgt_file, 'r') as nc:
        lats, lons = get_lats_lons(nc)
        u500 = project_to_game_grid(ms_to_knots(get_var_level(nc, 'u', 500)), lats, lons)
        v500 = -project_to_game_grid(ms_to_knots(get_var_level(nc, 'v', 500)), lats, lons)
        u700 = project_to_game_grid(ms_to_knots(get_var_level(nc, 'u', 700)), lats, lons)
        v700 = -project_to_game_grid(ms_to_knots(get_var_level(nc, 'v', 700)), lats, lons)

    # 0-6km shear (sfc to 500mb)
    shear_u = u500 - u10_kt
    shear_v = v500 - v10_kt
    shear_mag = np.sqrt(shear_u**2 + shear_v**2).astype(np.float32)
    write_gridf(str(output_dir / 'shear_06.gridf'), shear_mag, shear_u, shear_v)

    # 0-3km shear (sfc to 700mb)
    shear03_u = u700 - u10_kt
    shear03_v = v700 - v10_kt
    shear03_mag = np.sqrt(shear03_u**2 + shear03_v**2).astype(np.float32)
    write_gridf(str(output_dir / 'shear_03.gridf'), shear03_mag, shear03_u, shear03_v)

    print(f"\nDone. Output files in {output_dir}/")
    for f in sorted(output_dir.glob('*.gridf')):
        print(f"  {f.name} ({f.stat().st_size / 1024:.1f} KB)")

    return 0

if __name__ == '__main__':
    sys.exit(main())