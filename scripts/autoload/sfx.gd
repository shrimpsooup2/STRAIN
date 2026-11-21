extends Node
## Sfx — every sound in STRAIN is synthesised here; nothing is loaded from disk.
##   Sfx.play(id, pitch := 1.0, vol_db := 0.0)   one-shot from a polyphonic pool
##   Sfx.drone(region)                            looping ambience, crossfaded; "" stops
##   Sfx.heartbeat(rate)                          0 = off; < 10 = beats per second, >= 10 = BPM
## Short sounds are generated lazily (and pre-warmed on a worker thread at boot);
## drones are generated on a worker thread the first time they are asked for.
## Format: AudioStreamWAV, 16-bit mono, 22050 Hz.

const RATE := 22050
const MASTER_DB := -8.0
const DRONE_DB := -10.0
const HEART_DB := -3.0
const POOL := 12
const DRONE_LEN := 4.0
const DRONE_XF := 0.3
const FADE_SEC := 1.6

const SIN := 0
const TRI := 1
const SQR := 2
const SAW := 3

## Most-used first: the warm-up thread works down this list.
const NAMES := [
	"type", "blip", "select", "confirm", "cancel", "error", "step", "door", "pickup", "page",
	"express", "clean", "link", "skip", "splice", "tick", "mutate",
	"hit_s", "hit_m", "hit_l", "film", "heal", "chorus", "rot", "mark", "gnaw", "knot",
	"windup", "break", "stagger", "enemy_die", "hurt",
	"win", "lose", "reward", "adapt", "map_step", "shop", "event", "rest",
	"power_on", "thud", "whisper", "glitch",
	"inject", "plunger", "vein", "resonance", "shift", "pour", "bubble", "vial", "needle",
	"heart",
]
const DRONES := ["wound", "rivers", "hollow", "archive", "root", "lab", "dream", "title"]

var _known := {}
var _warned := {}
var _cache := {}             ## id -> AudioStreamWAV
var _drone_cache := {}       ## region -> AudioStreamWAV
var _last := {}              ## id -> msec of last play (spam guard)
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var _quitting := false

var _players: Array[AudioStreamPlayer] = []
var _next := 0

var _drone_a: AudioStreamPlayer
var _drone_b: AudioStreamPlayer
var _drone_player: AudioStreamPlayer = null
var _drone_cur := ""
var _drone_want := ""
var _drone_pending := {}
var _fade_tw := {}           ## player instance id -> Tween

var _hb_player: AudioStreamPlayer
var _hb_rate := 0.0
var _hb_next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in NAMES:
		_known[id] = true
	for i in POOL:
		_players.append(_new_player())
	_drone_a = _new_player()
	_drone_b = _new_player()
	_hb_player = _new_player()
	_tasks.append(WorkerThreadPool.add_task(_warm, true, "Sfx warm-up"))


func _new_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = MASTER_DB
	add_child(p)
	return p


func _exit_tree() -> void:
	_quitting = true
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


# ------------------------------------------------------------------ public

## True if `id` is a sound this autoload can make.
func has_sound(id: String) -> bool:
	return _known.has(id)


## One-shot. Unknown ids are a silent no-op (warned once).
func play(id: String, pitch := 1.0, vol_db := 0.0) -> void:
	if not _known.has(id):
		if not _warned.has(id):
			_warned[id] = true
			push_warning("Sfx: unknown sound '%s'" % id)
		return
	var now := Time.get_ticks_msec()
	var last: int = _last.get(id, -100000)
	if now - last < 18:
		return
	_last[id] = now
	var s := _get_stream(id)
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.pitch_scale = clampf(pitch, 0.05, 8.0)
	p.volume_db = MASTER_DB + vol_db
	p.play()


## Looping regional ambience. "" fades the current drone out. Same region = no-op.
func drone(region: String) -> void:
	if region == _drone_want:
		return
	_drone_want = region
	if region == "" or not region in DRONES:
		if region != "" and not _warned.has("drone:" + region):
			_warned["drone:" + region] = true
			push_warning("Sfx: unknown drone '%s'" % region)
		_stop_drone()
		return
	_mutex.lock()
	var s: AudioStreamWAV = _drone_cache.get(region)
	_mutex.unlock()
	if s != null:
		_start_drone(region, s)
	elif not _drone_pending.has(region):
		_drone_pending[region] = true
		_tasks.append(WorkerThreadPool.add_task(_drone_task.bind(region), true, "Sfx drone"))


## Name of the drone currently playing (or fading in), "" if none.
func current_drone() -> String:
	return _drone_cur


## Heartbeat pulse under everything. rate <= 0 stops it. rate < 10 is beats per
## second (1.0 = 60 BPM); rate >= 10 is read as BPM. Louder and higher as it speeds up.
func heartbeat(rate: float) -> void:
	_hb_rate = maxf(rate, 0.0)
	if _hb_rate <= 0.0:
		_hb_next = 0
	elif _hb_next == 0:
		_hb_next = Time.get_ticks_msec() + 60


func stop_all() -> void:
	for p in _players:
		p.stop()
	heartbeat(0.0)
	drone("")


# ------------------------------------------------------------------ playback

func _free_player() -> AudioStreamPlayer:
	for k in POOL:
		var i := (_next + k) % POOL
		if not _players[i].playing:
			_next = (i + 1) % POOL
			return _players[i]
	var p := _players[_next]
	_next = (_next + 1) % POOL
	return p


func _get_stream(id: String) -> AudioStreamWAV:
	_mutex.lock()
	var s: AudioStreamWAV = _cache.get(id)
	_mutex.unlock()
	if s == null:
		s = _make(id)
		_mutex.lock()
		_cache[id] = s
		_mutex.unlock()
	return s


func _warm() -> void:
	for i in NAMES.size():
		if _quitting:
			return
		var id: String = NAMES[i]
		_mutex.lock()
		var have := _cache.has(id)
		_mutex.unlock()
		if not have:
			_get_stream(id)


func _drone_task(region: String) -> void:
	var s := _make_drone(region)
	_mutex.lock()
	_drone_cache[region] = s
	_mutex.unlock()
	call_deferred("_drone_ready", region)


func _drone_ready(region: String) -> void:
	_drone_pending.erase(region)
	_reap()
	if region != _drone_want:
		return
	_mutex.lock()
	var s: AudioStreamWAV = _drone_cache.get(region)
	_mutex.unlock()
	if s != null:
		_start_drone(region, s)


func _reap() -> void:
	for t in _tasks.duplicate():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_tasks.erase(t)


func _start_drone(region: String, s: AudioStreamWAV) -> void:
	if region == _drone_cur and _drone_player != null and _drone_player.playing:
		return
	var old := _drone_player
	var p := _drone_b if old == _drone_a else _drone_a
	_kill_fade(p)
	p.stream = s
	_set_drone_vol(0.0, p)
	p.play(randf() * DRONE_LEN * 0.5)
	_drone_player = p
	_drone_cur = region
	_fade(p, true)
	if old != null:
		_fade(old, false)


func _stop_drone() -> void:
	if _drone_player != null:
		_fade(_drone_player, false)
	_drone_player = null
	_drone_cur = ""


func _kill_fade(p: AudioStreamPlayer) -> void:
	var key := p.get_instance_id()
	var old_tw: Tween = _fade_tw.get(key)
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	_fade_tw.erase(key)


func _fade(p: AudioStreamPlayer, fade_in: bool) -> void:
	_kill_fade(p)
	var from := clampf(db_to_linear(p.volume_db - MASTER_DB - DRONE_DB), 0.0, 1.0)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_set_drone_vol.bind(p), from, 1.0 if fade_in else 0.0, FADE_SEC)
	if not fade_in:
		tw.tween_callback(p.stop)
	_fade_tw[p.get_instance_id()] = tw


func _set_drone_vol(x: float, p: AudioStreamPlayer) -> void:
	p.volume_db = MASTER_DB + DRONE_DB + linear_to_db(maxf(x, 0.001))


func _process(_dt: float) -> void:
	if _hb_rate <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now < _hb_next:
		return
	var bps := _hb_rate if _hb_rate < 10.0 else _hb_rate / 60.0
	bps = clampf(bps, 0.3, 4.0)
	_hb_next = now + int(1000.0 / bps)
	var s := _get_stream("heart")
	if s == null:
		return
	_hb_player.stream = s
	_hb_player.pitch_scale = 1.0 + clampf(bps - 1.0, -0.4, 2.0) * 0.08
	_hb_player.volume_db = MASTER_DB + HEART_DB + clampf((bps - 1.0) * 2.0, -4.0, 4.0)
	_hb_player.play()


# ------------------------------------------------------------------ synthesis primitives
# All primitives mix into a PackedFloat32Array; they touch no shared state, so the
# worker thread can run them. Noise uses a local LCG instead of a shared RNG.

func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	b.fill(0.0)
	return b


## Oscillator with exponential pitch sweep f0 -> f1, linear attack, exponential decay.
func _tone(b: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, amp: float,
		wave := SIN, atk := 0.004, dec := 6.0, vib := 0.0, vib_f := 6.0) -> void:
	var s0 := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	if n <= 0 or f0 <= 0.0:
		return
	var inv := 1.0 / RATE
	var ratio := f1 / f0
	var sweep := absf(f1 - f0) > 0.01
	var ph := 0.0
	for i in n:
		var t := i * inv
		var f := f0
		if sweep:
			f = f0 * pow(ratio, t / dur)
		if vib != 0.0:
			f *= 1.0 + vib * sin(TAU * vib_f * t)
		ph += f * inv
		ph -= floorf(ph)
		var v := 0.0
		match wave:
			SIN:
				v = sin(TAU * ph)
			TRI:
				v = 4.0 * absf(ph - 0.5) - 1.0
			SQR:
				v = 1.0 if ph < 0.5 else -1.0
			_:
				v = 2.0 * ph - 1.0
		var env := minf(1.0, t / atk) * exp(-t * dec) * minf(1.0, (dur - t) * 150.0)
		b[s0 + i] += v * amp * env


## Filtered noise. Cutoff sweeps fc0 -> fc1. band = crude band-pass (lp minus a lower lp).
func _noise(b: PackedFloat32Array, t0: float, dur: float, amp: float, fc0: float, fc1: float,
		atk := 0.003, dec := 8.0, band := false, seed_v := 1) -> void:
	var s0 := int(t0 * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	if n <= 0:
		return
	var inv := 1.0 / RATE
	var st := (seed_v * 7919 + 104729) & 0x7fffffff
	var lp := 0.0
	var lp2 := 0.0
	var ratio := fc1 / fc0
	for i in n:
		var t := i * inv
		var fc := fc0 * pow(ratio, t / dur)
		var a := 1.0 - exp(-TAU * fc * inv)
		st = (st * 1103515245 + 12345) & 0x7fffffff
		var x := float(st) / 1073741824.0 - 1.0
		lp += a * (x - lp)
		var v := lp * sqrt((2.0 - a) / a) * 0.6
		if band:
			var a2 := a * 0.4
			lp2 += a2 * (lp - lp2)
			v = (lp - lp2) * sqrt((2.0 - a) / a) * 0.9
		var env := minf(1.0, t / atk) * exp(-t * dec) * minf(1.0, (dur - t) * 150.0)
		b[s0 + i] += v * amp * env


## Glass: inharmonic partials with faster-decaying highs.
func _chime(b: PackedFloat32Array, t0: float, f: float, amp: float, dec := 6.0) -> void:
	var d := minf(4.6 / dec, float(b.size()) / RATE - t0)
	if d <= 0.0:
		return
	var parts := [[1.0, 1.0, 1.0], [1.004, 0.4, 1.2], [2.76, 0.35, 2.0], [5.40, 0.15, 3.5], [8.93, 0.06, 5.0]]
	for pt in parts:
		var mul: float = pt[0]
		var a: float = pt[1]
		var dk: float = pt[2]
		if f * mul < 10000.0:
			_tone(b, t0, d / dk, f * mul, f * mul, amp * a, SIN, 0.001, dec * dk)


## A wet bubble: short sine with a rising chirp.
func _bubble(b: PackedFloat32Array, t0: float, f: float, amp: float) -> void:
	_tone(b, t0, 0.06, f, f * 2.4, amp, SIN, 0.002, 28.0)


## Steady sine for drones: optional tremolo and vibrato, no envelope.
func _hum(b: PackedFloat32Array, f: float, amp: float, trem_f := 0.0, trem_d := 0.0,
		vib := 0.0, vib_f := 0.25) -> void:
	var inv := 1.0 / RATE
	var ph := 0.0
	for i in b.size():
		var t := i * inv
		var ff := f
		if vib != 0.0:
			ff *= 1.0 + vib * sin(TAU * vib_f * t)
		ph += ff * inv
		ph -= floorf(ph)
		var g := 1.0
		if trem_d > 0.0:
			g = 1.0 - trem_d + trem_d * (0.5 + 0.5 * sin(TAU * trem_f * t))
		b[i] += sin(TAU * ph) * amp * g


## Steady noise bed for drones: cutoff wanders around fc, optional amplitude swell.
func _wind(b: PackedFloat32Array, amp: float, fc: float, fc_mod := 0.0, mod_f := 0.25,
		am_f := 0.0, am_d := 0.0, band := false, seed_v := 1) -> void:
	var inv := 1.0 / RATE
	var st := (seed_v * 7919 + 104729) & 0x7fffffff
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := i * inv
		var c := maxf(30.0, fc + fc_mod * sin(TAU * mod_f * t))
		var a := 1.0 - exp(-TAU * c * inv)
		st = (st * 1103515245 + 12345) & 0x7fffffff
		var x := float(st) / 1073741824.0 - 1.0
		lp += a * (x - lp)
		var v := lp * sqrt((2.0 - a) / a) * 0.6
		if band:
			lp2 += a * 0.4 * (lp - lp2)
			v = (lp - lp2) * sqrt((2.0 - a) / a) * 0.9
		var g := 1.0
		if am_d > 0.0:
			g = 1.0 - am_d + am_d * (0.5 - 0.5 * cos(TAU * am_f * t))
		b[i] += v * amp * g


func _wav(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var n := b.size()
	var edge := mini(44, n / 4)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v: float = b[i]
		if not loop:
			if i < edge:
				v *= float(i) / edge
			elif i >= n - edge:
				v *= float(n - 1 - i) / edge
		v = tanh(v * 1.1)
		bytes.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


# ------------------------------------------------------------------ recipes
# Palette: low wet squelches, glass chimes, filtered noise. Nothing bright for long.

func _make(id: String) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = hash(id)
	var b := PackedFloat32Array()
	match id:
		# --- UI / movement
		"blip":
			b = _buf(0.06)
			_tone(b, 0, 0.06, 900, 780, 0.25, TRI, 0.002, 35)
		"select":
			b = _buf(0.14)
			_tone(b, 0, 0.12, 660, 990, 0.2, TRI, 0.002, 20)
			_chime(b, 0.03, 1980, 0.07, 25)
		"confirm":
			b = _buf(0.45)
			_noise(b, 0, 0.03, 0.08, 4000, 3000, 0.001, 80, true, 2)
			_chime(b, 0, 1046.5, 0.2, 9)
			_chime(b, 0.055, 1568, 0.18, 8)
		"cancel":
			b = _buf(0.18)
			_tone(b, 0, 0.16, 520, 280, 0.22, TRI, 0.002, 14)
			_tone(b, 0, 0.1, 140, 90, 0.2, SIN, 0.002, 25)
		"error":
			b = _buf(0.3)
			_tone(b, 0, 0.11, 150, 140, 0.1, SQR, 0.002, 4)
			_tone(b, 0, 0.11, 158, 150, 0.08, SQR, 0.002, 4)
			_tone(b, 0.14, 0.15, 150, 120, 0.1, SQR, 0.002, 4)
			_tone(b, 0.14, 0.15, 158, 125, 0.08, SQR, 0.002, 4)
			_noise(b, 0, 0.3, 0.05, 600, 300, 0.005, 6, false, 3)
		"type":
			b = _buf(0.03)
			_noise(b, 0, 0.02, 0.2, 3500, 2500, 0.001, 120, true, 4)
			_tone(b, 0, 0.015, 1400, 1100, 0.08, SIN, 0.001, 120)
		"step":
			b = _buf(0.12)
			_noise(b, 0, 0.1, 0.3, 500, 150, 0.003, 30, false, 5)
			_tone(b, 0, 0.09, 95, 60, 0.25, SIN, 0.002, 30)
		"door":
			b = _buf(0.7)
			_tone(b, 0, 0.2, 120, 70, 0.3, SIN, 0.002, 15)
			_noise(b, 0, 0.03, 0.2, 2000, 1500, 0.001, 80, false, 6)
			_noise(b, 0.05, 0.6, 0.16, 1500, 300, 0.05, 4, true, 7)
			_tone(b, 0.1, 0.6, 55, 42, 0.25, SIN, 0.05, 5)
		"pickup":
			b = _buf(0.4)
			_bubble(b, 0, 400, 0.1)
			_chime(b, 0, 1318.5, 0.17, 10)
			_chime(b, 0.06, 1760, 0.15, 9)
		"page":
			b = _buf(0.25)
			_noise(b, 0, 0.22, 0.2, 3000, 1200, 0.03, 10, true, 8)
			_noise(b, 0.08, 0.12, 0.12, 4500, 2500, 0.01, 20, true, 9)
		# --- gene actions
		"express":
			b = _buf(0.35)
			_tone(b, 0, 0.2, 180, 340, 0.3, SIN, 0.005, 12, 0.04, 22)
			_noise(b, 0, 0.12, 0.15, 900, 300, 0.003, 20, false, 10)
			_chime(b, 0.03, 1320, 0.09, 12)
		"clean":
			b = _buf(0.6)
			_chime(b, 0, 1568, 0.18, 7)
			_chime(b, 0.04, 2093, 0.15, 7)
			_chime(b, 0.08, 3136, 0.07, 9)
			_noise(b, 0, 0.3, 0.05, 6000, 8000, 0.01, 10, true, 11)
		"link":
			b = _buf(0.35)
			_tone(b, 0, 0.2, 587, 880, 0.12, TRI, 0.003, 14)
			_chime(b, 0, 1175, 0.18, 10)
		"skip":
			b = _buf(0.3)
			_noise(b, 0, 0.28, 0.18, 1400, 300, 0.005, 9, true, 12)
			_tone(b, 0, 0.25, 300, 140, 0.12, TRI, 0.003, 10)
		"splice":
			b = _buf(0.22)
			_tone(b, 0, 0.05, 700, 700, 0.16, TRI, 0.002, 40)
			_tone(b, 0.06, 0.05, 940, 940, 0.16, TRI, 0.002, 40)
			_noise(b, 0.05, 0.06, 0.15, 2500, 900, 0.002, 40, true, 13)
			_bubble(b, 0.1, 350, 0.12)
		"tick":
			b = _buf(0.03)
			_tone(b, 0, 0.02, 2200, 2200, 0.16, SIN, 0.0005, 200)
			_noise(b, 0, 0.01, 0.1, 5000, 5000, 0.0005, 300, false, 14)
		"mutate":
			b = _buf(0.6)
			_tone(b, 0, 0.55, 260, 620, 0.22, SIN, 0.02, 3, 0.07, 13)
			_tone(b, 0, 0.55, 390, 930, 0.07, TRI, 0.02, 4, 0.05, 9)
			_noise(b, 0, 0.5, 0.1, 400, 2000, 0.05, 4, true, 15)
		# --- combat
		"hit_s":
			b = _buf(0.14)
			_noise(b, 0, 0.1, 0.35, 2600, 500, 0.002, 35, false, 16)
			_tone(b, 0, 0.1, 200, 90, 0.3, SIN, 0.002, 30)
		"hit_m":
			b = _buf(0.22)
			_noise(b, 0, 0.18, 0.4, 2200, 300, 0.002, 22, false, 17)
			_tone(b, 0, 0.18, 150, 60, 0.4, SIN, 0.002, 18)
			_tone(b, 0, 0.05, 90, 80, 0.08, SQR, 0.002, 60)
		"hit_l":
			b = _buf(0.45)
			_noise(b, 0, 0.02, 0.25, 6000, 5000, 0.001, 150, false, 18)
			_noise(b, 0, 0.35, 0.45, 1800, 120, 0.002, 11, false, 19)
			_tone(b, 0, 0.4, 120, 38, 0.5, SIN, 0.002, 9)
			_tone(b, 0, 0.12, 70, 45, 0.12, SAW, 0.002, 25)
		"film":
			b = _buf(0.5)
			_tone(b, 0, 0.3, 440, 660, 0.06, SIN, 0.03, 8)
			_noise(b, 0, 0.35, 0.08, 5000, 7000, 0.04, 8, true, 20)
			_chime(b, 0, 1320, 0.13, 8)
			_chime(b, 0.03, 1980, 0.11, 8)
		"heal":
			b = _buf(0.6)
			_tone(b, 0, 0.45, 440, 660, 0.12, TRI, 0.05, 5)
			_tone(b, 0, 0.45, 554, 830, 0.07, SIN, 0.05, 5)
			_bubble(b, 0.05, 500, 0.08)
			_bubble(b, 0.12, 650, 0.07)
			_chime(b, 0.15, 1320, 0.11, 7)
		"chorus":
			b = _buf(0.8)
			for f in [330.0, 415.3, 493.9]:
				_tone(b, 0, 0.8, f, f, 0.1, SIN, 0.08, 3.5, 0.006, 5)
			_noise(b, 0, 0.6, 0.05, 2500, 2500, 0.1, 4, true, 21)
		"rot":
			b = _buf(0.5)
			_noise(b, 0, 0.45, 0.15, 500, 200, 0.02, 5, false, 22)
			for k in 6:
				_bubble(b, k * 0.065 + r.randf() * 0.02, r.randf_range(140, 300), 0.14)
		"mark":
			b = _buf(0.5)
			_tone(b, 0, 0.45, 150, 140, 0.18, SIN, 0.02, 5)
			_tone(b, 0, 0.08, 1250, 1250, 0.14, TRI, 0.002, 30)
			_tone(b, 0.12, 0.08, 1250, 1250, 0.12, TRI, 0.002, 30)
		"gnaw":
			b = _buf(0.35)
			for k in 4:
				_noise(b, k * 0.075, 0.06, 0.3, 1500, 500, 0.002, 45, true, 30 + k)
				_tone(b, k * 0.075, 0.05, 160, 110, 0.15, SIN, 0.002, 50)
		"knot":
			b = _buf(0.45)
			_tone(b, 0, 0.4, 220, 120, 0.25, SIN, 0.01, 6, 0.03, 30)
			_tone(b, 0, 0.4, 90, 80, 0.06, SAW, 0.02, 6, 0.05, 17)
			_noise(b, 0, 0.3, 0.1, 700, 300, 0.005, 8, true, 23)
		"windup":
			b = _buf(0.65)
			_tone(b, 0, 0.6, 70, 240, 0.25, SIN, 0.35, 0.5)
			_tone(b, 0, 0.6, 140, 480, 0.05, TRI, 0.4, 0.5)
			_noise(b, 0, 0.6, 0.14, 300, 2400, 0.4, 0.5, true, 24)
		"break":
			b = _buf(0.6)
			_noise(b, 0, 0.05, 0.4, 7000, 3000, 0.001, 50, true, 25)
			_tone(b, 0, 0.2, 160, 60, 0.3, SIN, 0.002, 15)
			for k in 9:
				_chime(b, r.randf() * 0.12, r.randf_range(1800, 5200), 0.07, r.randf_range(10, 22))
		"stagger":
			b = _buf(0.5)
			_tone(b, 0, 0.45, 320, 110, 0.25, SIN, 0.01, 5, 0.1, 9)
			_tone(b, 0, 0.45, 480, 160, 0.06, TRI, 0.01, 6, 0.1, 9)
		"enemy_die":
			b = _buf(0.9)
			_tone(b, 0, 0.8, 220, 40, 0.35, SIN, 0.01, 3.5, 0.05, 11)
			_noise(b, 0, 0.7, 0.25, 1400, 90, 0.003, 4.5, false, 26)
			for k in 5:
				_bubble(b, 0.1 + k * 0.11, r.randf_range(180, 420), 0.1)
		"hurt":
			b = _buf(0.35)
			_tone(b, 0, 0.3, 100, 45, 0.45, SIN, 0.002, 10)
			_noise(b, 0, 0.25, 0.3, 1100, 180, 0.002, 14, false, 27)
			_tone(b, 0, 0.12, 75, 60, 0.08, SQR, 0.002, 25)
		# --- results / map
		"win":
			b = _buf(1.4)
			_tone(b, 0, 1.3, 261.6, 261.6, 0.08, SIN, 0.1, 2.5)
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for k in notes.size():
				var f: float = notes[k]
				_chime(b, k * 0.11, f, 0.15, 4.5)
		"lose":
			b = _buf(1.6)
			_tone(b, 0, 1.5, 330, 165, 0.14, TRI, 0.03, 2)
			_tone(b, 0, 1.5, 311, 155, 0.1, SIN, 0.03, 2)
			_tone(b, 0, 1.5, 55, 55, 0.25, SIN, 0.2, 1.8)
			_noise(b, 0, 1.2, 0.06, 600, 150, 0.2, 2, false, 28)
		"reward":
			b = _buf(0.5)
			_bubble(b, 0, 500, 0.08)
			_chime(b, 0, 784, 0.16, 8)
			_chime(b, 0.07, 1175, 0.14, 7)
		"adapt":
			b = _buf(1.0)
			_tone(b, 0, 0.6, 200, 500, 0.2, SIN, 0.03, 3, 0.06, 11)
			_noise(b, 0, 0.5, 0.06, 300, 1500, 0.1, 4, true, 29)
			_chime(b, 0.25, 659.25, 0.12, 4)
			_chime(b, 0.25, 987.8, 0.1, 4)
			_chime(b, 0.32, 1318.5, 0.07, 5)
		"map_step":
			b = _buf(0.2)
			_tone(b, 0, 0.1, 110, 70, 0.25, SIN, 0.002, 30)
			_noise(b, 0, 0.06, 0.1, 600, 250, 0.002, 40, false, 31)
			_chime(b, 0.02, 660, 0.06, 18)
		"shop":
			b = _buf(0.5)
			_chime(b, 0, 1760, 0.14, 9)
			_chime(b, 0.09, 2349, 0.12, 9)
			_chime(b, 0.1, 1765, 0.06, 10)
		"event":
			b = _buf(0.9)
			_tone(b, 0, 0.9, 220, 220, 0.09, TRI, 0.15, 2.5)
			_tone(b, 0, 0.9, 233, 233, 0.08, TRI, 0.2, 2.5)
			_tone(b, 0, 0.9, 110, 110, 0.14, SIN, 0.15, 2)
			_noise(b, 0, 0.7, 0.04, 1200, 1200, 0.2, 3, true, 32)
		"rest":
			b = _buf(1.4)
			for f in [261.6, 329.6, 392.0]:
				_tone(b, 0, 1.4, f, f, 0.09, SIN, 0.25, 1.8, 0.004, 4)
			_noise(b, 0, 1.0, 0.04, 400, 400, 0.3, 2.5, false, 33)
		# --- ambience one-shots
		"power_on":
			b = _buf(1.2)
			_noise(b, 0, 0.03, 0.3, 3000, 3000, 0.001, 100, false, 34)
			_tone(b, 0, 1.1, 40, 120, 0.25, SIN, 0.3, 0.8)
			_tone(b, 0, 1.1, 40, 120, 0.08, SAW, 0.3, 0.8)
			_tone(b, 0.2, 1.0, 60, 60, 0.08, SIN, 0.2, 1)
			_chime(b, 0.9, 1046.5, 0.1, 6)
		"thud":
			b = _buf(0.45)
			_tone(b, 0, 0.4, 65, 32, 0.55, SIN, 0.002, 9)
			_noise(b, 0, 0.2, 0.25, 350, 120, 0.002, 18, false, 35)
		"whisper":
			b = _buf(1.3)
			for k in 6:
				var t0 := k * 0.18 + r.randf() * 0.05
				var fc := r.randf_range(1400, 2600)
				_noise(b, t0, r.randf_range(0.1, 0.2), 0.12, fc, fc * 0.8, 0.04, 10, true, 40 + k)
				if r.randf() < 0.4:
					_noise(b, t0 + 0.05, 0.08, 0.05, 5000, 5000, 0.02, 20, true, 50 + k)
		"glitch":
			b = _buf(0.3)
			for k in 7:
				var f := r.randf_range(200, 3000)
				_tone(b, k * 0.04, 0.03, f, f * r.randf_range(0.7, 1.3), 0.09, SQR, 0.0005, 5)
				if r.randf() < 0.4:
					_noise(b, k * 0.04, 0.02, 0.12, 6000, 6000, 0.0005, 40, false, 60 + k)
		# --- §18 additions
		"inject":
			b = _buf(0.45)
			_noise(b, 0, 0.3, 0.2, 4500, 1800, 0.01, 8, true, 61)
			_tone(b, 0, 0.08, 1600, 800, 0.11, SIN, 0.001, 30)
			_tone(b, 0.05, 0.35, 140, 210, 0.25, SIN, 0.02, 7, 0.05, 18)
			_bubble(b, 0.2, 300, 0.1)
		"plunger":
			b = _buf(0.5)
			_noise(b, 0, 0.45, 0.2, 700, 300, 0.08, 4, false, 62)
			_tone(b, 0, 0.45, 170, 120, 0.18, SIN, 0.05, 4, 0.03, 24)
			_tone(b, 0.38, 0.07, 90, 90, 0.2, SIN, 0.002, 35)
		"vein":
			b = _buf(0.7)
			_tone(b, 0, 0.25, 70, 55, 0.4, SIN, 0.01, 9)
			_tone(b, 0.22, 0.3, 62, 48, 0.3, SIN, 0.01, 9)
			_noise(b, 0, 0.6, 0.1, 300, 150, 0.05, 3, false, 63)
		"resonance":
			b = _buf(1.5)
			for f in [110.0, 165.0, 220.0, 330.0, 440.0]:
				_tone(b, 0, 1.5, f, f, 0.08, SIN, 0.4, 1.6, 0.01, 6)
			_noise(b, 0, 1.2, 0.05, 1500, 4000, 0.4, 2, true, 64)
			_chime(b, 0.4, 1320, 0.11, 3.5)
			_chime(b, 0.45, 1980, 0.07, 4)
		"shift":
			b = _buf(0.45)
			_noise(b, 0, 0.45, 0.25, 350, 2600, 0.18, 4, true, 65)
			_tone(b, 0, 0.4, 90, 160, 0.12, SIN, 0.1, 4)
		"pour":
			b = _buf(0.9)
			_noise(b, 0, 0.85, 0.2, 600, 900, 0.05, 2, true, 66)
			_noise(b, 0, 0.85, 0.08, 1800, 1400, 0.1, 2, true, 67)
			for k in 8:
				_bubble(b, r.randf() * 0.75, r.randf_range(300, 900), 0.07)
		"bubble":
			b = _buf(0.1)
			_tone(b, 0, 0.08, 420, 1100, 0.2, SIN, 0.002, 35)
		"vial":
			b = _buf(0.45)
			_noise(b, 0, 0.015, 0.12, 6000, 6000, 0.0005, 200, false, 68)
			_chime(b, 0, 2637, 0.14, 11)
			_chime(b, 0.012, 3520, 0.08, 13)
		"needle":
			b = _buf(0.15)
			_noise(b, 0, 0.01, 0.12, 5000, 5000, 0.0005, 300, false, 69)
			_tone(b, 0, 0.1, 3000, 2300, 0.08, TRI, 0.001, 25)
			_tone(b, 0, 0.1, 4400, 4400, 0.04, SIN, 0.001, 40)
		"heart":
			b = _buf(0.5)
			_tone(b, 0, 0.16, 75, 50, 0.5, SIN, 0.002, 16)
			_noise(b, 0, 0.08, 0.12, 250, 200, 0.002, 30, false, 70)
			_tone(b, 0.17, 0.2, 65, 45, 0.38, SIN, 0.002, 14)
		_:
			return null
	return _wav(b)


## A DRONE_LEN-second loop; the tail is crossfaded into the head so it wraps cleanly.
func _make_drone(region: String) -> AudioStreamWAV:
	var b := _buf(DRONE_LEN + DRONE_XF)
	match region:
		"wound":
			_hum(b, 55.0, 0.2, 0.5, 0.5)
			_hum(b, 110.3, 0.04)
			_wind(b, 0.15, 220.0, 120.0, 0.25, 0.25, 0.4, false, 101)
		"rivers":
			_hum(b, 73.4, 0.1, 0.25, 0.3)
			_wind(b, 0.22, 500.0, 350.0, 0.5, 0.25, 0.3, false, 102)
			_wind(b, 0.06, 1800.0, 600.0, 0.75, 0.0, 0.0, true, 103)
		"hollow":
			_hum(b, 49.0, 0.14)
			_wind(b, 0.25, 700.0, 400.0, 0.25, 0.25, 0.85, true, 104)
		"archive":
			_hum(b, 110.0, 0.1, 0.5, 0.2)
			_hum(b, 164.8, 0.05)
			_hum(b, 1760.0, 0.012, 1.0, 0.8)
			_hum(b, 2637.0, 0.006, 0.75, 0.9)
			_wind(b, 0.05, 3000.0, 0.0, 0.25, 0.0, 0.0, true, 105)
		"root":
			_hum(b, 41.2, 0.22)
			_hum(b, 42.0, 0.15)
			_hum(b, 61.7, 0.08, 0.25, 0.5)
			_wind(b, 0.1, 150.0, 60.0, 0.25, 0.0, 0.0, false, 106)
		"lab":
			_hum(b, 60.0, 0.08)
			_hum(b, 120.0, 0.05)
			_hum(b, 180.0, 0.025)
			_wind(b, 0.1, 600.0, 0.0, 0.25, 0.0, 0.0, true, 107)
		"dream":
			_hum(b, 110.0, 0.07, 0.25, 0.4)
			_hum(b, 220.0, 0.06, 0.0, 0.0, 0.004, 0.5)
			_hum(b, 277.2, 0.05, 0.0, 0.0, 0.004, 0.75)
			_hum(b, 329.6, 0.05, 0.0, 0.0, 0.004, 0.25)
			_wind(b, 0.04, 4000.0, 2000.0, 0.25, 0.0, 0.0, true, 108)
		"title":
			_hum(b, 55.0, 0.18, 0.25, 0.3)
			_hum(b, 82.4, 0.07, 0.5, 0.4)
			_hum(b, 440.0, 0.015, 0.25, 0.9)
			_wind(b, 0.08, 300.0, 150.0, 0.25, 0.0, 0.0, false, 109)
		_:
			return null
	var n := int(DRONE_LEN * RATE)
	var xf := b.size() - n
	for i in xf:
		var w := float(i) / xf
		b[i] = b[i] * w + b[n + i] * (1.0 - w)
	b.resize(n)
	return _wav(b, true)
