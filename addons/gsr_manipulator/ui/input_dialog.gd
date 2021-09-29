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
extends ConfirmationDialog

onready var edit := $VBox/LineEdit
var allow_empty := false


func _ready():
	edit.connect("text_changed", self, "_on_edit_text_changed")
	_on_edit_text_changed(edit.text)
	edit.grab_focus()


func get_edit_text():
	return edit.text


func set_edit_text(text: String):
	edit.text = text
	edit.select_all()
	_on_edit_text_changed(text)


func _on_edit_text_changed(newtext: String):
	get_ok().disabled = !allow_empty && newtext.empty()


func _input(event):
	if event is InputEventKey:
		if event.scancode == KEY_ESCAPE:
			hide()
		elif event.scancode == KEY_ENTER && !get_ok().disabled:
			hide()
			emit_signal("confirmed")
