class_name CosmeticsPanel
extends Control

const PLAYER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_rounded.glb")
const Catalog = preload("res://scripts/presentation/face_catalog.gd")
const FacePreview = preload("res://scripts/ui/face_preview.gd")
const CharacterFace = preload("res://scripts/presentation/character_face.gd")
signal closed
var _face_preview: Control
var _face_caption: Label
var _mannequin: Node3D
var _mannequin_face: BoneAttachment3D
var _tabs: TabContainer
var _face_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build(active_tab: int = 0) -> void:
	_face_buttons.clear()
	UiTheme.apply(self)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.06, 0.08, 0.94)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	UiTheme.title(outer, "Hacé tu personaje", 32, UiTheme.PAPER)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)
	var preview: VBoxContainer = UiTheme.panel(columns, Vector2(310, 0), 16)
	UiTheme.tag(preview, "ASÍ QUEDA", UiTheme.YELLOW, 0)
	_face_preview = FacePreview.new()
	_face_preview.name = "FacePreview"
	_face_preview.custom_minimum_size = Vector2(270, 218)
	preview.add_child(_face_preview)
	_face_caption = UiTheme.label(preview, "", 15)
	_face_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_uniform_preview(preview)
	UiTheme.label(preview, "Tu personaje dentro del juego", 13, UiTheme.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var settings: VBoxContainer = UiTheme.panel(columns, Vector2(550, 0), 16)
	settings.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for role: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var style := StyleBoxFlat.new()
		style.bg_color = UiTheme.YELLOW if role == "tab_selected" else UiTheme.PAPER
		style.content_margin_left = 22; style.content_margin_right = 22
		style.content_margin_top = 10; style.content_margin_bottom = 10
		style.set_corner_radius_all(8)
		_tabs.add_theme_stylebox_override(role, style)
	_tabs.add_theme_color_override("font_selected_color", UiTheme.INK)
	_tabs.add_theme_color_override("font_unselected_color", UiTheme.MUTED)
	_tabs.add_theme_font_override("font", UiTheme.display_font())
	_tabs.add_theme_font_size_override("font_size", 21)
	settings.add_child(_tabs)
	var face: VBoxContainer = _tab("Rostro")
	UiTheme.label(face, "Combiná los ojos y la boca como quieras.", 16, UiTheme.MUTED)
	_face_choices(face, "Ojos", "eyes", Catalog.EYES)
	_face_choices(face, "Boca", "mouth", Catalog.MOUTHS)
	var uniform: VBoxContainer = _tab("Uniforme")
	_section(uniform, "Tu uniforme", "Se ve igual para toda la tripulación.",
		UnlockManager.cosmetic_choices(), UnlockManager.selected_cosmetic, UnlockManager.select_cosmetic)
	var truck: VBoxContainer = _tab("Camión")
	_section(truck, "Camión", "Si sos el anfitrión, lo usa toda la tripulación.",
		UnlockManager.truck_choices(), UnlockManager.selected_truck, UnlockManager.select_truck)
	_section(truck, "Pintura", "", UnlockManager.paint_choices(), UnlockManager.selected_paint, UnlockManager.select_paint)
	_tabs.current_tab = active_tab
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 18)
	outer.add_child(footer)
	UiTheme.label(footer, "Tus cambios se guardan automáticamente", 15, UiTheme.PAPER).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var done: Button = UiTheme.button(footer, "Listo", true, Vector2(180, 48))
	done.name = "Done"
	done.pressed.connect(close)
	_refresh_face()

func open() -> void:
	show()
	_grab_first_button.call_deferred()

func close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

func _tab(label: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = label
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 12)
	scroll.add_child(contents)
	return contents

func _face_choices(parent: VBoxContainer, title: String, kind: String, options: Dictionary) -> void:
	UiTheme.title(parent, title, 23)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for id: StringName in options:
		var button: Button = UiTheme.button(grid, "", false, Vector2(108, 78))
		button.name = kind.capitalize() + "_" + String(id)
		button.tooltip_text = title + ": " + String(options[id])
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("kind", kind)
		button.set_meta("choice", id)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 8; content.offset_right = -8
		content.offset_top = 7; content.offset_bottom = -7
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)
		var icon := TextureRect.new()
		icon.texture = Catalog.thumbnail(kind, id)
		icon.custom_minimum_size = Vector2(72, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		var label := UiTheme.label(content, String(options[id]), 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.pressed.connect(func() -> void:
			if kind == "eyes": UnlockManager.select_eyes(id)
			else: UnlockManager.select_mouth(id)
			_refresh_face()
		)
		_face_buttons.append(button)
		buttons.append(button)
	_wire_grid_focus(buttons, grid.columns)

func _wire_grid_focus(buttons: Array[Button], columns: int) -> void:
	for index: int in buttons.size():
		var button: Button = buttons[index]
		var column: int = index % columns
		var neighbors: Dictionary = {
			&"focus_neighbor_left": buttons[index - 1] if column > 0 else button,
			&"focus_neighbor_right": buttons[index + 1] if column < columns - 1 and index + 1 < buttons.size() else button,
			&"focus_neighbor_top": buttons[index - columns] if index >= columns else button,
			&"focus_neighbor_bottom": buttons[index + columns] if index + columns < buttons.size() else button,
		}
		for property: StringName in neighbors:
			button.set(property, button.get_path_to(neighbors[property]))

func _grab_first_button() -> void:
	for node: Node in find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return

func _refresh_face() -> void:
	_face_preview.shirt_color = UnlockManager.cosmetic_color()
	_face_preview.set_expression(UnlockManager.selected_eyes, UnlockManager.selected_mouth)
	_face_caption.text = "%s · %s" % [Catalog.EYES[UnlockManager.selected_eyes], Catalog.MOUTHS[UnlockManager.selected_mouth]]
	if _mannequin_face != null:
		_mannequin_face.set_expression(UnlockManager.selected_eyes, UnlockManager.selected_mouth)
	for button: Button in _face_buttons:
		var selected: StringName = UnlockManager.selected_eyes if button.get_meta("kind") == "eyes" else UnlockManager.selected_mouth
		var chosen: bool = button.get_meta("choice") == selected
		button.set_pressed_no_signal(chosen)
		var style := UiTheme.surface_style(6, UiTheme.MINT if chosen else UiTheme.WHITE)
		style.shadow_size = 0; style.shadow_offset = Vector2.ZERO
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("pressed", style)

func _section(column: VBoxContainer, title: String, subtitle: String, choices: Array[Dictionary], selected: StringName, select: Callable) -> void:
	UiTheme.title(column, title, 26)
	if subtitle != "": UiTheme.label(column, subtitle, 15, UiTheme.MUTED)
	for choice: Dictionary in choices:
		var id: StringName = choice["id"]
		var available: bool = bool(choice["available"])
		var label: String = String(choice["title"])
		if choice.has("detail"): label += " · " + String(choice["detail"])
		if not available:
			var rule: Dictionary = UnlockManager.requirements(StringName(choice["unlock"]))
			label += " — %d entregas / %d puntos" % [int(rule.get("deliveries", 0)), int(rule.get("score", 0))]
		var button: Button = UiTheme.button(column, label, id == selected, Vector2(0, 44))
		button.disabled = not available; button.clip_text = true
		button.pressed.connect(func() -> void:
			if select.call(id): _refresh()
		)

func _build_uniform_preview(parent: Node) -> void:
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(0, 138)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.stretch = true
	parent.add_child(frame)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(278, 150)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	frame.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = UiTheme.PAPER
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.9
	camera.position = Vector3(1.7, 1.2, -4.0)
	camera.look_at(Vector3(0, 0.84, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -145, 0)
	world.add_child(light)
	_mannequin = PLAYER_SCENE.instantiate() as Node3D
	_mannequin.name = "UniformMannequin"
	world.add_child(_mannequin)
	_tint_first_mesh(_mannequin, UnlockManager.cosmetic_color())
	var skeleton := _find(_mannequin, "Skeleton3D") as Skeleton3D
	_mannequin_face = CharacterFace.new()
	_mannequin_face.setup(_mannequin, skeleton, 1)
	var animation := _find(_mannequin, "AnimationPlayer") as AnimationPlayer
	if animation != null and animation.has_animation("Idle"):
		animation.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		animation.play("Idle")

func _tint_first_mesh(node: Node, color: Color) -> void:
	var mesh := _find(node, "MeshInstance3D") as MeshInstance3D
	if mesh == null: return
	for surface: int in mesh.mesh.get_surface_count():
		var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		if source == null or source.resource_name not in ["Shirt", "ShirtTrim"]: continue
		var material := source.duplicate() as StandardMaterial3D
		material.albedo_color = color.darkened(0.18) if source.resource_name == "ShirtTrim" else color
		mesh.set_surface_override_material(surface, material)

func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name): return node
	for child: Node in node.get_children():
		var result: Node = _find(child, type_name)
		if result != null: return result
	return null

func _refresh() -> void:
	var tab: int = _tabs.current_tab
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build(tab)
	if visible:
		_grab_first_button.call_deferred()
