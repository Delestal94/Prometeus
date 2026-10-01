extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_customization_screen.gd
##
## The appearance screen (N-506, scripts/ui/cosmetics_panel.gd) and the depot's
## lockers that open it:
## - from the main menu it has the face, uniform and truck tabs; eight eyes and
##   eight mouths as cards; the picked card (and only it) wears the check, and
##   picking moves it, saves it and never un-picks by clicking twice; a
##   ready-made face sets both and is checked only while both still match;
## - the dice never rolls a blank face nor the one you already have;
## - a locked uniform is a disabled card that says how it is earned;
## - tabs show one page and move the camera (face close-up, body for the rest);
## - focus: tabs down to the picked card, the last row down to Done;
## - the depot's lockers (depot_panel.gd) open the same screen in depot mode,
##   without the truck tab, keep it (no rebuild) while you pick, and closing it
##   closes the depot panel.

## Loaded at run time, not preloaded: the panel names autoloads (UnlockManager),
## which don't exist yet when a --script test is compiled.
const SCREEN_PATH: String = "res://scripts/ui/cosmetics_panel.gd"
const PREVIEW_PATH: String = "res://scripts/ui/customize/character_preview.gd"
## CosmeticsPanel.Mode.DEPOT and CharacterPreview.Framing.FACE / BODY.
const MODE_DEPOT: int = 1
const FRAMING_FACE: int = 0
const FRAMING_BODY: int = 1

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	unlocks.call(&"reset_profile")
	await _check_menu_panel(unlocks)
	await _check_depot_lockers(unlocks)
	unlocks.call(&"reset_profile")
	if _failures == 0:
		print("PASS: customization screen cards, dice, locks, pages, focus and depot lockers")
	quit(_failures)


func _check_menu_panel(unlocks: Node) -> void:
	var panel: Control = load(SCREEN_PATH).new()
	root.add_child(panel)
	await process_frame
	for tab: String in ["Tab_face", "Tab_uniform", "Tab_truck"]:
		_expect(panel.find_child(tab, true, false) != null, "The menu screen has %s" % tab)
	_expect(panel.find_children("Eyes_*", "Button", true, false).size() == 8, "Eight eyes cards")
	_expect(panel.find_children("Mouth_*", "Button", true, false).size() == 8, "Eight mouth cards")
	_expect(_checked(panel) == ["Eyes_classic", "Mouth_smile"], "A fresh profile checks classic eyes and smile (got %s)"
			% str(_checked(panel)))
	panel.find_child("Eyes_determined", true, false).pressed.emit()
	panel.find_child("Mouth_smirk", true, false).pressed.emit()
	_expect(unlocks.get(&"selected_eyes") == &"determined" and unlocks.get(&"selected_mouth") == &"smirk",
			"Picking a card saves it")
	_expect(_checked(panel) == ["Eyes_determined", "Mouth_smirk"], "The check moves to the picked cards (got %s)"
			% str(_checked(panel)))
	var picked := panel.find_child("Eyes_determined", true, false) as Button
	picked.button_pressed = false
	picked.pressed.emit()
	_expect(picked.button_pressed and unlocks.get(&"selected_eyes") == &"determined",
			"Clicking the picked card again keeps it picked")

	# A ready-made face sets both layers, and wears the check while they match it.
	panel.find_child("Preset_cheeky", true, false).pressed.emit()
	_expect(unlocks.get(&"selected_eyes") == &"wink" and unlocks.get(&"selected_mouth") == &"smirk",
			"A ready-made face picks its eyes and its mouth")
	var cheeky := panel.find_child("Preset_cheeky", true, false) as Button
	_expect(cheeky.button_pressed and cheeky.get_node(^"Check").visible, "The ready-made face is checked")
	panel.find_child("Mouth_grin", true, false).pressed.emit()
	_expect(not cheeky.get_node(^"Check").visible, "Changing one layer un-checks the ready-made face")

	var dice := panel.find_child("Randomize", true, false) as Button
	for roll: int in 20:
		var eyes_before: StringName = unlocks.get(&"selected_eyes")
		var mouth_before: StringName = unlocks.get(&"selected_mouth")
		dice.pressed.emit()
		var eyes: StringName = unlocks.get(&"selected_eyes")
		var mouth: StringName = unlocks.get(&"selected_mouth")
		if eyes == &"none" or mouth == &"none" or eyes == eyes_before or mouth == mouth_before:
			_expect(false, "The dice rolled %s/%s after %s/%s" % [eyes, mouth, eyes_before, mouth_before])
			break

	var coral := panel.find_child("Uniform_coral_uniform", true, false) as Button
	_expect(coral != null and coral.disabled, "A locked uniform is a disabled card")
	_expect(coral != null and coral.tooltip_text.contains("%d" % int(
			(unlocks.call(&"requirements", &"coral_uniform") as Dictionary).get("deliveries", 0))),
			"The locked card says how it is earned (%s)" % (coral.tooltip_text if coral != null else ""))

	var preview: Control = panel.find_child("CharacterPreview", true, false)
	(panel.find_child("Tab_uniform", true, false) as Button).pressed.emit()
	_expect((panel.find_child("Page_uniform", true, false) as Control).visible
			and not (panel.find_child("Page_face", true, false) as Control).visible, "A tab shows only its page")
	_expect(preview.get(&"framing") == FRAMING_BODY, "The uniform tab frames the whole body")
	(panel.find_child("Tab_face", true, false) as Button).pressed.emit()
	_expect(preview.get(&"framing") == FRAMING_FACE, "The face tab frames the head")

	var tab := panel.find_child("Tab_face", true, false) as Button
	var landing := tab.get_node(tab.focus_neighbor_bottom) as Button
	_expect(landing != null and landing.button_pressed and landing.get_meta(&"kind") in ["preset", "eyes"],
			"Down from the tabs lands on the first picked card (got %s)" % (landing.name if landing else "nothing"))
	var last_mouth := panel.find_child("Mouth_none", true, false) as Button
	_expect(last_mouth.get_node(last_mouth.focus_neighbor_bottom) == panel.find_child("Done", true, false),
			"Down from the last row reaches Done")
	panel.queue_free()
	await process_frame


func _check_depot_lockers(unlocks: Node) -> void:
	unlocks.call(&"reset_profile")
	var depot_panel: Control = load("res://scripts/ui/depot_panel.gd").new()
	root.add_child(depot_panel)
	await process_frame
	var closed: Array[bool] = [false]
	depot_panel.connect(&"closed", func() -> void: closed[0] = true)
	depot_panel.call(&"open", &"wardrobe", null)
	await process_frame
	var wardrobe: Control = depot_panel.get_node_or_null(^"Wardrobe")
	_expect(wardrobe != null and wardrobe.get(&"mode") == MODE_DEPOT, "The lockers open the screen in depot mode")
	if wardrobe == null:
		depot_panel.queue_free()
		return
	_expect(wardrobe.find_child("Tab_truck", true, false) == null, "No truck tab at the lockers (that's the workshop)")
	_expect(wardrobe.find_child("Tab_face", true, false) != null, "The face is chosen at the lockers")
	wardrobe.find_child("Mouth_laugh", true, false).pressed.emit()
	await process_frame
	_expect(unlocks.get(&"selected_mouth") == &"laugh", "A face picked at the lockers is saved")
	_expect(depot_panel.get_node_or_null(^"Wardrobe") == wardrobe and is_instance_valid(wardrobe),
			"Picking does not rebuild the lockers' screen")
	wardrobe.call(&"close")
	_expect(not depot_panel.visible and closed[0], "Closing the screen closes the depot panel")
	depot_panel.queue_free()
	await process_frame


## The face cards wearing the check (uniform and truck pages have theirs).
func _checked(panel: Control) -> Array[String]:
	var names: Array[String] = []
	var cards: Array[Node] = panel.find_children("Eyes_*", "Button", true, false)
	cards.append_array(panel.find_children("Mouth_*", "Button", true, false))
	for card: Node in cards:
		var badge: CanvasItem = card.get_node_or_null(^"Check")
		if badge != null and badge.visible:
			names.append(String(card.name))
	names.sort()
	return names


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1
