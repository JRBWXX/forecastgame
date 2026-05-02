class_name GridFLoader

## Loads .gridf binary files produced by the Python preprocessor
## into AtmosphereData instances.
##
## File format (little-endian):
##   - magic: 4 bytes "GRDF"
##   - version: uint8
##   - has_vector: uint8
##   - grid_width: uint16
##   - grid_height: uint16
##   - value_min: float32
##   - value_max: float32
##   - values: float32 array (grid_width * grid_height)
##   - if has_vector:
##       - u_values: float32 array
##       - v_values: float32 array


## Load a .gridf file and return an AtmosphereData instance, or null on error.
static func load_file(path: String) -> AtmosphereData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GridFLoader: cannot open " + path)
		return null

	# Magic number
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "GRDF":
		push_error("GridFLoader: invalid magic in " + path + " (got '" + magic + "')")
		return null

	# Header
	f.big_endian = false
	var version := f.get_8()
	if version != 1:
		push_error("GridFLoader: unsupported version " + str(version))
		return null

	var has_vector := f.get_8() == 1
	var gw := f.get_16()
	var gh := f.get_16()
	var value_min := f.get_float()
	var value_max := f.get_float()

	# Create data instance
	var data := AtmosphereData.new(gw, gh)
	data.value_min = value_min
	data.value_max = value_max

	# Scalar values
	var n := gw * gh
	for i in range(n):
		data.values[i] = f.get_float()

	# Vector components if present
	if has_vector:
		data.init_vector()
		for i in range(n):
			data.u_values[i] = f.get_float()
		for i in range(n):
			data.v_values[i] = f.get_float()

	f.close()
	return data

## Load all fields for a real-event scenario from a directory.
## Returns a dictionary with the same structure as ScenarioGenerator.generate():
##   { "wind_data": Dictionary, "contour_data": Dictionary }
##
## Expected files in scenario_dir:
##   height_200MB.gridf, height_300MB.gridf, ..., height_925MB.gridf
##   pressure_SFC.gridf
##   wind_200MB.gridf, ..., wind_925MB.gridf, wind_SFC.gridf
##   dewpoint_SFC.gridf
##   shear_06.gridf
static func load_scenario(scenario_dir: String) -> Dictionary:
	var wind_data: Dictionary = {}
	var contour_data: Dictionary = {}

	var ua_levels := ["200MB", "300MB", "500MB", "700MB", "850MB", "925MB"]

	for level in ua_levels:
		var hgt := load_file(scenario_dir + "/height_" + level + ".gridf")
		if hgt:
			contour_data[level] = hgt
		var wind := load_file(scenario_dir + "/wind_" + level + ".gridf")
		if wind:
			wind_data[level] = wind

	# Surface
	var sfc_pres := load_file(scenario_dir + "/pressure_SFC.gridf")
	if sfc_pres:
		contour_data["SFC"] = sfc_pres
	var sfc_wind := load_file(scenario_dir + "/wind_SFC.gridf")
	if sfc_wind:
		wind_data["SFC"] = sfc_wind

	# Scalars
	var dewpoint := load_file(scenario_dir + "/dewpoint_SFC.gridf")
	if dewpoint:
		wind_data["SFTD"] = dewpoint

	var shear := load_file(scenario_dir + "/shear_06.gridf")
	if shear:
		wind_data["SHR06"] = shear

	# Derived Products
	var cape := load_file(scenario_dir + "/sbcape.gridf")
	if cape:
		wind_data["SBCAPE"] = cape
		
	var srh := load_file(scenario_dir + "/srh03.gridf")
	if srh:
		wind_data["SRH03"] = srh

	return {
		"wind_data": wind_data,
		"contour_data": contour_data,
	}
