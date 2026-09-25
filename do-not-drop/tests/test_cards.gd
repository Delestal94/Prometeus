extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cards.gd
##
## S-103 card contract: only the three usable cards can be drawn; Rescue
## resolves an active route event but survives an empty press; depot cards
## apply their effect and are consumed exactly once.

var failures: int = 0
var notices: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node(^"CrewProgression")
	var route_events: Node = root.get_node(^"RouteEventManager")
	var shop: Node = root.get_node(^"ShopVoteManager")
	var bus: Node = root.get_node(^"EventBus")
	bus.connect(&"depot_notice", _on_notice)

	_test_drawable_cards(crew)
	_test_rescue(crew, route_events)
	_test_empty_rescue(crew, route_events)
	_test_discount(crew)
	_test_revote(crew, shop)

	crew.call(&"reset_campaign")
	route_events.call(&"reset_route")
	shop.active = false
	shop.votes.clear()
	bus.disconnect(&"depot_notice", _on_notice)
	if failures == 0:
		print("PASS: only usable cards are drawn and Rescue, Discount and Re-vote consume on a valid use")
	quit(failures)


func _test_drawable_cards(crew: Node) -> void:
	crew.call(&"reset_campaign")
	var constants: Dictionary = (crew.get_script() as Script).get_script_constant_map()
	var drawable: Array = constants[&"DRAWABLE_CARDS"]
	_expect(drawable == [crew.Card.RESCUE, crew.Card.DISCOUNT, crew.Card.REVOTE],
		"The drawable pool contains only Rescue, Discount and Re-vote")
	for peer_id: int in range(1, 201):
		crew.dry_deliveries[peer_id] = crew.PITY_DELIVERIES
		crew.call(&"_grant_card_chance", peer_id)
		var drawn: int = int(crew.cards.get(peer_id, -1))
		_expect(drawn in drawable, "Peer %d drew a playable card (got %d)" % [peer_id, drawn])
		_expect(drawn not in [crew.Card.PRIORITY, crew.Card.INFORMATION],
			"Peer %d never draws Priority or Information" % peer_id)


func _test_rescue(crew: Node, route_events: Node) -> void:
	crew.call(&"reset_campaign")
	route_events.call(&"reset_route")
	crew.cards[1] = crew.Card.RESCUE
	_expect(route_events.call(&"begin_event", &"inspection") == &"inspection", "An inspection event starts for Rescue")
	_expect(bool(crew.call(&"request_use_card")), "Rescue succeeds while a route event is active")
	_expect(StringName(route_events.active_event_id).is_empty(), "Rescue clears the active route event")
	_expect(bool(route_events.resolved_events.get(&"inspection", false)), "Rescue records the event as resolved")
	_expect(not crew.cards.has(1), "A successful Rescue is consumed")


func _test_empty_rescue(crew: Node, route_events: Node) -> void:
	crew.call(&"reset_campaign")
	route_events.call(&"reset_route")
	notices.clear()
	crew.cards[1] = crew.Card.RESCUE
	_expect(not bool(crew.call(&"request_use_card")), "Rescue does nothing without an active event")
	_expect(crew.has_card(1, crew.Card.RESCUE), "An unused Rescue is not consumed")
	_expect(notices.has("No hay nada que rescatar"), "The player is told there is nothing to rescue")


func _test_discount(crew: Node) -> void:
	crew.call(&"reset_campaign")
	crew.cards[1] = crew.Card.DISCOUNT
	_expect(bool(crew.call(&"buy_supply_discounted", 1, &"padding")), "Discount buys an available supply")
	_expect(int(crew.team_money) == crew.STARTING_MONEY - 20, "Discount charges half of the $40 price")
	_expect(bool(crew.supplies.get(&"padding", false)), "The discounted supply is ready for the next run")
	_expect(not crew.cards.has(1), "A successful Discount is consumed")


func _test_revote(crew: Node, shop: Node) -> void:
	crew.call(&"reset_campaign")
	shop.call(&"open_shop", {&"padding": {"cost": 40, "label": "Acolchado"}})
	shop.call(&"vote", 1, &"padding")
	crew.cards[1] = crew.Card.REVOTE
	_expect(bool(shop.call(&"use_revote", 1)), "Re-vote succeeds during an active vote")
	_expect(shop.votes.is_empty(), "Re-vote clears the current votes")
	_expect(not crew.cards.has(1), "A successful Re-vote is consumed")


func _on_notice(text: String) -> void:
	notices.append(text)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1
