extends PanelContainer
class_name ScenarioDrawer

## Collapsible left drawer for scenario selection.
## Hidden by default, slides in when the drawer button is pressed.

signal scenario_selected(scenario_id: String)

var _buttons: Dictionary = {}
var _active_id: String = ""
var _desc_label: Label
var _is_open := false

const DRAWER_WIDTH := 240.0


func _ready() -> void:
	_build_ui()
	# Start hidden (off-screen to the left)
	visible = false
	custom_minimum_size.x = DRAWER_WIDTH

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	panel_style.border_color = Color(0.25, 0.28, 0.35, 0.8)
	panel_style.border_width_right = 1
	panel_style.set_content_margin_all(12.0)
	add_theme_stylebox_override("panel", panel_style)


func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open


func set_active_scenario(scenario_id: String) -> void:
	_active_id = scenario_id
	_update_button_states()
	var scenarios := ScenarioData.get_scenario_list()
	for s in scenarios:
		if s["id"] == scenario_id:
			_desc_label.text = s["desc"]
			break


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "SCENARIOS"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	root.add_child(sep)

	var scenarios := ScenarioData.get_scenario_list()
	for scenario in scenarios:
		var btn := _make_button(scenario)
		root.add_child(btn)
		_buttons[scenario["id"]] = btn

	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", StyleBoxLine.new())
	root.add_child(sep2)

	_desc_label = Label.new()
	_desc_label.text = "Select a scenario"
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color(0.50, 0.53, 0.62))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size.x = DRAWER_WIDTH - 24.0
	root.add_child(_desc_label)

	# Perturbation hint
	var hint := Label.new()
	hint.text = "R — randomize\nO — reset original\nP — show changes"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.38, 0.40, 0.50))
	root.add_child(hint)


func _make_button(scenario: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = scenario["name"]

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18)
	normal.border_color = Color(0.28, 0.32, 0.42)
	normal.border_width_left = 3
	normal.set_content_margin_all(7.0)
	normal.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.18, 0.24)
	hover.border_color = Color(0.45, 0.55, 0.75)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.72, 0.75, 0.85))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var sid: String = scenario["id"]
	btn.pressed.connect(func() -> void:
		scenario_selected.emit(sid)
		toggle()
	)
	return btn


func _update_button_states() -> void:
	var accent := Color(0.45, 0.65, 0.92)
	for sid in _buttons:
		var btn: Button = _buttons[sid]
		if sid == _active_id:
			var active := StyleBoxFlat.new()
			active.bg_color = accent.darkened(0.72)
			active.border_color = accent
			active.border_width_left = 4
			active.set_content_margin_all(7.0)
			active.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", active)
			btn.add_theme_color_override("font_color", accent)
		else:
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color(0.12, 0.14, 0.18)
			normal.border_color = Color(0.28, 0.32, 0.42)
			normal.border_width_left = 3
			normal.set_content_margin_all(7.0)
			normal.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", normal)
			btn.add_theme_color_override("font_color", Color(0.72, 0.75, 0.85))
