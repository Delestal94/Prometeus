extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/loc_text/tests/test_loc_text.gd
##
## The loc_text module on its own (docs/modulos.md): a LocText line is
## [key, args...]; render() translates the key where it is drawn, formats the
## arguments in, renders nested lines first, passes a plain String through,
## and shows an unknown key with its values instead of failing the format.

var _failures: int = 0


func _initialize() -> void:
	var line: Array = LocText.make("%s x %d", ["box", 3])
	_expect(line.size() == 3 and line[0] == "%s x %d", "make() keeps the key first (got %s)" % [line])
	_expect(LocText.render(line) == "box x 3",
		"A format key with no translation formats its arguments (got %s)" % LocText.render(line))
	_expect(LocText.render("already built") == "already built", "A String passes through")
	_expect(LocText.render(&"name") == "name", "A StringName passes through")
	_expect(LocText.render([]) == "" and LocText.render(null) == "", "An empty line or nothing renders as empty")
	_expect(LocText.render(["Plain"]) == "Plain",
		"A key alone renders as its translation (got %s)" % LocText.render(["Plain"]))
	var nested: Array = LocText.make("Hold %s", [LocText.make("%s (%d)", ["tape", 2])])
	_expect(LocText.render(nested) == "Hold tape (2)", "Nested lines render first (got %s)" % LocText.render(nested))
	var unknown: Array = LocText.make("UNKNOWN_KEY", [7, "x"])
	_expect(LocText.render(unknown) == "UNKNOWN_KEY 7 x",
		"An unknown key shows its values rather than failing (got %s)" % LocText.render(unknown))
	if _failures == 0:
		print("PASS: LocText lines render, nest and survive unknown keys")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
