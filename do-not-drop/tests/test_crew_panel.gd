extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_panel.gd
##
## The depot's crew panel (S-507, crew_panel.gd, built by hud.gd):
## - a "crew_panel" action exists (Tab / Back) and the shortcut pill teaches it
##   only while the depot is open;
## - build_entries() lists every connected peer in roster order with the shirt
##   colour and uniform name they wear, who is at the wheel and who has a box
##   (in the arms or on the lap), and marks the local player and the host;
## - each row shows an icon and words for the wheel and the box, not only colour;
## - invite_info(): only the LAN host gets the room code (the same one
##   RoomCode makes) and its IP; a Steam host is told to invite by Steam, a
##   host without a local network is told so, a guest is told why there is
##   none, and offline there is nothing;
## - the panel opens only while Tab is held AND the depot is open: not on the
##   start card, not while a depot station / options / pause is up, not once
##   the truck is on the road; it takes no mouse, no focus and no pause, so
##   walking and looking keep working under it;
## - a full crew of eight (N-228.6): build_entries() lists all eight in roster
##   order with the wheel and the boxes right, and the panel shows eight
##   "Row_<peer>" rows, with the LAN invite block, inside the 1280x720 base
##   screen (the palette has eight colours, N-228.3: only the rows' count and
##   place are checked here, the colours' distinctness is test_player_colors').

const ACTION: StringName = &"crew_panel"
const INVITE_LAN: StringName = &"lan"
const INVITE_NO_LAN: StringName = &"no_lan"
const INVITE_STEAM: StringName = &"steam"
const INVITE_GUEST: StringName = &"guest"
const INVITE_NONE: StringName = &"none"

var _failures: int = 0
# Scripts are loaded by path: their class names need the autoloads, which a
# test script compiles before they exist.
var _crew: GDScript
var _room_code: GDScript
var _player: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var run_manager: Node = root.get_node(^"/root/RunManager")
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	_crew = load("res://scripts/ui/hud/crew_panel.gd")
	_room_code = load("res://scripts/ui/room_code.gd")
	_player = load("res://scripts/gameplay/player/player.gd")

	# --- the action ---
	_expect(InputMap.has_action(ACTION), "The crew_panel action exists in the Input Map")
	var has_tab: bool = false
	var has_back: bool = false
	for event: InputEvent in InputMap.action_get_events(ACTION):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_TAB:
			has_tab = true
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
			has_back = true
	_expect(has_tab and has_back,
			"crew_panel is Tab and the gamepad Back button (tab %s, back %s)" % [has_tab, has_back])

	# --- who is in the list ---
	var carrying := Node.new()
	var lap := Node.new()
	var players: Dictionary = {
		1: _stub_player(&"team_color", null, null),
		2: _stub_player(&"coral_uniform", carrying, null),
		3: _stub_player(&"sky_uniform", null, lap),
	}
	var entries: Array[Dictionary] = _crew.build_entries([1, 2, 3, 4], players, 2, true, 1)
	_expect(entries.size() == 4,
			"Everyone on the roster is listed, even a player still spawning (got %d)" % entries.size())
	_expect(entries.map(func(e: Dictionary) -> int: return e["peer_id"]) == [1, 2, 3, 4],
			"Entries keep the roster order")
	_expect(bool(entries[0]["driving"]) and not bool(entries[1]["driving"]) and not bool(entries[2]["driving"]),
			"Only the peer the truck reports as driver is at the wheel")
	_expect(not bool(entries[0]["has_box"]) and bool(entries[1]["has_box"]) and bool(entries[2]["has_box"]),
			"A box in the arms or on the lap counts; empty hands do not (got %s)"
			% [entries.map(func(e: Dictionary) -> bool: return e["has_box"])])
	_expect(not bool(entries[3]["has_box"]) and not bool(entries[3]["driving"]),
			"A player that has not spawned yet has neither wheel nor box")
	_expect(bool(entries[1]["is_local"]) and not bool(entries[0]["is_local"]), "The local player is marked")
	_expect(bool(entries[0]["is_host"]) and not bool(entries[1]["is_host"]), "The host is marked online")
	# The host (peer 1) is colour slot 0, in a room and playing solo (N-226.2).
	_expect(entries[0]["color"] == _player.PLAYER_COLORS[0],
			"The team-colour uniform shows the seat's crew colour (got %s)" % entries[0]["color"])
	_expect(entries[1]["color"] == unlocks.call(&"cosmetic_color", &"coral_uniform")
			and entries[2]["color"] == unlocks.call(&"cosmetic_color", &"sky_uniform"),
			"A picked uniform shows its own colour")
	_expect(entries[1]["uniform"] == tr("UI_UNIFORM_CORAL") and entries[0]["uniform"] == tr("HUD_CREW_TEAM_COLOR"),
			"The uniform is named, not only coloured (got '%s' / '%s')"
			% [entries[1]["uniform"], entries[0]["uniform"]])
	_expect(entries[0]["color"] != entries[1]["color"] and entries[1]["color"] != entries[2]["color"],
			"The three uniforms are told apart by colour")
	var offline: Array[Dictionary] = _crew.build_entries([1], {}, 1, false, 0)
	_expect(offline.size() == 1 and not bool(offline[0]["is_host"]) and bool(offline[0]["is_local"]),
			"Playing solo lists just you, without a host tag")
	var no_driver: Array[Dictionary] = _crew.build_entries([1, 2], players, 1, true, 0)
	_expect(not bool(no_driver[0]["driving"]) and not bool(no_driver[1]["driving"]),
			"Nobody drives while the seat is empty (driver id 0)")

	# --- the invite ---
	var code: String = _room_code.encode("192.168.1.37", int(network.DEFAULT_PORT))
	var lan: Dictionary = _crew.invite_info(true, true, false, "192.168.1.37")
	_expect(lan["kind"] == INVITE_LAN and lan["code"] == code and lan["address"] == "192.168.1.37"
			and not code.is_empty(), "The LAN host gets the room code and the IP (got %s)" % lan)
	_expect(_crew.invite_info(true, true, false, "")["kind"] == INVITE_NO_LAN,
			"A host with no local network is told there is no code")
	var steam: Dictionary = _crew.invite_info(true, true, true, "192.168.1.37")
	_expect(steam["kind"] == INVITE_STEAM and String(steam["code"]).is_empty(),
			"A Steam host is sent to Steam and gets no code (got %s)" % steam)
	var guest: Dictionary = _crew.invite_info(true, false, false, "192.168.1.37")
	_expect(guest["kind"] == INVITE_GUEST and String(guest["code"]).is_empty()
			and String(guest["address"]).is_empty(), "A guest never gets the code (got %s)" % guest)
	_expect(_crew.invite_info(false, true, false, "192.168.1.37")["kind"] == INVITE_NONE,
			"Playing solo has nobody to invite")

	# --- the HUD builds it, and only the depot shows it ---
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var panel: Control = hud.crew_panel
	_expect(panel != null and panel.get_parent() == hud.root, "The HUD builds the crew panel")
	_expect(not panel.visible, "Hidden until asked for")
	_expect(not String(hud.shortcut_label.text).contains("Tab"), "The start card does not advertise Tab yet")

	Input.action_press(ACTION)
	await process_frame
	_expect(not panel.visible, "Holding Tab on the start card opens nothing (mode %s)" % hud.overlay_mode)

	hud.pause.primary_action()
	await process_frame
	_expect(hud.overlay_mode == "preparation" and panel.visible,
			"In the depot, holding Tab shows the panel (mode %s)" % hud.overlay_mode)
	_expect(String(hud.shortcut_label.text).contains("Tab"), "In the depot the shortcut pill teaches Tab")
	_expect(panel.find_child("Row_1", true, false) != null,
			"Playing solo, the live panel lists you")
	_expect(panel.find_child("You", true, false) != null, "Your own row says it is you")
	_expect(panel.find_child("Invite", true, false) == null, "Solo, there is no invite block")
	_expect(not _grabs_input(panel) and not _takes_focus(panel),
			"The panel takes no mouse and no focus: movement input keeps flowing")
	_expect(not paused, "Showing it does not pause the tree")

	Input.action_release(ACTION)
	await process_frame
	_expect(not panel.visible, "Letting go of Tab hides it")

	Input.action_press(ACTION)
	for blocker: Control in [hud.depot_panel, hud.options_panel]:
		blocker.show()
		await process_frame
		_expect(not panel.visible, "A %s on screen keeps the crew panel closed" % blocker.name)
		blocker.hide()
	hud.overlay.show()
	await process_frame
	_expect(not panel.visible, "The pause / results card keeps the crew panel closed")
	hud.overlay.hide()
	await process_frame
	_expect(panel.visible, "Back in the depot it shows again")
	run_manager.set(&"is_running", true)
	await process_frame
	_expect(not panel.visible, "Once the truck is on the road Tab does not open it")
	run_manager.set(&"is_running", false)
	Input.action_release(ACTION)

	# --- what the rows say ---
	var busy: Array[Dictionary] = _crew.build_entries([1, 2, 3], players, 2, true, 1)
	panel.render(busy, lan)
	var rows: Array[Node] = _rows(panel)
	_expect(rows.size() == 3, "One row per player (got %d)" % rows.size())
	var driver_row: Node = panel.find_child("Row_1", true, false)
	var box_row: Node = panel.find_child("Row_2", true, false)
	var idle_row: Node = panel.find_child("Row_3", true, false)
	_expect(driver_row.find_child("Driving", true, false) != null and driver_row.find_child("Box", true, false) == null,
			"The driver's row has the wheel badge and no box badge")
	_expect(box_row.find_child("Box", true, false) != null and box_row.find_child("Driving", true, false) == null,
			"The carrier's row has the box badge and no wheel badge")
	_expect(idle_row.find_child("Box", true, false) != null, "A box on the lap shows the badge too")
	for badge_name: String in ["Driving", "Box"]:
		var badge: Node = panel.find_child(badge_name, true, false)
		var has_icon: bool = false
		var has_words: bool = false
		for part: Node in badge.get_children():
			has_icon = has_icon or (part is TextureRect and (part as TextureRect).texture != null)
		has_words = _texts(badge).any(func(text: String) -> bool: return not text.is_empty())
		_expect(has_icon and has_words, "The %s badge has an icon and words, not just colour" % badge_name)
	_expect(_texts(driver_row.find_child("Driving", true, false)) == [tr("HUD_CREW_DRIVING")],
			"The wheel badge says it in words (got %s)" % [_texts(driver_row.find_child("Driving", true, false))])
	_expect(box_row.find_child("You", true, false) != null and driver_row.find_child("You", true, false) == null
			and driver_row.find_child("Host", true, false) != null, "Row 2 is you, row 1 is the host")
	_expect(String(box_row.find_child("Uniform", true, false).text) == tr("UI_UNIFORM_CORAL"),
			"The row names the uniform")
	var swatch_style: StyleBoxFlat = box_row.find_child("Swatch", true, false).get_theme_stylebox("panel")
	_expect(swatch_style.bg_color == busy[1]["color"], "The swatch is the shirt colour")
	var code_label: Label = panel.find_child("Code", true, false)
	_expect(code_label != null and code_label.text == code,
			"The LAN host's panel shows the room code (got %s)" % code_label)
	var address_label: Label = panel.find_child("Address", true, false)
	_expect(address_label != null and address_label.text.contains("192.168.1.37"), "and the IP for typing it")

	panel.render(busy, guest)
	_expect(panel.find_child("Code", true, false) == null, "A guest's panel has no room code")
	_expect(String(panel.find_child("Hint", true, false).text) == tr("HUD_CREW_GUEST"),
			"and says why (the host sees it)")
	panel.render(busy, steam)
	_expect(panel.find_child("Code", true, false) == null
			and String(panel.find_child("Hint", true, false).text) == tr("HUD_CREW_INVITE_STEAM"),
			"A Steam host's panel says to invite through Steam")
	panel.render(busy, _crew.invite_info(true, true, false, ""))
	_expect(panel.find_child("Code", true, false) == null
			and String(panel.find_child("Hint", true, false).text) == tr("HUD_CREW_NO_LAN"),
			"A host without a network is told so instead of showing an empty code")

	# --- a full crew of eight ---
	await _check_full_crew(panel, lan)

	# --- the real thing: hosting on this machine ---
	network.set(&"transport", network.Transport.ENET)
	var hosted: Error = network.call(&"host_session")
	if hosted == OK:
		await process_frame
		panel.set(&"_signature", "")
		panel.refresh()
		var lan_address: String = network.call(&"lan_address")
		var live_code: Label = panel.find_child("Code", true, false)
		if lan_address.is_empty():
			_expect(live_code == null, "Hosting without a LAN shows no code")
		else:
			_expect(live_code != null and live_code.text == _room_code.encode(lan_address, network.DEFAULT_PORT),
					"Hosting on this LAN, the panel shows the room code")
		_expect(panel.find_child("Host", true, false) != null, "The host is tagged when hosting")
	else:
		print("  (could not host on this machine, live invite check skipped: %s)" % hosted)
	network.call(&"leave_session")
	network.set(&"transport", network.Transport.AUTO)

	hud.free()
	carrying.free()
	lap.free()
	for stub: Node in players.values():
		stub.free()
	await process_frame
	if _failures == 0:
		print("PASS: the crew panel lists everyone with colour, wheel and box, shows the code only to the LAN host, "
				+ "and opens only in the depot")
	quit(_failures)


## Eight peers (1 drives, seven ride), each one a row, all of it on the base screen.
func _check_full_crew(panel: Control, invite: Dictionary) -> void:
	var roster: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	var boxes: Dictionary = {}
	var crew: Dictionary = {}
	for peer_id: int in roster:
		var box: Node = null
		if peer_id > 1:
			box = Node.new()
			boxes[peer_id] = box
		crew[peer_id] = _stub_player(&"team_color", box, null)
	var full: Array[Dictionary] = _crew.build_entries(roster, crew, 5, true, 1)
	_expect(full.size() == 8, "All eight on the roster are listed (got %d)" % full.size())
	_expect(full.map(func(e: Dictionary) -> int: return e["peer_id"]) == roster,
			"Eight entries keep the roster order")
	_expect(full.filter(func(e: Dictionary) -> bool: return e["driving"]).size() == 1 and bool(full[0]["driving"]),
			"One driver among the eight")
	_expect(full.filter(func(e: Dictionary) -> bool: return e["has_box"]).size() == 7 and not bool(full[0]["has_box"]),
			"The seven passengers carry a box, the driver does not")
	_expect(full.filter(func(e: Dictionary) -> bool: return e["is_local"]).size() == 1 and bool(full[4]["is_local"]),
			"Only the local seat is marked among the eight")
	root.size = Vector2i(1280, 720)
	var base := Vector2(1280.0, 720.0)
	Input.action_press(ACTION)
	panel.set_process(false)
	panel.show()
	panel.call(&"render", full, invite)
	await process_frame
	await process_frame
	var rows: Array[Node] = _rows(panel)
	_expect(rows.size() == 8, "Eight players make eight rows (got %d)" % rows.size())
	for peer_id: int in roster:
		_expect(panel.find_child("Row_%d" % peer_id, true, false) != null, "Row_%d exists" % peer_id)
	var card: Control = panel.get_child(0).get_child(0)
	var rect: Rect2 = card.get_global_rect()
	_expect(Rect2(Vector2.ZERO, base).encloses(rect.grow(2.0)),
			"The panel with eight rows and the invite fits %s (got %s)" % [base, rect])
	var last_row: Control = panel.find_child("Row_8", true, false)
	_expect(Rect2(Vector2.ZERO, base).encloses(last_row.get_global_rect()),
			"The last row is on screen (got %s)" % last_row.get_global_rect())
	_expect(panel.find_child("Code", true, false) != null, "The room code still shows with eight rows")
	Input.action_release(ACTION)
	panel.hide()
	panel.set_process(true)
	for box: Node in boxes.values():
		box.free()
	for stub: Node in crew.values():
		stub.free()


func _stub_player(cosmetic: StringName, carried: Object, tended: Object) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar cosmetic_id: StringName = &\"team_color\"\n" \
			+ "var carried_package = null\nvar tended_package = null\n"
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.set(&"cosmetic_id", cosmetic)
	stub.set(&"carried_package", carried)
	stub.set(&"tended_package", tended)
	return stub


func _rows(panel: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in panel.find_children("Row_*", "HBoxContainer", true, false):
		found.append(node)
	return found


func _texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		found.append((label as Label).text)
	return found


## True when any control under `node` would eat mouse clicks.
func _grabs_input(node: Node) -> bool:
	for child: Node in node.find_children("*", "Control", true, false):
		if (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
	return (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP


## True when any control under `node` could take keyboard / gamepad focus.
func _takes_focus(node: Node) -> bool:
	for child: Node in node.find_children("*", "Control", true, false):
		if (child as Control).focus_mode != Control.FOCUS_NONE:
			return true
	return (node as Control).focus_mode != Control.FOCUS_NONE


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
