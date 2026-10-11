extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_proportion_editor.gd
##
## S-311.22 adds the Body page to the existing customization screen. This test
## covers its six presets, 17 native sliders, live gel preview, safe random,
## preset restore, undo and deterministic keyboard/gamepad focus path.
## S-311.27-31 also verify that the preview uses the GL Compatibility gel shader
## with a transparent centre, a denser Fresnel edge, normal-displaced screen
## refraction, a procedural studio-window reflection, thickness absorption and
## single-pass wrapped back lighting.

const SCREEN_PATH: String = "res://scripts/ui/cosmetics_panel.gd"
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var panel: Control = load(SCREEN_PATH).new()
	root.add_child(panel)
	await process_frame
	await process_frame
	var body_tab := panel.find_child("Tab_body", true, false) as Button
	_expect(body_tab != null, "customization has a Body tab")
	if body_tab == null:
		panel.free()
		quit(_failures)
		return
	body_tab.pressed.emit()
	await process_frame

	var editor: Control = panel.find_child("GelProportionEditor", true, false)
	var preview: Control = panel.find_child("CharacterPreview", true, false)
	var proportions: Resource = panel.get(&"_proportions")
	_expect(editor != null and editor.is_visible_in_tree(), "the Body tab shows the proportion editor")
	_expect(preview.get(&"gel_mannequin").visible, "the Body tab shows the gel mannequin")
	_expect(not preview.get(&"mannequin").visible, "the rounded mannequin is hidden on the Body tab")
	_check_gel_material(preview)
	if editor == null:
		panel.free()
		quit(_failures)
		return

	var picker := editor.find_child("ProportionPreset", true, false) as OptionButton
	var sliders: Array[Node] = editor.find_children("Proportion_*", "HSlider", true, false)
	_expect(picker != null and picker.item_count == 6, "all six named presets are selectable")
	_expect(sliders.size() == 17, "every proportion has one slider")
	await _check_input_contract(panel, body_tab, picker, sliders)
	_check_mouse_rotation(preview)

	var applications_before: int = preview.call(&"proportion_application_count")
	picker.select(1)
	picker.item_selected.emit(1)
	_expect(proportions.get(&"general_thickness") == -1.0, "selecting Flaca applies its values")
	_expect(
		preview.call(&"proportion_application_count") > applications_before,
		"selecting a preset updates the gel mannequin live"
	)

	var thickness := editor.find_child("Proportion_general_thickness", true, false) as HSlider
	thickness.value = -0.42
	_expect(is_equal_approx(proportions.get(&"general_thickness"), -0.42), "a slider edits the resource")
	(editor.find_child("ProportionUndo", true, false) as Button).pressed.emit()
	_expect(proportions.get(&"general_thickness") == -1.0, "Undo restores the previous slider value")
	thickness.value = 0.25
	(editor.find_child("ProportionRestore", true, false) as Button).pressed.emit()
	_expect(proportions.get(&"general_thickness") == -1.0, "Restore returns to the selected preset")

	var random := editor.find_child("ProportionRandom", true, false) as Button
	random.call(&"set_random_seed", 31_122)
	random.pressed.emit()
	_expect(Presets.is_safe(proportions.call(&"as_dictionary")), "Random produces a safe body")
	_expect(
		preview.call(&"proportion_application_count") > applications_before + 2,
		"slider, restore and random changes reach the live preview"
	)

	panel.queue_free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("PASS: gel proportion editor presets, sliders, input, preview, restore and undo")
	quit(_failures)


func _check_input_contract(
	panel: Control,
	body_tab: Button,
	picker: OptionButton,
	sliders: Array[Node]
) -> void:
	_expect(picker.focus_mode == Control.FOCUS_ALL, "the preset picker accepts keyboard and gamepad focus")
	for node: Node in sliders:
		var slider := node as HSlider
		_expect(slider.focus_mode == Control.FOCUS_ALL, "%s accepts keyboard/gamepad focus" % slider.name)
		_expect(slider.mouse_filter == Control.MOUSE_FILTER_STOP, "%s accepts mouse dragging" % slider.name)
		_expect(not slider.focus_neighbor_top.is_empty(), "%s has an explicit Up target" % slider.name)
		_expect(not slider.focus_neighbor_bottom.is_empty(), "%s has an explicit Down target" % slider.name)
	var top_target: Node = picker.get_node_or_null(picker.focus_neighbor_top)
	_expect(top_target == body_tab, "Up from the editor returns to the Body tab")
	var last := sliders[-1] as HSlider
	_expect(last.get_node_or_null(last.focus_neighbor_bottom) == panel.find_child("Done", true, false),
			"Down from the last slider reaches Done")
	_expect(_action_has_joy_motion(&"look_left") and _action_has_joy_motion(&"look_right"),
			"the preview turn actions are mapped to the right gamepad stick")
	var first := sliders[0] as HSlider
	first.value = 1.0
	first.grab_focus()
	var before: float = first.value
	var keyboard := InputEventKey.new()
	keyboard.keycode = KEY_RIGHT
	await _send_input(keyboard)
	_expect(first.value > before, "Right Arrow adjusts a focused slider")
	before = first.value
	var gamepad := InputEventJoypadButton.new()
	gamepad.button_index = JOY_BUTTON_DPAD_RIGHT
	await _send_input(gamepad)
	_expect(first.value > before, "gamepad D-pad Right adjusts a focused slider")


func _check_mouse_rotation(preview: Control) -> void:
	var gel: Node3D = preview.get(&"gel_mannequin")
	var before: float = gel.rotation.y
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	preview.call(&"_gui_input", press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(24.0, 0.0)
	preview.call(&"_gui_input", drag)
	preview.call(&"_process", 0.0)
	_expect(not is_equal_approx(gel.rotation.y, before), "mouse drag turns the gel mannequin")


func _check_gel_material(preview: Control) -> void:
	var gel: Node3D = preview.get(&"gel_mannequin")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(gel)
	var material: ShaderMaterial = mesh.material_override as ShaderMaterial if mesh != null else null
	_expect(material == GEL_MATERIAL,
		"the gel preview uses the shared GL Compatibility material")
	if material == null:
		return
	var center: float = material.get_shader_parameter(&"center_opacity")
	var edge: float = material.get_shader_parameter(&"edge_opacity")
	var density: float = material.get_shader_parameter(&"edge_density")
	var refraction_strength: float = material.get_shader_parameter(&"refraction_strength")
	var refraction_mix: float = material.get_shader_parameter(&"refraction_mix")
	var roughness: float = material.get_shader_parameter(&"roughness")
	var specular: float = material.get_shader_parameter(&"specular")
	var subsurface_wrap: float = material.get_shader_parameter(&"subsurface_wrap")
	var backlight_strength: float = material.get_shader_parameter(&"backlight_strength")
	var backlight_power: float = material.get_shader_parameter(&"backlight_power")
	var studio_strength: float = material.get_shader_parameter(&"studio_reflection_strength")
	var studio_softness: float = material.get_shader_parameter(&"studio_reflection_softness")
	var thickness_map: Texture2D = material.get_shader_parameter(&"thickness_map") as Texture2D
	var thickness_decode: float = material.get_shader_parameter(&"thickness_decode_meters")
	var absorption: float = material.get_shader_parameter(&"absorption_coefficient")
	var absorption_color: float = material.get_shader_parameter(&"absorption_color_mix")
	var absorption_opacity: float = material.get_shader_parameter(&"absorption_opacity")
	_expect(center > 0.0 and center < edge and edge <= 1.0,
		"the gel centre is transparent and the Fresnel edge is denser")
	_expect(density > 0.0 and density <= 1.0,
		"the Fresnel edge also carries extra colour density")
	_expect(refraction_strength > 0.0 and refraction_mix > 0.0,
		"the shared gel material enables background refraction")
	_expect(roughness <= 0.1 and specular >= 0.85,
		"the studio reflection uses a crisp low-roughness specular surface")
	_expect(subsurface_wrap > 0.0 and subsurface_wrap <= 1.0,
		"the gel wraps direct light around its silhouette")
	_expect(backlight_strength > 0.0 and backlight_power > 1.0,
		"the gel enables focused fake subsurface transmission at back-light")
	_expect(material.next_pass == null,
		"the fake subsurface glow stays in the shared material's single pass")
	_expect(studio_strength > 0.0 and studio_softness > 0.0,
		"the shared gel material enables its procedural studio matcap")
	_expect(thickness_map != null and thickness_map.get_width() == 1024,
		"the shared gel material loads the baked base-body thickness map")
	_expect(thickness_decode == 2.0 and absorption > 0.0,
		"the thickness map is decoded in metres for Beer-Lambert absorption")
	_expect(absorption_color > 0.0 and absorption_opacity > 0.0,
		"thicker gel gains colour and opacity")
	var shader_code: String = material.shader.code
	_expect(
		shader_code.contains("hint_screen_texture")
		and shader_code.contains("SCREEN_UV")
		and shader_code.contains("NORMAL.xy"),
		"GL Compatibility refraction reads the screen and displaces it by the normal"
	)
	_expect(
		shader_code.contains("matcap_uv")
		and shader_code.contains("window_reflection")
		and shader_code.contains("studio_ribbon_width")
		and shader_code.contains("EMISSION"),
		"the studio window and ribbon stay visible against a dark sky"
	)
	_expect(
		shader_code.contains("texture(thickness_map, UV).r")
		and shader_code.contains("exp(-absorption_coefficient * thickness_meters)")
		and shader_code.contains("thickness_absorption * absorption_opacity"),
		"the shader attenuates transmission and raises opacity from baked thickness"
	)
	_expect(
		shader_code.contains("void light()")
		and shader_code.contains("wrapped_light")
		and shader_code.contains("back_scatter")
		and shader_code.contains("DIFFUSE_LIGHT"),
		"the same shader pass adds wrapped diffuse and light-driven back scatter"
	)


func _action_has_joy_motion(action: StringName) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return true
	return false


func _send_input(event: InputEvent) -> void:
	event.set(&"pressed", true)
	Input.parse_input_event(event)
	await process_frame
	event.set(&"pressed", false)
	Input.parse_input_event(event)
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
