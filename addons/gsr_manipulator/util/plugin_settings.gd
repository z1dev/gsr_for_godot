extends Node

# Unit size for snapping when grab-moving a node.
var grab_snap_size := 1.0
# Number of subdivisions for smoothing when grab-moving a node. Must be 1 or higher.
var grab_snap_subd := 10

# Whether the z and y shortcuts are swapped when locking to an axis.
var zy_swapped = false

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


func store_snap_preset(name: String, snap: float, subdiv: int) -> int:
	var pos = snap_presets.bsearch_custom(name, self, "_compare_snap_presets", true)
	var val = { "name" : name, "snap" : snap, "subdiv" : subdiv }
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
	return snap_presets[index].snap


func snap_preset_subdiv(index: int):
	if index < 0 || index >= snap_presets.size():
		return null
	return snap_presets[index].subdiv


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
		grab_snap_size = 1.0
		grab_snap_subd = 10
		return
	grab_snap_size = snap_presets[index].snap
	grab_snap_subd = snap_presets[index].subdiv


func set_snap_values(snap: float, subd: int):
	grab_snap_size = snap
	grab_snap_subd = subd

