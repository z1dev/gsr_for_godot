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


static func show_file_dialog(plugin: EditorPlugin, title: String, file: bool = true) -> EditorFileDialog:
	var dlg := EditorFileDialog.new()
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.mode = EditorFileDialog.MODE_OPEN_DIR if !file else EditorFileDialog.MODE_OPEN_FILE
	dlg.display_mode = EditorFileDialog.DISPLAY_LIST
	dlg.window_title = title
	var vp = plugin.get_editor_interface().get_base_control()
	vp.add_child(dlg)
	dlg.show_modal(true)
	dlg.set_position(Vector2((vp.get_rect().size.x - dlg.get_rect().size.x) / 2, (vp.get_rect().size.y - dlg.get_rect().size.y) / 2))
	dlg.invalidate()
	return dlg

