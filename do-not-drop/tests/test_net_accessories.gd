extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_net_accessories.gd
##
## N-923.5 the accessories over the network, host-authoritative, in one process
## (accessory_ground.gd, accessory_net.gd, crew_progression.gd, shop_vote_manager.gd).
## The two-process version -- a real client buys by vote, wears, drops and picks
## up, and the host and the client read the same -- is the accessory stage of
## tests/net_pair.gd (tools/run-net-pair.sh).
## - AccessoryGround: one pickup per accessory, ids never reused, a pickup is
##   only finite and catalogued; expired() by the host's clock; prune() takes a
##   pickup whose owner no longer has it; to_array()/load_array() round-trip
##   with the same ids and places, signal only what changed, and drop anything
##   malformed (types, unknown ids, owners off the list, NaN, doubles).
## - AccessoryNet on the host (stand-in players in the "player" group): wearing
##   needs ownership, the right slot and the accessory in hand (not on the
##   ground); &"" takes it off; dropping needs ownership and a body in the level,
##   takes it off, lands it in front of the player (or of the seat), keeps it
##   the owner's (the shop still sees it taken), and one lying per player;
##   picking up needs reach (an interactable's), moves the one copy to the taker
##   or gives it back to its owner, and a pickup is taken once; the save is
##   written once per burst of changes.
## - It goes back to its owner when the owner leaves (peer_removed), after
##   PICKUP_LIFETIME_MSEC, when the delivery ends (run_ended), and when the owner
##   no longer has it; leaving the session clears the ground.
## - A client's copy is the host's word (apply_host_state): the same inventory and
##   ground, and a hostile payload changes nothing that doesn't check out.
## - The autoload CrewProgression has its AccessoryNet child on its inventory, with
##   the four RPCs: three any_peer reliable requests and an authority reliable sync.
## - The shop vote settles an accessory before the crew hears shop_resolved, so the
##   host's own panel, rebuilding on it, already sees who owns it.

const OWNERS: Array[String] = ["mint", "yellow", "coral"]
const COLOURS := {1: "mint", 2: "yellow", 3: "coral"}
const SEATED_SOURCE: String = "extends Node3D\nvar seat := Vector3.ZERO\n\nfunc reach_origin() -> Vector3:\n" \
		+ "\treturn seat\n"
const BUS_SOURCE: String = "extends Node\nsignal run_ended(score: int, results: Dictionary)\n" \
		+ "signal shop_opened(offers: Dictionary)\nsignal shop_vote_changed(peer_id: int, offer_id: StringName)\n" \
		+ "signal shop_resolved(offer_id: StringName, offer: Dictionary)\n"

var _failures: int = 0
var _saves: Array[int] = [0]
var _players: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_ground()
	_check_ground_wire()
	var bus: Node = _script_node(BUS_SOURCE)
	root.add_child(bus)
	var inventory := AccessoryInventory.new()
	var net := AccessoryNet.new()
	var save := func() -> bool:
		_saves[0] += 1
		return true
	net.setup(inventory, OWNERS, _colour_of, save, null, bus)
	root.add_child(net)
	_check_equip(net, inventory)
	await _check_drop_and_pick_up(net, inventory)
	_check_returns(net, inventory, bus)
	_check_client_copy(net, inventory)
	_check_autoload()
	await _check_vote_order()
	net.queue_free()
	bus.queue_free()
	for player: Node in _players:
		player.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: accessories are worn, dropped and picked up through the host, one copy each,"
				+ " and every peer reads the same")
	quit(_failures)


# --- AccessoryGround -------------------------------------------------------------------

func _check_ground() -> void:
	var ground := AccessoryGround.new()
	var added: Array = []
	var removed: Array = []
	ground.pickup_added.connect(func(id: int, _pickup: Dictionary) -> void: added.append(id))
	ground.pickup_removed.connect(func(id: int) -> void: removed.append(id))
	var first: int = ground.add(&"cap", "mint", 1, Vector3(1, 0, 2), 1000)
	_expect(first == 1 and ground.pickup_of(&"cap") == 1 and added == [1], "A drop is pickup 1 (got %d)" % first)
	_expect(ground.add(&"cap", "yellow", 2, Vector3.ZERO, 1000) == 0, "One copy: the same accessory can't lie twice")
	_expect(ground.add(&"crown", "mint", 1, Vector3.ZERO, 1000) == 0, "An accessory that isn't sold can't lie")
	_expect(ground.add(&"hard_hat", "", 1, Vector3.ZERO, 1000) == 0, "A pickup needs an owner")
	_expect(ground.add(&"hard_hat", "mint", 1, Vector3(NAN, 0, 0), 1000) == 0, "A pickup lies somewhere finite")
	var pickup: Dictionary = ground.get_pickup(first)
	_expect(pickup.get("accessory") == &"cap" and pickup.get("owner") == "mint" and int(pickup.get("dropper")) == 1
			and pickup.get("position") == Vector3(1, 0, 2),
			"A pickup knows what, whose, who dropped it and where (%s)" % [pickup])
	_expect(ground.owned_by("mint") == [1] and ground.owned_by("yellow").is_empty(), "Pickups are listed by owner")
	_expect(not ground.remove(first).is_empty() and removed == [1] and ground.remove(first).is_empty(),
			"A pickup is taken once")
	var second: int = ground.add(&"cap", "mint", 1, Vector3.ZERO, 5000)
	_expect(second == 2, "Ids are never reused (got %d)" % second)
	_expect(ground.expired(5000 + 9999, 10000).is_empty() and ground.expired(15000, 10000) == [2],
			"A pickup expires once it has lain its lifetime, by the host's clock")
	var inventory := AccessoryInventory.new()
	inventory.grant("mint", &"cap")
	_expect(ground.prune(inventory).is_empty() and ground.has(second), "An owned pickup stays")
	inventory.remove("mint", &"cap")
	_expect(ground.prune(inventory) == [2] and ground.is_empty(), "A pickup its owner no longer has is taken away")


func _check_ground_wire() -> void:
	var host := AccessoryGround.new()
	host.add(&"cap", "mint", 1, Vector3(1, 0, 2), 0)
	host.add(&"hi_vis_vest", "yellow", 2, Vector3(-3, 1, 0), 0)
	var client := AccessoryGround.new()
	var added: Array = []
	var removed: Array = []
	client.pickup_added.connect(func(id: int, _pickup: Dictionary) -> void: added.append(id))
	client.pickup_removed.connect(func(id: int) -> void: removed.append(id))
	client.load_array(host.to_array(), OWNERS)
	_expect(client.ids() == host.ids() and client.get_pickup(2).get("position") == Vector3(-3, 1, 0)
			and client.get_pickup(1).get("owner") == "mint" and added == [1, 2],
			"A client reads the same pickups, ids and places as the host (got %s)" % [client.to_array()])
	host.remove(1)
	var vest: int = host.pickup_of(&"hi_vis_vest")
	host.add(&"hard_hat", "coral", 3, Vector3(0, 0, 5), 0)
	added.clear()
	client.load_array(host.to_array(), OWNERS)
	_expect(removed == [1] and added == [3] and client.has(vest) and client.ids() == host.ids(),
			"Only what changed is signalled (removed %s, added %s)" % [removed, added])
	removed.clear()
	client.load_array([_wire(3, "hard_hat", "coral", Vector3(9, 0, 0)), _wire(2, "hi_vis_vest", "yellow",
			Vector3(-3, 1, 0))], OWNERS)
	_expect(removed == [3] and client.get_pickup(3).get("position") == Vector3(9, 0, 0),
			"A pickup that moved is put down again where the host says")

	var float_id: Dictionary = _wire(1, "cap", "mint", Vector3.ZERO)
	float_id["id"] = 1.5
	var text_position: Dictionary = _wire(7, "cap", "mint", Vector3.ZERO)
	text_position["position"] = "here"
	client.load_array(["junk", float_id, _wire(0, "cap", "mint", Vector3.ZERO), _wire(4, "crown", "mint", Vector3.ZERO),
		_wire(5, "cap", "pirate", Vector3.ZERO), _wire(6, "cap", "mint", Vector3(INF, 0, 0)), text_position,
		_wire(8, "cap", "mint", Vector3(1, 0, 0)), _wire(9, "cap", "yellow", Vector3(2, 0, 0))], OWNERS)
	_expect(client.ids() == [8], "Malformed pickups are dropped and an accessory lies once (got %s)" % [client.ids()])
	var flood: Array = []
	for index: int in 40:
		flood.append(_wire(index + 1, "cap", "mint", Vector3.ZERO))
	client.load_array(flood, OWNERS)
	_expect(client.ids() == [1], "However many entries name it, an accessory lies once (got %s)" % [client.ids()])
	client.load_array(42, OWNERS)
	_expect(client.is_empty(), "Something that isn't a list clears the copy (got %s)" % [client.ids()])


# --- AccessoryNet on the host ---------------------------------------------------------------

func _check_equip(net: AccessoryNet, inventory: AccessoryInventory) -> void:
	inventory.grant("mint", &"cap")
	inventory.grant("yellow", &"hi_vis_vest")
	_expect(net.equip_as(2, &"head", &"cap") == &"not_owner" and not inventory.is_equipped("yellow", &"cap"),
			"Nobody wears what isn't theirs")
	_expect(net.equip_as(1, &"torso", &"cap") == &"unknown" and net.equip_as(1, &"hat_rack", &"cap") == &"unknown"
			and net.equip_as(1, &"head", &"crown") == &"unknown" and net.equip_as(9, &"head", &"cap") == &"unknown",
			"A wrong slot, an unknown accessory or a peer without a colour is refused")
	_expect(net.equip_as(1, &"head", &"cap") == &"" and inventory.is_equipped("mint", &"cap"),
			"The owner wears it, in its slot")
	_expect(net.equip_as(1, &"head", &"") == &"" and inventory.equipped_in("mint", &"head") == &"",
			"An empty accessory takes off what is worn there")
	net.equip(&"head", &"cap")
	_expect(inventory.is_equipped("mint", &"cap"), "Offline, the local player's request is applied at once")


func _check_drop_and_pick_up(net: AccessoryNet, inventory: AccessoryInventory) -> void:
	_expect(net.drop_as(1, &"cap") == &"no_player" and net.ground.is_empty() and inventory.is_equipped("mint", &"cap"),
			"Without a body in the level nothing is dropped")
	_player(1, Vector3.ZERO)
	var yellow: Node3D = _player(2, Vector3(10, 0, 0))
	_player(3, Vector3(0, 0, 1.5))
	_expect(net.drop_as(2, &"cap") == &"not_owner" and net.drop_as(2, &"crown") == &"unknown",
			"Only the owner drops it, and only a catalogued one")
	var saves_before: int = _saves[0]
	_expect(net.drop_as(1, &"cap") == &"", "The owner drops the cap")
	var pickup_id: int = net.ground.pickup_of(&"cap")
	var landed: Vector3 = net.ground.get_pickup(pickup_id).get("position", Vector3.INF)
	_expect(pickup_id > 0 and landed.distance_to(Vector3(0, 0, -AccessoryNet.DROP_DISTANCE)) < 0.01,
			"It lands in front of the player (at %s)" % [landed])
	_expect(not inventory.is_equipped("mint", &"cap") and inventory.owner_of(&"cap") == "mint",
			"Dropped, it is taken off but stays its owner's until somebody picks it up")
	_expect(AccessoryOffers.block_reason(inventory, "coral", &"cap") == &"taken",
			"The shop still sees a dropped accessory as taken: it is never sold twice")
	_expect(net.equip_as(1, &"head", &"cap") == &"on_ground" and net.drop_as(1, &"cap") == &"on_ground",
			"What lies on the ground can't be worn or dropped again")
	inventory.grant("mint", &"hard_hat")
	_expect(net.drop_as(1, &"hard_hat") == &"too_many" and net.ground.ids().size() == 1,
			"One accessory lying per player at a time")

	_expect(net.pick_up_as(2, pickup_id) == &"far" and net.ground.has(pickup_id) and inventory.owns("mint", &"cap"),
			"Out of reach (10 m) nothing is picked up")
	_expect(net.pick_up_as(3, pickup_id) == &"", "A player within reach picks it up")
	_expect(inventory.owner_of(&"cap") == "coral" and not inventory.owns("mint", &"cap") and net.ground.is_empty(),
			"It moves to the taker, one copy, and leaves the ground")
	_expect(net.pick_up_as(2, pickup_id) == &"gone" and net.pick_up_as(3, 999) == &"gone",
			"A pickup is taken once; an unknown one is gone")
	net.drop_as(3, &"cap")
	var own: int = net.ground.pickup_of(&"cap")
	var own_at: Vector3 = net.ground.get_pickup(own).get("position", Vector3.INF)
	_expect(own_at.distance_to(Vector3(0, 0, 1.5 - AccessoryNet.DROP_DISTANCE)) < 0.01,
			"...in front of the one who drops it this time (at %s)" % [own_at])
	_expect(net.pick_up_as(3, own) == &"" and inventory.owns("coral", &"cap") and net.ground.is_empty(),
			"Its owner can take it back")

	# Seated: the body stays where they sat, the reach is the seat (Player.reach_origin()).
	var seated: Node3D = _script_node(SEATED_SOURCE) as Node3D
	seated.add_to_group(AccessoryNet.PLAYER_GROUP)
	seated.set_multiplayer_authority(2)
	root.add_child(seated)
	_players.append(seated)
	seated.set(&"seat", Vector3(10, 1, 0.5))
	yellow.remove_from_group(AccessoryNet.PLAYER_GROUP)
	net.drop_as(2, &"hi_vis_vest")
	var vest: Dictionary = net.ground.get_pickup(net.ground.pickup_of(&"hi_vis_vest"))
	var vest_at: Vector3 = vest.get("position", Vector3.INF)
	_expect(vest_at.distance_to(Vector3(10, 1, 0.5 - AccessoryNet.DROP_DISTANCE)) < 0.01,
			"A seated player drops at the seat, not where its body was left (at %s)" % [vest_at])
	seated.set(&"seat", Vector3(30, 0, 0))
	_expect(net.pick_up_as(2, int(vest.get("id", 0))) == &"far", "...and reaches from the seat")
	net.return_all()

	await create_timer(AccessoryNet.SAVE_DELAY_SEC + 0.3).timeout
	_expect(_saves[0] == saves_before + 1, "A burst of changes saves the campaign once (saved %d times)"
			% (_saves[0] - saves_before))


func _check_returns(net: AccessoryNet, inventory: AccessoryInventory, bus: Node) -> void:
	net.drop_as(3, &"cap")
	net.call(&"_on_peer_removed", 3)
	_expect(net.ground.is_empty() and inventory.owner_of(&"cap") == "coral",
			"Its owner leaving gives a dropped accessory back to them")
	net.drop_as(3, &"cap")
	var at: int = int(net.ground.get_pickup(net.ground.pickup_of(&"cap")).get("at_msec", 0))
	_expect(net.expire_pickups(at + AccessoryNet.PICKUP_LIFETIME_MSEC - 1) == 0 and not net.ground.is_empty(),
			"Before its lifetime it stays on the ground")
	_expect(net.expire_pickups(at + AccessoryNet.PICKUP_LIFETIME_MSEC) == 1 and net.ground.is_empty()
			and inventory.owns("coral", &"cap"), "After %d s nobody took it: it goes back to its owner"
			% (AccessoryNet.PICKUP_LIFETIME_MSEC / 1000))
	net.drop_as(3, &"cap")
	bus.emit_signal(&"run_ended", 0, {})
	_expect(net.ground.is_empty() and inventory.owns("coral", &"cap"), "The delivery ending gives it back")
	net.drop_as(3, &"cap")
	net.call(&"_on_roster_changed", [1])
	_expect(net.ground.is_empty(), "Offline, a roster change means the session is over: the ground is cleared")
	net.drop_as(3, &"cap")
	_expect(not net.ground.is_empty(), "(dropped again)")
	inventory.clear()
	_expect(net.ground.is_empty(), "A pickup whose owner no longer has it (reset campaign) goes away")


func _check_client_copy(host: AccessoryNet, host_inventory: AccessoryInventory) -> void:
	host_inventory.grant("mint", &"cap")
	host_inventory.grant("yellow", &"hard_hat")
	host_inventory.equip("yellow", &"hard_hat")
	host.drop_as(1, &"cap")
	var inventory := AccessoryInventory.new()
	inventory.grant("coral", &"thermal_backpack")
	var client := AccessoryNet.new()
	client.setup(inventory, OWNERS, _colour_of, Callable())
	client.apply_host_state(host_inventory.to_dict(), host.ground.to_array())
	_expect(inventory.to_dict() == host_inventory.to_dict() and not host.ground.is_empty(),
			"The client's inventory is the host's (%s)" % [inventory.to_dict()])
	_expect(client.ground.to_array() == host.ground.to_array(), "The client's ground is the host's")
	client.apply_host_state({"mint": {"owned": ["cap", "crown"], "equipped": {"head": "crown"}},
		"pirate": {"owned": ["cap"]}}, [_wire(3, "cap", "pirate", Vector3.ZERO)])
	_expect(inventory.owned_by("mint") == [&"cap"] and inventory.owner_of(&"hard_hat") == ""
			and client.ground.is_empty(),
			"A payload that doesn't check out leaves only what does (%s)" % [inventory.to_dict()])
	client.free()
	host.return_all()
	host_inventory.clear()


# --- The game's wiring ----------------------------------------------------------------------

func _check_autoload() -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var net: AccessoryNet = crew.get_node_or_null(^"AccessoryNet") as AccessoryNet
	_expect(net != null and crew.get(&"accessory_net") == net, "CrewProgression has its AccessoryNet child")
	if net == null:
		return
	_expect(net.inventory == crew.get(&"accessories"), "...on the crew's own inventory")
	var config: Dictionary = (net.get_script() as Script).get_rpc_config()
	for request: StringName in [&"request_equip_accessory", &"request_drop_accessory", &"request_pickup_accessory"]:
		var found: Dictionary = config.get(request, {})
		_expect(int(found.get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_ANY_PEER
				and not bool(found.get("call_local", true))
				and int(found.get("transfer_mode", -1)) == MultiplayerPeer.TRANSFER_MODE_RELIABLE,
				"%s is an any_peer, remote, reliable request (got %s)" % [request, found])
	var sync: Dictionary = config.get(&"_receive_accessories", {})
	_expect(int(sync.get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_AUTHORITY
			and not bool(sync.get("call_local", true))
			and int(sync.get("transfer_mode", -1)) == MultiplayerPeer.TRANSFER_MODE_RELIABLE
			and int(sync.get("channel", 0)) == 0,
			"_receive_accessories is the host's reliable sync on the campaign's channel (got %s)" % [sync])
	_expect(config.size() == 4, "AccessoryNet has exactly the four RPCs (got %s)" % [config.keys()])


func _check_vote_order() -> void:
	var path: String = "user://net_accessories_%d.json" % Time.get_ticks_usec()
	var crew: Node = (load("res://scripts/core/crew_progression.gd") as Script).new()
	crew.set(&"campaign_path", path)
	crew.call(&"reset_campaign")
	crew.set(&"team_money", 1000)
	var bus: Node = _script_node(BUS_SOURCE)
	var shop: Node = (load("res://scripts/core/shop_vote_manager.gd") as Script).new()
	shop.set(&"crew_progression", crew)
	shop.set(&"event_bus", bus)
	root.add_child(shop)
	var seen: Array = []
	var accessories: AccessoryInventory = crew.get(&"accessories")
	bus.connect(&"shop_resolved", func(_id: StringName, _offer: Dictionary) -> void:
		seen.append(accessories.owner_of(&"cap")))
	var buyer: String = String(crew.call(&"player_color_key", 2))
	shop.call(&"open_shop", AccessoryOffers.build([1, 2]))
	shop.call(&"vote", 1, AccessoryOffers.offer_id(2, &"cap"))
	shop.call(&"finish_vote", [1])
	_expect(seen == [buyer] and int(crew.get(&"team_money")) == 940,
			"When the crew hears shop_resolved the accessory is already its buyer's, paid once (saw %s, $%d)"
			% [seen, int(crew.get(&"team_money"))])
	shop.queue_free()
	await process_frame
	bus.free()
	crew.free()
	for file: String in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))


func _colour_of(peer: int) -> String:
	return String(COLOURS.get(peer, ""))


func _wire(id: Variant, accessory: String, owner: String, position: Vector3) -> Dictionary:
	return {"id": id, "accessory": accessory, "owner": owner, "dropper": 1, "position": position}


func _player(peer_id: int, at: Vector3) -> Node3D:
	var player := Node3D.new()
	player.add_to_group(AccessoryNet.PLAYER_GROUP)
	player.set_multiplayer_authority(peer_id)
	root.add_child(player)
	player.global_position = at
	_players.append(player)
	return player


func _script_node(source: String) -> Node:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script.new()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
