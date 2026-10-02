extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_progression.gd
## The crew's campaign economy: shop money is shared, a delivery pays the team,
## merit (and rescue credit) stays personal, and a voted purchase spends the
## cooperative wallet.
##
## Two layers on purpose:
## - the wallet itself (crew_progression.gd), fed a results dictionary: the
##   payout is delivery_points + cargo_points, with no chaos multiplier, and an
##   Endless-style result (neither field) pays nothing (N-227.2);
## - a real delivery through the RunManager autoload (run_manager.gd
##   finish_run -> CrewProgression.award_delivery): one box handed over at a
##   door, one still aboard and intact, a realistic 130 s run. The team wallet
##   has to rise by delivery_points + cargo_points (door points are paid, not
##   only the box still in the van), the score carries the chaos multiplier the
##   payout does not, the results carry no time bonus and show the payout.
##
## Colour slots (N-226.2: player_color_slot.gd, crew_progression.gd):
## - the colour of a peer is the index the host gave it (NetworkManager.color_slot),
##   wrapped to the eight-colour palette (N-228.3), never posmod(peer_id, 5): with
##   ENet-sized ids (> 1.8e9) the five of a crew all differ, the host is slot 0
##   playing solo and in a room, and slots 5..7 have colours of their own;
## - the campaign is saved by slot ("players": {"0": ...}, CAMPAIGN_VERSION 3 since N-923.2):
##   a new session with other random ids but the same slots gets the same merit
##   and cards back, and swapped slots swap them;
## - a leaver's progress is saved under the slot it wore when the roster last
##   changed, even though the network freed that slot first;
## - a version-1 save (colour names) migrates (the host, old "yellow", becomes
##   slot 0); a corrupt, newer or oddly typed file starts a fresh campaign.
##   The test uses its own save path, never the user's real file.

const REAL_RUN_SECONDS: float = 130.0
const TEST_SAVE: String = "user://test_n226_campaign.json"
## Peer ids the size ENet and Steam hand out. Under posmod(id, 5) they are
## 0, 4, 2, 1, 4: two share a colour, and so does the host (1) with the fourth.
const BIG_IDS: Array[int] = [2043517840, 1873311209, 2110004977, 1966280031, 2017733559]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	crew.call(&"reset_campaign")
	_expect(int(crew.get(&"team_money")) == 100, "Campaign starts with shared shop money")
	_expect(crew.call(&"award_action", 2, &"recover_box_1", 15), "A useful action grants merit")
	_expect(not crew.call(&"award_action", 2, &"recover_box_1", 15), "The same rescue is not farmable")
	_expect(int((crew.get(&"merit") as Dictionary)[2]) == 15, "Merit remains personal")
	var paid: Dictionary = {"cargo_points": 100, "delivery_points": 150, "chaos_multiplier": 1.2, "score": 300}
	crew.call(&"award_delivery", paid, [1, 2])
	_expect(int(crew.get(&"team_money")) == 350,
			"Delivery payout (doors + cargo, no chaos) belongs to the team (got %d)" % int(crew.get(&"team_money")))
	_expect(int(paid.get("payout", -1)) == 250, "The results carry the payout for the results screen")
	crew.call(&"award_delivery", {"delivery_points": -80, "cargo_points": 0}, [1])
	_expect(int(crew.get(&"team_money")) == 350, "A net-negative delivery never takes money from the wallet")
	crew.call(&"award_delivery", {"distance_traveled": 900.0, "score": 900}, [1])
	_expect(int(crew.get(&"team_money")) == 350, "Endless results carry no cargo or door points: no payout")
	crew.set(&"team_money", 200)
	_expect(crew.call(&"spend", 50) and int(crew.get(&"team_money")) == 150,
			"A voted purchase spends cooperative money")
	_expect(not crew.call(&"spend", 151), "Cannot overspend team money")
	_check_real_delivery(crew)
	_check_color_slots(crew)
	crew.call(&"reset_campaign")
	if failures == 0:
		print("PASS: shared money, personal merit and delivery rewards")
	quit(failures)


## A whole delivery-mode run through the real RunManager, not a hand-made
## results dictionary.
func _check_real_delivery(crew: Node) -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	var run_script: GDScript = load("res://scripts/core/run_manager.gd")
	root.get_node(^"/root/UnlockManager").call(&"reset_profile")
	crew.call(&"reset_campaign")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 1)
	manager.call(&"start_run")
	bus.emit_signal(&"cargo_registered", &"door", "HUD_TRAP_FRAGILE")
	bus.emit_signal(&"cargo_registered", &"aboard", "HUD_TRAP_BALANCE")
	manager.set(&"cargo", {
		&"door": {"integrity": 100.0, "maximum": 100.0, "state": 0},
		&"aboard": {"integrity": 100.0, "maximum": 100.0, "state": 0},
	})
	manager.call(&"register_delivery", 0, &"delivered_ok", &"door")
	manager.set(&"elapsed_seconds", REAL_RUN_SECONDS)
	manager.set(&"had_simultaneous_risk", true)
	var before: int = int(crew.get(&"team_money"))
	manager.call(&"finish_run", true)
	var results: Dictionary = manager.get(&"results")
	var gained: int = int(crew.get(&"team_money")) - before
	var expected: int = int(results.get("delivery_points", 0)) + int(results.get("cargo_points", 0))
	_expect(bool(results.get("delivered", false)),
			"The real run ends as a delivery (got %s)" % _got(results, "delivered"))
	_expect(int(results.get("houses_delivered", 0)) == 1,
			"The door counts as delivered (got %s)" % _got(results, "houses_delivered"))
	_expect(int(results.get("cargo_intact", 0)) == 1,
			"The box still aboard is intact (got %s)" % _got(results, "cargo_intact"))
	_expect(int(results.get("cargo_points", 0)) == int(run_script.POINTS_INTACT),
			"The aboard box scores its intact points (got %s)" % _got(results, "cargo_points"))
	_expect(int(results.get("delivery_points", 0)) > 0,
			"The handed-over door scores delivery points (got %s)" % _got(results, "delivery_points"))
	_expect(float(results.get("elapsed_seconds", 0.0)) >= REAL_RUN_SECONDS,
			"The run lasted a realistic time (got %s)" % _got(results, "elapsed_seconds"))
	_expect(not results.has("time_bonus"), "The time bonus is gone from the results")
	for line: Dictionary in results.get("breakdown", []):
		_expect(String(line["label"]) != "HUD_SCORE_SPEED", "No speed line in the breakdown")
	_expect(int(results.get("delivery_points", 0)) == int(run_script.POINTS_DELIVERED_INTACT),
			"The door pays the intact delivery points (got %s)" % _got(results, "delivery_points"))
	_expect(gained == int(run_script.POINTS_DELIVERED_INTACT) + int(run_script.POINTS_INTACT),
			"The wallet gets door + cargo points, not only the box aboard (got +%d)" % gained)
	_expect(int(results.get("payout", -1)) == gained, "The results show what the team was paid")
	_expect(int(results.get("score", 0)) == roundi((int(results.get("delivery_points", 0))
			+ int(results.get("cargo_points", 0))) * run_script.CHAOS_MULTIPLIER),
			"Score is (cargo + doors) x chaos multiplier, no time term (got %s)" % _got(results, "score"))
	_expect(float(results.get("chaos_multiplier", 1.0)) == run_script.CHAOS_MULTIPLIER,
			"The shared scare applies its multiplier to the score only (got %s)" % _got(results, "chaos_multiplier"))
	_expect(gained > 0, "A real delivery raises the team wallet (got +%d)" % gained)
	_expect(gained == expected,
			"The wallet rises by the payout the results carry (got +%d, expected +%d)" % [gained, expected])
	manager.call(&"reset_run")


## A crew in the room: the real NetworkManager with a slot map and roster set
## by hand (offline, so nothing is sent), which CrewProgression reads.
func _seat(network: Node, slots: Dictionary) -> void:
	var peers: Array[int] = []
	for peer: Variant in slots:
		peers.append(int(peer))
	network.set(&"_color_slots", slots)
	network.set(&"peer_ids", peers)


func _read_save() -> Dictionary:
	var file := FileAccess.open(TEST_SAVE, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _write_save(text: String) -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean_saves() -> void:
	for suffix: String in ["", ".bak", ".bad", ".tmp"]:
		if FileAccess.file_exists(TEST_SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + suffix))


func _check_color_slots(crew: Node) -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var constants: Dictionary = (crew.get_script() as GDScript).get_script_constant_map()
	var keys: Array = constants["PLAYER_COLOR_KEYS"]
	var old_slots: Dictionary = network.get(&"_color_slots").duplicate()
	var old_peers: Array[int] = []
	old_peers.assign(network.get(&"peer_ids"))
	var old_path: String = String(crew.get(&"campaign_path"))
	crew.set(&"campaign_path", TEST_SAVE)
	_clean_saves()

	# Solo play: the host is slot 0 offline (NetworkManager alone says 1 there).
	_seat(network, {})
	network.set(&"peer_ids", [1] as Array[int])
	_expect(int(crew.call(&"player_slot", 1)) == 0 and crew.call(&"player_color_key", 1) == "mint",
			"Playing solo the host is slot 0 (got %s)" % crew.call(&"player_slot", 1))

	# A crew with ENet-sized ids: every colour comes from the host's index.
	var crew_slots := {1: 0, BIG_IDS[0]: 1, BIG_IDS[1]: 2, BIG_IDS[2]: 3, BIG_IDS[3]: 4}
	_seat(network, crew_slots)
	var seen: Dictionary = {}
	for peer: int in crew_slots:
		var expected: String = keys[int(crew_slots[peer])]
		_expect(crew.call(&"player_color_key", peer) == expected,
				"Peer %d wears the colour of its slot %d (got %s)" % [peer, int(crew_slots[peer]),
				crew.call(&"player_color_key", peer)])
		seen[crew.call(&"player_color_key", peer)] = true
	_expect(seen.size() == 5, "Five players, five different colours (got %d)" % seen.size())
	var old_scheme: Dictionary = {}
	for peer: int in crew_slots:
		old_scheme[posmod(peer, 5)] = true
	_expect(old_scheme.size() < 5, "These ids would have shared a colour under posmod(peer_id, 5)")
	# Random crews: distinct colours for up to five, whatever the ids.
	var rng := RandomNumberGenerator.new()
	rng.seed = 226
	for trial: int in 100:
		var random_slots := {1: 0}
		for slot: int in range(1, 5):
			random_slots[rng.randi_range(1_000_000_000, 2_147_483_000)] = slot
		_seat(network, random_slots)
		var colors: Dictionary = {}
		for peer: int in random_slots:
			colors[crew.call(&"player_color_key", peer)] = true
		if colors.size() != 5:
			_expect(false, "A random crew of five shares a colour (got %d colours, %s)" % [colors.size(), random_slots])
			break
	# Eight seats, eight colours (N-228.3): 5..7 are their own, never wrapped.
	_seat(network, {1: 0, BIG_IDS[0]: 5, BIG_IDS[1]: 6, BIG_IDS[2]: 7})
	_expect(int(crew.call(&"player_slot", BIG_IDS[0])) == 5 and int(crew.call(&"player_slot", BIG_IDS[1])) == 6
			and int(crew.call(&"player_slot", BIG_IDS[2])) == 7, "Slots 5..7 have their own colours")
	_expect(crew.call(&"player_color_key", BIG_IDS[2]) == keys[7] and keys.size() == 8,
			"The crew's palette has one key per seat of a full room (got %d)" % keys.size())

	# Saved by slot. First session: host + two joiners.
	_seat(network, {1: 0, BIG_IDS[0]: 1, BIG_IDS[1]: 2})
	crew.call(&"reset_campaign")
	crew.call(&"award_action", BIG_IDS[0], &"n226_a", 25)
	crew.call(&"award_action", BIG_IDS[1], &"n226_b", 10)
	crew.get(&"cards")[BIG_IDS[0]] = 3 # Card.RESCUE
	_expect(crew.call(&"save_campaign"), "The campaign saves to the test path")
	var saved: Dictionary = _read_save()
	var players: Dictionary = saved.get("players", {})
	_expect(int(saved.get("version", 0)) == int(constants["CAMPAIGN_VERSION"]) and int(saved.get("version", 0)) == 3,
			"The save is version 3 (got %s)" % saved.get("version"))
	_expect(players.has("1") and players.has("2") and players.has("0") and players.size() == 3,
			"The save is keyed by slot (got %s)" % [players.keys()])
	_expect(int(Dictionary(players.get("1", {})).get("merit", -1)) == 25
			and int(Dictionary(players.get("2", {})).get("merit", -1)) == 10
			and int(Dictionary(players.get("1", {})).get("card", -1)) == 3,
			"Each slot keeps its own merit and card (got %s)" % [players])
	for name_key: String in keys:
		_expect(not players.has(name_key), "The save no longer uses colour names (found %s)" % name_key)
	# Second session, other random ids, same seats: the progress comes back.
	_seat(network, {1: 0, BIG_IDS[3]: 1, BIG_IDS[4]: 2})
	crew.call(&"load_campaign")
	var merit: Dictionary = crew.get(&"merit")
	_expect(int(merit.get(BIG_IDS[3], -1)) == 25 and int(merit.get(BIG_IDS[4], -1)) == 10,
			"New ids in the same slots get the same merit back (got %s)" % [merit])
	_expect(int(crew.get(&"cards").get(BIG_IDS[3], -1)) == 3 and not crew.get(&"cards").has(BIG_IDS[4]),
			"...and the card (got %s)" % [crew.get(&"cards")])
	# Swapped seats swap the progress: it follows the slot, not the arrival.
	_seat(network, {1: 0, BIG_IDS[3]: 2, BIG_IDS[4]: 1})
	crew.call(&"load_campaign")
	merit = crew.get(&"merit")
	_expect(int(merit.get(BIG_IDS[3], -1)) == 10 and int(merit.get(BIG_IDS[4], -1)) == 25,
			"Progress follows the slot, not the peer id (got %s)" % [merit])

	# A leaver is saved under the slot it wore, although the map freed it first.
	_seat(network, {1: 0, BIG_IDS[0]: 1, BIG_IDS[1]: 2})
	crew.call(&"reset_campaign")
	crew.call(&"award_action", BIG_IDS[0], &"n226_leaver", 30)
	_seat(network, {1: 0, BIG_IDS[1]: 2, BIG_IDS[2]: 1})
	_expect(int(crew.call(&"player_slot", BIG_IDS[0])) != 1, "The leaver's id no longer reads as slot 1")
	crew.call(&"_capture_player", BIG_IDS[0])
	var by_slot: Dictionary = crew.get(&"_saved_players_by_slot")
	_expect(int(Dictionary(by_slot.get(1, {})).get("merit", -1)) == 30,
			"A leaver's merit is saved under the slot it wore (got %s)" % [by_slot])
	crew.call(&"_apply_saved_player", BIG_IDS[2])
	_expect(int(crew.get(&"merit").get(BIG_IDS[2], -1)) == 30,
			"The next one into the freed slot carries its progress on (the seat; N-221 reservations aside)")

	# A version-1 save (colour names) still loads: the host (old "yellow") is slot 0.
	_seat(network, {1: 0, BIG_IDS[0]: 1, BIG_IDS[1]: 2})
	_write_save(JSON.stringify({"version": 1, "team_money": 250, "supplies": ["padding"], "players": {
			"yellow": {"merit": 40, "card": 2, "dry_deliveries": 1},
			"mint": {"merit": 7, "card": -1, "dry_deliveries": 0},
			"coral": {"merit": 3, "card": -1, "dry_deliveries": 2}}}))
	crew.call(&"load_campaign")
	merit = crew.get(&"merit")
	_expect(int(crew.get(&"team_money")) == 250 and crew.get(&"supplies").has(&"padding"),
			"A version-1 save keeps its money and supplies")
	_expect(int(merit.get(1, -1)) == 40 and int(merit.get(BIG_IDS[0], -1)) == 7 and int(merit.get(BIG_IDS[1], -1)) == 3,
			"A version-1 save migrates: old yellow is the host, old mint slot 1 (got %s)" % [merit])
	_expect(int(crew.get(&"cards").get(1, -1)) == 2 and int(crew.get(&"dry_deliveries").get(BIG_IDS[1], -1)) == 2,
			"...with its card and dry deliveries")
	crew.call(&"save_campaign")
	var migrated: Dictionary = _read_save()
	_expect(int(migrated.get("version", 0)) == 3 and Dictionary(migrated.get("players", {})).has("0"),
			"The next save writes version 3 (got %s)" % [migrated])

	# Slots 5..7 (N-228.3) save and load like the rest; a five-slot file still loads.
	_seat(network, {1: 0, BIG_IDS[0]: 7})
	crew.call(&"reset_campaign")
	crew.call(&"award_action", BIG_IDS[0], &"n228_slot7", 12)
	crew.call(&"save_campaign")
	_expect(Dictionary(_read_save().get("players", {})).has("7"), "The eighth seat is saved under slot 7")
	_seat(network, {1: 0, BIG_IDS[1]: 7})
	crew.call(&"load_campaign")
	_expect(int(crew.get(&"merit").get(BIG_IDS[1], -1)) == 12, "...and its merit comes back to the seat")
	_write_save(JSON.stringify({"version": 2, "team_money": 90, "players": {"4": {"merit": 9}}}))
	_seat(network, {1: 0, BIG_IDS[0]: 4, BIG_IDS[1]: 7})
	crew.call(&"load_campaign")
	_expect(int(crew.get(&"merit").get(BIG_IDS[0], -1)) == 9 and int(crew.get(&"merit").get(BIG_IDS[1], -1)) == 0,
			"A save from the five-colour days loads: slot 4 keeps its merit, the new seats start clean")

	# Files it must not crash on: corrupt, from a newer game, wrong types.
	_seat(network, {1: 0})
	_write_save("{not json at all")
	crew.call(&"load_campaign")
	_expect(int(crew.get(&"team_money")) == 100,
			"A corrupt save starts a fresh campaign (got %d)" % int(crew.get(&"team_money")))
	_clean_saves()
	_write_save(JSON.stringify({"version": 99, "team_money": 999, "players": {"0": {"merit": 500}}}))
	crew.call(&"load_campaign")
	_expect(int(crew.get(&"team_money")) == 100 and int(crew.get(&"merit").get(1, -1)) == 0,
			"A save from a newer game is not guessed at (got %d money)" % int(crew.get(&"team_money")))
	_write_save(JSON.stringify({"version": 2, "team_money": 70, "supplies": "padding", "players": [1, 2]}))
	crew.call(&"load_campaign")
	_expect(int(crew.get(&"team_money")) == 70 and crew.get(&"supplies").is_empty(),
			"A save with wrongly typed fields loads what it can")
	_write_save(JSON.stringify({"version": 2, "players": {"0": {"merit": "lots", "card": 99}, "9": {"merit": 5}}}))
	crew.call(&"load_campaign")
	_expect(int(crew.get(&"merit").get(1, -1)) == 0 and not crew.get(&"cards").has(1),
			"Nonsense values and out-of-palette slots are ignored")

	_clean_saves()
	crew.set(&"campaign_path", old_path)
	network.set(&"_color_slots", old_slots)
	network.set(&"peer_ids", old_peers)


func _got(results: Dictionary, key: String) -> String:
	return str(results.get(key))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
