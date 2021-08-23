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
const NumberEdit = preload("./number_edit.gd")

onready var snap_edit := $VBoxContainer/SnapEdit
onready var subd_edit:= $VBoxContainer/SubdEdit
onready var save_button := $VBoxContainer/HBoxContainer/SaveButton
onready var preset_options := $VBoxContainer/HBoxContainer/PresetOptions
onready var revert_button := $VBoxContainer/HBoxContainer/RevertButton
onready var del_button := $VBoxContainer/HBoxContainer/DelButton

var editor: EditorPlugin = null setget set_editor


var save_dlg = null


func _ready():
	del_button.icon = get_icon("Remove", "EditorIcons")
	revert_button.icon = get_icon("Reload", "EditorIcons")
	snap_edit.mode = NumberEdit.MODE_FLOAT
	subd_edit.mode = NumberEdit.MODE_INT
	snap_edit.empty_allowed = false
	subd_edit.empty_allowed = false
	snap_edit.connect("text_finalized", self, "_on_snap_finalized")
	subd_edit.connect("text_finalized", self, "_on_snap_finalized")

	save_button.connect("pressed", self, "_on_save_pressed")
	del_button.connect("pressed", self, "_on_del_preset_pressed")
	revert_button.connect("pressed", self, "_on_revert_preset_pressed")
	preset_options.connect("item_selected", self, "_on_preset_options_item_selected")

	update_values()
		
	
func set_editor(val):
	if editor == null:
		editor = val
		update_values()


var inited := false
func update_values():
	if inited || editor == null || snap_edit == null:
		return
	inited = true
	fill_preset_options()
	var snap = str(editor.settings.grab_snap_size)
	if !('.' in snap):
		snap += ".0"
	snap_edit.text = snap
	subd_edit.text = str(editor.settings.grab_snap_subd)


func _on_save_pressed():
	show_save_dialog()


func show_save_dialog():
	save_dlg = InputDialog.instance()
	var top_parent: Control = find_top_parent()
	top_parent.add_child(save_dlg)
	save_dlg.connect("confirmed", self, "_on_save_dialog_confirmed")
	save_dlg.connect("hide", self, "_on_save_dialog_hidden")
	save_dlg.set_position((top_parent.get_rect().size / 2) - (save_dlg.get_rect().size / 2))
	save_dlg.show_modal(true)


func find_top_parent():
	var p = self
	var last_control = null
	while p != null:
		p = p.get_parent()
		if p != null && p is Control:
			last_control = p
	return last_control


func _on_save_dialog_confirmed():
	if save_dlg == null:
		return
	var text = save_dlg.get_edit_text()
	save_preset(text)


func _on_save_dialog_hidden():
	call_deferred("_delete_save_dialog")


func _delete_save_dialog():
	save_dlg.queue_free()
	save_dlg = null


func _on_del_preset_pressed():
	delete_preset(preset_options.selected)


func _on_revert_preset_pressed():
	var snap = str(editor.settings.snap_preset_snap(preset_options.selected))
	if !('.' in snap):
		snap += ".0"
	snap_edit.text = snap
	subd_edit.text = str(editor.settings.snap_preset_subdiv(preset_options.selected))
	revert_button.disabled = true
	

func _on_snap_finalized():
	editor.settings.set_snap_values(float(snap_edit.text), int(subd_edit.text))
	del_button.disabled = (preset_options.selected == -1 ||
			preset_options.selected >= editor.settings.snap_preset_count())
	
	update_revert_button()


func update_revert_button():
	revert_button.disabled = (preset_options.selected == -1 ||
			preset_options.selected >= editor.settings.snap_preset_count() ||
			(editor.settings.snap_preset_snap(preset_options.selected) == float(snap_edit.text) &&
			editor.settings.snap_preset_subdiv(preset_options.selected) == int(subd_edit.text)))


func _on_preset_options_item_selected(index: int):
	if index == -1:
		editor.settings.set_snap_values(float(snap_edit.text), int(subd_edit.text))
		del_button.disabled = true
		update_revert_button()
		return
	var snap = str(editor.settings.snap_preset_snap(index))
	if !('.' in snap):
		snap += ".0"
	snap_edit.text = snap
	subd_edit.text = str(editor.settings.snap_preset_subdiv(index))
	editor.settings.select_snap_preset(index)
	del_button.disabled = false
	update_revert_button()
	

func save_preset(text: String):
	var oldpos = preset_options.selected
	var pos = editor.settings.store_snap_preset(text, float(snap_edit.text), int(subd_edit.text))
	fill_preset_options()
	preset_options.selected = pos
	
	del_button.disabled = editor.settings.snap_preset_count() == 0
	update_revert_button()


func delete_preset(index: int):
	editor.settings.delete_snap_preset(index)
	fill_preset_options()
	
	del_button.disabled = editor.settings.snap_preset_count() == 0
	update_revert_button()



func fill_preset_options():
	preset_options.clear()
	for ix in editor.settings.snap_preset_count():
		preset_options.add_item(editor.settings.snap_preset_name(ix))
	preset_options.disabled = preset_options.get_item_count() == 0
