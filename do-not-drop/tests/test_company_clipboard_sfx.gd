extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_clipboard_sfx.gd
##
## The clipboard's sounds (expansion D-1913, diseno/portapapeles.md §6), synthesized in SynthAudio:
## - clipboard_clip_up, clipboard_clip_down and clipboard_sheet are short 16-bit one-shots (under 0.2 s, no
##   loop), never clipped, built once and shared; the clip taken out and put away are different sounds;
## - CompanyClipboard plays them on its own player on the SFX bus: the clip on raise() and on stow(), the sheet
##   when the sheet showing changes (turn(), a tab clicked, raise() on another sheet while raised), and not when
##   it opens on a sheet or is asked for the one already showing.
## A bare clipboard with two plain sheets and a stand-in player: no company world.

var _failures: int = 0


class FakePlayer:
	extends Node
	var carried_package: Node = null
	var tended_package: Node = null
	var seat_node_path: NodePath = NodePath()
	var _ragdolled: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_streams()
	await _test_cues()
	if _failures == 0:
		print("PASS: the clipboard snaps its clip out and away and swishes a sheet on every turn")
	quit(_failures)


func _test_streams() -> void:
	var streams: Dictionary = {
		"clip_up": SynthAudio.clipboard_clip_up(),
		"clip_down": SynthAudio.clipboard_clip_down(),
		"sheet": SynthAudio.clipboard_sheet(),
	}
	for cue: String in streams:
		var stream: AudioStreamWAV = streams[cue]
		_expect(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,
			"%s is a 16-bit mono stream" % cue)
		if stream == null:
			continue
		var seconds: float = stream.data.size() / 2.0 / stream.mix_rate
		_expect(seconds > 0.05 and seconds < 0.2, "%s is short (%.2f s)" % [cue, seconds])
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s does not loop" % cue)
		var peak: int = 0
		for index: int in range(0, stream.data.size() - 1, 2):
			peak = maxi(peak, absi(stream.data.decode_s16(index)))
		_expect(peak > 3000 and peak < 32767, "%s is heard and not clipped (peak %d)" % [cue, peak])
	_expect(SynthAudio.clipboard_clip_up() == streams["clip_up"], "the clip is built once and shared")
	_expect(streams["clip_up"].data != streams["clip_down"].data, "taking it out and putting it away sound apart")


func _test_cues() -> void:
	var player := FakePlayer.new()
	root.add_child(player)
	player.set_process_unhandled_input(true)
	var clip := CompanyClipboard.new()
	clip.player_of = func() -> Node: return player
	clip.peer_id = func() -> int: return 1
	root.add_child(clip)
	await process_frame
	clip.frame.add_sheet(CompanyClipboard.SHEET_STOCK, "Stock", Control.new())
	clip.frame.add_sheet(CompanyClipboard.SHEET_SUPPLIER, "Supplier", Control.new())
	var sfx := clip.get_node_or_null(^"ClipboardSfx") as AudioStreamPlayer
	_expect(sfx != null and sfx.bus == &"SFX", "the clipboard plays on the SFX bus")
	_expect(clip.raise(), "it comes out with free hands")
	_expect(clip.last_cue == CompanyClipboard.CUE_UP and sfx.stream == SynthAudio.clipboard_clip_up(),
		"raising it snaps the clip, not a sheet (got %s)" % clip.last_cue)
	clip.turn(1)
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_SUPPLIER, "E turns to the Supplier sheet")
	_expect(clip.last_cue == CompanyClipboard.CUE_SHEET and sfx.stream == SynthAudio.clipboard_sheet(),
		"turning a sheet swishes it")
	clip.last_cue = &""
	clip.show_sheet(CompanyClipboard.SHEET_SUPPLIER)
	_expect(clip.last_cue == &"", "asking for the sheet already showing is silent")
	clip.frame.sheet_picked.emit(CompanyClipboard.SHEET_STOCK)
	_expect(clip.last_cue == CompanyClipboard.CUE_SHEET, "a tab clicked swishes the sheet")
	clip.last_cue = &""
	clip.raise(CompanyClipboard.SHEET_SUPPLIER)
	_expect(clip.last_cue == CompanyClipboard.CUE_SHEET, "the supplier board's shortcut while raised turns the sheet")
	clip.stow()
	_expect(clip.last_cue == CompanyClipboard.CUE_DOWN and sfx.stream == SynthAudio.clipboard_clip_down(),
		"putting it away snaps the clip")
	clip.last_cue = &""
	clip.stow()
	_expect(clip.last_cue == &"", "stowing it again is silent")
	_expect(clip.raise() and clip.last_cue == CompanyClipboard.CUE_UP, "it comes out again on the remembered sheet")
	clip.stow()
	clip.queue_free()
	player.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
