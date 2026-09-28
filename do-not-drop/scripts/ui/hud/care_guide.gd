extends RefCounted
## "What now?" for the box in your hands or at your seat (playtest
## 2026-09-28: "I don't know whether to pick it up or what to do"). One step,
## the most urgent first, read from the replicated care state (PackageCare's
## snapshot plus the trap's action, hint and tap sequence that
## PackageRescue.publish_care() adds), so every peer tells the same story:
##   collect  -- a rescue with pieces on the floor: go and pick them up
##   sequence -- a tap sequence pending (the bomb, Peso creciente)
##   tool     -- a rescue that needs the kit, or a job already under way
##   release  -- the creature says hands off
##   hold     -- keep the primary action held: steady, calm, mop (only
##               while `need_hands` says the box needs it)
##   idle     -- nothing to do right now: you can let go
##   lost     -- nothing left to save
## Pure data in, pure data out: CareCard draws it.

## What holding does, per content, as the card's headline.
const HOLD_TITLES: Dictionary = {&"fragile": "SOSTENELA", &"balance": "ENDEREZALA",
	&"liquid": "SECÁ EL DERRAME", &"noisy": "CALMALA", &"hostile": "CALMALA",
	&"growing_weight": "SOSTENELA", &"explosive": "SOSTENELA"}


## `keys` names the controls as the player's device calls them:
## {primary, tool, interact}. `tool` is the tool the card offers (&"" for
## none) and `tool_name` what to call it.
static func next_step(state: Dictionary, kind: StringName, tool: StringName, tool_name: String,
		keys: Dictionary) -> Dictionary:
	var phase := StringName(state.get("phase", &"intact"))
	var missing: int = int(state.get("missing", 0))
	var sequence: Dictionary = state.get("sequence", {})
	var action := StringName(state.get("action", &"hold"))
	var hint: String = String(state.get("hint", ""))
	var working: bool = float(state.get("work", 0.0)) > 0.0 and StringName(state.get("tool", &"")) == tool
	if phase == &"crisis" and missing > 0:
		return _step(&"collect", "JUNTÁ LAS PIEZAS",
			"Quedan %d en el piso: acercate a cada una y apretá %s." % [missing, keys.get("interact", "E")])
	var steps: Array = sequence.get("steps", [])
	if int(sequence.get("index", 0)) < steps.size() and bool(sequence.get("pending", true)):
		var how: String = "mantené %s y tocá una tecla por vez" % keys.get("primary", "Clic izq.") \
			if bool(state.get("on_foot", false)) else "una tecla por vez, sin clic"
		return _step(&"sequence", "TOCÁ EN ORDEN",
			"%s: %s. Si le errás, vuelve a empezar." % [String(sequence.get("verb", "Resolver")), how])
	var urgent: bool = phase in [&"crisis", &"lost"] or bool(state.get("restore", false))
	if tool != &"" and (urgent or working):
		return _step(&"tool", "USÁ: %s" % tool_name.to_upper(),
			"Mantené %s hasta llenar el círculo." % keys.get("tool", "Clic der."))
	if phase == &"lost":
		return _step(&"lost", "CONTENIDO PERDIDO", hint if not hint.is_empty() else "Ya no se puede recuperar.")
	if action == &"release":
		return _step(&"release", "¡SOLTALA!", "No toques la caja hasta que vuelva a pedir calma.")
	# Hands are asked for when the box needs them -- at risk, strained or
	# being thrown about -- not all the time: a card that always says "hold"
	# never lets the player know they're done (playtest 2026-09-28).
	if action == &"hold" and bool(state.get("need_hands", true)):
		return _step(&"hold", String(HOLD_TITLES.get(kind, "SOSTENELA")),
			"Mantené %s: la protege de golpes y curvas." % keys.get("primary", "Clic izq."))
	return _step(&"idle", "TODO EN ORDEN", hint if not hint.is_empty()
		else "Podés soltar. Mantené %s si se sacude o se pone en riesgo." % keys.get("primary", "Clic izq."))


static func _step(step: StringName, title: String, detail: String) -> Dictionary:
	return {"step": step, "title": title, "detail": detail}
