extends Node2D
class_name ContourOverlay

## Draws contour lines (isohypses/isobars) from an AtmosphereData grid
## using the marching squares algorithm. Lines are labeled at intervals.

const LABEL_SPACING := 350.0      # Map pixels between labels along a contour
const MIN_SEGMENT_LEN := 8.0      # Skip very short segments

var _data: AtmosphereData
var _contour_interval: float = 6.0
var _contour_lines: Array = []     # Array of { value, segments }
var _line_color := Color(0.90, 0.92, 0.95, 0.65)
var _label_color := Color(0.90, 0.92, 0.95, 0.85)
var _line_width := 1.2
var _label_size := 11
var _unit_suffix := " dam"

func set_data(data: AtmosphereData, interval: float, unit: String = " dam") -> void:
	_data = data
	_contour_interval = interval
	_unit_suffix = unit
	_extract_contours()
	queue_redraw()

func clear() -> void:
	_data = null
	_contour_lines.clear()
	queue_redraw()

func set_line_color(color: Color) -> void:
	_line_color = color
	queue_redraw()

# ── Contour Extraction (Marching Squares) ───────────────────

func _extract_contours() -> void:
	_contour_lines.clear()
	if not _data:
		return

	# Find value range
	var vmin := INF
	var vmax := -INF
	for i in range(_data.values.size()):
		var v := _data.values[i]
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)

	# Generate contour values at the interval
	var first_contour := ceilf(vmin / _contour_interval) * _contour_interval
	var contour_val := first_contour
	while contour_val <= vmax:
		var segments := _march_squares(contour_val)
		if segments.size() > 0:
			var chains := _chain_segments(segments)
			_contour_lines.append({
				"value": contour_val,
				"chains": chains,
			})
		contour_val += _contour_interval

## Run marching squares for a single contour value.
## Returns an array of line segments [Vector2, Vector2].
func _march_squares(threshold: float) -> Array:
	var segments: Array = []
	var gw := _data.grid_width
	var gh := _data.grid_height

	for gy in range(gh - 1):
		for gx in range(gw - 1):
			# Four corners of the cell
			var v00 := _data.get_cell(gx, gy)
			var v10 := _data.get_cell(gx + 1, gy)
			var v01 := _data.get_cell(gx, gy + 1)
			var v11 := _data.get_cell(gx + 1, gy + 1)

			# Build case index (which corners are above threshold)
			var case_idx := 0
			if v00 >= threshold: case_idx |= 1
			if v10 >= threshold: case_idx |= 2
			if v01 >= threshold: case_idx |= 4
			if v11 >= threshold: case_idx |= 8

			# Skip empty/full cells
			if case_idx == 0 or case_idx == 15:
				continue

			# Interpolate edge crossings
			# Edge 0: top (v00 → v10)
			# Edge 1: right (v10 → v11)
			# Edge 2: bottom (v01 → v11)
			# Edge 3: left (v00 → v01)
			var e0 := _interp_edge(gx, gy, gx + 1, gy, v00, v10, threshold)
			var e1 := _interp_edge(gx + 1, gy, gx + 1, gy + 1, v10, v11, threshold)
			var e2 := _interp_edge(gx, gy + 1, gx + 1, gy + 1, v01, v11, threshold)
			var e3 := _interp_edge(gx, gy, gx, gy + 1, v00, v01, threshold)

			# Generate segments based on marching squares lookup
			match case_idx:
				1: segments.append([e0, e3])
				2: segments.append([e0, e1])
				3: segments.append([e3, e1])
				4: segments.append([e3, e2])
				5: segments.append([e0, e2])
				6:
					# Saddle point — use average to disambiguate
					var avg := (v00 + v10 + v01 + v11) * 0.25
					if avg >= threshold:
						segments.append([e0, e3])
						segments.append([e1, e2])
					else:
						segments.append([e0, e1])
						segments.append([e3, e2])
				7: segments.append([e1, e2])
				8: segments.append([e1, e2])
				9:
					# Saddle point
					var avg := (v00 + v10 + v01 + v11) * 0.25
					if avg >= threshold:
						segments.append([e0, e1])
						segments.append([e3, e2])
					else:
						segments.append([e0, e3])
						segments.append([e1, e2])
				10: segments.append([e0, e3])
				11: segments.append([e3, e2])
				12: segments.append([e3, e1])
				13: segments.append([e0, e1])
				14: segments.append([e0, e3])

	return segments

## Interpolate the crossing point along a grid edge.
func _interp_edge(gx0: int, gy0: int, gx1: int, gy1: int,
		v0: float, v1: float, threshold: float) -> Vector2:
	var t := 0.5
	if not is_equal_approx(v1, v0):
		t = (threshold - v0) / (v1 - v0)
		t = clampf(t, 0.0, 1.0)

	# Convert grid coords to map coords
	var map0 := _grid_to_map(gx0, gy0)
	var map1 := _grid_to_map(gx1, gy1)
	return map0.lerp(map1, t)

func _grid_to_map(gx: int, gy: int) -> Vector2:
	var fx := float(gx) / (_data.grid_width - 1)
	var fy := float(gy) / (_data.grid_height - 1)
	return Vector2(
		_data.map_min.x + fx * (_data.map_max.x - _data.map_min.x),
		_data.map_min.y + fy * (_data.map_max.y - _data.map_min.y)
	)

## Chain individual segments into connected polylines for smoother rendering.
func _chain_segments(segments: Array) -> Array:
	if segments.size() == 0:
		return []

	var chains: Array = []
	var used := PackedByteArray()
	used.resize(segments.size())
	var snap_dist := 2.0  # Grid-space snap tolerance

	for i in range(segments.size()):
		if used[i]:
			continue
		used[i] = 1

		var chain: PackedVector2Array = PackedVector2Array()
		chain.append(segments[i][0])
		chain.append(segments[i][1])

		# Try to extend chain forward and backward
		var changed := true
		while changed:
			changed = false
			for j in range(segments.size()):
				if used[j]:
					continue
				var s0: Vector2 = segments[j][0]
				var s1: Vector2 = segments[j][1]

				# Try to append to end
				if chain[chain.size() - 1].distance_to(s0) < snap_dist:
					chain.append(s1)
					used[j] = 1
					changed = true
				elif chain[chain.size() - 1].distance_to(s1) < snap_dist:
					chain.append(s0)
					used[j] = 1
					changed = true
				# Try to prepend to start
				elif chain[0].distance_to(s1) < snap_dist:
					chain.insert(0, s0)
					used[j] = 1
					changed = true
				elif chain[0].distance_to(s0) < snap_dist:
					chain.insert(0, s1)
					used[j] = 1
					changed = true

		if chain.size() >= 2:
			chains.append(chain)

	return chains

# ── Rendering ───────────────────────────────────────────────

func _draw() -> void:
	if _contour_lines.size() == 0:
		return

	var font := ThemeDB.fallback_font

	for contour in _contour_lines:
		var value: float = contour["value"]
		var chains: Array = contour["chains"]
		var label_text := str(int(value))

		for chain_raw in chains:
			var chain: PackedVector2Array = chain_raw as PackedVector2Array
			if chain.size() < 2:
				continue

			# Draw the contour line
			draw_polyline(chain, _line_color, _line_width, true)

			# Place labels along the chain at intervals
			var accumulated := 0.0
			# Start with an offset so labels aren't all at the beginning
			var next_label := LABEL_SPACING * 0.3

			for i in range(chain.size() - 1):
				var seg_len := chain[i].distance_to(chain[i + 1])
				accumulated += seg_len

				if accumulated >= next_label and seg_len > MIN_SEGMENT_LEN:
					# Place label at midpoint of this segment
					var mid: Vector2 = (chain[i] + chain[i + 1]) * 0.5
					var angle := (chain[i + 1] - chain[i]).angle()

					# Keep text readable (not upside down)
					if angle > PI * 0.5 or angle < -PI * 0.5:
						angle += PI

					# Draw background for readability
					var text_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, _label_size)
					var half_size: Vector2 = text_size * 0.5
					var bg_pos: Vector2 = mid - half_size - Vector2(3, 0)
					var bg_size: Vector2 = text_size + Vector2(6, 2)
					draw_rect(Rect2(bg_pos, bg_size), Color(0.06, 0.08, 0.12, 0.70))

					# Draw label
					var label_pos: Vector2 = mid - Vector2(half_size.x, -text_size.y * 0.3)
					draw_string(font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size, _label_color)

					next_label = accumulated + LABEL_SPACING
