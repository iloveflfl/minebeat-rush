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
var _shadow: MeshInstance3D
var _face := "happy"

# --- the face, as parameters rather than as a set of pictures ---------------
var _eye_sockets: Array[Node3D] = []
var _eye_pieces: Array[FoxFace.Piece] = []
var _iris_pieces: Array[FoxFace.Piece] = []
var _shine_pieces: Array[FoxFace.Piece] = []
var _lid_pieces: Array[FoxFace.Piece] = []
var _mouth_piece: FoxFace.Piece
## Expression parameters. Each is sprung, so an expression change is a move
## through the space between two faces rather than a cut between them.
var _p_open := Spring.new()         ## eye aperture
var _p_bow := Spring.new()          ## eye centre line arched up: the ^^ squint
var _p_lid := Spring.new()          ## brow angle, + angry / - worried
var _p_mopen := Spring.new()        ## jaw
var _p_smile := Spring.new()        ## mouth corners, + up / - down

# --- involuntary motion ------------------------------------------------------
var _blink := FoxLife.Blink.new()
var _gaze := FoxLife.Gaze.new()
var _breath := FoxLife.Breath.new()
## Extra look direction supplied by the director, on top of the state's own.
var _look_hint := Vector2.ZERO

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

# --- parts that bend rather than pivot ---------------------------------------
var _collar: Node3D
var _ear_parts: Array[FoxPuppet.BendPart] = []
var _scarf_parts: Array[FoxPuppet.BendPart] = []
var _ear_strands: Array[FoxChain.Strand] = []
var _ear_ribbons: Array[FoxChain.Ribbon] = []
var _tail_strand: FoxChain.Strand
var _tail_ribbon: FoxChain.Ribbon
var _scarf_strands: Array[FoxChain.Strand] = []
var _scarf_ribbons: Array[FoxChain.Ribbon] = []
## Last frame's velocity, differenced to get the acceleration the strands feel.
var _prev_velocity := Vector3.ZERO

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
	var s := FoxPuppet.scale_for(S)
	var b := FoxPuppet.boxes()

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	# Joints, in the drawing's own pixels. Every one of these was read off a
	# labelled grid of the panel rather than estimated, and they are the places
	# the animal actually bends: the hip line, the shoulder each folded forepaw
	# hangs from, the throat the head turns on.
	var feet := Vector2(FoxPuppet.centre_x(), FoxPuppet.floor_y())
	var hips := Vector2(197.0, 470.0)
	var neck := Vector2(193.0, 302.0)
	var sho := [Vector2(180.0, 336.0), Vector2(224.0, 334.0)]
	var hip_j := [Vector2(176.0, 428.0), Vector2(218.0, 428.0)]

	_hips = Node3D.new()
	var fl := FoxPuppet.to_local(feet, s)
	_hips.position = Vector3(fl.x, fl.y, 0)
	_rig.add_child(_hips)

	# Back to front. The order is the rig: a leg's cut root is hidden because
	# the torso is drawn over it, so nothing has to be painted back in.
	_tail = FoxPuppet.quad(_hips, "tail", Vector2(200.0, 450.0), feet, s, -0.030)

	_legs.clear()
	for i in 2:
		var nm := "leg_l" if i == 0 else "leg_r"
		var leg := FoxPuppet.quad(_hips, nm, hip_j[i], feet, s,
				-0.014 + float(i) * 0.002)
		_legs.append(leg)

	_torso = FoxPuppet.quad(_hips, "torso", hips, feet, s, 0.0)

	_scarf_ends.clear()
	for part in ["scarf_end_l", "scarf_end_r"]:
		var end := FoxPuppet.BendPart.new(_torso, part, hips, s, 0.018, 0.06)
		_scarf_strands.append(end.strand)
		_scarf_parts.append(end)

	# In front of the scarf. Behind it the forepaws were completely covered, so
	# the one limb with the largest swing in the whole rig moved invisibly - the
	# same layering mistake that made the vector version look armless.
	_arms.clear()
	for j in 2:
		var nmp := "paw_l" if j == 0 else "paw_r"
		var paw := FoxPuppet.quad(_torso, nmp, sho[j], hips, s,
				0.026 + float(j) * 0.002)
		_arms.append(paw)

	_neck = Node3D.new()
	var nl := FoxPuppet.to_local(neck, s) - FoxPuppet.to_local(hips, s)
	_neck.position = Vector3(nl.x, nl.y, 0.030)
	_torso.add_child(_neck)

	_ears.clear()
	for part2 in ["ear_l", "ear_r"]:
		var ear := FoxPuppet.BendPart.new(_neck, part2, neck, s, -0.012, 0.62)
		_ear_strands.append(ear.strand)
		_ear_parts.append(ear)

	_head = FoxPuppet.quad(_neck, "head", neck, neck, s, 0.004)
	_collar = FoxPuppet.quad(_torso, "scarf_collar", neck, hips, s, 0.048)

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
		ear.position = Vector3(sx * 0.062 * S, 0.075 * S, Z.EAR)
		_head.add_child(ear)
		# On the sheet the ears are as tall as the whole body and only gently
		# splayed. They are the character's silhouette, and they are simulated
		# rather than rotated: stiff enough to stand up, loose enough that the
		# tips lag a beat behind the head and overshoot when it stops.
		_ear_strands.append(FoxChain.Strand.new(
				FoxChain.arc(Vector2.ZERO, 90.0 - sx * 13.0, 90.0 - sx * 27.0,
						0.395, 6), 0.66))
		_ear_ribbons.append(FoxChain.Ribbon.new(ear, 0.0, true))
		_ears.append(ear)

	# Skull. The tufts are a gentle waver in the outline, not scallops - at 40
	# segments against 11 bumps the two frequencies beat against each other and
	# the head came out faceted, like something chipped from stone.
	FoxArt.shape(_head, FoxArt.blob(Vector2(0, Z.skull_y), Vector2(0.145, 0.134), 72, 9,
			0.026, 0.55), FoxArt.FUR, S, Z.SKULL)
	# Fur tufts: a spike between the ears and a spray on each cheek. They are
	# small and they are the difference between this fennec and a generic round
	# animal - the sheet draws them on every single view.
	_tuft(_head, Vector2(0, 0.176), 0.020, 0.050, 0.0, S)
	_tuft(_head, Vector2(-0.030, 0.172), 0.017, 0.040, 24.0, S)
	_tuft(_head, Vector2(0.030, 0.172), 0.017, 0.040, -24.0, S)
	for cheek in [-1.0, 1.0]:
		for k in 3:
			_tuft(_head, Vector2(cheek * (0.132 - k * 0.012), 0.085 - k * 0.045),
					0.015, 0.044, cheek * (98.0 - k * 12.0), S)
	for sx2 in [-1.0, 1.0]:
		FoxArt.detail(_head, FoxArt.ellipse(Vector2(sx2 * 0.098, 0.022),
				Vector2(0.030, 0.017), 16), FoxArt.BLUSH, S, Z.BLUSH)
	# The muzzle is a small pale wedge low on the face. Drawn any larger it stops
	# reading as a snout and becomes a mask over the whole head.
	FoxArt.detail(_head, FoxArt.ellipse(Vector2(0, 0.006), Vector2(0.068, 0.046), 28),
			FoxArt.BELLY, S, Z.MUZZLE)
	FoxArt.shape(_head, FoxArt.ellipse(Vector2(0, 0.030), Vector2(0.017, 0.012), 14),
			FoxArt.NOSE, S, Z.NOSE, 0.005)

	# --- the face -----------------------------------------------------------
	# One eye, one mouth, rebuilt from parameters every frame. There is no set
	# of expressions here to pick from: an expression is a point in the
	# parameter space and everything between two of them is a face too.
	for sx3 in [-1.0, 1.0]:
		var socket := Node3D.new()
		# Set high on the skull. The reference puts the eyes on the upper third,
		# and that is what keeps the face babyish rather than muzzle-forward.
		socket.position = Vector3(sx3 * 0.058 * S, 0.080 * S, 0)
		_head.add_child(socket)
		_eye_pieces.append(FoxFace.Piece.new(socket, FoxArt.EYE, Z.EYE))
		_iris_pieces.append(FoxFace.Piece.new(socket, FoxArt.IRIS, Z.EYE + 0.002))
		_shine_pieces.append(FoxFace.Piece.new(socket, FoxArt.EYE_LIGHT, Z.MOUTH))
		_lid_pieces.append(FoxFace.Piece.new(socket, FoxArt.FUR, Z.LID))
		_eye_sockets.append(socket)
	_mouth_piece = FoxFace.Piece.new(_head, FoxArt.NOSE.darkened(0.35), Z.MOUTH, 0.004)


## One spike of fur, laid so its base is buried in whatever it grows out of.
##
## Drawn behind the skull rather than on it: a tuft that sits on top reads as a
## sticker, and a tuft poking out from underneath reads as fur.
func _tuft(parent: Node3D, at: Vector2, w: float, len: float, deg: float,
		S: float) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(at.x * S, at.y * S, Z.SKULL - 0.002)
	holder.rotation_degrees.z = deg
	# Hairline ink. At the character's scale the standard outline weight is wider
	# than the tuft itself, and a row of them turns into one black smudge.
	FoxArt.shape(holder, FoxArt.teardrop(Vector2(0, -len * 0.45), w, len, 1.25),
			FoxArt.FUR, S, 0.0, 0.0045)


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
		# The eyes go to the new subject immediately, ahead of the body. Gaze
		# leads action in every animal, and getting that order right is most of
		# what makes a character look like it decided to move rather than like
		# it was moved.
		state = s
		_gaze.flick_to(_look_where() + _look_hint)
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


## An expression is five numbers: eye aperture, eye bow, brow angle, jaw, and
## mouth corners. Naming four points in that space keeps the calling code
## readable, but nothing stops the face from sitting between them, and springs
## mean it usually is.
const FACES := {
	"happy":      {"open": 0.05, "bow": 0.95, "lid":  0.0, "mopen": 0.42, "smile":  0.90},
	"surprised":  {"open": 1.00, "bow": 0.00, "lid": -0.15, "mopen": 0.85, "smile":  0.05},
	"determined": {"open": 0.72, "bow": 0.00, "lid":  1.00, "mopen": 0.06, "smile": -0.20},
	"worried":    {"open": 0.80, "bow": 0.00, "lid": -1.00, "mopen": 0.18, "smile": -0.75},
}


func _set_face(name: String) -> void:
	if not FACES.has(name):
		return
	if name != _face:
		# Cut on a blink. Animators hide a change of pose behind one because the
		# eye genuinely cannot see through it, and it costs nothing here.
		_blink.trigger()
	_face = name


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
	_step_face(dt)
	_step_strands(dt)


## Simulate and redraw everything that bends.
##
## The pseudo-force is the whole trick. Working in the rig's own frame, the
## strands' roots never move, so nothing would ever swing. Feeding the
## character's own acceleration back in with the sign flipped is exactly what a
## passenger feels in a braking car, and it is why the scarf streams behind on
## the way up and snaps forward at the top without a single authored frame.
func _step_strands(dt: float) -> void:
	if dt <= 0.0:
		return
	var accel := (_velocity - _prev_velocity) / maxf(dt, 0.0001)
	_prev_velocity = _velocity
	# Clamped, because a teleport between sectors produces an acceleration that
	# would fire the scarf off into the next canyon.
	if accel.length() > 90.0:
		accel = accel.normalized() * 90.0
	var flip := _facing

	for e in _ear_parts:
		# Ears are light, so they feel their own motion far more than gravity.
		e.strand.step(dt, Vector2(-accel.x * flip * 0.30,
				-accel.y * 0.30 + _s_ear.v * 0.9), Vector2(0, -2.2))
		e.draw()

	for sc in _scarf_parts:
		# Cloth: it barely resists, so it is almost entirely the character's
		# own motion made visible.
		sc.strand.step(dt, Vector2(-accel.x * flip * 0.55, -accel.y * 0.55),
				Vector2(0, -7.0))
		sc.draw()


## The face, evaluated rather than selected.
##
## Two layers compose here without knowing about each other, which is the whole
## reason for doing it this way. The expression layer says what the character
## feels; the involuntary layer blinks, looks around and breathes regardless.
## The eye ends up at the product of the two, so the character can blink while
## surprised and still be surprised on the far side of the blink - something
## four prebuilt faces cannot express at any level of effort.
func _step_face(dt: float) -> void:
	var f: Dictionary = FACES[_face]
	# Expression springs. Slower than the body: a face settles into a mood.
	_p_open.step(float(f["open"]), 220.0, 19.0, dt)
	_p_bow.step(float(f["bow"]), 200.0, 18.0, dt)
	_p_lid.step(float(f["lid"]), 190.0, 18.0, dt)
	_p_mopen.step(float(f["mopen"]), 230.0, 19.0, dt)
	_p_smile.step(float(f["smile"]), 210.0, 18.0, dt)

	# Arousal drives the blink rate. Startled animals blink more.
	var arousal := 0.0
	match state:
		State.ARMED, State.LAUNCH: arousal = 0.9
		State.FALL, State.GLIDE: arousal = 1.4
		State.LAND, State.DASH: arousal = 0.5
	var lids := _blink.step(dt, arousal)
	var g := _gaze.step(dt, _look_where() + _look_hint)
	var br := _breath.step(dt, lerpf(0.32, 0.85, clampf(arousal, 0.0, 1.0)), 1.0)

	# Breathing rides on the torso and never on the head, so the face stays put
	# while the chest moves - the same reason squash is held off the skull.
	if _torso:
		var d := br * (0.014 if state == State.IDLE else 0.008)
		_torso.scale = Vector3(1.0 - d * 0.45, 1.0 + d, 1.0)

	var S := FIGURE_H
	var open: float = clampf(_p_open.v, 0.0, 1.2) * lids
	var bow: float = _p_bow.v * (0.35 + 0.65 * lids)
	for i in _eye_pieces.size():
		var sx := -1.0 if i == 0 else 1.0
		# The eye itself does not move; the gaze moves what is inside it, plus a
		# few tenths of a millimetre of the eye. Sliding the whole eye around the
		# face is the classic tell of a look-at bolted onto a rig.
		var at := Vector2(g.x * 0.004, g.y * 0.003)
		var eye_poly := FoxFace.eye(at, FoxFace.EYE_W, FoxFace.EYE_H, open, bow)
		_eye_pieces[i].draw(eye_poly, PackedVector2Array(), S)
		# The amber iris inside the dark rim. Inset by a fixed fraction of the
		# current aperture so it shrinks with the eye and vanishes into the rim
		# as the lid closes, rather than being clipped off at some threshold.
		var iris_amt: float = clampf((open - 0.28) / 0.72, 0.0, 1.0)
		var iris := FoxFace.eye(at + Vector2(g.x * 0.010, g.y * 0.008),
				FoxFace.EYE_W * 0.72, FoxFace.EYE_H * 0.80,
				open * 0.80 * iris_amt, bow)
		_iris_pieces[i].draw(iris if iris_amt > 0.02 else PackedVector2Array(),
				PackedVector2Array(), S)
		# The catchlight is what the gaze is actually readable through.
		var shine_open: float = clampf((open - 0.35) / 0.65, 0.0, 1.0)
		var shine := FoxFace.lid(at + Vector2(sx * 0.010 + g.x * 0.013,
				0.010 + g.y * 0.010), 0.010 * shine_open, 0.011 * shine_open)
		_shine_pieces[i].draw(shine if shine_open > 0.02 else PackedVector2Array(),
				PackedVector2Array(), S)
		# The brow: a fur disc dropped over the top of the eye and tilted. Angry
		# tilts the inner end down, worried tilts the outer end down, and the one
		# parameter covers both because they are the same motion mirrored.
		# The brow is placed against the eye's current top rather than at a fixed
		# height. It has to clear an arched happy squint - which reaches much
		# higher than a flat open eye - and then dip into the eye by a real
		# amount when the expression calls for a narrowed one.
		var lv := _p_lid.v
		const LID_RY := 0.030
		var rest := FoxFace.eye_top(open, bow) + LID_RY + 0.010
		_lid_pieces[i].node.rotation_degrees.z = sx * lv * 24.0
		_lid_pieces[i].draw(
				FoxFace.lid(Vector2(0, rest - 0.025 * absf(lv)), 0.044, LID_RY),
				PackedVector2Array(), S)

	if _mouth_piece:
		var mo: float = _p_mopen.v
		var sm: float = _p_smile.v
		var mp := FoxFace.mouth(Vector2(0, 0.003), 0.040, 0.034, mo, sm)
		var mo_ink := FoxFace.mouth(Vector2(0, 0.003), 0.040, 0.034, mo, sm, 0.004)
		_mouth_piece.draw(mp, mo_ink, S)


## What the character has reason to be looking at right now.
##
## A gaze that only wanders is better than a stare, but it reads as vacant - the
## eyes are moving and nothing is behind them. What makes a character look aware
## is that its eyes are on the thing the situation is about: the board while it
## is reading one, the sky on the way up, the deck rushing at it on the way
## down. The player never consciously notices this and always feels it.
func _look_where() -> Vector2:
	match state:
		State.IDLE: return Vector2(0.0, -0.42)      # reading the row of clues
		State.ARMED: return Vector2(0.0, -0.20)     # down at its own feet
		State.DASH: return Vector2(_dash_dir.x * 0.85, -0.25)
		State.LAUNCH: return Vector2(0.0, 0.62)
		State.APEX: return Vector2(0.0, 0.30)
		State.FALL: return Vector2(0.0, -0.78)      # at the deck coming up
		State.GLIDE: return Vector2(0.0, -0.92)
		State.LAND: return Vector2(0.0, -0.35)
		State.CHEER: return Vector2(0.0, 0.45)
	return Vector2.ZERO


## An extra bias the director can add - toward the cell being aimed at, or the
## gate. Added to the state's own direction rather than replacing it.
func look_at_offset(p: Vector2) -> void:
	_look_hint = p.limit_length(0.8)


## One-line readout of the involuntary layer, for capture runs.
func face_debug() -> String:
	return "face=%-10s lids=%.2f gaze=%+.2f,%+.2f breath=%+.2f" % [
			_face, _blink.openness, _gaze.offset.x, _gaze.offset.y, _breath.value]


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
		# Only the anchor is posed. Where the rest of the scarf goes is the
		# simulation's business, and it is far better at it than a sine was.
		var ssx := -1.0 if i == 0 else 1.0
		_scarf_ends[i].rotation_degrees.z = ssx * (4.0 + 16.0 * _s_fan.v)

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
##
## Only the *voluntary* part is left here - where the character is choosing to
## point its ears and tail. All the follow-through this function used to
## compute, the lag and the whip driven off velocity, now comes out of the
## strand simulation instead. Doing both was double-counting the same physics
## and fighting itself: a spring pulling the whole ear one way while the ear's
## own points were already lagging the other.
func _follow_through(dt: float) -> void:
	_head_lag.step(clampf(-_velocity.x * 2.2, -24.0, 24.0), 130.0, 14.0, dt)

	for i in _ears.size():
		var sx := -1.0 if i == 0 else 1.0
		# Straight up when alert, swept back when moving fast, fanned wide at the
		# apex. The strand supplies the bend; this only aims the root.
		var base := lerpf(52.0, -8.0, clampf(_s_ear.v * 0.5 + 0.5, 0.0, 1.0))
		var twitch := sin(_time * 5.4 + float(i) * 1.7) * 1.4
		_ears[i].rotation_degrees.z = -sx * (base * 0.42 + _s_fan.v * 26.0) + twitch

	if _tail:
		_tail.rotation_degrees.z = -14.0 + _s_fan.v * 22.0 - _s_lean.v * 0.35
