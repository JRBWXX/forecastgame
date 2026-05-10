extends RefCounted
class_name AtmosphereData

## Holds a 2D grid of float values over the CONUS map area.
## Provides bilinear interpolation and color ramp mapping.
## Designed to be reused for any scalar atmospheric parameter.

# Grid dimensions
var grid_width: int
var grid_height: int

# Map-space bounds (matches the projected CONUS coordinates)
var map_min := Vector2(50.0, 50.0)
var map_max := Vector2(1550.0, 842.0)

# Raw data (row-major: index = y * grid_width + x)
var values: PackedFloat32Array

# Value range for color mapping
var value_min: float = 0.0
var value_max: float = 5000.0

# Optional vector components (for wind/shear fields)
var u_values: PackedFloat32Array   # East-west component (positive = east/right)
var v_values: PackedFloat32Array   # North-south in map coords (positive = down/south)
var has_vector := false

func _init(w: int = 80, h: int = 45) -> void:
	grid_width = w
	grid_height = h
	values = PackedFloat32Array()
	values.resize(w * h)
	u_values = PackedFloat32Array()
	v_values = PackedFloat32Array()

func get_cell(gx: int, gy: int) -> float:
	gx = clampi(gx, 0, grid_width - 1)
	gy = clampi(gy, 0, grid_height - 1)
	return values[gy * grid_width + gx]

func set_cell(gx: int, gy: int, val: float) -> void:
	if gx >= 0 and gx < grid_width and gy >= 0 and gy < grid_height:
		values[gy * grid_width + gx] = val

func map_to_grid(map_pos: Vector2) -> Vector2:
	var fx := (map_pos.x - map_min.x) / (map_max.x - map_min.x) * (grid_width - 1)
	var fy := (map_pos.y - map_min.y) / (map_max.y - map_min.y) * (grid_height - 1)
	return Vector2(fx, fy)

func sample(map_pos: Vector2) -> float:
	var g := map_to_grid(map_pos)
	var x0 := int(floor(g.x))
	var y0 := int(floor(g.y))
	var x1 := x0 + 1
	var y1 := y0 + 1
	var fx := g.x - x0
	var fy := g.y - y0
	var v00 := get_cell(x0, y0)
	var v10 := get_cell(x1, y0)
	var v01 := get_cell(x0, y1)
	var v11 := get_cell(x1, y1)
	var top := v00 * (1.0 - fx) + v10 * fx
	var bot := v01 * (1.0 - fx) + v11 * fx
	return top * (1.0 - fy) + bot * fy

func init_vector() -> void:
	u_values = PackedFloat32Array()
	u_values.resize(grid_width * grid_height)
	v_values = PackedFloat32Array()
	v_values.resize(grid_width * grid_height)
	has_vector = true

func get_u(gx: int, gy: int) -> float:
	gx = clampi(gx, 0, grid_width - 1)
	gy = clampi(gy, 0, grid_height - 1)
	return u_values[gy * grid_width + gx]

func get_v(gx: int, gy: int) -> float:
	gx = clampi(gx, 0, grid_width - 1)
	gy = clampi(gy, 0, grid_height - 1)
	return v_values[gy * grid_width + gx]

func set_vector(gx: int, gy: int, u: float, v: float) -> void:
	if gx >= 0 and gx < grid_width and gy >= 0 and gy < grid_height:
		var idx := gy * grid_width + gx
		u_values[idx] = u
		v_values[idx] = v

func sample_vector(map_pos: Vector2) -> Vector2:
	var g := map_to_grid(map_pos)
	var x0 := int(floor(g.x))
	var y0 := int(floor(g.y))
	var x1 := x0 + 1
	var y1 := y0 + 1
	var fx := g.x - x0
	var fy := g.y - y0
	var u00 := get_u(x0, y0); var v00_v := get_v(x0, y0)
	var u10 := get_u(x1, y0); var v10_v := get_v(x1, y0)
	var u01 := get_u(x0, y1); var v01_v := get_v(x0, y1)
	var u11 := get_u(x1, y1); var v11_v := get_v(x1, y1)
	var u_top := u00 * (1.0 - fx) + u10 * fx
	var u_bot := u01 * (1.0 - fx) + u11 * fx
	var u_val := u_top * (1.0 - fy) + u_bot * fy
	var v_top := v00_v * (1.0 - fx) + v10_v * fx
	var v_bot := v01_v * (1.0 - fx) + v11_v * fx
	var v_val := v_top * (1.0 - fy) + v_bot * fy
	return Vector2(u_val, v_val)

# ── Color Ramps ─────────────────────────────────────────────

static var sbcape_stops: Array[Dictionary] = [
	{ "val": 0.0,    "color": Color(0.95, 0.95, 0.95, 0.0) },
	{ "val": 100.0,  "color": Color(0.92, 0.92, 0.90, 0.40) },
	{ "val": 250.0,  "color": Color(0.93, 0.93, 0.80, 0.55) },
	{ "val": 500.0,  "color": Color(0.94, 0.91, 0.55, 0.70) },
	{ "val": 750.0,  "color": Color(0.91, 0.85, 0.22, 0.75) },
	{ "val": 1000.0, "color": Color(0.90, 0.73, 0.10, 0.78) },
	{ "val": 1250.0, "color": Color(0.97, 0.60, 0.00, 0.80) },
	{ "val": 1500.0, "color": Color(0.93, 0.40, 0.00, 0.82) },
	{ "val": 1750.0, "color": Color(0.88, 0.22, 0.00, 0.83) },
	{ "val": 2000.0, "color": Color(0.82, 0.08, 0.00, 0.85) },
	{ "val": 2500.0, "color": Color(0.62, 0.00, 0.00, 0.85) },
	{ "val": 3000.0, "color": Color(0.42, 0.00, 0.05, 0.85) },
	{ "val": 3500.0, "color": Color(0.38, 0.00, 0.25, 0.85) },
	{ "val": 4000.0, "color": Color(0.48, 0.12, 0.55, 0.85) },
	{ "val": 4500.0, "color": Color(0.58, 0.32, 0.68, 0.85) },
	{ "val": 5000.0, "color": Color(0.73, 0.52, 0.82, 0.85) },
	{ "val": 5500.0, "color": Color(0.84, 0.72, 0.88, 0.85) },
	{ "val": 6000.0, "color": Color(0.30, 0.72, 0.72, 0.85) },
	{ "val": 6500.0, "color": Color(0.15, 0.58, 0.58, 0.85) },
	{ "val": 7000.0, "color": Color(0.05, 0.42, 0.42, 0.85) },
	{ "val": 7500.0, "color": Color(0.35, 0.10, 0.10, 0.88) },
	{ "val": 8000.0, "color": Color(0.25, 0.05, 0.05, 0.90) },
	{ "val": 8500.0, "color": Color(0.15, 0.02, 0.02, 0.90) },
]

## Mixed-Layer CAPE color ramp — same scale as SBCAPE
static var mlcape_stops: Array[Dictionary] = [
	{ "val": 0.0,    "color": Color(0.95, 0.95, 0.95, 0.0) },
	{ "val": 100.0,  "color": Color(0.92, 0.92, 0.90, 0.40) },
	{ "val": 250.0,  "color": Color(0.93, 0.93, 0.80, 0.55) },
	{ "val": 500.0,  "color": Color(0.94, 0.91, 0.55, 0.70) },
	{ "val": 750.0,  "color": Color(0.91, 0.85, 0.22, 0.75) },
	{ "val": 1000.0, "color": Color(0.90, 0.73, 0.10, 0.78) },
	{ "val": 1500.0, "color": Color(0.97, 0.60, 0.00, 0.80) },
	{ "val": 2000.0, "color": Color(0.93, 0.40, 0.00, 0.82) },
	{ "val": 2500.0, "color": Color(0.82, 0.08, 0.00, 0.85) },
	{ "val": 3000.0, "color": Color(0.62, 0.00, 0.00, 0.85) },
	{ "val": 3500.0, "color": Color(0.42, 0.00, 0.05, 0.85) },
	{ "val": 4000.0, "color": Color(0.48, 0.12, 0.55, 0.85) },
	{ "val": 5000.0, "color": Color(0.73, 0.52, 0.82, 0.85) },
	{ "val": 6000.0, "color": Color(0.30, 0.72, 0.72, 0.85) },
	{ "val": 7000.0, "color": Color(0.05, 0.42, 0.42, 0.85) },
	{ "val": 8500.0, "color": Color(0.15, 0.02, 0.02, 0.90) },
]

## CINH color ramp — maps J/kg (absolute value) to color.
## Light = weak cap, dark red/brown = strong cap.
static var cinh_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },     # Transparent (no cap)
	{ "val": 10.0,  "color": Color(0.80, 0.88, 0.72, 0.35) },    # Very light green
	{ "val": 25.0,  "color": Color(0.65, 0.82, 0.55, 0.50) },    # Light green
	{ "val": 50.0,  "color": Color(0.88, 0.85, 0.40, 0.62) },    # Yellow
	{ "val": 75.0,  "color": Color(0.95, 0.72, 0.15, 0.70) },    # Light orange
	{ "val": 100.0, "color": Color(0.95, 0.55, 0.00, 0.75) },    # Orange
	{ "val": 150.0, "color": Color(0.90, 0.35, 0.00, 0.80) },    # Dark orange
	{ "val": 200.0, "color": Color(0.82, 0.15, 0.00, 0.83) },    # Red
	{ "val": 300.0, "color": Color(0.62, 0.00, 0.00, 0.85) },    # Dark red
	{ "val": 400.0, "color": Color(0.42, 0.00, 0.05, 0.87) },    # Maroon
	{ "val": 500.0, "color": Color(0.28, 0.08, 0.05, 0.90) },    # Very dark brown
]

## MUCAPE — same color ramp as SBCAPE
static var mucape_stops: Array[Dictionary] = [
	{ "val": 0.0,    "color": Color(0.95, 0.95, 0.95, 0.0) },
	{ "val": 100.0,  "color": Color(0.92, 0.92, 0.90, 0.40) },
	{ "val": 250.0,  "color": Color(0.93, 0.93, 0.80, 0.55) },
	{ "val": 500.0,  "color": Color(0.94, 0.91, 0.55, 0.70) },
	{ "val": 750.0,  "color": Color(0.91, 0.85, 0.22, 0.75) },
	{ "val": 1000.0, "color": Color(0.90, 0.73, 0.10, 0.78) },
	{ "val": 1500.0, "color": Color(0.97, 0.60, 0.00, 0.80) },
	{ "val": 2000.0, "color": Color(0.93, 0.40, 0.00, 0.82) },
	{ "val": 2500.0, "color": Color(0.82, 0.08, 0.00, 0.85) },
	{ "val": 3000.0, "color": Color(0.62, 0.00, 0.00, 0.85) },
	{ "val": 3500.0, "color": Color(0.42, 0.00, 0.05, 0.85) },
	{ "val": 4000.0, "color": Color(0.48, 0.12, 0.55, 0.85) },
	{ "val": 5000.0, "color": Color(0.73, 0.52, 0.82, 0.85) },
	{ "val": 6000.0, "color": Color(0.30, 0.72, 0.72, 0.85) },
	{ "val": 7000.0, "color": Color(0.05, 0.42, 0.42, 0.85) },
	{ "val": 8500.0, "color": Color(0.15, 0.02, 0.02, 0.90) },
]

## MUCIN — same color ramp as CINH
static var mucinh_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 10.0,  "color": Color(0.80, 0.88, 0.72, 0.35) },
	{ "val": 25.0,  "color": Color(0.65, 0.82, 0.55, 0.50) },
	{ "val": 50.0,  "color": Color(0.88, 0.85, 0.40, 0.62) },
	{ "val": 75.0,  "color": Color(0.95, 0.72, 0.15, 0.70) },
	{ "val": 100.0, "color": Color(0.95, 0.55, 0.00, 0.75) },
	{ "val": 150.0, "color": Color(0.90, 0.35, 0.00, 0.80) },
	{ "val": 200.0, "color": Color(0.82, 0.15, 0.00, 0.83) },
	{ "val": 300.0, "color": Color(0.62, 0.00, 0.00, 0.85) },
	{ "val": 400.0, "color": Color(0.42, 0.00, 0.05, 0.87) },
	{ "val": 500.0, "color": Color(0.28, 0.08, 0.05, 0.90) },
]

## Mid-level lapse rate (500-700mb) color ramp — °C/km
static var lapse_rate_ml_stops: Array[Dictionary] = [
	{ "val": 0.0,  "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 5.5,  "color": Color(0.90, 0.92, 0.95, 0.0) },   # Transparent below moist adiabatic
	{ "val": 6.0,  "color": Color(0.65, 0.78, 0.55, 0.35) },  # Light green
	{ "val": 6.5,  "color": Color(0.45, 0.72, 0.35, 0.55) },  # Green
	{ "val": 7.0,  "color": Color(0.82, 0.85, 0.20, 0.65) },  # Yellow-green
	{ "val": 7.5,  "color": Color(0.95, 0.80, 0.05, 0.72) },  # Yellow
	{ "val": 8.0,  "color": Color(0.98, 0.62, 0.00, 0.78) },  # Orange
	{ "val": 8.5,  "color": Color(0.95, 0.38, 0.00, 0.83) },  # Dark orange
	{ "val": 9.0,  "color": Color(0.88, 0.15, 0.00, 0.87) },  # Red
	{ "val": 9.5,  "color": Color(0.65, 0.00, 0.05, 0.90) },  # Dark red
	{ "val": 10.0, "color": Color(0.45, 0.00, 0.20, 0.92) },  # Maroon
	{ "val": 12.0, "color": Color(0.28, 0.05, 0.28, 0.95) },  # Purple
]

## Low-level lapse rate (Sfc-700mb) color ramp — °C/km
static var lapse_rate_ll_stops: Array[Dictionary] = [
	{ "val": 0.0,  "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 4.0,  "color": Color(0.90, 0.92, 0.95, 0.0) },   # Transparent below threshold
	{ "val": 5.0,  "color": Color(0.65, 0.78, 0.55, 0.35) },  # Light green
	{ "val": 5.5,  "color": Color(0.45, 0.72, 0.35, 0.55) },  # Green
	{ "val": 6.0,  "color": Color(0.82, 0.85, 0.20, 0.65) },  # Yellow-green
	{ "val": 6.5,  "color": Color(0.95, 0.80, 0.05, 0.72) },  # Yellow
	{ "val": 7.0,  "color": Color(0.98, 0.62, 0.00, 0.78) },  # Orange
	{ "val": 7.5,  "color": Color(0.95, 0.38, 0.00, 0.83) },  # Dark orange
	{ "val": 8.0,  "color": Color(0.88, 0.15, 0.00, 0.87) },  # Red
	{ "val": 8.5,  "color": Color(0.65, 0.00, 0.05, 0.90) },  # Dark red
	{ "val": 9.0,  "color": Color(0.45, 0.00, 0.20, 0.92) },  # Maroon
	{ "val": 10.0, "color": Color(0.28, 0.05, 0.28, 0.95) },  # Purple
]

static var bulk_shear_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.95, 0.95, 0.95, 0.0) },
	{ "val": 20.0,  "color": Color(0.92, 0.92, 0.95, 0.45) },
	{ "val": 25.0,  "color": Color(0.75, 0.75, 0.95, 0.60) },
	{ "val": 30.0,  "color": Color(0.58, 0.58, 0.95, 0.70) },
	{ "val": 35.0,  "color": Color(0.38, 0.42, 0.92, 0.75) },
	{ "val": 40.0,  "color": Color(0.22, 0.30, 0.88, 0.78) },
	{ "val": 45.0,  "color": Color(0.10, 0.20, 0.78, 0.80) },
	{ "val": 50.0,  "color": Color(0.05, 0.55, 0.78, 0.80) },
	{ "val": 55.0,  "color": Color(0.05, 0.68, 0.55, 0.80) },
	{ "val": 60.0,  "color": Color(0.10, 0.72, 0.28, 0.80) },
	{ "val": 65.0,  "color": Color(0.45, 0.78, 0.15, 0.80) },
	{ "val": 70.0,  "color": Color(0.78, 0.82, 0.08, 0.82) },
	{ "val": 75.0,  "color": Color(0.90, 0.78, 0.00, 0.82) },
	{ "val": 80.0,  "color": Color(0.97, 0.60, 0.00, 0.83) },
	{ "val": 85.0,  "color": Color(0.93, 0.38, 0.00, 0.84) },
	{ "val": 90.0,  "color": Color(0.85, 0.15, 0.00, 0.85) },
	{ "val": 95.0,  "color": Color(0.70, 0.05, 0.00, 0.85) },
	{ "val": 100.0, "color": Color(0.50, 0.00, 0.02, 0.85) },
	{ "val": 105.0, "color": Color(0.55, 0.00, 0.35, 0.85) },
	{ "val": 110.0, "color": Color(0.52, 0.10, 0.58, 0.85) },
	{ "val": 115.0, "color": Color(0.58, 0.30, 0.70, 0.85) },
	{ "val": 120.0, "color": Color(0.72, 0.50, 0.82, 0.85) },
	{ "val": 125.0, "color": Color(0.82, 0.70, 0.88, 0.85) },
	{ "val": 130.0, "color": Color(0.20, 0.60, 0.60, 0.85) },
	{ "val": 135.0, "color": Color(0.40, 0.18, 0.10, 0.88) },
	{ "val": 140.0, "color": Color(0.28, 0.08, 0.05, 0.90) },
]

static var dewpoint_stops: Array[Dictionary] = [
	{ "val": -40.0, "color": Color(0.35, 0.22, 0.12, 0.85) },
	{ "val": -30.0, "color": Color(0.45, 0.32, 0.18, 0.85) },
	{ "val": -20.0, "color": Color(0.55, 0.42, 0.28, 0.82) },
	{ "val": -10.0, "color": Color(0.65, 0.55, 0.40, 0.78) },
	{ "val": 0.0,   "color": Color(0.72, 0.68, 0.58, 0.72) },
	{ "val": 10.0,  "color": Color(0.78, 0.78, 0.70, 0.65) },
	{ "val": 20.0,  "color": Color(0.75, 0.82, 0.68, 0.65) },
	{ "val": 30.0,  "color": Color(0.62, 0.78, 0.52, 0.70) },
	{ "val": 35.0,  "color": Color(0.48, 0.72, 0.38, 0.75) },
	{ "val": 40.0,  "color": Color(0.30, 0.65, 0.28, 0.78) },
	{ "val": 45.0,  "color": Color(0.18, 0.55, 0.22, 0.80) },
	{ "val": 50.0,  "color": Color(0.08, 0.45, 0.18, 0.82) },
	{ "val": 55.0,  "color": Color(0.02, 0.35, 0.20, 0.85) },
	{ "val": 60.0,  "color": Color(0.05, 0.30, 0.35, 0.85) },
	{ "val": 65.0,  "color": Color(0.12, 0.28, 0.55, 0.85) },
	{ "val": 70.0,  "color": Color(0.30, 0.22, 0.65, 0.85) },
	{ "val": 75.0,  "color": Color(0.50, 0.25, 0.60, 0.85) },
	{ "val": 80.0,  "color": Color(0.62, 0.35, 0.55, 0.88) },
]

static var srh03_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },     # Transparent
	{ "val": 50.0,  "color": Color(0.55, 0.80, 0.55, 0.40) },    # Light green
	{ "val": 100.0, "color": Color(0.30, 0.75, 0.35, 0.58) },    # Green
	{ "val": 150.0, "color": Color(0.15, 0.68, 0.25, 0.65) },    # Dark green
	{ "val": 200.0, "color": Color(0.75, 0.82, 0.15, 0.70) },    # Yellow-green
	{ "val": 250.0, "color": Color(0.92, 0.85, 0.10, 0.75) },    # Yellow
	{ "val": 300.0, "color": Color(0.98, 0.68, 0.00, 0.78) },    # Orange
	{ "val": 400.0, "color": Color(0.95, 0.42, 0.00, 0.82) },    # Dark orange
	{ "val": 500.0, "color": Color(0.88, 0.15, 0.00, 0.85) },    # Red
	{ "val": 600.0, "color": Color(0.68, 0.00, 0.10, 0.87) },    # Dark red
	{ "val": 750.0, "color": Color(0.55, 0.00, 0.40, 0.88) },    # Magenta
	{ "val": 1000.0,"color": Color(0.40, 0.00, 0.65, 0.90) },    # Purple
]

static var wind_200mb_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 50.0,  "color": Color(0.72, 0.72, 0.92, 0.50) },
	{ "val": 55.0,  "color": Color(0.60, 0.62, 0.90, 0.58) },
	{ "val": 60.0,  "color": Color(0.45, 0.50, 0.88, 0.65) },
	{ "val": 65.0,  "color": Color(0.30, 0.40, 0.85, 0.70) },
	{ "val": 70.0,  "color": Color(0.15, 0.30, 0.80, 0.75) },
	{ "val": 75.0,  "color": Color(0.05, 0.45, 0.75, 0.78) },
	{ "val": 80.0,  "color": Color(0.05, 0.58, 0.62, 0.78) },
	{ "val": 85.0,  "color": Color(0.08, 0.65, 0.45, 0.80) },
	{ "val": 90.0,  "color": Color(0.15, 0.70, 0.28, 0.80) },
	{ "val": 95.0,  "color": Color(0.40, 0.75, 0.15, 0.80) },
	{ "val": 100.0, "color": Color(0.70, 0.80, 0.08, 0.82) },
	{ "val": 105.0, "color": Color(0.85, 0.78, 0.00, 0.82) },
	{ "val": 110.0, "color": Color(0.95, 0.65, 0.00, 0.83) },
	{ "val": 115.0, "color": Color(0.93, 0.48, 0.00, 0.84) },
	{ "val": 120.0, "color": Color(0.88, 0.30, 0.00, 0.85) },
	{ "val": 125.0, "color": Color(0.80, 0.15, 0.00, 0.85) },
	{ "val": 130.0, "color": Color(0.65, 0.05, 0.00, 0.85) },
	{ "val": 135.0, "color": Color(0.50, 0.00, 0.02, 0.85) },
	{ "val": 140.0, "color": Color(0.55, 0.00, 0.35, 0.85) },
	{ "val": 145.0, "color": Color(0.52, 0.10, 0.58, 0.85) },
	{ "val": 150.0, "color": Color(0.58, 0.30, 0.70, 0.85) },
	{ "val": 155.0, "color": Color(0.72, 0.50, 0.82, 0.85) },
	{ "val": 160.0, "color": Color(0.82, 0.70, 0.88, 0.85) },
	{ "val": 165.0, "color": Color(0.20, 0.60, 0.60, 0.85) },
	{ "val": 170.0, "color": Color(0.40, 0.18, 0.10, 0.88) },
	{ "val": 175.0, "color": Color(0.28, 0.08, 0.05, 0.90) },
]

static var wind_700mb_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 20.0,  "color": Color(0.85, 0.88, 0.95, 0.40) },
	{ "val": 25.0,  "color": Color(0.72, 0.78, 0.95, 0.55) },
	{ "val": 28.0,  "color": Color(0.52, 0.60, 0.90, 0.65) },
	{ "val": 30.0,  "color": Color(0.35, 0.42, 0.88, 0.72) },
	{ "val": 33.0,  "color": Color(0.20, 0.28, 0.82, 0.78) },
	{ "val": 35.0,  "color": Color(0.08, 0.35, 0.75, 0.78) },
	{ "val": 38.0,  "color": Color(0.05, 0.50, 0.68, 0.80) },
	{ "val": 40.0,  "color": Color(0.05, 0.60, 0.48, 0.80) },
	{ "val": 43.0,  "color": Color(0.10, 0.68, 0.30, 0.80) },
	{ "val": 45.0,  "color": Color(0.40, 0.75, 0.15, 0.80) },
	{ "val": 48.0,  "color": Color(0.72, 0.80, 0.08, 0.82) },
	{ "val": 50.0,  "color": Color(0.88, 0.75, 0.00, 0.82) },
	{ "val": 53.0,  "color": Color(0.95, 0.60, 0.00, 0.83) },
	{ "val": 55.0,  "color": Color(0.92, 0.42, 0.00, 0.84) },
	{ "val": 58.0,  "color": Color(0.85, 0.22, 0.00, 0.85) },
	{ "val": 60.0,  "color": Color(0.72, 0.08, 0.00, 0.85) },
	{ "val": 63.0,  "color": Color(0.55, 0.00, 0.02, 0.85) },
	{ "val": 65.0,  "color": Color(0.55, 0.00, 0.35, 0.85) },
	{ "val": 68.0,  "color": Color(0.52, 0.10, 0.58, 0.85) },
	{ "val": 70.0,  "color": Color(0.58, 0.30, 0.70, 0.85) },
	{ "val": 73.0,  "color": Color(0.72, 0.50, 0.82, 0.85) },
	{ "val": 75.0,  "color": Color(0.82, 0.70, 0.88, 0.85) },
	{ "val": 80.0,  "color": Color(0.20, 0.60, 0.60, 0.85) },
	{ "val": 83.0,  "color": Color(0.40, 0.18, 0.10, 0.88) },
	{ "val": 85.0,  "color": Color(0.28, 0.08, 0.05, 0.90) }
]

static var wind_925mb_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 20.0,  "color": Color(0.85, 0.88, 0.95, 0.40) },
	{ "val": 22.0,  "color": Color(0.72, 0.78, 0.95, 0.55) },
	{ "val": 24.0,  "color": Color(0.52, 0.60, 0.90, 0.65) },
	{ "val": 28.0,  "color": Color(0.35, 0.42, 0.88, 0.72) },
	{ "val": 30.0,  "color": Color(0.20, 0.28, 0.82, 0.78) },
	{ "val": 32.0,  "color": Color(0.08, 0.35, 0.75, 0.78) },
	{ "val": 34.0,  "color": Color(0.05, 0.50, 0.68, 0.80) },
	{ "val": 36.0,  "color": Color(0.05, 0.60, 0.48, 0.80) },
	{ "val": 38.0,  "color": Color(0.10, 0.68, 0.30, 0.80) },
	{ "val": 40.0,  "color": Color(0.40, 0.75, 0.15, 0.80) },
	{ "val": 42.0,  "color": Color(0.72, 0.80, 0.08, 0.82) },
	{ "val": 44.0,  "color": Color(0.88, 0.75, 0.00, 0.82) },
	{ "val": 46.0,  "color": Color(0.95, 0.60, 0.00, 0.83) },
	{ "val": 48.0,  "color": Color(0.92, 0.42, 0.00, 0.84) },
	{ "val": 50.0,  "color": Color(0.85, 0.22, 0.00, 0.85) },
	{ "val": 52.0,  "color": Color(0.72, 0.08, 0.00, 0.85) },
	{ "val": 54.0,  "color": Color(0.55, 0.00, 0.02, 0.85) },
	{ "val": 56.0,  "color": Color(0.55, 0.00, 0.35, 0.85) },
	{ "val": 58.0,  "color": Color(0.52, 0.10, 0.58, 0.85) },
	{ "val": 60.0,  "color": Color(0.58, 0.30, 0.70, 0.85) },
	{ "val": 62.0,  "color": Color(0.72, 0.50, 0.82, 0.85) },
	{ "val": 64.0,  "color": Color(0.82, 0.70, 0.88, 0.85) },
	{ "val": 66.0,  "color": Color(0.20, 0.60, 0.60, 0.85) },
	{ "val": 70.0,  "color": Color(0.40, 0.18, 0.10, 0.88) },
	{ "val": 75.0,  "color": Color(0.28, 0.08, 0.05, 0.90) },
]

static var wind_sfc_stops: Array[Dictionary] = [
	{ "val": 0.0,   "color": Color(0.90, 0.92, 0.95, 0.0) },
	{ "val": 5.0,   "color": Color(0.85, 0.88, 0.95, 0.40) },
	{ "val": 10.0,  "color": Color(0.72, 0.78, 0.95, 0.55) },
	{ "val": 12.0,  "color": Color(0.52, 0.60, 0.90, 0.65) },
	{ "val": 14.0,  "color": Color(0.35, 0.42, 0.88, 0.72) },
	{ "val": 16.0,  "color": Color(0.20, 0.28, 0.82, 0.78) },
	{ "val": 18.0,  "color": Color(0.08, 0.35, 0.75, 0.78) },
	{ "val": 20.0,  "color": Color(0.05, 0.50, 0.68, 0.80) },
	{ "val": 22.0,  "color": Color(0.05, 0.60, 0.48, 0.80) },
	{ "val": 24.0,  "color": Color(0.10, 0.68, 0.30, 0.80) },
	{ "val": 26.0,  "color": Color(0.40, 0.75, 0.15, 0.80) },
	{ "val": 28.0,  "color": Color(0.72, 0.80, 0.08, 0.82) },
	{ "val": 30.0,  "color": Color(0.88, 0.75, 0.00, 0.82) },
	{ "val": 32.0,  "color": Color(0.95, 0.60, 0.00, 0.83) },
	{ "val": 34.0,  "color": Color(0.92, 0.42, 0.00, 0.84) },
	{ "val": 36.0,  "color": Color(0.85, 0.22, 0.00, 0.85) },
	{ "val": 38.0,  "color": Color(0.72, 0.08, 0.00, 0.85) },
	{ "val": 40.0,  "color": Color(0.55, 0.00, 0.02, 0.85) },
	{ "val": 42.0,  "color": Color(0.55, 0.00, 0.35, 0.85) },
	{ "val": 44.0,  "color": Color(0.52, 0.10, 0.58, 0.85) },
	{ "val": 46.0,  "color": Color(0.58, 0.30, 0.70, 0.85) },
	{ "val": 48.0,  "color": Color(0.72, 0.50, 0.82, 0.85) },
	{ "val": 50.0,  "color": Color(0.82, 0.70, 0.88, 0.85) },
	{ "val": 55.0,  "color": Color(0.20, 0.60, 0.60, 0.85) },
	{ "val": 60.0,  "color": Color(0.40, 0.18, 0.10, 0.88) },
	{ "val": 65.0,  "color": Color(0.28, 0.08, 0.05, 0.90) },
]

static func color_from_ramp(val: float, stops: Array[Dictionary]) -> Color:
	if val <= stops[0]["val"]:
		return stops[0]["color"]
	if val >= stops[stops.size() - 1]["val"]:
		return stops[stops.size() - 1]["color"]
	for i in range(stops.size() - 1):
		var lo: Dictionary = stops[i]
		var hi: Dictionary = stops[i + 1]
		if val >= lo["val"] and val < hi["val"]:
			var t: float = (val - float(lo["val"])) / (float(hi["val"]) - float(lo["val"]))
			return (lo["color"] as Color).lerp(hi["color"] as Color, t)
	return stops[stops.size() - 1]["color"]

# ── Height/Pressure Field Generators ────────────────────────

## Build a height field from a list of features.
## Each feature is a Dictionary describing a specific atmospheric structure.
## See scenario_data.gd for the feature format.
##
##   mean_height   - base height value (dam for UA, mb for surface)
##   base_amp      - base amplitude for waves at this level
##   features      - array of feature dictionaries
##   lat_grad_mult - multiplier on the north-south background gradient
static func build_field_from_features(
	grid_w: int, grid_h: int,
	mean_value: float, base_amp: float,
	features: Array, lat_grad_mult: float = 1.8,
	shortwave_scale: float = 1.0
) -> AtmosphereData:
	var data := AtmosphereData.new(grid_w, grid_h)

	var y_center := (data.map_min.y + data.map_max.y) * 0.5
	var y_range := data.map_max.y - data.map_min.y
	var x_range := data.map_max.x - data.map_min.x

	# Background latitudinal gradient (per map-pixel)
	var lat_gradient := base_amp * lat_grad_mult / y_range

	# First pass: compute base height with longwave/shortwave contour displacements
	for gy in range(grid_h):
		for gx in range(grid_w):
			var fx := float(gx) / (grid_w - 1)
			var fy := float(gy) / (grid_h - 1)
			var map_x := data.map_min.x + fx * x_range
			var map_y := data.map_min.y + fy * y_range

			# Start with base latitudinal gradient
			var total_shift := 0.0

			# Apply wave features (they displace contours N/S)
			for feature in features:
				var ftype: String = feature["type"]
				if ftype == "longwave":
					var wnum: float = feature["wave_num"]
					var wamp: float = feature["amplitude"] * base_amp
					var wphase: float = feature["phase"]
					var wave_pixels := y_range * 0.35 * wamp / base_amp
					total_shift += sin((fx - wphase) * TAU * wnum) * wave_pixels

				elif ftype == "shortwave":
					var wnum: float = feature["wave_num"]
					var wamp: float = feature["amplitude"] * base_amp
					var wphase: float = feature["phase"]
					var lat_c: float = feature.get("lat_center", 0.5)
					var lat_s: float = feature.get("lat_spread", 0.3)
					# Shortwave only affects a latitude band
					var lat_dist := (fy - lat_c) / lat_s
					var lat_factor: float = exp(-lat_dist * lat_dist)
					var wave_pixels := y_range * 0.25 * wamp * shortwave_scale
					total_shift += sin((fx - wphase) * TAU * wnum) * wave_pixels * lat_factor

			var effective_y := map_y + total_shift
			var height := mean_value + (effective_y - y_center) * lat_gradient

			# Apply closed features (add/subtract height directly)
			for feature in features:
				var ftype: String = feature["type"]
				if ftype == "closed_low":
					var pos: Vector2 = feature["pos"]
					var depth: float = feature["depth"]
					var radius: float = feature["radius"]
					var dist := Vector2(map_x, map_y).distance_to(pos) / radius
					height -= depth * exp(-dist * dist)

				elif ftype == "closed_high":
					var pos: Vector2 = feature["pos"]
					var strength: float = feature["strength"]
					var radius: float = feature["radius"]
					var dist := Vector2(map_x, map_y).distance_to(pos) / radius
					height += strength * exp(-dist * dist)

			data.set_cell(gx, gy, height)

	# Set reasonable value bounds
	var max_dev := base_amp * 3.0
	data.value_min = mean_value - max_dev
	data.value_max = mean_value + max_dev

	return data

## Apply jet streak features by locally tightening the gradient.
## This is done as a post-process: steepen heights toward their gradient direction
## within the jet streak region.
static func apply_jet_streaks(data: AtmosphereData, features: Array) -> void:
	var has_streaks := false
	for feature in features:
		if (feature as Dictionary)["type"] == "jet_streak":
			has_streaks = true
			break
	if not has_streaks:
		return

	var gw := data.grid_width
	var gh := data.grid_height
	var x_range := data.map_max.x - data.map_min.x
	var y_range := data.map_max.y - data.map_min.y

	# Copy original heights
	var base_heights := PackedFloat32Array(data.values)

	for gy in range(gh):
		for gx in range(gw):
			var fx := float(gx) / (gw - 1)
			var fy := float(gy) / (gh - 1)
			var map_x := data.map_min.x + fx * x_range
			var map_y := data.map_min.y + fy * y_range
			var pos := Vector2(map_x, map_y)

			# Find total streak influence at this point
			var total_boost := 0.0
			for feature in features:
				var feat: Dictionary = feature
				if feat["type"] != "jet_streak":
					continue
				var streak_pos: Vector2 = feat["pos"]
				var radius: float = feat["radius"]
				var intensity: float = feat["intensity"]
				var dist := pos.distance_to(streak_pos) / radius
				total_boost += (intensity - 1.0) * exp(-dist * dist)

			if total_boost > 0.001:
				# Compute local N-S gradient from base heights
				var y_up := maxi(gy - 1, 0)
				var y_dn := mini(gy + 1, gh - 1)
				var dh_dy := (base_heights[y_dn * gw + gx] - base_heights[y_up * gw + gx]) * 0.5

				# Amplify the deviation from mean at this point
				# by scaling the N-S gradient contribution
				var current := data.values[gy * gw + gx]
				# Shift the point southward (toward warmer heights) proportionally
				# to the gradient, creating tighter packing on the cold side
				data.values[gy * gw + gx] = current - dh_dy * total_boost * 1.5

# ── Legacy wrappers for backward compat ─────────────────────

static func generate_height_field(
	grid_w: int, grid_h: int,
	mean_height: float, trough_amp: float,
	wave_phase: float, _noise_scale: float,
	_seed_val: int
) -> AtmosphereData:
	# Simple legacy wrapper — one longwave feature
	var features := [
		{ "type": "longwave", "wave_num": 1.5, "amplitude": 1.0, "phase": wave_phase }
	]
	return build_field_from_features(grid_w, grid_h, mean_height, trough_amp, features)

static func generate_surface_pressure(
	grid_w: int, grid_h: int,
	mean_pressure: float, low_center: Vector2,
	low_depth: float, low_radius: float,
	_noise_scale: float, _seed_val: int
) -> AtmosphereData:
	var features := [
		{ "type": "closed_low", "pos": low_center, "depth": low_depth, "radius": low_radius }
	]
	return build_field_from_features(grid_w, grid_h, mean_pressure, 3.0, features, 0.3)

# ── Wind Derived from Height/Pressure Fields ────────────────

## Derive a geostrophic wind field from a height or pressure field.
## Uses numerical gradient of the height field rotated 90° for geostrophic balance.
## In Northern Hemisphere, wind flows parallel to contours with low heights to the left.
##
##   height_data    - the height/pressure field to derive winds from
##   wind_scale     - converts height gradient to wind speed in knots
##   cross_isobar   - angle (degrees) winds cross toward low pressure (friction)
##                    0 = purely geostrophic (upper levels)
##                    15-20 = moderate friction (850/925mb)
##                    25-35 = strong friction (surface)
##   noise_scale    - adds small-scale turbulence to the wind field
##   noise_seed     - seed for turbulence noise
static func derive_wind_from_heights(
	height_data: AtmosphereData,
	wind_scale: float,
	cross_isobar: float = 0.0,
	noise_scale: float = 0.0,
	noise_seed: int = 0
) -> AtmosphereData:
	var gw := height_data.grid_width
	var gh := height_data.grid_height
	var data := AtmosphereData.new(gw, gh)
	data.init_vector()

	# Optional turbulence noise
	var turb: FastNoiseLite = null
	if noise_scale > 0.0:
		turb = FastNoiseLite.new()
		turb.seed = noise_seed
		turb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		turb.frequency = noise_scale

	var cross_rad := deg_to_rad(cross_isobar)

	for gy in range(gh):
		for gx in range(gw):
			# Compute height gradient using central differences
			var dh_dx: float
			var dh_dy: float

			if gx == 0:
				dh_dx = height_data.get_cell(1, gy) - height_data.get_cell(0, gy)
			elif gx == gw - 1:
				dh_dx = height_data.get_cell(gw - 1, gy) - height_data.get_cell(gw - 2, gy)
			else:
				dh_dx = (height_data.get_cell(gx + 1, gy) - height_data.get_cell(gx - 1, gy)) * 0.5

			if gy == 0:
				dh_dy = height_data.get_cell(gx, 1) - height_data.get_cell(gx, 0)
			elif gy == gh - 1:
				dh_dy = height_data.get_cell(gx, gh - 1) - height_data.get_cell(gx, gh - 2)
			else:
				dh_dy = (height_data.get_cell(gx, gy + 1) - height_data.get_cell(gx, gy - 1)) * 0.5

			# Geostrophic wind in map coordinates:
			# u = wind_scale * dh/dy  (height increasing southward → westerly wind)
			# v = -wind_scale * dh/dx (height increasing eastward → northerly wind)
			var u_geo := wind_scale * dh_dy
			var v_geo := -wind_scale * dh_dx

			# Apply cross-isobar angle (friction turns wind toward low pressure)
			# Rotate the geostrophic wind vector toward the negative gradient
			var u_final: float
			var v_final: float
			if cross_isobar > 0.0:
				var cos_a := cos(cross_rad)
				var sin_a := sin(cross_rad)
				# Rotate clockwise (toward low pressure in NH)
				u_final = u_geo * cos_a + v_geo * sin_a
				v_final = -u_geo * sin_a + v_geo * cos_a
			else:
				u_final = u_geo
				v_final = v_geo

			# Add turbulence
			if turb:
				var fx := float(gx) / (gw - 1)
				var fy := float(gy) / (gh - 1)
				var map_x := data.map_min.x + fx * (data.map_max.x - data.map_min.x)
				var map_y := data.map_min.y + fy * (data.map_max.y - data.map_min.y)
				var turb_u := turb.get_noise_2d(map_x, map_y) * 3.0
				var turb_v := turb.get_noise_2d(map_x + 500.0, map_y + 500.0) * 3.0
				u_final += turb_u
				v_final += turb_v

			var speed := sqrt(u_final * u_final + v_final * v_final)
			data.set_cell(gx, gy, speed)
			data.set_vector(gx, gy, u_final, v_final)

	data.value_max = 170.0
	return data

# ── Non-derived Parameter Generators ────────────────────────

static func generate_sbcape(
	grid_w: int, grid_h: int,
	warm_center: Vector2, warm_radius: float,
	peak_cape: float, noise_scale: float,
	seed_val: int
) -> AtmosphereData:
	var data := AtmosphereData.new(grid_w, grid_h)
	data.value_max = peak_cape
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_scale
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed_val + 42
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = noise_scale * 2.5
	for gy in range(grid_h):
		for gx in range(grid_w):
			var fx := float(gx) / (grid_w - 1)
			var fy := float(gy) / (grid_h - 1)
			var map_x := data.map_min.x + fx * (data.map_max.x - data.map_min.x)
			var map_y := data.map_min.y + fy * (data.map_max.y - data.map_min.y)
			var pos := Vector2(map_x, map_y)
			var dist := pos.distance_to(warm_center) / warm_radius
			var warm_factor := exp(-dist * dist * 1.5)
			var lat_bias := fy * 0.6 + 0.2
			var n1 := noise.get_noise_2d(map_x, map_y) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(map_x, map_y) * 0.3
			var cape_val := peak_cape * warm_factor * lat_bias * (n1 + 0.3) + n2 * 400.0
			cape_val = maxf(cape_val, 0.0)
			data.set_cell(gx, gy, cape_val)
	return data

static func generate_bulk_shear(
	grid_w: int, grid_h: int,
	jet_center: Vector2, jet_radius: float,
	peak_shear: float, base_dir_deg: float,
	dir_spread: float, noise_scale: float,
	seed_val: int
) -> AtmosphereData:
	var data := AtmosphereData.new(grid_w, grid_h)
	data.value_max = peak_shear
	data.init_vector()
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_scale
	var dir_noise := FastNoiseLite.new()
	dir_noise.seed = seed_val + 99
	dir_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dir_noise.frequency = noise_scale * 0.8
	var mag_noise := FastNoiseLite.new()
	mag_noise.seed = seed_val + 200
	mag_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mag_noise.frequency = noise_scale * 1.5
	for gy in range(grid_h):
		for gx in range(grid_w):
			var fx := float(gx) / (grid_w - 1)
			var fy := float(gy) / (grid_h - 1)
			var map_x := data.map_min.x + fx * (data.map_max.x - data.map_min.x)
			var map_y := data.map_min.y + fy * (data.map_max.y - data.map_min.y)
			var pos := Vector2(map_x, map_y)
			var dist := pos.distance_to(jet_center) / jet_radius
			var jet_factor := exp(-dist * dist * 2.0)
			var lat_factor := 1.0 - fy * 0.5
			var n := mag_noise.get_noise_2d(map_x, map_y) * 0.3 + 0.7
			var mag := peak_shear * jet_factor * lat_factor * n
			mag = maxf(mag, 0.0)
			var dir_offset := dir_noise.get_noise_2d(map_x, map_y) * dir_spread
			var dir_rad := deg_to_rad(base_dir_deg + dir_offset)
			var u := sin(dir_rad) * mag
			var v := -cos(dir_rad) * mag
			data.set_cell(gx, gy, mag)
			data.set_vector(gx, gy, u, v)
	return data

static func generate_dewpoint(
	grid_w: int, grid_h: int,
	moisture_center: Vector2, moisture_radius: float,
	peak_td: float, dry_td: float,
	noise_scale: float, seed_val: int
) -> AtmosphereData:
	var data := AtmosphereData.new(grid_w, grid_h)
	data.value_min = dry_td
	data.value_max = peak_td
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_scale
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed_val + 77
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = noise_scale * 2.0
	for gy in range(grid_h):
		for gx in range(grid_w):
			var fx := float(gx) / (grid_w - 1)
			var fy := float(gy) / (grid_h - 1)
			var map_x := data.map_min.x + fx * (data.map_max.x - data.map_min.x)
			var map_y := data.map_min.y + fy * (data.map_max.y - data.map_min.y)
			var pos := Vector2(map_x, map_y)
			var dist := pos.distance_to(moisture_center) / moisture_radius
			var moist_factor := exp(-dist * dist * 1.2)
			var lat_bias := fy * 0.5 + 0.3
			var lon_bias := fx * 0.3 + 0.5
			var n1 := noise.get_noise_2d(map_x, map_y) * 0.15
			var n2 := noise2.get_noise_2d(map_x, map_y) * 0.08
			var td := dry_td + (peak_td - dry_td) * moist_factor * lat_bias * lon_bias + n1 * 15.0 + n2 * 8.0
			td = clampf(td, dry_td, peak_td)
			data.set_cell(gx, gy, td)
	return data

static func generate_srh03(
	grid_w: int, grid_h: int,
	helicity_center: Vector2, helicity_radius: float,
	peak_srh: float, noise_scale: float,
	seed_val: int
) -> AtmosphereData:
	var data := AtmosphereData.new(grid_w, grid_h)
	data.value_max = peak_srh
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = noise_scale
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed_val + 55
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = noise_scale * 2.2
	for gy in range(grid_h):
		for gx in range(grid_w):
			var fx := float(gx) / (grid_w - 1)
			var fy := float(gy) / (grid_h - 1)
			var map_x := data.map_min.x + fx * (data.map_max.x - data.map_min.x)
			var map_y := data.map_min.y + fy * (data.map_max.y - data.map_min.y)
			var pos := Vector2(map_x, map_y)
			var dist := pos.distance_to(helicity_center) / helicity_radius
			var hel_factor := exp(-dist * dist * 1.8)
			var lat_bias := fy * 0.4 + 0.4
			var n1 := noise.get_noise_2d(map_x, map_y) * 0.3 + 0.7
			var n2 := noise2.get_noise_2d(map_x, map_y) * 0.15
			var srh := peak_srh * hel_factor * lat_bias * n1 + n2 * 80.0
			srh = maxf(srh, 0.0)
			data.set_cell(gx, gy, srh)
	return data
