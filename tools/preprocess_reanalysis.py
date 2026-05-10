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

def compute_mucape_mucin(temp_pl: np.ndarray, q_pl: np.ndarray,
                          pressure_levels: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """
    Compute Most-Unstable CAPE and CIN (J/kg).
    Searches the lowest 300 hPa (1000-700mb) for the parcel with highest CAPE.
    Applies virtual temperature correction.
    Returns (mucape, mucin) both in J/kg (mucin as positive magnitude).
    """
    nlat, nlon = temp_pl.shape[1], temp_pl.shape[2]
    mucape = np.zeros((nlat, nlon), dtype=np.float32)
    mucin  = np.zeros((nlat, nlon), dtype=np.float32)

    A = 17.625
    B = 243.04
    Rd = 287.05
    Cp = 1005.7
    g  = 9.81
    Lv = 2.501e6

    sort_idx = np.argsort(pressure_levels)[::-1]
    pressure_levels = pressure_levels[sort_idx]
    temp_pl = temp_pl[sort_idx]
    q_pl    = q_pl[sort_idx]

    # Search for most unstable parcel in lowest 300 hPa (1000-700 mb)
    search_levels = [p for p in pressure_levels if 700.0 <= p <= 1000.0]

    for j in range(nlat):
        for i in range(nlon):
            best_cape = 0.0
            best_cin  = 0.0

            for start_p in search_levels:
                # Find index of this starting level
                start_idx = int(np.argmin(np.abs(pressure_levels - start_p)))
                t_parcel = float(temp_pl[start_idx, j, i])
                q_parcel = max(float(q_pl[start_idx, j, i]), 0.0)

                # Dewpoint from q and pressure
                e = q_parcel * start_p / (0.622 + q_parcel)
                e = max(e, 0.001)
                td_c = (B * np.log(e / 6.112)) / (A - np.log(e / 6.112))
                td_k = td_c + 273.15

                # LCL temperature and pressure
                tlcl = 56.0 + 1.0 / (
                    1.0 / (td_k - 56.0) + np.log(t_parcel / td_k) / 800.0)
                plcl = start_p * (tlcl / t_parcel) ** (Cp / Rd)

                prev_p = start_p
                prev_t = t_parcel
                prev_q = q_parcel
                cape_val = 0.0
                cin_val  = 0.0
                lfc_found = False

                for lev_idx in range(len(pressure_levels)):
                    p = float(pressure_levels[lev_idx])
                    if p >= start_p:
                        continue
                    if p < 100.0:
                        break

                    t_env = float(temp_pl[lev_idx, j, i])
                    q_env = max(float(q_pl[lev_idx, j, i]), 0.0)
                    tv_env = t_env * (1.0 + 0.608 * q_env)

                    dp = prev_p - p
                    if dp <= 0:
                        continue

                    if prev_p > plcl:
                        # Dry adiabatic
                        t_parcel = prev_t * (p / prev_p) ** (Rd / Cp)
                        q_parcel = prev_q
                    else:
                        # Moist pseudo-adiabatic
                        t_c_p = t_parcel - 273.15
                        es = 6.112 * np.exp(A * t_c_p / (B + t_c_p))
                        ws = 0.622 * es / max(p - es, 0.001)
                        q_parcel = ws
                        numer = Rd * t_parcel + Lv * ws
                        denom = Cp + (Lv**2 * ws * 0.622) / (Rd * t_parcel**2)
                        gamma_s = numer / (denom * p)
                        t_parcel = t_parcel - gamma_s * dp

                    tv_parcel = t_parcel * (1.0 + 0.608 * q_parcel)
                    t_avg = (tv_parcel + tv_env) / 2.0
                    dz = (Rd * t_avg / g) * np.log(prev_p / p)

                    if tv_parcel > tv_env:
                        lfc_found = True
                        buoy = g * (tv_parcel - tv_env) / tv_env
                        cape_val += buoy * dz
                    elif not lfc_found:
                        # Below LFC — accumulate CIN
                        buoy = g * (tv_parcel - tv_env) / tv_env
                        cin_val += buoy * dz  # negative contribution

                    prev_p = p
                    prev_t = t_parcel
                    prev_q = q_parcel

                if cape_val > best_cape:
                    best_cape = cape_val
                    best_cin  = abs(cin_val)

            mucape[j, i] = best_cape
            mucin[j, i]  = best_cin

    return (np.clip(mucape, 0.0, 10000.0).astype(np.float32),
            np.clip(mucin,  0.0, 1000.0).astype(np.float32))

def compute_lapse_rate(t_upper: np.ndarray, t_lower: np.ndarray,
                       z_upper: np.ndarray, z_lower: np.ndarray) -> np.ndarray:
    """
    Compute lapse rate in °C/km between two levels.
    t_upper, t_lower: temperature in Kelvin
    z_upper, z_lower: geopotential height in meters
    Returns lapse rate in °C/km (positive = temperature decreasing with height)
    """
    dz = z_upper - z_lower      # meters, positive upward
    dt = t_upper - t_lower      # Kelvin, negative when temp decreases with height
    # Avoid division by zero
    dz = np.where(np.abs(dz) < 1.0, 1.0, dz)
    lapse = -dt / dz * 1000.0   # °C/km
    return np.clip(lapse, 0.0, 12.0).astype(np.float32)

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

def compute_esrh_ebwd(temp_pl: np.ndarray, q_pl: np.ndarray,
                       pressure_levels: np.ndarray,
                       u_pl: np.ndarray, v_pl: np.ndarray,
                       wind_pressure_levels: np.ndarray,
                       u_sfc: np.ndarray, v_sfc: np.ndarray
                       ) -> tuple[np.ndarray, np.ndarray]:
    """
    Compute Effective SRH and Effective Bulk Wind Difference.

    temp_pl, q_pl:              (n_cape_levels, H, W) on pressure_levels
    u_pl, v_pl:                 (n_wind_levels, H, W) on wind_pressure_levels
    u_sfc, v_sfc:               (H, W) surface 10m winds in m/s
    pressure_levels:            descending (1000->200)
    wind_pressure_levels:       descending (1000->300)

    Returns (esrh, ebwd) where ebwd is in m/s
    """
    nlat, nlon = temp_pl.shape[1], temp_pl.shape[2]
    esrh = np.zeros((nlat, nlon), dtype=np.float32)
    ebwd = np.zeros((nlat, nlon), dtype=np.float32)

    A = 17.625
    B = 243.04
    Rd = 287.05
    Cp = 1005.7
    g  = 9.81
    Lv = 2.501e6

    # Sort cape levels descending
    sort_idx = np.argsort(pressure_levels)[::-1]
    pressure_levels = pressure_levels[sort_idx]
    temp_pl = temp_pl[sort_idx]
    q_pl    = q_pl[sort_idx]

    # Sort wind levels descending
    wsort_idx = np.argsort(wind_pressure_levels)[::-1]
    wind_pressure_levels = wind_pressure_levels[wsort_idx]
    u_pl = u_pl[wsort_idx]
    v_pl = v_pl[wsort_idx]

    # Helper: lift parcel from start_p, return (cape, cin, el_pressure)
    def lift_parcel(j: int, i: int, start_p: float) -> tuple[float, float, float]:
        start_idx = int(np.argmin(np.abs(pressure_levels - start_p)))
        t_parcel = float(temp_pl[start_idx, j, i])
        q_parcel = max(float(q_pl[start_idx, j, i]), 0.0)

        e = q_parcel * start_p / (0.622 + q_parcel)
        e = max(e, 0.001)
        td_c = (B * np.log(e / 6.112)) / (A - np.log(e / 6.112))
        td_k = td_c + 273.15
        tlcl = 56.0 + 1.0 / (1.0 / (td_k - 56.0) + np.log(t_parcel / td_k) / 800.0)
        plcl = start_p * (tlcl / t_parcel) ** (Cp / Rd)

        prev_p = start_p
        prev_t = t_parcel
        prev_q = q_parcel
        cape_val = 0.0
        cin_val  = 0.0
        lfc_found = False
        el_p = start_p  # Default EL to start level if no LFC found

        for lev_idx in range(len(pressure_levels)):
            p = float(pressure_levels[lev_idx])
            if p >= start_p:
                continue
            if p < 100.0:
                break

            t_env = float(temp_pl[lev_idx, j, i])
            q_env = max(float(q_pl[lev_idx, j, i]), 0.0)
            tv_env = t_env * (1.0 + 0.608 * q_env)

            dp = prev_p - p
            if dp <= 0:
                continue

            if prev_p > plcl:
                t_parcel = prev_t * (p / prev_p) ** (Rd / Cp)
                q_parcel = prev_q
            else:
                t_c_p = t_parcel - 273.15
                es = 6.112 * np.exp(A * t_c_p / (B + t_c_p))
                ws = 0.622 * es / max(p - es, 0.001)
                q_parcel = ws
                numer = Rd * t_parcel + Lv * ws
                denom = Cp + (Lv**2 * ws * 0.622) / (Rd * t_parcel**2)
                gamma_s = numer / (denom * p)
                t_parcel = t_parcel - gamma_s * dp

            tv_parcel = t_parcel * (1.0 + 0.608 * q_parcel)
            t_avg = (tv_parcel + tv_env) / 2.0
            dz = (Rd * t_avg / g) * np.log(prev_p / p)

            if tv_parcel > tv_env:
                lfc_found = True
                buoy = g * (tv_parcel - tv_env) / tv_env
                cape_val += buoy * dz
                el_p = p  # Update EL to current level while parcel is buoyant
            elif not lfc_found:
                buoy = g * (tv_parcel - tv_env) / tv_env
                cin_val += buoy * dz

            prev_p = p
            prev_t = t_parcel
            prev_q = q_parcel

        return cape_val, abs(cin_val), el_p

    # Helper: interpolate wind at a given pressure level
    def interp_wind(j: int, i: int, p_target: float) -> tuple[float, float]:
        if p_target >= wind_pressure_levels[0]:
            return float(u_sfc[j, i]), float(v_sfc[j, i])
        if p_target <= wind_pressure_levels[-1]:
            return float(u_pl[-1, j, i]), float(v_pl[-1, j, i])
        for k in range(len(wind_pressure_levels) - 1):
            p_lo = wind_pressure_levels[k]
            p_hi = wind_pressure_levels[k + 1]
            if p_hi <= p_target <= p_lo:
                t = (p_lo - p_target) / (p_lo - p_hi)
                u = float(u_pl[k, j, i]) * (1 - t) + float(u_pl[k+1, j, i]) * t
                v = float(v_pl[k, j, i]) * (1 - t) + float(v_pl[k+1, j, i]) * t
                return u, v
        return float(u_sfc[j, i]), float(v_sfc[j, i])

    # Candidate levels for effective inflow base search
    inflow_candidates = [p for p in pressure_levels if 700.0 <= p <= 1000.0]
    # Bunkers levels for storm motion
    bunkers_levels = [p for p in wind_pressure_levels if 500.0 <= p <= 925.0]

    for j in range(nlat):
        for i in range(nlon):
            # ── Find effective inflow layer ──────────────────
            eff_base_p = None
            eff_top_p  = None

            for p in inflow_candidates:
                cape_val, cin_val, _ = lift_parcel(j, i, p)
                if cape_val >= 100.0 and cin_val <= 250.0:
                    if eff_base_p is None:
                        eff_base_p = p
                    eff_top_p = p  # Keep updating — highest qualifying level

            # No effective inflow layer — leave as zero
            if eff_base_p is None or eff_top_p is None or eff_base_p == eff_top_p:
                continue

            # ── Find EL of most unstable parcel ─────────────
            # Use the inflow base as the MU parcel starting level
            _, _, el_p = lift_parcel(j, i, eff_base_p)

            # ── Compute Bunkers right-mover storm motion ─────
            sum_u, sum_v = float(u_sfc[j, i]), float(v_sfc[j, i])
            count = 1
            for p in bunkers_levels:
                pidx = int(np.argmin(np.abs(wind_pressure_levels - p)))
                sum_u += float(u_pl[pidx, j, i])
                sum_v += float(v_pl[pidx, j, i])
                count += 1
            mean_u = sum_u / count
            mean_v = sum_v / count

            # Shear vector: 500mb minus surface
            pidx_500 = int(np.argmin(np.abs(wind_pressure_levels - 500.0)))
            shear_u = float(u_pl[pidx_500, j, i]) - float(u_sfc[j, i])
            shear_v = float(v_pl[pidx_500, j, i]) - float(v_sfc[j, i])
            shear_mag = float(np.sqrt(shear_u**2 + shear_v**2))
            if shear_mag < 0.001:
                continue

            rm_u = mean_u + 7.5 * (shear_v / shear_mag)
            rm_v = mean_v - 7.5 * (shear_u / shear_mag)

            # ── ESRH: integrate hodograph in effective layer ─
            # Build hodograph points from eff_base to eff_top
            hodo_levels = [p for p in wind_pressure_levels
                           if eff_top_p <= p <= eff_base_p]
            if len(hodo_levels) < 2:
                # Layer too thin — add interpolated endpoints
                hodo_levels = [eff_base_p, eff_top_p]

            srh_val = 0.0
            prev_u, prev_v = interp_wind(j, i, hodo_levels[0])
            for k in range(1, len(hodo_levels)):
                curr_u, curr_v = interp_wind(j, i, hodo_levels[k])
                sr_u0 = prev_u - rm_u
                sr_v0 = prev_v - rm_v
                sr_u1 = curr_u - rm_u
                sr_v1 = curr_v - rm_v
                srh_val -= (sr_u0 * sr_v1 - sr_v0 * sr_u1)
                prev_u, prev_v = curr_u, curr_v

            esrh[j, i] = max(0.0, srh_val)

            # ── EBWD: wind difference base to 50% EL height ─
            # Mid-storm level approximated as halfway between
            # inflow base and EL in pressure space
            mid_p = (eff_base_p + el_p) / 2.0
            u_base, v_base = interp_wind(j, i, eff_base_p)
            u_mid,  v_mid  = interp_wind(j, i, mid_p)
            ebwd_u = u_mid  - u_base
            ebwd_v = v_mid  - v_base
            ebwd[j, i] = float(np.sqrt(ebwd_u**2 + ebwd_v**2))

    return (np.clip(esrh, 0.0, 3000.0).astype(np.float32),
            np.clip(ebwd, 0.0,  100.0).astype(np.float32))

def compute_scp(mucape: np.ndarray, mucin: np.ndarray,
                esrh: np.ndarray, ebwd: np.ndarray) -> np.ndarray:
    """
    Supercell Composite Parameter (SCP).

    SCP = (muCAPE / 1000) * (ESRH / 50) * (EBWD_term) * (muCIN_term)

    EBWD_term:
        < 10 m/s -> 0
        10-20 m/s -> EBWD / 20
        > 20 m/s -> 1.0

    muCIN_term:
        muCIN > 40 J/kg -> 1.0 (weak cap, no penalty)
        else            -> -40 / (-muCIN) = 40 / muCIN

    Only positive values retained (right-mover supercells).
    """
    # CAPE term
    cape_term = mucape / 1000.0

    # ESRH term
    srh_term = esrh / 50.0

    # EBWD term
    ebwd_term = np.where(ebwd < 10.0, 0.0,
                np.where(ebwd > 20.0, 1.0,
                         ebwd / 20.0))

    # muCIN term - 1.0 when CIN is weak, penalizes strong caps
    # mucin is stored as positive magnitude
    mucin_safe = np.where(mucin < 1.0, 1.0, mucin)
    cin_term = np.where(mucin <= 40.0, 1.0, 40.0 / mucin_safe)

    scp = cape_term * srh_term * ebwd_term * cin_term

    # Only positive values (right-moving supercells)
    scp = np.where(scp < 0.0, 0.0, scp)

    return np.clip(scp, 0.0, 50.0).astype(np.float32)

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
                  pressure_levels=[1000, 975, 950, 925, 900, 875, 850, 825,
                                   800, 775, 750, 700, 650, 600, 550, 500,
                                   450, 400, 350, 300],
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

    # ── MLCAPE — computed from pressure-level temps ──────────

    print("  Computing MLCAPE...")
    mlcape_grid = compute_mlcape(temp_pl_arr, q_pl_arr,
                                 np.array(pressure_level_list, dtype=np.float32))
    mlcape_grid = gaussian_filter(mlcape_grid, sigma=0.8).astype(np.float32)
    write_gridf(str(output_dir / 'mlcape.gridf'), mlcape_grid)

    # MUCAPE and MUCIN — computed from pressure-level profiles
    print("  Computing MUCAPE/MUCIN...")
    mucape_grid, mucin_grid = compute_mucape_mucin(
        temp_pl_arr, q_pl_arr,
        np.array(pressure_level_list, dtype=np.float32)
    )
    mucape_grid = gaussian_filter(mucape_grid, sigma=0.8).astype(np.float32)
    mucin_grid = gaussian_filter(mucin_grid, sigma=0.8).astype(np.float32)
    write_gridf(str(output_dir / 'mucape.gridf'), mucape_grid)
    write_gridf(str(output_dir / 'mucinh.gridf'), mucin_grid)

    # Surface winds in m/s for SRH computation
    u10_ms_game = project_to_game_grid(u10, lats, lons)
    v10_ms_game = project_to_game_grid(v10, lats, lons)

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

    # ── Bulk shear and lapse rates ───────────────────────────

    print("Processing bulk shear and lapse rates...")
    with Dataset(pl_wind_hgt_file, 'r') as nc:
        lats, lons = get_lats_lons(nc)
        u500 = project_to_game_grid(ms_to_knots(get_var_level(nc, 'u', 500)), lats, lons)
        v500 = -project_to_game_grid(ms_to_knots(get_var_level(nc, 'v', 500)), lats, lons)
        u700 = project_to_game_grid(ms_to_knots(get_var_level(nc, 'u', 700)), lats, lons)
        v700 = -project_to_game_grid(ms_to_knots(get_var_level(nc, 'v', 700)), lats, lons)

        # Heights for lapse rate computation
        z500_m = project_to_game_grid(
            get_var_level(nc, 'z', 500) / 9.80665, lats, lons)
        z700_m = project_to_game_grid(
            get_var_level(nc, 'z', 700) / 9.80665, lats, lons)

    # 0-6km shear (sfc to 500mb)
    shear_u = u500 - u10_kt
    shear_v = v500 - v10_kt
    shear_mag = np.sqrt(shear_u ** 2 + shear_v ** 2).astype(np.float32)
    write_gridf(str(output_dir / 'shear_06.gridf'), shear_mag, shear_u, shear_v)

    # 0-3km shear (sfc to 700mb)
    shear03_u = u700 - u10_kt
    shear03_v = v700 - v10_kt
    shear03_mag = np.sqrt(shear03_u ** 2 + shear03_v ** 2).astype(np.float32)
    write_gridf(str(output_dir / 'shear_03.gridf'), shear03_mag, shear03_u, shear03_v)

    # Temperature at 500mb and 700mb for lapse rates
    with Dataset(cape_pl_file, 'r') as nc:
        pl_lats_cape, pl_lons_cape = get_lats_lons(nc)
        t500_game = project_to_game_grid(
            get_var_level(nc, 't', 500), pl_lats_cape, pl_lons_cape)
        t700_game = project_to_game_grid(
            get_var_level(nc, 't', 700), pl_lats_cape, pl_lons_cape)

    # Surface temperature (2m, already in K)
    with Dataset(sfc_file, 'r') as nc:
        sfc_lats, sfc_lons = get_lats_lons(nc)
        t2m_game = project_to_game_grid(
            get_var(nc, 't2m', '2m_temperature'), sfc_lats, sfc_lons)

    # 500-700mb lapse rate (mid-level)
    lr_ml = compute_lapse_rate(t500_game, t700_game, z500_m, z700_m)
    lr_ml = gaussian_filter(lr_ml, sigma=0.8).astype(np.float32)
    write_gridf(str(output_dir / 'lr_midlevel.gridf'), lr_ml)

    # Sfc-700mb lapse rate (low-level, surface ~0m)
    z_sfc = np.zeros_like(z700_m)  # Surface height approximated as 0m
    lr_ll = compute_lapse_rate(t700_game, t2m_game, z700_m, z_sfc)
    lr_ll = gaussian_filter(lr_ll, sigma=0.8).astype(np.float32)
    write_gridf(str(output_dir / 'lr_lowlevel.gridf'), lr_ll)

    # ── ESRH and EBWD ────────────────────────────────────────
    print("  Computing ESRH and EBWD...")
    with Dataset(srh_pl_file, 'r') as nc_srh:
        pl_lats_srh, pl_lons_srh = get_lats_lons(nc_srh)
        wind_pressure_levels_arr = np.array(
            nc_srh.variables['pressure_level'][:], dtype=np.float32)
        n_wind_levels = len(wind_pressure_levels_arr)
        u_pl_game = np.zeros((n_wind_levels, GRID_H, GRID_W), dtype=np.float32)
        v_pl_game = np.zeros((n_wind_levels, GRID_H, GRID_W), dtype=np.float32)
        for k in range(n_wind_levels):
            u_raw = np.array(nc_srh.variables['u'][0, k, :, :], dtype=np.float32)
            v_raw = np.array(nc_srh.variables['v'][0, k, :, :], dtype=np.float32)
            u_pl_game[k] = project_to_game_grid(u_raw, pl_lats_srh, pl_lons_srh)
            v_pl_game[k] = project_to_game_grid(v_raw, pl_lats_srh, pl_lons_srh)

    esrh_grid, ebwd_grid = compute_esrh_ebwd(
        temp_pl_arr, q_pl_arr,
        np.array(pressure_level_list, dtype=np.float32),
        u_pl_game, v_pl_game,
        wind_pressure_levels_arr,
        u10_ms_game, v10_ms_game
    )
    esrh_grid = gaussian_filter(esrh_grid, sigma=0.8).astype(np.float32)
    ebwd_grid = gaussian_filter(ebwd_grid, sigma=0.8).astype(np.float32)
    write_gridf(str(output_dir / 'esrh.gridf'), esrh_grid)
    write_gridf(str(output_dir / 'ebwd.gridf'), ebwd_grid)

    # ── Supercell Composite Parameter ───────────────────────
    print("  Computing SCP...")
    scp_grid = compute_scp(mucape_grid, mucin_grid, esrh_grid, ebwd_grid)
    scp_grid = gaussian_filter(scp_grid, sigma=0.5).astype(np.float32)
    write_gridf(str(output_dir / 'scp.gridf'), scp_grid)

    print(f"\nDone. Output files in {output_dir}/")
    for f in sorted(output_dir.glob('*.gridf')):
        print(f"  {f.name} ({f.stat().st_size / 1024:.1f} KB)")

    return 0

if __name__ == '__main__':
    sys.exit(main())