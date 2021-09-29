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


# To remember later:
#ei.get_base_control() # panel 4036 - viewport/editornode/control/panel - parent of big vboxcontainer 
#ei.get_editor_viewport() # vboxcontainer 4100 - canvasitemeditor, spatialeditor etc. parent
	

# Returns a child node of the control node if it matches the class name `childclass`.
# It can return a specific child node with an `index` of all child nodes with the
# same class name.
static func find_child(control: Node, childclass: String, index: int = 0):
	if control == null:
		return null
		
	for c in control.get_children():
		if c.get_class() == childclass:
			if index == 0:
				return c
			index -= 1
	return null


# Returns the first child under control with the the given class name. First
# searches the direct children, then each folder recursively in order.
static func find_child_recursive(control: Node, childclass: String):
	if control == null:
		return null
	
	var arr = [control]
	var pos = 0
	
	while pos < arr.size():
		control = arr[pos]
		for c in control.get_children():
			if c.get_class() == childclass:
				return c
			arr.append(c)
		pos += 1
	return null


static func get_top_bar(editor: EditorPlugin):
	var ei = editor.get_editor_interface()
	return find_child(find_child(ei.get_base_control(), "VBoxContainer"), "HBoxContainer")


static func get_menu_bar(editor: EditorPlugin):
	return find_child(get_top_bar(editor), "HBoxContainer")


const MENU_SCENE = 0
const MENU_PROJECT = 1
const MENU_DEBUG = 2
const MENU_EDITOR = 3
const MENU_HELP = 4


static func get_menu(editor: EditorPlugin, index) -> PopupMenu:
	return find_child(find_child(get_menu_bar(editor), "MenuButton", index), "PopupMenu") as PopupMenu


static func current_main_screen(editor: EditorPlugin):
	var ei = editor.get_editor_interface()
	
	var menubar = get_top_bar(editor)
	
	var button_container = null
	var ix = 0
	while button_container == null:
		var container = find_child(menubar, "HBoxContainer", ix)
		if container == null:
			break
		var btn = find_child(container, "ToolButton")
		if btn != null && btn.text == "2D":
			button_container = container
		else:
			ix += 1
	
	if button_container != null:
		for iy in button_container.get_child_count():
			var btn = button_container.get_child(iy)
			if btn != null && btn is ToolButton && btn.visible && btn.pressed:
				return btn.text
	
	return ""


static func fs_selected_path(editor: EditorPlugin):
	var ei = editor.get_editor_interface()
	return ei.get_current_path()
#	var fsdock: FileSystemDock = ei.get_file_system_dock()
#	var split = (find_child(fsdock, "Button", 1) as Button).pressed
#	var tree := find_child(fsdock, "Tree", 0) as Tree
#	var sel := tree.get_next_selected(null)


static func spatial_editor(editor: EditorPlugin):
	var ei = editor.get_editor_interface()
	var vp = ei.get_editor_viewport()
	
	return find_child(vp, "SpatialEditor")


static func get_editor_settings_dialog(editor: EditorPlugin):
	var ei = editor.get_editor_interface()
	return find_child_recursive(ei.get_base_control(), "EditorSettingsDialog")


static func spatial_toolbar(editor: EditorPlugin):
	return find_child(spatial_editor(editor), "HBoxContainer")


static func spatial_use_local_toolbutton(editor: EditorPlugin):
	return find_child(spatial_toolbar(editor), "ToolButton", 9)


static func spatial_snap_toolbutton(editor: EditorPlugin):
	return find_child(spatial_toolbar(editor), "ToolButton", 10)


static func get_setting(editor: EditorPlugin, settingname: String):
	var ei: EditorInterface = editor.get_editor_interface()
	var es: EditorSettings = ei.get_editor_settings()
	return es.get_setting(settingname)
	

static func set_setting(editor: EditorPlugin, settingname: String, value):
	var ei: EditorInterface = editor.get_editor_interface()
	var es: EditorSettings = ei.get_editor_settings()
	es.set_setting(settingname, value)


static func is_dark_theme(editor: EditorPlugin) -> bool:
	var es := editor.get_editor_interface().get_editor_settings()
	
	var AUTO_COLOR = 0
	var LIGHT_COLOR = 2
	var base_color: Color = es.get_setting("interface/theme/base_color")
	var icon_font_color_setting = es.get_setting("interface/theme/icon_and_font_color")
	return (icon_font_color_setting == AUTO_COLOR && ((base_color.r + base_color.g + base_color.b) / 3.0) < 0.5) || icon_font_color_setting == LIGHT_COLOR;


static func connect_settings_changed(editor: EditorPlugin, callback: String):
	var es := editor.get_editor_interface().get_editor_settings()
	es.connect("settings_changed", editor, callback)


static func disconnect_settings_changed(editor: EditorPlugin, callback: String):
	var es := editor.get_editor_interface().get_editor_settings()
	es.disconnect("settings_changed", editor, callback)


#static func get_config_property(section: String, name: String, default):
#	var config = ConfigFile.new()
#	if config.load("user://gsr.cfg") != OK:
#		return default
#	else:
#		return config.get_value(section, name, default)


# Reads the contents of an ini file and returns them as a dictionary of sections,
# with values of key/value pair dictionaries.
static func load_config(filename) -> Dictionary:
	var config := ConfigFile.new()
	config.load(filename)
	
	var r = {}
	
	var sections := config.get_sections()
	for sec in sections:
		var s = {}
		var keys = config.get_section_keys(sec)
		for key in keys:
			var val = config.get_value(sec, key)
			s[key] = val
		r[sec] = s
		
	return r


# Saves the data as an ini file. The data must be a dictionary of sections, with
# values of key/value pair dictionaries. Does not erase or overwrite existing
# values that are not in data.
static func save_config(filename, data):
	var config = ConfigFile.new()
	# We don't care if it didn't load, just want to make sure that we get all
	# the keys if it does load.
	config.load(filename)
	for key in data.keys():
		if typeof(key) != TYPE_STRING || !(data[key] is Dictionary):
			continue
		for key2 in data[key].keys():
			if typeof(key2) != TYPE_STRING:
				continue
			config.set_value(key, key2, data[key][key2])
	config.save(filename)


static func is_undo_enabled(editor: EditorPlugin):
	var menu := get_menu(editor, MENU_SCENE)
	for ix in menu.get_item_count():
		if menu.get_item_text(ix) == "Undo":
			return !menu.is_item_disabled(ix)
	if menu.get_item_count() > 16:
		return !menu.is_item_disabled(16)
	return false


static func is_redo_enabled(editor: EditorPlugin):
	var menu = get_menu(editor, MENU_SCENE)
	for ix in menu.get_item_count():
		if menu.get_item_text(ix) == "Redo":
			return !menu.is_item_disabled(ix)
	if menu.get_item_count() > 17:
		return !menu.is_item_disabled(17)
	return false


static func disable_undoredo(editor: EditorPlugin, undo: bool, redo: bool):
	var menu = get_menu(editor, MENU_SCENE)
	if undo:
		for ix in menu.get_item_count():
			if menu.get_item_text(ix) == "Undo":
				menu.set_item_disabled(ix, true)
				undo = false
				break
		if undo && menu.get_item_count() > 16:
			menu.set_item_disabled(16, true)
	if redo:
		for ix in menu.get_item_count():
			if menu.get_item_text(ix) == "Redo":
				menu.set_item_disabled(ix, true)
				return
		if menu.get_item_count() > 17:
			menu.set_item_disabled(17, true)


static func enable_undoredo(editor: EditorPlugin, undo: bool, redo: bool):
	var menu = get_menu(editor, MENU_SCENE)
	if undo:
		for ix in menu.get_item_count():
			if menu.get_item_text(ix) == "Undo":
				menu.set_item_disabled(ix, false)
				undo = false
				break
		if undo && menu.get_item_count() > 16:
			menu.set_item_disabled(16, false)
	if redo:
		for ix in menu.get_item_count():
			if menu.get_item_text(ix) == "Redo":
				menu.set_item_disabled(ix, false)
				return
		if menu.get_item_count() > 17:
			menu.set_item_disabled(17, false)

