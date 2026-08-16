class_name FoxLife
extends RefCounted

## The involuntary layer: everything the character does that the game never
## asked it to do.
##
## The rig had a complete set of voluntary motion - it leaned, launched, landed,
## fanned its ears, swung its arms in three different apex takes - and it still
## read as a puppet, because every single thing it did was something the game
## told it to do. A character that only ever moves on command looks operated.
##
## What separates a live character from an operated one is the motion nobody
## asked for: it blinks on its own schedule, its chest moves whether or not it
## is doing anything, and its eyes go to whatever is worth looking at rather
## than staring dead ahead. None of these are animations. They are small
## autonomous processes that run the whole time and are read out as parameters.
##
## Each one below is modelled on how the real thing behaves rather than on what
## is easy to code, because the tells are specific and an audience catches them
## without being able to say why.


## Eyelids.
##
## A blink is not symmetric and not periodic. The close is roughly twice as fast
## as the open, and the gaps between blinks are heavy-tailed - mostly a few
## seconds, occasionally much longer, and sometimes two in quick succession.
## Blinking on a fixed timer is worse than not blinking at all: the regularity
## is itself unnatural, and it reads as a mechanism.
class Blink:
	const CLOSE := 0.055
	const OPEN := 0.115

	var openness := 1.0
	var _t := -1.0
	var _next := 1.5
	var _double := false
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		_rng.randomize()
		_next = _rng.randf_range(0.8, 3.0)

	## `arousal` shortens the gaps. A startled animal blinks more, not less.
	func step(dt: float, arousal: float) -> float:
		if _t < 0.0:
			_next -= dt * (1.0 + arousal * 1.6)
			if _next <= 0.0:
				_t = 0.0
				# A quarter of blinks come in pairs. This one detail does more
				# for the illusion than any amount of tuning the timing curve.
				_double = _rng.randf() < 0.25
		else:
			_t += dt
			var d := CLOSE + OPEN
			if _t >= d:
				if _double:
					_double = false
					_t = 0.0
				else:
					_t = -1.0
					_next = _schedule()
		if _t < 0.0:
			openness = 1.0
		elif _t < CLOSE:
			openness = 1.0 - _t / CLOSE
		else:
			# Eased on the way back up, so the lid settles instead of snapping.
			var u := (_t - CLOSE) / OPEN
			openness = u * u * (3.0 - 2.0 * u)
		return openness

	func _schedule() -> float:
		# Heavy-tailed on purpose: mostly short gaps with the occasional long
		# one. A uniform draw produces a rhythm, and a rhythm is a machine.
		var u := _rng.randf()
		return 0.9 + 5.0 * u * u * u

	## Force a blink now - used to hide an instant the pose changes completely,
	## which is what animators cut on.
	func trigger() -> void:
		if _t < 0.0:
			_t = 0.0


## Where the eyes are pointed.
##
## Eyes do not drift. They hold on something, then jump to the next thing in a
## movement too fast to follow, and hold again. Interpolating smoothly toward a
## target is the single most common way to get this wrong - it produces a slow
## creepy glide no eye has ever made.
class Gaze:
	var offset := Vector2.ZERO
	var _from := Vector2.ZERO
	var _to := Vector2.ZERO
	var _hold := 0.4
	var _t := 1.0
	var _rng := RandomNumberGenerator.new()

	const SACCADE := 0.045

	func _init() -> void:
		_rng.randomize()

	## `want` is where the character has reason to look, in eye-offset units
	## roughly -1..1. The eye goes there, but not immediately and not exactly:
	## it keeps making small excursions of its own, which is what stops a
	## look-at system from reading as a turret.
	func step(dt: float, want: Vector2) -> Vector2:
		if _t < 1.0:
			_t = minf(1.0, _t + dt / SACCADE)
			var u := _t * _t * (3.0 - 2.0 * _t)
			offset = _from.lerp(_to, u)
			return offset
		_hold -= dt
		if _hold <= 0.0:
			_hold = _rng.randf_range(0.35, 1.5)
			_from = offset
			_to = (want + Vector2(_rng.randf_range(-0.28, 0.28),
					_rng.randf_range(-0.20, 0.20))).limit_length(1.0)
			_t = 0.0
		return offset

	## Snap the eyes somewhere now, for a moment that has to be looked at.
	func flick_to(p: Vector2) -> void:
		_from = offset
		_to = p.limit_length(1.0)
		_t = 0.0
		_hold = 0.55


## The chest.
##
## Inhale is slower than exhale, and the shoulders lag the chest. A plain sine
## gives an even in-out that reads as a pulsing balloon rather than breathing;
## skewing the phase is most of the difference.
class Breath:
	var value := 0.0
	var _phase := 0.0

	func step(dt: float, rate: float, depth: float) -> float:
		_phase = fposmod(_phase + dt * rate, 1.0)
		# Inhale over the first 60% of the cycle, exhale over the remaining 40%.
		var u := _phase / 0.6 if _phase < 0.6 else 1.0 - (_phase - 0.6) / 0.4
		value = depth * (u * u * (3.0 - 2.0 * u) - 0.5) * 2.0
		return value
