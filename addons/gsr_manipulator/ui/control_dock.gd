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
extends PanelContainer


const InputDialog = preload("./input_dialog.tscn")


onready var snap_edit = $VBoxContainer/SnapEdit
onready var subd_edit = $VBoxContainer/SubdEdit
onready var save_button = $VBoxContainer/HBoxContainer/SaveButton
onready var preset_options = $VBoxContainer/HBoxContainer/PresetOptions
onready var del_button = $VBoxContainer/HBoxContainer/DelButton


var sdlg = null


func _ready():
	del_button.icon = get_icon("Remove", "EditorIcons")

	snap_edit.connect("text_changed", self, "_on_numedit_changed", [snap_edit, false])
	subd_edit.connect("text_changed", self, "_on_numedit_changed", [subd_edit, true])
	
	save_button.connect("pressed", self, "_on_save_pressed")
	del_button.connect("pressed", self, "_on_del_preset_pressed")


func _on_numedit_changed(val: String, edit: LineEdit, int_only: bool):
	var cpos = edit.caret_position
	var cdif = 0
	var changed = false
	var dot = int_only
	var newstr: String
	
	for ix in edit.text.length():
		var ch = edit.text[ix]
		if ch == '.':
			if !dot:
				dot = true
			else:
				if cpos > ix:
					cdif += 1
				changed = true
				continue
		elif ch < '0' || ch > '9':
			if cpos > ix:
				cdif += 1
			changed = true
			continue
		newstr += ch
	
	if !changed:
		return
	
	edit.text = newstr
	edit.caret_position = cpos - cdif


func _on_save_pressed():
	show_save_dialog()


func show_save_dialog():
	sdlg = InputDialog.instance()
	var top_parent: Control = find_top_parent()
	top_parent.add_child(sdlg)
	sdlg.connect("confirmed", self, "_on_save_dialog_confirmed")
	sdlg.connect("hide", self, "_on_save_dialog_hidden")
	sdlg.set_position((top_parent.get_rect().size / 2) - (sdlg.get_rect().size / 2))
	sdlg.show_modal(true)


func find_top_parent():
	var p = self
	var last_control = null
	while p != null:
		p = p.get_parent()
		if p != null && p is Control:
			last_control = p
	return last_control


func _on_save_dialog_confirmed():
	if sdlg == null:
		return
	var text = sdlg.get_edit_text()
	save_preset(text)


func _on_save_dialog_hidden():
	print("Hidden")
	call_deferred("_delete_save_dialog")


func _delete_save_dialog():
	sdlg.queue_free()
	sdlg = null


func save_preset(text: String):
	pass


func delete_preset(index: int):
	pass
