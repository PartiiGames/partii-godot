class_name PartiiNet
## The netcode rule, ready to use (both backends): the host runs the world; clients send inputs, the
## host sends snapshots; every packet is unreliable and byte-packed; the newest state wins.
##
## Clients → host, PartiiNet.Inputs: each packet repeats the last few inputs (redundancy instead of
## resends), so a lost packet costs nothing while the next one arrives.
##   var inputs := PartiiNet.Inputs.new()
##   Partii.send(Partii.room().host, inputs.pack(my_input_bytes))      # client, every tick
##   for b in inputs.unpack(from, bytes): apply(from, b)               # host, on Partii.message
##
## Host → clients, PartiiNet.Snapshots: a sequence number per snapshot; older or repeated ones are dropped.
##   var snaps := PartiiNet.Snapshots.new()
##   Partii.send(Partii.BROADCAST, snaps.pack(world_bytes))            # host, every tick
##   var w := snaps.unpack(from, bytes); if not w.is_empty(): show(w)  # client
##
## Packets are tagged (one byte), so one message handler can route both: PartiiNet.kind(bytes).
## Keep each packet under PartiiNet.MAX_PACKET (1199 bytes); split big worlds.

const MAX_PACKET := 1199
const KIND_INPUTS := 0x49   # "I"
const KIND_SNAPSHOT := 0x53 # "S"

## The packet's kind (KIND_INPUTS, KIND_SNAPSHOT) or -1.
static func kind(bytes: PackedByteArray) -> int:
	return bytes[0] if bytes.size() > 0 else -1


class Inputs:
	extends RefCounted
	## How many recent inputs each packet repeats.
	var redundancy := 4
	var _seq := 0
	var _recent: Array[PackedByteArray] = []
	var _last := {} # sender mid → the newest input seq applied

	## A packet with this input and the last few before it: [kind][seq u32][n u8]([len u16][bytes])*, newest first.
	func pack(input: PackedByteArray) -> PackedByteArray:
		_seq += 1
		_recent.push_front(input)
		if _recent.size() > redundancy:
			_recent.resize(redundancy)
		var b := StreamPeerBuffer.new()
		b.big_endian = true
		b.put_u8(PartiiNet.KIND_INPUTS)
		b.put_u32(_seq)
		b.put_u8(_recent.size())
		for i in _recent:
			b.put_u16(i.size())
			b.put_data(i)
		return b.data_array

	## The inputs from this sender not seen before, oldest first (none when the packet is stale).
	func unpack(from: int, bytes: PackedByteArray) -> Array[PackedByteArray]:
		var out: Array[PackedByteArray] = []
		if bytes.size() < 6 or bytes[0] != PartiiNet.KIND_INPUTS:
			return out
		var b := StreamPeerBuffer.new()
		b.big_endian = true
		b.data_array = bytes
		b.seek(1)
		var seq := b.get_u32()
		var n := b.get_u8()
		var last := int(_last.get(from, 0))
		var got: Array[PackedByteArray] = []
		for i in n:
			if b.get_available_bytes() < 2:
				break
			var size := b.get_u16()
			var r := b.get_data(size)
			if r[0] != OK:
				break
			got.append(PackedByteArray(r[1]))
		# got[0] is seq, got[1] is seq - 1, ...
		for i in range(got.size() - 1, -1, -1):
			if seq - i > last:
				out.append(got[i])
		if seq > last:
			_last[from] = seq
		return out

	## Forget a sender (it left).
	func forget(from: int) -> void:
		_last.erase(from)


class Snapshots:
	extends RefCounted
	var _seq := 0
	var _newest := {} # sender mid → the newest snapshot seq seen

	## [kind][seq u32][state bytes]
	func pack(state: PackedByteArray) -> PackedByteArray:
		_seq += 1
		var b := StreamPeerBuffer.new()
		b.big_endian = true
		b.put_u8(PartiiNet.KIND_SNAPSHOT)
		b.put_u32(_seq)
		b.put_data(state)
		return b.data_array

	## The state when it's newer than any before from this sender; empty when it's old (drop it).
	func unpack(from: int, bytes: PackedByteArray) -> PackedByteArray:
		if bytes.size() < 5 or bytes[0] != PartiiNet.KIND_SNAPSHOT:
			return PackedByteArray()
		var seq := (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4]
		if seq <= int(_newest.get(from, 0)):
			return PackedByteArray()
		_newest[from] = seq
		return bytes.slice(5)

	## The seq of the newest snapshot taken from this sender (0: none yet).
	func newest(from: int) -> int:
		return int(_newest.get(from, 0))
