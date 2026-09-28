class_name DepotPanel
extends Control
## The screen a depot station opens (depot_station.gd): one panel, five
## faces -- the order sheet, the lockers (uniform), the workshop (truck and
## paint), the supplies counter and the team's progress. Same "shipping
## label" look as every other screen (UiTheme), full keyboard and gamepad.
##
## It doesn't pause anything: in co-op the world keeps going while you pick a
## uniform. The player stops reading input while the cursor is free, and gets
## it back when this closes.

signal closed

var station: StringName = &"orders"
## The level's depot, for its orders and to ask for a purchase.
var depot: Node = null
var _body: VBoxContainer
var _first_focus: Control = null
var _vote_timer_label: Label = null


func open(station_id: StringName, depot_node: Node) -> void:
	station = station_id
	depot = depot_node
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if station == &"shop" and NetworkManager.is_online():
		_request_open_vote()
	_rebuild()
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)


func close() -> void:
	if not visible:
		return
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	hide()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"depot_supplies_changed", func(_list: Array, _money: int) -> void:
			if visible and station == &"shop":
				_rebuild())
		bus.connect(&"card_changed", func(peer_id: int, _card_id: int) -> void:
			if visible and station == &"shop" and peer_id == NetworkManager.local_id():
				_rebuild())
		bus.connect(&"shop_opened", func(_offers: Dictionary) -> void:
			if visible and station == &"shop":
				_rebuild())
		bus.connect(&"shop_vote_changed", func(_peer_id: int, _offer_id: StringName) -> void:
			if visible and station == &"shop":
				UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.VOTE)
				_rebuild())
		bus.connect(&"shop_resolved", _on_shop_resolved)
		# Somebody else took the wheel: the depot is behind us now.
		bus.connect(&"run_started", func(_route: StringName, _players: Array) -> void: close())
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	if unlocks != null:
		unlocks.connect(&"progress_changed", func() -> void:
			if visible and station in [&"wardrobe", &"garage", &"records"]:
				_rebuild())


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _vote_timer_label == null or not visible or station != &"shop":
		return
	_vote_timer_label.text = _vote_status_text()


func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_first_focus = null
	_vote_timer_label = null
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_body = UiTheme.panel(center, Vector2(620, 0), 28)
	_body.add_theme_constant_override("separation", 12)
	match station:
		&"wardrobe":
			_build_wardrobe()
		&"garage":
			_build_garage()
		&"shop":
			_build_shop()
		&"records":
			_build_records()
		_:
			_build_orders()
	var back: Button = UiTheme.button(_body, tr("UI_DEPOT_BACK"), false, Vector2(0, 46))
	back.pressed.connect(close)
	if _first_focus == null:
		_first_focus = back
	_first_focus.call_deferred(&"grab_focus")


func _header(title: String, tag: String, tag_color: Color, subtitle: String) -> void:
	UiTheme.title(_body, title, 38)
	UiTheme.tag(_body, tag, tag_color, -1.5, 14)
	if not subtitle.is_empty():
		var line: Label = UiTheme.label(_body, subtitle, 16, UiTheme.MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 560


func _build_orders() -> void:
	_header(tr("UI_DEPOT_ORDERS"), tr("UI_DEPOT_ORDERS_TAG"), UiTheme.SKY, tr("UI_DEPOT_ORDERS_HINT"))
	var orders: Array = depot.get(&"orders") if depot != null else []
	if orders.is_empty():
		UiTheme.label(_body, tr("UI_DEPOT_ENDLESS_HINT"), 18)
		return
	for order: Dictionary in orders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_body.add_child(row)
		var icon := TextureRect.new()
		icon.texture = UiTheme.trap_icon(String(order.trap))
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var text := VBoxContainer.new()
		row.add_child(text)
		UiTheme.label(text, tr("UI_DEPOT_ORDER_ROW") % [int(order.house) + 1, order.code], 22, UiTheme.INK, true)
		var state: String = tr("UI_DEPOT_ON_BOARD") if _is_loaded(order.package_id) else tr("UI_DEPOT_ON_SHELF")
		UiTheme.label(text, "%s · %s  —  %s" % [order.trap, String(order.content).to_lower(), state], 16, UiTheme.MINT if state == tr("UI_DEPOT_ON_BOARD") else UiTheme.MUTED)


func _build_wardrobe() -> void:
	_header(tr("UI_DEPOT_LOCKERS"), tr("UI_DEPOT_UNIFORM_TAG"), UiTheme.MINT, tr("UI_DEPOT_UNIFORM_HINT"))
	_choices(UnlockManager.cosmetic_choices(), UnlockManager.selected_cosmetic, UnlockManager.select_cosmetic, true)


func _build_garage() -> void:
	var host: bool = NetworkManager.is_host()
	_header(tr("UI_DEPOT_WORKSHOP"), tr("UI_DEPOT_WORKSHOP_TAG"), UiTheme.RED,
		tr("UI_DEPOT_WORKSHOP_HOST_HINT") if host else tr("UI_DEPOT_WORKSHOP_GUEST_HINT"))
	UiTheme.label(_body, tr("UI_TRUCK"), 20, UiTheme.INK, true)
	_choices(UnlockManager.truck_choices(), UnlockManager.selected_truck, UnlockManager.select_truck, host)
	UiTheme.label(_body, tr("UI_PAINT"), 20, UiTheme.INK, true)
	_choices(UnlockManager.paint_choices(), UnlockManager.selected_paint, UnlockManager.select_paint, host)


func _build_shop() -> void:
	var money: int = int(depot.get(&"team_money")) if depot != null else CrewProgression.team_money
	var owned: Array = depot.get(&"supplies") if depot != null else []
	var peer_id: int = NetworkManager.local_id()
	var voting: bool = NetworkManager.is_online()
	var has_discount: bool = CrewProgression.has_card(peer_id, CrewProgression.Card.DISCOUNT)
	var has_revote: bool = CrewProgression.has_card(peer_id, CrewProgression.Card.REVOTE)
	var current_winner: StringName = ShopVoteManager.resolve_winner(NetworkManager.peer_ids) if voting else &""
	_header(tr("UI_DEPOT_SUPPLIES"), tr("UI_DEPOT_TEAM_CASH") % money, UiTheme.YELLOW, tr("UI_DEPOT_SUPPLIES_HINT"))
	if voting:
		_vote_timer_label = UiTheme.label(_body, _vote_status_text(), 17, UiTheme.GRAPE, true)
	if has_revote and voting:
		var revote: Button = UiTheme.button(_body, tr("UI_DEPOT_USE_REVOTE"), false, Vector2(0, 42))
		revote.disabled = not ShopVoteManager.active
		revote.tooltip_text = tr("UI_DEPOT_REVOTE_TOOLTIP")
		revote.pressed.connect(_use_revote)
		if _first_focus == null and not revote.disabled:
			_first_focus = revote
	for supply_id: StringName in CrewProgression.SUPPLIES:
		var item: Dictionary = CrewProgression.SUPPLIES[supply_id]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_body.add_child(row)
		var have: bool = owned.has(supply_id)
		var cost: int = int(item.cost)
		var label: String = "%s%s  ·  $%d" % [tr("UI_DEPOT_VOTE_PREFIX") if voting else "", item.title, cost]
		if have:
			label = tr("UI_DEPOT_SUPPLY_READY") % item.title
		var enabled: bool = not have and money >= cost and (not voting or ShopVoteManager.active)
		var button: Button = UiTheme.button(row, label, enabled, Vector2(0, 46))
		button.disabled = not enabled
		button.pressed.connect(func() -> void:
			if voting:
				_request_vote(supply_id)
			else:
				var depot_node: Node = _depot_node()
				if depot_node != null:
					depot_node.call(&"buy_supply", supply_id))
		if _first_focus == null and not button.disabled:
			_first_focus = button
		var detail: Label = UiTheme.label(row, String(item.detail), 15, UiTheme.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 560
		if voting:
			_add_voters(row, supply_id)
		if has_discount and not have and (not voting or supply_id == current_winner):
			var discounted_cost: int = maxi(0, roundi(cost * 0.5))
			var discount: Button = UiTheme.button(row, tr("UI_DEPOT_USE_DISCOUNT") % discounted_cost, true, Vector2(0, 40))
			discount.disabled = money < discounted_cost or (voting and not ShopVoteManager.active)
			discount.pressed.connect(func() -> void:
				if voting:
					_request_discount(supply_id)
				else:
					var depot_node: Node = _depot_node()
					if depot_node != null:
						depot_node.call(&"buy_supply_discounted", supply_id))
			if _first_focus == null and not discount.disabled:
				_first_focus = discount


func _use_revote() -> void:
	if NetworkManager.is_online() and not NetworkManager.is_host():
		ShopVoteManager.rpc_id(1, &"request_revote")
	else:
		ShopVoteManager.request_revote()


func _request_open_vote() -> void:
	if NetworkManager.is_host():
		ShopVoteManager.request_open_shop()
	else:
		ShopVoteManager.rpc_id(1, &"request_open_shop")


func _request_vote(supply_id: StringName) -> void:
	if NetworkManager.is_host():
		ShopVoteManager.request_vote(supply_id)
	else:
		ShopVoteManager.rpc_id(1, &"request_vote", supply_id)


func _request_discount(supply_id: StringName) -> void:
	if NetworkManager.is_host():
		ShopVoteManager.request_discount(supply_id)
	else:
		ShopVoteManager.rpc_id(1, &"request_discount", supply_id)


func _vote_status_text() -> String:
	if not ShopVoteManager.active:
		return tr("UI_DEPOT_VOTE_CLOSED")
	if not ShopVoteManager.timer_started:
		return tr("UI_DEPOT_VOTE_OPEN")
	return tr("UI_DEPOT_VOTE_OPEN_TIMER") % ceili(ShopVoteManager.seconds_left)


func _add_voters(parent: Node, supply_id: StringName) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	parent.add_child(line)
	UiTheme.label(line, tr("UI_DEPOT_VOTES"), 14, UiTheme.MUTED)
	var count: int = 0
	for voter: Variant in NetworkManager.peer_ids:
		var peer_id: int = int(voter)
		if StringName(ShopVoteManager.votes.get(peer_id, &"")) != supply_id:
			continue
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(20, 20)
		dot.tooltip_text = tr("UI_PLAYER_N") % peer_id
		var style := StyleBoxFlat.new()
		style.bg_color = Player.PLAYER_COLORS[peer_id % Player.PLAYER_COLORS.size()]
		style.border_color = UiTheme.INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(99)
		dot.add_theme_stylebox_override("panel", style)
		line.add_child(dot)
		count += 1
	if count == 0:
		UiTheme.label(line, "—", 14, UiTheme.MUTED)


func _on_shop_resolved(offer_id: StringName, offer: Dictionary) -> void:
	var discounted: bool = bool(offer.get("discounted", false))
	var should_purchase: bool = NetworkManager.local_id() == int(offer.get("discount_peer", 0)) if discounted else NetworkManager.is_host()
	if should_purchase and not offer_id.is_empty():
		var depot_node: Node = _depot_node()
		if depot_node != null:
			if discounted:
				depot_node.call(&"buy_supply_discounted", offer_id)
			else:
				depot_node.call(&"buy_supply", offer_id)
	if visible and station == &"shop":
		_rebuild()


func _depot_node() -> Node:
	if is_instance_valid(depot):
		return depot
	var scene: Node = get_tree().current_scene
	return scene.get(&"depot") if scene != null and &"depot" in scene else null


func _build_records() -> void:
	_header(tr("UI_DEPOT_RECORDS"), tr("UI_DEPOT_PROGRESS_TAG"), UiTheme.GRAPE, "")
	var summary: Dictionary = UnlockManager.progress_summary()
	UiTheme.label(_body, tr("UI_DEPOT_RECORDS_SUMMARY") % [
		int(summary.deliveries), int(summary.score), int(summary.runs), RunManager.best_score()], 16, UiTheme.MUTED)
	for unlock_id: StringName in UnlockManager.UNLOCKS:
		var rule: Dictionary = UnlockManager.requirements(unlock_id)
		var got: bool = UnlockManager.is_unlocked(unlock_id)
		UiTheme.label(_body, tr("UI_DEPOT_UNLOCK_LINE") % [tr("UI_DEPOT_UNLOCK_DONE") if got else tr("UI_DEPOT_UNLOCK_TODO"), rule.title, int(rule.deliveries), int(rule.score)], 17, UiTheme.MINT if got else UiTheme.MUTED)


func _choices(choices: Array[Dictionary], selected: StringName, select: Callable, enabled: bool) -> void:
	for choice: Dictionary in choices:
		var id: StringName = choice["id"]
		var available: bool = bool(choice["available"])
		var text: String = String(choice["title"])
		if choice.has("detail"):
			text += "  ·  " + String(choice["detail"])
		if not available:
			var rule: Dictionary = UnlockManager.requirements(StringName(choice["unlock"]))
			text += tr("UI_DEPOT_LOCKED_SUFFIX") % [int(rule.get("deliveries", 0)), int(rule.get("score", 0))]
		var button: Button = UiTheme.button(_body, text, id == selected, Vector2(0, 44))
		button.disabled = not available or not enabled
		button.clip_text = true
		if choice.has("color"):
			var swatch := ColorRect.new()
			swatch.color = Color(choice["color"])
			swatch.custom_minimum_size = Vector2(18, 18)
			swatch.position = Vector2(12, 13)
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(swatch)
			button.add_theme_constant_override("h_separation", 8)
			button.text = "      " + button.text
		button.pressed.connect(func() -> void:
			if select.call(id):
				_rebuild())
		if _first_focus == null and not button.disabled:
			_first_focus = button


func _is_loaded(package_id: StringName) -> bool:
	for package: Node in get_tree().get_nodes_in_group(&"cargo"):
		if StringName(package.get(&"package_id")) == package_id:
			return bool(package.get(&"is_loaded"))
	return false
