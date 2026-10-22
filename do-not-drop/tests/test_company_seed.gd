extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_seed.gd
##
## The company's world seed (expansion D-0246, company_seed.gd + CompanyState.company_seed):
## - new_company() draws a seed in 1..MAX_SEED, and a given one is kept;
## - the seed survives to_dict() -> from_dict(), also through a JSON round trip (the save);
## - a save without one (before D-0246) gets the same seed from its name on every load, and a
##   malformed one (text, a fraction, 0, negative, over 31 bits) is never kept;
## - for_day(): same seed, day and stream give the same seed; another day, stream or company
##   another one; day_seed() is today's unless a day is given;
## - the whole day of orders (OrderGenerator.generate_day) is the same for two companies with the
##   same seed, and for a host and a client mirror loaded from the host's to_dict(), and changes
##   with the seed;
## - nothing in the business draws randomness outside a seeded generator (no randi()/randf()/
##   randomize()/shuffle()/pick_random() in scripts/gameplay/business/ or scripts/core/company/,
##   other than CompanySeed.fresh()).

const BUSINESS_DIRS: Array[String] = ["res://scripts/gameplay/business", "res://scripts/core/company"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	_expect(state != null, "CompanyState autoload exists")
	if state == null:
		quit(1)
		return
	_test_new_company(state)
	_test_round_trip(state)
	_test_old_and_malformed(state)
	_test_for_day(state)
	_test_same_orders(state)
	_test_no_unseeded_draws()
	state.reset()
	if _failures == 0:
		print("PASS: company seed is saved, shared and the only source of the day's draws")
	quit(_failures)


func _test_new_company(state: Node) -> void:
	state.new_company("Acme")
	var drawn: int = state.company_seed
	_expect(drawn >= 1 and drawn <= CompanySeed.MAX_SEED, "new_company() draws a seed in range (got %d)" % drawn)
	state.new_company("Acme", 1234)
	_expect(state.company_seed == 1234, "a given seed is kept (got %d)" % state.company_seed)
	state.new_company("Acme", -5)
	_expect(state.company_seed >= 1, "an invalid given seed draws a new one (got %d)" % state.company_seed)
	state.reset()
	_expect(state.company_seed == 0, "reset() clears the seed")


func _test_round_trip(state: Node) -> void:
	state.new_company("Acme", CompanySeed.MAX_SEED)
	var saved: Dictionary = state.to_dict()
	_expect(saved.get("company_seed") == CompanySeed.MAX_SEED, "to_dict() carries company_seed")
	state.reset()
	state.from_dict(saved)
	_expect(state.company_seed == CompanySeed.MAX_SEED, "from_dict() restores the seed")
	var json: Variant = JSON.parse_string(JSON.stringify(saved))
	state.reset()
	state.from_dict(json)
	_expect(state.company_seed == CompanySeed.MAX_SEED,
		"the seed survives the JSON of the save exactly (got %d)" % state.company_seed)


func _test_old_and_malformed(state: Node) -> void:
	state.new_company("Old SRL", 77)
	var old: Dictionary = state.to_dict()
	old.erase("company_seed")
	state.from_dict(old)
	var first: int = state.company_seed
	state.from_dict(old)
	_expect(first >= 1 and first <= CompanySeed.MAX_SEED and state.company_seed == first,
		"a save without a seed gets the same one from its name on every load (got %d, %d)"
		% [first, state.company_seed])
	_expect(CompanySeed.from_name("Old SRL") != CompanySeed.from_name("New SRL"), "another name, another seed")
	for bad: Variant in ["123", 12.5, 0, -3, CompanySeed.MAX_SEED + 1, null, [1], {}]:
		_expect(CompanySeed.normalize(bad) == 0, "normalize() refuses %s" % [bad])
		var data: Dictionary = old.duplicate()
		data["company_seed"] = bad
		state.from_dict(data)
		_expect(state.company_seed == CompanySeed.from_name("Old SRL"),
			"a malformed seed (%s) falls back to the name's" % [bad])
	_expect(CompanySeed.normalize(42.0) == 42, "a whole float (JSON) is a seed")


func _test_for_day(state: Node) -> void:
	var a: int = CompanySeed.for_day(1234, 3, CompanySeed.ORDERS)
	_expect(a == CompanySeed.for_day(1234, 3, CompanySeed.ORDERS), "same seed, day and stream: same day seed")
	_expect(a != CompanySeed.for_day(1234, 4, CompanySeed.ORDERS), "another day, another seed")
	_expect(a != CompanySeed.for_day(1234, 3, CompanySeed.SUPPLIERS), "another stream, another seed")
	_expect(a != CompanySeed.for_day(1235, 3, CompanySeed.ORDERS), "another company, another seed")
	state.new_company("Acme", 1234)
	state.day = 3
	_expect(state.day_seed(CompanySeed.ORDERS) == a, "day_seed() is today's")
	_expect(state.day_seed(CompanySeed.ORDERS, 4) == CompanySeed.for_day(1234, 4, CompanySeed.ORDERS),
		"day_seed() takes another day when given")


func _test_same_orders(state: Node) -> void:
	var zones: Array[ZoneDefinition] = []
	var products: Dictionary = {}
	var requirements: Dictionary = {}
	for file: String in DirAccess.get_files_at("res://data/products"):
		if file.ends_with(".tres"):
			var def: ProductDefinition = load("res://data/products/" + file)
			products[def.id] = def
	for file: String in DirAccess.get_files_at("res://data/order_requirements"):
		if file.ends_with(".tres"):
			var req: OrderRequirement = load("res://data/order_requirements/" + file)
			requirements[req.id] = req
	zones.append(load("res://data/zones/centro.tres") as ZoneDefinition)
	state.new_company("Host SRL", 5150)
	state.day = 2
	var host_day: Array = OrderGenerator.generate_day(
		state.day_seed(CompanySeed.ORDERS), state.day, 3, zones, products, requirements)
	var mirror := Node.new()
	mirror.set_script(state.get_script())
	mirror.from_dict(state.to_dict())
	var client_day: Array = OrderGenerator.generate_day(
		mirror.day_seed(CompanySeed.ORDERS), mirror.day, 3, zones, products, requirements)
	mirror.free()
	_expect(not host_day.is_empty() and str(host_day) == str(client_day),
		"host and a mirror loaded from its to_dict() plan the same orders (%d)" % host_day.size())
	state.new_company("Host SRL", 5151)
	state.day = 2
	var other: Array = OrderGenerator.generate_day(
		state.day_seed(CompanySeed.ORDERS), state.day, 3, zones, products, requirements)
	_expect(str(other) != str(host_day), "another seed, other orders")


func _test_no_unseeded_draws() -> void:
	# Global draws (randi(), randf(), randomize()...) and Array.shuffle() / pick_random() use the
	# engine's unseeded generator; rng.randi() on a seeded RandomNumberGenerator is fine.
	var unseeded := RegEx.create_from_string(
		"(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize)\\(|\\.(shuffle|pick_random)\\(")
	var hits: Array[String] = []
	for dir: String in BUSINESS_DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd") or file == "company_seed.gd":
				continue
			var lines: PackedStringArray = FileAccess.get_file_as_string(dir.path_join(file)).split("\n")
			for i: int in lines.size():
				var line: String = lines[i].strip_edges()
				if not line.begins_with("#") and unseeded.search(line) != null:
					hits.append("%s:%d %s" % [file, i + 1, line])
	_expect(hits.is_empty(), "no unseeded randomness in the business (found %s)" % [hits])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
