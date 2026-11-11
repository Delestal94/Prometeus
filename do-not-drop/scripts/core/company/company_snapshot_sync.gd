class_name CompanySnapshotSync
extends RefCounted
## The bookkeeping of CompanyNet's snapshot on its way (D-2004, section 3 of
## docs/expansion-distritos/diseno/red-autoridad.md; out of company_net.gd in D-0254).
##
## Host: which peer may have a snapshot now (one request let through per peer every
## CompanyNet.SNAPSHOT_INTERVAL_MSEC: may_grant(), granted()), the number each snapshot goes out with and its
## chunks (pack()). Client: when to ask again while it waits (ask_due()) and the chunks of the snapshot being
## put together (take_chunk()).
##
## No RPC, no signal and no business state here: CompanyNet holds one (CompanyNet.sync), sends the chunks
## (_snapshot), holds the events while this peer waits and applies what take_chunk() gives back
## (apply_snapshot()). CompanySnapshot packs, unpacks and checks the bytes.

## Client: called on the first chunk of a newer snapshot, before that chunk is kept: CompanyNet starts holding
## events (its _start_waiting()).
var started: Callable = Callable()
## Client: when it last asked for a snapshot (msec), -1 for never.
var asked_msec: int = -1

## Host: {peer: msec} of the last snapshot request let through, per peer.
var _granted: Dictionary = {}
## Host: {peer: true} once a snapshot too big to send was reported for it (one error per peer).
var _oversize_reported: Dictionary = {}
## Host: id of the last snapshot sent. Each one takes the next, so a peer can tell an older
## snapshot's chunks apart.
var _id: int = 0
## Client: the newest snapshot id seen and, while that one is put together, its chunk count,
## size uncompressed and {chunk index: bytes}. _rx_total is 0 once it is done or thrown away.
var _rx_id: int = 0
var _rx_total: int = 0
var _rx_size: int = 0
var _rx_chunks: Dictionary = {}


## Host: a snapshot request from `peer` at `now_msec` may go through: none did less than
## CompanyNet.SNAPSHOT_INTERVAL_MSEC before (a broken client asks once per event).
func may_grant(peer: int, now_msec: int) -> bool:
	var last: int = int(_granted.get(peer, -1))
	return last < 0 or now_msec - last >= CompanyNet.SNAPSHOT_INTERVAL_MSEC


## Host: `peer`'s request went through at `now_msec` (its snapshot was sent).
func granted(peer: int, now_msec: int) -> void:
	_granted[peer] = now_msec


## Host: `data` (CompanyNet.snapshot()) for `peer` as {id, size, chunks}: the next snapshot number, its size
## uncompressed and its chunks of at most `chunk_bytes` (CompanySnapshot.pack()). {} when it is over
## CompanyNet.SNAPSHOT_MAX_BYTES or SNAPSHOT_MAX_CHUNKS: an error, once per peer until one fits.
func pack(peer: int, data: Dictionary, chunk_bytes: int) -> Dictionary:
	var packed: Dictionary = CompanySnapshot.pack(data, chunk_bytes)
	if packed.is_empty():
		if not _oversize_reported.has(peer):
			_oversize_reported[peer] = true
			push_error("CompanyNet: the snapshot for peer %d is over %d bytes or %d chunks; not sent"
				% [peer, CompanyNet.SNAPSHOT_MAX_BYTES, CompanyNet.SNAPSHOT_MAX_CHUNKS])
		return {}
	_oversize_reported.erase(peer)
	_id += 1
	packed["id"] = _id
	return packed


## Host: `peer` disconnected; its rate limit and its oversize report go.
func forget(peer: int) -> void:
	_granted.erase(peer)
	_oversize_reported.erase(peer)


## Client: CompanyNet.SNAPSHOT_INTERVAL_MSEC passed since it last asked (or it never did), so it asks now:
## true, and `now_msec` is kept as the last time. False while the wait is on.
func ask_due(now_msec: int) -> bool:
	if asked_msec >= 0 and now_msec - asked_msec < CompanyNet.SNAPSHOT_INTERVAL_MSEC:
		return false
	asked_msec = now_msec
	return true


## Client: keeps one chunk (checked first, rule 5: ids and counts in range, at most SNAPSHOT_CHUNK_BYTES, the
## same total and size as the rest of its snapshot). The first chunk of a newer snapshot drops what was kept of
## the one before, tells CompanyNet (`started`) and restarts the wait before asking again. A repeated chunk, or
## one of an older or finished snapshot, changes nothing. Null until the last one is in; then the snapshot they
## make once joined, {} when they don't unpack (CompanySnapshot.unpack()).
func take_chunk(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray) -> Variant:
	if not CompanySnapshot.chunk_ok(id, chunk, total, size, bytes) or id < _rx_id:
		return null
	if id > _rx_id:
		_rx_id = id
		_rx_total = total
		_rx_size = size
		_rx_chunks = {}
		if started.is_valid():
			started.call()
		asked_msec = Time.get_ticks_msec()
	elif _rx_total == 0 or total != _rx_total or size != _rx_size or _rx_chunks.has(chunk):
		return null
	_rx_chunks[chunk] = bytes
	if _rx_chunks.size() < _rx_total:
		return null
	var joined: PackedByteArray = CompanySnapshot.join(_rx_chunks, _rx_total)
	_rx_total = 0
	_rx_chunks = {}
	return CompanySnapshot.unpack(joined, _rx_size)
