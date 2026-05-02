class_name ScenarioData

## Scenario definitions. Two types:
##   - "real" scenarios load preprocessed reanalysis data from a directory
##   - "procedural" scenarios use the feature-based generator (legacy)
##
## Real scenarios can also have an optional "perturbation" dict to modify
## the loaded data (spatial shift, intensity scale, etc.) for hypothetical variations.

static func get_scenario(name: String) -> Dictionary:
	match name:
		"april_27_2011_12z":  return _april_27_2011_12z()
		"may_03_1999_18z":    return _may_03_1999_18z()
		_:                     return _april_27_2011_12z()

static func get_scenario_list() -> Array[Dictionary]:
	return [
		{ "id": "april_27_2011_12z", "name": "April 27, 2011 — 12Z",
		  "desc": "Historic Dixie Alley tornado outbreak. Real reanalysis data, 12Z analysis. Deep negatively-tilted closed low over the central US, powerful jet streak, extreme moisture surge into the warm sector." },
		{ "id": "may_03_1999_18z", "name": "May 3, 1999 — 18Z",
		  "desc": "Bridge Creek-Moore F5 outbreak. Classic southern Plains supercell setup with a powerful dryline and strong low-level jet."}
	]

# ── Real-Event Scenarios (load from disk) ───────────────────

static func _april_27_2011_12z() -> Dictionary:
	return {
		"name": "April 27, 2011 — 12Z",
		"type": "real",
		"data_path": "res://scenarios/april_27_2011_12z",
	}

static func _may_03_1999_18z() -> Dictionary:
	return {
		"name": "May 3, 1999 — 18Z",
		"type": "real",
		"data_path": "res://scenarios/may_03_1999_18z",
	}
