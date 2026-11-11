class_name OrderRating
extends RefCounted
## The customer's rating of a delivery, 1 to 5 stars (expansion D-0816, "Modo Empresa").
##
## Pure functions, no node, no autoload, no UI. stars() reads what OrderSettlement.settle returned:
## a delivery with nothing wrong earns 4 stars, 5 if it also tipped (it was quick); with failures the
## worst one decides (wrong box 1, broken product 2, late or mislabeled 3). The rating is information
## for the door's reaction (D-0817) and the day summary: it moves no money and no reputation, so it
## cannot be farmed. Numbers live in CompanyTuning.

## Translation keys of the words, index 0 = 1 star.
const LABEL_KEYS: Array[String] = [
	"UI_ORDER_STARS_1", "UI_ORDER_STARS_2", "UI_ORDER_STARS_3", "UI_ORDER_STARS_4", "UI_ORDER_STARS_5",
]


## Stars 1-5 for a settle() result. 0 when the result is not ok (nothing was delivered, nothing to rate).
static func stars(result: Dictionary) -> int:
	if not bool(result.get("ok", false)):
		return 0
	var kinds: Array = result.get("kinds", [])
	if kinds.is_empty():
		var best: int = CompanyTuning.STARS_MAX if int(result.get("tip", 0)) > 0 else CompanyTuning.STARS_CLEAN_SLOW
		return clampi(best, CompanyTuning.STARS_MIN, CompanyTuning.STARS_MAX)
	var worst: int = CompanyTuning.STARS_MAX
	for kind: Variant in kinds:
		worst = mini(worst, _stars_of(StringName(str(kind))))
	return clampi(worst, CompanyTuning.STARS_MIN, CompanyTuning.STARS_MAX)


## Translation key of the word for `stars` ("" when it is not 1-5).
static func label_key(stars_count: int) -> String:
	if stars_count < CompanyTuning.STARS_MIN or stars_count > CompanyTuning.STARS_MAX:
		return ""
	return LABEL_KEYS[stars_count - CompanyTuning.STARS_MIN]


## The word for `stars` in the current language ("" when it is not 1-5).
static func label(stars_count: int) -> String:
	var key: String = label_key(stars_count)
	return "" if key.is_empty() else TranslationServer.translate(key)


## Stars a single failure caps the rating at. A kind this class does not know (an abandoned order
## never reaches the door) counts as the worst.
static func _stars_of(kind: StringName) -> int:
	match kind:
		OrderPenalties.KIND_WRONG:
			return CompanyTuning.STARS_WRONG_BOX
		OrderPenalties.KIND_BROKEN:
			return CompanyTuning.STARS_BROKEN
		OrderPenalties.KIND_LATE:
			return CompanyTuning.STARS_LATE
		OrderPenalties.KIND_MISLABELED:
			return CompanyTuning.STARS_MISLABELED
	return CompanyTuning.STARS_MIN
