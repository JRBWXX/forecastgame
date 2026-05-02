class_name ScenarioGenerator

## Generates all atmospheric data fields from a feature-based scenario definition.

const GRID_W := 80
const GRID_H := 45

const WIND_CONFIG: Dictionary = {
	"200MB": { "scale": 45.0, "cross": 0.0,  "turb": 0.0, "seed_offset": 10 },
	"300MB": { "scale": 48.0, "cross": 0.0,  "turb": 0.0, "seed_offset": 20 },
	"500MB": { "scale": 32.0, "cross": 0.0,  "turb": 0.0, "seed_offset": 30 },
	"700MB": { "scale": 18.0, "cross": 5.0,  "turb": 0.0, "seed_offset": 40 },
	"850MB": { "scale": 12.0, "cross": 15.0, "turb": 0.0, "seed_offset": 50 },
	"925MB": { "scale": 9.0,  "cross": 22.0, "turb": 0.0, "seed_offset": 60 },
	"SFC":   { "scale": 7.0,  "cross": 30.0, "turb": 0.0, "seed_offset": 70 },
}

const UA_LEVELS: Array[String] = ["200MB", "300MB", "500MB", "700MB", "850MB", "925MB"]

# Per-level height settings — mean height and amplitude per level
const HEIGHT_CONFIG: Dictionary = {
	"200MB": { "mean": 1176.0, "amp": 18.0 },
	"300MB": { "mean": 924.0,  "amp": 15.0 },
	"500MB": { "mean": 564.0,  "amp": 10.0 },
	"700MB": { "mean": 306.0,  "amp": 5.0  },
	"850MB": { "mean": 148.0,  "amp": 3.5  },
	"925MB": { "mean": 76.0,   "amp": 2.5  },
}

# Features tilt westward with height (higher levels = more westward phase shift).
# This is per-level phase offset applied to longwave/shortwave features.
const LEVEL_TILT: Dictionary = {
	"200MB": -0.08,
	"300MB": -0.05,
	"500MB": 0.0,
	"700MB": 0.04,
	"850MB": 0.06,
	"925MB": 0.07,
}

# Shortwave prominence per level — minimal aloft, full at low levels
const SHORTWAVE_SCALE: Dictionary = {
	"200MB": 0.0,
	"300MB": 0.15,
	"500MB": 0.5,
	"700MB": 1.0,
	"850MB": 1.0,
	"925MB": 1.0,
}


static func generate(scenario: Dictionary) -> Dictionary:
	var wind_data: Dictionary = {}
	var contour_data: Dictionary = {}

	var ua_features: Array = scenario.get("ua_features", [])
	var sfc_features: Array = scenario.get("sfc_features", [])
	var level_features: Dictionary = scenario.get("level_features", {})

	# ── 1. Generate UA height fields ────────────────────────
	for level in UA_LEVELS:
		var h_cfg: Dictionary = HEIGHT_CONFIG[level]

		# Merge shared features (with tilt) and level-specific features
		var combined_features := _apply_tilt(ua_features, LEVEL_TILT[level])
		if level_features.has(level):
			var extras: Array = level_features[level]
			for extra in extras:
				combined_features.append(extra)

		var sw_scale: float = SHORTWAVE_SCALE[level]

		var data := AtmosphereData.build_field_from_features(
			GRID_W, GRID_H, h_cfg["mean"], h_cfg["amp"], combined_features, 1.8, sw_scale
		)
		AtmosphereData.apply_jet_streaks(data, combined_features)

		contour_data[level] = data

	# ── 2. Generate surface pressure field ──────────────────
	var sfc_data := AtmosphereData.build_field_from_features(
		GRID_W, GRID_H, 1013.0, 3.5, sfc_features, 0.3
	)
	contour_data["SFC"] = sfc_data

	# ── 3. Derive winds from height fields ──────────────────
	for level in WIND_CONFIG:
		var w_cfg: Dictionary = WIND_CONFIG[level]
		wind_data[level] = AtmosphereData.derive_wind_from_heights(
			contour_data[level],
			w_cfg["scale"],
			w_cfg["cross"],
			w_cfg["turb"],
			w_cfg["seed_offset"]
		)

	# ── 4. Scalar parameter fields ──────────────────────────
	wind_data["SBCAPE"] = AtmosphereData.generate_sbcape(
		GRID_W, GRID_H,
		scenario["warm_center"], scenario["warm_radius"],
		scenario["peak_cape"], 0.008, 100
	)

	wind_data["SHR06"] = AtmosphereData.generate_bulk_shear(
		GRID_W, GRID_H,
		scenario["shear_center"], 500.0,
		scenario["peak_shear"], scenario["shear_dir"],
		40.0, 0.007, 200
	)

	wind_data["SFTD"] = AtmosphereData.generate_dewpoint(
		GRID_W, GRID_H,
		scenario["moisture_center"], scenario["moisture_radius"],
		scenario["peak_td"], scenario["dry_td"],
		0.007, 300
	)

	wind_data["SRH03"] = AtmosphereData.generate_srh03(
		GRID_W, GRID_H,
		scenario["helicity_center"], 450.0,
		scenario["peak_srh"], 0.008, 400
	)

	return {
		"wind_data": wind_data,
		"contour_data": contour_data,
	}

## Apply level tilt to wave features (longwaves and shortwaves get their phase shifted).
static func _apply_tilt(features: Array, tilt: float) -> Array:
	var tilted: Array = []
	for feature in features:
		var feat: Dictionary = (feature as Dictionary).duplicate()
		var ftype: String = feat["type"]
		if ftype == "longwave" or ftype == "shortwave":
			feat["phase"] = feat["phase"] + tilt
		tilted.append(feat)
	return tilted
