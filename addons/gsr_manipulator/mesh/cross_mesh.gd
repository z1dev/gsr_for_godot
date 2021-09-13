extends MeshInstance


var editor: EditorPlugin


var size := 1.0
var subdiv := 10

func _init(e):
	editor = e
	update()
	create_material()


func create_material():
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	#mat.flags_vertex_lighting = true
	mat.distance_fade_mode = SpatialMaterial.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 135.5
	mat.distance_fade_max_distance = 0.0
	mat.vertex_color_use_as_albedo = true
	#mat.albedo_color = Color(0.8, 0.8, 0.6, 0.8)
	material_override = mat


func update():
	if mesh != null && size == editor.settings.grid_size && subdiv == editor.settings.grid_subdiv:
		return
	
	size = editor.settings.grid_size
	subdiv = editor.settings.grid_subdiv
	
	generate()


func generate():
	var lines = PoolVector3Array()
	var colors = PoolColorArray()
	
	var color = Color(0.8, 0.8, 0.4, 0.8)

	var pos = size / subdiv / 2.0
	lines.append(Vector3(-pos, 0.0, 0.0))
	colors.append(color)
	lines.append(Vector3(pos, 0.0, 0.0))
	colors.append(color)
	
	lines.append(Vector3(0.0, -pos, 0.0))
	colors.append(color)
	lines.append(Vector3(0.0, pos, 0.0))
	colors.append(color)

	lines.append(Vector3(0.0, 0.0, -pos))
	colors.append(color)
	lines.append(Vector3(0.0, 0.0, pos))
	colors.append(color)

	
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = lines
	arrays[ArrayMesh.ARRAY_COLOR] = colors
	
	var amesh = ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh = amesh


