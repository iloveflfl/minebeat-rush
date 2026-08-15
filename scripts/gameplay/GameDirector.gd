extends Node3D

## GDD 25 - stage start/end, Act transitions, the destination.
##
## This is where the one causal chain of the game lives, and it is deliberately
## the only place that knows about all of it:
##
##     the sector collapses  ->  you need a mine  ->  the mine throws you  ->
##     you reach the next stretch of the same bridge
##
## GDD 26 [LOCK]: every discrete event below is driven by comparing the current
## *audio* beat against an absolute beat number. Nothing here counts with a
## Timer, and a dropped frame simply resolves several events in one pass.

enum State { BOOT, FREE_MOVE, ARMED, ACCIDENT_AIR, GROUND, AIR, GATE_AIR, ARRIVED, RESULTS }

var state: State = State.BOOT

var bridge: BridgeManager
var backdrop: BackdropDirector
var _pending_lights: Array = []
var player: PlayerMotor
var anim: CharacterAnimator
var cam: CameraDirector
var vfx: VFXDirector
var hud: HUD
var beat_ring: BeatRing
var launch := LaunchController.new()

var stage: Stage1Data.BuiltStage

# --- timeline ---------------------------------------------------------------
var _accident_beat := float(Tuning.ACCIDENT_GO_BEAT)
var _first_ground_beat := float(Tuning.FIRST_GROUND_BEAT)
var _cycle_beat := 0.0              ## landing GO of the sector being played
var _sector_index := -1
var _damage_fired := 0
var _air_phase_fired := 0
var _armed := false

# --- run record (GDD 22.2) --------------------------------------------------
var _launches := 0
var _glides := 0
var _perfect := 0
var _streak := 0
var _best_streak := 0
var _consecutive_glides := 0
var _last_arrival_song_time := -99.0
var _last_grade := LaunchController.Grade.PERFECT
var _hinted_sector := -1


## GDD 25.1: presentation only. The sector chain, the beat grid and the dash
## budget are identical on every tier - a phone plays exactly the same stage.
func _apply_quality_tier() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Quality.msaa()
	vp.scaling_3d_scale = Quality.render_scale()
	# Screen-space AA does not exist on the Compatibility renderer the web build
	# uses, and the setter warns there even when the value being set is
	# "disabled" - so on that renderer the property is left alone entirely.
	if not Quality.is_compatibility():
		vp.screen_space_aa = (Viewport.SCREEN_SPACE_AA_DISABLED if Quality.is_mobile()
				else Viewport.SCREEN_SPACE_AA_FXAA)
	print("MineBeat Rush - quality tier: %s" % Quality.describe())


func _ready() -> void:
	randomize()
	_apply_quality_tier()
	_build_environment()

	stage = Stage1Data.build(BeatConductor.tempo)
	for e in stage.errors:
		push_error("Stage 1 authoring error: %s" % e)
	assert(stage.errors.is_empty(), "Stage 1 failed validation - see errors above (GDD 27.1)")

	launch.setup(BeatConductor.tempo)

	bridge = BridgeManager.new()
	bridge.name = "Bridge"
	add_child(bridge)
	bridge.setup(stage)
	bridge.build_intro_deck()
	bridge.ensure_range(0)
	backdrop.setup(absf(stage.gate_z), _pending_lights)

	vfx = VFXDirector.new()
	vfx.name = "VFX"
	add_child(vfx)

	player = PlayerMotor.new()
	player.name = "Player"
	add_child(player)
	anim = CharacterAnimator.new()
	anim.name = "Character"
	player.add_child(anim)
	beat_ring = BeatRing.new()
	beat_ring.name = "BeatRing"
	player.add_child(beat_ring)

	cam = CameraDirector.new()
	cam.name = "Camera"
	add_child(cam)
	cam.target = player

	# GDD 23 / 33: the same three directions, reachable with a thumb.
	var touch := TouchInput.new()
	touch.name = "Touch"
	add_child(touch)

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.restart_requested.connect(_restart)
	hud.pause_toggled.connect(_on_pause_toggled)

	player.dash_started.connect(_on_dash_started)
	player.dash_arrived.connect(_on_dash_arrived)
	player.dash_rejected.connect(_on_dash_rejected)

	_parse_dev_args()
	cam.closeup = _closeup
	if _dev_sector >= 0:
		_dev_jump_to_sector(_dev_sector)
	else:
		_enter_free_move()


# ---------------------------------------------------------------------------
# development entry points  (never reachable from a normal launch)
#   godot --path . -- --sector 18
#   godot --path . -- --sector 18 --shots S:/GameDev/MineBeatRush/captures
# ---------------------------------------------------------------------------

var _dev_sector := -1
var _auto_play := false
var _closeup := 0.0
var _shot_dir := ""
var _shot_beat_step := 0.75
var _shots_left := 0
var _next_shot_beat := 0.0
var _shot_index := 0


func _parse_dev_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--sector":
				if i + 1 < args.size():
					_dev_sector = int(args[i + 1])
			"--shots":
				if i + 1 < args.size():
					_shot_dir = args[i + 1]
					if _shots_left == 0:
						_shots_left = 12
			"--shot-count":
				if i + 1 < args.size():
					_shots_left = int(args[i + 1])
			"--shot-from":
				if i + 1 < args.size():
					_next_shot_beat = float(args[i + 1])
			"--shot-step":
				if i + 1 < args.size():
					_shot_beat_step = float(args[i + 1])
			"--auto":
				_auto_play = true
			"--closeup":
				if i + 1 < args.size():
					_closeup = float(args[i + 1])


## Development auto-play: solves the sector with the same MineGrid the level
## validator uses, then times the final arrival to land a PERFECT. It drives
## PlayerMotor.inject(), i.e. the exact path a key press takes, so it is a real
## test of the loop rather than a bypass of it.
func _auto_step() -> void:
	if player.is_dashing() or _sector_index < 0:
		return
	var g: MineGrid = stage.grids[_sector_index]
	var d := g.min_dashes_to_mine(player.cell)
	if d <= 0:
		return
	var go_time := BeatConductor.time_at_beat(_cycle_beat + float(Tuning.GROUND_BEATS))
	var remaining := go_time - BeatConductor.song_time
	if remaining > float(d) * Tuning.DASH_TIME + 0.05:
		return
	for m in MineGrid.CORE_MOVES:
		var nxt: Vector2i = player.cell + m
		if g.is_walkable(nxt) and g.min_dashes_to_mine(nxt) == d - 1:
			player.inject(m)
			return


func _dev_jump_to_sector(index: int) -> void:
	index = clampi(index, 0, stage.sectors.size() - 1)
	_armed = true
	_first_ground_beat = float(Tuning.FIRST_GROUND_BEAT)
	var b := _sector_ground_beat(index)
	BeatConductor.start(b)
	hud.hide_joystick()
	bridge.intro_sector.queue_free()
	_enter_ground(index, 0.0)
	cam.warp_to_target()
	_next_shot_beat = maxf(_next_shot_beat, b + 0.2)


func _service_shots(beat: float) -> void:
	if _shots_left <= 0 or _shot_dir == "":
		return
	if beat < _next_shot_beat:
		return
	_next_shot_beat = beat + _shot_beat_step
	_shots_left -= 1
	_capture()
	if _shots_left <= 0:
		get_tree().create_timer(0.5).timeout.connect(func() -> void: get_tree().quit())


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%02d.png" % [_shot_dir, _shot_index])
	print("captured shot_%02d.png  state=%-7s beat=%.2f  launches=%d glides=%d perfect=%d"
			% [_shot_index, State.keys()[state], BeatConductor.beat,
				_launches, _glides, _perfect])
	_shot_index += 1


# ---------------------------------------------------------------------------
# world dressing
# ---------------------------------------------------------------------------

## Cel shading wants flat, generous, unclipped light: no ambient occlusion
## grime, no filmic roll-off eating the top end, and just enough bloom that the
## bright things feel like they are glowing rather than merely pale.
func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.58, 0.92)
	sky_mat.sky_horizon_color = Color(0.98, 0.92, 0.78)
	sky_mat.sky_curve = 0.09
	# The reading camera looks *down*, so most of the visible dome is the ground
	# half. It gets the pale far-rock violet, which reads as distance haze
	# instead of as a wall of sky.
	sky_mat.ground_bottom_color = Greybox.C_ROCK_FAR.lightened(0.28)
	sky_mat.ground_horizon_color = Greybox.C_ROCK_FAR.lightened(0.45)
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# Cel shading has no falloff to hide behind: whatever the light adds up to is
	# exactly what lands on screen. Sun plus fill plus ambient is held just under
	# 1.0 so an authored albedo arrives on screen as the colour it was picked as.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.78, 0.98)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = 1.0

	# GDD 15.2: haze so the bridge reads as kilometres long, and so the far
	# canyon desaturates into the sky the way a painted background would.
	env.fog_enabled = true
	env.fog_light_color = Color(0.90, 0.88, 0.82)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.18

	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	env.adjustment_brightness = 1.02

	if Quality.is_compatibility():
		# The Compatibility renderer applies tonemapping and glow differently and
		# comes out hot. Trimmed here rather than in the palette so the desktop
		# and web builds keep the same authored colours.
		env.ambient_light_energy *= 0.72
		env.glow_intensity *= 0.45
		env.fog_density *= 0.55
		env.adjustment_brightness = 0.94
		env.adjustment_saturation = 1.02

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_color = Color(1.0, 0.97, 0.88)
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.shadow_blur = 0.6
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 3.0
	sun.directional_shadow_max_distance = Quality.shadow_distance()
	sun.shadow_enabled = not Quality.is_mobile()
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -145, 0)
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.light_energy = 0.12
	add_child(fill)

	backdrop = BackdropDirector.new()
	backdrop.name = "Backdrop"
	backdrop.env = env
	backdrop.sky_mat = sky_mat
	add_child(backdrop)
	_pending_lights = [sun, fill]


# ---------------------------------------------------------------------------
# Act 0 - free roam (GDD 12.1)
# ---------------------------------------------------------------------------

func _enter_free_move() -> void:
	state = State.FREE_MOVE
	player.place_on(bridge.intro_grid, Vector3.ZERO, Stage1Data.intro_start_cell())
	player.allow_back = true          ## only ever true here (GDD 7.1 [LOCK])
	player.input_enabled = true
	anim.set_state(CharacterAnimator.State.IDLE)
	# GDD 12.1: an establishing look down the canyon at the Sun Gate first, then
	# the camera settles into the roaming view and hands control over.
	cam.set_view(CameraDirector.View.OPENING)
	cam.warp_to_target()
	AudioDirector.set_act("Intro", true)
	BeatConductor.start()
	get_tree().create_timer(3.2).timeout.connect(func() -> void:
		if state == State.FREE_MOVE:
			cam.set_view(CameraDirector.View.FREE))


## GDD 12.2: stepping on the charge arms it. A short CLICK, a held silence, then
## the blast. The fuse is quantised up to the next bar so the explosion lands on
## a downbeat and the whole 3-2-1-GO grid is born from it.
func _arm_charge(auto: bool) -> void:
	if _armed:
		return
	_armed = true
	state = State.ARMED
	player.release()
	anim.set_state(CharacterAnimator.State.ARMED)
	AudioDirector.set_act("Accident")
	AudioDirector.play("sfx_click", 1.0 if not auto else 0.6)

	var now := BeatConductor.beat
	var earliest := now + 2.0
	_accident_beat = clampf(ceil(earliest / 4.0) * 4.0, 8.0, float(Tuning.ACCIDENT_GO_BEAT))
	if _accident_beat < earliest:
		_accident_beat += 4.0
	_first_ground_beat = _accident_beat + float(Tuning.AIR_BEATS)


## GDD 12.2 steps 4-7: the reversal. Not a death - a launch.
func _do_accident() -> void:
	state = State.ACCIDENT_AIR
	var from := player.global_position
	var target := _landing_position(0, from.x)

	bridge.intro_sector.collapse()
	vfx.mine_launch(from, true)
	vfx.collapse_burst(from + Vector3(0, -1, 6), 10.0)
	AudioDirector.play("sfx_explosion", 1.0)
	AudioDirector.play("sfx_collapse", 0.8)
	cam.impulse(0.9, 9.0)
	cam.set_view(CameraDirector.View.LAUNCH)
	hud.break_joystick()

	_last_grade = LaunchController.Grade.PERFECT
	launch.begin_launch(_accident_beat, from, target, LaunchController.Grade.PERFECT)
	anim.set_state(CharacterAnimator.State.LAUNCH, LaunchController.Grade.PERFECT)
	_air_phase_fired = 0
	# GDD 7.1 [LOCK]: from here on there is no backward input, because from here
	# on there is no bridge behind you.
	player.allow_back = false


# ---------------------------------------------------------------------------
# the core cycle
# ---------------------------------------------------------------------------

func _sector_ground_beat(index: int) -> float:
	return _first_ground_beat + float(Tuning.CYCLE_BEATS) * float(index)


func _landing_position(index: int, carry_x: float) -> Vector3:
	if index >= stage.sectors.size():
		return bridge.gate_landing_position()
	var d: SectorData = stage.sectors[index]
	var col := SectorData.x_to_col(carry_x, d.width)
	return d.cell_to_world(Vector2i(col, 0))


func _enter_ground(index: int, carry_x: float) -> void:
	_sector_index = index
	state = State.GROUND
	_cycle_beat = _sector_ground_beat(index)
	_damage_fired = 0

	bridge.ensure_range(index)
	var d: SectorData = stage.sectors[index]
	var g: MineGrid = stage.grids[index]
	var sec := bridge.sector(index)

	var col := SectorData.x_to_col(carry_x, d.width)
	player.place_on(g, Vector3(0, 0, d.world_z), Vector2i(col, 0), d.sand_cells)
	player.input_enabled = true
	player.allow_back = false
	_last_arrival_song_time = -99.0

	AudioDirector.set_act(d.act)
	backdrop.set_act(d.act)
	cam.set_view(CameraDirector.View.GROUND)
	beat_ring.set_active(true)
	cam.frame_depth = maxf(9.0, float(d.length - 1) * Tuning.TILE + 3.0)
	vfx.suppress = true               ## GDD 23: reading time is visually calm

	if index > 0:
		bridge.drop_sector(index - 2)

	# GDD 23: the adjacency hint, only after the player has actually struggled.
	if GameSettings.adjacency_hint_enabled and _consecutive_glides >= 2 \
			and sec != null and _hinted_sector != index:
		_hinted_sector = index
		sec.flash_adjacency(sec.best_clue_for(col))


## GDD 6.1 [LOCK]: the whole sector is damaged as one body on beats 3, 2 and 1,
## and goes on GO.
func _apply_damage(stage_num: int) -> void:
	var sec := bridge.sector(_sector_index)
	if sec != null:
		sec.set_damage(stage_num)
	AudioDirector.play("sfx_crack%d" % stage_num, 0.55 + 0.18 * stage_num, 1.0, 0.05)
	if stage_num >= 3:
		vfx.suppress = false          ## the last beat is allowed to get loud
		cam.impulse(0.05 * stage_num, 10.0)


## The GO downbeat. Everything the game is about happens on this line.
func _resolve_go() -> void:
	var d: SectorData = stage.sectors[_sector_index]
	var g: MineGrid = stage.grids[_sector_index]
	var sec := bridge.sector(_sector_index)
	var go_beat := _cycle_beat + float(Tuning.GROUND_BEATS)
	var on_mine := g.is_mine(player.cell)

	player.release()
	vfx.suppress = false
	beat_ring.set_active(false)
	if sec != null:
		sec.reveal_all_candidates()
		AudioDirector.play("sfx_reveal", 0.5)

	var from := player.global_position
	var next_index := _sector_index + 1
	var target := _landing_position(next_index, from.x)

	if on_mine:
		# GDD 10.1: success. Timing only changes how beautiful it looks.
		var early := BeatConductor.time_at_beat(go_beat) - _last_arrival_song_time
		var grade := LaunchController.grade_for(early, d.timing_exempt)
		_last_grade = grade
		# Show the working, not just the verdict (see HUD.show_grade). Only for
		# the opening stretch - after that the ring alone carries it.
		if _sector_index < 12:
			hud.show_grade(LaunchController.grade_name(grade),
					[Color(1, 0.92, 0.45), Color(0.62, 0.92, 1.0),
						Color(1.0, 0.62, 0.55)][int(grade)],
					maxf(0.0, early), Tuning.GOOD_WINDOW * 1.6)
		_launches += 1
		_consecutive_glides = 0
		if grade == LaunchController.Grade.PERFECT:
			_perfect += 1
			_streak += 1
			_best_streak = maxi(_best_streak, _streak)
		else:
			_streak = 0

		var big := d.spectacle == "final_gap" or d.gap_after > 40.0
		vfx.mine_launch(from, big)
		AudioDirector.play("sfx_explosion", 1.0 if big else 0.85, 1.0 if big else 1.12)
		# The comic layer on top of the real blast: the reversal is supposed to be
		# funny, not frightening (GDD 4.2 / 12.2).
		AudioDirector.play("sfx_pop", 0.8, 1.0 if big else 1.18, 0.05)
		if grade == LaunchController.Grade.PERFECT:
			AudioDirector.play("sfx_sparkle", 0.5, 1.0, 0.04)
		cam.impulse(0.85 if big else 0.55, 9.0)
		launch.begin_launch(go_beat, from, target, grade)
		anim.set_state(CharacterAnimator.State.LAUNCH, grade)
	else:
		# GDD 10.2 [LOCK]: fail forward. The deck goes, the scarf opens, and the
		# player still arrives at the next stretch on the same downbeat.
		_glides += 1
		_consecutive_glides += 1
		_streak = 0
		_last_grade = LaunchController.Grade.BAD
		AudioDirector.play("sfx_scarf", 0.9)
		AudioDirector.play("sfx_boing", 0.55, 0.85, 0.08)
		vfx.scarf_deploy(from)
		launch.begin_glide(go_beat, from, target)
		anim.set_state(CharacterAnimator.State.GLIDE, LaunchController.Grade.BAD)

	if sec != null:
		sec.collapse()
		vfx.collapse_burst(Vector3(0, -1.5, d.world_z - float(d.length) * Tuning.TILE * 0.5),
				float(d.width) * Tuning.TILE)
	AudioDirector.play("sfx_collapse", 0.75)

	cam.set_view(CameraDirector.View.GLIDE if launch.mode == LaunchController.Mode.GLIDE
			else CameraDirector.View.LAUNCH)
	_air_phase_fired = 0
	state = State.GATE_AIR if next_index >= stage.sectors.size() else State.AIR


## GDD 6.2 / 11.1: the four air beats. Launch, rise, apex, accelerating fall.
func _air_phase(phase: int) -> void:
	if launch.mode == LaunchController.Mode.GLIDE:
		cam.set_view(CameraDirector.View.GLIDE)
		if phase == 1:
			AudioDirector.play("sfx_wind_fall", 0.45)
		elif phase == 3:
			AudioDirector.play("sfx_wind_rise", 0.40)
		return

	match phase:
		1:
			cam.set_view(CameraDirector.View.AIR_RISE)
			anim.set_state(CharacterAnimator.State.LAUNCH, launch.grade)
			AudioDirector.play("sfx_wind_rise", 0.55)
		2:
			cam.set_view(CameraDirector.View.GATE if state == State.GATE_AIR
					else CameraDirector.View.APEX)
			anim.set_state(CharacterAnimator.State.APEX, launch.grade)
		3:
			cam.set_view(CameraDirector.View.FALL)
			anim.set_state(CharacterAnimator.State.FALL, launch.grade)
			AudioDirector.play("sfx_wind_fall", 0.5)


func _do_landing() -> void:
	var pos := launch.sample(launch.end_beat)
	AudioDirector.play("sfx_land", 0.9 if _last_grade != LaunchController.Grade.BAD else 1.0)
	vfx.landing(pos, _last_grade)
	cam.impulse(0.28, 12.0)
	anim.set_state(CharacterAnimator.State.LAND, _last_grade)

	if state == State.GATE_AIR:
		_arrive_at_gate(pos)
		return

	var next_index := _sector_index + 1
	if _sector_index < 0:
		next_index = 0
	_enter_ground(next_index, pos.x)


## GDD 21 / 31.11: the destination exists, you get there, the stage ends.
func _arrive_at_gate(pos: Vector3) -> void:
	state = State.ARRIVED
	player.position = pos
	player.release()
	anim.set_state(CharacterAnimator.State.CHEER)
	cam.set_view(CameraDirector.View.GATE)
	AudioDirector.set_act("Outro")
	backdrop.set_act("Outro")
	AudioDirector.play("sfx_gate", 0.9)
	bridge.collapse_everything_behind(0)
	AudioDirector.play("sfx_collapse", 1.0)
	hud.set_count(-1, false)
	get_tree().create_timer(3.4).timeout.connect(_show_results)


func _show_results() -> void:
	if state == State.RESULTS:
		return
	state = State.RESULTS
	var total := stage.sectors.size()
	var rank := "C"
	if _glides == 0 and _perfect >= int(total * 0.85):
		rank = "SS"
	elif _glides == 0:
		rank = "S"
	elif _glides <= 2:
		rank = "A"
	elif _glides <= 5:
		rank = "B"
	hud.show_results({
		"title": "DESERT BRIDGE ESCAPED",
		"launches": _launches,
		"sectors": total,
		"glides": _glides,
		"perfect": _perfect,
		"streak": _best_streak,
		"route": "HIGH" if _glides == 0 else "MAIN",
		"rank": rank,
	})


# ---------------------------------------------------------------------------
# frame update - all discrete events resolved against the audio clock
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var beat := BeatConductor.beat

	match state:
		State.FREE_MOVE:
			# Safety net: if the player never finds the charge, the bridge's own
			# demolition network wakes up anyway, so the stage always starts
			# inside the validated tempo window.
			if beat >= float(Tuning.ACCIDENT_GO_BEAT) - 8.0:
				_arm_charge(true)

		State.ARMED:
			if beat >= _accident_beat:
				_do_accident()

		State.GROUND:
			var elapsed := beat - _cycle_beat
			var want := clampi(int(floor(elapsed)), 0, 3)
			while _damage_fired < want:
				_damage_fired += 1
				_apply_damage(_damage_fired)
			if elapsed >= float(Tuning.GROUND_BEATS):
				_resolve_go()
			else:
				_follow_deck()
				var pip := clampi(int(floor(elapsed)), 0, 3)
				hud.set_count(pip, pip == 3)
				if _auto_play:
					_auto_step()

		State.ACCIDENT_AIR, State.AIR, State.GATE_AIR:
			var air_elapsed := beat - launch.go_beat
			var want_phase := clampi(int(floor(air_elapsed)), 0, 3)
			while _air_phase_fired < want_phase:
				_air_phase_fired += 1
				_air_phase(_air_phase_fired)
			if air_elapsed >= float(Tuning.AIR_BEATS):
				_do_landing()
			else:
				player.position = launch.sample(beat)
				hud.set_count(want_phase, want_phase == 3)

	_update_debug(beat)
	_service_shots(beat)


## The deck the player is standing on sinks and leans as it fails, and the
## player goes with it (GDD 6.1).
func _follow_deck() -> void:
	var sec := bridge.sector(_sector_index)
	if sec != null:
		player.origin.y = sec.position.y


func _update_debug(beat: float) -> void:
	if hud == null or not hud.show_debug:
		return
	var sid := "-"
	if _sector_index >= 0 and _sector_index < stage.sectors.size():
		sid = stage.sectors[_sector_index].id
	hud.set_debug_text("\n".join([
		"state %s   beat %.2f   bpm %.0f   %s" % [State.keys()[state], beat,
				BeatConductor.bpm(),
				"FALLBACK CLOCK" if BeatConductor.using_fallback_clock() else "audio clock"],
		"sector %s (%d/%d)   cell %s   cycle GO @ %.0f" % [sid, _sector_index + 1,
				stage.sectors.size(), player.cell, _cycle_beat + Tuning.GROUND_BEATS],
		"launches %d  glides %d  perfect %d  streak %d" % [_launches, _glides, _perfect, _streak],
	]))


# ---------------------------------------------------------------------------
# input plumbing
# ---------------------------------------------------------------------------

func _on_dash_started(dir: Vector2i, _to: Vector2i) -> void:
	anim.notify_dash(dir)
	anim.set_state(CharacterAnimator.State.DASH)
	AudioDirector.play("sfx_dash", 0.45, 1.0, 0.10)


func _on_dash_arrived(cell: Vector2i) -> void:
	AudioDirector.play("sfx_step", 0.40, 1.0, 0.12)
	var d := player.dash_dir()
	vfx.dash_puff(player.global_position, Vector3(float(d.x), 0.0, -float(d.y)))
	_last_arrival_song_time = BeatConductor.song_time

	if state == State.FREE_MOVE and cell == Stage1Data.INTRO_MINE:
		_arm_charge(false)


func _on_dash_rejected(_dir: Vector2i) -> void:
	AudioDirector.play("sfx_reject", 0.35, 1.0, 0.08)


func _on_pause_toggled(paused: bool) -> void:
	get_tree().paused = paused
	AudioDirector.set_paused(paused)


func _restart() -> void:
	get_tree().paused = false
	AudioDirector.set_paused(false)
	BeatConductor.stop()
	get_tree().reload_current_scene()






