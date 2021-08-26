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
extends EditorPlugin

const UI = preload("./util/editor_ui.gd")
const FS = preload("./util/file_system.gd")
const PluginSettings = preload("./util/plugin_settings.gd")
const ControlDock = preload("./ui/control_dock.tscn")
const GridMesh = preload("./mesh/grid_mesh.gd")

# Separate script for stuff that needs to persist
var settings: PluginSettings = PluginSettings.new()


# Current manipulation of objects
enum GSRState { NONE, GRAB, ROTATE, SCALE, SCENE_PLACEMENT }
# Axis of manipulation
enum GSRLimit { NONE, X = 1, Y = 2, Z = 4, REVERSE = 8 }
# Axis for reading snapping values.
enum GSRAxis { XZ = 0, Y = 1 }

# Objects manipulated by this plugin are selected
var selected := false
# Saved objects for hiding their gizmos.
var selected_objects: WeakRef = weakref(null)


# Current manipulation of objects from GSRState
var state: int = GSRState.NONE
# Axis of manipulation from GSRLimit
var limit: int = 0
# Objects being manipulated.
var selection := []
# Using local axis or global
var local := false

# Set to 0.1 when smoothing movement is required as shift is held down.
var smoothing := false
# Whether the ctrl key is held down while manipulating. Reverses the effect of
# the snap button on the UI.
var snap_toggle = false


# Numeric string entered to set parameter for manipulation
var numerics: String

# A center point in global space used when manipulating objects. Stays the
# same until manipulation ends.
var selection_center: Vector3
# The selection_center point projected onto the camera's plane.
var selection_centerpos: Vector2
# Position of mouse when manipulation started
var start_mousepos: Vector2
# Position in the viewport when manipulation starts. Computed from mousepos.
var start_viewpoint: Vector3
# Current mouse position
var mousepos: Vector2
# Used while manipulating objects to know the mouse position one step before the
# current mouse position.
var saved_mousepos: Vector2
# Distance of selection from the editor camera's plane.
var selection_distance := 0.0
# The transform of each selected object when manipulation started, so it can
# be restored on cancel or undo.
var start_transform := []
# The global transform of each selected object when manipulation started.
var start_global_transform := []

# Used when rotating to know the angle the selection was rotated by. This can be
# multiple times a full circle.
var rotate_angle := 0.0
# The applied rotation in degrees, used for the text display on the view.
var rotate_display := 0.0

# The applied scale in percent, used for the text display on the view.
var scale_display := 0.0
var scale_axis_display: Vector3

# Camera of the 3d view saved to be able to get projections on the camera
# plane when drawing the axis of manipulation.
var editor_camera: Camera = null


# Set to true during manipulation when the gizmos are shrank invisible.
var gizmohidden = false
# Used when hiding gizmos so their original size can be restored.
var saved_gizmo_size


# Button added to toolbar for settings like the z key toggle.
var menu_button: MenuButton
#var toolbutton_z_up: ToolButton

# Dock added to the UI with plugin settings.
var control_dock = null


# Scene being placed on the scene as a "tile"
var spatialscene: Spatial = null
# Parent node the "tiles" will be placed on in scene placement mode. Either the
# root Spatial node if nothing is selected, or the selected spatial node.
var spatialparent: Spatial = null
# Path to packed scene being placed as "tile"
var spatial_file_path: String = ""


var grid_mesh = null


func _enter_tree():
	settings.load_config()
	add_toolbuttons()
	add_control_dock()
	register_callbacks(true)
	generate_grid_mesh()


func _exit_tree():
	settings.save_config()
	register_callbacks(false)
	remove_toolbuttons()
	# Make sure we don't hold a reference of anything
	reset()
	selected_objects = weakref(null)
	remove_control_dock()
	free_grid_mesh()


func add_control_dock():
	control_dock = ControlDock.instance()
	control_dock.editor = self
	get_editor_interface().get_editor_viewport().add_child(control_dock)
	update_control_dock()
	
	
func remove_control_dock():
	control_dock.queue_free()
	

func add_toolbuttons():
	if menu_button == null:
		menu_button = MenuButton.new()
		menu_button.text = "GSR"
		var popup = menu_button.get_popup()
		popup.add_check_item("Z for up")
		popup.set_item_tooltip(0, "Swap z and y axis-lock shortcuts")
		popup.set_item_checked(0, settings.zy_swapped)
		
		popup.add_check_item("Snap options")
		popup.set_item_tooltip(1, "Show snapping options in 3D editor")
		popup.set_item_checked(1, settings.snap_controls_shown)
		
		popup.add_separator()
		
		popup.add_item("Unpack scene...")
		popup.set_item_tooltip(3, "Save child scenes in their own scene files.")
		
		
		UI.spatial_toolbar(self).add_child(menu_button)
		popup.connect("index_pressed", self, "_on_menu_button_popup_index_pressed")
			
#	if toolbutton_z_up == null:
#		toolbutton_z_up = ToolButton.new()
#		toolbutton_z_up.toggle_mode = true
#		toolbutton_z_up.hint_tooltip = "Swap z and y axis lock shortcuts"
#		toolbutton_z_up.connect("toggled", self, "_on_toolbutton_z_up_toggled")
#		if UI.is_dark_theme(self):
#			toolbutton_z_up.icon = preload("./icons/icon_z_up.svg")
#		else:
#			toolbutton_z_up.icon = preload("./icons/icon_z_up_light.svg")
#
#		toolbutton_z_up.pressed = UI.get_config_property("settings", "z_up", false)
#		UI.spatial_toolbar(self).add_child(toolbutton_z_up)


func _on_menu_button_popup_index_pressed(index: int):
	var popup = menu_button.get_popup()
	
	# Z Up
	if index == 0:
		popup.set_item_checked(0, !popup.is_item_checked(0))
		settings.zy_swapped = popup.is_item_checked(0)
		return
	# Snap controls
	if index == 1:
		popup.set_item_checked(1, !popup.is_item_checked(1))
		settings.snap_controls_shown = popup.is_item_checked(1)
		update_control_dock()
	# Unpack scene
	if index == 3:
		unpack_scene()


func remove_toolbuttons():
	if menu_button != null:
		if menu_button.get_parent() != null:
			menu_button.get_parent().remove_child(menu_button)
		menu_button.free()
		menu_button = null
		
#	if toolbutton_z_up != null:
#		if toolbutton_z_up.get_parent() != null:
#			toolbutton_z_up.get_parent().remove_child(toolbutton_z_up)
#		toolbutton_z_up.free()
#		toolbutton_z_up = null


#func _on_settings_changed():
#	if menu_button != null:
#		var popup = menu_button.get_popup()
##		if UI.is_dark_theme(self):
##			popup.set_item_icon(0, preload("./icons/icon_z_up.svg"))
##		else:
##			popup.set_item_icon(0, preload("./icons/icon_z_up_light.svg"))
#
##	if toolbutton_z_up != null:
##		if UI.is_dark_theme(self):
##			toolbutton_z_up.icon = preload("./icons/icon_z_up.svg")
##		else:
##			toolbutton_z_up.icon = preload("./icons/icon_z_up_light.svg")
	

func register_callbacks(register: bool):
	if register:
		connect("main_screen_changed", self, "_on_main_screen_changed")
		#UI.connect_settings_changed(self, "_on_settings_changed")
	else:
		disconnect("main_screen_changed", self, "_on_main_screen_changed")
		#UI.disconnect_settings_changed(self, "_on_settings_changed")
	pass


func _on_main_screen_changed(name: String):
	update_control_dock()


func update_control_dock():
	control_dock.visible = settings.snap_controls_shown && UI.current_main_screen(self) == "3D"


#func _on_toolbutton_z_up_toggled(toggled: bool):
#	settings.zy_swapped = toggled


func handles(object):
	if object != null:
		var ei = get_editor_interface()
		var es = ei.get_selection()
		var nodes = es.get_transformable_selected_nodes()
		for n in nodes:
			if n is Spatial:
				selected_objects = weakref(object)
				return true
		if object is Spatial:
			selected_objects = weakref(object)
			return true

	return object == null


func make_visible(visible):
	if selected == visible:
		return
		
	selected = visible
	if !visible:
		show_gizmo()
	cancel_all()


# Whether the button to use local space by default is pressed. After I figured it
# out how to find it.
func is_local_button_down():
	var button: ToolButton = UI.spatial_use_local_toolbutton(self)
	if button != null:
		return button.pressed
	return false


func is_snapping():
	if !numerics.empty():
		return false
	
	var button: ToolButton = UI.spatial_snap_toolbutton(self)
	if button != null:
		return (button.pressed && !snap_toggle) || (!button.pressed && snap_toggle)
	return snap_toggle


func get_grab_action_strength():
	if !smoothing:
		return 1.0
	return 1.0 / settings.grab_snap_subd_x


func get_action_strength():
	if !smoothing:
		return 1.0
	return 0.1


func grab_step_size():
	return settings.grab_snap_size_x * get_grab_action_strength()


func rotate_step_size():
	return 5.0 * get_action_strength()


func scale_step_size():
	return 0.1 * get_action_strength()


func tile_step_size(axis: int, with_smoothing: bool):
	if !smoothing || !with_smoothing:
		if axis == GSRAxis.XZ:
			return settings.grab_snap_size_x
		return settings.grab_snap_size_y
	if axis == GSRAxis.XZ || !settings.use_y_grab_snap:
		return settings.grab_snap_size_x * (1.0 / settings.grab_snap_subd_x)
	return settings.grab_snap_size_y * (1.0 / settings.grab_snap_subd_y)
	

func hide_gizmo():
	if gizmohidden:
		return

	gizmohidden = true

	saved_gizmo_size = UI.get_setting(self, "editors/3d/manipulator_gizmo_size")
	UI.set_setting(self, "editors/3d/manipulator_gizmo_size", 0)
	

func show_gizmo():
	if !gizmohidden:
		return

	gizmohidden = false

	UI.set_setting(self, "editors/3d/manipulator_gizmo_size", saved_gizmo_size)
	saved_gizmo_size = UI.get_setting(self, "editors/3d/manipulator_gizmo_size")
	

func draw_line_dotted(control: CanvasItem, from: Vector2, to: Vector2, dot_len: float, space_len: float, color: Color, width: float = 1.0, antialiased: bool = false):
	var normal := (to - from).normalized()
	
	var start := from
	var end := from + normal * dot_len
	var length = (to - from).length()
	
	while length > (start - from).length():
		if length < (end - from).length():
			end = to
		
		control.draw_line(start, end, color, width, antialiased)
		
		start = end + normal * space_len
		end = start + normal * dot_len


var mousepos_offset := Vector2.ZERO
var reference_mousepos := Vector2.ZERO


func manipulation_mousepos() -> Vector2:
	return (mousepos - reference_mousepos) * get_action_strength() + mousepos_offset


func save_manipulation_mousepos():
	mousepos_offset += (mousepos - reference_mousepos) * get_action_strength()
	reference_mousepos = mousepos
	
	
func forward_spatial_gui_input(camera, event):
	if event is InputEventKey:
		if event.echo:
			return false
			
		if event.scancode == KEY_SHIFT:
			if state == GSRState.NONE:
				return false
			save_manipulation_mousepos()
			smoothing = event.pressed
		elif event.scancode == KEY_CONTROL:
			if state == GSRState.NONE:
				return false
			snap_toggle = event.pressed
		if !event.pressed:
			return false
		
		if selected && char(event.unicode) == 'g':
			if state == GSRState.GRAB:
				return false
			start_manipulation(camera, GSRState.GRAB)
			saved_mousepos = mousepos
			return true
		elif selected && char(event.unicode) == 'r':
			if state == GSRState.ROTATE:
				return false
			start_manipulation(camera, GSRState.ROTATE)
			saved_mousepos = mousepos
			return true
		elif selected && char(event.unicode) == 's':
			if state == GSRState.SCALE:
				return false
			start_manipulation(camera, GSRState.SCALE)
			saved_mousepos = mousepos
			return true
		elif char(event.unicode) == 'a':
			if state == GSRState.SCENE_PLACEMENT:
				return false
			start_scene_placement(camera)
			saved_mousepos = mousepos
			return true
		elif event.scancode == KEY_ESCAPE:
			cancel_all()
			return true
		elif state != GSRState.NONE && state != GSRState.SCENE_PLACEMENT:
			var newlimit = 0
			if event.scancode == KEY_ENTER || event.scancode == KEY_KP_ENTER:
				finalize_manipulation()
				return true
			elif char(event.unicode) == 'x' || char(event.unicode) == 'X':
				change_limit(camera, GSRLimit.X | (GSRLimit.REVERSE if event.shift else 0))
				return true
			elif char(event.unicode) == 'y' || char(event.unicode) == 'Y':
				if !settings.zy_swapped:
					change_limit(camera, GSRLimit.Y | (GSRLimit.REVERSE if event.shift else 0))
				else:
					change_limit(camera, GSRLimit.Z | (GSRLimit.REVERSE if event.shift else 0))
				return true
			elif char(event.unicode) == 'z' || char(event.unicode) == 'Z':
				if !settings.zy_swapped:
					change_limit(camera, GSRLimit.Z | (GSRLimit.REVERSE if event.shift else 0))
				else:
					change_limit(camera, GSRLimit.Y | (GSRLimit.REVERSE if event.shift else 0))
				return true
			elif (char(event.unicode) >= '0' && char(event.unicode) <= '9' ||
					char(event.unicode) == '.' || char(event.unicode) == '-'):
				numeric_input(camera, char(event.unicode))
				return true
			elif event.scancode == KEY_BACKSPACE:
				numeric_delete(camera)
				return true
	
	elif event is InputEventMouseButton:
		if state != GSRState.NONE:
			if event.button_index == BUTTON_RIGHT:
				cancel_all()
				return true
			elif event.button_index == BUTTON_LEFT:
				if state != GSRState.SCENE_PLACEMENT:
					finalize_manipulation()
					return true
				finalize_scene_placement()
				return true
			elif snap_toggle && state == GSRState.SCENE_PLACEMENT && (event.button_index == BUTTON_WHEEL_UP ||
					event.button_index == BUTTON_WHEEL_DOWN):
				var dir = 1.0 if event.button_index == BUTTON_WHEEL_UP else -1.0
				var amount = 15.0 if !smoothing else 5.0
				spatialscene.rotate_y(dir * PI / 180.0 * amount)
				return true
	elif event is InputEventMouseMotion:
		mousepos = current_camera_position(event, camera)
		if state == GSRState.NONE:
			saved_mousepos = mousepos
			return false
		
		if state == GSRState.SCENE_PLACEMENT:
			update_scene_placement()
			saved_mousepos = mousepos
			
			# Returning true here would prevent navigating the 3D view.
			return false
			
		elif state != GSRState.NONE:
			if numerics.empty():
				manipulate_selection()
				
		saved_mousepos = mousepos
		return state != GSRState.NONE
			
	return false


# Returns the screen position of event relative to editor_camera instead of the
# camera, which the event corresponds
func current_camera_position(event: InputEventMouseMotion, camera: Camera) -> Vector2:
	if camera == editor_camera || editor_camera == null:
		return event.position
	return editor_camera.get_parent().get_parent().get_local_mouse_position()
	


func forward_spatial_draw_over_viewport(overlay):
	# Hack to check if this overlay is the one we use right now:
	if !is_instance_valid(editor_camera) || overlay.get_parent().get_child(0).get_child(0).get_child(0) != editor_camera:
		return
		
	if state == GSRState.NONE || state == GSRState.SCENE_PLACEMENT:
		return
	
	var f = overlay.get_font("font")
	var text: String
	
	if state == GSRState.GRAB:
		text = "[Grab]"
	elif state == GSRState.ROTATE:
		text = "[Rotate]"
	elif state == GSRState.SCALE:
		text = "[Scale]"
	
	if limit == GSRLimit.X:
		text += " X axis"
	elif limit == GSRLimit.Y:
		text += " Y axis"
	elif limit == GSRLimit.Z:
		text += " Z axis"
	elif limit & GSRLimit.X:
		text += " YZ axis"
	elif limit & GSRLimit.Y:
		text += " XZ axis"
	elif limit & GSRLimit.Z:
		text += " XY axis"
	
	if !numerics.empty():
		text += "  Input: " + numerics

	if state == GSRState.GRAB:
		# The new center of selection, to calculate distance moved
		var center = Vector3.ZERO
		for ix in selection.size():
			center += selection[ix].global_transform.origin
		center /= selection.size()
		var dist = selection_center - center
		text += "  Distance: %.4f  Dx: %.4f  Dy: %.4f  Dz: %.4f" % [dist.length(), dist.x, dist.y, dist.z]
	elif state == GSRState.ROTATE:
		text += "  Deg: %.2f°" % [rotate_display]
	elif state == GSRState.SCALE:
		text += "  Scale: %.2f%%  Sx: %.4f  Sy: %.4f  Sz: %.4f" % [scale_display, scale_axis_display.x, scale_axis_display.y, scale_axis_display.z]
		
	overlay.draw_string(f, Vector2(16, 57), text, Color(0, 0, 0, 1))
	overlay.draw_string(f, Vector2(15, 56), text)
	
	if state != GSRState.GRAB:
		draw_line_dotted(overlay, mousepos + Vector2(0.5, 0.5), 
				selection_centerpos + Vector2(0.5, 0.5), 4.0, 4.0, Color.black, 1.0, true)
		draw_line_dotted(overlay, mousepos, selection_centerpos, 4.0, 4.0, Color.white, 1.0, true)
		
	if !local:
		if limit == GSRLimit.X:
			draw_axis(overlay, GSRLimit.X)
		elif limit == GSRLimit.Y:
			draw_axis(overlay, GSRLimit.Y)
		elif limit == GSRLimit.Z:
			draw_axis(overlay, GSRLimit.Z)
		elif limit & GSRLimit.X:
			draw_axis(overlay, GSRLimit.Y)
			draw_axis(overlay, GSRLimit.Z)
		elif limit & GSRLimit.Y:
			draw_axis(overlay, GSRLimit.X)
			draw_axis(overlay, GSRLimit.Z)
		elif limit & GSRLimit.Z:
			draw_axis(overlay, GSRLimit.X)
			draw_axis(overlay, GSRLimit.Y)
	else:
		for ix in selection.size():
			if editor_camera.is_position_behind(start_global_transform[ix].origin):
				continue
			
			if limit == GSRLimit.X:
				draw_axis(overlay, GSRLimit.X, start_global_transform[ix])
			elif limit == GSRLimit.Y:
				draw_axis(overlay, GSRLimit.Y, start_global_transform[ix])
			elif limit == GSRLimit.Z:
				draw_axis(overlay, GSRLimit.Z, start_global_transform[ix])
			elif limit & GSRLimit.X:
				draw_axis(overlay, GSRLimit.Y, start_global_transform[ix])
				draw_axis(overlay, GSRLimit.Z, start_global_transform[ix])
			elif limit & GSRLimit.Y:
				draw_axis(overlay, GSRLimit.X, start_global_transform[ix])
				draw_axis(overlay, GSRLimit.Z, start_global_transform[ix])
			elif limit & GSRLimit.Z:
				draw_axis(overlay, GSRLimit.X, start_global_transform[ix])
				draw_axis(overlay, GSRLimit.Y, start_global_transform[ix])
			


func draw_axis(control: Control, which, gtrans = null):
	if editor_camera == null:
		return
	
	var viewrect := control.get_rect()
	
	var center = selection_center if gtrans == null else gtrans.origin
	var centerpos = selection_centerpos if gtrans == null else editor_camera.unproject_position(center)
	
	# x red
	# z blue
	# y green
	var color = Color(1, 0.6, 0.6, 1) if which == GSRLimit.X else \
			(Color(0.6, 1, 0.6, 1) if which == GSRLimit.Y else Color(0.6, 0.6, 1, 1))
	
	var global_axis = (!local || gtrans == null) || (state == GSRState.ROTATE && local && (limit & GSRLimit.REVERSE))
	
	var left = Vector3.LEFT if global_axis else gtrans.basis.x.normalized()
	var up = Vector3.UP if global_axis else gtrans.basis.y.normalized()
	var forward = Vector3.FORWARD if global_axis else gtrans.basis.z.normalized()
	
	var xaxis = (centerpos - editor_camera.unproject_position(center + left * 10000.0)).normalized()
	var yaxis = (centerpos - editor_camera.unproject_position(center + up * 10000.0)).normalized()
	var zaxis = (centerpos - editor_camera.unproject_position(center + forward * 10000.0)).normalized()
	
	var checkaxis
	
	if which == GSRLimit.X:
		checkaxis = xaxis
	elif which == GSRLimit.Y:
		checkaxis = yaxis
	else:
		checkaxis = zaxis
		
	# Intersection point of the axis with the viewport's top
	var pt1 := get_intersection(centerpos, checkaxis, Vector2(0, 0), Vector2(1, 0))
	# Intersection point of the axis with the viewport's bottom
	var pt2 := get_intersection(centerpos, checkaxis, Vector2(0, viewrect.size.y - 1), Vector2(1, 0))
	# Intersection point of the axis with the viewport's left
	var pt3 := get_intersection(centerpos, checkaxis, Vector2(0, 0), Vector2(0, 1))
	# Intersection point of the axis with the viewport's right
	var pt4 := get_intersection(centerpos, checkaxis, Vector2(viewrect.size.x - 1, 0), Vector2(0, 1))
	
	var start = pt1 if inside_viewrect(viewrect.size, pt1) else (pt2 if inside_viewrect(viewrect.size, pt2) else pt3)
	var end = pt2 if start != pt2 && inside_viewrect(viewrect.size, pt2) else \
			(pt3 if start != pt3 && inside_viewrect(viewrect.size, pt3) else pt4)
	
	control.draw_line(start, end, color)


# Returns the point where line 1 and line 2 would intersect, if ever. Not a
# full intersection check. We use the fact that line 2 is always horizontal or
# vertical.
func get_intersection(l1_start: Vector2, l1_normal: Vector2, l2_start: Vector2, l2_normal: Vector2) -> Vector2:
	var l1horz = l1_normal.y == 0.0
	var l1vert = l1_normal.x == 0.0
	
	var l2horz = l2_normal.y == 0.0
	var l2vert = l2_normal.x == 0.0
	
	# Lines never meet. Return a point outside the viewport area.
	if (l1horz && l2horz) || (l1vert && l2vert):
		return Vector2(-100, -100)
	
	if l1vert:
		return Vector2(l1_start.x, l2_start.y)
	if l1horz:
		return Vector2(l1_start.y, l2_start.x)
	
	if l2vert:
		# slope of line 1
		var a := l1_normal.y / l1_normal.x
		return Vector2(l2_start.x, l1_start.y + (l2_start.x - l1_start.x) * a)
	if l2horz:
		# slope of line 1
		var a := l1_normal.x / l1_normal.y
		return Vector2(l1_start.x + (l2_start.y - l1_start.y) * a, l2_start.y)
	
	return Vector2.ZERO
	

func inside_viewrect(viewsize: Vector2, pt: Vector2):
	return pt.x >= -0.001 && pt.y >= -0.001 && pt.x <= viewsize.x + 0.001 && pt.y <= viewsize.y + 0.001


func get_placement_scene(path) -> PackedScene:
	var ei = get_editor_interface()
	
	var fs = ei.get_resource_filesystem()
	if fs.get_file_type(path) != "PackedScene":
		return null
	var ps: PackedScene = load(path)
	if !ps.can_instance():
		return null
	var sstate = ps.get_state()
	if sstate.get_node_count() < 1:
		return null
	if !ClassDB.class_exists(sstate.get_node_type(0)) && ClassDB.is_parent_class(sstate.get_node_type(0), "Spatial"):
		return null
	return ps

func start_scene_placement(camera: Camera):
	cancel_all()
	
	# Get the selected scene in the file system that can be instanced.
	spatial_file_path = UI.fs_selected_path(self)
	if spatial_file_path.empty():
		return
	
	var ps := get_placement_scene(spatial_file_path)
	if ps == null:
		return
	
	var ei = get_editor_interface()
	var es = ei.get_selection()
	var objects = es.get_transformable_selected_nodes()
	if objects == null || objects.empty():
		var root = ei.get_edited_scene_root()
		if !(root is Spatial):
			return
		spatialparent = root
	elif objects.size() > 1:
		# Multiple nodes selected. Only one is acceptable for scene placement.
		return
	else:
		if !(objects[0] is Spatial):
			return
		spatialparent = objects[0];

	state = GSRState.SCENE_PLACEMENT
	start_mousepos = mousepos
	
	spatialscene = ps.instance()
	spatialparent.add_child(spatialscene)

	editor_camera = camera	
	
	if grid_mesh != null:
		spatialparent.add_child(grid_mesh)
	update_scene_placement()
		
	
	
func start_manipulation(camera: Camera, newstate):
	if state != GSRState.NONE:
		cancel_all()
	
	state = newstate
	start_mousepos = mousepos
	local = is_local_button_down()
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
	selection = []
	var objects = es.get_transformable_selected_nodes()
	for obj in objects:
		if obj is Spatial:
			selection.append(obj)
			
	start_transform.resize(selection.size())
	start_global_transform.resize(selection.size())
	
	#print(UI.get_setting(self, "editors/3d/manipulator_gizmo_opacity"))
	
	if selection.empty():
		reset()
	else:
		selection_center = Vector3.ZERO
		
		var alternate_center = true
		var sel_min: Vector3
		var sel_max: Vector3
		
		for ix in selection.size():
			start_transform[ix] = selection[ix].transform
			start_global_transform[ix] = selection[ix].global_transform
			
			var ori = selection[ix].global_transform.origin
			if !alternate_center:
				selection_center += ori
			else:
				if ix == 0:
					sel_min = ori
					sel_max = ori
				else:
					sel_min.x = min(sel_min.x, ori.x)
					sel_min.y = min(sel_min.y, ori.y)
					sel_min.z = min(sel_min.z, ori.z)
					sel_max.x = max(sel_max.x, ori.x)
					sel_max.y = max(sel_max.y, ori.y)
					sel_max.z = max(sel_max.z, ori.z)
		if !alternate_center:
			selection_center /= selection.size()
		else:
			selection_center = (sel_min + sel_max) / 2.0
			
		selection_centerpos = camera.unproject_position(selection_center)
		selection_distance = selection_center.distance_to(camera.project_ray_origin(selection_centerpos))
		start_viewpoint = camera.project_position(mousepos, selection_distance)
		
		hide_gizmo()
		update_overlays()
		#Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		editor_camera = camera


func change_limit(camera, newlimit):
	revert_manipulation()
	if newlimit != 0:
		var lbd = is_local_button_down()
		if newlimit == limit:
			if local != lbd:
				newlimit = 0
				local = lbd
			else:
				local = !local
		elif limit != 0:
			local = lbd
		limit = newlimit
	apply_manipulation()


func numeric_input(camera: Camera, ch):
	if ch == '.':
		if numerics.find('.') != -1:
			return
		numerics += ch
		update_overlays()
		return
		
	revert_manipulation()
	if ch == '-':
		if numerics.empty() || numerics[0] != '-':
			numerics = "-" + numerics
		else:
			numerics = numerics.substr(1)
	else:
		numerics += ch
	apply_manipulation()


func numeric_delete(camera: Camera):
	if numerics.empty():
		return
	
	if numerics[numerics.length() - 1] == ".":
		numerics = numerics.substr(0, numerics.length() - 1)
		return
		
	revert_manipulation()
	numerics = numerics.substr(0, numerics.length() - 1)
	apply_manipulation()


func update_scene_placement():
	if spatialscene == null:
		return
		
	var plane = Plane(spatialparent.global_transform.basis.y, 0)
	var point = plane.intersects_ray(editor_camera.project_ray_origin(mousepos), editor_camera.project_ray_normal(mousepos))
	if point == null:
		if grid_mesh != null:
			grid_mesh.visible = false
		return
		
	point = spatialparent.to_local(point)
	var place = Vector3(stepify(point.x, tile_step_size(GSRAxis.XZ, false)), stepify(point.y, tile_step_size(GSRAxis.Y, false)), stepify(point.z, tile_step_size(GSRAxis.XZ, false)))
	var point_dif = Vector3.ZERO
	if smoothing:
		point_dif = Vector3(stepify(point.x, tile_step_size(GSRAxis.XZ, true)), stepify(point.y, tile_step_size(GSRAxis.Y, true)), stepify(point.z, tile_step_size(GSRAxis.XZ, true))) - place
	
	spatialscene.transform.origin = place + point_dif
	grid_mesh.visible = true
	update_grid_position(place)


func finalize_scene_placement():
	if spatialscene == null || spatialparent == null:
		reset_scene_action()
		return
	
	var transform = spatialscene.transform
	reset_scene_action()
	
	#spatialscene.owner = spatialparent.owner if spatialparent.owner != null else spatialparent
	
	var ur = get_undo_redo()
	ur.create_action("GSR Scene Placement")
	ur.add_do_method(self, "do_place_scene", spatial_file_path, spatialparent, transform)
	ur.add_undo_method(self, "undo_place_scene", spatialparent)
	ur.commit_action()
	
	reset()


func do_place_scene(spath, sparent, stransform):
	var ps := get_placement_scene(spath)
	if ps == null || !is_instance_valid(sparent):
		return
	
	var s = ps.instance()
	sparent.add_child(s)
	s.owner = sparent if sparent.owner == null else sparent.owner
	s.transform = stransform


func undo_place_scene(sparent):
	if !is_instance_valid(sparent) || !(sparent is Spatial):
		return
	sparent.remove_child(sparent.get_child(sparent.get_child_count() - 1)) 


func manipulate_selection():
	if state == GSRState.NONE || state == GSRState.SCENE_PLACEMENT:
		return
	
	revert_manipulation()
	apply_manipulation()


# Moves/rotates/scales selection back to original transform before manipulation
# started.
func revert_manipulation():
	if selection.empty():
		return
	
	for ix in selection.size():
		selection[ix].transform = start_transform[ix]


func reset_scene_action():
	if spatialscene != null:
		spatialscene.queue_free()
		spatialscene = null
	if grid_mesh != null && grid_mesh.get_parent() != null:
		grid_mesh.get_parent().remove_child(grid_mesh)


func apply_manipulation():
	if state == GSRState.SCENE_PLACEMENT || selection.empty():
		return
	
	var camera := editor_camera
	
	var constant = null
	if !numerics.empty():
		constant = numerics.to_float()

	if state == GSRState.GRAB:
		var offset: Vector3
		
		for ix in selection.size():
			if limit == GSRLimit.NONE:
				var vnew := camera.project_position(manipulation_mousepos(), selection_distance)
				offset = vnew - start_viewpoint
			if (limit & GSRLimit.X) || (limit & GSRLimit.Y) || (limit & GSRLimit.Z):
				if (limit & GSRLimit.REVERSE):
					var plane = get_limit_axis_reverse_plane(ix)
					var cam_pt = plane.intersects_ray(camera.project_ray_origin(manipulation_mousepos()), camera.project_ray_normal(manipulation_mousepos()))
					if cam_pt != null:
						offset = cam_pt - start_viewpoint
					else:
						offset = Vector3.ZERO #selection[ix].global_transform.origin - start_transform[ix].origin
				else:
					var cvec = camera.project_ray_normal(manipulation_mousepos())
					# Vector of the axis, either global or local, based on value of `local`
					var xvec = get_limit_axis_vector(ix)
					# Make a plane with the selection's center point on it. The mouse position
					# is then projected on it to determine how much the selection needs
					# to be moved.
					# The plane is created in two steps because I can't be asked to
					# calculate the distance argument. First make a plane on the origin,
					# then another after the distance is calculated using the first plane.
					var plane = Plane(cvec.cross(xvec).cross(xvec), 0)
					plane = Plane(cvec.cross(xvec).cross(xvec), plane.distance_to(start_viewpoint))
					
					# The point where the normal from the mouse intersects the plane. The
					# distance of this point from the selection along the xvec determines
					# how much to move the selection.
					var cam_pt = plane.intersects_ray(camera.project_ray_origin(manipulation_mousepos()), cvec)
					if cam_pt != null:
						plane = Plane(xvec, 0)
						plane = Plane(xvec, plane.distance_to(start_viewpoint))
						
						offset = xvec * plane.distance_to(cam_pt)
					else:
						offset = Vector3.ZERO #selection[ix].global_transform.origin - start_transform[ix].origin
					if constant != null:
						offset = get_grab_offset_for_axis(offset, xvec).normalized() * constant
						
			if is_snapping():
				if limit == GSRLimit.NONE:
					offset = Vector3(stepify(offset.x, grab_step_size()),
							stepify(offset.y, grab_step_size()),
							stepify(offset.z, grab_step_size()))
							
				elif (limit & GSRLimit.X) || (limit & GSRLimit.Y) || (limit & GSRLimit.Z):
					if (limit & GSRLimit.REVERSE):
						var vec = get_limit_axis_reverse_vectors(ix)
						var vec1 = offset.project(vec[0])
						var vec2 = offset.project(vec[1])
						
						offset = vec1.normalized() * stepify(vec1.length(), grab_step_size()) + vec2.normalized() * stepify(vec2.length(), grab_step_size())
					else:
						offset = offset.normalized() * stepify(offset.length(), grab_step_size())
						
			offset_object(ix, offset)
	elif state == GSRState.ROTATE:
		var offset: float = 0.0
		var point := selection_center
		var axis := Vector3.ZERO
		
		var change = Vector2(mousepos - selection_centerpos).angle_to(Vector2(saved_mousepos - selection_centerpos)) * get_action_strength()
		rotate_angle += change
		
		if is_snapping():
			var snapstep = rotate_step_size()
			rotate_display = stepify(rad2deg(rotate_angle), snapstep)
		else:
			rotate_display = rad2deg(constant if constant != null else rotate_angle) 
		
		for ix in selection.size():
			if limit == GSRLimit.NONE:
				axis = camera.global_transform.basis.z.normalized()
				offset = rotate_angle
			if (limit & GSRLimit.X) || (limit & GSRLimit.Y) || (limit & GSRLimit.Z):
				axis = get_limit_axis_vector(ix).normalized()
				
				if constant != null || camera.global_transform.basis.z.normalized().angle_to(axis) < PI / 2.0:
					offset = rotate_angle
				else:
					offset = -rotate_angle
					
			if constant != null:
				offset = deg2rad(constant)
			elif selection.size() == 1:
				rotate_display = rad2deg(offset)
				if is_snapping():
					var snapstep = rotate_step_size()
					rotate_display = stepify(rad2deg(offset), snapstep)
					
			if is_snapping():
				var snapstep = rotate_step_size()
				offset = deg2rad(stepify(rad2deg(offset), snapstep))
				
			rotate_object(ix, offset, point, axis, local)
	elif state == GSRState.SCALE:
		var point := selection_center
		var scale
		if constant == null:
			scale = (selection_centerpos - manipulation_mousepos()).length() / (selection_centerpos - start_mousepos).length()
		else:
			scale = float(constant) #/ 100.0
			
		if is_snapping():
			var snapstep = scale_step_size()
			scale = stepify(scale, snapstep)
			
		scale_display = scale * 100
		
		for ix in selection.size():
			var scaled: Vector3
			# The axis for scaling the pivots of selected objects relative to the center.
			var axis: Vector3
			var from = 1.0
			var to = 1.0
			if limit == GSRLimit.NONE:
				axis = Vector3(1.0, 1.0, 1.0)
				scaled = Vector3(scale, scale, scale)
				to = scale
			if (limit & GSRLimit.X) || (limit & GSRLimit.Y) || (limit & GSRLimit.Z):
				var basisx = selection[ix].global_transform.basis.x.normalized()
				var basisy = selection[ix].global_transform.basis.y.normalized()
				var basisz = selection[ix].global_transform.basis.z.normalized()
				axis = get_scale_limit_vector(basisx, basisy, basisz)
				if (limit & GSRLimit.REVERSE):
					from = scale
				else:
					to = scale
							
				scaled = Vector3(lerp(from, to, abs(basisx.dot(axis))),
						lerp(from, to, abs(basisy.dot(axis))),
						lerp(from, to, abs(basisz.dot(axis))))
				if local:
					point = selection[ix].global_transform.origin

			#axis = axis.normalized()
			var axis_scale = Vector3(lerp(from, to, abs(axis.x)),
					lerp(from, to, abs(axis.y)),
					lerp(from, to, abs(axis.z)))
			scale_axis_display = axis_scale
			scale_object(ix, scaled, axis_scale, point, local)
	update_overlays()


func get_limit_axis_vector(index: int) -> Vector3:
	if (limit & GSRLimit.X):
		return Vector3(1.0, 0.0, 0.0) if !local else selection[index].global_transform.basis.x.normalized()
	elif (limit & GSRLimit.Y):
		return Vector3(0.0, 1.0, 0.0) if !local else selection[index].global_transform.basis.y.normalized()
	elif (limit & GSRLimit.Z):
		return Vector3(0.0, 0.0, 1.0) if !local else selection[index].global_transform.basis.z.normalized()
	return Vector3.ZERO


# Returns offset or its reverse depending on whether it's pointing at the same
# direction as axisvec.
func get_grab_offset_for_axis(offset: Vector3, axisvec: Vector3) -> Vector3:
	if offset.length() == 0:
		return axisvec
	return offset if offset.angle_to(axisvec) < PI else -1 * offset
	

func get_scale_limit_vector(basisx: Vector3, basisy: Vector3, basisz: Vector3) -> Vector3:
	if (limit & GSRLimit.X):
		return Vector3(1.0, 0.0, 0.0) if !local else basisx
	if (limit & GSRLimit.Y):
		return Vector3(0.0, 1.0, 0.0) if !local else basisy
	if (limit & GSRLimit.Z):
		return Vector3(0.0, 0.0, 1.0) if !local else basisz
	return Vector3.ZERO


func get_limit_axis_reverse_plane(index: int) -> Plane:
	var v1: Vector3
	var v2: Vector3
	if (limit & GSRLimit.X):
		if !local || selection.size() <= index:
			v1 = Vector3(0.0, 1.0, 0.0)
			v2 = Vector3(0.0, 0.0, 1.0)
		else:
			v1 = selection[index].global_transform.basis.y.normalized()
			v2 = selection[index].global_transform.basis.z.normalized()
	elif (limit & GSRLimit.Y):
		if !local || selection.size() <= index:
			v1 = Vector3(1.0, 0.0, 0.0)
			v2 = Vector3(0.0, 0.0, 1.0)
		else:
			v1 = selection[index].global_transform.basis.x.normalized()
			v2 = selection[index].global_transform.basis.z.normalized()
	elif (limit & GSRLimit.Z):
		if !local || selection.size() <= index:
			v1 = Vector3(0.0, 1.0, 0.0)
			v2 = Vector3(1.0, 0.0, 0.0)
		else:
			v1 = selection[index].global_transform.basis.x.normalized()
			v2 = selection[index].global_transform.basis.y.normalized()
	return Plane(start_viewpoint, start_viewpoint + v1, start_viewpoint + v2)


func get_limit_axis_reverse_vectors(index: int) -> Array:
	var v1: Vector3
	var v2: Vector3
	if (limit & GSRLimit.X):
		if !local || selection.size() <= index:
			v1 = Vector3(0.0, 1.0, 0.0)
			v2 = Vector3(0.0, 0.0, 1.0)
		else:
			v1 = selection[index].global_transform.basis.y #- selection[index].global_transform.origin
			v2 = selection[index].global_transform.basis.z #- selection[index].global_transform.origin
	elif (limit & GSRLimit.Y):
		if !local || selection.size() <= index:
			v1 = Vector3(1.0, 0.0, 0.0)
			v2 = Vector3(0.0, 0.0, 1.0)
		else:
			v1 = selection[index].global_transform.basis.x #- selection[index].global_transform.origin
			v2 = selection[index].global_transform.basis.z #- selection[index].global_transform.origin
	elif (limit & GSRLimit.Z):
		if !local || selection.size() <= index:
			v1 = Vector3(1.0, 0.0, 0.0)
			v2 = Vector3(0.0, 1.0, 0.0)
		else:
			v1 = selection[index].global_transform.basis.x #- selection[index].global_transform.origin
			v2 = selection[index].global_transform.basis.y #- selection[index].global_transform.origin
	return [v1.normalized(), v2.normalized()]
	

func cancel_all():
	reset_scene_action()
	revert_manipulation()
	reset()


func finalize_manipulation():
	# Saving current transforms, and then resetting to original, so the undo
	# can do its magic with the two transforms.
	var selection_final_state = []
	for s in selection:
		selection_final_state.append(s.global_transform)
	revert_manipulation()
	
	var ur = get_undo_redo()
	ur.create_action("GSR Action")
	for ix in selection.size():
		var item = selection[ix]
		ur.add_do_property(item, "global_transform", selection_final_state[ix])
		ur.add_undo_property(item, "global_transform", item.global_transform)
	ur.commit_action()
	
	reset()


func reset():
	state = GSRState.NONE
	limit = GSRLimit.NONE
	local = false
	selection = []
	
	start_transform = []
	start_global_transform = []
	rotate_angle = 0.0
	numerics = ""
	
	spatialscene = null
	spatialparent = null
	
	show_gizmo()
	update_overlays()
	#Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	editor_camera = null

	mousepos_offset = Vector2.ZERO
	reference_mousepos = Vector2.ZERO


func offset_object(index: int, movedby: Vector3):
	selection[index].global_transform.origin += movedby


func rotate_object(index: int, angle: float, center: Vector3, axis: Vector3, in_place: bool):
	var obj = selection[index]
	
	var displaced
	if !in_place:
		displaced = obj.global_transform.origin - center
		var t := Transform().rotated(axis, angle)
		displaced = t.xform(displaced)
		
	obj.global_rotate(axis, angle)
	
	if !in_place:
		obj.global_transform.origin = displaced + center


func scale_object(index: int, scale: Vector3, pos_scale: Vector3, center: Vector3, in_place: bool):
	var obj = selection[index]
	obj.scale = Vector3(obj.transform.basis.x.length() * scale.x, obj.transform.basis.y.length() * scale.y, obj.transform.basis.z.length() * scale.z)
	
	obj.global_transform.origin = (obj.global_transform.origin - center) * pos_scale + center


func generate_grid_mesh():
	grid_mesh = GridMesh.new(self)


func free_grid_mesh():
	grid_mesh.free()
	grid_mesh = null


func check_grid():
	if grid_mesh == null:
		generate_grid_mesh()
	else:
		grid_mesh.update()

func update_grid_position(center):
	grid_mesh.transform.origin = center


func unpack_scene():
	var scene = get_editor_interface().get_edited_scene_root()
	if scene == null:
		return
		
	var dlg := FS.show_file_dialog(self, "Select Destination Folder", false)
	dlg.connect("dir_selected", self, "_on_unpack_dir_selected")
	dlg.connect("hide", self, "_on_dialog_closed", [dlg])


func _on_dialog_closed(dlg):
	dlg.queue_free()


func _on_unpack_dir_selected(dir):
	var scene = get_editor_interface().get_edited_scene_root()
	
	for ix in scene.get_child_count():
		var node = scene.get_child(ix)
		if !(node is Spatial):
			continue
		var name = node.name
		var unpacked = PackedScene.new()
		unpacked.pack(node)
		if ResourceSaver.save(dir + "/" + name + ".tscn", unpacked) == OK:
			print("Saving file: " + dir + "/" + name + ".tscn")
		else:
			print("Error. Failed to save " + dir + "/" + name + ".tscn")
