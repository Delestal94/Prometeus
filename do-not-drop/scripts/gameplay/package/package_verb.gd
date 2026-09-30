class_name PackageVerb
extends RefCounted
## The verb over each box (N-117): what its crew has to do about it, written in
## the world so nobody needs the HUD card to play the trap. Worked out from what
## every peer has -- the replicated trap state and the care state the host
## publishes -- never from the host-only behavior, and empty while the box asks
## nothing, so the world stays clean. PackageFeedback draws it.
##
##   Fragile        Amortiguá  -- a bump is close and a tap would count
##   Balance        Contrapesá -- the box is at risk
##   Liquid         Fregá      -- the box is at risk
##   Noisy          Abrazalo   -- the box is at risk
##   Hostile        Leelo      -- its mood: ">:(" the moment it is angry (a hold
##                                is an attack), ":)" once it is at risk; the
##                                shapes differ, not only the colour
##   Growing weight Asegurá    -- the arrows still to tap, while asked for
##   Explosive      Pedí el código -- has its own sign (ExplosiveCountdown)

const ARROWS: Dictionary = {&"up": "↑", &"down": "↓", &"left": "←", &"right": "→"}
const YELLOW := Color("ffd25a")
const ANGRY := Color("ff6b5b")
const CALM := Color("8fe3a5")


## {text, color} for a box of `trap_id` in `state` (ITrapBehavior.TrapState)
## with the host's `care` state, or {} when it asks nothing.
static func ask(trap_id: StringName, state: int, care: Dictionary, run_active: bool) -> Dictionary:
	var out: Dictionary = {}
	if state != ITrapBehavior.TrapState.RUINED and run_active \
			and StringName(care.get("phase", &"intact")) == &"intact":
		var risky: bool = state >= ITrapBehavior.TrapState.AT_RISK
		var text: String = ""
		var color: Color = YELLOW
		match trap_id:
			&"fragile":
				var cushion: Dictionary = care.get("cushion", {})
				if float(cushion.get("eta", -1.0)) >= 0.0 and bool(cushion.get("ready", false)):
					text = TranslationServer.translate("HUD_VERB_FRAGILE")
			&"balance":
				text = TranslationServer.translate("HUD_VERB_BALANCE") if risky else ""
			&"liquid":
				text = TranslationServer.translate("HUD_VERB_LIQUID") if risky else ""
			&"noisy":
				text = TranslationServer.translate("HUD_VERB_NOISY") if risky else ""
			&"hostile":
				if StringName(care.get("action", &"")) == &"release":
					text = TranslationServer.translate("HUD_VERB_HOSTILE_ANGRY")
					color = ANGRY
				elif risky:
					text = TranslationServer.translate("HUD_VERB_HOSTILE_CALM")
					color = CALM
			&"growing_weight":
				text = _weight_text(care.get("sequence", {}))
		if not text.is_empty():
			out = {"text": text, "color": color}
	return out


## "¡ASEGURÁ! ↑ ← ↓" with the steps still to tap, or "" when none is asked for.
static func _weight_text(sequence: Dictionary) -> String:
	var steps: Array = sequence.get("steps", [])
	var index: int = int(sequence.get("index", 0))
	var text: String = ""
	if not steps.is_empty() and index < steps.size() and bool(sequence.get("pending", true)):
		var arrows: PackedStringArray = []
		for step: int in range(index, steps.size()):
			arrows.append(String(ARROWS.get(StringName(steps[step]), "?")))
		text = TranslationServer.translate("HUD_VERB_WEIGHT") % " ".join(arrows)
	return text
