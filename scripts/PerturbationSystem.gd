class_name PerturbationSystem

## Applies small, physically plausible perturbations to real-event scenario data.
##
## Perturbation types:
##   SPATIAL_SHIFT   — Shifts all UA fields and/or surface fields east/west/north/south
##   INTENSITY_SCALE — Scales the wind field speeds (stronger/weaker jet)
##   MOISTURE_SCALE  — Scales dewpoint anomalies (wetter/drier warm sector)
##   PRESSURE_SHIFT  — Deepens or weakens surface low by offsetting MSLP values
##
## All perturbations are bounded to stay physically plausible.
## A seed is stored so any scenario can be exactly reproduced.

# ── Perturbation bounds ────────────────────────────────────

## Maximum grid-cell shift for spatial perturbations.
## Game grid is 80x45 over CONUS. 1 cell ≈ 30-60 km. Max 3 cells ≈ 90-180 km.
const MAX_SPATIAL_SHIFT_CELLS := 12

## Wind speed scale range (fraction of original speed).
## 0.85 = 15% weaker, 1.15 = 15% stronger.
const WIND_SCALE_MIN := 0.50
const WIND_SCALE_MAX := 1.65

## Dewpoint anomaly scale range.
## Applied to the anomaly from a base value, not the absolute dewpoint.
const MOISTURE_SCALE_MIN := 0.60
const MOISTURE_SCALE_MAX := 1.60

## Surface pressure offset range (mb).
## Shifts the entire MSLP field up or down.
const PRESSURE_OFFSET_MIN := -8.0
const PRESSURE_OFFSET_MAX := 8.0

## Represents a single applied perturbation with human-readable description.
class AppliedPerturbation:
	var type: String
	var description: String
	var value: float

	func _init(t: String, d: String, v: float) -> void:
		type = t
		description = d
		value = v

## Result of applying perturbations to a scenario.
class PerturbationResult:
	var wind_data: Dictionary
	var contour_data: Dictionary
	var perturbations: Array[AppliedPerturbation]
	var perturb_seed: int

	func _init() -> void:
		wind_data = {}
		contour_data = {}
		perturbations = []
		perturb_seed = 0

	## Human-readable summary of all applied perturbations.
	func get_summary() -> String:
		if perturbations.is_empty():
			return "No perturbations applied."
		var lines: Array[String] = []
		for p in perturbations:
			lines.append("• " + p.description)
		return "\n".join(lines)

## Generate a random perturbation seed.
static func random_seed() -> int:
	return randi()

## Apply random perturbations to loaded scenario data.
##
##   wind_data    — from GridFLoader.load_scenario()["wind_data"]
##   contour_data — from GridFLoader.load_scenario()["contour_data"]
##   seed         — random seed (store this to reproduce the scenario)
##   config       — optional Dictionary to enable/disable specific perturbation types
##                  Default config enables all types with moderate strength.
static func apply(
	wind_data: Dictionary,
	contour_data: Dictionary,
	perturb_seed: int,
	config: Dictionary = {}
) -> PerturbationResult:
	var result := PerturbationResult.new()
	result.perturb_seed = perturb_seed

	var rng := RandomNumberGenerator.new()
	rng.seed = perturb_seed

	# Deep-copy the data so we don't modify the originals
	result.wind_data = _deep_copy_atmo_dict(wind_data)
	result.contour_data = _deep_copy_atmo_dict(contour_data)

	var enable_spatial: bool = config.get("spatial", true)
	var enable_wind: bool = config.get("wind_scale", true)
	var enable_moisture: bool = config.get("moisture", true)
	var enable_pressure: bool = config.get("pressure", true)

	# ── 1. Spatial shift ─────────────────────────────────
	if enable_spatial:
		var shift_x := rng.randi_range(-MAX_SPATIAL_SHIFT_CELLS, MAX_SPATIAL_SHIFT_CELLS)
		var shift_y := rng.randi_range(-1, 1)  # Less N/S shift than E/W

		if shift_x != 0 or shift_y != 0:
			# Shift all UA levels and surface together — physically consistent
			var all_keys: Array = []
			for k in result.wind_data:
				all_keys.append(k)
			for k in result.contour_data:
				if not all_keys.has(k):
					all_keys.append(k)

			for key in all_keys:
				if result.wind_data.has(key):
					_shift_field(result.wind_data[key], shift_x, shift_y)
				if result.contour_data.has(key):
					_shift_field(result.contour_data[key], shift_x, shift_y)

			# Human-readable description
			var dir_x := ""
			var dir_y := ""
			if shift_x > 0:
				dir_x = str(shift_x * 175) + " km east"
			elif shift_x < 0:
				dir_x = str(-shift_x * 175) + " km west"
			if shift_y > 0:
				dir_y = str(shift_y * 175) + " km south"
			elif shift_y < 0:
				dir_y = str(-shift_y * 175) + " km north"

			var parts: Array[String] = []
			if dir_x != "":
				parts.append(dir_x)
			if dir_y != "":
				parts.append(dir_y)
			var dir_str := ", ".join(parts)

			result.perturbations.append(AppliedPerturbation.new(
				"spatial_shift",
				"Pattern shifted " + dir_str,
				float(shift_x)
			))

	# ── 2. Wind intensity scale ───────────────────────────
	if enable_wind:
		var scale := rng.randf_range(WIND_SCALE_MIN, WIND_SCALE_MAX)

		# Only scale if the change is meaningful (>3%)
		if absf(scale - 1.0) > 0.03:
			var ua_levels := ["200MB", "300MB", "500MB", "700MB", "850MB", "925MB"]
			for level in ua_levels:
				if result.wind_data.has(level):
					_scale_wind_speed(result.wind_data[level], scale)

			var pct := int(round(absf(scale - 1.0) * 100.0))
			var dir := "stronger" if scale > 1.0 else "weaker"
			result.perturbations.append(AppliedPerturbation.new(
				"wind_scale",
				"Upper-level winds " + str(pct) + "% " + dir,
				scale
			))

	# ── 3. Moisture perturbation ──────────────────────────
	if enable_moisture and result.wind_data.has("SFTD"):
		var scale := rng.randf_range(MOISTURE_SCALE_MIN, MOISTURE_SCALE_MAX)

		if absf(scale - 1.0) > 0.03:
			_scale_dewpoint_anomaly(result.wind_data["SFTD"], scale)

			var pct := int(round(absf(scale - 1.0) * 100.0))
			var dir := "richer" if scale > 1.0 else "drier"
			result.perturbations.append(AppliedPerturbation.new(
				"moisture_scale",
				"Warm sector moisture " + str(pct) + "% " + dir,
				scale
			))

	# ── 4. Surface pressure shift ─────────────────────────
	if enable_pressure and result.contour_data.has("SFC"):
		var offset := rng.randf_range(PRESSURE_OFFSET_MIN, PRESSURE_OFFSET_MAX)

		if absf(offset) > 0.5:
			_offset_field(result.contour_data["SFC"], offset)

			var dir := "deeper" if offset < 0.0 else "weaker"
			var mb_str := str(snappedf(absf(offset), 0.5))
			result.perturbations.append(AppliedPerturbation.new(
				"pressure_shift",
				"Surface low " + str(mb_str) + " mb " + dir,
				offset
			))

	return result

# ── Field manipulation helpers ──────────────────────────────

## Shift an AtmosphereData grid by dx, dy cells (rolls the array).
## Fills edges with the nearest valid value to avoid wrapping artifacts.
static func _shift_field(data: AtmosphereData, dx: int, dy: int) -> void:
	var gw := data.grid_width
	var gh := data.grid_height
	var n := gw * gh

	# Shift scalar values
	data.values = _roll_grid(data.values, gw, gh, dx, dy)

	# Shift vector components if present
	if data.has_vector:
		data.u_values = _roll_grid(data.u_values, gw, gh, dx, dy)
		data.v_values = _roll_grid(data.v_values, gw, gh, dx, dy)
		# Recompute speed
		for i in range(n):
			var u := data.u_values[i]
			var v := data.v_values[i]
			data.values[i] = sqrt(u * u + v * v)

## Roll a 1D array that represents a 2D grid by (dx, dy) cells.
## Instead of wrapping, clamps to edge values.
static func _roll_grid(
	arr: PackedFloat32Array,
	gw: int, gh: int,
	dx: int, dy: int
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(gw * gh)

	for gy in range(gh):
		for gx in range(gw):
			# Source position (clamped — no wrap)
			var src_x := clampi(gx - dx, 0, gw - 1)
			var src_y := clampi(gy - dy, 0, gh - 1)
			out[gy * gw + gx] = arr[src_y * gw + src_x]

	return out

## Scale wind speed by a multiplier, keeping direction unchanged.
static func _scale_wind_speed(data: AtmosphereData, scale: float) -> void:
	var n := data.grid_width * data.grid_height
	for i in range(n):
		data.values[i] *= scale
	if data.has_vector:
		for i in range(n):
			data.u_values[i] *= scale
			data.v_values[i] *= scale

## Scale dewpoint anomaly relative to a reference temperature.
## Preserves the background and amplifies or dampens the moist region.
static func _scale_dewpoint_anomaly(data: AtmosphereData, scale: float) -> void:
	# Compute mean dewpoint as background reference
	var sum := 0.0
	var n := data.grid_width * data.grid_height
	for i in range(n):
		sum += data.values[i]
	var mean := sum / float(n)

	# Scale the anomaly from the mean
	for i in range(n):
		var anomaly := data.values[i] - mean
		data.values[i] = mean + anomaly * scale

## Add a constant offset to all values in a field.
static func _offset_field(data: AtmosphereData, offset: float) -> void:
	var n := data.grid_width * data.grid_height
	for i in range(n):
		data.values[i] += offset

## Deep copy a dictionary of AtmosphereData instances.
static func _deep_copy_atmo_dict(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		var src: AtmosphereData = source[key]
		var copy := AtmosphereData.new(src.grid_width, src.grid_height)
		copy.value_min = src.value_min
		copy.value_max = src.value_max
		copy.values = PackedFloat32Array(src.values)
		if src.has_vector:
			copy.init_vector()
			copy.u_values = PackedFloat32Array(src.u_values)
			copy.v_values = PackedFloat32Array(src.v_values)
		out[key] = copy
	return out
