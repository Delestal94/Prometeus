class_name DayClose
extends RefCounted
## Closing the day early and what the exits warn (expansion D-0253, diseno/guardado.md rule 2).
## Pure functions over the world's DayCycle, no node, no state. A day that is cut (leaving, the
## host gone, the process killed) leaves nothing: the save is still that day's opening. To keep
## what was done, the host closes the day from the pause: DayCycle.close_early() sends CLOSING now,
## the trips come back, the summary saves it like any close, and what was not delivered costs the
## same as at 20:00, so it dodges nothing.
##
## Decision (D-0253.2): only the host closes it, with no vote; the host already opens the next day.
## The company's pause menu (D-1909) draws its button from button() and puts exit_warning() over
## its two exits (to the menu and out of the game).

## Translation keys: the pause's button, its confirmation, what a client reads on it, and the
## warning over the exits.
const BUTTON_KEY: String = "UI_COMPANY_CLOSE_DAY"
const CONFIRM_KEY: String = "UI_COMPANY_CLOSE_DAY_CONFIRM"
const HOST_ONLY_KEY: String = "UI_COMPANY_CLOSE_DAY_HOST_ONLY"
const EXIT_WARNING_KEY: String = "UI_COMPANY_EXIT_LOSES_DAY"


## True where the button works: on the host (solo too) while the day is OPERATING.
static func can_close(cycle: DayCycle) -> bool:
	return _live(cycle) and cycle.is_host() and cycle.phase() == DayCycle.Phase.OPERATING


## Host, after the confirmation: the day goes to CLOSING now. False, changing nothing, wherever
## can_close() is false.
static func close(cycle: DayCycle) -> bool:
	return can_close(cycle) and cycle.close_early()


## The pause's button as it is drawn: {text, enabled, hint, confirm}. On a client it is off and
## its hint says the host closes the day; on the host it is on while the day is OPERATING, and
## pressing it asks `confirm` first.
static func button(cycle: DayCycle) -> Dictionary:
	var client: bool = _live(cycle) and not cycle.is_host()
	return {
		"text": TranslationServer.translate(BUTTON_KEY),
		"enabled": can_close(cycle),
		"hint": TranslationServer.translate(HOST_ONLY_KEY) if client else "",
		"confirm": TranslationServer.translate(CONFIRM_KEY),
	}


## True when leaving now would lose the day: this peer saves the company (the host, solo too) and
## the day is OPERATING or CLOSING. A client leaving loses nothing of the host's day.
static func exit_loses_day(cycle: DayCycle) -> bool:
	if not _live(cycle) or not cycle.is_host():
		return false
	return cycle.phase() == DayCycle.Phase.OPERATING or cycle.phase() == DayCycle.Phase.CLOSING


## The warning over the exits in the current language, or "" when leaving loses nothing.
static func exit_warning(cycle: DayCycle) -> String:
	return TranslationServer.translate(EXIT_WARNING_KEY) if exit_loses_day(cycle) else ""


static func _live(cycle: DayCycle) -> bool:
	return cycle != null and is_instance_valid(cycle)
