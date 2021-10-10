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
extends Node


const UI = preload("./editor_ui.gd")

signal snap_settings_changed()


# Unit size for snapping when moving a node in a grid.
var grid_size := 1.0
# Number of subdivisions of each grid section. Must be 1 or higher.
var grid_subdiv := 10

# Whether the z and y shortcuts are swapped when locking to an axis.
var zy_swapped = false
# Whether snap settings are shown in the 3D editor
var snap_controls_shown = false
# Using the plugin's mouse selection method in the 3d scene.
var smart_select = false

# Options of smart select to allow selecting by clicking on these
var select_front_facing = true
var select_back_facing = true
var select_collision = true
var select_light = true
var select_camera = true
var select_raycast = true

# Presets (stored in dictionaries) created for grid snap and subdivision values.
var snap_presets = []
# Preset last selected in the settings panel
var selected_snap_preset = -1

# Used when hiding gizmos so their original size can be restored. It's a setting
# because it needs to be restored as Godot doesn't notify us on close in time
# to be restored when the plugin quits.
var saved_gizmo_size = -1

func load_config():
	var config := UI.load_config("user://gsr.cfg")
	
	var section = config.get("settings")
	if section != null:
		zy_swapped = section.get("z_up", false)
		snap_controls_shown = section.get("snap_controls_shown", false)
		smart_select = section.get("smart_select", false)
		selected_snap_preset = section.get("snap_preset", false)
	
	section = config.get("selectables")
	if section != null:
		select_front_facing = section.get("select_front_facing", true)
		select_back_facing = section.get("select_back_facing", true)
		select_collision = section.get("select_collision", true)
		select_light = section.get("select_light", true)
		select_camera = section.get("select_camera", true)
		select_raycast = section.get("select_raycast", true)
		
	section = config.get("grid")
	if section != null:
		grid_size = section.get("grid_size", 1.0)
		grid_subdiv = section.get("grid_subdiv", 10)
	
	section = config.get("editor")
	if section != null:
		saved_gizmo_size = section.get("saved_gizmo_size", -1)
	
	section = config.get("snap_presets")
	var presets = {}
	if section != null:
		for key in section.keys():
			if typeof(key) != TYPE_STRING:
				continue
			var u_pos = key.rfind("_")
			if u_pos == -1:
				continue
			var ix = int(key.substr(u_pos + 1))
			var k = key.substr(0, u_pos)
			if (k != "name" && k != "grid_size" && k != "grid_subdiv"):
				continue
			if !presets.has(ix):
				presets[ix] = {}
			presets[ix][k] = section[key]
	
	snap_presets = []
	for key in presets.keys():
		if presets[key].size() != 3:
			continue
		snap_presets.append(presets[key])
	snap_presets.sort_custom(self, "_compare_snap_presets")
	

func save_config():
	var config = { "settings" : { "z_up" : zy_swapped, "snap_preset" : selected_snap_preset,
						"snap_controls_shown" : snap_controls_shown, "smart_select" : smart_select },
			"selectables" : { "select_front_facing" : select_front_facing,
				"select_back_facing" : select_back_facing, "select_collision" : select_collision,
				"select_light" : select_light, "select_camera" : select_camera, 
				"select_raycast" : select_raycast },
			"grid" : { "grid_size" : grid_size, "grid_subdiv" : grid_subdiv },
			"editor" : { "saved_gizmo_size" : saved_gizmo_size } }
	
	var presets = {}
	for ix in snap_presets.size():
		presets["name_" + str(ix)] = snap_presets[ix].name
		presets["grid_size_" + str(ix)] = snap_presets[ix].grid_size
		presets["grid_subdiv_" + str(ix)] = snap_presets[ix].grid_subdiv
	
	if !presets.empty():
		config["snap_presets"] = presets
	
	UI.save_config("user://gsr.cfg", config)


func snap_preset_count():
	return snap_presets.size()


func snap_preset_name(index: int):
	if index < 0 || index >= snap_presets.size():
		return null
	return snap_presets[index].name	


func store_grid_preset(name: String, siz: float, subd: int) -> int:
	var pos = snap_presets.bsearch_custom(name, self, "_compare_snap_presets", true)
	var val = { "name" : name, "grid_size" : siz, "grid_subdiv" : subd }
	if snap_presets.size() <= pos:
		snap_presets.append(val)
	elif snap_presets[pos].name != name:
		snap_presets.insert(pos, val)
	else:
		snap_presets[pos] = val
	return pos


func snap_preset_snap(index: int):
	if index < 0 || index >= snap_presets.size():
		return null
	return snap_presets[index].grid_size


func snap_preset_subdiv(index: int):
	if index < 0 || index >= snap_presets.size():
		return null
	return snap_presets[index].grid_subdiv


func _compare_snap_presets(a, b):
	if (a is String) != (b is String):
		if a is String:
			return a < b.name
		else:
			return a.name < b
	elif a is String:
		return a < b
	else:
		return a.name < b.name


func delete_snap_preset(index: int):
	snap_presets.remove(index)


func select_snap_preset(index: int):
	if index < 0 || index >= snap_presets.size():
		set_snap_values(1.0, 10)
		return
		
	grid_size = snap_presets[index].grid_size
	grid_subdiv = snap_presets[index].grid_subdiv
	
	set_snap_values(snap_presets[index].grid_size, snap_presets[index].grid_subdiv)


func set_snap_values(siz: float, subd: int):
	if grid_size == siz && grid_subdiv == subd:
		return
	
	grid_size = siz
	grid_subdiv = subd
	
	emit_signal("snap_settings_changed")

