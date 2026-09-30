extends RefCounted
## Sounds of the traps' own actions that came after synth_audio.gd filled up
## (its file-length limit): same recipe as its trap cues, cached here.

const RATE: int = 22050
static var _cache: Dictionary = {}


## Fragile's "Amortiguá" landing (N-117): a short, soft thump that drops in
## pitch, the bump taken in a cushion instead of a chime of glass. Simple
## enough to leave as is; disenador-audio can retune it.
static func cushion_pad() -> AudioStreamWAV:
	if not _cache.has(&"cushion_pad"):
		_cache[&"cushion_pad"] = _make_cushion_pad()
	return _cache[&"cushion_pad"]


static func _make_cushion_pad() -> AudioStreamWAV:
	const DURATION: float = 0.16
	var data := PackedByteArray()
	var count: int = int(RATE * DURATION)
	data.resize(count * 2)
	for i: int in count:
		var t: float = float(i) / RATE
		var sample: float = sin(TAU * (170.0 - t * 300.0) * t) * exp(-t * 30.0)
		data.encode_s16(i * 2, roundi(sample * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
