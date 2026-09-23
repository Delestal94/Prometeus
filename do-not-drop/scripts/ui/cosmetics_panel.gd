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
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	center.add_child(outer)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	outer.add_child(columns)
	var people: VBoxContainer = UiTheme.panel(columns, Vector2(470, 0), 22)
	people.add_theme_constant_override("separation", 12)
	_section(people, "Uniforme", "Tu color, igual para todos en la partida.",
		UnlockManager.cosmetic_choices(), UnlockManager.selected_cosmetic, UnlockManager.select_cosmetic)
	# The truck and its paint (docs/tareas-nacho.md #85-#89): the host's
	# choice is the one the whole crew drives.
	var truck: VBoxContainer = UiTheme.panel(columns, Vector2(470, 0), 22)
	truck.add_theme_constant_override("separation", 12)
	_section(truck, "Camión", "Si sos el anfitrión, es el que maneja toda la tripulación.",
		UnlockManager.truck_choices(), UnlockManager.selected_truck, UnlockManager.select_truck)
	_section(truck, "Pintura", "",
		UnlockManager.paint_choices(), UnlockManager.selected_paint, UnlockManager.select_paint)
	var close_button: Button = UiTheme.button(outer, "Volver", false, Vector2(0, 48))
	close_button.pressed.connect(func() -> void: hide(); closed.emit())


func _section(column: VBoxContainer, title: String, subtitle: String, choices: Array[Dictionary], selected: StringName, select: Callable) -> void:
	UiTheme.title(column, title, 30)
	if subtitle != "":
		UiTheme.label(column, subtitle, 15, UiTheme.MUTED)
	for choice: Dictionary in choices:
		var id: StringName = choice["id"]
		var available: bool = bool(choice["available"])
		var label: String = String(choice["title"])
		if choice.has("detail"):
			label += "  ·  " + String(choice["detail"])
		if not available:
			var rule: Dictionary = UnlockManager.requirements(StringName(choice["unlock"]))
			label += "  — bloqueado (%d entregas, %d puntos)" % [int(rule.get("deliveries", 0)), int(rule.get("score", 0))]
		var button: Button = UiTheme.button(column, label, id == selected, Vector2(0, 44))
		button.disabled = not available
		button.clip_text = true
		if choice.has("color"):
			var style := StyleBoxFlat.new()
			style.bg_color = Color(choice["color"])
			style.set_corner_radius_all(8)
			button.add_theme_stylebox_override("hover", style)
		button.pressed.connect(func() -> void:
			if select.call(id):
				_refresh()
		)


func _refresh() -> void:
	for child: Node in get_children():
		child.queue_free()
	call_deferred("_build")
