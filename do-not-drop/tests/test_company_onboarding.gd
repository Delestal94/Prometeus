extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_onboarding.gd
##
## The first week's guide of the company mode (expansion D-1901, diseno/onboarding.md): company_onboarding.gd,
## company_onboarding_tracker.gd and company_onboarding_line.gd.
## - CompanyOnboarding.current(): day 1 walks the loop in order (stock_pallet, pick, pack, drive, deliver,
##   return); a player with units in the hands sees pick / pack, one driving sees drive, deliver, return; two
##   players with different hands see different steps; with no pallet left stock_pallet counts as done; after
##   the loop the later rows show only once their trigger fired and their day came (unload and order_more from
##   day 2), in table order; Armado asistido skips fill; a profile that did everything sees nothing; past day 7
##   nothing shows; every id has a translation key that exists in es and en and an action;
## - the tracker on its own: a units_moved from this peer's hands to a shelf ticks stock_pallet, one from a shelf
##   into the hands ticks pick (another peer's does not), an order packed / out with the player seated /
##   delivered and a trip back after it tick pack, drive, deliver and return (a trip back before the delivery
##   does not); who joins mid-day does not tick what the books already held, and a late order never packed
##   ticks nothing; each tick goes once into the profile
##   (company_onboard_<id>) and a new tracker reading that profile starts where it was left;
## - the line: shows the objective with its control and "✓" with the line just done, then the next one.
## The bot test (test_company_bot_day) checks the same tracker on the real world while the bot plays day 1.

var _failures: int = 0


class FakeProfile:
	extends RefCounted
	var seen_tips: Dictionary = {}
	var marks: Array[StringName] = []

	func mark_tip_seen(tip: StringName) -> bool:
		if seen_tips.get(tip, false):
			return false
		seen_tips[tip] = true
		marks.append(tip)
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_order()
	_test_player_first()
	_test_later_rows()
	_test_keys()
	await _test_tracker()
	await _test_line()
	if _failures == 0:
		print("PASS: the first week's guide walks the loop, follows each player and ticks into the profile")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _id(player: Dictionary, company: Dictionary, seen: Dictionary) -> StringName:
	return CompanyOnboarding.current(player, company, seen).get("id", &"")


func _test_order() -> void:
	var seen: Dictionary = {}
	var company: Dictionary = {"day": 1, "pallet_left": true}
	for id: StringName in CompanyOnboarding.DAY_ONE:
		_expect(_id({}, company, seen) == id, "day 1 shows %s next (got %s)" % [id, _id({}, company, seen)])
		seen[id] = true
	_expect(_id({}, company, seen) == &"", "the loop done, nothing is left on day 1")
	_expect(CompanyOnboarding.loop_done(seen), "...and the loop counts as done")
	_expect(_id({}, {"day": 1, "pallet_left": false}, {}) == CompanyOnboarding.PICK,
		"with no pallet left to put away, stock_pallet counts as done")
	_expect(CompanyOnboarding.current({}, {"day": 8}, {}).is_empty(), "past day 7 the guide is over")


func _test_player_first() -> void:
	var company: Dictionary = {"day": 1, "pallet_left": true}
	var seen: Dictionary = {CompanyOnboarding.STOCK_PALLET: true}
	_expect(_id({"holding": true}, company, {}) == CompanyOnboarding.PICK, "units in the hands show pick")
	var picked: Dictionary = {CompanyOnboarding.STOCK_PALLET: true, CompanyOnboarding.PICK: true}
	_expect(_id({"holding": true}, company, picked) == CompanyOnboarding.PACK, "...and pack once picked")
	_expect(_id({"driving": true}, company, seen) == CompanyOnboarding.DRIVE, "driving shows drive")
	var drove: Dictionary = {CompanyOnboarding.DRIVE: true}
	_expect(_id({"driving": true}, company, drove) == CompanyOnboarding.DELIVER, "...then deliver")
	drove[CompanyOnboarding.DELIVER] = true
	_expect(_id({"driving": true}, company, drove) == CompanyOnboarding.RETURN, "...then return")
	_expect(_id({"packing": true}, company, seen) == CompanyOnboarding.PACK, "at the table, pack")
	# Two players: one put the pallet away and drives, the other still has the shelf to fill.
	var first: StringName = _id({"driving": true}, company, seen)
	var second: StringName = _id({}, company, {})
	_expect(first != second and second == CompanyOnboarding.STOCK_PALLET,
		"two players see their own steps (%s, %s)" % [first, second])


func _test_later_rows() -> void:
	var all: Dictionary = {}
	for id: StringName in CompanyOnboarding.DAY_ONE:
		all[id] = true
	var fired: Dictionary = {
		CompanyOnboarding.UNLOAD: true, CompanyOnboarding.ORDER_MORE: true, CompanyOnboarding.FILL: true,
	}
	_expect(_id({}, {"day": 1, "triggers": fired}, all) == &"", "unload, order_more and fill wait for day 2")
	_expect(_id({}, {"day": 2, "triggers": {}}, all) == &"", "a row whose trigger did not fire does not show")
	_expect(_id({}, {"day": 2, "triggers": fired}, all) == CompanyOnboarding.UNLOAD, "on day 2 unload goes first")
	all[CompanyOnboarding.UNLOAD] = true
	_expect(_id({}, {"day": 2, "triggers": fired}, all) == CompanyOnboarding.ORDER_MORE, "...then order_more")
	all[CompanyOnboarding.ORDER_MORE] = true
	_expect(_id({}, {"day": 3, "triggers": fired}, all) == CompanyOnboarding.FILL, "...then fill")
	_expect(_id({}, {"day": 3, "triggers": fired, "assisted_packing": true}, all) == &"",
		"Armado asistido skips fill")
	_expect(_id({}, {"day": 1, "triggers": {CompanyOnboarding.RESTOCK: true}}, all) == CompanyOnboarding.RESTOCK,
		"restock may show on day 1 once its trigger fired")
	all[CompanyOnboarding.FILL] = true
	all[CompanyOnboarding.RESTOCK] = true
	_expect(_id({"driving": true, "holding": true}, {"day": 4, "triggers": fired}, all) == &"",
		"a profile that did everything sees nothing")


func _test_keys() -> void:
	for id: StringName in CompanyOnboarding.KEYS:
		var key: String = CompanyOnboarding.KEYS[id]
		TranslationServer.set_locale("en")
		var en: String = TranslationServer.translate(key)
		TranslationServer.set_locale("es")
		var es: String = TranslationServer.translate(key)
		_expect(en != key and es != key and en != es, "%s is translated in es and en" % key)
		_expect(CompanyOnboarding.ACTIONS.has(id), "%s has an action" % id)
	_expect(TranslationServer.translate("UI_ONBOARD_CONTROL").count("%s") == 1, "the control line takes the key")


class FakePlayer:
	extends Node
	var seat_node_path: NodePath = NodePath()
	var carried_package: Node = null


func _tracker(net: CompanyNet, profile: FakeProfile, player: FakePlayer, book: OrderBook) -> CompanyOnboardingTracker:
	var tracker := CompanyOnboardingTracker.new()
	tracker.net = net
	tracker.profile = profile
	tracker.peer_id = func() -> int: return 7
	tracker.player_of = func() -> Node: return player
	tracker.books_of = func() -> Array: return [book]
	root.add_child(tracker)
	return tracker


func _test_tracker() -> void:
	var net := CompanyNet.new()
	root.add_child(net)
	net.inventory = Inventory.new()
	net.inventory.receive(&"hen", 3, &"pallet:p1")
	var profile := FakeProfile.new()
	var player := FakePlayer.new()
	root.add_child(player)
	var book := OrderBook.new()
	var items: Array = [{"product": &"hen", "qty": 1}]
	_expect(book.add(Order.make(&"d1_o01", "Ana", &"centro", &"h1", items, 0, {})), "the order goes in the book")
	var tracker: CompanyOnboardingTracker = _tracker(net, profile, player, book)
	await process_frame
	_expect(tracker.line().get("id") == CompanyOnboarding.STOCK_PALLET, "a fresh profile starts on stock_pallet")
	var hands: StringName = CompanyNet.hands_location(7)
	net.event_applied.emit(1, &"units_moved", {"product": &"hen", "qty": 1, "from": &"hands:9", "to": &"shelf:a_0"})
	_expect(not tracker.is_done(CompanyOnboarding.STOCK_PALLET), "another peer's units do not tick it")
	net.event_applied.emit(2, &"units_moved", {"product": &"hen", "qty": 1, "from": hands, "to": &"shelf:a_0"})
	_expect(tracker.is_done(CompanyOnboarding.STOCK_PALLET), "units from these hands to a shelf tick stock_pallet")
	_expect(tracker.line().get("id") == CompanyOnboarding.PICK, "...and the line goes to pick")
	net.event_applied.emit(3, &"units_moved", {"product": &"hen", "qty": 1, "from": &"shelf:a_0", "to": hands})
	_expect(tracker.is_done(CompanyOnboarding.PICK), "units from a shelf into these hands tick pick")
	_expect(book.mark_packed(&"d1_o01", &"box1"), "the order is packed")
	tracker.refresh()
	_expect(tracker.is_done(CompanyOnboarding.PACK) and not tracker.is_done(CompanyOnboarding.DRIVE),
		"a packed order ticks pack")
	_expect(book.mark_out(&"d1_o01", &"t1"), "the order goes out")
	tracker.refresh()
	_expect(not tracker.is_done(CompanyOnboarding.DRIVE), "out with nobody seated is not drive")
	player.seat_node_path = NodePath("Van/Driver")
	tracker.refresh()
	_expect(tracker.is_done(CompanyOnboarding.DRIVE), "seated with an order out ticks drive")
	tracker.call(&"_on_trip_closed", &"t1", &"van", [] as Array[StringName])
	tracker.refresh()
	_expect(not tracker.is_done(CompanyOnboarding.RETURN), "a trip back before any delivery is not return")
	_expect(book.mark_delivered(&"d1_o01", 90, true, 600) >= 0, "the order is delivered")
	tracker.refresh()
	_expect(tracker.is_done(CompanyOnboarding.DELIVER) and not tracker.is_done(CompanyOnboarding.RETURN),
		"delivered ticks deliver; the trip back from before does not tick return")
	tracker.call(&"_on_trip_closed", &"t1", &"van", [] as Array[StringName])
	tracker.refresh()
	_expect(tracker.is_done(CompanyOnboarding.RETURN), "a trip back after the delivery ticks return")
	_expect(tracker.line().is_empty(), "day 1 done: no line")
	var tips: Array[StringName] = []
	for id: StringName in CompanyOnboarding.DAY_ONE:
		tips.append(CompanyOnboarding.tip_id(id))
	_expect(profile.marks == tips, "each step went into the profile once, in order (got %s)" % [profile.marks])
	var again: CompanyOnboardingTracker = _tracker(net, profile, player, book)
	await process_frame
	_expect(again.line().is_empty() and again.is_done(CompanyOnboarding.RETURN),
		"a tracker on that profile starts with the loop done")
	again.free()
	# Joining a company mid-day: what the books already hold was the crew's, not this player's.
	var joiner_profile := FakeProfile.new()
	var joiner: CompanyOnboardingTracker = _tracker(net, joiner_profile, player, book)
	await process_frame
	joiner.refresh()
	_expect(not joiner.is_done(CompanyOnboarding.PACK) and not joiner.is_done(CompanyOnboarding.DELIVER),
		"who joins mid-day does not tick the crew's packed and delivered orders")
	var late := OrderBook.new()
	var late_items: Array = [{"product": &"hen", "qty": 1}]
	_expect(late.add(Order.make(&"d1_o02", "Leo", &"centro", &"h2", late_items, 0, {})), "a second order")
	var late_tracker: CompanyOnboardingTracker = _tracker(net, FakeProfile.new(), player, late)
	await process_frame
	_expect(late.expire(10000).size() == 1 and late.state_of(&"d1_o02") == &"late", "an order goes late unpacked")
	late_tracker.refresh()
	_expect(not late_tracker.is_done(CompanyOnboarding.PACK) and not late_tracker.is_done(CompanyOnboarding.DELIVER),
		"a late order that was never packed ticks neither pack nor deliver")
	late_tracker.free()
	joiner.free()
	tracker.free()
	player.free()
	net.free()


func _test_line() -> void:
	var line := CompanyOnboardingLine.new()
	root.add_child(line)
	await process_frame
	line.show_line(CompanyOnboarding.line(CompanyOnboarding.PICK))
	_expect(line.objective_text().ends_with(tr("UI_ONBOARD_PICK")) and line.control_text() != "",
		"the line shows the objective and its control (got '%s' / '%s')" % [line.objective_text(), line.control_text()])
	line.tick(CompanyOnboarding.PICK)
	line.show_line(CompanyOnboarding.line(CompanyOnboarding.PACK))
	_expect(line.objective_text().begins_with(CompanyOnboardingLine.TICK_MARK), "a tick shows ✓ with the line done")
	await create_timer(CompanyOnboardingLine.TICK_SECONDS + 0.3).timeout
	_expect(line.objective_text().ends_with(tr("UI_ONBOARD_PACK")), "...then the next line")
	line.show_line({})
	_expect(line.objective_text() == "" and not line.visible, "an empty line hides it")
	line.free()
