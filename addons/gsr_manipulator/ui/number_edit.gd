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
extends LineEdit


const MODE_FLOAT = 0 
const MODE_INT = 1

var mode = 0
var empty_allowed = true

var savetext

signal text_finalized


func _ready():
	connect("text_changed", self, "_on_text_changed")
	connect("focus_entered", self, "_on_focus_entered")
	connect("focus_exited", self, "_on_focus_exited")


func _on_text_changed(newtext: String):
	var cpos = caret_position
	var cdif = 0
	var changed = false
	var dot = (mode == MODE_INT)
	var newstr: String
	
	for ix in newtext.length():
		var ch = newtext[ix]
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
	
	text = newstr
	caret_position = cpos - cdif


func _on_focus_entered():
	savetext = text


func _on_focus_exited():
	if empty_allowed || !text.empty():
		if text != savetext:
			emit_signal("text_finalized")
		return
	text = savetext


