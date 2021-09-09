extends MeshInstance


var editor: EditorPlugin

var size := 1.0
var subdiv := 10


const GRID_SIZE := 100


func _init(e):
	editor = e
	update()
	create_material()


func create_material():
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.flags_vertex_lighting = true
	mat.albedo_color = Color(0.8, 0.8, 0.6, 0.8)
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
	
	var half_size = GRID_SIZE / 2
	for ix in GRID_SIZE:
		var pos = ix - half_size
		
		lines.append(Vector3((pos + 0.5) * size, 0.0, size * -half_size))
		colors.append(Color.yellow)
		lines.append(Vector3((pos + 0.5) * size, 0.0, size * half_size))
		colors.append(Color.yellow)
		
		lines.append(Vector3(size * -half_size, 0.0, (pos + 0.5) * size))
		colors.append(Color.yellow)
		lines.append(Vector3(size * half_size, 0.0, (pos + 0.5) * size))
		colors.append(Color.yellow)

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = lines
	arrays[ArrayMesh.ARRAY_COLOR] = colors
	
	var amesh = ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh = amesh


