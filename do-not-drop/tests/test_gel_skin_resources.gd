extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_skin_resources.gd
## S-311.65: sixteen base skin resources expose stable colour, absorption and shine values.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const Definition := preload("res://scripts/gameplay/player/gel/gel_skin_definition.gd")
const EXPECTED_IDS: Array[StringName] = [
	&"milk", &"strawberry", &"lime", &"grape", &"orange", &"mint", &"lemon", &"blueberry",
	&"cherry", &"cola", &"watermelon", &"blackberry", &"peach", &"sky", &"translucent_charcoal",
	&"rainbow",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Catalog.DEFAULT_ID == &"milk", "milk is the default skin")
	_expect(Catalog.SKINS.size() == 16, "the catalog has exactly sixteen skins")
	_expect(Catalog.ids() == EXPECTED_IDS, "the catalog preserves the sixteen stable IDs and order")
	_expect(Catalog.skin(&"unknown").get(&"id") == &"milk", "unknown skins fall back to milk")

	var seen_ids: Dictionary = {}
	var seen_colors: Dictionary = {}
	for definition: Resource in Catalog.SKINS:
		var skin_id: StringName = definition.get(&"id")
		var color: Color = definition.get(&"color")
		_expect(definition.get_script() == Definition, "%s uses GelSkinDefinition" % skin_id)
		_expect(definition.call(&"is_valid"), "%s has finite in-range gel values" % skin_id)
		_expect(not seen_ids.has(skin_id), "%s has a unique stable ID" % skin_id)
		_expect(not seen_colors.has(color.to_html()), "%s has a distinct base colour" % skin_id)
		_expect(Catalog.skin(skin_id) == definition, "%s resolves from the catalog" % skin_id)
		seen_ids[skin_id] = true
		seen_colors[color.to_html()] = true

	var milk: Resource = Catalog.skin(&"milk")
	var charcoal: Resource = Catalog.skin(&"translucent_charcoal")
	_expect(milk.get(&"color").is_equal_approx(Color(0.78, 0.82, 0.92, 1.0)),
		"milk retains the reference body colour")
	_expect(charcoal.get(&"color").a < 1.0, "charcoal is explicitly translucent")

	if _failures == 0:
		print("PASS: sixteen gel skin resources with colour, absorption and shine")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
