extends CanvasLayer
class_name GameHUD

## Main HUD — thin top bar, compact toolbar, status strip, and color legend.
## The map fills the rest of the screen.

signal parameter_requested(param_name: String)
signal drawing_tool_requested(category: int)   # -1 = none
signal toggle_overlay_requested
signal submit_requested
signal scenario_drawer_requested

# ── Parameter groups for dropdown ──────────────────────────
const PARAM_GROUPS: Array[Dictionary] = [
	{
		"label": "Instability",
		"params": ["SBCAPE", "MLCAPE", "CINH", "MLLR", "LLLR"],
	},
	{
		"label": "Kinematics",
		"params": ["SHR06", "SHR03", "SRH03", "SRH01"],
	},
	{
		"label": "Moisture",
		"params": ["SFTD"],
	},
	{
		"label": "Upper Air",
		"params": ["200MB", "300MB", "500MB", "700MB", "850MB", "925MB", "SFC"],
	},
]

const PARAM_FULL_NAMES: Dictionary = {
	"SBCAPE": "CAPE - Surface-Based",
	"MLCAPE": "CAPE - Mixed Layer",
	"CINH":   "CINH - Surface-Based",
	"MLLR":   "Lapse Rate - 500-700mb",
	"LLLR":   "Lapse Rate - Sfc-700mb",
	"SHR06":  "Bulk Shear - Sfc-6km",
	"SHR03":  "Bulk Shear - Sfc-3km",
	"SRH03":  "SR Helicity - 0-3km",
	"SRH01":  "SR Helicity - 0-1km",
	"SFTD":   "Dewpoints - Surface",
	"200MB":  "200 mb Analysis",
	"300MB":  "300 mb Analysis",
	"500MB":  "500 mb Analysis",
	"700MB":  "700 mb Analysis",
	"850MB":  "850 mb Analysis",
	"925MB":  "925 mb Analysis",
	"SFC":    "MSL Pressure/Wind",
}

# Drawing tool entries: label, category (-1 = none/cursor)
const DRAW_TOOLS: Array[Dictionary] = [
	{ "label": "— No Tool —", "category": -1 },
	{ "label": "TSTM  General Thunder", "category": 0 },
	{ "label": "MRGL  Marginal",        "category": 1 },
	{ "label": "SLGT  Slight",          "category": 2 },
	{ "label": "ENH   Enhanced",        "category": 3 },
	{ "label": "MDT   Moderate",        "category": 4 },
	{ "label": "HIGH  High",            "category": 5 },
]

# ── Node refs ───────────────────────────────────────────────
@onready var _scenario_label: Label    = %ScenarioLabel
@onready var _time_label: Label        = %TimeLabel
@onready var _param_dropdown: OptionButton  = %ParamDropdown
@onready var _draw_dropdown: OptionButton   = %DrawDropdown
@onready var _overlay_btn: Button      = %OverlayBtn
@onready var _submit_btn: Button       = %SubmitBtn
@onready var _drawer_btn: Button       = %DrawerBtn
@onready var _status_left: Label       = %StatusLeft
@onready var _status_right: Label      = %StatusRight
@onready var _legend_bar: Control      = %LegendBar

func _ready() -> void:
	_build_param_dropdown()
	_build_draw_dropdown()
	_param_dropdown.item_selected.connect(_on_param_selected)
	_draw_dropdown.item_selected.connect(_on_draw_selected)
	_overlay_btn.pressed.connect(func() -> void: toggle_overlay_requested.emit())
	_submit_btn.pressed.connect(func() -> void: submit_requested.emit())
	_drawer_btn.pressed.connect(func() -> void: scenario_drawer_requested.emit())
	update_status_right("[ ] switch param  |  Tab overlay  |  R randomize  |  O reset")

# ── Public API ──────────────────────────────────────────────

func set_scenario_info(scenario_name: String, time_str: String) -> void:
	_scenario_label.text = scenario_name
	_time_label.text = time_str

func set_active_param(param_name: String) -> void:
	# Find and select this param in the dropdown
	for i in range(_param_dropdown.item_count):
		if _param_dropdown.get_item_metadata(i) == param_name:
			_param_dropdown.select(i)
			return

func set_active_draw_tool(category: int) -> void:
	for i in range(_draw_dropdown.item_count):
		if _draw_dropdown.get_item_metadata(i) == category:
			_draw_dropdown.select(i)
			return

func update_status_left(text: String) -> void:
	_status_left.text = text

func update_status_right(text: String) -> void:
	_status_right.text = text

func set_overlay_active(active: bool) -> void:
	_overlay_btn.text = "Overlay: ON" if active else "Overlay: OFF"
	var color := Color(0.45, 0.80, 0.55) if active else Color(0.55, 0.58, 0.65)
	_overlay_btn.add_theme_color_override("font_color", color)

func update_legend(stops: Array[Dictionary], unit: String) -> void:
	_legend_bar.set_stops(stops, unit)

# ── Dropdown builders ───────────────────────────────────────

func _build_param_dropdown() -> void:
	_param_dropdown.clear()
	for group in PARAM_GROUPS:
		# Add separator with group name
		_param_dropdown.add_separator(group["label"])
		for param in group["params"]:
			_param_dropdown.add_item(PARAM_FULL_NAMES.get(param, param))
			var idx := _param_dropdown.item_count - 1
			_param_dropdown.set_item_metadata(idx, param)

func _build_draw_dropdown() -> void:
	_draw_dropdown.clear()
	for tool in DRAW_TOOLS:
		_draw_dropdown.add_item(tool["label"])
		var idx := _draw_dropdown.item_count - 1
		_draw_dropdown.set_item_metadata(idx, tool["category"])

func _on_param_selected(idx: int) -> void:
	var meta = _param_dropdown.get_item_metadata(idx)
	if meta != null and meta is String:
		parameter_requested.emit(meta as String)


func _on_draw_selected(idx: int) -> void:
	var meta = _draw_dropdown.get_item_metadata(idx)
	if meta != null:
		drawing_tool_requested.emit(int(meta))
