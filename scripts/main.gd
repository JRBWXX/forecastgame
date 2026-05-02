extends Node2D

## Main scene — wires together the map, camera, atmosphere, risk overlay, and HUD.

@onready var conus_map: CONUSMap = $CONUSMap
@onready var atmo_overlay: AtmosphereOverlay = $AtmosphereOverlay
@onready var wind_barbs: WindBarbOverlay = $WindBarbOverlay
@onready var contour_overlay: ContourOverlay = $ContourOverlay
@onready var risk_overlay: RiskOverlay = $RiskOverlay
@onready var hud: HUD = $HUD

var _risk_panel: RiskPanel
var _scenario_panel: ScenarioPanel

var _atmo_data: Dictionary = {}
var _contour_data: Dictionary = {}
var _current_scenario_id: String = ""

var _param_list: Array[String] = ["SBCAPE", "SHR06", "SFTD", "SRH03", "200MB", "300MB", "500MB", "700MB", "850MB", "925MB", "SFC"]
var _current_param_index: int = 0

var _base_wind_data: Dictionary = {}		# Unperturbed real data
var _base_contour_data: Dictionary = {}		# Unperturbed real data
var _current_perturbation: PerturbationSystem.PerturbationResult = null

const PARAM_UNITS: Dictionary = {
	"SBCAPE": " J/kg",
	"SHR06": " kt",
	"SFTD": " °F",
	"SRH03": " m²/s²",
	"200MB": " kt",
	"300MB": " kt",
	"500MB": " kt",
	"700MB": " kt",
	"850MB": " kt",
	"925MB": " kt",
	"SFC": " kt",
}

const CONTOUR_CONFIG: Dictionary = {
	"200MB": { "interval": 12.0, "unit": " dam" },
	"300MB": { "interval": 12.0, "unit": " dam" },
	"500MB": { "interval": 6.0,  "unit": " dam" },
	"700MB": { "interval": 3.0,  "unit": " dam" },
	"850MB": { "interval": 3.0,  "unit": " dam" },
	"925MB": { "interval": 3.0,  "unit": " dam" },
	"SFC":   { "interval": 4.0,  "unit": " mb" },
}

func _ready() -> void:
	conus_map.state_hovered.connect(_on_state_hovered)
	conus_map.state_clicked.connect(_on_state_clicked)

	# Risk panel (right side)
	_risk_panel = RiskPanel.new()
	_risk_panel.anchor_left = 1.0
	_risk_panel.anchor_right = 1.0
	_risk_panel.anchor_top = 0.0
	_risk_panel.anchor_bottom = 1.0
	_risk_panel.offset_left = -210.0
	_risk_panel.offset_top = 55.0
	_risk_panel.offset_bottom = -50.0
	hud.add_child(_risk_panel)

	_risk_panel.category_selected.connect(_on_category_selected)
	_risk_panel.clear_requested.connect(_on_clear_requested)
	_risk_panel.undo_requested.connect(_on_undo_requested)

	# Scenario panel (left side)
	_scenario_panel = ScenarioPanel.new()
	_scenario_panel.anchor_left = 0.0
	_scenario_panel.anchor_right = 0.0
	_scenario_panel.anchor_top = 0.0
	_scenario_panel.anchor_bottom = 1.0
	_scenario_panel.offset_right = 220.0
	_scenario_panel.offset_top = 55.0
	_scenario_panel.offset_bottom = -50.0
	hud.add_child(_scenario_panel)

	_scenario_panel.scenario_selected.connect(_on_scenario_selected)

	# Risk overlay signals
	risk_overlay.drawing_started.connect(_on_drawing_started)
	risk_overlay.drawing_finished.connect(_on_drawing_finished)
	risk_overlay.drawing_cancelled.connect(_on_drawing_cancelled)
	risk_overlay.vertex_placed.connect(_on_vertex_placed)
	risk_overlay.polygon_count_changed.connect(_on_polygon_count_changed)

	RenderingServer.set_default_clear_color(conus_map.ocean_color)

	# Load default scenario
	_load_scenario("april_27_2011_12z")

func _load_scenario(scenario_id: String) -> void:
	_current_scenario_id = scenario_id
	_scenario_panel.set_active_scenario(scenario_id)

	var scenario := ScenarioData.get_scenario(scenario_id)
	var scenario_type: String = scenario.get("type", "procedural")

	var result: Dictionary
	if scenario_type == "real":
		var data_path: String = scenario["data_path"]
		result = GridFLoader.load_scenario(data_path)
		if result["wind_data"].is_empty():
			push_error("Failed to load real scenario data from " + data_path)
			hud.update_info("ERROR: Could not load scenario data from " + data_path)
			return
	else:
		result = ScenarioGenerator.generate(scenario)

	_atmo_data = result["wind_data"]
	_contour_data = result["contour_data"]
	
	# Store clean base data for perturbation
	if scenario_type == "real":
		_base_wind_data = result["wind_data"]
		_base_contour_data = result["contour_data"]
		# Auto-apply a random perturbation on load
		_apply_perturbation(PerturbationSystem.random_seed())
		return # _apply_perturbation calls _switch_to_param
	
	# For procedural scenarios, no perturbations
	_base_wind_data = {}
	_base_contour_data = {}
	_current_perturbation = null

	# Reset to first parameter, but skip params that have no data loaded
	_current_param_index = _find_first_loaded_param()
	_switch_to_param(_current_param_index)

	var scenario_name: String = scenario["name"]
	hud.update_info("Loaded: " + scenario_name + "  —  [ / ] to switch params  |  Tab to toggle")

func _apply_perturbation(perturb_seed: int) -> void:
	if _base_wind_data.is_empty():
		return
	_current_perturbation = PerturbationSystem.apply(
		_base_wind_data, _base_contour_data, perturb_seed
	)
	_atmo_data = _current_perturbation.wind_data
	_contour_data = _current_perturbation.contour_data
	_current_param_index = _find_first_loaded_param()
	_switch_to_param(_current_param_index)
	var summary := _current_perturbation.get_summary()
	if summary == "No perturbations applied.":
		hud.update_info("Loaded (unperturbed)  —  [ / ] to switch  |  R to randomize")
	else:
		hud.update_info("R to randomize  |  [ / ] switch  |  Tab toggle")
		
func _show_perturbation_summary() -> void:
	if _current_perturbation == null:
		return
	var summary := _current_perturbation.get_summary()
	hud.update_info("Perturbation applied:\n" + summary)

func _find_first_loaded_param() -> int:
	for i in range(_param_list.size()):
		if _atmo_data.has(_param_list[i]):
			return i
	return 0

func _on_scenario_selected(scenario_id: String) -> void:
	if scenario_id != _current_scenario_id:
		_load_scenario(scenario_id)

func _switch_to_param(index: int) -> void:
	_current_param_index = index
	var param_name: String = _param_list[index]

	# Skip if this parameter isn't loaded for the current scenario
	if not _atmo_data.has(param_name):
		hud.update_info(param_name + " not available for this scenario  ([ / ] to switch)")
		atmo_overlay.set_overlay_visible(false)
		wind_barbs.clear()
		wind_barbs.visible = false
		contour_overlay.clear()
		contour_overlay.visible = false
		_set_data_overlay_active(false)
		return

	var data: AtmosphereData = _atmo_data[param_name]
	atmo_overlay.set_overlay_visible(true)
	atmo_overlay.set_data(data, param_name)
	_set_data_overlay_active(true)

	if data.has_vector:
		wind_barbs.set_data(data)
		wind_barbs.visible = true
	else:
		wind_barbs.clear()
		wind_barbs.visible = false

	if CONTOUR_CONFIG.has(param_name) and _contour_data.has(param_name):
		var cfg: Dictionary = CONTOUR_CONFIG[param_name]
		contour_overlay.set_data(_contour_data[param_name], cfg["interval"], cfg["unit"])
		contour_overlay.visible = true
	else:
		contour_overlay.clear()
		contour_overlay.visible = false

	hud.update_info(param_name + "  ([ / ] to switch  |  Tab to toggle)")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = (event as InputEventKey).keycode
		match key:
			KEY_TAB:
				var vis := not atmo_overlay.is_overlay_visible()
				atmo_overlay.set_overlay_visible(vis)
				wind_barbs.visible = vis and _atmo_data[_param_list[_current_param_index]].has_vector
				contour_overlay.visible = vis and CONTOUR_CONFIG.has(_param_list[_current_param_index])
				_set_data_overlay_active(vis)
				var state := "shown" if vis else "hidden"
				hud.update_info(_param_list[_current_param_index] + " overlay " + state + "  (Tab to toggle)")
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				_current_param_index = (_current_param_index + 1) % _param_list.size()
				_switch_to_param(_current_param_index)
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				_current_param_index = (_current_param_index - 1 + _param_list.size()) % _param_list.size()
				_switch_to_param(_current_param_index)
				get_viewport().set_input_as_handled()
			KEY_R:
				if not _base_wind_data.is_empty():
					_apply_perturbation(PerturbationSystem.random_seed())
					get_viewport().set_input_as_handled()
			KEY_P:
				_show_perturbation_summary()
				get_viewport().set_input_as_handled()
			KEY_O:
				if not _base_wind_data.is_empty():
					_atmo_data = PerturbationSystem._deep_copy_atmo_dict(_base_wind_data)
					_contour_data = PerturbationSystem._deep_copy_atmo_dict(_base_contour_data)
					_current_perturbation = null
					_current_param_index = _find_first_loaded_param()
					_switch_to_param(_current_param_index)
					hud.update_info("Scenario reset to original — R to radomize")
					get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if atmo_overlay.is_overlay_visible() and not risk_overlay.is_drawing():
		var mouse_pos := get_local_mouse_position()
		var val := atmo_overlay.sample_at(mouse_pos)
		var param_name: String = _param_list[_current_param_index]
		var state_name := _get_hovered_state_text()

		if val > 1.0 or param_name == "SFTD":
			var unit: String = PARAM_UNITS[param_name]
			hud.update_state_info(state_name + "    " + param_name + ": " + str(int(val)) + unit)
		else:
			hud.update_state_info(state_name)

func _get_hovered_state_text() -> String:
	var mouse_pos := conus_map.get_local_mouse_position()
	return conus_map._get_state_at(mouse_pos)

func _set_data_overlay_active(active: bool) -> void:
	conus_map.data_active = active
	conus_map.queue_redraw()

func _on_state_hovered(state_name: String) -> void:
	if not atmo_overlay.is_overlay_visible():
		hud.update_state_info(state_name)

func _on_state_clicked(state_name: String) -> void:
	hud.update_info("Selected: " + state_name)

func _on_category_selected(category: RiskData.Category) -> void:
	if risk_overlay.is_drawing() and risk_overlay.get_active_category() == category:
		risk_overlay.cancel_drawing()
	else:
		risk_overlay.begin_drawing(category)

func _on_clear_requested() -> void:
	risk_overlay.clear_all()
	hud.update_info("All risk polygons cleared")

func _on_undo_requested() -> void:
	risk_overlay.undo_last_polygon()
	hud.update_info("Last polygon removed")

func _on_drawing_started(category: RiskData.Category) -> void:
	_risk_panel.set_active_category(category)
	_set_drawing_mode(true)
	var label: String = RiskData.LABELS[category]
	hud.update_info("Drawing " + label + "  —  click to place vertices")

func _on_drawing_finished(category: RiskData.Category) -> void:
	_risk_panel.clear_active_category()
	_set_drawing_mode(false)
	var label: String = RiskData.LABELS[category]
	hud.update_info(label + " polygon committed  (" + str(risk_overlay.get_polygon_count()) + " total)")

func _on_drawing_cancelled() -> void:
	_risk_panel.clear_active_category()
	_set_drawing_mode(false)
	hud.update_info("Scroll to zoom  |  Middle-click drag to pan  |  1-6 to draw risk")

func _on_vertex_placed(count: int) -> void:
	_risk_panel.update_vertex_count(count)
	if count >= 3:
		hud.update_info("Click near first point or press Enter/Right-click to close")

func _on_polygon_count_changed(count: int) -> void:
	_risk_panel.update_polygon_count(count)

func _set_drawing_mode(active: bool) -> void:
	conus_map.input_enabled = not active
