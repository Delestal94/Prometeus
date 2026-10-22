extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_sound_subtitles.gd
##
## Sound subtitles for everything that only sounds (N-965), the queue in
## ui/hud/hud_prompts.gd over ui/hud/sound_subtitle_queue.gd:
## - with GameSettings.sound_subtitles off nothing shows; turning it off clears
##   what was up;
## - each EventBus event with a game meaning shows its translated HUD_SUB_* text:
##   another player's horn (with who, and the arrow to the truck; your own does
##   not), the doorbell of that house and the customer's cheer or groan by
##   outcome (a box lost on the road rang nothing), a wrong box refused at the
##   door, the three animals that go for a box, and the rain when the run starts;
## - several at once, highest priority first, at most MAX_VISIBLE lines; the
##   same event again refreshes its line instead of stacking;
## - each expires on its own clock (horn 1.5 s, bell 2.5 s) as the HUD ticks;
## - the at-risk trap's standing subtitle (refresh_sound_subtitle) still shows,
##   above the queue;
## - N-983: the subtitles have a plate of their own (subtitle_label, under the
##   prompt with a 4 px gap), apart from the interaction prompt, and in cream, not
##   the prompt's paper; the prompt draws its key as a keycap, not "[ E ]";
## - N-983.2: the at-risk trap's standing line carries the cargo card's "EN RIESGO !"
##   chip, so it is told apart by more than colour;
##   the chip follows the colour-blind palette live; the prompt's action icon is drawn
##   (not clipped by the label) and both plates keep their text centred;
## - N-983.3: the subtitle size option (normal / large / very large, up to 1.5x)
##   scales only the subtitle plate, clamps, and shows up in the options panel;
## - N-983.4: a faint text backdrop (under 0.5) thickens the text outline by 1 px;
## - N-983.5: the top-right card's "CARTA: <name> • G usar" stays on one line,
##   cutting a long name with "…", and still fits the top bar on a 4:3 window
##   with the largest HUD size;
## - arrow(): ahead, behind, left, right, and none when it is on top of you.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var bus: Node = root.get_node("EventBus")
	var network: Node = root.get_node("NetworkManager")
	var run_manager: Node = root.get_node("RunManager")
	var original: bool = settings.sound_subtitles
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var me: int = network.local_id()
	var other: int = me + 6

	# --- off: silence ---
	settings.sound_subtitles = false
	bus.horn_honked.emit(other)
	bus.cargo_animal_alert.emit(&"gull", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(String(hud.subtitle_label.text).is_empty(),
		"Subtitles off: no subtitle at all (got '%s')" % hud.subtitle_label.text)

	# --- the horn ---
	settings.sound_subtitles = true
	bus.horn_honked.emit(me)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(String(hud.subtitle_label.text).is_empty(),
		"Your own horn is not captioned (got '%s')" % hud.subtitle_label.text)
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	var horn_text: String = hud.prompts.tr("HUD_SUB_HORN") % (hud.prompts.tr("UI_PLAYER_N") % other)
	_expect(_text(hud) == horn_text,
		"Another player's horn names who honked (want '%s', got '%s')" % [horn_text, _text(hud)])
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == horn_text, "A second honk refreshes the line, it does not stack (got '%s')" % _text(hud))

	# --- the horn with a direction: the truck is to the right of the camera ---
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var truck := Node3D.new()
	truck.add_to_group(&"vehicle")
	root.add_child(truck)
	truck.global_position = Vector3(12.0, 0.0, 0.0)
	await process_frame
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == "→ " + horn_text,
		"The horn shows the arrow to the truck (got '%s')" % _text(hud))
	truck.global_position = Vector3(0.0, 0.0, -12.0)
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == "↑ " + horn_text, "A truck ahead gets the up arrow (got '%s')" % _text(hud))
	truck.free()
	camera.free()
	hud.prompts.refresh_sound_subtitle(5.0)
	_expect(_text(hud).is_empty(), "Everything expires after its seconds (got '%s')" % _text(hud))

	# --- the doorbell and the customer ---
	var bell_two: String = hud.prompts.tr("HUD_SUB_DOORBELL") % 3
	bus.house_delivery_recorded.emit(2, &"delivered_ok", &"p1")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(bell_two) and _text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_CHEER")),
		"A good delivery captions the bell of house 3 and the cheer (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(0, &"delivered_ruined", &"p2")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(hud.prompts.tr("HUD_SUB_DOORBELL") % 1)
			and _text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_GROAN")),
		"A ruined delivery captions the bell and the groan (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(0, &"delivered_at_risk", &"p2")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_GROAN")),
		"A dented delivery also groans (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(1, &"missed", &"")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "A door closed by its deadline rang nothing (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	bus.house_delivery_recorded.emit(1, &"lost", &"p3")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "A box lost on the road rang no bell (got '%s')" % _text(hud))
	bus.house_refused_package.emit(3, "A-1")
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).contains(hud.prompts.tr("HUD_SUB_DOORBELL") % 4)
			and _text(hud).contains(hud.prompts.tr("HUD_SUB_CLIENT_REFUSE")),
		"A wrong box captions the bell and the grumble (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)

	# --- the animals ---
	for animal: Array in [[&"gull", "HUD_SUB_GULL"], [&"dog", "HUD_SUB_DOG"], [&"bees", "HUD_SUB_BEES"]]:
		bus.cargo_animal_alert.emit(animal[0], &"box", 3.0, 4.0)
		hud.prompts.refresh_sound_subtitle(0.0)
		_expect(_text(hud) == hud.prompts.tr(animal[1]),
			"The %s alert shows %s (got '%s')" % [animal[0], animal[1], _text(hud)])
		hud.prompts.refresh_sound_subtitle(5.0)
	bus.cargo_animal_alert.emit(&"unicorn", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "An animal with no sound of its own shows nothing (got '%s')" % _text(hud))
	bus.cargo_animal_alert.emit(&"gull", &"box", 0.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "An alert with no warning time shows nothing (got '%s')" % _text(hud))
	bus.cargo_animal_alert.emit(&"gull", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	bus.cargo_animal_ended.emit(&"gull", &"box", &"scared", other)
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "The animal leaving takes its subtitle away (got '%s')" % _text(hud))

	# --- the rain ---
	bus.run_started.emit(&"test_route", [])
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud).is_empty(), "A dry route captions no rain (got '%s')" % _text(hud))
	var rain := AudioStreamPlayer.new()
	rain.name = "RainSound"
	root.add_child(rain)
	bus.run_started.emit(&"test_route", [])
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(_text(hud) == hud.prompts.tr("HUD_SUB_RAIN"), "A raining route captions the rain (got '%s')" % _text(hud))
	rain.free()
	hud.prompts.refresh_sound_subtitle(10.0)

	# --- several at once: priority order, a cap, expiry on each one's clock ---
	bus.house_delivery_recorded.emit(0, &"delivered_ok", &"p")
	bus.horn_honked.emit(other)
	bus.cargo_animal_alert.emit(&"dog", &"box", 3.0, 4.0)
	hud.prompts.refresh_sound_subtitle(0.0)
	var lines: PackedStringArray = _text(hud).split("\n")
	_expect(lines.size() == 3, "At most 3 subtitles show at once (got %d: '%s')" % [lines.size(), _text(hud)])
	_expect(lines[0] == hud.prompts.tr("HUD_SUB_DOG"), "The animal outranks the rest (got '%s')" % lines[0])
	_expect(lines[1] == horn_text, "The horn comes before the bell (got '%s')" % lines[1])
	hud.prompts.refresh_sound_subtitle(1.6)
	_expect(not _text(hud).contains(horn_text),
		"The horn expired after 1.5 s while the bell stays (got '%s')" % _text(hud))
	_expect(_text(hud).contains(bell_one(hud)), "The bell lasts longer than the horn (got '%s')" % _text(hud))
	hud.prompts.refresh_sound_subtitle(5.0)
	_expect(_text(hud).is_empty(), "All of it expired (got '%s')" % _text(hud))

	# --- the at-risk trap's standing subtitle stays, on top ---
	run_manager.cargo[&"sub_box"] = {"integrity": 35.0, "maximum": 100.0, "state": 1}
	bus.cargo_registered.emit(&"sub_box", "HUD_TRAP_FRAGILE")
	bus.package_state_changed.emit(&"sub_box", 1)
	bus.interaction_prompt_changed.emit("")
	bus.horn_honked.emit(other)
	hud.prompts.refresh_sound_subtitle(0.0)
	var standing: PackedStringArray = _text(hud).split("\n")
	_expect(standing.size() == 2 and standing[0].ends_with(hud.prompts.tr("HUD_SUB_FRAGILE"))
			and standing[1] == horn_text,
		"The trap's subtitle keeps its place above the queue (got '%s')" % _text(hud))
	# N-983.2: the standing line has the cargo card's "EN RIESGO !" chip (a shape and a
	# word, not only a colour); the queued ones, like the horn, do not.
	var at_risk_word: String = hud.prompts.tr("HUD_STATE_AT_RISK")
	_expect(standing[0].contains(at_risk_word) and not standing[1].contains(at_risk_word),
		"Only the trap at risk carries the EN RIESGO marker (got '%s')" % _text(hud))
	_expect(String(hud.subtitle_label.text).contains("[bgcolor="),
		"The at-risk marker is a chip with its own fill, not only coloured text")
	await _check_plates(hud, settings, bus, horn_text)
	run_manager.cargo.erase(&"sub_box")

	# --- turning the option off clears the queue ---
	settings.sound_subtitles = false
	hud.prompts.refresh_sound_subtitle(0.0)
	_expect(not _text(hud).contains(horn_text), "Turning subtitles off clears the queue (got '%s')" % _text(hud))

	# --- the arrow, from the point in the camera's space ---
	var arrow_script: GDScript = load("res://scripts/ui/hud/sound_subtitle_queue.gd")
	_expect(arrow_script.arrow(Vector3(10, 0, 1)) == "→", "Right of the view is the right arrow")
	_expect(arrow_script.arrow(Vector3(-10, 0, 1)) == "←", "Left of the view is the left arrow")
	_expect(arrow_script.arrow(Vector3(1, 0, -10)) == "↑", "Ahead is the up arrow")
	_expect(arrow_script.arrow(Vector3(1, 0, 10)) == "↓", "Behind is the down arrow")
	_expect(arrow_script.arrow(Vector3(1, 5, -1)) == "", "On top of the listener there is no arrow")

	await _check_card_line(hud)
	await _check_options(settings)
	settings.sound_subtitles = original
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: every sound with a game meaning shows its subtitle, queued, capped and expiring")
	quit(_failures)


func bell_one(hud: CanvasLayer) -> String:
	return hud.prompts.tr("HUD_SUB_DOORBELL") % 1


## What the subtitle plate shows (brackets and all), not its BBCode.
func _text(hud: CanvasLayer) -> String:
	return hud.subtitle_label.get_parsed_text()


## N-983.1, .3 and .4: the prompt and the subtitles on two plates, the cream, the
## keycap, the size option that scales only the subtitle plate, the outline.
func _check_plates(hud: CanvasLayer, settings: Node, bus: Node, horn_text: String) -> void:
	var prompt_label: RichTextLabel = hud.interaction_label
	var sub_label: RichTextLabel = hud.subtitle_label
	hud.dashboard.show()
	bus.interaction_prompt_changed.emit("Agarrar paquete")
	await process_frame
	await process_frame
	var shown_prompt: String = prompt_label.get_parsed_text()
	_expect(shown_prompt.contains("Agarrar paquete") and not shown_prompt.contains(horn_text),
		"The prompt plate holds the prompt and no sound (got '%s')" % shown_prompt)
	_expect(not _text(hud).contains("Agarrar") and _text(hud).contains(horn_text),
		"The subtitle plate holds the sounds and not the prompt (got '%s')" % _text(hud))
	_expect(String(prompt_label.text).contains("[bgcolor=") and not shown_prompt.contains("[ E ]"),
		"The prompt draws its key as a keycap, not as [ E ] text (got '%s')" % shown_prompt)
	_expect(sub_label != prompt_label and sub_label.get_parent() == prompt_label.get_parent()
			and sub_label.get_index() == prompt_label.get_index() + 1,
		"The subtitle plate is its own node, right under the prompt's")
	_expect(hud.prompt_stack.get_theme_constant("separation") == 4,
		"4 px of air between the prompt plate and the subtitle plate")
	_expect(prompt_label.visible and sub_label.visible
			and sub_label.get_global_rect().position.y >= prompt_label.get_global_rect().end.y - 0.01,
		"The subtitles sit below the prompt, not over it")
	_expect(sub_label.get_theme_color(&"default_color").is_equal_approx(Color("fff3d6")),
		"The subtitles are cream (#FFF3D6)")
	_expect(not sub_label.get_theme_color(&"default_color").is_equal_approx(
			prompt_label.get_theme_color(&"default_color")),
		"The subtitles are not the prompt's colour")
	# The action icon sits just left of the prompt plate, on screen and not clipped.
	var icon_rect: Rect2 = hud.interaction_icon.get_global_rect()
	_expect(hud.interaction_icon.visible and not prompt_label.clip_contents
			and icon_rect.size.x > 0.0 and icon_rect.end.x <= prompt_label.get_global_rect().position.x + 0.01
			and hud.hud_layer.get_global_rect().encloses(icon_rect),
		"The prompt's action icon is drawn left of the plate, inside the screen (got %s)" % icon_rect)
	_expect(prompt_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
			and sub_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"Both plates keep their text centred")
	# The at-risk chip follows the colour-blind palette live.
	var original_palette: bool = settings.colorblind_palette
	settings.colorblind_palette = true
	_expect(String(sub_label.text).contains(UiTheme.OKABE_ORANGE.to_html(false)),
		"The EN RIESGO chip takes the colour-blind palette as soon as it is switched")
	settings.colorblind_palette = original_palette
	bus.interaction_prompt_changed.emit("")
	await process_frame
	_expect(not prompt_label.visible and sub_label.visible,
		"Without a prompt only the subtitle plate shows (no empty plate)")

	# The size option scales the subtitle plate and nothing else.
	var base: int = hud.PILL_FONT_SIZE
	var prompt_before: int = prompt_label.get_theme_font_size(&"normal_font_size")
	var hint_before: int = hud.hint_label.get_theme_font_size(&"normal_font_size")
	var original_scale: float = settings.subtitle_scale
	for step: Array in [[1.0, 1.0], [1.25, 1.25], [1.5, 1.5], [3.0, 1.5], [0.2, 1.0]]:
		settings.subtitle_scale = step[0]
		var want: int = roundi(float(base) * float(step[1]))
		_expect(sub_label.get_theme_font_size(&"normal_font_size") == want,
			"Subtitle size %.2f draws the plate at %d (got %d)" % [
				step[0], want, sub_label.get_theme_font_size(&"normal_font_size")])
	settings.subtitle_scale = 1.5
	_expect(sub_label.get_theme_font_size(&"normal_font_size") > base,
		"Very large subtitles are bigger than normal")
	_expect(prompt_label.get_theme_font_size(&"normal_font_size") == prompt_before
			and hud.hint_label.get_theme_font_size(&"normal_font_size") == hint_before,
		"The size option leaves the prompt and the controls bar alone")
	_expect(settings.SAVED_KEYS.has(&"subtitle_scale"), "The subtitle size is one of the saved settings")
	settings.subtitle_scale = original_scale

	# N-983.4: a faint plate gets a thicker outline; the 0.3 floor does not move.
	var original_opacity: float = settings.text_backdrop_opacity
	settings.text_backdrop_opacity = 0.88
	var solid_outline: int = sub_label.get_theme_constant(&"outline_size")
	settings.text_backdrop_opacity = settings.TEXT_BACKDROP_MIN
	_expect(sub_label.get_theme_constant(&"outline_size") == solid_outline + 1
			and prompt_label.get_theme_constant(&"outline_size") == solid_outline + 1,
		"A faint plate thickens the outline by 1 px on both plates")
	_expect(is_equal_approx(settings.text_backdrop_opacity, 0.3), "The backdrop floor is still 0.3")
	settings.text_backdrop_opacity = original_opacity


## N-983.5: the card line is one line, with the key, whatever the card's name.
func _check_card_line(hud: CanvasLayer) -> void:
	var progression: Node = root.get_node("CrewProgression")
	var network: Node = root.get_node("NetworkManager")
	var me: int = network.local_id()
	var had_card: bool = progression.cards.has(me)
	var original_card: int = int(progression.cards.get(me, -1))
	hud.dashboard.show()
	var use_key: String = root.get_node("GameSettings").key_label(&"use_card")
	var card_width: float = hud.card_label.custom_minimum_size.x
	for card_id: int in progression.CARD_NAMES.keys():
		progression.cards[me] = card_id
		hud.notices.refresh_card()
		await process_frame
		var line_width: float = hud.card_label.get_content_width()
		_expect(hud.card_label.get_line_count() == 1 and line_width <= card_width + 8.0,
			"The card line fits its %d-wide card on one line for card %d (got %d lines, %d wide: '%s')" % [
				card_width, card_id, hud.card_label.get_line_count(), line_width, hud.card_label.get_parsed_text()])
		_expect(hud.card_label.get_parsed_text().contains(" %s " % use_key),
			"The card's use key stays on the line for card %d" % card_id)
	# A very long name is cut with an ellipsis, the key is kept.
	var cut: String = hud.notices.fit_card_line("Un nombre de carta largo largo largo largo largo", "G  usar")
	_expect(cut.contains("…") and cut.ends_with("G  usar"), "A long card name is cut with … (got '%s')" % cut)
	var short: String = hud.notices.fit_card_line("Re", "G  usar")
	_expect(short.contains("Re") and not short.contains("…"), "A short name is left whole (got '%s')" % short)
	await _check_card_room(hud, progression, me)
	if had_card:
		progression.cards[me] = original_card
	else:
		progression.cards.erase(me)
	hud.notices.refresh_card()


## N-983 (closing check): the 320-wide card line still fits the top bar on a 4:3
## window with the largest HUD size, the narrowest the HUD's own space gets
## (Hud.layout_scale grows with the window's height): the right column stays on
## screen and clear of the objective card on the left.
func _check_card_room(hud: CanvasLayer, progression: Node, me: int) -> void:
	var settings: Node = root.get_node("GameSettings")
	var original_size: Vector2i = root.size
	var original_scale: float = settings.hud_scale
	progression.cards[me] = progression.CARD_NAMES.keys()[0]
	hud.notices.refresh_card()
	for shape: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 960)]:
		root.size = shape
		settings.hud_scale = settings.HUD_SCALE_MAX
		hud.apply_hud_scale()
		await process_frame
		await process_frame
		var layer: Control = hud.hud_layer
		var expected_scale: float = settings.HUD_SCALE_MAX * float(shape.y) / 720.0
		_expect(is_equal_approx(layer.scale.x, expected_scale),
			"At %s the HUD lays out at %.2f (got %.2f): the window shape took" % [shape, expected_scale, layer.scale.x])
		var to_layer: Transform2D = layer.get_global_transform().affine_inverse()
		var column: Control = hud.get(&"_right_column")
		var objective: Control = column.get_parent().get_child(0)
		var column_left: float = (to_layer * column.get_global_transform() * Vector2.ZERO).x
		var column_right: float = (to_layer * column.get_global_transform() * Vector2(column.size.x, 0)).x
		var objective_right: float = (to_layer * objective.get_global_transform() * Vector2(objective.size.x, 0)).x
		_expect(column_right <= layer.size.x + 0.5,
			"At %s and the largest HUD the card column ends on screen (%d of %d)" % [shape, column_right, layer.size.x])
		_expect(objective_right <= column_left,
			"At %s and the largest HUD the card column clears the objective card (%d vs %d)" % [
				shape, objective_right, column_left])
		_expect(hud.card_label.get_line_count() == 1,
			"At %s and the largest HUD the card line stays on one line" % shape)
	root.size = original_size
	settings.hud_scale = original_scale
	hud.apply_hud_scale()


## N-983.3: the options panel offers the size with the other accessibility
## options, and picking one sets GameSettings.
func _check_options(settings: Node) -> void:
	var original_scale: float = settings.subtitle_scale
	var options: Control = load("res://scripts/ui/options_panel.gd").new()
	root.add_child(options)
	await process_frame
	var picker: OptionButton = options._subtitle_size_option
	_expect(picker != null and picker.item_count == 3 and picker.focus_mode != Control.FOCUS_NONE,
		"Options has a focusable 3-step subtitle size picker (gamepad reaches it)")
	if picker != null:
		picker.item_selected.emit(2)
		_expect(is_equal_approx(settings.subtitle_scale, 1.5), "Picking 'very large' sets 1.5x")
		picker.item_selected.emit(0)
		_expect(is_equal_approx(settings.subtitle_scale, 1.0), "Picking 'normal' sets 1x")
		settings.subtitle_scale = 1.25
		options._sync_from_settings()
		_expect(picker.selected == 1, "The picker follows the setting after a sync")
	options.queue_free()
	settings.subtitle_scale = original_scale


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
