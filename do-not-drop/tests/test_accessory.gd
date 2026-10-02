extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_accessory.gd
##
## N-923.1 accessory shop rules, pure (accessory_catalog.gd, accessory_inventory.gd):
## - the catalogue has the four S-305 accessories with a known slot, a positive
##   price (cap 60, vest 90, hard hat 120, backpack 150) and a translated title;
##   unknown ids have no slot and a price of -1, never "free";
## - one copy of each: granting one somebody has fails (the owner included), and
##   give()/remove() move or take it, so nothing is duplicated or conjured;
## - equipping needs ownership, wears one accessory per slot (a second head item
##   replaces the first), and what is given or removed is taken off first;
## - to_dict()/load_dict() round-trip to an equal dictionary (through JSON too);
##   unknown ids, worn-but-not-owned, wrong-slot, doubled and badly typed data
##   and owners outside the allowed list are dropped without crashing.

var _failures: int = 0
var _changes: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_catalog()
	_check_ownership()
	_check_equipping()
	_check_round_trip()
	_check_hostile_data()
	if _failures == 0:
		print("PASS: accessory catalogue and inventory keep one copy each, equip per slot and save without loss")
	quit(_failures)


func _check_catalog() -> void:
	var ids: Array[StringName] = AccessoryCatalog.ids()
	_expect(ids == [&"cap", &"hi_vis_vest", &"hard_hat", &"thermal_backpack"],
			"The shelf lists the four S-305 accessories in order (got %s)" % [ids])
	var prices := {&"cap": 60, &"hi_vis_vest": 90, &"hard_hat": 120, &"thermal_backpack": 150}
	for id: StringName in ids:
		_expect(AccessoryCatalog.has(id) and AccessoryCatalog.valid_slot(AccessoryCatalog.slot_of(id)),
				"%s has a valid slot (got %s)" % [id, AccessoryCatalog.slot_of(id)])
		_expect(AccessoryCatalog.price_of(id) == int(prices[id]),
				"%s costs %d (got %d)" % [id, int(prices[id]), AccessoryCatalog.price_of(id)])
		var title_key: String = AccessoryCatalog.title_key(id)
		_expect(title_key.begins_with("UI_ACCESSORY_") and tr(title_key) != "",
				"%s has a translation key (got %s)" % [id, title_key])
		_expect(AccessoryCatalog.model_path(id).begins_with(AccessoryCatalog.MODEL_DIR),
				"%s has a model path under the accessories folder" % id)
	_expect(AccessoryCatalog.slot_of(&"cap") == AccessoryCatalog.slot_of(&"hard_hat"),
			"The cap and the hard hat compete for the head")
	_expect(AccessoryCatalog.ids_for_slot(&"head") == [&"cap", &"hard_hat"],
			"ids_for_slot lists the head items (got %s)" % [AccessoryCatalog.ids_for_slot(&"head")])
	_expect(AccessoryCatalog.slot_of(&"jetpack") == &"" and AccessoryCatalog.price_of(&"jetpack") == -1
			and not AccessoryCatalog.has(&"jetpack") and AccessoryCatalog.model_path(&"jetpack") == "",
			"An unknown id has no slot, no model and a price of -1")
	for slot: StringName in AccessoryCatalog.SLOTS:
		_expect(not AccessoryCatalog.ids_for_slot(slot).is_empty() and AccessoryCatalog.slot_title_key(slot) != "",
				"Slot %s has accessories and a title" % slot)


func _check_ownership() -> void:
	var inv := AccessoryInventory.new()
	inv.changed.connect(func(owner: String) -> void: _changes.append(owner))
	_expect(inv.grant("mint", &"cap") and inv.owns("mint", &"cap") and inv.owner_of(&"cap") == "mint",
			"A granted accessory belongs to its owner")
	_expect(not inv.grant("mint", &"cap"), "The owner cannot buy the same accessory twice")
	_expect(not inv.grant("coral", &"cap") and not inv.owns("coral", &"cap"),
			"Nobody else gets a second copy while it exists")
	_expect(not inv.grant("mint", &"jetpack") and not inv.grant("", &"hard_hat"),
			"Unknown ids and empty owners are refused")
	_expect(_changes == ["mint"], "Only the successful grant announced a change (got %s)" % [_changes])

	# Moving it never duplicates or loses it.
	_expect(inv.give("mint", "coral", &"cap"), "The owner can give it away")
	_expect(inv.owner_of(&"cap") == "coral" and not inv.owns("mint", &"cap") and inv.owns("coral", &"cap"),
			"After giving, only the receiver has it")
	_expect(not inv.give("mint", "sky", &"cap") and inv.owner_of(&"cap") == "coral",
			"Giving what you no longer own does nothing")
	_expect(not inv.give("coral", "coral", &"cap") and not inv.give("coral", "", &"cap"),
			"Giving to yourself or to nobody does nothing")
	_expect(inv.owned_by("coral") == [&"cap"] and inv.owned_by("mint").is_empty(),
			"One owner's list has exactly what they have (got %s)" % [inv.owned_by("coral")])
	_expect(not inv.remove("mint", &"cap") and inv.remove("coral", &"cap") and inv.owner_of(&"cap") == "",
			"Only the owner can remove it, and then nobody has it")
	_expect(inv.grant("sky", &"cap"), "A removed accessory can be granted again (a single copy)")
	_expect(not inv.is_empty(), "An inventory with an accessory is not empty")
	inv.clear()
	_expect(inv.is_empty() and inv.owner_of(&"cap") == "", "clear() empties everything")


func _check_equipping() -> void:
	var inv := AccessoryInventory.new()
	_expect(not inv.equip("mint", &"cap"), "Equipping what you do not own fails")
	inv.grant("mint", &"cap")
	inv.grant("mint", &"hard_hat")
	inv.grant("mint", &"thermal_backpack")
	_expect(inv.equip("mint", &"cap") and inv.equipped_in("mint", &"head") == &"cap"
			and inv.is_equipped("mint", &"cap"),
			"An owned accessory can be worn")
	_expect(inv.equip("mint", &"hard_hat") and inv.equipped_in("mint", &"head") == &"hard_hat"
			and not inv.is_equipped("mint", &"cap"),
			"A second head item replaces the first (one per slot)")
	_expect(inv.owns("mint", &"cap"), "...but the replaced one stays in the inventory")
	inv.equip("mint", &"thermal_backpack")
	_expect(inv.equipped_by("mint") == {&"head": &"hard_hat", &"back": &"thermal_backpack"},
			"Different slots are worn together (got %s)" % [inv.equipped_by("mint")])
	_expect(not inv.unequip("mint", &"torso") and inv.unequip("mint", &"back")
			and inv.equipped_in("mint", &"back") == &"",
			"Taking off an empty slot fails; a worn one comes off")
	# Giving or removing what is worn takes it off first.
	_expect(inv.give("mint", "coral", &"hard_hat") and inv.equipped_in("mint", &"head") == &""
			and inv.equipped_in("coral", &"head") == &"" and not inv.is_equipped("coral", &"hard_hat"),
			"A worn accessory is taken off when it is given (the receiver starts with it off)")
	inv.equip("mint", &"cap")
	inv.remove("mint", &"cap")
	_expect(inv.equipped_by("mint").is_empty(), "A removed accessory is no longer worn")
	# The copy of the worn dictionary is not the live one.
	inv.equip("coral", &"hard_hat")
	var copy: Dictionary = inv.equipped_by("coral")
	copy[&"head"] = &"cap"
	_expect(inv.equipped_in("coral", &"head") == &"hard_hat", "equipped_by returns a copy")


func _check_round_trip() -> void:
	var inv := AccessoryInventory.new()
	inv.grant("mint", &"cap")
	inv.grant("mint", &"thermal_backpack")
	inv.grant("coral", &"hi_vis_vest")
	inv.grant("coral", &"hard_hat")
	inv.equip("mint", &"cap")
	inv.equip("coral", &"hard_hat")
	var saved: Dictionary = inv.to_dict()
	var back := AccessoryInventory.new()
	back.load_dict(saved)
	_expect(back.to_dict() == saved, "The inventory survives to_dict then load_dict (got %s)" % [back.to_dict()])
	_expect(back.equipped_in("mint", &"head") == &"cap" and back.owns("coral", &"hi_vis_vest")
			and back.equipped_in("coral", &"head") == &"hard_hat" and back.equipped_in("coral", &"torso") == &"",
			"Owned and worn come back exactly")
	# Through real JSON (what the campaign file does with it).
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var from_json := AccessoryInventory.new()
	from_json.load_dict(parsed)
	_expect(from_json.to_dict() == saved, "...also through JSON text (got %s)" % [from_json.to_dict()])
	_expect(AccessoryInventory.new().to_dict() == {}, "An empty inventory saves as an empty dictionary")
	# take_entry keeps what a colour owned, merge_entry gives it back.
	var entry: Dictionary = back.take_entry("coral")
	_expect(back.owned_by("coral").is_empty() and back.owner_of(&"hard_hat") == "" and not entry.is_empty(),
			"take_entry removes everything the owner had")
	_expect(back.merge_entry("sky", entry) == 2 and back.equipped_in("sky", &"head") == &"hard_hat",
			"merge_entry hands the entry to another owner, worn items included")


func _check_hostile_data() -> void:
	var inv := AccessoryInventory.new()
	inv.load_dict({
		"mint": {"owned": ["cap", "jetpack", "cap", 7, "hi_vis_vest"], "equipped": {
			"head": "cap", "torso": "hard_hat", "back": "thermal_backpack", "tail": "cap", "hat": 3}},
		"coral": {"owned": ["cap", "hard_hat"], "equipped": {"head": "hard_hat"}},
		"nobody": {"owned": ["thermal_backpack"], "equipped": {}},
		7: {"owned": ["hi_vis_vest"]},
		"sky": "not a dictionary",
		"teal": {"owned": "cap", "equipped": [1, 2]},
	}, ["mint", "coral", "sky", "teal"])
	_expect(inv.owned_by("mint") == [&"cap", &"hi_vis_vest"],
			"Unknown ids, repeats and non-strings are dropped (got %s)" % [inv.owned_by("mint")])
	_expect(inv.equipped_by("mint") == {&"head": &"cap"},
			"Worn items that are not owned or sit in the wrong slot are dropped (got %s)" % [inv.equipped_by("mint")])
	_expect(not inv.owns("coral", &"cap") and inv.owns("coral", &"hard_hat"),
			"A doctored file cannot give the same accessory to two owners")
	_expect(inv.owner_of(&"thermal_backpack") == "", "Owners outside the allowed list are ignored")
	_expect(inv.owned_by("sky").is_empty() and inv.owned_by("teal").is_empty(), "Badly typed entries are ignored")
	for junk: Variant in [null, 5, "text", [1, 2], {}]:
		inv.load_dict(junk)
		_expect(inv.is_empty(), "load_dict(%s) leaves an empty inventory without crashing" % [junk])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
