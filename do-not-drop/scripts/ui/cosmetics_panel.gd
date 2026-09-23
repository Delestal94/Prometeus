class_name CosmeticsPanel
extends Control

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	UiTheme.apply(self)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.06, 0.08, 0.92)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(550, 0), 26)
	column.add_theme_constant_override("separation", 14)
	UiTheme.title(column, "Uniforme", 36)
	UiTheme.label(column, "Tu color se guarda en este equipo y se muestra igual a todos en la partida.", 16, UiTheme.MUTED)
	for choice: Dictionary in UnlockManager.cosmetic_choices():
		var id: StringName = choice["id"]
		var available: bool = bool(choice["available"])
		var label: String = String(choice["title"])
		if not available:
			var rule: Dictionary = UnlockManager.requirements(StringName(choice["unlock"]))
			label += "  — bloqueado (%d entregas, %d puntos)" % [int(rule.get("deliveries", 0)), int(rule.get("score", 0))]
		var button: Button = UiTheme.button(column, label, id == UnlockManager.selected_cosmetic, Vector2(0, 48))
		button.disabled = not available
		var style := StyleBoxFlat.new()
		style.bg_color = Color(choice["color"])
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		button.add_theme_stylebox_override("hover", style)
		button.pressed.connect(func() -> void:
			if UnlockManager.select_cosmetic(id):
				_refresh()
		)
	var close_button: Button = UiTheme.button(column, "Volver", false, Vector2(0, 48))
	close_button.pressed.connect(func() -> void: hide(); closed.emit())


func _refresh() -> void:
	for child: Node in get_children():
		child.queue_free()
	call_deferred("_build")
