extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_cold_notice.gd
##
## The notice that something rotted (expansion D-0616.c, spoil_notice.gd, wired in company_root.gd):
## - SpoilNotice.text(): "Se echó a perder: 4 Bidón de leche" / "Spoiled: 4 Milk canister" from a units_spoiled
##   (product name from the catalog, in the player's language); an id the catalog doesn't know is shown
##   as is; a malformed event (no product, 0 or negative units) gives "";
## - SpoilNotice.announce(): sends the text as depot_notice on the bus, nothing when there is no bus or the
##   event is malformed;
## - the real CompanyRoot: when the host's tick rots the milk of the first pallets, the peer shows one
##   notice per product through EventBus.depot_notice with the units that were lost (the milk's, and the
##   cake's in its own notice).
## Expected in the log: the engine's leak notes at exit.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_cold_notice"

class FakeBus:
	extends Node
	signal depot_notice(text: String)

var _failures: int = 0
var _heard: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_text()
	_test_announce()
	await _test_root()
	if _failures == 0:
		print("PASS: a spoiled product is announced with its name and units")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)


func _test_text() -> void:
	var event := {"product": &"milk_canister", "qty": 4, "location": &"shelf:shelf_1_0"}
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	_expect(SpoilNotice.text(event) == "Se echó a perder: 4 Bidón de leche",
		"Spanish: units and name of the product (got '%s')" % SpoilNotice.text(event))
	TranslationServer.set_locale("en")
	_expect(SpoilNotice.text(event) == "Spoiled: 4 Milk canister",
		"English: units and name of the product (got '%s')" % SpoilNotice.text(event))
	var unknown := {"product": &"no_such_thing", "qty": 1, "location": &"x"}
	_expect(SpoilNotice.text(unknown) == "Spoiled: 1 no_such_thing", "An unknown id is shown as is")
	TranslationServer.set_locale(previous)
	for bad: Dictionary in [{}, {"product": &"milk_canister"}, {"product": &"milk_canister", "qty": 0},
			{"product": &"milk_canister", "qty": -2}, {"qty": 3}, {"product": &"", "qty": 3}]:
		_expect(SpoilNotice.text(bad) == "", "A malformed event gives no text (%s)" % [bad])


func _test_announce() -> void:
	var bus := FakeBus.new()
	var heard: Array[String] = []
	bus.depot_notice.connect(func(text: String) -> void: heard.append(text))
	var event := {"product": &"milk_canister", "qty": 2, "location": &"shelf:shelf_1_0"}
	_expect(SpoilNotice.announce(bus, event) and heard.size() == 1 and heard[0].contains("2"),
		"announce() sends one depot_notice (got %s)" % [heard])
	_expect(not SpoilNotice.announce(bus, {"product": &"milk_canister", "qty": 0}) and heard.size() == 1,
		"A malformed event sends nothing")
	_expect(not SpoilNotice.announce(null, event), "No bus, nothing to send, no error")
	_expect(not SpoilNotice.announce(Node.new(), event), "A node without the signal is ignored")
	bus.free()


func _on_notice(text: String) -> void:
	_heard.append(text)


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var tick: ColdChainTick = level.get_node_or_null(ColdChainTick.NODE_NAME) as ColdChainTick
	_expect(tick != null, "The root has its cold chain tick")
	if tick != null:
		var bus: Node = root.get_node(^"/root/EventBus")
		bus.connect(&"depot_notice", _on_notice)
		var milk: StringName = &"milk_canister"
		var total: int = level.net.inventory.count(milk)
		level.clock.start(float(CompanyTuning.DAY_START_MIN))
		tick.poll()
		level.clock.start(float(CompanyTuning.DAY_START_MIN) + 60.0)
		tick.poll()
		var before: int = _heard.size()
		level.clock.start(float(CompanyTuning.DAY_START_MIN) + 60.0 + CompanyTuning.COLD_SPOIL_MINUTES)
		tick.poll()
		var lost: int = total - level.net.inventory.count(milk)
		_expect(lost > 0, "The pallet milk rotted (lost %d of %d)" % [lost, total])
		var mine: Array[String] = _heard.slice(before)
		_expect(not mine.is_empty(), "The player was told (got %s)" % [mine])
		var expected: String = SpoilNotice.text({"product": milk, "qty": lost})
		_expect(mine.has(expected) and mine.count(expected) == 1,
			"One notice says the milk lost ('%s'; got %s)" % [expected, mine])
		bus.disconnect(&"depot_notice", _on_notice)
	level.free()
	state.call(&"reset")
	_clean()


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
