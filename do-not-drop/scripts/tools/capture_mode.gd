extends Node
## Debug-only clean-frame switch. F10 hides every canvas overlay plus any
## future first-person prop registered in the `viewmodel` group, then restores
## each node to the exact visibility it had before capture mode.

var enabled: bool = false
var _saved_visibility: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or (key.keycode != KEY_F10 and key.physical_keycode != KEY_F10):
		return
	set_enabled(not enabled)
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Overlays can be created after F10 (impact effects and wheels do this).
	# Remember and hide them as well so the frame stays clean until F10 again.
	if enabled:
		_hide_capture_nodes()


func set_enabled(value: bool) -> void:
	if not OS.is_debug_build() or value == enabled:
		return
	enabled = value
	if enabled:
		_saved_visibility.clear()
		_hide_capture_nodes()
	else:
		_restore_capture_nodes()


func _hide_capture_nodes() -> void:
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		_remember_and_hide(node)
	for node: Node in get_tree().get_nodes_in_group(&"viewmodel"):
		_remember_and_hide(node)


func _remember_and_hide(node: Node) -> void:
	if node is CanvasLayer:
		if not _saved_visibility.has(node):
			_saved_visibility[node] = (node as CanvasLayer).visible
		(node as CanvasLayer).visible = false
	elif node is Node3D:
		if not _saved_visibility.has(node):
			_saved_visibility[node] = (node as Node3D).visible
		(node as Node3D).visible = false
	elif node is CanvasItem:
		if not _saved_visibility.has(node):
			_saved_visibility[node] = (node as CanvasItem).visible
		(node as CanvasItem).visible = false


func _restore_capture_nodes() -> void:
	for node: Variant in _saved_visibility:
		if not is_instance_valid(node):
			continue
		if node is CanvasLayer:
			(node as CanvasLayer).visible = bool(_saved_visibility[node])
		elif node is Node3D:
			(node as Node3D).visible = bool(_saved_visibility[node])
		elif node is CanvasItem:
			(node as CanvasItem).visible = bool(_saved_visibility[node])
	_saved_visibility.clear()
