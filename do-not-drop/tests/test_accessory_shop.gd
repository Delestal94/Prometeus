extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_accessory_shop.gd
##
## N-923.3 buying accessories with the team's money (accessory_offers.gd,
## crew_progression.gd buy_accessory, shop_vote_manager.gd), on the host, with
## the buyer named explicitly (a colour key) so the network layer (N-923.5) can
## wrap it in an RPC later:
## - AccessoryOffers: one offer per accessory and buyer, the cost is the catalogue
##   price times a surcharge (never below 1) and half with a Discount card;
## - buy_accessory spends only if the grant works: it charges once and the item
##   goes to the buyer's colour only; an accessory somebody has (the buyer
##   included, one copy each), an unknown id, a bad buyer, a wallet that can't
##   pay or a Discount card that isn't held change nothing, and a failed
##   discounted purchase keeps the card; the surcharge (a service stop's 1.4)
##   and the card's half price are what is charged; it is saved with the campaign;
## - the depot's vote: the offers are the supplies plus the shelf per connected
##   player; the vote settles the winning accessory for ITS buyer (not the
##   voter), charging once; a second vote on it, a poor wallet or a closed
##   depot (run on) charge nothing; Priority and Discount cards work and are
##   only used up when the purchase goes through.
## - the depot's shop face lists the shelf (price, "you have it" once bought) and
##   a press buys it solo, for the local player, through the same settle.
## The crew and the vote here are private instances on a test campaign file; the
## panel check uses the autoload crew on a test file and restores it.

var _failures: int = 0
var _path: String
# By path at run time: the script names autoloads, which a preload here compiles too early.
var _crew_script: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_crew_script = load("res://scripts/core/crew_progression.gd")
	_path = "user://accessory_shop_%d.json" % Time.get_ticks_usec()
	var network: Node = root.get_node(^"/root/NetworkManager")
	var old_slots: Dictionary = (network.get(&"_color_slots") as Dictionary).duplicate()
	# Host 1 is slot 0 (mint), peer 2 slot 1 (yellow), peer 3 slot 2 (coral).
	network.set(&"_color_slots", {1: 0, 2: 1, 3: 2})
	_check_offers()
	_check_purchase()
	_check_vote()
	_check_closed_depot()
	await _check_panel()
	network.set(&"_color_slots", old_slots)
	for path: String in [_path, _path + ".tmp", _path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("PASS: accessories are bought with the team's money once, for the buyer, and only if the grant works")
	quit(_failures)


func _new_crew(money: int) -> Node:
	var crew: Node = _crew_script.new()
	crew.campaign_path = _path
	crew.reset_campaign()
	crew.team_money = money
	return crew


func _check_offers() -> void:
	_expect(AccessoryOffers.cost(&"cap") == 60 and AccessoryOffers.cost(&"thermal_backpack") == 150,
			"At the depot an accessory costs its catalogue price")
	_expect(AccessoryOffers.cost(&"cap", 1.4) == 84 and AccessoryOffers.cost(&"hard_hat", 1.4) == 168,
			"On the road the surcharge of 40% applies (cap 84, hard hat 168)")
	_expect(AccessoryOffers.cost(&"cap", 0.1) == 60, "A multiplier under 1 is no discount")
	_expect(AccessoryOffers.cost(&"cap", 1.4, true) == 42 and AccessoryOffers.cost(&"cap", 1.0, true) == 30,
			"The Discount card halves what is charged, surcharge included")
	_expect(AccessoryOffers.cost(&"nope") == -1, "An unknown accessory has no price (never free)")
	var offers: Dictionary = AccessoryOffers.build([1, 2], 1.4, {"venue": &"service_stop", "stop": "S1"})
	_expect(offers.size() == 8, "One offer per accessory and buyer (got %d)" % offers.size())
	var offer: Dictionary = offers[AccessoryOffers.offer_id(2, &"cap")]
	_expect(int(offer["buyer"]) == 2 and offer["accessory"] == &"cap" and int(offer["cost"]) == 84
			and offer["venue"] == &"service_stop" and offer["stop"] == "S1",
			"An offer names its buyer, accessory, surcharged cost and the venue's stamp (got %s)" % [offer])
	_expect(AccessoryOffers.is_offer(offer) and not AccessoryOffers.is_offer({"cost": 5})
			and not AccessoryOffers.is_offer(&"cap") and not AccessoryOffers.is_offer({"accessory": "bogus"}),
			"Only a catalogue accessory makes an accessory offer")
	var inventory := AccessoryInventory.new()
	inventory.grant("coral", &"cap")
	var blocked: Array = AccessoryOffers.blocked_ids(offers, inventory)
	_expect(blocked.size() == 2 and blocked.has(AccessoryOffers.offer_id(1, &"cap"))
			and blocked.has(AccessoryOffers.offer_id(2, &"cap")),
			"The offers of an accessory somebody has are blocked for every buyer (got %s)" % [blocked])
	_expect(AccessoryOffers.block_reason(inventory, "coral", &"cap") == &"owned"
			and AccessoryOffers.block_reason(inventory, "mint", &"cap") == &"taken"
			and AccessoryOffers.block_reason(inventory, "mint", &"hard_hat") == &""
			and AccessoryOffers.block_reason(inventory, "mint", &"nope") == &"unknown",
			"The reason says owned, taken, free or unknown")


func _check_purchase() -> void:
	var crew: Node = _new_crew(500)
	var result: Dictionary = crew.buy_accessory("yellow", &"cap")
	_expect(result["ok"] and int(result["cost"]) == 60 and int(crew.team_money) == 440,
			"The team pays the cap once ($500 -> $440, got %s)" % [result])
	_expect(crew.accessories.owns("yellow", &"cap") and not crew.accessories.owns("mint", &"cap"),
			"The cap is the buyer's alone, not the host's or the team's")

	result = crew.buy_accessory("yellow", &"cap")
	_expect(not result["ok"] and result["reason"] == &"owned" and int(crew.team_money) == 440,
			"Buying what the buyer has charges nothing (got %s, $%d)" % [result, int(crew.team_money)])
	result = crew.buy_accessory("mint", &"cap")
	_expect(not result["ok"] and result["reason"] == &"taken" and int(crew.team_money) == 440
			and not crew.accessories.owns("mint", &"cap"),
			"Another player can't buy the one copy and the team isn't charged (got %s)" % [result])

	crew.team_money = 100
	result = crew.buy_accessory("mint", &"thermal_backpack")
	_expect(not result["ok"] and result["reason"] == &"no_money" and int(crew.team_money) == 100
			and not crew.accessories.owns("mint", &"thermal_backpack"),
			"Without enough money nothing is bought and nothing is spent (got %s)" % [result])
	crew.team_money = 150
	_expect(crew.buy_accessory("mint", &"thermal_backpack")["ok"] and int(crew.team_money) == 0,
			"Exactly enough money is enough")

	crew.team_money = 300
	for bad: Array in [["mint", &"nope"], ["", &"hard_hat"], ["purple", &"hard_hat"]]:
		result = crew.buy_accessory(String(bad[0]), StringName(bad[1]))
		_expect(not result["ok"] and int(crew.team_money) == 300,
				"An unknown accessory or buyer charges nothing (%s -> %s)" % [bad, result])

	# The surcharge of a service stop (x1.4): 120 -> 168.
	result = crew.buy_accessory("coral", &"hard_hat", 1.4)
	_expect(result["ok"] and int(result["cost"]) == 168 and int(crew.team_money) == 132,
			"The road's surcharge is what is charged (got %s, $%d)" % [result, int(crew.team_money)])

	# The Discount card: held, half; not held, nothing; failed purchase keeps it.
	crew.team_money = 300
	crew.accessories.clear()
	result = crew.buy_accessory("mint", &"hi_vis_vest", 1.0, 2)
	_expect(not result["ok"] and result["reason"] == &"no_card" and int(crew.team_money) == 300,
			"Discount without the card charges nothing (got %s)" % [result])
	crew.cards[2] = crew.Card.DISCOUNT
	crew.accessories.grant("coral", &"hi_vis_vest")
	result = crew.buy_accessory("mint", &"hi_vis_vest", 1.0, 2)
	_expect(not result["ok"] and crew.has_card(2, crew.Card.DISCOUNT) and int(crew.team_money) == 300,
			"A purchase that fails keeps the Discount card (got %s)" % [result])
	crew.accessories.clear()
	result = crew.buy_accessory("mint", &"hi_vis_vest", 1.0, 2)
	_expect(result["ok"] and int(result["cost"]) == 45 and int(crew.team_money) == 255
			and not crew.has_card(2, crew.Card.DISCOUNT),
			"With the card the team pays half and the card is used up (got %s, $%d)" % [result, int(crew.team_money)])

	# It is saved with the campaign (a test file, never the player's own).
	var loaded: Node = _crew_script.new()
	loaded.campaign_path = _path
	loaded.load_campaign()
	_expect(loaded.accessories.owns("mint", &"hi_vis_vest") and int(loaded.team_money) == 255,
			"The purchase and the money it left are saved (got $%d)" % int(loaded.team_money))
	loaded.free()
	crew.free()


func _check_vote() -> void:
	var crew: Node = _new_crew(1000)
	var shop: Node = _new_shop(crew)
	var offers: Dictionary = AccessoryOffers.build([1, 2])
	var default_offers: Dictionary = shop.call(&"_default_offers")
	for supply: StringName in crew.SUPPLIES:
		_expect(default_offers.has(supply), "The depot's offers still have the supply %s" % supply)
	_expect(default_offers.has(AccessoryOffers.offer_id(1, &"cap")) and not default_offers.has(
			AccessoryOffers.offer_id(2, &"cap")),
			"...plus the shelf for the player at the counter (offline: the host alone)")

	# The vote of a different player settles the offer of ITS buyer (peer 2 = yellow).
	var cap_for_2: StringName = AccessoryOffers.offer_id(2, &"cap")
	shop.call(&"open_shop", offers)
	_expect(shop.call(&"vote", 1, cap_for_2), "The crew votes on an accessory offer")
	shop.call(&"finish_vote", [1])
	_expect(crew.accessories.owns("yellow", &"cap") and not crew.accessories.owns("mint", &"cap"),
			"The accessory goes to the offer's buyer, not to whoever voted")
	_expect(int(crew.team_money) == 940,
			"The vote charged the team once ($1000 -> $940, got $%d)" % int(crew.team_money))

	# The same offer again: the item is taken, nothing is charged.
	shop.call(&"open_shop", offers)
	shop.call(&"vote", 1, cap_for_2)
	shop.call(&"finish_vote", [1])
	_expect(int(crew.team_money) == 940,
			"Voting an accessory somebody has charges nothing (got $%d)" % int(crew.team_money))
	shop.call(&"open_shop", offers)
	shop.call(&"vote", 1, AccessoryOffers.offer_id(1, &"cap"))
	shop.call(&"finish_vote", [1])
	_expect(int(crew.team_money) == 940 and not crew.accessories.owns("mint", &"cap"),
			"...the one copy can't be bought again for another buyer either")

	# A wallet that can't pay.
	crew.team_money = 100
	shop.call(&"open_shop", offers)
	shop.call(&"vote", 1, AccessoryOffers.offer_id(1, &"thermal_backpack"))
	shop.call(&"finish_vote", [1])
	_expect(int(crew.team_money) == 100 and not crew.accessories.owns("mint", &"thermal_backpack"),
			"A vote the wallet can't pay buys nothing and spends nothing")

	# Priority: pays the full price, once, and the card goes only if it was bought.
	crew.team_money = 500
	crew.cards[1] = crew.Card.PRIORITY
	shop.call(&"open_shop", offers)
	_expect(shop.call(&"use_priority", 1, cap_for_2) == &"" and crew.has_card(1, crew.Card.PRIORITY),
			"Priority on an accessory somebody has is refused and keeps the card")
	_expect(shop.call(&"use_priority", 1, AccessoryOffers.offer_id(1, &"hi_vis_vest")) != &"",
			"Priority buys an accessory at once")
	_expect(crew.accessories.owns("mint", &"hi_vis_vest") and int(crew.team_money) == 410
			and not crew.has_card(1, crew.Card.PRIORITY),
			"...charged once for its buyer, and the card is used up (got $%d)" % int(crew.team_money))

	# Discount: half price, the card used up only by a purchase that happened.
	crew.cards[1] = crew.Card.DISCOUNT
	shop.call(&"open_shop", offers)
	_expect(shop.call(&"use_discount", 1, AccessoryOffers.offer_id(1, &"hard_hat")) != &"",
			"Discount closes the vote on the accessory")
	_expect(crew.accessories.owns("mint", &"hard_hat") and int(crew.team_money) == 350
			and not crew.has_card(1, crew.Card.DISCOUNT),
			"...half price ($120 -> $60), the card used up (got $%d)" % int(crew.team_money))
	crew.cards[1] = crew.Card.DISCOUNT
	crew.team_money = 10
	shop.call(&"open_shop", offers)
	shop.call(&"use_discount", 1, AccessoryOffers.offer_id(1, &"thermal_backpack"))
	_expect(int(crew.team_money) == 10 and crew.has_card(1, crew.Card.DISCOUNT)
			and not crew.accessories.owns("mint", &"thermal_backpack"),
			"A discounted purchase the wallet can't pay keeps the card and the money")

	# The host-callable settle, as the network layer will call it for a remote peer.
	crew.team_money = 400
	var settled: Dictionary = shop.call(&"settle_accessory_offer", AccessoryOffers.build([3])[
			AccessoryOffers.offer_id(3, &"thermal_backpack")])
	_expect(settled["ok"] and crew.accessories.owns("coral", &"thermal_backpack") and int(crew.team_money) == 250,
			"settle_accessory_offer buys for the named buyer (got %s, $%d)" % [settled, int(crew.team_money)])
	shop.free()
	crew.free()


func _check_closed_depot() -> void:
	var crew: Node = _new_crew(500)
	var shop: Node = _new_shop(crew)
	var manager: Node = root.get_node(^"/root/RunManager")
	manager.set(&"is_running", true)
	var offer: Dictionary = AccessoryOffers.build([1])[AccessoryOffers.offer_id(1, &"cap")]
	var result: Dictionary = shop.call(&"settle_accessory_offer", offer)
	manager.set(&"is_running", false)
	_expect(not result["ok"] and int(crew.team_money) == 500 and not crew.accessories.owns("mint", &"cap"),
			"The depot's counter sells nothing while a run is on (got %s)" % [result])
	shop.free()
	crew.free()


func _button_texts(panel: Control) -> Array[String]:
	var texts: Array[String] = []
	for button: Node in panel.find_children("*", "Button", true, false):
		texts.append((button as Button).text)
	return texts


func _check_panel() -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var old_path: String = String(crew.get(&"campaign_path"))
	var old_money: int = int(crew.get(&"team_money"))
	var inventory: AccessoryInventory = crew.get(&"accessories")
	var old_state: Dictionary = inventory.to_dict()
	crew.set(&"campaign_path", _path)
	inventory.clear()
	crew.set(&"team_money", 500)
	var panel: Control = (load("res://scripts/ui/depot_panel.gd") as Script).new()
	root.add_child(panel)
	await process_frame
	panel.call(&"open", &"shop", null)
	await process_frame
	var cap_row: String = "%s  ·  $60" % tr("UI_ACCESSORY_CAP")
	var buttons: Array[String] = _button_texts(panel)
	_expect(buttons.has(cap_row) and buttons.has("%s  ·  $150" % tr("UI_ACCESSORY_THERMAL_BACKPACK")),
			"The shop face lists the shelf with the catalogue prices (%s)" % [buttons])
	for button: Node in panel.find_children("*", "Button", true, false):
		if (button as Button).text == cap_row:
			(button as Button).pressed.emit()
	await process_frame
	_expect(inventory.owns("mint", &"cap") and int(crew.get(&"team_money")) == 440,
			"A press buys the cap for the local player, once ($%d)" % int(crew.get(&"team_money")))
	buttons = _button_texts(panel)
	_expect(buttons.has(tr("UI_ACCESSORY_ROW_OWNED") % tr("UI_ACCESSORY_CAP")),
			"The row then says the player has it (%s)" % [buttons])
	panel.free()
	crew.set(&"campaign_path", old_path)
	crew.set(&"team_money", old_money)
	inventory.load_dict(old_state)


func _new_shop(crew: Node) -> Node:
	var shop: Node = (load("res://scripts/core/shop_vote_manager.gd") as Script).new()
	shop.set(&"crew_progression", crew)
	root.add_child(shop)
	return shop


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
