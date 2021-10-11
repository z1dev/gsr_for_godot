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

const Interop = preload("./interop/interop.gd")
const UI = preload("./util/editor_ui.gd")
const FS = preload("./util/file_system.gd")
const Scene = preload("./util/scene.gd")
const PluginSettings = preload("./util/plugin_settings.gd")
const ControlDock = preload("./ui/control_dock.tscn")
const GridMesh = preload("./mesh/grid_mesh.gd")
const CrossMesh = preload("./mesh/cross_mesh.gd")


const MENU_INDEX_Z_UP = 0
const MENU_INDEX_SNAP_CONTROLS = 1
const MENU_INDEX_DEPTH_SELECT = 2
const MENU_INDEX_DEPTH_SELECT_OPTIONS = 4
const MENU_INDEX_UNPACK_SCENE = 6

const SELECTION_FRONT_FACING = 0
const SELECTION_BACK_FACING = 1
const SELECTION_COLLISION_SHAPE = 2
const SELECTION_LIGHT = 3
const SELECTION_CAMERA = 4
const SELECTION_RAYCAST = 5


const TINY_VALUE = 0.0001
# Minimum number of pixels, the mouse has to be away from the selection center
# when a scale manipulation starts. If the mouse is closer than this, a position
# this far from the center will be used.
const MINIMUM_MANIPULATION_MOUSE_DISTANCE = 10

const mouse_button_map = [BUTTON_LEFT, BUTTON_RIGHT, BUTTON_MIDDLE, BUTTON_XBUTTON1, BUTTON_XBUTTON2]
const mouse_button_mask = [BUTTON_MASK_LEFT, BUTTON_MASK_RIGHT, BUTTON_MASK_MIDDLE, BUTTON_MASK_XBUTTON1, BUTTON_MASK_XBUTTON2]

# A bit mask of currently pressed mouse buttons.
var mouse_button_pressed = 0	
	

# Separate script for stuff that needs to persist
var settings: PluginSettings = PluginSettings.new()


# Current manipulation of objects
enum GSRState { NONE, MANIPULATE, EXTERNAL_MANIPULATE, DUPLICATE, GRID_ADD, GRID_MOVE }
enum GSRAction { NONE, GRAB, SCALE, ROTATE }
# Axis of manipulation
enum GSRLimit { NONE, X = 1, Y = 2, Z = 4, REVERSE = 8 }
# Spatial "tile" placement plane's floor normal.
enum GSRAxis {X = 1, Y = 2, Z = 4}

# Objects manipulated by this plugin are selected.
var selected: bool = false

# When set, the transform used to limit manipulation to an axis, instead of using the global axis
# for rotation or scale axis.
var limit_transform = null

# Manipulation method used from GSRAction values. Doesn't necessarily match the active method.
var gsrstate: int = GSRState.NONE
# The currently used manipulation of spatials. This can be different from `action`, if it's
# temporarily switched to a different one. Cancelling or accepting the manipulation will
# return to the original action setting this to GSRAction.NONE.
var gsraction: int = GSRAction.NONE
# Axis of manipulation from GSRLimit
var limit: int = 0
# Objects being manipulated. Not the same as current selection, because this is
# only updated for manipulations and only contains transformable nodes.
var selection := []
# Using local axis or global
var local := false

# Ignoring all input as requested by an external plugin. When true, no input
# processing takes place.
var interop_ignore_input := false
# String id of the work taking place to broadcast through interop.
var interop_work: String = ""

# Only used during external action. List of actions that can be activated during
# the external action.
var external_allowed_actions = {}

# String parameter passed to external_request_manipulation()
var external_what: String
# Caller plugin passed to external_request_manipulation()
var external_caller = null
# Caller plugin callback function passed to external_request_manipulation()
var external_callback: String
# Saved value of selected before getting an external request.
var external_selected: bool = false

# Spatial nodes used for displaying a fake gizmo. Doesn't have the functionality
# of gizmos, just used for displaying the center of selection.
var gizmo_spatials := []

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
# Mouse position saved for calculating relative rotation.
var rotate_mousepos: Vector2
# Position in the viewport when manipulation starts. Computed from mousepos.
var start_viewpoint: Vector3
# Current mouse position
var mousepos: Vector2
# Distance of selection from the editor camera's plane.
var selection_distance := 0.0
# The transform of each selected object when manipulation started, so it can
# be restored on cancel or undo. The transformation is also restored on every
# manipulation frame.
var start_transform := []
# The global transform of each selected object when manipulation started.
var start_global_transform := []
# Array of transforms of the spatial moved during grid placement for undo-redo.
var grid_transforms = []
# Index in grid_transforms of current applied transformation to use in undo-redo.
var grid_undo_pos = -1

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

# Set when depth select is toggled. When true, gizmos will be invisible
# (that is, scaled to 0%).
var gizmodisabled = false
# Set to true during manipulation to mark gizmos hidden temporarily. Overriden
# by gizmodisabled if it's set to true.
var gizmohidden = false
# Used when hiding gizmos so their original size can be restored.
var saved_gizmo_size = -1

var undoredo_disabled = false
var hadundo = false
var hadredo = false

# Button added to toolbar for settings like the z key toggle.
var menu_button: MenuButton
# Sub-menu for selectable item options.
var sub_selectable: PopupMenu

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

# Normal vector direction of the placement grid of spatial nodes. Plane's distance
# from the 0 position is in `spatial_offset`.
var spatial_placement_plane: int = GSRAxis.Y

# Meshes not added to the final scene tree, used as helpers when manipulating.
var grid_mesh = null
var cross_mesh = null

# Node last selected in the 3d viewport by clicking when using depth select.
var mouse_select_last = null

# Mouse position for the last depth select action.
var mouse_select_last_pos
# Transformation of camera for the last depth select action.
var mouse_select_camera_transform: Transform

# Maximum distance the mouse can be away from mouse_select_last_pos for the depth select to
# pick one after the last selected
const MOUSE_SELECT_RESET_DISTANCE = 5


func _enter_tree():
	Interop.register(self, "gsr")
	settings.connect("snap_settings_changed", self, "_on_snap_settings_changed")
	settings.load_config()
	
	saved_gizmo_size = settings.saved_gizmo_size
	if saved_gizmo_size != -1:
		UI.set_setting(self, "editors/3d/manipulator_gizmo_size", saved_gizmo_size)
	
	add_toolbuttons()
	add_control_dock()
	register_callbacks(true)
	generate_meshes()
	if settings.depth_select:
		update_depth_select(true)
	
	var es = get_editor_interface().get_selection()
	es.connect("selection_changed", self, "_on_editor_selection_changed")
	var local_button: ToolButton = UI.spatial_use_local_toolbutton(self)
	local_button.connect("toggled", self, "_on_local_button_toggled")
	get_undo_redo().connect("version_changed", self, "_on_undo_redo")
	set_input_event_forwarding_always_enabled()


func _exit_tree():
	get_undo_redo().disconnect("version_changed", self, "_on_undo_redo")
	var local_button: ToolButton = UI.spatial_use_local_toolbutton(self)
	local_button.disconnect("toggled", self, "_on_local_button_toggled")
	
	var es = get_editor_interface().get_selection()
	es.disconnect("selection_changed", self, "_on_editor_selection_changed")
	
	settings.disconnect("snap_settings_changed", self, "_on_snap_settings_changed")
	settings.saved_gizmo_size = saved_gizmo_size if gizmodisabled || gizmohidden else -1
	update_depth_select(false)
	settings.save_config()
	register_callbacks(false)
	remove_toolbuttons()
	# Make sure we don't hold a reference of anything
	reset()
	remove_control_dock()
	free_meshes()
	Interop.deregister(self)


func _interop_notification(caller_plugin_id: String, code: int, id: String, args):
	match code:
		Interop.NOTIFY_CODE_REQUEST_IGNORE_INPUT:
			interop_ignore_input = true
		Interop.NOTIFY_CODE_ALLOW_INPUT:
			interop_ignore_input = false


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
		popup.name = "GSR_MainMenu"
		
		sub_selectable = PopupMenu.new()
		sub_selectable.name = "GSR_SelectableSubmenu"
		
		popup.add_check_item("Z for up")
		popup.set_item_tooltip(MENU_INDEX_Z_UP, "Swap z and y axis-lock shortcuts")
		popup.set_item_checked(MENU_INDEX_Z_UP, settings.zy_swapped)
		
		popup.add_check_item("Snap options")
		popup.set_item_tooltip(MENU_INDEX_SNAP_CONTROLS, "Show snapping options in 3D editor")
		popup.set_item_checked(MENU_INDEX_SNAP_CONTROLS, settings.snap_controls_shown)
		
		popup.add_check_item("Depth select")
		popup.set_item_tooltip(MENU_INDEX_DEPTH_SELECT, "Cycle through objects when left-clicking at the same position.\nWarning: This disables built in gizmos")
		popup.set_item_checked(MENU_INDEX_DEPTH_SELECT, settings.depth_select)
		
		popup.add_separator()
		
		popup.add_child(sub_selectable)
		popup.add_submenu_item("Selectable", "GSR_SelectableSubmenu")
		
		sub_selectable.add_check_item("Front-facing mesh")
		sub_selectable.set_item_tooltip(SELECTION_FRONT_FACING, "Select nodes when clicking on their front-facing triangle")
		sub_selectable.set_item_checked(SELECTION_FRONT_FACING, settings.select_front_facing)
		
		sub_selectable.add_check_item("Back-facing mesh")
		sub_selectable.set_item_tooltip(SELECTION_BACK_FACING, "Select nodes when clicking on their back-facing triangle")
		sub_selectable.set_item_checked(SELECTION_BACK_FACING, settings.select_back_facing)

		sub_selectable.add_check_item("Collision shape")
		sub_selectable.set_item_tooltip(SELECTION_COLLISION_SHAPE, "Select nodes when clicking on collision shapes")
		sub_selectable.set_item_checked(SELECTION_COLLISION_SHAPE, settings.select_collision)

		sub_selectable.add_check_item("Light")
		sub_selectable.set_item_tooltip(SELECTION_LIGHT, "Select nodes when clicking on lights")
		sub_selectable.set_item_checked(SELECTION_LIGHT, settings.select_light)

		sub_selectable.add_check_item("Camera")
		sub_selectable.set_item_tooltip(SELECTION_CAMERA, "Select nodes when clicking on cameras")
		sub_selectable.set_item_checked(SELECTION_CAMERA, settings.select_camera)

		sub_selectable.add_check_item("RayCast")
		sub_selectable.set_item_tooltip(SELECTION_RAYCAST, "Select nodes when clicking on raycasts")
		sub_selectable.set_item_checked(SELECTION_RAYCAST, settings.select_raycast)

		popup.add_separator()
		
		popup.add_item("Unpack scene...")
		popup.set_item_tooltip(MENU_INDEX_UNPACK_SCENE, "Save child scenes in their own scene files.")
		
		
		UI.spatial_toolbar(self).add_child(menu_button)
		popup.connect("index_pressed", self, "_on_menu_button_popup_index_pressed")
		sub_selectable.connect("index_pressed", self, "_on_sub_selectable_popup_index_pressed")


func _on_menu_button_popup_index_pressed(index: int):
	var popup = menu_button.get_popup()
	
	match index:
		MENU_INDEX_Z_UP:
			popup.set_item_checked(index, !popup.is_item_checked(index))
			settings.zy_swapped = popup.is_item_checked(index)
		MENU_INDEX_SNAP_CONTROLS:
			popup.set_item_checked(index, !popup.is_item_checked(index))
			settings.snap_controls_shown = popup.is_item_checked(index)
			update_control_dock()
		MENU_INDEX_DEPTH_SELECT:
			popup.set_item_checked(index, !popup.is_item_checked(index))
			settings.depth_select = popup.is_item_checked(index)
			update_depth_select(settings.depth_select)
		MENU_INDEX_UNPACK_SCENE:
			unpack_scene()


func _on_sub_selectable_popup_index_pressed(index: int):
	match index:
		SELECTION_FRONT_FACING:
			sub_selectable.set_item_checked(index, !sub_selectable.is_item_checked(index))
			settings.select_front_facing = sub_selectable.is_item_checked(index)
		SELECTION_BACK_FACING:
			sub_selectable.set_item_checked(index, !sub_selectable.is_item_checked(index))
			settings.select_back_facing = sub_selectable.is_item_checked(index)
		SELECTION_COLLISION_SHAPE:
			sub_selectable.set_item_checked(index, !sub_selectable.is_item_checked(index))
			settings.select_collision = sub_selectable.is_item_checked(index)
		SELECTION_LIGHT:
			sub_selectable.set_item_checked(index, !sub_selectable.is_item_checked(index))
			settings.select_light = sub_selectable.is_item_checked(index)
		SELECTION_CAMERA:
			sub_selectable.set_item_checked(index, !sub_selectable.is_item_checked(index))
			settings.select_camera = sub_selectable.is_item_checked(index)
		SELECTION_RAYCAST:
			sub_selectable.set_item_checked(index, !sub_selectable.is_item_checked(index))
			settings.select_raycast = sub_selectable.is_item_checked(index)


func remove_toolbuttons():
	if menu_button != null:
		if menu_button.get_parent() != null:
			menu_button.get_parent().remove_child(menu_button)
		menu_button.free()
		menu_button = null


func _on_snap_settings_changed():
	spatial_offset = Vector3.ZERO
	check_grid()


func register_callbacks(register: bool):
	if register:
		connect("main_screen_changed", self, "_on_main_screen_changed")
	else:
		disconnect("main_screen_changed", self, "_on_main_screen_changed")
	pass


func _on_main_screen_changed(name: String):
	update_control_dock()


func update_control_dock():
	control_dock.visible = settings.snap_controls_shown && UI.current_main_screen(self) == "3D"


func _on_editor_selection_changed():
	var es = get_editor_interface().get_selection()
	gizmo_spatials = es.get_transformable_selected_nodes()
	update_cross_transform()


func _on_local_button_toggled(button_pressed: bool):
	update_cross_transform()
	

func handles(object):
	if object != null:
		var ei = get_editor_interface()
		var es = ei.get_selection()
		var nodes = es.get_transformable_selected_nodes()
		for n in nodes:
			if n is Spatial:
				return true
		if object is Spatial:
			return true

	return object == null


func make_visible(visible):
	if gsrstate == GSRState.EXTERNAL_MANIPULATE || selected == visible:
		return
		
	selected = visible
	if !visible:
		show_gizmo()
		enable_undoredo()
		
	if cross_mesh != null && cross_mesh.get_parent() != null:
		cross_mesh.get_parent().remove_child(cross_mesh)


func _on_undo_redo():
	update_cross_transform()


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


func set_gizmo_disabled(disable):
	if gizmodisabled == disable:
		return
		
	gizmodisabled = disable
	
	var dlg = UI.get_editor_settings_dialog(self)
	if gizmodisabled:
		dlg.connect("visibility_changed", self, "_on_editor_visibility_changed")
	else:
		dlg.disconnect("visibility_changed", self, "_on_editor_visibility_changed")
	
	if gizmohidden:
		return

	__set_gizmo_visibility(!gizmodisabled)
	_on_editor_selection_changed()
	

func _on_editor_visibility_changed():
	var dlg = UI.get_editor_settings_dialog(self)
	__set_gizmo_visibility(dlg.visible)


func hide_gizmo():
	if gizmohidden:
		return

	gizmohidden = true

	if gizmodisabled:
		return
		
	__set_gizmo_visibility(false)
	_on_editor_selection_changed()
	

func show_gizmo():
	if !gizmohidden:
		return

	gizmohidden = false

	if gizmodisabled:
		return
		
	__set_gizmo_visibility(true)
	_on_editor_selection_changed()


# Inner method to scale unscale gizmo. Don't call directly.
func __set_gizmo_visibility(to_visible):
	if to_visible:
		UI.set_setting(self, "editors/3d/manipulator_gizmo_size", saved_gizmo_size)
		saved_gizmo_size = UI.get_setting(self, "editors/3d/manipulator_gizmo_size")
	else:
		saved_gizmo_size = UI.get_setting(self, "editors/3d/manipulator_gizmo_size")
		UI.set_setting(self, "editors/3d/manipulator_gizmo_size", 0)


func disable_undoredo():
	if undoredo_disabled:
		return
	hadundo = UI.is_undo_enabled(self)
	hadredo = UI.is_redo_enabled(self)
	UI.disable_undoredo(self, hadundo, hadredo)
	undoredo_disabled = true


func enable_undoredo():
	if !undoredo_disabled:
		return
	UI.enable_undoredo(self, hadundo, hadredo)
	undoredo_disabled = false


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
	

# Getting around an issue (bug?) in Godot that sends the same input event twice.
var last_input_event_id = 0
func forward_spatial_gui_input(camera, event):
	if interop_ignore_input && gsrstate != GSRState.EXTERNAL_MANIPULATE:
		# Asked to not react to input from other plugins.
		
		if event is InputEventMouseMotion:
			mousepos = current_camera_position(event, camera)		
		if event is InputEventMouseButton:
				# Storing pressed mouse button index helps preventing clashes with
				# Godot functionality like free look.
				var button_index = mouse_button_map.find(event.button_index)
				if button_index != -1:
					if event.pressed:
						mouse_button_pressed |= mouse_button_mask[button_index]
					else:
						mouse_button_pressed &= ~mouse_button_mask[button_index]
		return false
		
	# Getting around an issue (bug?) in Godot that sends the same input event twice.
	if last_input_event_id == event.get_instance_id():
		return true
	last_input_event_id = event.get_instance_id()
	
	if event is InputEventKey:
		if mouse_button_pressed != 0:
			return false
		
		if event.echo:
			return false
		
		if event.scancode == KEY_SHIFT:
			if gsraction == GSRAction.NONE:
				return false
			save_manipulation_mousepos()
			smoothing = event.pressed
			return true
		elif event.scancode == KEY_CONTROL:
			if gsraction == GSRAction.NONE:
				return false
			snap_toggle = event.pressed
			return true
		if !event.pressed:
			return false
		if event.scancode == KEY_PAGEUP:
			if selected && gsraction == GSRAction.NONE:
				var sel = get_editor_interface().get_selection().get_transformable_selected_nodes()
				if sel == null || sel.empty():
					return false
				for s in sel:
					if s != get_editor_interface().get_edited_scene_root():
						Scene.clear_selection(self)
						Scene.set_selected(self, s.get_parent(), true)
				return true
		elif selected && char(event.unicode) == 'g':
			if (gsraction == GSRAction.GRAB ||
					(gsrstate == GSRState.EXTERNAL_MANIPULATE && !external_allowed_actions.has(GSRAction.GRAB))):
				return false
			if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
				change_scene_manipulation(GSRAction.GRAB)
			elif gsrstate in [GSRState.MANIPULATE, GSRState.EXTERNAL_MANIPULATE, GSRState.DUPLICATE]:
				change_manipulation(GSRAction.GRAB)
			else:
				start_manipulation(camera, GSRAction.GRAB)
			return true
		elif selected && char(event.unicode) == 'D':
			if gsraction != GSRAction.NONE:
				return false
			start_duplication(camera)
			return true
		elif char(event.unicode) == 'r':
			if ((!selected && !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE])) ||
					gsrstate == GSRState.EXTERNAL_MANIPULATE && !external_allowed_actions.has(GSRAction.ROTATE)):
				return false
			if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
				change_scene_manipulation(GSRAction.ROTATE if gsraction != GSRAction.ROTATE else GSRAction.GRAB)
			elif gsrstate in [GSRState.MANIPULATE, GSRState.EXTERNAL_MANIPULATE, GSRState.DUPLICATE]:
				change_manipulation(GSRAction.ROTATE)
			else:
				start_manipulation(camera, GSRAction.ROTATE)
			return true
		elif char(event.unicode) == 's':
			if ((!selected && !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE])) ||
					gsrstate == GSRState.EXTERNAL_MANIPULATE && !external_allowed_actions.has(GSRAction.SCALE)):
				return false
			if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
				change_scene_manipulation(GSRAction.SCALE if gsraction != GSRAction.SCALE else GSRAction.GRAB)
			elif gsrstate in [GSRState.MANIPULATE, GSRState.EXTERNAL_MANIPULATE, GSRState.DUPLICATE]:
				change_manipulation(GSRAction.SCALE)
			else:
				start_manipulation(camera, GSRAction.SCALE)
			return true
		elif char(event.unicode) == 'a':
			if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE, GSRState.EXTERNAL_MANIPULATE, GSRState.DUPLICATE]:
				return false
			start_scene_placement(camera)
			return true
		elif char(event.unicode) == 'd':
			if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE, GSRState.EXTERNAL_MANIPULATE, GSRState.DUPLICATE]:
				return false
			start_duplicate_placement(camera)
			return true
		elif selected && char(event.unicode) == 'm':
			if gsrstate in [GSRState.GRID_ADD, GSRState.EXTERNAL_MANIPULATE, GSRState.DUPLICATE] || gsraction == GSRAction.GRAB:
				return false
			if gsrstate in [GSRState.GRID_MOVE]:
				change_scene_manipulation(GSRAction.GRAB)
			else:
				start_scene_manipulation(camera)
			return false
		elif event.scancode == KEY_ESCAPE:
			input_cancel()
			return true
		elif gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE] && gsraction == GSRAction.GRAB:
			if event.scancode == KEY_ENTER || event.scancode == KEY_KP_ENTER:
				input_accept()
				return true
			if event.scancode == KEY_Z && event.control && event.shift:
				if grid_undo_pos < grid_transforms.size() - 1:
					grid_undo_pos += 1
					var o = spatialscene.transform.origin
					spatialscene.transform = grid_transforms[grid_undo_pos]
					spatialscene.transform.origin = o
			elif event.scancode == KEY_Z && event.control:
				if grid_undo_pos > 0:
					grid_undo_pos -= 1
					var o = spatialscene.transform.origin
					spatialscene.transform = grid_transforms[grid_undo_pos]
					spatialscene.transform.origin = o
			elif (char(event.unicode) == 'x' || char(event.unicode) == 'X'):
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
		elif gsraction in [GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE]:
			var newlimit = 0
			if event.scancode == KEY_ENTER || event.scancode == KEY_KP_ENTER:
				input_accept()
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
		# Storing pressed mouse button index helps preventing clashes with
		# Godot functionality like free look.
		var button_index = mouse_button_map.find(event.button_index)
		if button_index != -1:
			if event.pressed:
				mouse_button_pressed |= mouse_button_mask[button_index]
			else:
				mouse_button_pressed &= ~mouse_button_mask[button_index]
			
		if gsraction != GSRAction.NONE:
			if event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN] && !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]):
				return true
			
			if !event.pressed:
				return true
				
			if event.button_index == BUTTON_RIGHT:
				input_cancel()
				return true
			elif event.button_index == BUTTON_LEFT:
				input_accept()
				return true
		else:
			assert(gsrstate != GSRState.EXTERNAL_MANIPULATE, "External action is not allowed when action is NONE")
			if event.button_index == BUTTON_LEFT && settings.depth_select:
				if event.pressed:
					editor_camera = camera
					start_mousepos = mousepos
					return true
				
				if start_mousepos != mousepos && editor_camera == camera:
					return false
					
				var select_flags = 0
				if settings.select_front_facing:
					select_flags |= Scene.MOUSE_SELECT_FRONT_FACING_TRIANGLES
				if settings.select_back_facing:
					select_flags |= Scene.MOUSE_SELECT_BACK_FACING_TRIANGLES
				if settings.select_collision:
					select_flags |= Scene.MOUSE_SELECT_COLLISION_SHAPE
				if settings.select_light:
					select_flags |= Scene.MOUSE_SELECT_LIGHT
				if settings.select_camera:
					select_flags |= Scene.MOUSE_SELECT_CAMERA
				if settings.select_raycast:
					select_flags |= Scene.MOUSE_SELECT_RAYCAST
				
				if event.shift:
					mouse_select_last = Scene.mouse_select_spatial(self, camera, mousepos, [grid_mesh, cross_mesh], select_flags)
				else:
					if (mouse_select_last_pos == null || mouse_select_last_pos.distance_to(mousepos) > MOUSE_SELECT_RESET_DISTANCE) || camera.transform != mouse_select_camera_transform:
						select_flags |= Scene.MOUSE_SELECT_RESET
					mouse_select_last = Scene.mouse_select_spatial(self, camera, mousepos, [grid_mesh, cross_mesh], select_flags, mouse_select_last)
				
				mouse_select_last_pos = mousepos
				mouse_select_camera_transform = camera.transform
				
				if mouse_select_last != null:
					if event.shift:
						Scene.set_selected(self, mouse_select_last, !Scene.is_node_selected(self, mouse_select_last))
					else:
						Scene.clear_selection(self)
						Scene.set_selected(self, mouse_select_last, true)
				else:
					Scene.clear_selection(self)
				return true
					
	elif event is InputEventMouseMotion:
		mousepos = current_camera_position(event, camera)
		if gsraction == GSRAction.NONE:
			assert(gsrstate != GSRState.EXTERNAL_MANIPULATE, "External action is not allowed when action is NONE")
			return false
		
		if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE] && gsraction == GSRAction.GRAB:
			update_scene_placement()
			# Returning true here would prevent navigating the 3D view.
			return false
		elif gsraction != GSRAction.NONE:
			if numerics.empty():
				manipulate_selection()
			else:
				update_overlays()
				
		return gsraction != GSRAction.NONE
			
	return false


# User pressed esc or right clicked to cancel manipulations.
func input_cancel():
	if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
		if gsraction == GSRAction.GRAB && limit == spatial_placement_plane:
			cancel_scene_limit()
		elif gsraction != GSRAction.GRAB:
			change_scene_manipulation(GSRAction.NONE)
		else:
			cancel_manipulation()
	else:
		external_cancel()
		cancel_manipulation()
	

# User pressed enter or clicked with left mouse button to accept the manipulation.
func input_accept():
	if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
		if gsraction in [GSRAction.SCALE, GSRAction.ROTATE]:
			change_scene_manipulation(GSRAction.GRAB)
		elif limit == spatial_placement_plane:
			change_scene_limit(limit)
		else:
			finalize_scene_placement()
	else:
		finalize_manipulation()
	

# Returns the screen position of event relative to editor_camera instead of the
# camera, which the event corresponds
func current_camera_position(event: InputEventMouseMotion, camera: Camera) -> Vector2:
	if camera == editor_camera || editor_camera == null:
		return event.position
	return editor_camera.get_parent().get_parent().get_local_mouse_position()


func forward_spatial_draw_over_viewport(overlay: Control):
	var overlay_camera = overlay.get_parent().get_child(0).get_child(0).get_child(0) as Camera
	
	# Hack to check if this overlay is the one we use right now:
	if !is_instance_valid(editor_camera) || overlay_camera != editor_camera:
		return
		
	if gsraction == GSRAction.NONE:
		return
		
	var f = overlay.get_font("font")
	var text: String
	
	if gsraction == GSRAction.GRAB:
		if gsrstate == GSRState.GRID_ADD:
			text = "[Grid Add]"
		elif gsrstate == GSRState.GRID_MOVE:
			text = "[Grid Move]"
		else:
			text = "[Grab]"
	elif gsraction == GSRAction.ROTATE:
		text = "[Rotate]"
	elif gsraction == GSRAction.SCALE:
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

	if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE] && gsraction == GSRAction.GRAB:
		text += "  Coords: (%.2f, %.2f, %.2f)" % [spatialscene.transform.origin.x, spatialscene.transform.origin.y, spatialscene.transform.origin.z]
		var cell = Vector3(int((abs(spatialscene.transform.origin.x) + TINY_VALUE) / settings.grid_size),
				int(floor((abs(spatialscene.transform.origin.y) + TINY_VALUE) / settings.grid_size)),
				int(floor((abs(spatialscene.transform.origin.z) + TINY_VALUE) / settings.grid_size)))
		var stepsize = settings.grid_size / settings.grid_subdiv
		var step = Vector3(int((abs(spatialscene.transform.origin.x) + TINY_VALUE - cell.x * settings.grid_size) / stepsize),
				int((abs(spatialscene.transform.origin.y) + TINY_VALUE - cell.y * settings.grid_size) / stepsize),
				int((abs(spatialscene.transform.origin.z) + TINY_VALUE - cell.z * settings.grid_size) / stepsize))
		var prefx = "-" if spatialscene.transform.origin.x < 0 else ""
		var prefy = "-" if spatialscene.transform.origin.y < 0 else ""
		var prefz = "-" if spatialscene.transform.origin.z < 0 else ""
		text += "  Cell x: %s%d.%d  y: %s%d.%d  z: %s%d.%d" % [prefx, int(cell.x), step.x,
				prefy, int(cell.y), step.y,
				prefz, int(cell.z), step.z]
		selection_centerpos = Scene.unproject(editor_camera, selection_center)
	elif gsraction == GSRAction.GRAB:
		# The new center of selection, to calculate distance moved
		var center = Vector3.ZERO
		for ix in selection.size():
			center += selection[ix].global_transform.origin
		center /= selection.size()
		var dist = center - selection_center
		text += "  Distance: %.4f  Dx: %.4f  Dy: %.4f  Dz: %.4f" % [dist.length(), dist.x, dist.y, dist.z]
	elif gsraction == GSRAction.ROTATE:
		text += "  Deg: %.2f°" % [rotate_display]
	elif gsraction == GSRAction.SCALE:
		text += "  Scale: %.2f%%  Sx: %.4f  Sy: %.4f  Sz: %.4f" % [scale_display, scale_axis_display.x, scale_axis_display.y, scale_axis_display.z]
				
		
	overlay.draw_string(f, Vector2(16, 57), text, Color(0, 0, 0, 1))
	overlay.draw_string(f, Vector2(15, 56), text)
	
	if gsraction in [GSRAction.SCALE, GSRAction.ROTATE]:
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
	elif !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]) || gsraction != GSRAction.GRAB:
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
	var centerpos = selection_centerpos if gtrans == null else Scene.unproject(editor_camera, center)
	
	# x red
	# z blue
	# y green
	var color = Color(1, 0.6, 0.6, 1) if which == GSRLimit.X else \
			(Color(0.6, 1, 0.6, 1) if which == GSRLimit.Y else Color(0.6, 0.6, 1, 1))
	
	var global_axis = (!local || gtrans == null) || (gsraction == GSRAction.ROTATE && local && (limit & GSRLimit.REVERSE))
	
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
	
	var xaxis = (centerpos - Scene.unproject(editor_camera, center + left * 10000.0)).normalized()
	var yaxis = (centerpos - Scene.unproject(editor_camera, center + up * 10000.0)).normalized()
	var zaxis = (centerpos - Scene.unproject(editor_camera, center + forward * 10000.0)).normalized()
	
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


func start_duplicate_placement(camera: Camera):
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
	var objects = es.get_transformable_selected_nodes()
	if (objects == null || objects.empty() || objects.size() > 1 || !(objects[0] is Spatial) ||
			objects[0].filename.empty() || objects[0].get_parent() == null ||
			!(objects[0].get_parent() is Spatial)):
		return
	
	if gsraction != GSRAction.NONE:
		cancel_manipulation()
	
	gsrstate = GSRState.GRID_ADD
	
	interop_work = "gsr_grid_duplicate"
	Interop.start_work(self, interop_work)
	
	initialize_scene_placement(camera, objects[0].filename, objects[0].get_parent())
	if spatialscene != null:
		spatial_offset = (vmod(vector_exclude_plane(objects[0].transform.origin, spatial_placement_plane),
				tile_step_size(false)) + vector_plane(objects[0].transform.origin, spatial_placement_plane))
		spatialscene.transform = objects[0].transform
		update_scene_placement()
		

func start_scene_placement(camera: Camera):
	# Get the selected scene in the file system that can be instanced.
	var path = UI.fs_selected_path(self)
	if path.empty():
		return
	
	var ei = get_editor_interface()
	var es = ei.get_selection()
	var objects = es.get_transformable_selected_nodes()
	
	var parent = null
	
	if objects == null || objects.empty():
		var root = ei.get_edited_scene_root()
		if !(root is Spatial):
			return
		parent = root
	elif objects.size() == 1:
		if !(objects[0] is Spatial):
			return
		parent = objects[0];
	
	if parent == null:
		return
	
	if gsraction != GSRAction.NONE:
		cancel_manipulation()
	
	gsrstate = GSRState.GRID_ADD
	
	interop_work = "gsr_scene_placemennt"
	Interop.start_work(self, interop_work)
	initialize_scene_placement(camera, path, parent)


func initialize_scene_placement(camera: Camera, path: String, parent: Spatial):
	# Get the selected scene in the file system that can be instanced.
	if camera == null || path.empty() || parent == null:
		return
	
	var ps := get_placement_scene(path)
	if ps == null:
		return
		
	gsraction = GSRAction.GRAB
	spatial_file_path = path
	
	spatialscene = ps.instance()
	spatialparent = parent

	start_mousepos = mousepos
	
	spatialparent.add_child(spatialscene)

	editor_camera = camera	
	
	if grid_mesh != null:
		spatialparent.add_child(grid_mesh)
		
	hide_gizmo()
	disable_undoredo()
	update_scene_placement()
	
	grid_transforms = [spatialscene.transform]
	grid_undo_pos = 0


func start_scene_manipulation(camera: Camera):
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
	var objects = es.get_transformable_selected_nodes()
	if (objects == null || objects.empty() || objects.size() > 1 || objects[0].get_parent() == null ||
			!(objects[0].get_parent() is Spatial)):
		return

	if gsraction != GSRAction.NONE:
		cancel_manipulation()

	interop_work = "gsr_grid"
	Interop.start_work(self, interop_work)
				
	spatialscene = objects[0]
	spatialparent =  spatialscene.get_parent()
	
	gsrstate = GSRState.GRID_MOVE
	gsraction = GSRAction.GRAB
	
	start_mousepos = mousepos
	editor_camera = camera	
	
	if grid_mesh != null:
		spatialparent.add_child(grid_mesh)
	
	if spatial_placement_plane != GSRLimit.X:
		spatial_offset.x = fmod(spatialscene.transform.origin.x + TINY_VALUE, tile_step_size(false))
	else:
		spatial_offset.x = stepify(spatialscene.transform.origin.x + TINY_VALUE, tile_step_size(false))
	if spatial_placement_plane != GSRLimit.Y:
		spatial_offset.y = fmod(spatialscene.transform.origin.y + TINY_VALUE, tile_step_size(false))
	else:
		spatial_offset.y = stepify(spatialscene.transform.origin.y + TINY_VALUE, tile_step_size(false))
	if spatial_placement_plane != GSRLimit.Z:
		spatial_offset.z = fmod(spatialscene.transform.origin.z + TINY_VALUE, tile_step_size(false))
	else:
		spatial_offset.z = stepify(spatialscene.transform.origin.z + TINY_VALUE, tile_step_size(false))
	grid_transforms = [spatialscene.transform]
	grid_undo_pos = 0
	
	hide_gizmo()
	disable_undoredo()
	update_scene_placement()


func change_scene_manipulation(newaction):
	assert(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE], "Can't change scene manipulation type when not in grid state.")
	if gsraction == newaction:
		return

	start_mousepos = mousepos
		
	if newaction == GSRAction.GRAB || newaction == GSRAction.NONE:
		if newaction != GSRAction.NONE:
			grid_transforms.resize(grid_undo_pos + 1)
			grid_transforms.append(spatialscene.transform)
			grid_undo_pos += 1
		revert_manipulation(newaction == GSRAction.NONE)
		gsraction = GSRAction.GRAB
		return
		
	if gsraction != GSRAction.GRAB:
		revert_manipulation(false)
		
	if newaction == GSRAction.ROTATE:
		rotate_mousepos = mousepos
		
	selection = [spatialscene]
	save_transforms()
	gsraction = newaction
	
	limit_transform = spatialparent.global_transform
	initialize_manipulation()


func external_request_manipulation(camera: Camera, what: String, obj, caller_object, caller_notification: String):
	assert(camera != null && !what.empty() && obj != null && caller_object != null &&
			!caller_notification.empty() && caller_object.has_method(caller_notification),
			"external_request_manipulation: not all arguments are valid")
	
	# Check what action is requested.
	var action_chars = [ 'g', 's', 'r' ]
	var action_choices = [ GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE ]
	
	var main_action = GSRAction.NONE
	external_allowed_actions = {}
	for ch in what:
		var ix = action_chars.find(ch)
		if ix == -1:
			continue
		if main_action == GSRAction.NONE:
			main_action = action_choices[ix]
		external_allowed_actions[action_choices[ix]] = true
	
	assert(main_action != GSRAction.NONE, "external_request_manipulation: request string invalid")
	if obj is Spatial:
		obj = [obj]
	elif obj is Array:
		for ix in obj.size():
			assert(obj[ix] is Spatial, "Every object must be a Spatial")
	
	if gsraction != GSRAction.NONE:
		cancel_manipulation()

	external_what = what
	external_caller = caller_object
	external_callback = caller_notification
	external_selected = selected

	editor_camera = camera
	local = is_local_button_down()

	gsrstate = GSRState.EXTERNAL_MANIPULATE
	gsraction = main_action
	
	start_mousepos = mousepos
	selection = obj
	selected = true
	
	hide_gizmo()
	disable_undoredo()
	save_transforms()
	initialize_manipulation()
	

# Same as grab, but first creates a duplicate of the selected scenes.
# Cancelling this action will still keep the duplicated meshes.
func start_duplication(camera: Camera):
	assert(gsrstate == GSRState.NONE, "Can't start duplication when an action is already in progress")
	
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
#	Scene.clear_selection(self)
#	Scene.set_selected(self, dup, true)
	
	var objects = es.get_transformable_selected_nodes()
	selection = []
	for obj in objects:
		if obj is Spatial:
			var dup = obj.duplicate()
			obj.get_parent().add_child(dup)
			dup.owner = obj.owner
			selection.append(dup)
	
	#selection = es.get_selected_nodes()
	if selection.empty():
		return
	
	editor_camera = camera
	local = is_local_button_down()
	
	gsrstate = GSRState.DUPLICATE
	save_transforms()

	interop_work = "gsr_duplicate"
	Interop.start_work(self, interop_work)
	
	start_mousepos = mousepos
		
	hide_gizmo()
	disable_undoredo()
	change_manipulation(GSRAction.GRAB)


func start_manipulation(camera: Camera, newaction):
	assert(gsrstate == GSRState.NONE, "Can't start manipulation when an action is already in progress")
	
	selection = []
	var ei = get_editor_interface()
	var es = ei.get_selection()
	
	var objects = es.get_transformable_selected_nodes()
	for obj in objects:
		if obj is Spatial:
			selection.append(obj)
	
	if selection.empty():
		return
		
	editor_camera = camera
	local = is_local_button_down()
	gsrstate = GSRState.MANIPULATE
	save_transforms()
		
	interop_work = "gsr_transform"
	Interop.start_work(self, interop_work)

	start_mousepos = mousepos

	hide_gizmo()
	disable_undoredo()
	change_manipulation(newaction)
	

func change_manipulation(newaction):
	assert(gsrstate in [GSRState.DUPLICATE, GSRState.EXTERNAL_MANIPULATE, GSRState.MANIPULATE], "Can't change manipulation action when not in the right state.")
	if gsraction == newaction:
		return

	if gsrstate == GSRState.DUPLICATE && (!(newaction in [GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE])):
		return
	
	if gsraction != GSRAction.NONE:
		revert_manipulation()
		
	gsraction = newaction
	initialize_manipulation()
	if newaction == GSRAction.ROTATE:
		rotate_mousepos = start_mousepos
	manipulate_selection()


func initialize_manipulation():
	if gsraction in [GSRAction.SCALE, GSRAction.ROTATE]:
		if (selection_centerpos.distance_to(start_mousepos) < MINIMUM_MANIPULATION_MOUSE_DISTANCE):
			if selection_centerpos == start_mousepos:
				start_mousepos = selection_centerpos + Vector2(MINIMUM_MANIPULATION_MOUSE_DISTANCE, 0)
			elif gsraction == GSRAction.SCALE:
				start_mousepos = selection_centerpos + ((start_mousepos - selection_centerpos).normalized() * MINIMUM_MANIPULATION_MOUSE_DISTANCE)
	
	selection_distance = selection_center.distance_to(Scene.camera_ray_origin(editor_camera, selection_centerpos))
	start_viewpoint = editor_camera.project_position(start_mousepos, selection_distance)
	
	update_overlays()


func calculate_global_center(objects: Array) -> Vector3:
	var result := Vector3.ZERO

	# Godot doesn't have defines, so I'm just adding a simple local variable here.
	# Alternate center is how Godot calculates the center of the selection. It's an unnatural
	# and strange choice, but it's easier to use this for the users when the default gizmo is
	# positioned there.
	var alternate_center = true
	
	var sel_min: Vector3
	var sel_max: Vector3

	for ix in objects.size():
		var ori = objects[ix].global_transform.origin
		if !alternate_center:
			result += ori
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
		result /= objects.size()
	else:
		result = (sel_min + sel_max) / 2.0
		
	return result


func change_scene_limit(newlimit):
	if !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]):
		return
		
	if limit != newlimit:
		saved_offset = vector_component(spatial_offset, newlimit)
		limit = newlimit
		limit_transform = spatialparent.global_transform
		update_scene_placement()
	else:
		limit = 0
		update_scene_placement()


func cancel_scene_limit():
	if !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]) || gsraction != GSRAction.GRAB:
		return
		
	spatial_offset = set_vector_component(spatial_offset, limit, saved_offset)
	limit = 0
	update_scene_placement()


func change_scene_plane(newplane):
	if !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]) || gsraction != GSRAction.GRAB || spatial_placement_plane == newplane:
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
	revert_transforms()
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
		
	revert_transforms()
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
		
	revert_transforms()
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


func vector_exclude_plane(vec: Vector3, plane: int):
	if plane == GSRAxis.X:
		return Vector3(0, vec.y, vec.z)
	if plane == GSRAxis.Y:
		return Vector3(vec.x, 0, vec.z)
	if plane == GSRAxis.Z:
		return Vector3(vec.x, vec.y, 0)


func vector_plane(vec: Vector3, plane: int):
	if plane == GSRAxis.X:
		return Vector3(vec.x, 0.0, 0.0)
	if plane == GSRAxis.Y:
		return Vector3(0.0, vec.y, 0.0)
	if plane == GSRAxis.Z:
		return Vector3(0.0, 0.0, vec.z)


func vmod(vec: Vector3, m: float) -> Vector3:
	return Vector3(fmod(vec.x, m), fmod(vec.y, m), fmod(vec.z, m))


# Returns a plane from a normal and a point it should contain.
func plane_from_point(normal, point: Vector3):
	if normal == null || normal == Vector3.ZERO:
		return null
		
	return Plane(normal, Plane(normal, 0.0).distance_to(point))


func scene_placement_plane() -> Plane:
	return plane_from_point(plane_axis(spatialparent, spatial_placement_plane),
			#spatialparent.global_transform.origin + 
			spatialparent.to_global(spatial_offset))


func scene_placement_limited_plane():
	#var plane = plane_from_point(plane_axis(spatialparent, limit), spatialparent.global_transform.origin)
	return plane_from_point(editor_camera.global_transform.basis.z, spatialscene.global_transform.origin)


func update_scene_placement():
	if spatialscene == null:
		return
	
	if limit != spatial_placement_plane:
		var plane = scene_placement_plane()
				
		var point = plane.intersects_ray(Scene.camera_ray_origin(editor_camera, mousepos),
				Scene.camera_ray_normal(editor_camera, mousepos))
		if point == null:
			if grid_mesh != null:
				grid_mesh.visible = false
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
	else:
		var plane = scene_placement_limited_plane() 
		if plane == null:
			if grid_mesh != null:
				grid_mesh.visible = false
			return
			
		var point = plane.intersects_ray(Scene.camera_ray_origin(editor_camera, mousepos),
				Scene.camera_ray_normal(editor_camera, mousepos))
		if point == null:
			if grid_mesh != null:
				grid_mesh.visible = false
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
	update_grid_position(spatialscene.transform.origin - vector_exclude_plane(spatial_offset, spatial_placement_plane))
	update_cross_transform()
		
	selection_center = spatialscene.global_transform.origin
	selection_centerpos = Scene.unproject(editor_camera, selection_center)
	update_overlays()


func finalize_scene_placement():
	if spatialscene == null || spatialparent == null:
		reset_scene_action()
		return
	
	limit = GSRLimit.NONE
	
	enable_undoredo()
	
	var ur = get_undo_redo()
	if gsrstate == GSRState.GRID_ADD:
		ur.create_action("GSR Scene Placement")
		ur.add_do_method(spatialparent, "add_child", spatialscene)
		ur.add_do_method(spatialscene, "set_owner", spatialparent.owner if spatialparent.owner != null else spatialparent)
		ur.add_do_property(spatialscene, "transform", spatialscene.transform)
		ur.add_do_reference(spatialscene)
		ur.add_undo_method(spatialparent, "remove_child", spatialscene)
		
		if spatialscene.get_parent() != null:
			spatialscene.get_parent().remove_child(spatialscene)
	else: # GRID_MOVE
		ur.create_action("GSR Action")
		ur.add_do_property(spatialscene, "transform", spatialscene.transform)
		ur.add_undo_property(spatialscene, "transform", grid_transforms[0])		
	ur.commit_action()
	
	reset()


#func do_place_scene(spath, sparentpath, stransform):
#	var ps := get_placement_scene(spath)
#	var root := get_editor_interface().get_edited_scene_root()
#	var sparent := root.get_node(sparentpath)
#	if ps == null || !is_instance_valid(sparent):
#		return
#
#	var s = ps.instance()
#	sparent.add_child(s)
#	s.owner = sparent if sparent.owner == null else sparent.owner
#	s.transform = stransform
#
#
#func undo_place_scene(sparentpath):
#	var root := get_editor_interface().get_edited_scene_root()
#	var sparent := root.get_node(sparentpath)
#	if !is_instance_valid(sparent) || !(sparent is Spatial):
#		return
#	sparent.remove_child(sparent.get_child(sparent.get_child_count() - 1)) 


func manipulate_selection():
	if !(gsraction in [GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE]) || selection.empty():
		return
	
	revert_transforms()
	apply_manipulation()


# Moves/rotates/scales selection back to original transform before manipulations started
# and resets limits/numeric input and relative mouse movement.
func revert_manipulation(transforms: bool = true):
	assert(!selection.empty(), "Can't revert manipulation when there was nothing selected")
	
	if transforms:
		revert_transforms()
	UI.disable_undoredo(self, hadundo, hadredo)

	limit = GSRLimit.NONE
	rotate_angle = 0.0
	numerics = ""
	mousepos_offset = Vector2.ZERO
	reference_mousepos = Vector2.ZERO


func save_transforms():
	start_transform.resize(selection.size())
	start_global_transform.resize(selection.size())
	
	for ix in selection.size():
		start_transform[ix] = selection[ix].transform
		start_global_transform[ix] = selection[ix].global_transform
		
	selection_center = calculate_global_center(selection)
	selection_centerpos = Scene.unproject(editor_camera, selection_center)
	

func revert_transforms():
	for ix in selection.size():
		selection[ix].transform = start_transform[ix]
	

func reset_scene_action():
	if spatialscene != null:
		if gsrstate == GSRState.GRID_ADD:
			spatialscene.free()
			spatialscene = null
		else: # GRID_MOVE
			spatialscene.transform = grid_transforms[0]
	if grid_mesh != null && grid_mesh.get_parent() != null:
		grid_mesh.get_parent().remove_child(grid_mesh)
	limit = GSRLimit.NONE


func apply_manipulation():
	if !(gsraction in [GSRAction.GRAB, GSRAction.SCALE, GSRAction.ROTATE]) || selection.empty():
		return
	
	var camera := editor_camera
	
	var constant = null
	if !numerics.empty():
		constant = numerics.to_float()

	if gsraction == GSRAction.GRAB:
		var offset: Vector3
		
		for ix in selection.size():
			if limit == GSRLimit.NONE:
				var vnew := camera.project_position(manipulation_mousepos(), selection_distance)
				offset = vnew - start_viewpoint
			if (limit & GSRLimit.X) || (limit & GSRLimit.Y) || (limit & GSRLimit.Z):
				if (limit & GSRLimit.REVERSE):
					var plane = get_limit_axis_reverse_plane(ix)
					var cam_pt = plane.intersects_ray(Scene.camera_ray_origin(camera, manipulation_mousepos()), Scene.camera_ray_normal(camera, manipulation_mousepos()))
					if cam_pt != null:
						offset = cam_pt - start_viewpoint
					else:
						offset = Vector3.ZERO #selection[ix].global_transform.origin - start_transform[ix].origin
				else:
					var cvec = Scene.camera_ray_normal(camera, manipulation_mousepos())
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
					var cam_pt = plane.intersects_ray(Scene.camera_ray_origin(camera, manipulation_mousepos()), cvec)
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
	elif gsraction == GSRAction.ROTATE:
		var offset: float = 0.0
		var point := selection_center
		var axis := Vector3.ZERO
		
		var change = Vector2(mousepos - selection_centerpos).angle_to(Vector2(rotate_mousepos - selection_centerpos)) * get_action_strength()
		rotate_mousepos = mousepos
		rotate_angle += change
		
		if is_snapping():
			var snapstep = rotate_step_size()
			rotate_display = stepify(rad2deg(rotate_angle), snapstep)
		else:
			rotate_display = constant if constant != null else rad2deg(rotate_angle) 
		
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
	elif gsraction == GSRAction.SCALE:
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
	update_cross_transform()


func offset_object(index: int, movedby: Vector3):
	selection[index].global_transform.origin += movedby
	UI.disable_undoredo(self, hadundo, hadredo)


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
	UI.disable_undoredo(self, hadundo, hadredo)


func scale_object(index: int, scale: Vector3, pos_scale: Vector3, center: Vector3, in_place: bool):
	var obj = selection[index]
	obj.scale = Vector3(obj.transform.basis.x.length() * scale.x, obj.transform.basis.y.length() * scale.y, obj.transform.basis.z.length() * scale.z)
	
	obj.global_transform.origin = (obj.global_transform.origin - center) * pos_scale + center
	UI.disable_undoredo(self, hadundo, hadredo)


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


func external_cancel():
	if gsrstate != GSRState.EXTERNAL_MANIPULATE:
		return
	external_caller.call(external_callback, external_what, false, null)
	external_reset()
	

# Cancels ongoing manipulation restoring old transform of involved spatials.
func cancel_manipulation():
	if gsraction == GSRAction.NONE:
		return
		
	if !(gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]):
		revert_manipulation()
	if gsraction == GSRAction.GRAB && gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
		reset_scene_action()
	reset()


# Applying grab, scale or rotate manipulation, so the spatials being manipulated take up their
# final position. In case manipulation is just the sub-action while placing a spatial in a grid,
# returns to that action instead, while keeping the new scale or rotation of the spatial.
func finalize_manipulation():
	if gsrstate in [GSRState.DUPLICATE, GSRState.MANIPULATE, GSRState.EXTERNAL_MANIPULATE]:
		# Saving current transforms, and then resetting to original, so the undo
		# can do its magic with the two transforms.
		var selection_final_state = []
		for s in selection:
			selection_final_state.append(s.transform)
		revert_manipulation()
		
		enable_undoredo()
		
		if gsrstate != GSRState.EXTERNAL_MANIPULATE:
			var reverted_transforms = []
			for s in selection:
				reverted_transforms.append(s.transform)
				
			var ur = get_undo_redo()
			if gsrstate == GSRState.DUPLICATE:
				Scene.clear_selection(self)
				ur.create_action("GSR Duplicate")
				for s in selection:
					var p = s.get_parent()
					ur.add_do_method(p, "add_child", s)
					ur.add_do_method(s, "set_owner", s.owner)
					ur.add_do_reference(s)
					ur.add_undo_method(p, "remove_child", s)
				for s in selection:
					s.get_parent().remove_child(s)
				ur.commit_action()
				for s in selection:
					Scene.set_selected(self, s, true)
			ur.create_action("GSR Action")
			for ix in selection.size():
				var item = selection[ix]
				ur.add_do_property(item, "transform", selection_final_state[ix])
				ur.add_undo_property(item, "transform", reverted_transforms[ix])
			ur.commit_action()
		else:
			external_caller.call(external_callback, external_what, true, selection_final_state)
			external_reset()
	
	reset()


func reset():
	var oldstate = gsrstate
	
	if gsrstate in [GSRState.GRID_ADD, GSRState.GRID_MOVE]:
		if grid_mesh != null && grid_mesh.get_parent() != null:
			grid_mesh.get_parent().remove_child(grid_mesh)
	
	gsrstate = GSRState.NONE

	grid_transforms = []
	grid_undo_pos = -1
	
	limit_transform = null
	
	spatialscene = null
	spatialparent = null
	
	snap_toggle = false
	
	show_gizmo()
	enable_undoredo()
	
	editor_camera = null

	start_transform = []
	start_global_transform = []
	selection = []
	local = false
	gsraction = GSRAction.GRAB if gsrstate != GSRState.NONE else GSRAction.NONE
	smoothing = false
	
	update_overlays()
	update_cross_transform()
	
	if oldstate != GSRState.NONE && gsrstate == GSRAction.NONE && !interop_work.empty():
		Interop.end_work(self, interop_work)
		
	interop_work = ""


func external_reset():
	external_allowed_actions = {}

	external_what = String()
	external_caller = null
	external_callback = String()
	selected = external_selected


func generate_meshes():
	if grid_mesh == null:
		grid_mesh = GridMesh.new(self)
	if cross_mesh == null:
		cross_mesh = CrossMesh.new(self)


func free_meshes():
	grid_mesh.free()
	grid_mesh = null
	cross_mesh.free()
	cross_mesh = null


func check_grid():
	if grid_mesh == null:
		grid_mesh = GridMesh.new(self)
	else:
		grid_mesh.update()


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


func update_cross_transform():
	if cross_mesh == null:
		return
	
	# The user might switch between scenes or close a scene. The cross mesh should be
	# attached to the new scene and the gizmos fetched again.
	var scene_root = get_editor_interface().get_edited_scene_root()
	if cross_mesh.get_parent() == null || cross_mesh.get_parent() != scene_root:
		if cross_mesh.get_parent() != null:
			cross_mesh.get_parent().remove_child(cross_mesh)
		if scene_root != null:
			scene_root.add_child(cross_mesh)
			gizmo_spatials = get_editor_interface().get_selection().get_transformable_selected_nodes()
		else:
			gizmo_spatials = []
			return

	var valid_spatials = spatialscene != null || (gizmo_spatials != null && !gizmo_spatials.empty())
	if valid_spatials && spatialscene == null:
		for s in gizmo_spatials:
			if !is_instance_valid(s) || s.get_parent() == null:
				valid_spatials = false
				break

	cross_mesh.visible = valid_spatials && ((gizmo_spatials != null && !gizmo_spatials.empty()) || spatialscene != null) && (gizmodisabled || gizmohidden)
	#if !valid_spatials:
	if !cross_mesh.visible:
		cross_mesh.get_parent().remove_child(cross_mesh)
		return

	var position: Vector3
	var xvec: Vector3
	var yvec: Vector3
	var zvec: Vector3
	if spatialscene != null:
		position = spatialscene.global_transform.origin
		xvec = Vector3.RIGHT
		yvec = Vector3.UP
		zvec = Vector3.BACK
	elif gizmo_spatials != null && !gizmo_spatials.empty():
		position = calculate_global_center(gizmo_spatials)
		var rotlocal = local if gsraction == GSRAction.NONE else is_local_button_down() 
		xvec = (gizmo_spatials[0].global_transform.basis.x if gizmo_spatials.size() == 1 && rotlocal else Vector3.RIGHT).normalized()
		yvec = (gizmo_spatials[0].global_transform.basis.y if gizmo_spatials.size() == 1 && rotlocal else Vector3.UP).normalized()
		zvec = (gizmo_spatials[0].global_transform.basis.z if gizmo_spatials.size() == 1 && rotlocal else Vector3.BACK).normalized()
	else:
		return
	cross_mesh.global_transform = Transform(xvec, yvec, zvec, position)


func update_depth_select(turn_on):
	set_gizmo_disabled(turn_on)


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



