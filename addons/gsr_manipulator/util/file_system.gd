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

