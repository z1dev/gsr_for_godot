#    Copyright 2021 Sólyom Zoltán
#
#    This file is part of Grab-Scale-Rotate for Godot
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

tool
extends MeshInstance

var Generator = preload("./mesh_generator.gd")

var editor: EditorPlugin


func _init(e):
	editor = e
	update()
	create_material()


func create_material():
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.flags_fixed_size = true
	mat.flags_no_depth_test = true
	mat.flags_do_not_receive_shadows = true
	mat.distance_fade_mode = SpatialMaterial.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 80
	mat.distance_fade_max_distance = 0.0
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	mat.params_depth_draw_mode = SpatialMaterial.DEPTH_DRAW_DISABLED


func update():
	if mesh != null:
		return
	
	generate()


func generate():
	var verts = []
	var colors = PoolColorArray()

	var xcolor = Color(0.6, 0.1, 0.1, 1)
	var ycolor = Color(0.1, 0.6, 0.1, 1)
	var zcolor = Color(0.1, 0.1, 0.7, 1)
	var siz = 0.1
	var width = siz * 0.024
	var box_siz = siz * 0.1
	
	Generator.add_block(verts, Vector3(-siz, -width, -width), siz * 2, width * 2, width * 2)
	Generator.add_block(verts, Vector3(siz, -box_siz, -box_siz), box_siz * 2, box_siz * 2, box_siz * 2)
	while colors.size() < verts.size():
		colors.append(xcolor)
		
	Generator.add_block(verts, Vector3(-width, -siz, -width), width * 2, siz * 2, width * 2)
	Generator.add_block(verts, Vector3(-box_siz, siz, -box_siz), box_siz * 2, box_siz * 2, box_siz * 2)
	while colors.size() < verts.size():
		colors.append(ycolor)

	Generator.add_block(verts, Vector3(-width, -width, -siz), width * 2, width * 2, siz * 2)
	Generator.add_block(verts, Vector3(-box_siz, -box_siz, siz), box_siz * 2, box_siz * 2, box_siz * 2)
	while colors.size() < verts.size():
		colors.append(zcolor)
	
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = verts
	arrays[ArrayMesh.ARRAY_COLOR] = colors

	var amesh = ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = amesh

