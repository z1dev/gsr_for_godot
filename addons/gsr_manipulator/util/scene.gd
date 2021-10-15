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
extends Object


# Distance in pixels around mouse position for finding meshes
const CLICK_MARGIN = 5

const POINT_MESH_CLICK_SIZE = 35


class DistanceOrderSorter:
	var distances
	
	func _init(dist):
		distances = dist
		
	func sort(a, b):
		return distances[a][0] < distances[b][0]


class FoundOrderSorter:
	var node_order
	var found

	func _init(o, f):
		node_order = o
		found = f
		
	func sort(a, b):
		var adist = found[a]
		var bdist = found[b]
		if adist == bdist:
			return node_order[a] < node_order[b]
		return adist < bdist



static func clear_selection(plugin: EditorPlugin):
	var ei := plugin.get_editor_interface()
	ei.get_selection().clear()
	ei.inspect_object(null)


static func is_node_selected(plugin: EditorPlugin, node: Node):
	var ei = plugin.get_editor_interface()
	var es = ei.get_selection()
	var sel = es.get_selected_nodes()
	return sel.find(node) != -1


static func set_selected(plugin: EditorPlugin, node: Node, select: bool):
	var ei := plugin.get_editor_interface()
	var es = ei.get_selection()
	var sel = es.get_selected_nodes()
	var ix = sel.find(node)
	if select:
		if ix != -1:
			return
		es.add_node(node)
		ei.inspect_object(node)
	else:
		if ix == -1:
			return
		var nextsel = null
		if ix < sel.size() - 1:
			nextsel = sel[ix + 1]
		elif ix > 0:
			nextsel = sel[ix - 1]
		es.remove_node(node)
		
		ei.inspect_object(nextsel)


static func get_absolute_path(plugin: EditorPlugin, node: Node):
	return plugin.get_editor_interface().get_edited_scene_root().get_path_to(node)


static func instance_from_path(plugin: EditorPlugin, path: String):
	return plugin.get_editor_interface().get_edited_scene_root().get_node(path)


enum { MOUSE_SELECT_FRONT_FACING_TRIANGLES = 1,
		MOUSE_SELECT_BACK_FACING_TRIANGLES = 2,
		MOUSE_SELECT_COLLISION_SHAPE = 4,
		MOUSE_SELECT_LIGHT = 8,
		MOUSE_SELECT_CAMERA = 16,
		MOUSE_SELECT_RAYCAST = 32,
		
		MOUSE_SELECT_RESET = 64 }

# Return a node at mousepos owned by the scene root. To return the node that's coming after another
# at the position, pass it in after_node.
static func mouse_select_spatial(plugin: EditorPlugin, camera: Camera, mousepos: Vector2, excluded_nodes, flags: int = 0, after_node = null):
	var scene_root = plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return null
		
	var check_front_tri = (flags & MOUSE_SELECT_FRONT_FACING_TRIANGLES) != 0
	var check_back_tri = (flags & MOUSE_SELECT_BACK_FACING_TRIANGLES) != 0
	var check_coll = (flags & MOUSE_SELECT_COLLISION_SHAPE) != 0
	var check_light = (flags & MOUSE_SELECT_LIGHT) != 0
	var check_cam = (flags & MOUSE_SELECT_CAMERA) != 0
	var check_ray = (flags & MOUSE_SELECT_RAYCAST) != 0
	
	# All scenes owned by the scene root.
	var scenes = get_scene_nodes(scene_root)
	
	var selectables = []
	# Find all mesh instance objects owned by the scenes in `scenes`.
	# Meshes will contain a pair of the scenes and an array of mesh instances belonging to them.
	for s in scenes:
		var arr = get_selectable_children(scene_root, s, flags, excluded_nodes)
		if arr == null || arr.empty():
			continue
		selectables.append([s, arr])
	
	if selectables.empty():
		return null
	
	var camera_plane := Plane(camera_ray_origin(camera, Vector2(100, 100)), camera_ray_origin(camera, Vector2(100, 0)),
			camera_ray_origin(camera, Vector2(0, 0))) if camera.projection != camera.PROJECTION_PERSPECTIVE else Plane(
				camera.project_position(Vector2(10, 10), camera.near + 0.00001), camera.project_position(Vector2(10, 0), camera.near + 0.00001),
				camera.project_position(Vector2(0, 0), camera.near + 0.00001))
	
	# Filter the meshes array to only hold those meshes that could have been clicked. Their aabb
	# projected on the camera contains mousepos.
	var tmp = selectables
	selectables = []
				
	var after_node_index = -1
	for pair in tmp:
		var scene_pair = null
		for s in pair[1]:
			if aabb_has_point(camera, camera_plane, mousepos, s):
				if scene_pair == null:
					scene_pair = [pair[0], [s]]
					if after_node == scene_pair[0]:
						after_node_index = selectables.size()
					selectables.append(scene_pair)
				else:
					scene_pair[1].append(s)

	# Find the closest and furthest point of the aabb of each mesh from the camera plane.
	var distances = []
	
	# Pairs of [mesh instance index, mesh index] in mesh values.
	var selpos = []
	for ix in selectables.size():
		var arr = selectables[ix][1] 
		for iy in arr.size():
			distances.append(aabb_distances(camera, camera_plane, arr[iy]))
			selpos.append([ix, iy])

	# Ordering of distances from camera plane.
	var order = range(distances.size())
	order.sort_custom(DistanceOrderSorter.new(distances), "sort")
	
	# Meshes under mousepos with their nearest distance
	var found = {}

	# Find the distance to after_node first, to know what comes after
	var after_node_dist = null
	if after_node_index != -1:
		for o in order:
			var pos = selpos[o]
			if pos[0] != after_node_index:
				continue
			if after_node_dist != null && distances[o][0] > after_node_dist:
				continue
			after_node_dist = nmin(after_node_dist, obj_hit_distance(camera, camera_plane, mousepos, selectables[pos[0]][1][pos[1]], check_front_tri, check_back_tri))
		if after_node_dist != null:
			found[after_node_index] = after_node_dist
		
	# A unique value of node owner, used for sorting. Same as the node's index when looping
	# through the order list.
	var node_order = {}

	# Index of node closest to the camera.
	var close_node = null
	# Distance of a node found closest to the camera.
	var close_dist = null
	
	# Distance of node closest to the camera but at or after after_node.
	var after_dist = null
	# Fill `found` with scenes and their nearest distance to the camera.
	for o in order:
		var pos = selpos[o]
		if !node_order.has(pos[0]):
			node_order[pos[0]] = node_order.size()
		
		if pos[0] == after_node_index:
			continue
		
		var dist = null
		# Find the closest mesh, independent of whether an after_node exists or not.
		if close_dist == null || distances[o][0] <= close_dist:
			dist = nmin(found.get(pos[0]), obj_hit_distance(camera, camera_plane, mousepos, selectables[pos[0]][1][pos[1]], check_front_tri, check_back_tri))
			if dist == null:
				continue
			found[pos[0]] = dist
			if close_dist == null || dist < close_dist:
				close_dist = dist
				close_node = pos[0]
		
		# Filling the found list with nodes that are near or after the after_node if it exists.
		# To make sure every node is considered that might come after the after_node, the after_dist
		# is set to the distance of the closest node that's further away than after_node. The rest,
		# that might be very close to after_node are all checked but don't change after_dist.
		if after_node_dist != null:
			if distances[o][1] >= after_node_dist && (after_dist == null || distances[o][0] <= after_dist):
				var fdist = found.get(pos[0])
				if fdist != null && fdist < after_node_dist:
					continue
				if dist == null:
					dist = nmin(fdist, obj_hit_distance(camera, camera_plane, mousepos, selectables[pos[0]][1][pos[1]], check_front_tri, check_back_tri))
					if dist == null:
						continue
				found[pos[0]] = dist
				if distances[o][0] > after_node_dist && (after_dist == null || dist < after_dist):
					after_dist = dist
					
	if close_node == null:
		if after_node_dist != null:
			return after_node
		return null
	
	if after_node_dist == null || ((flags & MOUSE_SELECT_RESET) != 0 && close_node != after_node_index):
		return selectables[close_node][0]
	
	# The found list has all nodes and their distances near after_node. To find the one coming
	# after after_node, an ordered index is created.
	
	order = found.keys()
	order.sort_custom(FoundOrderSorter.new(node_order, found), "sort")
	
	var pos = order.find(after_node_index)
	if pos == order.size() - 1 || pos == -1:
		return selectables[close_node][0]
	return selectables[order[pos + 1]][0]


static func unproject(camera: Camera, world_point: Vector3) -> Vector2:
	var shrink = 1
	var p = camera.get_parent()
	if p is Viewport:
		p = p.get_parent()
		if p is ViewportContainer:
			shrink = (p as ViewportContainer).stretch_shrink
	return camera.unproject_position(world_point) * shrink


static func camera_ray_origin(camera: Camera, screen_point: Vector2) -> Vector3:
	var shrink = 1
	var p = camera.get_parent()
	if p is Viewport:
		p = p.get_parent()
		if p is ViewportContainer:
			shrink = (p as ViewportContainer).stretch_shrink
	return camera.project_ray_origin(screen_point / shrink)


static func camera_ray_normal(camera: Camera, screen_point: Vector2) -> Vector3:
	var shrink = 1
	var p = camera.get_parent()
	if p is Viewport:
		p = p.get_parent()
		if p is ViewportContainer:
			shrink = (p as ViewportContainer).stretch_shrink
	return camera.project_ray_normal(screen_point / shrink)


# Returns an array of Spatial nodes that are owned by the passed scene.
static func get_scene_nodes(scene_root):
	var arr = [scene_root]
	var pos = 0
	
	var result = []
	if scene_root is Spatial:
		if !scene_root.visible:
			return []
		result.append(scene_root)
	
	while pos < arr.size():
		for c in arr[pos].get_children():
			if c.get_owner() != scene_root:
				continue
			if c is Spatial:
				if c.visible:
					result.append(c)
					arr.append(c)
			else:
				arr.append(c)
		pos += 1
	return result


# Returns an array of objects selectable by the plugin, whose owner is scene.
static func get_selectable_children(scene_root: Node, scene: Spatial, flags: int, excluded_nodes):
	var arr = [scene]
	var pos = 0
	
	var result = []
	if __is_selectable_scene(scene, flags):
		result.append(scene)
	
	while pos < arr.size():
		for c in arr[pos].get_children():
			if (excluded_nodes != null && c in excluded_nodes) || c.get_owner() == scene_root:
				continue
			if __is_selectable_scene(c, flags):
				result.append(c)
			arr.append(c)
		pos += 1
	return result


#MOUSE_SELECT_FRONT_FACING_TRIANGLES = 1,
#		MOUSE_SELECT_BACK_FACING_TRIANGLES = 2,
#		MOUSE_SELECT_COLLISION_SHAPE = 4,
#		MOUSE_SELECT_LIGHT = 8,
#		MOUSE_SELECT_CAMERA = 16,
#		MOUSE_SELECT_RAYCAST = 32,
static func __is_selectable_scene(s: Node, flags: int):
	return (((((flags & MOUSE_SELECT_FRONT_FACING_TRIANGLES) || (flags & MOUSE_SELECT_BACK_FACING_TRIANGLES))) && (s is MeshInstance && s.mesh != null)) ||
			((flags & MOUSE_SELECT_COLLISION_SHAPE) && s is CollisionShape && s.shape != null) || ((flags & MOUSE_SELECT_LIGHT) && s is Light) ||
			((flags & MOUSE_SELECT_CAMERA) && s is Camera) || ((flags & MOUSE_SELECT_RAYCAST) && s is RayCast))


# Returns true if projecting the aabb onto the camera's view plane contains the position.
static func aabb_has_point(camera: Camera, camera_plane: Plane, pos: Vector2, obj):
	var aabb: AABB
	if obj is MeshInstance:
		aabb = obj.get_aabb()
	elif obj is CollisionShape:
		var mesh = obj.shape.get_debug_mesh()
		aabb = mesh.get_aabb()
	elif obj is Light || obj is Camera:
		if camera.is_position_behind(obj.global_transform.origin):
			return false
		return pos.distance_to(camera.unproject_position(obj.global_transform.origin)) < POINT_MESH_CLICK_SIZE
	elif obj is RayCast:
		var pt1 = obj.global_transform.origin
		var pt2 = obj.to_global(obj.cast_to)
		
		var b1 = camera_plane.distance_to(pt1) < 0
		var b2 = camera_plane.distance_to(pt2) < 0
		if b1 && b2:
			return false
		
		pt1 = camera.unproject_position(camera_plane.intersects_segment(pt1, pt2)) if b1 else camera.unproject_position(pt1)
		pt2 = camera.unproject_position(camera_plane.intersects_segment(pt1, pt2)) if b2 else camera.unproject_position(pt2)
		var minpos = Vector2(min(pt1.x, pt2.x), min(pt1.y, pt2.y))
		var maxpos = Vector2(max(pt1.x, pt2.x), max(pt1.y, pt2.y))
		return Rect2(minpos - Vector2(CLICK_MARGIN, CLICK_MARGIN),
				maxpos - minpos + Vector2(CLICK_MARGIN, CLICK_MARGIN) * 2).has_point(pos)
	
	var pt1 = aabb.position
	var pt2 = aabb.end
	var points = [pt1, pt2, Vector3(pt1.x, pt1.y, pt2.z), Vector3(pt1.x, pt2.y, pt1.z),
			Vector3(pt2.x, pt1.y, pt1.z), Vector3(pt2.x, pt2.y, pt1.z),
			Vector3(pt2.x, pt1.y, pt2.z), Vector3(pt1.x, pt2.y, pt2.z)]
	for ix in points.size():
		points[ix] = obj.to_global(points[ix])
		
	var pointarray = [[0, 2], [0, 3], [0, 4], [1, 5], [1, 6], [1, 7], [2, 6], [2, 7], [3, 5], [3, 7], [4, 5], [4, 6]]
	
	var minpos = null
	var maxpos = null
	
	for ix in pointarray.size():
		var pair = pointarray[ix]
		pt1 = points[pair[0]]
		pt2 = points[pair[1]]
		var b1 = camera_plane.distance_to(pt1) < 0
		var b2 = camera_plane.distance_to(pt2) < 0
		if b1 && b2:
			continue
		
		if b1:
			pt1 = camera_plane.intersects_segment(pt1, pt2)
		elif b2:
			pt2 = camera_plane.intersects_segment(pt1, pt2)
	
		var p = camera.unproject_position(pt1)
		if minpos == null:
			minpos = p
			maxpos = p
		else:
			minpos = Vector2(min(minpos.x, p.x), min(minpos.y, p.y))
			maxpos = Vector2(max(maxpos.x, p.x), max(maxpos.y, p.y))
		p = camera.unproject_position(pt2)
		minpos = Vector2(min(minpos.x, p.x), min(minpos.y, p.y))
		maxpos = Vector2(max(maxpos.x, p.x), max(maxpos.y, p.y))
	
	if minpos == null:
		return false
	return Rect2(minpos - Vector2(CLICK_MARGIN, CLICK_MARGIN),
			maxpos - minpos + Vector2(CLICK_MARGIN, CLICK_MARGIN) * 2).has_point(pos)


static func aabb_distances(camera: Camera, camera_plane, obj):
	var aabb: AABB
	if obj is MeshInstance:
		aabb = obj.get_aabb()
	elif obj is CollisionShape:
		var mesh = obj.shape.get_debug_mesh()
		aabb = mesh.get_aabb()
	elif obj is Light || obj is Camera:
		var pos = camera_plane.distance_to(obj.global_transform.origin)
		return [pos - 0.001, pos + 0.001]
	elif obj is RayCast:
		var pt1 = obj.global_transform.origin
		var pt2 = obj.to_global(obj.cast_to)
		
		var b1 = camera_plane.distance_to(pt1) < 0
		var b2 = camera_plane.distance_to(pt2) < 0
		
		if b1:
			pt1 = camera_plane.intersects_segment(pt1, pt2)
		elif b2:
			pt2 = camera_plane.intersects_segment(pt1, pt2)
		var d1 = camera_plane.distance_to(pt1)
		var d2 = camera_plane.distance_to(pt2)
		return [min(d1, d2), max(d1, d2)]
		
	var near = null
	var far = null
	for ix in 8:
		var pt: Vector3 = obj.to_global(aabb.get_endpoint(ix))
		var dist = camera_plane.distance_to(pt)
		if near == null || near > dist:
			near = dist
		if far == null || far < dist:
			far = dist
	return [near, far]


# Returns the distance from 2d camera position projected onto mesh. Uses CLICK_MARGIN for more
# lenient check.
static func obj_hit_distance(camera: Camera, camera_plane: Plane, pos: Vector2, obj, front: bool, back: bool):
	var mesh: Mesh
	
	if obj is MeshInstance:
		mesh = obj.mesh
	elif obj is CollisionShape:
		mesh = obj.shape.get_debug_mesh()
	elif obj is Light || obj is Camera:
		return camera_plane.distance_to(obj.global_transform.origin)
	elif obj is RayCast:
		var v1 = obj.global_transform.origin
		var v2 = obj.to_global(obj.cast_to)
		var cv1 = camera.unproject_position(v1)
		var cv2 = camera.unproject_position(v2)
		return point_line_closer_distance(camera, camera_plane, pos, cv1, cv2, v1, v2, true)
		
	if mesh == null:
		return null
	if mesh.get_surface_count() == 0:
		return null
	
	var pos3d = camera_ray_origin(camera, pos)
	var norm3d = camera_ray_normal(camera, pos)
	
	var dist = null
	for ix in mesh.get_surface_count():
		var arr = mesh.surface_get_arrays(ix)
		if arr.size() < ArrayMesh.ARRAY_VERTEX + 1:
			continue
		if (arr[ArrayMesh.ARRAY_VERTEX] == null || arr[ArrayMesh.ARRAY_VERTEX].size() == 0 ||
				(!(arr[ArrayMesh.ARRAY_VERTEX] is PoolVector3Array) && !(arr[ArrayMesh.ARRAY_VERTEX] is Array))):
			continue
		var type = Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			type = mesh.surface_get_primitive_type(ix)
		var has_index = arr.size() > ArrayMesh.ARRAY_INDEX && arr[ArrayMesh.ARRAY_INDEX] != null
		var vertex_count = arr[ArrayMesh.ARRAY_INDEX].size() if has_index else arr[ArrayMesh.ARRAY_VERTEX].size()
		
		var camera_vertexes = []
		var mesh_vertexes = []
		for v in arr[ArrayMesh.ARRAY_VERTEX]:
			var global = obj.to_global(v)
			mesh_vertexes.append(global)
			camera_vertexes.append(unproject(camera, global))
			
		match type:
			Mesh.PRIMITIVE_POINTS:
				var iy = 0
				var pt
				var vix
				while iy < vertex_count:
					if has_index:
						vix = arr[ArrayMesh.ARRAY_INDEX][iy]
					else:
						vix = iy
					dist = nmin(dist, point_closer_distance(camera, pos, camera_vertexes[vix], mesh_vertexes[vix]) )
					iy += 1
			Mesh.PRIMITIVE_LINES, Mesh.PRIMITIVE_LINE_STRIP, Mesh.PRIMITIVE_LINE_LOOP:
				var iy = 0
				var previx
				var pt
				var vix
				while iy < vertex_count + (1 if type == Mesh.PRIMITIVE_LINE_LOOP else 0):
					if has_index:
						vix = arr[ArrayMesh.ARRAY_INDEX][iy if iy < vertex_count else 0]
					else:
						vix = iy if iy < vertex_count else 0
					if iy == 0 || (type == Mesh.PRIMITIVE_LINES && (iy % 2) == 0):
						previx = vix
						iy += 1
						continue
					# Position between 0 and 1 of pos projected to the vector (prevpt -> pt)
					dist = nmin(dist, point_line_closer_distance(camera, camera_plane, pos, camera_vertexes[previx], camera_vertexes[vix], mesh_vertexes[previx], mesh_vertexes[vix], false))
					previx = vix
					iy += 1
			Mesh.PRIMITIVE_TRIANGLES:
				if vertex_count < 3:
					return null
				var iy = 0
				var vix1
				var vix2
				var vix3
				while iy < vertex_count - 2:
					vix1 = arr[ArrayMesh.ARRAY_INDEX][iy] if has_index else iy
					vix2 = arr[ArrayMesh.ARRAY_INDEX][iy + 1] if has_index else iy + 1
					vix3 = arr[ArrayMesh.ARRAY_INDEX][iy + 2] if has_index else iy + 2
					dist = nmin(dist, point_triangle_distance(camera, camera_plane, pos, vix1, vix2, vix3, camera_vertexes, mesh_vertexes, pos3d, norm3d, front, back))
					iy += 3
			Mesh.PRIMITIVE_TRIANGLE_STRIP:
				if vertex_count < 3:
					return null
				var iy = 0
				var vix1
				var vix2
				var vix3
				while iy < vertex_count - 2:
					vix1 = arr[ArrayMesh.ARRAY_INDEX][iy] if has_index else iy
					vix2 = arr[ArrayMesh.ARRAY_INDEX][iy + 1] if has_index else iy + 1
					vix3 = arr[ArrayMesh.ARRAY_INDEX][iy + 2] if has_index else iy + 2
					if vix1 != vix2 && vix2 != vix3:
						dist = nmin(dist, point_triangle_distance(camera, camera_plane, pos, vix1, vix2, vix3, camera_vertexes, mesh_vertexes, pos3d, norm3d, front, back))
					iy += 1
			Mesh.PRIMITIVE_TRIANGLE_FAN:
				if vertex_count < 3:
					return null
				var iy = 0
				var vix1
				var vix2
				var vix3
				vix1 = arr[ArrayMesh.ARRAY_INDEX][0] if has_index else 0
				while iy < vertex_count - 2:
					vix2 = arr[ArrayMesh.ARRAY_INDEX][iy + 1] if has_index else iy + 1
					vix3 = arr[ArrayMesh.ARRAY_INDEX][iy + 2] if has_index else iy + 2
					if vix2 != vix3:
						dist = nmin(dist, point_triangle_distance(camera, camera_plane, pos, vix1, vix2, vix3, camera_vertexes, mesh_vertexes, pos3d, norm3d, front, back))
					iy += 1
	return dist
		

static func project_point_to_line(p, a, b) -> float:
	return (p - a).dot(b - a) / (b - a).dot(b - a)
	

static func nmin(a, b):
	if a == null:
		return b
	if b == null:
		return a
	return min(a, b)


static func point_closer_distance(camera: Camera, pos: Vector2, camera_vertex: Vector2, vertex: Vector3):
	if camera.is_position_behind(vertex):
		return null
		
	if pos.distance_to(camera_vertex) <= CLICK_MARGIN:
		#print("Point hit")
		return vertex.distance_to(camera_ray_origin(camera, camera_vertex))
	return null


# Returns the distance of pos (pos3d) to the line cv1->cv2 (v1->v2).
# If check_endpoints is true, and projecting the position on the line is outside the given
# segment, distance to the closer end point is returned. Returns null if distance can't be
# determined or point is not near the line.
static func point_line_closer_distance(camera: Camera, camera_plane: Plane, pos: Vector2, cv1: Vector2, cv2: Vector2, v1: Vector3, v2: Vector3, check_endpoints):
	var b1 = camera_plane.distance_to(v1) < 0 #camera.is_position_behind(v1)
	var b2 = camera_plane.distance_to(v2) < 0 #camera.is_position_behind(v2)
	if b1 && b2:
		return null
		
	var dist = null
	if check_endpoints:
		dist = nmin(point_closer_distance(camera, pos, cv1, v1), point_closer_distance(camera, pos, cv2,  v2))
	if cv1 == cv2:
		#if dist != null:
		#	print("Same points hit")
		return dist
	
	return nmin(dist, alternative_point_line_closer_distance(camera, camera_plane, pos, v1, v2))


static func alternative_point_line_closer_distance(camera: Camera, camera_plane: Plane, pos, v1: Vector3, v2: Vector3):
	#var b1 = camera_plane.distance_to(v1) < 0
	#var b2 = camera_plane.distance_to(v2) < 0
	if camera_plane.distance_to(v1) < 0:
		v1 = camera_plane.intersects_segment(v1, v2)
	elif camera_plane.distance_to(v2) < 0:
		v2 = camera_plane.intersects_segment(v1, v2)
	if v1 == null || v2 == null:
		return null
	
	#var b12 = camera.is_position_behind(v1)
	#var b22 = camera.is_position_behind(v2)
	var cv1 = camera.unproject_position(v1)
	var cv2 = camera.unproject_position(v2)
	var proj_pos = project_point_to_line(pos, cv1, cv2)
	if proj_pos < 0 || proj_pos > 1:
		return null

	var camera_vertex = cv1 + (cv2 - cv1) * proj_pos
	if pos.distance_to(camera_vertex) <= CLICK_MARGIN:
		var plane = Plane(v1, v2, v1 + camera.global_transform.basis.y if abs(cv1.x - cv2.x) > abs(cv1.y - cv2.y) else camera.global_transform.basis.x)
		var camera_origin_point = camera_ray_origin(camera, camera_vertex)
		var vertex = plane.intersects_ray(camera_origin_point, camera_ray_normal(camera, camera_vertex))
		if vertex != null:
			#print("Line hit: " + str(b1) + " " + str(b12) + " " + str(cv1) + str(v1) + " - " + str(b2) + " " + str(b22) + " " + str(cv2) + str(v2))
			return vertex.distance_to(camera_origin_point)
	return null


static func point_triangle_distance(camera: Camera, camera_plane, pos, vix1, vix2, vix3, camera_vertexes, mesh_vertexes, pos3d, norm3d, front: bool, back: bool):
	# First part of point in triangle distance, which also determines if it's a front
	# or back facing triangle to test.
	var edge1: Vector3 = mesh_vertexes[vix2] - mesh_vertexes[vix1]
	var edge2: Vector3 = mesh_vertexes[vix3] - mesh_vertexes[vix1]
	var pvec: Vector3 = norm3d.cross(edge2)
	var det: float = edge1.dot(pvec)
	
	if (!front || det > -0.00001) && (!back || det < 0.00001):
		return null	
	
	var dist = __point_triangle_distance_part2(mesh_vertexes[vix1], det, pvec, edge1, edge2, pos3d, norm3d)
	if dist != null:
		return dist
			
	return point_triangle_frame_distance(camera, camera_plane, pos, vix1, vix2, vix3, camera_vertexes, mesh_vertexes, pos3d, norm3d)

# originally comes from http://www.graphics.cornell.edu/pubs/1997/MT97.pdf
# source: https://gamedev.stackexchange.com/questions/25079/ray-triangle-intersection-issue
static func __point_triangle_distance_part2(mesh_vertex: Vector3, det: float, pvec: Vector3, edge1: Vector3, edge2: Vector3, pos3d: Vector3, norm3d: Vector3):
	var inv_det = 1.0 / det
	var tvec = pos3d - mesh_vertex
	var u = tvec.dot(pvec) * inv_det
	if u < 0.0 || u > 1.0:
		return null

	var qvec = tvec.cross(edge1)
	var v = norm3d.dot(qvec) * inv_det
	if v < 0.0 || u + v > 1.0:
		return null

	var t = edge2.dot(qvec) * inv_det
	if t < 0.0: # || t >= 1.0:
		return null
		
	# Position of intersection
	#return pos3d + (norm3d * t)
	
	# Distance of intersection
	return t


static func point_triangle_frame_distance(camera: Camera, camera_plane, pos, vix1, vix2, vix3, camera_vertexes, mesh_vertexes, pos3d: Vector3, norm3d: Vector3):
	var dist = point_closer_distance(camera, pos, camera_vertexes[vix1], mesh_vertexes[vix1])
	dist = nmin(dist, point_closer_distance(camera, pos, camera_vertexes[vix2], mesh_vertexes[vix2]))
	dist = nmin(dist, point_closer_distance(camera, pos, camera_vertexes[vix3], mesh_vertexes[vix3]))
	dist = nmin(dist, point_line_closer_distance(camera, camera_plane, pos, camera_vertexes[vix1], camera_vertexes[vix2], mesh_vertexes[vix1], mesh_vertexes[vix2], false))
	dist = nmin(dist, point_line_closer_distance(camera, camera_plane, pos, camera_vertexes[vix3], camera_vertexes[vix1], mesh_vertexes[vix3], mesh_vertexes[vix1], false))
	dist = nmin(dist, point_line_closer_distance(camera, camera_plane, pos, camera_vertexes[vix2], camera_vertexes[vix3], mesh_vertexes[vix2], mesh_vertexes[vix3], false))
	
	return dist


# From: https://stackoverflow.com/questions/2049582/how-to-determine-if-a-point-is-in-a-2d-triangle
static func point_line_side(p1: Vector2, p2: Vector2, p3: Vector2):
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


## From: https://stackoverflow.com/questions/2049582/how-to-determine-if-a-point-is-in-a-2d-triangle
#static func point_in_triangle(pt: Vector2, v1: Vector2, v2: Vector2, v3: Vector2):
#	var d1 = point_line_side(pt, v1, v2)
#	var d2 = point_line_side(pt, v2, v3)
#	var d3 = point_line_side(pt, v3, v1)
#
#	var has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
#	var has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)
#
#	return !(has_neg && has_pos)


