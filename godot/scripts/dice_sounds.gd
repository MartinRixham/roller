extends Node
## Impact sounds for the dice, synthesised at startup so there are no audio
## assets to ship or regenerate.
##
## Each sound is a short noise transient (the contact itself) plus a handful of
## exponentially decaying sine modes (whatever rings afterwards: the die, the
## table, the rail). Several variants per surface are rendered with slightly
## different modes so repeated hits do not sound machine-gunned.

enum Surface { FELT, WALL, DIE }

const MIX_RATE := 44100
const VARIANTS := 6

var _bank := {}
## Kept apart from the global RNG so sound never shifts a seeded roll sequence.
var _rng := RandomNumberGenerator.new()


## Play a random variant of the `surface` knock on `voice`; `loudness` is 0..1.
func play(voice: AudioStreamPlayer3D, surface: Surface, loudness: float) -> void:
	var variants: Array = _bank[surface]
	voice.stream = variants[_rng.randi() % variants.size()]
	voice.volume_db = linear_to_db(loudness)
	# Harder hits excite the higher modes, which reads as a touch brighter.
	voice.pitch_scale = _rng.randf_range(0.93, 1.07) + loudness * 0.05
	voice.play()


func _ready() -> void:
	# Fixed seed: the sounds are part of the game, not part of the roll.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD1CE
	for surface: Surface in Surface.values():
		var variants: Array[AudioStreamWAV] = []
		for i in VARIANTS:
			variants.append(_render(_recipe(surface, rng), rng))
		_bank[surface] = variants


## Noise burst and modes for one variant. Modes are [freq Hz, decay s, amp].
func _recipe(surface: Surface, rng: RandomNumberGenerator) -> Dictionary:
	var modes: Array = []
	match surface:
		Surface.FELT:
			# Felt over a wooden top: a dull thud, the die barely rings.
			for i in 3:
				modes.append([rng.randf_range(90, 240), rng.randf_range(0.03, 0.07), rng.randf_range(0.4, 0.7)])
			for i in 3:
				modes.append([rng.randf_range(2400, 5200), rng.randf_range(0.004, 0.009), rng.randf_range(0.05, 0.15)])
			return {length = 0.18, noise_ms = 5.0, noise_cutoff = 900.0, noise_amp = 0.9, modes = modes}
		Surface.WALL:
			# Bare wooden rail: a hollow knock with more of the die in it.
			for i in 3:
				modes.append([rng.randf_range(380, 1300), rng.randf_range(0.015, 0.035), rng.randf_range(0.4, 0.7)])
			for i in 4:
				modes.append([rng.randf_range(2500, 6000), rng.randf_range(0.007, 0.015), rng.randf_range(0.15, 0.35)])
			return {length = 0.14, noise_ms = 2.0, noise_cutoff = 3500.0, noise_amp = 0.8, modes = modes}
		_:
			# Two hard plastic dice: a bright, short clack from both bodies ringing.
			modes.append([rng.randf_range(1300, 1900), rng.randf_range(0.01, 0.02), rng.randf_range(0.2, 0.35)])
			for i in 6:
				modes.append([rng.randf_range(2600, 7200), rng.randf_range(0.006, 0.022), rng.randf_range(0.3, 0.7)])
			return {length = 0.1, noise_ms = 1.0, noise_cutoff = 9000.0, noise_amp = 0.7, modes = modes}


func _render(recipe: Dictionary, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var count := int(recipe.length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)

	# Contact transient: white noise through a one-pole low-pass, decaying fast.
	var noise_tau: float = recipe.noise_ms / 1000.0
	var lp_coeff := 1.0 - exp(-TAU * recipe.noise_cutoff / MIX_RATE)
	var lp := 0.0
	for n in mini(count, int(noise_tau * 8.0 * MIX_RATE)):
		var t := float(n) / MIX_RATE
		lp += lp_coeff * (rng.randf_range(-1.0, 1.0) - lp)
		samples[n] = lp * recipe.noise_amp * exp(-t / noise_tau)

	# Ringing: each mode starts at zero phase so there is no DC step.
	for mode: Array in recipe.modes:
		var omega: float = TAU * mode[0] / MIX_RATE
		var decay: float = exp(-1.0 / (mode[1] * MIX_RATE))
		var amp: float = mode[2]
		var n := 0
		while n < count and amp > 0.0005:
			samples[n] += amp * sin(omega * n)
			amp *= decay
			n += 1

	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.85 / maxf(peak, 0.0001)
	var fade := int(0.005 * MIX_RATE)

	var data := PackedByteArray()
	data.resize(count * 2)
	for n in count:
		var s := samples[n] * gain
		if n >= count - fade:
			s *= float(count - n) / fade
		data.encode_s16(n * 2, int(clampf(s, -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
