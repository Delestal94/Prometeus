extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_expansion_style.gd
##
## One font and one style across the expansion (D-1916, "tema de Godot"):
## - every text of the company screens (closing screen, pause menu, shop, dispatch board, clipboard with its
##   sheets, the day's HUD and the shed's feed) resolves to the brand's fonts: Lilita One (UiTheme.display_font)
##   or Nunito (UiTheme.body_font); none falls back to Godot's default font. The HUD and the feed carry the shared
##   theme (UiTheme.theme()) too;
## - every text in the company world (zone names, shelf labels, the supplier board's sign, the pallets', the
##   dispatch station's, the arrows over the stations and the packing table's marks) is in the display face
##   (UiTheme.label_3d). Not the base game's pieces that also stand in it: the truck's own dashboard (under
##   World/Vehicles) and the neighbours' speech bubbles (DoorReaction, with their own hand-lettered font).

## The world saves here, never in the game's slot.
const DIR: String = "user://test_expansion_style"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"new_company", "Style Co")
	await _check_screens(state)
	state.call(&"reset")
	await _check_world(state)
	if _failures == 0:
		print("PASS: the expansion's screens and world texts use the brand's two fonts")
	quit(_failures)


func _check_screens(state: Node) -> void:
	var summary := DaySummaryPanel.new()
	var pause := CompanyPauseMenu.new()
	var shop := CompanyShopPanel.new()
	var board := DispatchBoardPanel.new()
	var clip := ClipboardFrame.new()
	var hud := CompanyDayHud.new()
	var feed := ShedEventFeed.new()
	var screens: Array = [
		[summary, func() -> void: summary.open({"day": 3, "income_by_reason": {"order_paid": 90}},
			[], 0, {"employees": [{"name": "Ana", "wage": 60}], "tomorrow": ["market"]})],
		[pause, func() -> void: pause.open(true)],
		[shop, func() -> void: shop.open({"company": state, "can_act": true})],
		[board, func() -> void: board.open({})],
		[clip, func() -> void:
			clip.add_sheet(&"stock", "Stock", StockPanel.new())
			clip.add_sheet(&"supplier", "Proveedor", SupplierOrderPanel.new())
			clip.show()],
		[hud, func() -> void: hud.refresh()],
		[feed, func() -> void: feed.on_event(1, CompanyOrdersNet.ADDED, {"order": {"id": "d1_o01"}})],
	]
	for entry: Array in screens:
		var screen: Control = entry[0]
		root.add_child(screen)
		await process_frame
		(entry[1] as Callable).call()
		await process_frame
		var name: String = screen.get_script().resource_path.get_file()
		var texts: int = 0
		for node: Node in screen.find_children("*", "", true, false):
			if node is Label or node is Button or node is LineEdit:
				texts += 1
				var font: Font = (node as Control).get_theme_font(&"font")
				_expect(_brand(font), "%s: %s uses a brand font (got %s)" % [name, node.get_path(), font])
		_expect(texts > 0, "%s has texts to check" % name)
		screen.queue_free()
		await process_frame
	_expect(_themed(CompanyDayHud), "the day's HUD carries the shared theme")
	_expect(_themed(ShedEventFeed), "the feed carries the shared theme")


func _themed(script: GDScript) -> bool:
	var node: Control = script.new()
	root.add_child(node)
	var ok: bool = node.theme == UiTheme.theme()
	node.free()
	return ok


func _check_world(state: Node) -> void:
	var world := (load("res://scenes/gameplay/company_root.tscn") as PackedScene).instantiate() as CompanyRoot
	world.save_dir = DIR
	root.add_child(world)
	for i: int in 4:
		await process_frame
	var indicators := world.shed.get_node_or_null(^"ShedIndicators") as ShedIndicators
	if indicators != null and not world.shed.stations.is_empty():
		(world.shed.stations.values()[0] as PackingStation).supplies.stock[StationSupplies.TAPE] = 0
		indicators.refresh()
	var vfx := world.get_node_or_null(^"PackingVfx") as PackingVfx
	if vfx != null:
		vfx.play(PackingVfx.KIND_DONE, Vector3.ZERO)
	var labels: Array[Node] = world.find_children("*", "Label3D", true, false)
	_expect(labels.size() > 5, "the world has its texts (%d)" % labels.size())
	var kinds: Dictionary = {}
	for node: Node in labels:
		var label := node as Label3D
		var path: String = str(world.get_path_to(label))
		if path.begins_with("World/Vehicles/") or label.name == "SpeechBubble":
			continue
		kinds[label.name.get_slice("_", 0)] = true
		_expect(label.font != null and _brand(label.font), "%s is in the brand's face" % world.get_path_to(label))
	_expect(kinds.has("Need") and kinds.has("Mark"), "the arrows and the marks were checked too (%s)" % [kinds.keys()])
	world.queue_free()
	await process_frame
	state.call(&"reset")
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)


## Lilita One or a weight of Nunito.
static func _brand(font: Font) -> bool:
	if font == null:
		return false
	if font == UiTheme.display_font() or font.resource_path == UiTheme.DISPLAY_FONT_PATH:
		return true
	var variation := font as FontVariation
	return variation != null and variation.base_font != null \
		and variation.base_font.resource_path == UiTheme.BODY_FONT_PATH


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
