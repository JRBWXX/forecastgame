extends PanelContainer
class_name ScenarioPanel

## Left-side panel for selecting and loading weather scenarios.

signal scenario_selected(scenario_id: String)

var _buttons: Dictionary = {}
var _active_id: String = ""
var _desc_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.90)
	panel_style.set_content_margin_all(12.0)
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# Title
	var title := Label.new()
	title.text = "SCENARIOS"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	root.add_child(_make_separator())

	# Scenario buttons
	var scenarios := ScenarioData.get_scenario_list()
	for scenario in scenarios:
		var btn := _make_scenario_button(scenario)
		root.add_child(btn)
		_buttons[scenario["id"]] = btn

	root.add_child(_make_separator())

	# Description area
	_desc_label = Label.new()
	_desc_label.text = "Select a scenario to begin"
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size.x = 180.0
	root.add_child(_desc_label)

func set_active_scenario(scenario_id: String) -> void:
	_active_id = scenario_id
	_update_button_states()

	# Update description
	var scenarios := ScenarioData.get_scenario_list()
	for s in scenarios:
		if s["id"] == scenario_id:
			_desc_label.text = s["desc"]
			_desc_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
			break

func _make_scenario_button(scenario: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = "  " + scenario["name"]

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.16, 0.20)
	normal.border_color = Color(0.30, 0.35, 0.45)
	normal.border_width_left = 3
	normal.set_content_margin_all(8.0)
	normal.content_margin_left = 6.0
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.20, 0.26)
	hover.border_color = Color(0.45, 0.55, 0.75)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(0.55, 0.75, 0.95))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var sid: String = scenario["id"]
	btn.pressed.connect(_on_scenario_pressed.bind(sid))

	return btn

func _on_scenario_pressed(scenario_id: String) -> void:
	scenario_selected.emit(scenario_id)

func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	return sep

func _update_button_states() -> void:
	var accent := Color(0.45, 0.65, 0.90)
	for sid in _buttons:
		var btn: Button = _buttons[sid]
		if sid == _active_id:
			var active := StyleBoxFlat.new()
			active.bg_color = accent.darkened(0.7)
			active.border_color = accent
			active.border_width_left = 5
			active.set_content_margin_all(8.0)
			active.content_margin_left = 6.0
			active.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", active)
			btn.add_theme_color_override("font_color", accent)
		else:
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color(0.14, 0.16, 0.20)
			normal.border_color = Color(0.30, 0.35, 0.45)
			normal.border_width_left = 3
			normal.set_content_margin_all(8.0)
			normal.content_margin_left = 6.0
			normal.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", normal)
			btn.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
