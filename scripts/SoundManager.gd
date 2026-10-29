class_name SoundManager
extends Node

const MIX_RATE: int = 22050
const SETTINGS_PATH: String = "user://audio_settings.cfg"
const BASE_MUSIC_DB: float = -5.5
const BASE_SFX_DB: float = -2.5

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_pool_index: int = 0

var master_volume: float = 0.85
var music_volume: float = 0.75
var sfx_volume: float = 0.85
var is_muted: bool = false

var _sfx_cache: Dictionary = {}

func _ready() -> void:
	# Lecteur dédié à la musique celtique 8-bit en boucle
	music_player = AudioStreamPlayer.new()
	add_child(music_player)

	# Pool de 8 lecteurs audio pour jouer plusieurs effets sonores simultanément
	for _i in range(8):
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)

	_load_settings()
	_PrebuildSfxCache()
	_StartCelticMusic()
	_apply_volumes()

func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_muted(muted: bool) -> void:
	is_muted = muted
	_apply_volumes()
	_save_settings()

func toggle_audio() -> bool:
	set_muted(not is_muted)
	return not is_muted

func _apply_volumes() -> void:
	var eff_music: float = 0.0 if is_muted else (master_volume * music_volume)
	var eff_sfx: float = 0.0 if is_muted else (master_volume * sfx_volume)

	if eff_music <= 0.001:
		music_player.volume_db = -80.0
		music_player.stream_paused = true
	else:
		music_player.volume_db = linear_to_db(eff_music) + BASE_MUSIC_DB
		music_player.stream_paused = false
		if music_player.stream != null and not music_player.playing:
			music_player.play()

	var sfx_db: float = -80.0 if eff_sfx <= 0.001 else (linear_to_db(eff_sfx) + BASE_SFX_DB)
	for p in sfx_players:
		p.volume_db = sfx_db

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "is_muted", is_muted)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = clampf(float(cfg.get_value("audio", "master_volume", 0.85)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", 0.75)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
		is_muted = bool(cfg.get_value("audio", "is_muted", false))

func _StartCelticMusic() -> void:
	var stream: AudioStreamWAV = _GenerateCalmCelticMusic()
	music_player.stream = stream
	music_player.play()
	_apply_volumes()

func _PrebuildSfxCache() -> void:
	_sfx_cache["card_pick"] = _GenCardPickSfx()
	_sfx_cache["card_undo"] = _GenCardUndoSfx()
	_sfx_cache["rotate"] = _GenRotateSfx()
	_sfx_cache["cast_launch"] = _GenCastLaunchSfx()
	_sfx_cache["impact_fire"] = _GenImpactFireSfx()
	_sfx_cache["impact_ice"] = _GenImpactIceSfx()
	_sfx_cache["impact_poison"] = _GenImpactPoisonSfx()
	_sfx_cache["impact_earth"] = _GenImpactEarthSfx()
	_sfx_cache["impact_neutral"] = _GenImpactNeutralSfx()
	_sfx_cache["monster_death"] = _GenMonsterDeathSfx()
	_sfx_cache["market_buy"] = _GenMarketBuySfx()
	_sfx_cache["market_trash"] = _GenMarketTrashSfx()
	_sfx_cache["tower_hit"] = _GenTowerHitSfx()
	_sfx_cache["wave_clear"] = _GenWaveClearSfx()
	_sfx_cache["end_turn"] = _GenEndTurnSfx()

func play_sfx(sfx_name: String, pitch_scale: float = 1.0) -> void:
	if is_muted or (master_volume * sfx_volume) <= 0.001 or not _sfx_cache.has(sfx_name):
		return
	var p: AudioStreamPlayer = sfx_players[sfx_pool_index]
	sfx_pool_index = (sfx_pool_index + 1) % sfx_players.size()
	p.stream = _sfx_cache[sfx_name]
	p.pitch_scale = pitch_scale
	p.play()

func play_spell_cast() -> void:
	play_sfx("cast_launch", randf_range(0.96, 1.05))

func play_spell_impact(element: int) -> void:
	match element:
		SpellData.Element.FIRE:
			play_sfx("impact_fire", randf_range(0.95, 1.05))
		SpellData.Element.ICE:
			play_sfx("impact_ice", randf_range(0.97, 1.04))
		SpellData.Element.POISON:
			play_sfx("impact_poison", randf_range(0.95, 1.05))
		SpellData.Element.EARTH:
			play_sfx("impact_earth", randf_range(0.94, 1.03))
		_:
			play_sfx("impact_neutral", randf_range(0.96, 1.04))

# ============================================================================
# SYNTHÉTISEUR CHIPTUNE 8-BIT : MUSIQUE CELTIQUE CALME (MODE DE RÉ DORIEN)
# ============================================================================
# Mélodie à la flûte irlandaise (onde triangle + léger vibrato),
# Arpèges de harpe celtique (onde pulse 25% pincée) et bourdon doux à la basse.

static func _MidiToFreq(midi_note: int) -> float:
	if midi_note <= 0:
		return 0.0
	return 440.0 * pow(2.0, float(midi_note - 69) / 12.0)

static func _WavePulse(phase: float, duty: float = 0.25) -> float:
	var p: float = fposmod(phase, 1.0)
	return 1.0 if p < duty else -1.0

static func _WaveTriangle(phase: float) -> float:
	var p: float = fposmod(phase, 1.0)
	return 4.0 * absf(p - 0.5) - 1.0

static func _CreateWav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var byte_data := PackedByteArray()
	byte_data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var clamped: float = clampf(samples[i], -1.0, 1.0)
		var pcm16: int = int(roundf(clamped * 32760.0))
		byte_data[i * 2] = pcm16 & 0xFF
		byte_data[i * 2 + 1] = (pcm16 >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	wav.data = byte_data
	return wav

func _GenerateCalmCelticMusic() -> AudioStreamWAV:
	# Mesure en 6/8 calme (Ballade celtique) : 8 mesures de 6 croches = 48 pas
	# Chaque croche dure 0.30 seconde -> Boucle complète de 14.4 secondes
	var step_dur: float = 0.30
	var total_steps: int = 48
	var total_samples: int = int(float(total_steps) * step_dur * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total_samples)

	# Notes MIDI en Ré Dorien (D, E, F, G, A, B, C) :
	# D4=62, E4=64, F4=65, G4=67, A4=69, B4=71, C5=72, D5=74, E5=76, F5=77, G5=79, A5=81
	# Mélodie de flûte celtique (0 = tenue de la note précédente, -1 = silence/respiration)
	var whistle_melody: Array[int] = [
		# Mesure 1 (Dm)          # Mesure 2 (C)
		74, 0, 76, 77, 76, 74,   72, 0, 69, 67, 0, -1,
		# Mesure 3 (G)           # Mesure 4 (Dm)
		71, 0, 72, 74, 76, 71,   69, 0, 65, 62, 0, -1,
		# Mesure 5 (Dm)          # Mesure 6 (F)
		74, 76, 77, 81, 0, 79,   77, 0, 76, 72, 0, 74,
		# Mesure 7 (C / Am)      # Mesure 8 (Dm final doux)
		76, 74, 72, 69, 67, 69,  62, 0, 0, 0, 0, -1
	]

	# Arpèges de harpe celtique (6 croches par mesure)
	var harp_arpeggios: Array[int] = [
		# M1: Dm (D3 A3 D4 F4 A4 F4)
		50, 57, 62, 65, 69, 65,
		# M2: C  (C3 G3 C4 E4 G4 E4)
		48, 55, 60, 64, 67, 64,
		# M3: G  (G3 B3 D4 G4 B4 G4)
		55, 59, 62, 67, 71, 67,
		# M4: Dm (D3 A3 D4 F4 A4 D4)
		50, 57, 62, 65, 69, 62,
		# M5: Dm (D3 A3 D4 F4 A4 F4)
		50, 57, 62, 65, 69, 65,
		# M6: F  (F3 C4 F4 A4 C5 A4)
		53, 60, 65, 69, 72, 69,
		# M7: C  (C3 G3 C4 E4 G4 E4)
		48, 55, 60, 64, 67, 64,
		# M8: Dm (D3 A3 D4 F4 D4 A3)
		50, 57, 62, 65, 62, 57
	]

	# Basse / Bourdon doux par mesure (8 mesures)
	var bass_roots: Array[int] = [38, 36, 43, 38, 38, 41, 36, 38]

	# Pré-calcul des segments de la mélodie (début et durée de chaque note de flûte)
	var note_starts: Array[int] = []
	var note_pitches: Array[int] = []
	var note_lengths: Array[int] = []
	note_starts.resize(total_steps)
	note_pitches.resize(total_steps)
	note_lengths.resize(total_steps)

	var cur_pitch: int = -1
	var cur_start: int = 0
	for s in range(total_steps):
		var m_val: int = whistle_melody[s]
		if m_val != 0:
			cur_pitch = m_val
			cur_start = s
		note_pitches[s] = cur_pitch
		note_starts[s] = cur_start

	for s in range(total_steps):
		var st: int = note_starts[s]
		var ln: int = 1
		while st + ln < total_steps and whistle_melody[st + ln] == 0:
			ln += 1
		note_lengths[s] = ln

	var whistle_phase: float = 0.0
	var harp_phase: float = 0.0
	var bass_phase: float = 0.0

	for i in range(total_samples):
		var t: float = float(i) / float(MIX_RATE)
		var step_idx: int = clampi(int(t / step_dur), 0, total_steps - 1)
		var step_local_t: float = fmod(t, step_dur)
		var measure_idx: int = clampi(step_idx / 6, 0, 7)
		var measure_local_t: float = fmod(t, step_dur * 6.0)

		# 1. Flûte celtique (Tin Whistle)
		var w_sample: float = 0.0
		var w_midi: int = note_pitches[step_idx]
		if w_midi > 0:
			var n_start_step: int = note_starts[step_idx]
			var n_len_steps: int = note_lengths[step_idx]
			var note_t: float = t - float(n_start_step) * step_dur
			var note_dur: float = float(n_len_steps) * step_dur

			# Vibrato doux celtique
			var vibrato: float = 1.0 + sin(note_t * TAU * 5.2) * 0.0045 * clampf(note_t / 0.25, 0.0, 1.0)
			var w_freq: float = _MidiToFreq(w_midi) * vibrato
			whistle_phase += w_freq / float(MIX_RATE)

			var attack: float = clampf(note_t / 0.045, 0.0, 1.0)
			var release: float = clampf((note_dur - note_t) / 0.06, 0.0, 1.0)
			var env: float = attack * release
			w_sample = (_WaveTriangle(whistle_phase) * 0.75 + _WavePulse(whistle_phase, 0.5) * 0.25) * env * 0.24

		# 2. Harpe celtique (Arpège pincé 8-bit)
		var h_midi: int = harp_arpeggios[step_idx]
		var h_freq: float = _MidiToFreq(h_midi)
		harp_phase += h_freq / float(MIX_RATE)
		var h_attack: float = clampf(step_local_t / 0.008, 0.0, 1.0)
		var h_decay: float = exp(-step_local_t * 7.5)
		var h_sample: float = _WavePulse(harp_phase, 0.25) * h_attack * h_decay * 0.20

		# 3. Bourdon doux de basse (Triangle)
		var b_midi: int = bass_roots[measure_idx]
		var b_freq: float = _MidiToFreq(b_midi)
		bass_phase += b_freq / float(MIX_RATE)
		var b_env: float = clampf(measure_local_t / 0.05, 0.0, 1.0) * exp(-measure_local_t * 0.7)
		var b_sample: float = _WaveTriangle(bass_phase) * b_env * 0.22

		samples[i] = clampf(w_sample + h_sample + b_sample, -0.95, 0.95)

	return _CreateWav(samples, true)

# ============================================================================
# GÉNÉRATION DES EFFETS SONORES 8-BIT (SORTS, MARCHÉ, MORT DES MONSTRES...)
# ============================================================================

func _GenCardPickSfx() -> AudioStreamWAV:
	# Petit arpège de harpe cristallin à 2 notes
	var dur: float = 0.14
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = 523.25 if t < 0.06 else 659.25 # C5 -> E5
		phase += freq / float(MIX_RATE)
		var env: float = exp(-fmod(t, 0.07) * 28.0)
		s[i] = _WavePulse(phase, 0.25) * env * 0.45
	return _CreateWav(s)

func _GenCardUndoSfx() -> AudioStreamWAV:
	var dur: float = 0.14
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = 523.25 if t < 0.06 else 392.00 # C5 -> G4
		phase += freq / float(MIX_RATE)
		var env: float = exp(-fmod(t, 0.07) * 28.0)
		s[i] = _WaveTriangle(phase) * env * 0.45
	return _CreateWav(s)

func _GenRotateSfx() -> AudioStreamWAV:
	var dur: float = 0.055
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = lerpf(440.0, 680.0, t / dur)
		phase += freq / float(MIX_RATE)
		var env: float = 1.0 - (t / dur)
		s[i] = _WaveTriangle(phase) * env * 0.32
	return _CreateWav(s)

func _GenCastLaunchSfx() -> AudioStreamWAV:
	# Incantation du Sorcier + départ du projectile magique
	var dur: float = 0.28
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var ratio: float = t / dur
		var freq: float = lerpf(280.0, 920.0, pow(ratio, 1.3)) + sin(t * 75.0) * 35.0
		phase += freq / float(MIX_RATE)
		var env: float = sin(ratio * PI)
		s[i] = (_WavePulse(phase, 0.25) * 0.6 + _WaveTriangle(phase) * 0.4) * env * 0.45
	return _CreateWav(s)

func _GenImpactFireSfx() -> AudioStreamWAV:
	# Explosion de flammes 8-bit (bruit crépitant + chute de fréquence grave)
	var dur: float = 0.38
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var noise_hold: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = lerpf(260.0, 55.0, pow(t / dur, 0.6))
		phase += freq / float(MIX_RATE)
		if i % 6 == 0:
			noise_hold = rng.randf_range(-1.0, 1.0)
		var env: float = exp(-t * 7.5)
		s[i] = (_WavePulse(phase, 0.5) * 0.45 + noise_hold * 0.55) * env * 0.55
	return _CreateWav(s)

func _GenImpactIceSfx() -> AudioStreamWAV:
	# Cristaux de givre étincelants 8-bit
	var dur: float = 0.34
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var notes: Array[float] = [1046.5, 1318.5, 1568.0, 2093.0, 1568.0, 2093.0]
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var idx: int = clampi(int((t / dur) * float(notes.size())), 0, notes.size() - 1)
		var freq: float = notes[idx]
		phase += freq / float(MIX_RATE)
		var env: float = exp(-t * 6.5)
		s[i] = (_WaveTriangle(phase) * 0.65 + _WavePulse(phase, 0.15) * 0.35) * env * 0.48
	return _CreateWav(s)

func _GenImpactPoisonSfx() -> AudioStreamWAV:
	# Bouillonnement acide (modulation de fréquence 8-bit)
	var dur: float = 0.36
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var bubble: float = sin(t * TAU * 19.0) * 140.0
		var freq: float = lerpf(380.0, 210.0, t / dur) + bubble
		phase += freq / float(MIX_RATE)
		var env: float = exp(-t * 6.0)
		s[i] = _WavePulse(phase, 0.3) * env * 0.45
	return _CreateWav(s)

func _GenImpactEarthSfx() -> AudioStreamWAV:
	# Secousse tellurique sourde et impact rocheux
	var dur: float = 0.40
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var noise_hold: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = lerpf(135.0, 42.0, t / dur)
		phase += freq / float(MIX_RATE)
		if i % 14 == 0:
			noise_hold = rng.randf_range(-1.0, 1.0)
		var env: float = exp(-t * 6.8)
		s[i] = (_WavePulse(phase, 0.5) * 0.65 + noise_hold * 0.35) * env * 0.58
	return _CreateWav(s)

func _GenImpactNeutralSfx() -> AudioStreamWAV:
	# Onde arcanique claire
	var dur: float = 0.30
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var p1: float = 0.0
	var p2: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		p1 += 440.0 / float(MIX_RATE)
		p2 += 659.25 / float(MIX_RATE)
		var env: float = exp(-t * 8.5)
		s[i] = (_WaveTriangle(p1) + _WavePulse(p2, 0.25)) * 0.5 * env * 0.45
	return _CreateWav(s)

func _GenMonsterDeathSfx() -> AudioStreamWAV:
	# Dissolution 8-bit du monstre + tintement de la pièce d'or gagnée (+1 Or)
	var dur: float = 0.36
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var noise_val: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		if t < 0.18:
			# Chute de pitch 8-bit du monstre vaincu
			var freq: float = lerpf(420.0, 95.0, t / 0.18)
			phase += freq / float(MIX_RATE)
			if i % 8 == 0:
				noise_val = rng.randf_range(-1.0, 1.0)
			var env: float = 1.0 - (t / 0.18) * 0.5
			s[i] = (_WavePulse(phase, 0.5) * 0.6 + noise_val * 0.4) * env * 0.48
		else:
			# Tintement de pièce d'or (B5 -> E6)
			var ct: float = t - 0.18
			var c_freq: float = 987.77 if ct < 0.05 else 1318.51
			phase += c_freq / float(MIX_RATE)
			var env: float = exp(-ct * 16.0)
			s[i] = _WavePulse(phase, 0.25) * env * 0.45
	return _CreateWav(s)

func _GenMarketBuySfx() -> AudioStreamWAV:
	# Jingle d'achat au marché (C5 -> E5 -> G5 -> C6)
	var dur: float = 0.36
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.50]
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var step: int = clampi(int(t / 0.08), 0, 3)
		var local_t: float = fmod(t, 0.08)
		phase += notes[step] / float(MIX_RATE)
		var env: float = exp(-local_t * 14.0) if step < 3 else exp(-(t - 0.24) * 10.0)
		s[i] = _WavePulse(phase, 0.25) * env * 0.48
	return _CreateWav(s)

func _GenMarketTrashSfx() -> AudioStreamWAV:
	# Suppression / brûlure d'une carte (marché ou deck)
	var dur: float = 0.26
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var n: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = lerpf(520.0, 160.0, t / dur)
		phase += freq / float(MIX_RATE)
		if i % 5 == 0:
			n = rng.randf_range(-1.0, 1.0)
		var env: float = exp(-t * 9.0)
		s[i] = (_WaveTriangle(phase) * 0.5 + n * 0.5) * env * 0.45
	return _CreateWav(s)

func _GenTowerHitSfx() -> AudioStreamWAV:
	# Alerte grave quand la Tour du Sorcier subit des dégâts
	var dur: float = 0.35
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = 146.83 if t < 0.15 else 110.0 # D3 -> A2
		phase += freq / float(MIX_RATE)
		var env: float = exp(-fmod(t, 0.16) * 9.0)
		s[i] = _WavePulse(phase, 0.5) * env * 0.55
	return _CreateWav(s)

func _GenWaveClearSfx() -> AudioStreamWAV:
	# Fanfare celtique de victoire de vague (D5 -> F5 -> A5 -> D6)
	var dur: float = 0.52
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var notes: Array[float] = [587.33, 698.46, 880.0, 1174.66]
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var step: int = clampi(int(t / 0.11), 0, 3)
		phase += notes[step] / float(MIX_RATE)
		var env: float = exp(-(t - float(step) * 0.11) * 8.0)
		s[i] = (_WaveTriangle(phase) * 0.6 + _WavePulse(phase, 0.25) * 0.4) * env * 0.48
	return _CreateWav(s)

func _GenEndTurnSfx() -> AudioStreamWAV:
	var dur: float = 0.16
	var count: int = int(dur * float(MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = lerpf(240.0, 160.0, t / dur)
		phase += freq / float(MIX_RATE)
		var env: float = exp(-t * 16.0)
		s[i] = _WaveTriangle(phase) * env * 0.45
	return _CreateWav(s)
