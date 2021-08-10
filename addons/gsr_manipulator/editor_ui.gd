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

extends Object

func _ready():
	pass


# Returns a child node of the control node if it matches the class name `childclass`.
# It can return a specific child node with an `index`, of all child nodes with the
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


static func spatial_editor(editor: EditorPlugin):
	var ei = editor.get_editor_interface()
	var vp = ei.get_editor_viewport()
	
	return find_child(vp, "SpatialEditor")


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
	
