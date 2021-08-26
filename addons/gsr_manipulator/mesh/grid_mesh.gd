extends MeshInstance


var editor: EditorPlugin

var size_xz := 1.0
var subd_xz := 10
var size_y := 1.0
var subd_y := 10


const GRID_SIZE := 20


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
	if mesh != null && (size_xz == editor.settings.grab_snap_size_x && subd_xz == editor.settings.grab_snap_subd_x &&
			((!editor.settings.use_y_grab_snap && size_xz == size_y && subd_xz == subd_y) ||
				(editor.settings.use_y_grab_snap && size_y == editor.settings.grab_snap_size_y &&
				subd_y == editor.settings.grab_snap_subd_y))):
		return
	
	size_xz = editor.settings.grab_snap_size_x
	subd_xz = editor.settings.grab_snap_subd_x
	if !editor.settings.use_y_grab_snap:
		size_y = size_xz
		subd_y = subd_xz
	else:
		size_y = editor.settings.grab_snap_size_y
		subd_y = editor.settings.grab_snap_subd_y
	
	generate()


func generate():
	var lines = PoolVector3Array()
	var colors = PoolColorArray()
	
	var half_size = GRID_SIZE / 2
	for ix in GRID_SIZE:
		var pos = ix - half_size
		
		lines.append(Vector3((pos + 0.5) * size_xz, 0.0, size_xz * -half_size))
		colors.append(Color.yellow)
		lines.append(Vector3((pos + 0.5) * size_xz, 0.0, size_xz * half_size))
		colors.append(Color.yellow)
		
		lines.append(Vector3(size_xz * -half_size, 0.0, (pos + 0.5) * size_xz))
		colors.append(Color.yellow)
		lines.append(Vector3(size_xz * half_size, 0.0, (pos + 0.5) * size_xz))
		colors.append(Color.yellow)

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = lines
	arrays[ArrayMesh.ARRAY_COLOR] = colors
	
	var amesh = ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh = amesh


