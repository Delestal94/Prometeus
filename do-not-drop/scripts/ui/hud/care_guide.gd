extends RefCounted
## "What now?" for the box in your hands or at your seat (playtest
## 2026-09-28: "I don't know whether to pick it up or what to do"). One step,
## the most urgent first, read from the replicated care state (PackageCare's
## snapshot plus the trap's action, hint and tap sequence that
## PackageRescue.publish_care() adds), so every peer tells the same story:
##   collect  -- a rescue with pieces on the floor: go and pick them up
##   sequence -- a tap sequence pending (the bomb, Peso creciente); for the
##               bomb the owner is told to ask the driver for the code
##   cushion  -- Fragile with a bump announced ahead: one tap, right now
##   lean     -- Balance: hold the primary and lean against the tilt (A/D)
##   scrub    -- Liquid: swing A and D, side to side, nothing held
##   tool     -- a rescue that needs the kit, or a job already under way
##   release  -- the creature says hands off
##   hold     -- keep the primary action held: steady, calm, mop (only
##               while `need_hands` says the box needs it)
##   idle     -- nothing to do right now: you can let go
##   lost     -- nothing left to save
## Pure data in, pure data out: CareCard draws it.

## What holding does, per content, as the card's headline.
## Keys in translations/strings_ui.csv, translated when the step is built.
const HOLD_TITLES: Dictionary = {&"fragile": "HUD_CARE_TITLE_HOLD", &"balance": "HUD_CARE_TITLE_STRAIGHTEN",
	&"liquid": "HUD_CARE_TITLE_MOP", &"noisy": "HUD_CARE_TITLE_CALM", &"hostile": "HUD_CARE_TITLE_CALM",
	&"growing_weight": "HUD_CARE_TITLE_HOLD", &"explosive": "HUD_CARE_TITLE_HOLD"}


## `keys` names the controls as the player's device calls them:
## {primary, tool, interact}. `tool` is the tool the card offers (&"" for
## none) and `tool_name` what to call it.
static func next_step(state: Dictionary, kind: StringName, tool: StringName, tool_name: String,
		keys: Dictionary) -> Dictionary:
	var phase := StringName(state.get("phase", &"intact"))
	var missing: int = int(state.get("missing", 0))
	var sequence: Dictionary = state.get("sequence", {})
	var action := StringName(state.get("action", &"hold"))
	# A LocText line from the host, read in this player's language (N-805).
	var hint: String = LocText.render(state.get("hint", []))
	var working: bool = float(state.get("work", 0.0)) > 0.0 and StringName(state.get("tool", &"")) == tool
	if phase == &"crisis" and missing > 0:
		return _step(&"collect", _tr("HUD_CARE_COLLECT"),
			_tr("HUD_CARE_COLLECT_DETAIL") % [missing, keys.get("interact", "E")])
	var steps: Array = sequence.get("steps", [])
	if int(sequence.get("index", 0)) < steps.size() and bool(sequence.get("pending", true)):
		var how: String = _tr("HUD_CARE_SEQUENCE_ON_FOOT") % keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK")) \
			if bool(state.get("on_foot", false)) else _tr("HUD_CARE_SEQUENCE_SEATED")
		# The bomb's code is on the driver's dashboard, not on this card.
		if StringName(sequence.get("reader", &"owner")) == &"driver":
			var ask: String = _tr("HUD_CARE_ASK_CODE_DETAIL")
			if bool(state.get("on_foot", false)):
				ask += " " + _tr("HUD_CARE_ASK_CODE_ON_FOOT") % keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK"))
			return _step(&"sequence", _tr("HUD_CARE_ASK_CODE"), ask)
		return _step(&"sequence", _tr("HUD_CARE_SEQUENCE"),
			_tr("HUD_CARE_SEQUENCE_DETAIL") % [_tr(String(sequence.get("verb", "HUD_CARE_VERB_SOLVE"))), how])
	var cushion: Dictionary = state.get("cushion", {})
	if float(cushion.get("eta", -1.0)) >= 0.0 and bool(cushion.get("ready", false)):
		return _step(&"cushion", _tr("HUD_CARE_CUSHION"),
			_tr("HUD_CARE_CUSHION_DETAIL") % keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK")))
	var urgent: bool = phase in [&"crisis", &"lost"] or bool(state.get("restore", false))
	if tool != &"" and (urgent or working):
		return _step(&"tool", _tr("HUD_CARE_TOOL") % tool_name.to_upper(),
			_tr("HUD_CARE_TOOL_DETAIL") % keys.get("tool", _tr("HUD_CARE_KEY_RIGHT_CLICK")))
	if phase == &"lost":
		return _step(&"lost", _tr("HUD_CARE_LOST"), hint if not hint.is_empty() else _tr("HUD_CARE_LOST_DETAIL"))
	if action == &"release":
		return _step(&"release", _tr("HUD_CARE_RELEASE"), _tr("HUD_CARE_RELEASE_DETAIL"))
	# Hands are asked for when the box needs them -- at risk, strained or
	# being thrown about -- not all the time: a card that always says "hold"
	# never lets the player know they're done (playtest 2026-09-28).
	# The two traps that answer to a movement (N-117): Balance leans against the
	# tilt with the primary held, Liquid scrubs side to side with nothing held.
	if action == &"lean" and bool(state.get("need_hands", true)):
		return _step(&"lean", _tr("HUD_CARE_LEAN"),
			_tr("HUD_CARE_LEAN_DETAIL") % [keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK")), keys.get("sides", "WASD")])
	if action == &"scrub" and bool(state.get("need_hands", true)):
		var scrub: String = _tr("HUD_CARE_SCRUB_DETAIL") % keys.get("swing", "A / D")
		if bool(state.get("on_foot", false)):
			scrub += " " + _tr("HUD_CARE_ASK_CODE_ON_FOOT") % keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK"))
		return _step(&"scrub", _tr("HUD_CARE_SCRUB"), scrub)
	if action == &"hold" and bool(state.get("need_hands", true)):
		return _step(&"hold", _tr(String(HOLD_TITLES.get(kind, "HUD_CARE_TITLE_HOLD"))),
			_tr("HUD_CARE_HOLD_DETAIL") % keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK")))
	return _step(&"idle", _tr("HUD_CARE_IDLE"), hint if not hint.is_empty()
		else _tr("HUD_CARE_IDLE_DETAIL") % keys.get("primary", _tr("HUD_CARE_KEY_LEFT_CLICK")))


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)


static func _step(step: StringName, title: String, detail: String) -> Dictionary:
	return {"step": step, "title": title, "detail": detail}
