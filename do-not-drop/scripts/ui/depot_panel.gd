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


func close() -> void:
	if not visible:
		return
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
	var back: Button = UiTheme.button(_body, "Volver al depósito", false, Vector2(0, 46))
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
	_header("Pedidos de hoy", "PIZARRA", UiTheme.SKY, "Cada casa espera un paquete en particular. Buscalo por su estante, cargalo en el camión y entregalo en esa puerta.")
	var orders: Array = depot.get(&"orders") if depot != null else []
	if orders.is_empty():
		UiTheme.label(_body, "Ruta sin fin: no hay casas. Cargá lo que quieras y aguantá lo más lejos posible.", 18)
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
		UiTheme.label(text, "Casa %d  ·  estante %s" % [int(order.house) + 1, order.code], 22, UiTheme.INK, true)
		var state: String = "a bordo" if _is_loaded(order.package_id) else "en el estante"
		UiTheme.label(text, "%s · %s  —  %s" % [order.trap, String(order.content).to_lower(), state], 16, UiTheme.MINT if state == "a bordo" else UiTheme.MUTED)


func _build_wardrobe() -> void:
	_header("Vestuario", "UNIFORME", UiTheme.MINT, "Tu color para esta partida. Lo ve todo el equipo.")
	_choices(UnlockManager.cosmetic_choices(), UnlockManager.selected_cosmetic, UnlockManager.select_cosmetic, true)


func _build_garage() -> void:
	var host: bool = NetworkManager.is_host()
	_header("Taller", "CAMIÓN Y PINTURA", UiTheme.RED,
		"Los cambios se ven al instante en el camión." if host else "El camión lo elige quien hostea la partida. Podés mirar lo que hay.")
	UiTheme.label(_body, "Camión", 20, UiTheme.INK, true)
	_choices(UnlockManager.truck_choices(), UnlockManager.selected_truck, UnlockManager.select_truck, host)
	UiTheme.label(_body, "Pintura", 20, UiTheme.INK, true)
	_choices(UnlockManager.paint_choices(), UnlockManager.selected_paint, UnlockManager.select_paint, host)


func _build_shop() -> void:
	var money: int = int(depot.get(&"team_money")) if depot != null else CrewProgression.team_money
	var owned: Array = depot.get(&"supplies") if depot != null else []
	var peer_id: int = NetworkManager.local_id()
	var voting: bool = NetworkManager.is_online()
	var has_discount: bool = CrewProgression.has_card(peer_id, CrewProgression.Card.DISCOUNT)
	var has_revote: bool = CrewProgression.has_card(peer_id, CrewProgression.Card.REVOTE)
	var current_winner: StringName = ShopVoteManager.resolve_winner(NetworkManager.peer_ids) if voting else &""
	_header("Suministros", "CAJA DEL EQUIPO  ·  $%d" % money, UiTheme.YELLOW, "Se pagan con la plata del equipo y se usan en el próximo reparto que salga del depósito.")
	if voting:
		_vote_timer_label = UiTheme.label(_body, _vote_status_text(), 17, UiTheme.GRAPE, true)
	if has_revote and voting:
		var revote: Button = UiTheme.button(_body, "Usar Re-voto", false, Vector2(0, 42))
		revote.disabled = not ShopVoteManager.active
		revote.tooltip_text = "Disponible cuando haya una votación de compra activa."
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
		var label: String = "%s%s  ·  $%d" % ["Votar: " if voting else "", item.title, cost]
		if have:
			label = "%s  ·  listo para salir" % item.title
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
			var discount: Button = UiTheme.button(row, "Usar Descuento (−50 %%)  ·  $%d" % discounted_cost, true, Vector2(0, 40))
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
		return "Votación cerrada · volvé a abrir el mostrador para iniciar otra"
	if not ShopVoteManager.timer_started:
		return "Votación abierta · el reloj empieza con el primer voto"
	return "Votación abierta · %d s" % ceili(ShopVoteManager.seconds_left)


func _add_voters(parent: Node, supply_id: StringName) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	parent.add_child(line)
	UiTheme.label(line, "Votos:", 14, UiTheme.MUTED)
	var count: int = 0
	for voter: Variant in NetworkManager.peer_ids:
		var peer_id: int = int(voter)
		if StringName(ShopVoteManager.votes.get(peer_id, &"")) != supply_id:
			continue
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(20, 20)
		dot.tooltip_text = "Jugador %d" % peer_id
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
	_header("Equipo del mes", "PROGRESO", UiTheme.GRAPE, "")
	var summary: Dictionary = UnlockManager.progress_summary()
	UiTheme.label(_body, "%d entregas exitosas  ·  %d puntos  ·  %d partidas  ·  mejor reparto %d pts" % [
		int(summary.deliveries), int(summary.score), int(summary.runs), RunManager.best_score()], 16, UiTheme.MUTED)
	for unlock_id: StringName in UnlockManager.UNLOCKS:
		var rule: Dictionary = UnlockManager.requirements(unlock_id)
		var got: bool = UnlockManager.is_unlocked(unlock_id)
		UiTheme.label(_body, "%s  %s  —  %d entregas + %d pts" % ["Listo:" if got else "Falta:", rule.title, int(rule.deliveries), int(rule.score)], 17, UiTheme.MINT if got else UiTheme.MUTED)


func _choices(choices: Array[Dictionary], selected: StringName, select: Callable, enabled: bool) -> void:
	for choice: Dictionary in choices:
		var id: StringName = choice["id"]
		var available: bool = bool(choice["available"])
		var text: String = String(choice["title"])
		if choice.has("detail"):
			text += "  ·  " + String(choice["detail"])
		if not available:
			var rule: Dictionary = UnlockManager.requirements(StringName(choice["unlock"]))
			text += "  — bloqueado (%d entregas, %d pts)" % [int(rule.get("deliveries", 0)), int(rule.get("score", 0))]
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
