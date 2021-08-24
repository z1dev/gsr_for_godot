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
