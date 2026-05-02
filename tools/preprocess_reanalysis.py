#!/usr/bin/env python3
"""
NCEP/NCAR Reanalysis preprocessor for the SPC forecast game.

Reads gridded reanalysis data and resamples it onto the game's CONUS grid.
Outputs compact binary files that Godot loads via FileAccess.

USAGE:
    1. Download the required NetCDF files (see DATA SOURCES below).
    2. Place them in a directory (e.g. ./reanalysis_data/).
    3. Run: python3 preprocess_reanalysis.py YYYY-MM-DD HH OUTPUT_NAME
       Example: python3 preprocess_reanalysis.py 2011-04-27 12 april_27_2011_12z

DATA SOURCES:
    NCEP/NCAR Reanalysis 1 (4x daily, 2.5 degree, since 1948)
    https://psl.noaa.gov/data/gridded/data.ncep.reanalysis.html

    Required files (one per variable per year):
        - hgt.YYYY.nc       (geopotential height, all pressure levels)
        - uwnd.YYYY.nc      (zonal wind at pressure levels)
        - vwnd.YYYY.nc      (meridional wind at pressure levels)
        - air.sig995.YYYY.nc       (near-surface temperature)
        - rhum.sig995.YYYY.nc      (near-surface relative humidity)
        - uwnd.10m.gauss.YYYY.nc   (10m zonal wind, surface)
        - vwnd.10m.gauss.YYYY.nc   (10m meridional wind, surface)
        - slp.YYYY.nc     (sea level pressure)

    Direct download URLs:
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/pressure/hgt.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/pressure/uwnd.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/pressure/vwnd.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface/air.sig995.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface/rhum.sig995.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface_gauss/uwnd.10m.gauss.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface_gauss/vwnd.10m.gauss.YYYY.nc
        https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/surface/slp.YYYY.nc

OUTPUT FORMAT:
    Each scenario produces a directory with one .gridf file per field.

    .gridf file format (little-endian):
        - magic: 4 bytes "GRDF"
        - version: uint8 (1)
        - has_vector: uint8 (0 = scalar only, 1 = scalar + u/v components)
        - grid_width: uint16
        - grid_height: uint16
        - value_min: float32
        - value_max: float32
        - values: float32 array (grid_width * grid_height, row-major)
        - if has_vector:
            - u_values: float32 array
            - v_values: float32 array
"""

import sys
import os
import struct
from pathlib import Path
from datetime import datetime

try:
    import numpy as np
    from netCDF4 import Dataset
except ImportError as e:
    print(f"ERROR: Missing required package: {e}")
    print("Install with: pip install numpy netCDF4")
    sys.exit(1)

def download_reanalysis_files(year: int, data_dir: Path) -> bool:
    """Download required NCEP/NCAR Reanalysis files for a given year."""
    import urllib.request

    base_url = "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis"

    files_to_download = [
        (f"{base_url}/pressure/hgt.{year}.nc", f"hgt.{year}.nc"),
        (f"{base_url}/pressure/uwnd.{year}.nc", f"uwnd.{year}.nc"),
        (f"{base_url}/pressure/vwnd.{year}.nc", f"vwnd.{year}.nc"),
        (f"{base_url}/pressure/air.{year}.nc", f"air.{year}.nc"),
        (f"{base_url}/surface/air.sig995.{year}.nc", f"air.sig995.{year}.nc"),
        (f"{base_url}/surface/rhum.sig995.{year}.nc", f"rhum.sig995.{year}.nc"),
        (f"{base_url}/surface_gauss/uwnd.10m.gauss.{year}.nc", f"uwnd.10m.gauss.{year}.nc"),
        (f"{base_url}/surface_gauss/vwnd.10m.gauss.{year}.nc", f"vwnd.10m.gauss.{year}.nc"),
        (f"{base_url}/surface/slp.{year}.nc", f"slp.{year}.nc"),
    ]

    data_dir.mkdir(parents=True, exist_ok=True)
    all_ok = True

    for url, filename in files_to_download:
        dest = data_dir / filename
        if dest.exists():
            print(f" {filename} already exists, skipping.")
            continue
        print(f" Downloading {filename} ...", end="", flush=True)
        try:
            tmp = dest.with_suffix(".tmp")
            def progress(block_num, block_size, total_size):
                if total_size > 0:
                    pct = min(100, block_num * block_size * 100 // total_size)
                    print(f"\r Downloading {filename}... {pct}%", end="", flush=True)
            urllib.request.urlretrieve(url, tmp, reporthook=progress)
            tmp.rename(dest)
            size_mb = dest.stat().st_size / (1024 * 1024)
            print(f"\r {filename} done ({size_mb:.2f} MB).")
        except Exception as e:
            print(f"\r Error downloading {filename}: {e}")
            if tmp.exists():
                tmp.unlink()
            all_ok = False
    return all_ok

# ── Game grid configuration (matches AtmosphereData defaults) ──
GRID_W = 80
GRID_H = 45
MAP_MIN_X = 50.0
MAP_MIN_Y = 50.0
MAP_MAX_X = 1550.0
MAP_MAX_Y = 842.0

# CONUS bounds in lat/lon used to project reanalysis onto game grid
# These match the projection used in our state boundary data
LON_MIN, LON_MAX = -124.7, -67.0
LAT_MIN, LAT_MAX = 25.1, 49.4

# ── Pressure levels we extract ──────────────────────────────
PRESSURE_LEVELS_MB = [200, 300, 500, 700, 850, 925]

def load_reanalysis_field(filepath: str, var_name: str, time_idx: int,
                          level_idx: int = None) -> np.ndarray:
    """Load a 2D field from a NetCDF file at a given time and (optional) level."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Missing data file: {filepath}")

    with Dataset(filepath, 'r') as nc:
        var = nc.variables[var_name]
        if level_idx is not None:
            data = var[time_idx, level_idx, :, :]
        else:
            data = var[time_idx, :, :]
        # Apply scale_factor and add_offset if present (NetCDF compression)
        if hasattr(var, 'scale_factor') or hasattr(var, 'add_offset'):
            sf = getattr(var, 'scale_factor', 1.0)
            ao = getattr(var, 'add_offset', 0.0)
            data = data * sf + ao
        return np.array(data, dtype=np.float32)

def get_lat_lon_arrays(filepath: str) -> tuple[np.ndarray, np.ndarray]:
    """Read latitude and longitude arrays from a NetCDF file."""
    with Dataset(filepath, 'r') as nc:
        lats = np.array(nc.variables['lat'][:])
        lons = np.array(nc.variables['lon'][:])
        return lats, lons

def get_time_index(filepath: str, target_date: datetime) -> int:
    """Find the time index closest to the target date in a NetCDF file."""
    with Dataset(filepath, 'r') as nc:
        time_var = nc.variables['time']
        # NCEP times are typically "hours since 1800-01-01"
        units = time_var.units
        try:
            from netCDF4 import num2date
            times = num2date(time_var[:], units=units)
            # Find closest time
            time_diffs = [abs((datetime(t.year, t.month, t.day, t.hour) - target_date).total_seconds())
                         for t in times]
            return int(np.argmin(time_diffs))
        except Exception:
            # Fallback: assume 6-hourly data starting Jan 1 of file year
            year = target_date.year
            base = datetime(year, 1, 1)
            hours_diff = (target_date - base).total_seconds() / 3600.0
            return int(round(hours_diff / 6.0))

def get_level_index(filepath: str, target_mb: int) -> int:
    """Find the pressure level index for a given pressure in mb."""
    with Dataset(filepath, 'r') as nc:
        levels = np.array(nc.variables['level'][:])
        return int(np.argmin(np.abs(levels - target_mb)))

def project_to_game_grid(field: np.ndarray, lats: np.ndarray, lons: np.ndarray) -> np.ndarray:
    """
    Project a global lat/lon field onto the game's CONUS grid.
    Uses the same equirectangular projection with cosine-latitude correction
    as our state boundary data.
    """
    # Normalize longitudes to -180 to 180 if needed
    if lons.max() > 180:
        lons = np.where(lons > 180, lons - 360, lons)
        # Sort lons ascending and reorder the field columns to match
        sort_idx = np.argsort(lons)
        lons = lons[sort_idx]
        field = field[:, sort_idx]

    center_lat = (LAT_MIN + LAT_MAX) / 2
    cos_correction = np.cos(np.radians(center_lat))

    lon_range = (LON_MAX - LON_MIN) * cos_correction
    lat_range = LAT_MAX - LAT_MIN

    map_w = MAP_MAX_X - MAP_MIN_X
    map_h = MAP_MAX_Y - MAP_MIN_Y

    # Use min of x and y scale (matching state projection)
    scale = min(map_w / lon_range, map_h / lat_range)

    out = np.zeros((GRID_H, GRID_W), dtype=np.float32)

    for gy in range(GRID_H):
        for gx in range(GRID_W):
            # Game grid cell to map-space coords
            map_x = MAP_MIN_X + (gx / (GRID_W - 1)) * (MAP_MAX_X - MAP_MIN_X)
            map_y = MAP_MIN_Y + (gy / (GRID_H - 1)) * (MAP_MAX_Y - MAP_MIN_Y)

            # Reverse projection — same formula as the state data generator
            # Solve: map_x = (lon - LON_MIN) * cos_correction * scale + PADDING
            # We used PADDING=50 in the state data, which corresponds to MAP_MIN_X
            lon = LON_MIN + (map_x - MAP_MIN_X) / (cos_correction * scale)
            lat = LAT_MAX - (map_y - MAP_MIN_Y) / scale

            # Bilinear interpolation from reanalysis grid
            # Find surrounding lat/lon indices
            # Reanalysis lats typically run north to south
            lat_decreasing = lats[0] > lats[-1]
            if lat_decreasing:
                lat_idx_f = (lats[0] - lat) / (lats[0] - lats[-1]) * (len(lats) - 1)
            else:
                lat_idx_f = (lat - lats[0]) / (lats[-1] - lats[0]) * (len(lats) - 1)

            lon_idx_f = (lon - lons[0]) / (lons[-1] - lons[0]) * (len(lons) - 1)

            # Clamp
            lat_idx_f = max(0.0, min(len(lats) - 1.001, lat_idx_f))
            lon_idx_f = max(0.0, min(len(lons) - 1.001, lon_idx_f))

            i0 = int(lat_idx_f)
            j0 = int(lon_idx_f)
            i1 = i0 + 1
            j1 = j0 + 1
            fi = lat_idx_f - i0
            fj = lon_idx_f - j0

            v00 = field[i0, j0]
            v10 = field[i0, j1]
            v01 = field[i1, j0]
            v11 = field[i1, j1]

            top = v00 * (1 - fj) + v10 * fj
            bot = v01 * (1 - fj) + v11 * fj
            out[gy, gx] = top * (1 - fi) + bot * fi

    return out

def write_gridf(path: str, values: np.ndarray, u: np.ndarray = None,
                v: np.ndarray = None) -> None:
    """Write a binary .gridf file for Godot to read."""
    has_vector = u is not None and v is not None

    flat_values = values.flatten().astype('<f4')
    value_min = float(flat_values.min())
    value_max = float(flat_values.max())

    with open(path, 'wb') as f:
        f.write(b'GRDF')                  # magic
        f.write(struct.pack('<B', 1))     # version
        f.write(struct.pack('<B', 1 if has_vector else 0))
        f.write(struct.pack('<H', GRID_W))
        f.write(struct.pack('<H', GRID_H))
        f.write(struct.pack('<f', value_min))
        f.write(struct.pack('<f', value_max))
        f.write(flat_values.tobytes())
        if has_vector:
            f.write(u.flatten().astype('<f4').tobytes())
            f.write(v.flatten().astype('<f4').tobytes())

def kelvin_to_fahrenheit(k: np.ndarray) -> np.ndarray:
    return (k - 273.15) * 9.0 / 5.0 + 32.0

def calc_dewpoint_f(temp_k: np.ndarray, rh_pct: np.ndarray) -> np.ndarray:
    """
    Calculate dewpoint in °F from temperature (K) and relative humidity (%).
    Uses the Magnus approximation.
    """
    temp_c = temp_k - 273.15
    rh = np.clip(rh_pct / 100.0, 0.001, 1.0)

    a = 17.625
    b = 243.04
    alpha = np.log(rh) + (a * temp_c) / (b + temp_c)
    td_c = (b * alpha) / (a - alpha)

    return td_c * 9.0 / 5.0 + 32.0

def ms_to_knots(ms: np.ndarray) -> np.ndarray:
    return ms * 1.94384

def compute_sbcape(temp_pl: np.ndarray, pressure_levels: np.ndarray,
                   temp_sfc: np.ndarray, rh_sfc: np.ndarray) -> np.ndarray:
    """
    Compute surface-based CAPE (J/kg) using pseudo-adiabatic parcel ascent.
    All arrays are on the same grid (GRID_H x GRID_W).
    temp_pl: (n_levels, GRID_H, GRID_W) in Kelvin, pressure_levels descending (1000->200)
    """
    nlat, nlon = temp_sfc.shape
    cape = np.zeros((nlat, nlon), dtype=np.float32)

    A = 17.625
    B = 243.04
    Rd = 287.05
    Cp = 1005.7
    g = 9.81
    Lv = 2.501e6

    # Ensure pressure levels are sorted descending (surface first)
    sort_idx = np.argsort(pressure_levels)[::-1]
    pressure_levels = pressure_levels[sort_idx]
    temp_pl = temp_pl[sort_idx]

    for j in range(nlat):
        for i in range(nlon):
            t_sfc = float(temp_sfc[j, i])
            rh = float(np.clip(rh_sfc[j, i] / 100.0, 0.01, 1.0))

            # Surface dewpoint
            t_c = t_sfc - 273.15
            alpha = np.log(rh) + (A * t_c) / (B + t_c)
            td_c = (B * alpha) / (A - alpha)
            td_k = td_c + 273.15

            # LCL temperature and pressure (Bolton 1980)
            tlcl = 56.0 + 1.0 / (1.0 / (td_k - 56.0) + np.log(t_sfc / td_k) / 800.0)
            plcl = 1000.0 * (tlcl / t_sfc) ** (Cp / Rd)

            t_parcel = t_sfc
            prev_p = 1000.0
            prev_t_parcel = t_sfc
            cape_val = 0.0

            for lev_idx in range(len(pressure_levels)):
                p = float(pressure_levels[lev_idx])
                if p >= 1000.0:
                    continue  # Skip surface level
                if p < 100.0:
                    break     # Stop at 100mb

                t_env = float(temp_pl[lev_idx, j, i])
                dp = prev_p - p   # positive (going up)

                # Lift parcel
                if prev_p > plcl:
                    # Dry adiabatic below LCL
                    # Poisson's equation
                    t_parcel = prev_t_parcel * (p / prev_p) ** (Rd / Cp)
                else:
                    # Moist pseudo-adiabatic above LCL
                    t_c_parcel = t_parcel - 273.15
                    es = 6.112 * np.exp(A * t_c_parcel / (B + t_c_parcel))
                    ws = 0.622 * es / max(p - es, 0.001)
                    # Saturated adiabatic lapse rate (K/mb)
                    numer = Rd * t_parcel + Lv * ws
                    denom = Cp + (Lv ** 2 * ws * 0.622) / (Rd * t_parcel ** 2)
                    gamma_s = numer / (denom * p)  # K/mb
                    t_parcel = t_parcel - gamma_s * dp

                # Positive buoyancy contribution
                if t_parcel > t_env:
                    # Layer-average buoyancy
                    buoy = g * (t_parcel - t_env) / t_env
                    # Layer thickness via hypsometric equation (m)
                    t_avg = (t_parcel + t_env) / 2.0
                    dz = (Rd * t_avg / g) * np.log(prev_p / p)
                    cape_val += buoy * dz

                prev_p = p
                prev_t_parcel = t_parcel

            cape[j, i] = cape_val

    return np.clip(cape, 0.0, 10000.0)


def compute_srh03(u_levels: dict, v_levels: dict,
                  u_sfc: np.ndarray, v_sfc: np.ndarray) -> np.ndarray:
    """
    Compute 0-3km Storm Relative Helicity (m²/s²).
    All wind arrays are on the game grid (GRID_H x GRID_W) in m/s.
    """
    hodo_levels_mb = [925, 850, 700]
    bunkers_levels = [925, 850, 700, 500]

    nlat, nlon = u_sfc.shape
    srh = np.zeros((nlat, nlon), dtype=np.float32)

    for j in range(nlat):
        for i in range(nlon):
            # Build hodograph from surface upward through ~3km
            hodo_u = [float(u_sfc[j, i])]
            hodo_v = [float(v_sfc[j, i])]

            for mb in hodo_levels_mb:
                if mb in u_levels:
                    hodo_u.append(float(u_levels[mb][j, i]))
                    hodo_v.append(float(v_levels[mb][j, i]))

            if len(hodo_u) < 2:
                continue

            # Mean wind for Bunkers (surface + pressure levels)
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

            # Shear vector: 500mb minus surface
            if 500 in u_levels:
                shear_u = float(u_levels[500][j, i]) - float(u_sfc[j, i])
                shear_v = float(v_levels[500][j, i]) - float(v_sfc[j, i])
            else:
                shear_u = hodo_u[-1] - hodo_u[0]
                shear_v = hodo_v[-1] - hodo_v[0]

            shear_mag = float(np.sqrt(shear_u**2 + shear_v**2))
            if shear_mag < 0.001:
                continue

            # Right-mover: 7.5 m/s to the right of shear vector
            # Right of shear = rotate shear 90° clockwise = (shear_v, -shear_u)
            rm_u = mean_u + 7.5 * (shear_v / shear_mag)
            rm_v = mean_v - 7.5 * (shear_u / shear_mag)

            # SRH = -2 * signed area swept by storm-relative hodograph
            # Using the shoelace formula on storm-relative vectors
            srh_val = 0.0
            for k in range(len(hodo_u) - 1):
                sr_u0 = hodo_u[k]     - rm_u
                sr_v0 = hodo_v[k]     - rm_v
                sr_u1 = hodo_u[k + 1] - rm_u
                sr_v1 = hodo_v[k + 1] - rm_v
                # Negative sign gives positive SRH for cyclonically curved hodographs
                srh_val -= (sr_u0 * sr_v1 - sr_v0 * sr_u1)

            srh[j, i] = max(0.0, srh_val)

    return srh

def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 1

    date_str = sys.argv[1]   # YYYY-MM-DD
    hour = int(sys.argv[2])  # 0, 6, 12, or 18
    output_name = sys.argv[3]

    data_dir = Path(os.environ.get('REANALYSIS_DATA_DIR', './reanalysis_data'))
    output_dir = Path(f'./scenarios/{output_name}')
    output_dir.mkdir(parents=True, exist_ok=True)

    target_date = datetime.strptime(date_str, '%Y-%m-%d').replace(hour=hour)
    year = target_date.year

    print(f"Processing {target_date} from {data_dir}/")
    print(f"Output: {output_dir}/")

    # Required files
    files = {
        'hgt':       data_dir / f'hgt.{year}.nc',
        'uwnd':      data_dir / f'uwnd.{year}.nc',
        'vwnd':      data_dir / f'vwnd.{year}.nc',
        'air_pl':    data_dir / f'air.{year}.nc',
        'air_sfc':   data_dir / f'air.sig995.{year}.nc',
        'rhum_sfc':  data_dir / f'rhum.sig995.{year}.nc',
        'u10m':      data_dir / f'uwnd.10m.gauss.{year}.nc',
        'v10m':      data_dir / f'vwnd.10m.gauss.{year}.nc',
        'slp':       data_dir / f'slp.{year}.nc',
    }

    # Auto-download missing files
    missing = [str(p) for p in files.values() if not p.exists()]
    if missing:
        print(f"Some files missing for {year}. Downloading from NOAA PSL...")
        if not download_reanalysis_files(year, data_dir):
            print("Some downloads failed. Check internet connection, or input year and try again.")
            return 1
        # Re-check after download
        missing = [str(p) for p in files.values() if not p.exists()]
        if missing:
            print("Some files still missing after download attempt.")
            for m in missing:
                print(f" {m}")
            return 1
    else:
        print(f"All data files for {year} found locally.")

    # Get coordinate arrays and time index from one file
    pressure_lats, pressure_lons = get_lat_lon_arrays(str(files['hgt']))
    time_idx = get_time_index(str(files['hgt']), target_date)
    print(f"Time index: {time_idx}")

    # ── Process pressure levels ─────────────────────────────
    for mb in PRESSURE_LEVELS_MB:
        print(f"  {mb}mb...")
        level_idx = get_level_index(str(files['hgt']), mb)

        # Heights (meters → decameters)
        hgt_m = load_reanalysis_field(str(files['hgt']), 'hgt', time_idx, level_idx)
        hgt_dam = hgt_m / 10.0
        hgt_grid = project_to_game_grid(hgt_dam, pressure_lats, pressure_lons)

        # Winds at this level (m/s → knots)
        u_ms = load_reanalysis_field(str(files['uwnd']), 'uwnd', time_idx, level_idx)
        v_ms = load_reanalysis_field(str(files['vwnd']), 'vwnd', time_idx, level_idx)
        u_kt = project_to_game_grid(ms_to_knots(u_ms), pressure_lats, pressure_lons)
        # Reanalysis v is positive northward; our map y increases southward, so flip
        v_kt = -project_to_game_grid(ms_to_knots(v_ms), pressure_lats, pressure_lons)
        speed_kt = np.sqrt(u_kt ** 2 + v_kt ** 2)

        # Save height as contour data
        write_gridf(str(output_dir / f'height_{mb}MB.gridf'), hgt_grid)

        # Save wind as vector field
        write_gridf(str(output_dir / f'wind_{mb}MB.gridf'), speed_kt, u_kt, v_kt)

    # ── Surface fields ──────────────────────────────────────
    print("  Surface...")

    # SLP (Pa → mb)
    slp_lats, slp_lons = get_lat_lon_arrays(str(files['slp']))
    slp_pa = load_reanalysis_field(str(files['slp']), 'slp', time_idx)
    slp_mb = slp_pa / 100.0
    slp_grid = project_to_game_grid(slp_mb, slp_lats, slp_lons)
    write_gridf(str(output_dir / 'pressure_SFC.gridf'), slp_grid)

    # Surface dewpoint (computed from T and RH at sigma=0.995)
    sfc_lats, sfc_lons = get_lat_lon_arrays(str(files['air_sfc']))
    temp_k = load_reanalysis_field(str(files['air_sfc']), 'air', time_idx)
    rh_pct = load_reanalysis_field(str(files['rhum_sfc']), 'rhum', time_idx)
    td_f = calc_dewpoint_f(temp_k, rh_pct)
    td_grid = project_to_game_grid(td_f, sfc_lats, sfc_lons)
    write_gridf(str(output_dir / 'dewpoint_SFC.gridf'), td_grid)

    # Surface winds (10m, on Gaussian grid)
    sfc_u_lats, sfc_u_lons = get_lat_lon_arrays(str(files['u10m']))
    u10_ms = load_reanalysis_field(str(files['u10m']), 'uwnd', time_idx)
    v10_ms = load_reanalysis_field(str(files['v10m']), 'vwnd', time_idx)
    u10_kt = project_to_game_grid(ms_to_knots(u10_ms), sfc_u_lats, sfc_u_lons)
    v10_kt = -project_to_game_grid(ms_to_knots(v10_ms), sfc_u_lats, sfc_u_lons)
    speed10_kt = np.sqrt(u10_kt ** 2 + v10_kt ** 2)
    write_gridf(str(output_dir / 'wind_SFC.gridf'), speed10_kt, u10_kt, v10_kt)

    # ── Derived fields ──────────────────────────────────────
    # ── SBCAPE ──────────────────────────────────────────────
    print("  Computing SBCAPE...")
    pressure_level_list = [1000, 925, 850, 700, 600, 500, 400, 300, 250, 200]
    pl_lats, pl_lons = get_lat_lon_arrays(str(files['air_pl']))

    # Project all pressure-level temps onto game grid first
    temp_pl_game = []
    for mb in pressure_level_list:
        lev_idx = get_level_index(str(files['air_pl']), mb)
        t_raw = load_reanalysis_field(str(files['air_pl']), 'air', time_idx, lev_idx)
        temp_pl_game.append(project_to_game_grid(t_raw, pl_lats, pl_lons))
    temp_pl_arr = np.array(temp_pl_game)  # (levels, GRID_H, GRID_W)

    # Use 1000mb temperature as surface parcel temperature
    # over land than sigma=0.995 which picks up warm Gulf SSTs
    lev_idx_1000 = get_level_index(str(files['air_pl']), 1000)
    temp_1000mb = load_reanalysis_field(str(files['air_pl']), 'air', time_idx, lev_idx_1000)
    temp_sfc_game = project_to_game_grid(temp_1000mb, pl_lats, pl_lons)

    # RH still from sigma=0.995 — regrid to match pressure-level grid
    rh_sfc_game = project_to_game_grid(rh_pct, sfc_lats, sfc_lons)
    # Resize rh_sfc_game to match pressure-level game grid if needed
    # (both should be 45x80 already after project_to_game_grid)

    cape_grid = compute_sbcape(
        temp_pl_arr,
        np.array(pressure_level_list, dtype=np.float32),
        temp_sfc_game,
        rh_sfc_game
    )

    # Smooth SBCAPE to remove blockiness from 2.5-degree grid artifacts
    from scipy.ndimage import gaussian_filter
    cape_grid = gaussian_filter(cape_grid, sigma=1.2).astype(np.float32)

    write_gridf(str(output_dir / 'sbcape.gridf'), cape_grid)

    # ── 0-3km SRH ───────────────────────────────────────────
    print(" Computing 0-3km SRH...")

    srh_levels_mb = [925, 850, 700, 500]
    u_lvl: dict = {}
    v_lvl: dict = {}
    for mb in srh_levels_mb:
        lev_idx = get_level_index(str(files['uwnd']), mb)
        u_lvl[mb] = load_reanalysis_field(str(files['uwnd']), 'uwnd', time_idx, lev_idx)
        v_lvl[mb] = load_reanalysis_field(str(files['vwnd']), 'vwnd', time_idx, lev_idx)

    # Project all pressure-level winds onto game grid first, then compute SRH on game grid
    u_lvl_game: dict = {}
    v_lvl_game: dict = {}
    for mb in srh_levels_mb:
        # Keep in m/s for SRH calculation — no ms_to_knots here
        u_lvl_game[mb] = project_to_game_grid(u_lvl[mb], pressure_lats, pressure_lons)
        v_lvl_game[mb] = project_to_game_grid(v_lvl[mb], pressure_lats, pressure_lons)

    # Surface winds also in m/s
    u10_ms_game = project_to_game_grid(u10_ms, sfc_u_lats, sfc_u_lons)
    v10_ms_game = project_to_game_grid(v10_ms, sfc_u_lats, sfc_u_lons)

    srh_grid = compute_srh03(u_lvl_game, v_lvl_game, u10_ms_game, v10_ms_game)
    write_gridf(str(output_dir / 'srh03.gridf'), srh_grid)

    # Bulk shear (0-6km) — vector difference between sfc wind and 500mb wind
    # 500mb is roughly at 5.5km — close enough to "0-6km" for game purposes
    u500_ms = load_reanalysis_field(str(files['uwnd']), 'uwnd', time_idx,
                                     get_level_index(str(files['uwnd']), 500))
    v500_ms = load_reanalysis_field(str(files['vwnd']), 'vwnd', time_idx,
                                     get_level_index(str(files['vwnd']), 500))
    u500_kt = project_to_game_grid(ms_to_knots(u500_ms), pressure_lats, pressure_lons)
    v500_kt = -project_to_game_grid(ms_to_knots(v500_ms), pressure_lats, pressure_lons)

    shear_u = u500_kt - u10_kt
    shear_v = v500_kt - v10_kt
    shear_mag = np.sqrt(shear_u ** 2 + shear_v ** 2)
    write_gridf(str(output_dir / 'shear_06.gridf'), shear_mag, shear_u, shear_v)

    print(f"\nDone. Output files in {output_dir}/")
    print("Files:")
    for f in sorted(output_dir.glob('*.gridf')):
        size_kb = f.stat().st_size / 1024
        print(f"  {f.name} ({size_kb:.1f} KB)")

    return 0

if __name__ == '__main__':
    sys.exit(main())
