extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_assembly_quality.gd
##
## Packing quality 0-100 (expansion D-0709, assembly_quality.gd), six boxes of known quality for an
## order of one porcelain vase that asks for the fragile seal:
## - a vase filling an S box, taped, labeled and sealed: 100;
## - the same without the seal: 85 (-15 per missing seal);
## - the vase alone in an M box, nothing padded: 19/27 free cells, fragile, so -30 x 1.5 x 19/27;
## - the same M box with every gap padded: 100;
## - no tape and no label: -10, once;
## - a hen instead of the vase: wrong contents -40, half the S box empty -15 (not fragile), no seal -15;
## - a null box scores 0, and the score never leaves 0..100.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const HEN: ProductDefinition = preload("res://data/products/hen.tres")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var products: Dictionary = {&"porcelain_vase": VASE, &"hen": HEN}
	var order: Dictionary = {
		"id": &"o1",
		"items": [{"product": &"porcelain_vase", "qty": 1}],
		"requirements": [&"fragile"],
	}
	_expect_near(
		AssemblyQuality.score(_box(&"S", VASE, true, true, true), order, products),
		100.0,
		"perfect box"
	)
	_expect_near(
		AssemblyQuality.score(_box(&"S", VASE, true, true, false), order, products),
		85.0,
		"missing seal"
	)
	var loose: PackedBox = _box(&"M", VASE, true, true, true)
	_expect_near(
		AssemblyQuality.score(loose, order, products),
		100.0 - 30.0 * 1.5 * 19.0 / 27.0,
		"unpadded fragile gaps"
	)
	loose.fill_free_cells(19)
	_expect_near(AssemblyQuality.score(loose, order, products), 100.0, "padded gaps cost nothing")
	_expect_near(
		AssemblyQuality.score(_box(&"S", VASE, false, false, true), order, products),
		90.0,
		"no tape, no label"
	)
	_expect_near(
		AssemblyQuality.score(_box(&"S", VASE, true, false, true), order, products),
		90.0,
		"no label alone"
	)
	_expect_near(
		AssemblyQuality.score(_box(&"S", HEN, true, true, false), order, products),
		30.0,
		"wrong content"
	)
	var parts: Dictionary = AssemblyQuality.breakdown(
		_box(&"S", HEN, true, true, false), order, products
	)
	_expect_near(parts["content"], 40.0, "breakdown: content")
	_expect_near(parts["gaps"], 15.0, "breakdown: gaps")
	_expect_near(parts["seals"], 15.0, "breakdown: seals")
	_expect_near(parts["closure"], 0.0, "breakdown: closure")
	_expect_near(AssemblyQuality.score(null, order, products), 0.0, "null box")
	var hopeless: PackedBox = _box(&"XL", HEN, false, false, false)
	var q: float = AssemblyQuality.score(hopeless, order, products)
	_expect(q >= 0.0 and q <= 100.0, "score stays inside 0..100")
	quit(_failures)


func _box(
	size: StringName, product: ProductDefinition, taped: bool, labeled: bool, sealed: bool
) -> PackedBox:
	var box := PackedBox.new(size)
	box.place(product, Vector3i.ZERO)
	box.taped = taped
	if labeled:
		box.label_order_id = &"o1"
	if sealed:
		box.stamps.append(&"fragile")
	return box


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _expect_near(got: float, want: float, label: String) -> void:
	_expect(absf(got - want) < 0.01, "%s (got %.3f, want %.3f)" % [label, got, want])
