extends RefCounted
## Small crash-safe JSON store. Data is written completely to .tmp before
## the previous file is rotated and the new one takes its place.


static func write(path: String, value: Variant) -> bool:
	var temporary: String = path + ".tmp"
	var backup: String = path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.close()
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(_absolute(backup))
	if FileAccess.file_exists(path) and DirAccess.rename_absolute(_absolute(path), _absolute(backup)) != OK:
		DirAccess.remove_absolute(_absolute(temporary))
		return false
	if DirAccess.rename_absolute(_absolute(temporary), _absolute(path)) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(_absolute(backup), _absolute(path))
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(_absolute(backup))
	return true


static func read(path: String, fallback: Variant) -> Variant:
	_recover_backup(path)
	if not FileAccess.file_exists(path):
		return _copy(fallback)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _copy(fallback)
	var contents: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(contents) != OK or typeof(json.data) != typeof(fallback):
		_quarantine(path)
		return _copy(fallback)
	return json.data


static func _recover_backup(path: String) -> void:
	if FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".bak"):
		return
	DirAccess.rename_absolute(_absolute(path + ".bak"), _absolute(path))


static func _quarantine(path: String) -> void:
	if FileAccess.file_exists(path + ".bad"):
		DirAccess.remove_absolute(_absolute(path + ".bad"))
	if DirAccess.rename_absolute(_absolute(path), _absolute(path + ".bad")) == OK:
		return
	# Some Windows setups deny a rename inside Godot's virtual user:// even
	# after the reader closes. Preserve the evidence before removing the bad
	# source instead of silently losing it.
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return
	var contents: PackedByteArray = source.get_buffer(source.get_length())
	source.close()
	var destination := FileAccess.open(path + ".bad", FileAccess.WRITE)
	if destination == null:
		return
	destination.store_buffer(contents)
	destination.close()
	DirAccess.remove_absolute(_absolute(path))


static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func _copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
