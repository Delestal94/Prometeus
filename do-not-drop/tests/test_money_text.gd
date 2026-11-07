extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_money_text.gd
## Covers D-0546: money is shown with the separator of the language ("$1,234" in English, "$1.234" in
## Spanish), negative amounts keep the sign before the "$", and small amounts get no separator.

var _failures: int = 0


func _initialize() -> void:
	_expect(MoneyText.format(0, "en") == "$0", "zero")
	_expect(MoneyText.format(999, "en") == "$999", "no separator under 1000")
	_expect(MoneyText.format(1234, "en") == "$1,234", "English groups with a comma")
	_expect(MoneyText.format(1234, "es_AR") == "$1.234", "Spanish groups with a dot")
	_expect(MoneyText.format(1234567, "es") == "$1.234.567", "two separators")
	_expect(MoneyText.format(-1500, "en") == "-$1,500", "a loss keeps the sign first")
	_expect(MoneyText.format(1000, "en") == "$1,000", "exact thousand")
	if _failures == 0:
		print("PASS: money text follows the language")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
