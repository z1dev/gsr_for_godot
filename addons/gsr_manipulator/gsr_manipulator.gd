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
const CrossMesh = preload("./mesh/cross_mesh.gd")


const TINY_VALE = 0.0001

# Separate script for stuff that needs to persist
var settings: PluginSettings = PluginSettings.new()


# Current manipulation of objects
enum GSRAction { NONE, GRAB, ROTATE, SCALE, SCENE_PLACE, SCENE_MOVE }
# Axis of manipulation
enum GSRLimit { NONE, X = 1, Y = 2, Z = 4, REVERSE = 8 }
# Spatial "tile" placement plane's floor normal.
enum GSRAxis {X = 1, Y = 2, Z = 4}

# Objects manipulated by this plugin are selected.
var selected := false
# Saved objects for hiding their gizmos.
var selected_objects: WeakRef = weakref(null)
# When set, the transform used to limit manipulation to an axis, instead of using the global axis
# for rotation or scale axis.
var limit_transform = null

# Manipulation method used from GSRAction values. Doesn't necessarily match the active method.
var action: int = GSRAction.NONE
# The currently used manipulation of spatials. This can be different from `state`, if it's
# temporarily switched to a different one. Cancelling or accepting the manipulation will return
# to the original state.
var active_action: int = GSRAction.NONE
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
# be restored on cancel or undo. The transformation is also restored on every
# manipulation frame.
var start_transform := []
# The global transform of each selected object when manipulation started.
var start_global_transform := []
# Same as start_transform but for scene grid snapping.
var grid_start_transform = null

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
# Offset of spatial node from the grid point during placement. The component of the current
# placement plane is the distance from the 0 coordinate on that plane.
var spatial_offset: Vector3
# Offset when changing limit to the normal of the placement plane.
var saved_offset: float

# Rotation of spatial node on the y axis when placing it on the grid.
#var spatial_rotation: float

# Normal vector direction of the placement grid of spatial nodes. Plane's distance
# from the 0 position is in `spatial_offset`.
var spatial_placement_plane: int = GSRAxis.Y

var grid_mesh = null
var cross_mesh = null


func _enter_tree():
	settings.connect("snap_settings_changed", self, "_on_snap_settings_changed")
	settings.load_config()
	add_toolbuttons()
	add_control_dock()
	register_callbacks(true)
	generate_meshes()


func _exit_tree():
	settings.disconnect("snap_settings_changed", self, "_on_snap_settings_changed")
	settings.save_config()
	register_callbacks(false)
	remove_toolbuttons()
	# Make sure we don't hold a reference of anything
	reset()
	selected_objects = weakref(null)
	remove_control_dock()
	free_meshes()


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


func _on_snap_settings_changed():
	spatial_offset = Vector3.ZERO
	check_grid()


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
	cancel_manipulation()


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
	return 1.0 / settings.grid_subdiv


func get_action_strength():
	if !smoothing:
		return 1.0
	return 0.1


func grab_step_size():
	return settings.grid_size * get_grab_action_strength()


func rotate_step_size():
	return 5.0 * get_action_strength()


func scale_step_size():
	return 0.1 * get_action_strength()


func tile_step_size(with_smoothing: bool):
	if !with_smoothing:
		return settings.grid_size
	return settings.grid_size / settings.grid_subdiv
	

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
			if action == GSRAction.NONE:
				return false
			save_manipulation_mousepos()
			smoothing = event.pressed
			return true
		elif event.scancode == KEY_CONTROL:
			if action == GSRAction.NONE:
				return false
			snap_toggle = event.pressed
			return true
		if !event.pressed:
			return false
		if selected && char(event.unicode) == 'g':
			if action in [GSRAction.GRAB, GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
				return false
			start_manipulation(camera, GSRAction.GRAB)
			saved_mousepos = mousepos
			return true
		if selected && char(event.unicode) == 'm':
			if get_current_action() != GSRAction.NONE:
				change_scene_manipulation(GSRAction.NONE)
			if action in [GSRAction.GRAB, GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
				return false
			start_scene_manipulation(camera)
		elif char(event.unicode) == 'r' && ((selected && action != GSRAction.ROTATE) || action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]):
			if action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
				change_scene_manipulation(GSRAction.ROTATE if active_action != GSRAction.ROTATE else GSRAction.NONE)
			else:
				start_manipulation(camera, GSRAction.ROTATE)
			saved_mousepos = mousepos
			return true
		elif char(event.unicode) == 's' && ((selected && action != GSRAction.SCALE) || action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]):
			if action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
				change_scene_manipulation(GSRAction.SCALE if active_action != GSRAction.SCALE else GSRAction.NONE)
			else:
				start_manipulation(camera, GSRAction.SCALE)
			saved_mousepos = mousepos
			return true
		elif !(action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]) && char(event.unicode) == 'a':
			start_scene_placement(camera)
			saved_mousepos = mousepos
			return true
		elif event.scancode == KEY_ESCAPE:
			cancel_manipulation()
			return true
		elif get_current_action() in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
			if (char(event.unicode) == 'x' || char(event.unicode) == 'X'):
				if spatial_placement_plane == GSRAxis.X:
					change_scene_limit(GSRLimit.X)
				else:
					change_scene_plane(GSRAxis.X)
			elif ((!settings.zy_swapped && (char(event.unicode) == 'y' || char(event.unicode) == 'Y')) ||
					(settings.zy_swapped && (char(event.unicode) == 'z' || char(event.unicode) == 'Z'))):
				if spatial_placement_plane == GSRAxis.Y:
					change_scene_limit(GSRLimit.Y)
				else:
					change_scene_plane(GSRAxis.Y)
			elif ((!settings.zy_swapped && (char(event.unicode) == 'z' || char(event.unicode) == 'Z')) ||
					(settings.zy_swapped && (char(event.unicode) == 'y' || char(event.unicode) == 'Y'))):
				if spatial_placement_plane == GSRAxis.Z:
					change_scene_limit(GSRLimit.Z)
				else:
					change_scene_plane(GSRAxis.Z)
			return true
		elif action != GSRAction.NONE:
			var newlimit = 0
			if event.scancode == KEY_ENTER || event.scancode == KEY_KP_ENTER:
				finalize_manipulation()
				return true
			elif char(event.unicode) == 'x' || char(event.unicode) == 'X':
				change_limit(GSRLimit.X | (GSRLimit.REVERSE if event.shift else 0))
				return true
			elif char(event.unicode) == 'y' || char(event.unicode) == 'Y':
				if !settings.zy_swapped:
					change_limit(GSRLimit.Y | (GSRLimit.REVERSE if event.shift else 0))
				else:
					change_limit(GSRLimit.Z | (GSRLimit.REVERSE if event.shift else 0))
				return true
			elif char(event.unicode) == 'z' || char(event.unicode) == 'Z':
				if !settings.zy_swapped:
					change_limit(GSRLimit.Z | (GSRLimit.REVERSE if event.shift else 0))
				else:
					change_limit(GSRLimit.Y | (GSRLimit.REVERSE if event.shift else 0))
				return true
			elif (char(event.unicode) >= '0' && char(event.unicode) <= '9' ||
					char(event.unicode) == '.' || char(event.unicode) == '-'):
				numeric_input(char(event.unicode))
				return true
			elif event.scancode == KEY_BACKSPACE:
				numeric_delete()
				return true
	
	elif event is InputEventMouseButton:
		if action != GSRAction.NONE:
			if !event.pressed:
				return
				
			if event.button_index == BUTTON_RIGHT:
				if get_current_action() in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE] && limit == spatial_placement_plane:
					cancel_scene_limit()
				else:
					cancel_manipulation()
				return true
			elif event.button_index == BUTTON_LEFT:
				if get_current_action() in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
					if limit == spatial_placement_plane:
						change_scene_limit(limit)
					else:
						finalize_scene_placement()
				else:
					finalize_manipulation()
				return true
#			elif snap_toggle && state == GSRAction.SCENE_PLACE && (event.button_index == BUTTON_WHEEL_UP ||
#					event.button_index == BUTTON_WHEEL_DOWN):
#				if event.is_pressed():
#					var dir = 1.0 if event.button_index == BUTTON_WHEEL_UP else -1.0
#					var amount = 15.0 if !smoothing else 5.0
#					spatial_rotation += dir * PI / 180.0 * amount
#					spatialscene.rotate_y(dir * PI / 180.0 * amount)
#				return true
	elif event is InputEventMouseMotion:
		mousepos = current_camera_position(event, camera)
		if action == GSRAction.NONE:
			saved_mousepos = mousepos
			return false
		
		if get_current_action() in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
			update_scene_placement()
			saved_mousepos = mousepos
			# Returning true here would prevent navigating the 3D view.
			return false
			
		elif get_current_action() != GSRAction.NONE:
			if numerics.empty():
				manipulate_selection()
				
		saved_mousepos = mousepos
		return action != GSRAction.NONE
			
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
		
	if action == GSRAction.NONE:
		return
		
	var f = overlay.get_font("font")
	var text: String
	
	if get_current_action() == GSRAction.GRAB:
		text = "[Grab]"
	elif get_current_action() == GSRAction.ROTATE:
		text = "[Rotate]"
	elif get_current_action() == GSRAction.SCALE:
		text = "[Scale]"
	elif get_current_action() == GSRAction.SCENE_PLACE:
		text = "[Grid Add]"
	elif get_current_action() == GSRAction.SCENE_MOVE:
		text = "[Grid Move]"
	
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

	if get_current_action() == GSRAction.GRAB:
		# The new center of selection, to calculate distance moved
		var center = Vector3.ZERO
		for ix in selection.size():
			center += selection[ix].global_transform.origin
		center /= selection.size()
		var dist = center - selection_center
		text += "  Distance: %.4f  Dx: %.4f  Dy: %.4f  Dz: %.4f" % [dist.length(), dist.x, dist.y, dist.z]
	elif get_current_action() == GSRAction.ROTATE:
		text += "  Deg: %.2f°" % [rotate_display]
	elif get_current_action() == GSRAction.SCALE:
		text += "  Scale: %.2f%%  Sx: %.4f  Sy: %.4f  Sz: %.4f" % [scale_display, scale_axis_display.x, scale_axis_display.y, scale_axis_display.z]
	elif get_current_action() in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
		text += "  Coords: (%.2f, %.2f, %.2f)" % [spatialscene.transform.origin.x, spatialscene.transform.origin.y, spatialscene.transform.origin.z]
		var cell = Vector3(int((abs(spatialscene.transform.origin.x) + TINY_VALE) / settings.grid_size),
				int(floor((abs(spatialscene.transform.origin.y) + TINY_VALE) / settings.grid_size)),
				int(floor((abs(spatialscene.transform.origin.z) + TINY_VALE) / settings.grid_size)))
		var stepsize = settings.grid_size / settings.grid_subdiv
		var step = Vector3(int((abs(spatialscene.transform.origin.x) + TINY_VALE - cell.x * settings.grid_size) / stepsize),
				int((abs(spatialscene.transform.origin.y) + TINY_VALE - cell.y * settings.grid_size) / stepsize),
				int((abs(spatialscene.transform.origin.z) + TINY_VALE - cell.z * settings.grid_size) / stepsize))
		var prefx = "-" if spatialscene.transform.origin.x < 0 else ""
		var prefy = "-" if spatialscene.transform.origin.y < 0 else ""
		var prefz = "-" if spatialscene.transform.origin.z < 0 else ""
		text += "  Cell x: %s%d.%d  y: %s%d.%d  z: %s%d.%d" % [prefx, int(cell.x), step.x,
				prefy, int(cell.y), step.y,
				prefz, int(cell.z), step.z]
		selection_centerpos = editor_camera.unproject_position(selection_center)
				
		
	overlay.draw_string(f, Vector2(16, 57), text, Color(0, 0, 0, 1))
	overlay.draw_string(f, Vector2(15, 56), text)
	
	if get_current_action() in [GSRAction.SCALE, GSRAction.ROTATE]:
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
	elif !(get_current_action() in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]):
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
	
	var global_axis = (!local || gtrans == null) || (get_current_action() == GSRAction.ROTATE && local && (limit & GSRLimit.REVERSE))
	
	var left: Vector3 = Vector3.LEFT
	var up: Vector3 = Vector3.UP
	var forward: Vector3 = Vector3.FORWARD
	if !global_axis:
		left = gtrans.basis.x.normalized()
		up = gtrans.basis.y.normalized()
		forward = gtrans.basis.z.normalized()
	elif limit_transform != null:
		left = limit_transform.basis.x.normalized()
		up = limit_transform.basis.y.normalized()
		forward = limit_transform.basis.z.normalized()
	
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
	if action != GSRAction.NONE:
		cancel_manipulation()
	
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

	action = GSRAction.SCENE_PLACE
	start_mousepos = mousepos
	
	spatialscene = ps.instance()
	spatialparent.add_child(spatialscene)

	editor_camera = camera	
	
	if grid_mesh != null:
		spatialparent.add_child(grid_mesh)
		spatialparent.add_child(cross_mesh)
		
	#spatialscene.rotate_y(spatial_rotation)
	
	hide_gizmo()
	update_scene_placement()


func start_scene_manipulation(camera: Camera):
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
	var objects = es.get_transformable_selected_nodes()
	if objects == null || objects.empty() || objects.size() > 1 || objects[0].get_parent() == null || !(objects[0].get_parent() is Spatial):
		return
				
	if action != GSRAction.NONE:
		cancel_manipulation()
	spatialscene = objects[0]
	spatialparent =  spatialscene.get_parent()
	action = GSRAction.SCENE_MOVE
	
	start_mousepos = mousepos
	editor_camera = camera	
	
	if grid_mesh != null:
		spatialparent.add_child(grid_mesh)
		spatialparent.add_child(cross_mesh)
	
	spatial_offset.x = fmod(spatialscene.transform.origin.x, tile_step_size(false))
	spatial_offset.y = fmod(spatialscene.transform.origin.y, tile_step_size(false))
	spatial_offset.z = fmod(spatialscene.transform.origin.z, tile_step_size(false))
	
	grid_start_transform = spatialscene.transform
	
	hide_gizmo()
	update_scene_placement()


func change_scene_manipulation(newaction):
	if !(action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]) || active_action == newaction:
		return
	if active_action != GSRAction.NONE || newaction == GSRAction.NONE:
		cancel_manipulation()
		
	active_action = newaction
	if newaction == GSRAction.NONE:
		return
		
	var dummy = [spatialscene]
	limit_transform = spatialparent.global_transform
	initialize_manipulation(dummy)


func start_manipulation(camera: Camera, newaction):
	if action != GSRAction.NONE:
		cancel_manipulation()
	
	editor_camera = camera
		
	action = newaction
	local = is_local_button_down()
	
	
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
	var spatials = []
	var objects = es.get_transformable_selected_nodes()
	for obj in objects:
		if obj is Spatial:
			spatials.append(obj)
	
	if spatials.empty():
		reset()
	else:
		hide_gizmo()
		initialize_manipulation(spatials)


func initialize_manipulation(spatials):
	start_mousepos = mousepos
	selection = spatials
	
	start_transform.resize(selection.size())
	start_global_transform.resize(selection.size())
	
	selection_center = Vector3.ZERO
	
	# Godot doesn't have defines, so I'm just adding a simple local variable here.
	# Alternate center is how Godot calculates the center of the selection. It's an unnatural
	# and strange choice, but it's easier to use this for the users when the default gizmo is
	# positioned there.
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
		
	selection_centerpos = editor_camera.unproject_position(selection_center)
	selection_distance = selection_center.distance_to(editor_camera.project_ray_origin(selection_centerpos))
	start_viewpoint = editor_camera.project_position(mousepos, selection_distance)
	
	update_overlays()
	#Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func change_scene_limit(newlimit):
	if !(action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]):
		return
		
	if limit != newlimit:
#		if limit == spatial_placement_plane:
#			cancel_scene_limit()
		saved_offset = vector_component(spatial_offset, newlimit)
		limit = newlimit
		limit_transform = spatialparent.global_transform
		update_scene_placement()
	else:
		limit = 0
		update_scene_placement()


func cancel_scene_limit():
	if !(action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]):
		return
		
	spatial_offset = set_vector_component(spatial_offset, limit, saved_offset)
	limit = 0
	update_scene_placement()


func change_scene_plane(newplane):
	if !(action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]) || spatial_placement_plane == newplane:
		return
	
	if limit != 0:
		change_scene_limit(0)
		
	if newplane != GSRAxis.X:
		spatial_offset.x = fmod(spatial_offset.x, tile_step_size(false))
	if newplane != GSRAxis.Y:
		spatial_offset.y = fmod(spatial_offset.y, tile_step_size(false))
	if newplane != GSRAxis.Z:
		spatial_offset.z = fmod(spatial_offset.z, tile_step_size(false))
		
	spatial_placement_plane = newplane
	spatial_offset = set_vector_component(spatial_offset, spatial_placement_plane, vector_component(spatialscene.transform.origin, spatial_placement_plane))
	update_grid_rotation()
	update_scene_placement()


func change_limit(newlimit):
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


func numeric_input(ch):
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


func numeric_delete():
	if numerics.empty():
		return
	
	if numerics[numerics.length() - 1] == ".":
		numerics = numerics.substr(0, numerics.length() - 1)
		return
		
	revert_manipulation()
	numerics = numerics.substr(0, numerics.length() - 1)
	apply_manipulation()


# Returns the axis of a spatial based on the GSRAxis axis parameter. Set global to false to get
# the local axis instead of the global vector.
func plane_axis(spatial, planeaxis, global = true):
	if global:
		return spatial.global_transform.basis.x if planeaxis == GSRAxis.X else (
				spatial.global_transform.basis.y if planeaxis == GSRAxis.Y else
				spatial.global_transform.basis.z)
	return spatial.transform.basis.x if planeaxis == GSRAxis.X else (
			spatial.transform.basis.y if planeaxis == GSRAxis.Y else
			spatial.transform.basis.z)


# Returns the component of a vector specified by the GSRAxis.
func vector_component(vec: Vector3, axis: int) -> float:
	if axis == GSRAxis.X:
		return vec.x
	if axis == GSRAxis.Y:
		return vec.y
	if axis == GSRAxis.Z:
		return vec.z
	return 0.0


# Returns the vector with a component specified by the GSRAxis updated to a new value.
func set_vector_component(vec: Vector3, axis: int, val: float) -> Vector3:
	if axis == GSRAxis.X:
		vec.x = val
	if axis == GSRAxis.Y:
		vec.y = val
	if axis == GSRAxis.Z:
		vec.z = val
	return vec


# Returns a plane from a normal and a point it should contain.
func plane_from_point(normal, point: Vector3):
	if normal == null || normal == Vector3.ZERO:
		return null
		
	return Plane(normal, Plane(normal, 0.0).distance_to(point))


func scene_placement_plane() -> Plane:
	return plane_from_point(plane_axis(spatialparent, spatial_placement_plane),
			spatialparent.global_transform.origin + spatial_offset)


func scene_placement_limited_plane():
	#var plane = plane_from_point(plane_axis(spatialparent, limit), spatialparent.global_transform.origin)
	return plane_from_point(editor_camera.global_transform.basis.z, spatialscene.global_transform.origin)


func vector_exclude_plane(vec: Vector3, plane: int):
	if plane == GSRAxis.X:
		return Vector3(0, vec.y, vec.z)
	if plane == GSRAxis.Y:
		return Vector3(vec.x, 0, vec.z)
	if plane == GSRAxis.Z:
		return Vector3(vec.x, vec.y, 0)


func update_scene_placement():
	if spatialscene == null:
		return
	
	if limit != spatial_placement_plane:
		var plane = scene_placement_plane()
				
		var point = plane.intersects_ray(editor_camera.project_ray_origin(mousepos),
				editor_camera.project_ray_normal(mousepos))
		if point == null:
			if grid_mesh != null:
				grid_mesh.visible = false
				cross_mesh.visible = false
			return
			
		point = spatialparent.to_local(point)
		if !smoothing:
			if spatial_placement_plane != GSRAxis.X:
				point.x -= spatial_offset.x
			if spatial_placement_plane != GSRAxis.Y:
				point.y -= spatial_offset.y
			if spatial_placement_plane != GSRAxis.Z:
				point.z -= spatial_offset.z
		# Coordinates on placement plane based on mouse position, snapped to a grid point.
		var place = vector_exclude_plane(Vector3(stepify(point.x, tile_step_size(false)),
				stepify(point.y, tile_step_size(false)),
				stepify(point.z, tile_step_size(false))), spatial_placement_plane)
		if smoothing:
			var smooth_place = vector_exclude_plane(Vector3(stepify(point.x, tile_step_size(true)),
					stepify(point.y, tile_step_size(true)),
					stepify(point.z, tile_step_size(true))) - place, spatial_placement_plane)
			if spatial_placement_plane != GSRAxis.X && (limit == 0 || limit == GSRAxis.X):
				spatial_offset.x = fmod(smooth_place.x, tile_step_size(false))
			if spatial_placement_plane != GSRAxis.Y && (limit == 0 || limit == GSRAxis.Y):
				spatial_offset.y = fmod(smooth_place.y, tile_step_size(false))
			if spatial_placement_plane != GSRAxis.Z && (limit == 0 || limit == GSRAxis.Z):
				spatial_offset.z = fmod(smooth_place.z, tile_step_size(false))
		if limit == 0:
			spatialscene.transform.origin = place + spatial_offset
		elif limit == GSRLimit.X:
			spatialscene.transform.origin.x = (place + spatial_offset).x
		elif limit == GSRLimit.Y:
			spatialscene.transform.origin.y = (place + spatial_offset).y
		else:
			spatialscene.transform.origin.z = (place + spatial_offset).z
			
		grid_mesh.visible = true
		cross_mesh.visible = true
		update_grid_position(spatialscene.transform.origin - vector_exclude_plane(spatial_offset, spatial_placement_plane))
		update_cross_position()
	else:
		var plane = scene_placement_limited_plane() 
		if plane == null:
			if grid_mesh != null:
				grid_mesh.visible = false
				cross_mesh.visible = false
			return
			
		var point = plane.intersects_ray(editor_camera.project_ray_origin(mousepos),
				editor_camera.project_ray_normal(mousepos))
		if point == null:
			if grid_mesh != null:
				grid_mesh.visible = false
				cross_mesh.visible = false
			return
		
		point = spatialparent.to_local(point)
		var place = Vector3(stepify(point.x, tile_step_size(true)), stepify(point.y, tile_step_size(true)), stepify(point.z, tile_step_size(true)))
		if limit == GSRLimit.X:
			spatial_offset.x = place.x
			spatialscene.transform.origin.x = place.x
		elif limit == GSRLimit.Y:
			spatial_offset.y = place.y
			spatialscene.transform.origin.y = place.y
		else:
			spatial_offset.z = place.z
			spatialscene.transform.origin.z = place.z
			
		grid_mesh.visible = true
		cross_mesh.visible = true
		update_grid_position(spatialscene.transform.origin - vector_exclude_plane(spatial_offset, spatial_placement_plane))
		
	selection_center = spatialscene.global_transform.origin
	selection_centerpos = editor_camera.unproject_position(selection_center)
	update_overlays()


func finalize_scene_placement():
	if spatialscene == null || spatialparent == null:
		reset_scene_action()
		return
	
	var transform = spatialscene.transform
	reset_scene_action()
	
	var ur = get_undo_redo()
	
	if action == GSRAction.SCENE_PLACE:
		ur.create_action("GSR Scene Placement")
		ur.add_do_method(self, "do_place_scene", spatial_file_path, spatialparent, transform)
		ur.add_undo_method(self, "undo_place_scene", spatialparent)
	else: # SCENE_MOVE
		ur.create_action("GSR Action")
		ur.add_do_property(spatialscene, "transform", transform)
		ur.add_undo_property(spatialscene, "transform", spatialscene.transform)		
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
	if !(get_current_action() in [GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE]) || selection.empty():
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
		if action == GSRAction.SCENE_PLACE:
			spatialscene.queue_free()
			spatialscene = null
		else: # SCENE_MOVE
			spatialscene.transform = grid_start_transform
	if grid_mesh != null && grid_mesh.get_parent() != null:
		grid_mesh.get_parent().remove_child(grid_mesh)
	if cross_mesh != null && cross_mesh.get_parent() != null:
		cross_mesh.get_parent().remove_child(cross_mesh)


func apply_manipulation():
	if !(get_current_action() in [GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE]) || selection.empty():
		return
	
	var camera := editor_camera
	
	var constant = null
	if !numerics.empty():
		constant = numerics.to_float()

	if get_current_action() == GSRAction.GRAB:
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
	elif get_current_action() == GSRAction.ROTATE:
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
	elif get_current_action() == GSRAction.SCALE:
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
	if !local && limit_transform != null:
		if (limit & GSRLimit.X):
			return limit_transform.basis.x.normalized()
		elif (limit & GSRLimit.Y):
			return limit_transform.basis.y.normalized()
		elif (limit & GSRLimit.Z):
			return limit_transform.basis.z.normalized()
		return Vector3.ZERO
		
	
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
	if !local && limit_transform != null:
		if (limit & GSRLimit.X):
			return limit_transform.basis.x.normalized()
		elif (limit & GSRLimit.Y):
			return limit_transform.basis.y.normalized()
		elif (limit & GSRLimit.Z):
			return limit_transform.basis.z.normalized()
		return Vector3.ZERO
	
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


# Cancels ongoing manipulation and grid snapping action, restoring old transform of involved
# spatials. If full_cancel is false and a spatial is being rotated/scaled inside the grid, only
# the rotation/scale is cancelled, not the grid action. Otherwise both are cancelled.
func cancel_manipulation(full_cancel = false):
	if get_current_action() in [GSRAction.GRAB, GSRAction.ROTATE, GSRAction.SCALE]:
		revert_manipulation()
	if (full_cancel || active_action == GSRAction.NONE) && action in [GSRAction.SCENE_PLACE, GSRAction.SCENE_MOVE]:
		reset_scene_action()
	reset(full_cancel)


# Applying grab, scale or rotate manipulation, so the spatials being manipulated take up their
# final position. In case manipulation is just the sub-action while placing a spatial in a grid,
# returns to that action instead, while keeping the new scale or rotation of the spatial.
func finalize_manipulation():
	if active_action == GSRAction.NONE:
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
	
	reset(active_action == GSRAction.NONE)


func reset(full_reset = true):
	if full_reset || active_action == GSRAction.NONE:
		# Reset these only if not in a sub-action.
		action = GSRAction.NONE
	
		grid_start_transform = null
		
		limit_transform = null
		
		spatialscene = null
		spatialparent = null
		
		snap_toggle = false
		
		show_gizmo()
		
		editor_camera = null

	# Values reset for every action.
	limit = GSRLimit.NONE
	rotate_angle = 0.0
	numerics = ""

	start_transform = []
	start_global_transform = []
	selection = []
	local = false
	active_action = GSRAction.NONE
	smoothing = false
	
	mousepos_offset = Vector2.ZERO
	reference_mousepos = Vector2.ZERO
	
	update_overlays()


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


func generate_meshes():
	grid_mesh = GridMesh.new(self)
	cross_mesh = CrossMesh.new(self)


func free_meshes():
	grid_mesh.free()
	grid_mesh = null
	cross_mesh.free()
	cross_mesh = null


func check_grid():
	if grid_mesh == null:
		generate_meshes()
	else:
		grid_mesh.update()
		cross_mesh.update()


# Rotate spatial placement grid based on placement plane. When rotation is 0, the
# grid is facing up on the local Y vector.
func update_grid_rotation():
	if grid_mesh == null:
		return
		
	if spatial_placement_plane == GSRAxis.Y:
		grid_mesh.rotation = Vector3.ZERO
	elif spatial_placement_plane == GSRAxis.Z:
		grid_mesh.rotation = Vector3(PI / 2, 0.0, 0.0)
	else:
		grid_mesh.rotation = Vector3(0.0, 0.0, PI / 2)


func update_grid_position(center):
	grid_mesh.transform.origin = center


func update_cross_position():
	cross_mesh.transform.origin = spatialscene.transform.origin
	cross_mesh.rotation = spatialscene.rotation


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


func get_current_action():
	return action if active_action == GSRAction.NONE else active_action

