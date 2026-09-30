class_name LocText
extends RefCounted
## A line of text that the host builds and another peer shows: it travels as
## [key, args...] and whoever draws it translates it, so a client in English
## doesn't read the host's Spanish (N-805). An argument that is itself an
## Array is another such line (a tool's name inside a progress line); a key
## with no translation passes through as is, so a plain format ("%s · %d%%")
## can stand in for a key.


static func make(key: String, args: Array = []) -> Array:
	return [key] + args


## The line in this peer's language; "" for an empty line. A String is
## returned as it is (already built for this peer).
static func render(text: Variant) -> String:
	if text is String or text is StringName:
		return String(text)
	if not text is Array or (text as Array).is_empty():
		return ""
	var parts: Array = text
	var line: String = String(TranslationServer.translate(StringName(str(parts[0]))))
	if parts.size() == 1:
		return line
	var args: Array = []
	for arg: Variant in parts.slice(1):
		args.append(render(arg) if arg is Array else arg)
	# A key this build doesn't know (a newer host) comes back as the key:
	# show it with its values rather than fail the format every frame.
	if not line.contains("%"):
		return " ".join([line] + args.map(func(arg: Variant) -> String: return str(arg)))
	return line % args
