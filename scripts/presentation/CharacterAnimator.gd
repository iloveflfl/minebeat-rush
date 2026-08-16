class_name CharacterAnimator
extends Node3D

## GDD 14 - the fennec: a drawn character, jointed, standing up in the 3D world.
##
## The concept sheet is reference. The character itself is *drawn here*, out of
## closed vector shapes (see FoxArt), because every attempt to slice the sheet
## into moving parts failed the same way: a cut through a picture leaves a
## straight edge, and whatever the cut concealed does not exist. Rotate a cut-out
## ear and the head has a hole. Sink the head to hide the hole and the neck reads
## as severed. Hide the cut by clamping the joint and you have concealment rather
## than a rig.
##
## Rebuilt as shapes, none of that can happen: parts overlap instead of abutting,
## every piece carries its own ink outline all the way round, and a joint can
## travel as far as the pose asks. It also finally buys real arms, legs and a
## tail, which is what "the pose is always the same" was really about.
##
## Motion is springs, not lerps - a lerp arrives and stops, a spring overshoots
## and settles, and that is what reads as weight. On top of the authored poses
## sit the follow-through channels, and per GDD 14.2 [LOCK] those only ever
## follow: they never drive the pose or the cell the player stands on.

enum State { IDLE, DASH, ARMED, LAUNCH, APEX, FALL, LAND, GLIDE, CHEER }

## Scale of the drawing in metres, against a 2 m tile.
##
## Not the character's actual height: the art is laid out over a unit box and
## only fills the top three quarters of it, so the figure stands about 0.78 of
## this. At 2.30 that came to 1.8 m, and on a five-wide board the reading camera
## has to frame ten metres - which left the fennec sixty pixels tall at 720p no
## matter how well it was drawn. Scaled up it reads at playing distance, and
## being taller than one tile is normal for the genre rather than a collision
## problem: the rig has no collider, and its ground height comes from the cell
## it stands on.
const FIGURE_H := 2.95


class Spring:
	var v := 0.0
	var vel := 0.0
	func step(target: float, stiff: float, damp: float, dt: float) -> float:
		vel += ((target - v) * stiff - vel * damp) * dt
		v += vel * dt
		return v
	func snap(x: float) -> void:
		v = x
		vel = 0.0


var state: State = State.IDLE
var grade: LaunchController.Grade = LaunchController.Grade.PERFECT

# --- rig --------------------------------------------------------------------
var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _neck: Node3D
var _head: Node3D
var _ears: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _tail: Node3D
var _scarf_ends: Array[Node3D] = []
var _eyes: Dictionary = {}          ## expression -> Node3D
var _mouths: Dictionary = {}
var _shadow: MeshInstance3D
var _face := "happy"

# --- animation channels -----------------------------------------------------
var _s_lean := Spring.new()
var _s_squash := Spring.new()
var _s_rise := Spring.new()
var _s_head := Spring.new()
var _s_ear := Spring.new()          ## +1 straight up, -1 swept back
var _s_fan := Spring.new()          ## ears splayed outward
var _s_arm := Spring.new()          ## -1 back, 0 rest, +1 up and out
var _s_leg := Spring.new()          ## 0 straight, 1 tucked
## Asymmetry, in degrees, added to one side and subtracted from the other.
##
## Everything else in the rig is mirrored, and a perfectly mirrored figure looks
## the same in every pose no matter what the other channels do - which is what
## made three different apex "takes" read as one pose with three faces. Breaking
## the mirror is what turns a shape into a pose.
var _s_asym := Spring.new()
var _ear_lag := [Spring.new(), Spring.new()]
var _tail_lag := Spring.new()
var _head_lag := Spring.new()

var _facing := 1.0
var _want_facing := 1.0
var _pinch := 1.0
var _prev_global := Vector3.ZERO
var _velocity := Vector3.ZERO
var _dash_dir := Vector3.ZERO
var _dash_t := 99.0
var _state_t := 0.0
var _time := 0.0
var _anticipate := 0.0
var _hitstop := 0.0
var _variant := 0
var _idle_beat := 0.0
var _flick := 0.0


func _ready() -> void:
	_build()
	_prev_global = global_position
	_s_ear.snap(1.0)


# ---------------------------------------------------------------------------
# construction - proportions measured off the concept sheet
# ---------------------------------------------------------------------------

func _build() -> void:
	var S := FIGURE_H

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.17 * S, 0)
	_rig.add_child(_hips)

	# --- legs ---------------------------------------------------------------
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		# Set wider apart than their own radius. Closer together than that, the two
		# outlines cross in the crotch and the legs read as a drawn X.
		leg.position = Vector3(sx * 0.066 * S, 0, 0)
		_hips.add_child(leg)
		FoxArt.shape(leg, FoxArt.limb(Vector2(0, 0), Vector2(0, -0.148), 0.043, 0.036),
				FoxArt.FUR, S, -0.004)
		FoxArt.shape(leg, FoxArt.ellipse(Vector2(0, -0.162), Vector2(0.050, 0.028), 18),
				FoxArt.BELLY, S, -0.003)
		_legs.append(leg)

	# --- tail ----------------------------------------------------------------
	# Anchored at the hips and drawn first, so it sweeps out from behind the
	# body. Hung off the torso it rode up to shoulder height and read as a
	# balloon on a string.
	_tail = Node3D.new()
	_tail.position = Vector3(0.058 * S, 0.020 * S, -0.020)
	_hips.add_child(_tail)
	# Thick at the root and barely tapering: a fennec's tail is a brush. Drawn
	# as a thin stem with a round tip on the end it read as a lollipop.
	FoxArt.shape(_tail, FoxArt.sweep(Vector2(0, 0), Vector2(0.130, -0.010),
			Vector2(0.185, 0.120), 0.054, 0.082), FoxArt.FUR, S, 0.0)
	# The tip is a rounded cap that swallows the whole end of the brush. Drawn
	# smaller it sat on the tail like a ball on a stick, and its outline crossed
	# the fur in a straight line that read as a cut.
	FoxArt.detail(_tail, FoxArt.blob(Vector2(0.183, 0.122), Vector2(0.086, 0.080), 30,
			0, 0.0, 0.0), FoxArt.TAIL_TIP, S, 0.001)

	# --- torso ---------------------------------------------------------------
	_torso = Node3D.new()
	_hips.add_child(_torso)
	FoxArt.shape(_torso, FoxArt.blob(Vector2(0, 0.115), Vector2(0.105, 0.135), 44),
			FoxArt.FUR, S, 0.0)
	FoxArt.detail(_torso, FoxArt.ellipse(Vector2(0, 0.090), Vector2(0.068, 0.098), 26),
			FoxArt.BELLY, S, 0.002)

	# --- scarf: a band at the throat with two short tails on the chest -------
	# The tails used to run the whole height of the torso, which stopped reading
	# as a scarf and started reading as an open red jacket.
	for sx3 in [-1.0, 1.0]:
		var end := Node3D.new()
		end.position = Vector3(sx3 * 0.034 * S, 0.252 * S, 0)
		_torso.add_child(end)
		FoxArt.shape(end, FoxArt.sweep(Vector2(0, 0), Vector2(sx3 * 0.022, -0.055),
				Vector2(sx3 * 0.020, -0.112), 0.026, 0.016),
				FoxArt.SCARF, S, 0.006)
		_scarf_ends.append(end)
	FoxArt.shape(_torso, FoxArt.blob(Vector2(0, 0.265), Vector2(0.098, 0.040), 30),
			FoxArt.SCARF, S, 0.008)
	FoxArt.detail(_torso, FoxArt.ellipse(Vector2(0, 0.252), Vector2(0.079, 0.019), 20),
			FoxArt.SCARF_DARK, S, 0.009)

	# --- arms ----------------------------------------------------------------
	# In front of the scarf tails. Behind them the arms were completely hidden,
	# and the figure looked armless in every shot.
	for sx2 in [-1.0, 1.0]:
		var arm := Node3D.new()
		# The shoulder pivot has to sit *inside* the torso outline. Anchored out
		# at the silhouette's edge it looked fine hanging down and tore open a
		# gap the moment the arm swung out - the limb read as detached.
		arm.position = Vector3(sx2 * 0.070 * S, 0.188 * S, 0)
		_torso.add_child(arm)
		FoxArt.shape(arm, FoxArt.limb(Vector2(0, 0), Vector2(0, -0.088), 0.030, 0.034),
				FoxArt.FUR, S, 0.012)
		_arms.append(arm)

	# --- head ----------------------------------------------------------------
	# Sits well in front of everything on the body. Depth here is draw order, and
	# without the gap the scarf band paints straight over the face.
	_neck = Node3D.new()
	_neck.position = Vector3(0, 0.375 * S, 0.030)
	_torso.add_child(_neck)
	_head = Node3D.new()
	_head_build(S)

	_build_shadow()


## Draw order inside the head.
##
## These are painter's order, not anatomy, and getting them wrong is subtle in a
## way that costs whole iterations: at one point the scarf band was painting
## straight across the face, and the eyes were buried a thousandth of a unit
## behind the muzzle - both looked like modelling mistakes and neither was one.
## Naming the layers makes the stacking something you can read off the file.
class Z:
	const EAR := -0.010
	const SKULL := 0.000
	const BLUSH := 0.004
	const MUZZLE := 0.006
	const EYE := 0.010
	const MOUTH := 0.011
	const LID := 0.013
	const NOSE := 0.014
	## Centre of the skull in head-local units, so the face can be laid out
	## relative to it instead of by trial and error.
	const skull_y := 0.055


func _head_build(S: float) -> void:
	_neck.add_child(_head)

	# Ears first so they sit behind the skull - the head's own outline then
	# closes over where they meet it, which is how a drawing hides a joint.
	# Ears are nearly half the animal on the reference, and almost as wide as the
	# skull. They go in first so the skull's outline closes over their roots.
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(sx * 0.078 * S, 0.062 * S, Z.EAR)
		_head.add_child(ear)
		# A fennec's ears are broad and splayed, not tall and parallel. At 0.47
		# high and 0.175 wide they stood straight up like a rabbit's.
		FoxArt.shape(ear, FoxArt.teardrop(Vector2(0, -0.055), 0.210, 0.345),
				FoxArt.FUR, S, 0.0)
		FoxArt.detail(ear, FoxArt.teardrop(Vector2(0, -0.020), 0.122, 0.272),
				FoxArt.EAR_INNER, S, 0.002)
		FoxArt.detail(ear, FoxArt.teardrop(Vector2(0, 0.008), 0.064, 0.196),
				FoxArt.EAR_DEEP, S, 0.003)
		ear.rotation_degrees.z = -sx * 15.0
		_ears.append(ear)

	# Skull. The tufts are a gentle waver in the outline, not scallops - at 40
	# segments against 11 bumps the two frequencies beat against each other and
	# the head came out faceted, like something chipped from stone.
	FoxArt.shape(_head, FoxArt.blob(Vector2(0, Z.skull_y), Vector2(0.145, 0.134), 72, 9,
			0.026, 0.55), FoxArt.FUR, S, Z.SKULL)
	for sx2 in [-1.0, 1.0]:
		FoxArt.detail(_head, FoxArt.ellipse(Vector2(sx2 * 0.098, 0.022),
				Vector2(0.030, 0.017), 16), FoxArt.BLUSH, S, Z.BLUSH)
	# The muzzle is a small pale wedge low on the face. Drawn any larger it stops
	# reading as a snout and becomes a mask over the whole head.
	FoxArt.detail(_head, FoxArt.ellipse(Vector2(0, 0.006), Vector2(0.068, 0.046), 28),
			FoxArt.BELLY, S, Z.MUZZLE)
	FoxArt.shape(_head, FoxArt.ellipse(Vector2(0, 0.030), Vector2(0.017, 0.012), 14),
			FoxArt.NOSE, S, Z.NOSE, 0.005)

	# --- expressions: one set of eyes and one mouth per mood ----------------
	for name in ["happy", "surprised", "determined", "worried"]:
		var eyes := Node3D.new()
		_head.add_child(eyes)
		_eyes[name] = eyes
		var mouth := Node3D.new()
		_head.add_child(mouth)
		_mouths[name] = mouth
		for sx3 in [-1.0, 1.0]:
			# Sat well above the muzzle. The reference puts the eyes on the upper
			# third of the skull, and it is what keeps the face babyish.
			var at := Vector2(sx3 * 0.058, 0.080)
			match name:
				"happy":
					# Closed and arched with delight: the lower half of an ellipse,
					# which triangulates to the lens shape between arc and chord.
					FoxArt.detail(eyes, FoxArt.ellipse(at + Vector2(0, 0.004),
							Vector2(0.032, 0.026), 22, 200, 340), FoxArt.EYE, S, Z.EYE)
				"surprised":
					FoxArt.detail(eyes, FoxArt.ellipse(at, Vector2(0.029, 0.034), 22),
							FoxArt.EYE, S, Z.EYE)
					FoxArt.detail(eyes, FoxArt.ellipse(at + Vector2(sx3 * 0.009, 0.012),
							Vector2(0.010, 0.012), 14), FoxArt.EYE_LIGHT, S, Z.MOUTH)
				"determined":
					FoxArt.detail(eyes, FoxArt.ellipse(at, Vector2(0.028, 0.029), 22),
							FoxArt.EYE, S, Z.EYE)
					FoxArt.detail(eyes, FoxArt.ellipse(at + Vector2(sx3 * 0.009, 0.010),
							Vector2(0.009, 0.010), 14), FoxArt.EYE_LIGHT, S, Z.MOUTH)
					# The angry lid: a fur-coloured disc laid over the top of the eye
					# and tilted in, so the eye is narrowed rather than redrawn.
					var brow := FoxArt.ellipse(at + Vector2(0, 0.028),
							Vector2(0.042, 0.028), 20)
					var lid := FoxArt.detail(eyes, brow, FoxArt.FUR, S, Z.LID)
					lid.rotation_degrees.z = sx3 * 22.0
				"worried":
					FoxArt.detail(eyes, FoxArt.ellipse(at, Vector2(0.027, 0.031), 22),
							FoxArt.EYE, S, Z.EYE)
					FoxArt.detail(eyes, FoxArt.ellipse(at + Vector2(sx3 * 0.008, 0.010),
							Vector2(0.009, 0.011), 14), FoxArt.EYE_LIGHT, S, Z.MOUTH)
					var lid2 := FoxArt.detail(eyes, FoxArt.ellipse(
							at + Vector2(0, 0.030), Vector2(0.040, 0.028), 20),
							FoxArt.FUR, S, Z.LID)
					lid2.rotation_degrees.z = -sx3 * 18.0
		# Mouths sit on the muzzle, under the nose.
		match name:
			"happy":
				FoxArt.shape(mouth, FoxArt.ellipse(Vector2(0, 0.012),
						Vector2(0.021, 0.019), 22, 190, 350), FoxArt.NOSE.darkened(0.35),
						S, Z.MOUTH, 0.004)
			"surprised":
				FoxArt.shape(mouth, FoxArt.ellipse(Vector2(0, 0.010),
						Vector2(0.013, 0.015), 18), FoxArt.NOSE.darkened(0.4),
						S, Z.MOUTH, 0.004)
			"determined":
				FoxArt.shape(mouth, FoxArt.limb(Vector2(-0.018, 0.012),
						Vector2(0.018, 0.012), 0.004, 0.004, 6),
						FoxArt.EYE, S, Z.MOUTH, 0.0)
			"worried":
				FoxArt.shape(mouth, FoxArt.ellipse(Vector2(0, 0.022),
						Vector2(0.019, 0.016), 22, 10, 170), FoxArt.EYE, S, Z.MOUTH, 0.0)
	_set_face("happy")


func _build_shadow() -> void:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.26, 0.17, 0.24, 0.32)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.02
	disc.radial_segments = 18
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = sm
	_shadow.top_level = true
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

func set_state(s: State, g: LaunchController.Grade = LaunchController.Grade.PERFECT) -> void:
	if s != state:
		_state_t = 0.0
		# Never the same take twice running. A uniform draw repeats a third of
		# the time, and a repeat is exactly what the player reads as "it always
		# does the same thing" - the one impression the variety is there to
		# avoid. Picking from the other two guarantees consecutive jumps differ.
		_variant = (_variant + 1 + randi() % 2) % 3
		if s == State.LAUNCH:
			_anticipate = 0.08
	state = s
	grade = g
	_set_face(_face_for(s, g))


func hit_stop(seconds: float) -> void:
	_hitstop = maxf(_hitstop, seconds)


func notify_dash(dir: Vector2i) -> void:
	_dash_dir = Vector3(float(dir.x), 0.0, -float(dir.y))
	_dash_t = 0.0
	_anticipate = 0.04
	if dir.x != 0:
		_want_facing = 1.0 if dir.x > 0 else -1.0


func _face_for(s: State, g: LaunchController.Grade) -> String:
	match s:
		State.ARMED: return "surprised"
		State.LAUNCH: return "determined" if _variant != 2 else "surprised"
		State.APEX:
			if g == LaunchController.Grade.PERFECT:
				return ["happy", "determined", "happy"][_variant]
			return "surprised" if _variant == 0 else "worried"
		State.FALL: return "surprised" if _variant != 1 else "worried"
		State.LAND: return "worried" if g == LaunchController.Grade.BAD else "happy"
		State.GLIDE: return "worried"
		State.CHEER: return "happy"
		State.DASH: return "determined"
	return "happy"


func _set_face(name: String) -> void:
	if not _eyes.has(name):
		return
	_face = name
	for k in _eyes:
		(_eyes[k] as Node3D).visible = k == name
		(_mouths[k] as Node3D).visible = k == name


# ---------------------------------------------------------------------------
# per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := clampf(delta, 1.0 / 240.0, 1.0 / 24.0)
	_time += dt
	_dash_t += dt
	_state_t += dt
	_anticipate = maxf(0.0, _anticipate - dt)

	var g := global_position
	if delta > 0.0:
		_velocity = _velocity.lerp((g - _prev_global) / delta, 0.35)
	_prev_global = g

	if state == State.DASH and _dash_t > 0.30:
		set_state(State.IDLE)

	if _hitstop > 0.0:
		_hitstop -= dt
		_apply(dt)
		return

	_drive(dt)
	_apply(dt)
	_follow_through(dt)


func _drive(dt: float) -> void:
	var lean := 0.0
	var squash := 0.0
	var rise := 0.0
	var head := 0.0
	var ear := 1.0
	var fan := 0.0
	var arm := 0.0
	var leg := 0.15
	var asym := 0.0
	var stiff := 180.0
	var damp := 17.0

	match state:
		State.IDLE:
			squash = sin(_time * 3.0) * 0.045
			head = sin(_time * 0.8) * 4.0
			ear = 1.0 + sin(_time * 2.2) * 0.06
			_idle_beat -= dt
			if _idle_beat <= 0.0:
				_idle_beat = randf_range(1.4, 3.2)
				_flick = 1.0
				_variant = randi() % 3
			_flick = maxf(0.0, _flick - dt * 2.4)
			match _variant:
				0: ear += _flick * 1.1
				1: head += _flick * 24.0
				_: arm = _flick * 0.5
			stiff = 90.0

		State.DASH:
			var into := clampf(1.0 - _dash_t / Tuning.DASH_TIME, 0.0, 1.0)
			lean = -_dash_dir.x * 30.0 * into
			squash = 0.40 * into
			head = _dash_dir.x * 18.0 * into
			ear = -0.9
			arm = -0.9
			leg = 0.05
			stiff = 340.0
			damp = 21.0

		State.ARMED:
			squash = -0.10
			lean = sin(_time * 22.0) * 2.6
			head = 6.0
			ear = 1.35
			arm = 0.35
			leg = 0.55
			stiff = 260.0

		State.LAUNCH:
			squash = 0.85 if grade == LaunchController.Grade.PERFECT else 0.55
			rise = 0.08
			head = -12.0
			ear = -1.0
			arm = -1.0
			leg = 0.0
			asym = [18.0, -24.0, 6.0][_variant]
			if grade == LaunchController.Grade.BAD:
				lean = 34.0
			stiff = 430.0
			damp = 20.0

		State.APEX:
			# The pose the jump exists to show, in three takes. Each take has to
			# differ in the silhouette, not only in the face - a mirrored figure
			# with a different expression is still the same pose.
			squash = -0.18
			rise = 0.04
			head = -18.0
			ear = 0.5
			fan = 1.0
			arm = 1.0
			leg = 0.85
			match _variant:
				0:
					# Airborne cheer: one arm punched up, the other trailing.
					lean = -6.0 + sin(_time * 2.2) * 5.0
					asym = 46.0
				1:
					# Tucked and proud: both arms up, body arched back.
					squash = -0.26
					head = -26.0
					arm = 1.0
					asym = -14.0
				_:
					# Cocky back-lean with one leg kicked out.
					lean = 16.0
					head = -8.0
					arm = 0.45
					leg = 0.45
					asym = -52.0
			if grade == LaunchController.Grade.BAD:
				lean = 150.0 * sin(_time * 2.4)
				fan = 0.4
				arm = -0.3
				asym = 30.0 * sin(_time * 3.1)
			stiff = 110.0
			damp = 12.0

		State.FALL:
			squash = 0.34
			lean = 8.0
			head = 14.0
			ear = 1.1
			arm = -0.7
			leg = 0.3
			asym = [22.0, -30.0, 8.0][_variant]
			if grade == LaunchController.Grade.BAD:
				lean = 240.0 * sin(_time * 2.1)
				asym = 40.0 * sin(_time * 2.6)
			stiff = 150.0

		State.LAND:
			var lu := clampf(_state_t / 0.22, 0.0, 1.0)
			var punch := (1.0 - lu) * (1.0 - lu)
			squash = -0.62 * punch
			ear = 1.0 - 2.4 * punch
			fan = 0.8 * punch
			arm = 0.6 * punch
			leg = 0.15 + 0.7 * punch
			asym = [26.0, -34.0, 12.0][_variant] * punch
			if grade == LaunchController.Grade.BAD:
				lean = 44.0 * punch
			stiff = 300.0
			damp = 14.0

		State.GLIDE:
			squash = -0.24
			lean = sin(_time * 2.7) * 24.0
			head = sin(_time * 3.3) * 12.0
			ear = 0.15
			fan = 1.0
			arm = 1.0
			leg = 0.25
			# Windmilling: the two arms are a quarter-cycle apart, which is what
			# flailing looks like and what mirrored arms can never look like.
			asym = sin(_time * 5.1) * 38.0
			stiff = 70.0
			damp = 10.0

		State.CHEER:
			var hop := absf(sin(_time * 4.2))
			squash = -0.10 + hop * 0.34
			rise = hop * 0.14
			head = -12.0
			ear = 1.25
			fan = 0.4
			arm = 1.0
			asym = sin(_time * 4.2) * 30.0
			stiff = 130.0

	if _anticipate > 0.0:
		squash = -0.40
		rise = -0.04
		ear = 1.4
		leg = 0.85
		arm = -0.4
		lean *= -0.3

	_s_lean.step(lean, stiff, damp, dt)
	_s_squash.step(squash, stiff, damp, dt)
	_s_rise.step(rise, stiff, damp, dt)
	_s_head.step(head, stiff * 0.6, damp * 0.9, dt)
	_s_ear.step(ear, stiff * 0.5, damp * 0.8, dt)
	_s_fan.step(fan, stiff * 0.6, damp, dt)
	_s_arm.step(arm, stiff * 0.7, damp, dt)
	_s_leg.step(leg, stiff * 0.8, damp, dt)
	_s_asym.step(asym, stiff * 0.55, damp * 0.9, dt)


func _apply(dt: float) -> void:
	# The paper turn: squash flat, flip, spring back.
	var pinch_target := 1.0 if _facing == _want_facing else 0.0
	_pinch = move_toward(_pinch, pinch_target, dt * 11.0)
	if _pinch <= 0.03 and _facing != _want_facing:
		_facing = _want_facing
	if _facing == _want_facing:
		_pinch = move_toward(_pinch, 1.0, dt * 11.0)

	# Volume-preserving squash and stretch, but on the body only.
	#
	# Run over the whole rig at +-60% it turned the fennec into a noodle at the
	# top of every jump: the skull stretched into an egg and the face with it.
	# Animators stretch the body and hold the head, because the head is what the
	# player is actually reading. So the scale goes on the hips and the neck
	# carries the exact inverse - the head rides higher and lower with the
	# stretch but never changes shape.
	var sy := 1.0 + clampf(_s_squash.v, -0.8, 0.9) * 0.30
	var sx := 1.0 / maxf(0.4, sy)
	_hips.scale = Vector3(sx, sy, 1.0)
	_neck.scale = Vector3(1.0 / sx, 1.0 / sy, 1.0)
	# Facing and the paper turn stay on the rig, where they flip the whole figure.
	_rig.scale = Vector3(maxf(0.02, _pinch) * _facing, 1.0, 1.0)
	_rig.rotation_degrees = Vector3(0, 0, _s_lean.v)
	# Scaling about the hips also scales the legs, so a squash would lift the
	# feet clear of the deck and a stretch would push them through it. On the
	# ground the rig drops by exactly what the legs lost, which keeps the soles
	# planted no matter how hard the body compresses.
	var planted := state in [State.IDLE, State.ARMED, State.LAND, State.DASH,
			State.CHEER]
	var foot_fix := (sy - 1.0) * 0.162 * FIGURE_H if planted else 0.0
	_rig.position.y = _s_rise.v * FIGURE_H + foot_fix

	_head.rotation_degrees.z = _s_head.v + _head_lag.v

	# The asymmetry bias is deliberately *not* multiplied by the side sign. That
	# is the whole point: multiplying by the sign would mirror it and leave the
	# figure as symmetric as before. Added flat, it swings both limbs the same
	# way on screen, which is how one arm ends up over the head while the other
	# trails behind. The trailing limb takes less of it than the leading one, so
	# the two never look like a single rigid piece.
	for i in _legs.size():
		var lsx := -1.0 if i == 0 else 1.0
		var splay := 10.0 + 46.0 * _s_leg.v * (0.4 + 0.6 * _s_fan.v)
		_legs[i].rotation_degrees.z = lsx * splay \
				+ _s_asym.v * (0.50 if i == 1 else -0.18)
		_legs[i].position.y = -0.04 * FIGURE_H * _s_leg.v

	for i in _arms.size():
		var asx := -1.0 if i == 0 else 1.0
		var a := _s_arm.v
		var swing := (16.0 + 120.0 * maxf(0.0, a) * (0.45 + 0.55 * _s_fan.v)) \
				- 50.0 * maxf(0.0, -a)
		_arms[i].rotation_degrees.z = asx * swing \
				+ _s_asym.v * (1.0 if i == 1 else -0.42)

	for i in _scarf_ends.size():
		var ssx := -1.0 if i == 0 else 1.0
		_scarf_ends[i].rotation_degrees.z = ssx * (6.0 + 26.0 * _s_fan.v) \
				+ clampf(-_velocity.y * 2.2, -34.0, 34.0) * 0.4 \
				+ sin(_time * 3.4 + float(i) * 1.9) * 4.0

	var deck_y := _deck_y()
	var lift: float = maxf(0.0, global_position.y - deck_y)
	var f := clampf(1.0 - lift / 7.0, 0.0, 1.0)
	_shadow.visible = f > 0.02
	_shadow.global_position = Vector3(global_position.x, deck_y + 0.035, global_position.z)
	_shadow.scale = Vector3(0.6 + 0.4 * f, 1.0, 0.5 + 0.4 * f)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = 0.32 * f


func _deck_y() -> float:
	var p := get_parent()
	if p is PlayerMotor:
		var pm := p as PlayerMotor
		return pm.origin.y + pm.surface_height(pm.cell)
	return 0.0


## GDD 14.2 [LOCK]: ears, head and tail only ever follow the body.
func _follow_through(dt: float) -> void:
	_head_lag.step(clampf(-_velocity.x * 2.2, -24.0, 24.0), 130.0, 14.0, dt)

	var vert := clampf(-_velocity.y * 1.5, -55.0, 55.0)
	var lat := clampf(-_velocity.x * 2.6, -45.0, 45.0)
	for i in _ears.size():
		var sx := -1.0 if i == 0 else 1.0
		var lag: float = _ear_lag[i].step(vert * 0.55 + lat * 0.45, 110.0, 12.0, dt)
		# Straight up when alert, swept right back when moving fast, fanned wide
		# at the apex. The shapes are complete, so this can go as far as it likes.
		var base := lerpf(58.0, -10.0, clampf(_s_ear.v * 0.5 + 0.5, 0.0, 1.0))
		var twitch := sin(_time * 5.4 + float(i) * 1.7) * 1.5
		_ears[i].rotation_degrees.z = -sx * (base * 0.42 + _s_fan.v * 30.0) \
				+ lag * 0.35 + twitch

	var whip: float = _tail_lag.step(clampf(-_velocity.y * 3.0, -60.0, 60.0)
			- _s_lean.v * 0.6, 95.0, 11.0, dt)
	_tail.rotation_degrees.z = -18.0 + whip * 0.5 + _s_fan.v * 24.0 \
			+ sin(_time * 2.6) * 5.0
