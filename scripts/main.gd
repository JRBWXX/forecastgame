extends Node2D

## Main scene — wires map, overlays, new HUD, and scenario system.

@onready var conus_map: CONUSMap                = $CONUSMap
@onready var atmo_overlay: AtmosphereOverlay    = $AtmosphereOverlay
@onready var wind_barbs: WindBarbOverlay        = $WindBarbOverlay
@onready var contour_overlay: ContourOverlay    = $ContourOverlay
@onready var risk_overlay: RiskOverlay          = $RiskOverlay
@onready var hud: GameHUD                       = $HUD
@onready var scenario_drawer: ScenarioDrawer    = %ScenarioDrawer
@onready var risk_palette: RiskPalette          = %RiskPalette

# ── Scenario / data state ───────────────────────────────────
var _atmo_data: Dictionary = {}
var _contour_data: Dictionary = {}
var _base_wind_data: Dictionary = {}
var _base_contour_data: Dictionary = {}
var _current_scenario_id: String = ""
var _current_perturbation: PerturbationSystem.PerturbationResult = null

var _param_list: Array[String] = [
	"SBCAPE", "MLCAPE", "MUCAPE", "CINH", "MUCINH", "MLLR", "LLLR",
	"SHR06", "SHR03", "SRH03", "SRH01", "SFTD",
	"200MB", "300MB", "500MB", "700MB", "850MB", "925MB", "SFC"
]
var _current_param_index: int = 0

const PARAM_UNITS: Dictionary = {
	"SBCAPE": " J/kg", "MLCAPE": " J/kg", "MUCAPE": " J/kg", "CINH": " J/kg", "MUCINH": " J/kg",
	"MLLR": " °C/km", "LLLR": " °C/km",
	"SHR03":  " kt", "SHR06": " kt", "SFTD": " °F", 
	"SRH03": " m²/s²", "SRH01":  " m²/s²",
	"200MB": " kt", "300MB": " kt", "500MB": " kt",
	"700MB": " kt", "850MB": " kt", "925MB": " kt", "SFC": " kt",
}

const CONTOUR_CONFIG: Dictionary = {
	"200MB": { "interval": 6.0,  "unit": " dam" },
	"300MB": { "interval": 6.0,  "unit": " dam" },
	"500MB": { "interval": 3.0,  "unit": " dam" },
	"700MB": { "interval": 1.5,  "unit": " dam" },
	"850MB": { "interval": 1.5,  "unit": " dam" },
	"925MB": { "interval": 1.5,  "unit": " dam" },
	"SFC":   { "interval": 2.0,  "unit": " mb" },
}

const PARAM_RAMPS: Dictionary = {
	"SBCAPE": "sbcape_stops",
	"MLCAPE": "mlcape_stops",
	"MUCAPE": "mucape_stops",
	"CINH":   "cinh_stops",
	"MUCINH": "mucinh_stops",
	"MLLR":   "lapse_rate_ml_stops",
	"LLLR":   "lapse_rate_ll_stops",
	"SHR03":  "bulk_shear_stops",
	"SHR06":  "bulk_shear_stops",
	"SFTD":   "dewpoint_stops",
	"SRH01":  "srh03_stops",
	"SRH03":  "srh03_stops",
	"200MB":  "wind_200mb_stops",
	"300MB":  "wind_200mb_stops",
	"500MB":  "bulk_shear_stops",
	"700MB":  "wind_700mb_stops",
	"850MB":  "wind_700mb_stops",
	"925MB":  "wind_925mb_stops",
	"SFC":    "wind_sfc_stops",
}

func _ready() -> void:
	# Wire HUD signals
	hud.parameter_requested.connect(_on_parameter_requested)
	hud.drawing_tool_requested.connect(_on_drawing_tool_requested)
	hud.toggle_overlay_requested.connect(_on_toggle_overlay)
	hud.submit_requested.connect(_on_submit)
	hud.scenario_drawer_requested.connect(func() -> void: scenario_drawer.toggle())

	# Wire scenario drawer
	scenario_drawer.scenario_selected.connect(_on_scenario_selected)

	# Wire risk palette
	risk_palette.undo_polygon_requested.connect(func() -> void:
		risk_overlay.undo_last_polygon())
	risk_palette.clear_all_requested.connect(func() -> void:
		risk_overlay.clear_all()
		risk_palette.update_polygon_count(0))

	# Wire risk overlay
	risk_overlay.drawing_started.connect(_on_drawing_started)
	risk_overlay.drawing_finished.connect(_on_drawing_finished)
	risk_overlay.drawing_cancelled.connect(_on_drawing_cancelled)
	risk_overlay.vertex_placed.connect(func(c: int) -> void:
		risk_palette.update_vertex_count(c))
	risk_overlay.polygon_count_changed.connect(func(c: int) -> void:
		risk_palette.update_polygon_count(c))

	# Wire map hover
	conus_map.state_hovered.connect(_on_state_hovered)

	RenderingServer.set_default_clear_color(conus_map.ocean_color)

	_load_scenario("april_27_2011_12z")

# ── Scenario loading ────────────────────────────────────────

func _load_scenario(scenario_id: String) -> void:
	_current_scenario_id = scenario_id
	scenario_drawer.set_active_scenario(scenario_id)

	var scenario := ScenarioData.get_scenario(scenario_id)
	var scenario_type: String = scenario.get("type", "procedural")

	var result: Dictionary
	if scenario_type == "real":
		result = GridFLoader.load_scenario(scenario["data_path"])
		if result["wind_data"].is_empty():
			hud.update_status_left("ERROR: Could not load scenario data")
			return
		_base_wind_data = result["wind_data"]
		_base_contour_data = result["contour_data"]
		_apply_perturbation(PerturbationSystem.random_seed())
		return
	else:
		result = ScenarioGenerator.generate(scenario)
		_base_wind_data = {}
		_base_contour_data = {}
		_current_perturbation = null

	_atmo_data = result["wind_data"]
	_contour_data = result["contour_data"]
	_finish_scenario_load(scenario["name"])

func _finish_scenario_load(scenario_name: String) -> void:
	_current_param_index = _find_first_loaded_param()
	_switch_to_param(_current_param_index)
	hud.set_scenario_info(scenario_name, _get_scenario_time())
	hud.update_status_right("R randomize  |  O reset  |  P show changes")

func _get_scenario_time() -> String:
	var scenario := ScenarioData.get_scenario(_current_scenario_id)
	# Extract time from scenario id if possible
	var scenario_name: String = scenario.get("name", "")
	return scenario_name

# ── Perturbation ────────────────────────────────────────────

func _apply_perturbation(perturb_seed: int) -> void:
	if _base_wind_data.is_empty():
		return
	_current_perturbation = PerturbationSystem.apply(
		_base_wind_data, _base_contour_data, perturb_seed)
	_atmo_data = _current_perturbation.wind_data
	_contour_data = _current_perturbation.contour_data
	var scenario := ScenarioData.get_scenario(_current_scenario_id)
	_finish_scenario_load(scenario["name"])

# ── Parameter switching ─────────────────────────────────────

func _switch_to_param(index: int) -> void:
	_current_param_index = index
	var param_name: String = _param_list[index]

	hud.set_active_param(param_name)

	if not _atmo_data.has(param_name):
		hud.update_status_left(param_name + " — not available for this scenario")
		atmo_overlay.set_overlay_visible(false)
		wind_barbs.visible = false
		contour_overlay.visible = false
		_set_data_active(false)
		return

	var data: AtmosphereData = _atmo_data[param_name]
	atmo_overlay.set_overlay_visible(true)
	atmo_overlay.set_data(data, param_name)
	_set_data_active(true)

	# Wind barbs
	if data.has_vector:
		wind_barbs.set_data(data)
		wind_barbs.visible = true
	else:
		wind_barbs.clear()
		wind_barbs.visible = false

	# Contour lines
	if CONTOUR_CONFIG.has(param_name) and _contour_data.has(param_name):
		var cfg: Dictionary = CONTOUR_CONFIG[param_name]
		contour_overlay.set_data(_contour_data[param_name], cfg["interval"], cfg["unit"])
		contour_overlay.visible = true
	else:
		contour_overlay.clear()
		contour_overlay.visible = false

	# Update legend
	_update_legend(param_name)

func _update_legend(param_name: String) -> void:
	var ramp_name: String = PARAM_RAMPS.get(param_name, "")
	if ramp_name == "":
		return
	var unit: String = PARAM_UNITS.get(param_name, "")
	# Get the stops array from AtmosphereData by name
	var stops: Array[Dictionary] = _get_ramp_stops(ramp_name)
	if not stops.is_empty():
		hud.update_legend(stops, unit)

func _get_ramp_stops(ramp_name: String) -> Array[Dictionary]:
	match ramp_name:
		"sbcape_stops":        return AtmosphereData.sbcape_stops
		"mlcape_stops":        return AtmosphereData.mlcape_stops
		"mucape_stops":        return AtmosphereData.mucape_stops
		"cinh_stops":          return AtmosphereData.cinh_stops
		"mucinh_stops":        return AtmosphereData.mucinh_stops
		"lapse_rate_ml_stops": return AtmosphereData.lapse_rate_ml_stops
		"lapse_rate_ll_stops": return AtmosphereData.lapse_rate_ll_stops
		"bulk_shear_stops":    return AtmosphereData.bulk_shear_stops
		"dewpoint_stops":      return AtmosphereData.dewpoint_stops
		"srh03_stops":         return AtmosphereData.srh03_stops
		"wind_200mb_stops":    return AtmosphereData.wind_200mb_stops
		"wind_700mb_stops":    return AtmosphereData.wind_700mb_stops
		"wind_925mb_stops":    return AtmosphereData.wind_925mb_stops
		"wind_sfc_stops":      return AtmosphereData.wind_sfc_stops
	return []

# ── HUD signal handlers ─────────────────────────────────────

func _on_parameter_requested(param_name: String) -> void:
	var idx := _param_list.find(param_name)
	if idx >= 0:
		_switch_to_param(idx)

func _on_drawing_tool_requested(category: int) -> void:
	if category < 0:
		if risk_overlay.is_drawing():
			risk_overlay.cancel_drawing()
	else:
		var cat := category as RiskData.Category
		if risk_overlay.is_drawing() and risk_overlay.get_active_category() == cat:
			risk_overlay.cancel_drawing()
		else:
			risk_overlay.begin_drawing(cat)

func _on_toggle_overlay() -> void:
	var vis := not atmo_overlay.is_overlay_visible()
	atmo_overlay.set_overlay_visible(vis)
	var param_name: String = _param_list[_current_param_index]
	wind_barbs.visible = vis and _atmo_data.has(param_name) and _atmo_data[param_name].has_vector
	contour_overlay.visible = vis and CONTOUR_CONFIG.has(param_name)
	_set_data_active(vis)
	hud.set_overlay_active(vis)

func _on_submit() -> void:
	hud.update_status_left("Forecast submitted! (scoring system coming soon)")

func _on_scenario_selected(scenario_id: String) -> void:
	if scenario_id != _current_scenario_id:
		_load_scenario(scenario_id)

# ── Risk overlay handlers ───────────────────────────────────

func _on_drawing_started(category: RiskData.Category) -> void:
	risk_palette.show_drawing(category)
	conus_map.input_enabled = false
	hud.set_active_draw_tool(category)
	var label: String = RiskData.LABELS[category]
	hud.update_status_left("Drawing " + label + "  —  click to place vertices")

func _on_drawing_finished(category: RiskData.Category) -> void:
	risk_palette.hide_drawing()
	conus_map.input_enabled = true
	hud.set_active_draw_tool(-1)
	var label: String = RiskData.LABELS[category]
	hud.update_status_left(label + " polygon committed")

func _on_drawing_cancelled() -> void:
	risk_palette.hide_drawing()
	conus_map.input_enabled = true
	hud.set_active_draw_tool(-1)
	hud.update_status_left("")

func _on_state_hovered(state_name: String) -> void:
	if not atmo_overlay.is_overlay_visible() and not risk_overlay.is_drawing():
		hud.update_status_left(state_name)

# ── Process (cursor readout) ────────────────────────────────

func _process(_delta: float) -> void:
	if atmo_overlay.is_overlay_visible() and not risk_overlay.is_drawing():
		var mouse_pos := get_local_mouse_position()
		var val := atmo_overlay.sample_at(mouse_pos)
		var param_name: String = _param_list[_current_param_index]
		var state_name := conus_map._get_state_at(conus_map.get_local_mouse_position())

		if val > 1.0 or param_name == "SFTD":
			var unit: String = PARAM_UNITS.get(param_name, "")
			var text := param_name + ": " + str(int(val)) + unit
			if state_name != "":
				text = state_name + "    " + text
			hud.update_status_left(text)
		elif state_name != "":
			hud.update_status_left(state_name)

# ── Keyboard shortcuts ──────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return

	match ke.keycode:
		KEY_TAB:
			_on_toggle_overlay()
			get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:
			_cycle_param(1)
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT:
			_cycle_param(-1)
			get_viewport().set_input_as_handled()
		KEY_R:
			if not _base_wind_data.is_empty():
				_apply_perturbation(PerturbationSystem.random_seed())
			get_viewport().set_input_as_handled()
		KEY_O:
			if not _base_wind_data.is_empty():
				_atmo_data = PerturbationSystem._deep_copy_atmo_dict(_base_wind_data)
				_contour_data = PerturbationSystem._deep_copy_atmo_dict(_base_contour_data)
				_current_perturbation = null
				_switch_to_param(_current_param_index)
				hud.update_status_right("Reset to original  —  R to randomize")
			get_viewport().set_input_as_handled()
		KEY_P:
			if _current_perturbation != null:
				hud.update_status_left(_current_perturbation.get_summary())
			get_viewport().set_input_as_handled()
		_:
			# Number keys for risk drawing
			if RiskData.HOTKEYS.has(ke.keycode):
				var cat: RiskData.Category = RiskData.HOTKEYS[ke.keycode]
				_on_drawing_tool_requested(cat)
				get_viewport().set_input_as_handled()

func _cycle_param(direction: int) -> void:
	var count := _param_list.size()
	var new_idx := (_current_param_index + direction + count) % count
	# Skip unavailable params
	var attempts := 0
	while not _atmo_data.has(_param_list[new_idx]) and attempts < count:
		new_idx = (new_idx + direction + count) % count
		attempts += 1
	_switch_to_param(new_idx)

# ── Helpers ─────────────────────────────────────────────────

func _find_first_loaded_param() -> int:
	for i in range(_param_list.size()):
		if _atmo_data.has(_param_list[i]):
			return i
	return 0

func _set_data_active(active: bool) -> void:
	conus_map.data_active = active
	conus_map.queue_redraw()
	hud.set_overlay_active(active)
