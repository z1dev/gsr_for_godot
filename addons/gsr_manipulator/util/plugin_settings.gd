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

# Unit size for snapping when grab-moving a node on the x/z axes.
var grab_snap_size_x := 1.0
# Unit size for snapping when grab-moving a node on the y axis.
var grab_snap_size_y := 1.0
# Number of subdivisions for smoothing when grab-moving a node on the x/z axes. Must be 1 or higher.
var grab_snap_subd_x := 10
# Number of subdivisions for smoothing when grab-moving a node on the y axis. Must be 1 or higher.
var grab_snap_subd_y := 10
# Whether to use separate x and y snapping.
var use_y_grab_snap := false

# Whether the z and y shortcuts are swapped when locking to an axis.
var zy_swapped = false
# Whether snap settings are shown in the corner of the 3D editor
var snap_controls_shown = false

# Presets (stored in dictionaries) created for snap and subdivision values.
var snap_presets = []

func _ready():
	pass


func snap_preset_count():
	return snap_presets.size()


func snap_preset_name(index: int):
	if index < 0 || index >= snap_presets.size():
		return null
	return snap_presets[index].name	


func store_snap_preset(name: String, snap_x: float, subdiv_x: int, use_y: bool, snap_y: float, subdiv_y: int) -> int:
	var pos = snap_presets.bsearch_custom(name, self, "_compare_snap_presets", true)
	var val = { "name" : name, "snap_x" : snap_x, "subdiv_x" : subdiv_x,
			"use_y" : use_y, "snap_y" : snap_y, "subdiv_y" : subdiv_y }
	if snap_presets.size() <= pos:
		snap_presets.append(val)
	elif snap_presets[pos].name != name:
		snap_presets.insert(pos, val)
	else:
		snap_presets[pos] = val
	return pos


func snap_preset_snap(index: int, y: bool):
	if index < 0 || index >= snap_presets.size():
		return null
	if y:
		return snap_presets[index].snap_y
	return snap_presets[index].snap_x


func snap_preset_subdiv(index: int, y: bool):
	if index < 0 || index >= snap_presets.size():
		return null
	if y:
		return snap_presets[index].subdiv_y
	return snap_presets[index].subdiv_x


func snap_preset_use_y(index: int):
	if index < 0 || index >= snap_presets.size():
		return false
	return snap_presets[index].use_y
	
	
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
		grab_snap_size_x = 1.0
		grab_snap_subd_x = 10
		grab_snap_size_y = 1.0
		grab_snap_subd_y = 10
		return
	grab_snap_size_x = snap_presets[index].snap_x
	grab_snap_subd_x = snap_presets[index].subdiv_x
	grab_snap_size_y = snap_presets[index].snap_y
	grab_snap_subd_y = snap_presets[index].subdiv_y


func set_snap_values(snap_x: float, subd_x: int, use_y: bool, snap_y: float, subd_y: int):
	grab_snap_size_x = snap_x
	grab_snap_subd_x = subd_x
	grab_snap_size_y = snap_y
	grab_snap_subd_y = subd_y
	use_y_grab_snap = use_y

