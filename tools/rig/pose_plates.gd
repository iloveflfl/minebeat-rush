extends SceneTree

## Render the posing rig in every game state, on a clean plate.
##
## These are not frames anyone will see. They are the structure handed to the
## generator, which draws the real character in the pose the rig chose - the
## rig decides what a landing looks like, the generator decides what it looks
## *like*. Getting that division right is the whole point: prompts alone could
## not move this character off its reference stance, and a hand-blocked
## silhouette was too crude for the model to take seriously.
##
## Each state is held for a moment of simulated time first, because every
## channel in the rig is a spring: sampled on the frame the state changes, they
## are all still at the previous pose.

const OUT := "res://../captures/plates/"

# state, variant, and how long to let the springs settle before the shot
const SHOTS := [
	["idle", FoxVector.State.IDLE, 0, 1.2],
	["armed", FoxVector.State.ARMED, 0, 0.7],
	["launch", FoxVector.State.LAUNCH, 0, 0.30],
	["apex_a", FoxVector.State.APEX, 0, 0.9],
	["apex_b", FoxVector.State.APEX, 1, 0.9],
	["apex_c", FoxVector.State.APEX, 2, 0.9],
	["fall", FoxVector.State.FALL, 0, 0.7],
	["land", FoxVector.State.LAND, 0, 0.10],
	["glide", FoxVector.State.GLIDE, 0, 1.1],
	["cheer", FoxVector.State.CHEER, 0, 0.5],
	["dash", FoxVector.State.DASH, 0, 0.14],
]


func _init() -> void:
	var root := get_root()
	root.transparent_bg = false
	# A flat cream plate, the same paper the sheet was drawn on, so the
	# generator is not asked to invent a background as well as a pose.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.992, 0.957, 0.918)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Framed a little taller than the figure so a raised limb is never clipped.
	cam.size = 4.6
	cam.position = Vector3(0, 1.55, 8)
	cam.near = 0.05
	cam.far = 40.0
	root.add_child(cam)

	var rig := FoxVector.new()
	root.add_child(rig)

	await process_frame
	await process_frame

	var dir := DirAccess.open("res://")
	var abs := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(abs)

	for shot in SHOTS:
		var name: String = shot[0]
		var st: int = shot[1]
		var variant: int = shot[2]
		var settle: float = shot[3]
		rig.set_state(st)
		rig.set("_variant", variant)
		# Step the springs by hand at a fixed rate. Waiting on real frames
		# would make the plates depend on how fast this machine happens to be.
		var t := 0.0
		while t < settle:
			rig.call("_drive", 1.0 / 120.0)
			rig.call("_follow_through", 1.0 / 120.0)
			rig.call("_apply", 1.0 / 120.0)
			rig.call("_step_strands", 1.0 / 120.0)
			t += 1.0 / 120.0
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png(abs + name + ".png")
		print("plate  %-8s %d x %d" % [name, img.get_width(), img.get_height()])

	quit()
