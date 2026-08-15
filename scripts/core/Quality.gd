class_name Quality
extends RefCounted

## One place that decides how much world to build.
##
## The desktop build renders a few hundred props plus an ink hull on every one
## of them, which doubles the draw calls. A phone browser cannot take that, so
## the backdrop density, the ink width and the shadow distance all scale off a
## single tier decided once at startup.
##
## Nothing here touches gameplay. GDD 25.1: presentation may never change the
## puzzle - the sector chain, the beat grid and the dash budget are identical on
## every tier.

enum Tier { DESKTOP, MOBILE }

static var _tier: int = -1


static func tier() -> Tier:
	if _tier < 0:
		_tier = Tier.MOBILE if _detect_mobile() else Tier.DESKTOP
	return _tier as Tier


static func _detect_mobile() -> bool:
	if OS.has_feature("mobile"):
		return true
	# A web build on a phone reports "web" plus a touchscreen and a small window.
	if OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		return true
	return false


static func is_mobile() -> bool:
	return tier() == Tier.MOBILE


## True on the OpenGL Compatibility renderer, which is what the web build runs.
## It has no RenderingDevice, and it lands noticeably brighter than Forward+ for
## the same Environment - so the exposure needs its own trim.
static func is_compatibility() -> bool:
	return RenderingServer.get_rendering_device() == null


## Multiplier for "how many decorative props to spawn".
static func prop_density() -> float:
	return 0.42 if is_mobile() else 1.0


## Ink width multiplier. Thin lines alias badly on a dense phone screen and cost
## a full extra pass, so mobile gets a slightly heavier line on fewer objects.
static func ink_scale() -> float:
	return 1.15 if is_mobile() else 1.0


## Background props get no ink at all on mobile - it is the cheapest large win.
static func background_ink() -> float:
	return 0.0 if is_mobile() else 1.0


static func shadow_distance() -> float:
	return 60.0 if is_mobile() else 130.0


static func msaa() -> int:
	return Viewport.MSAA_DISABLED if is_mobile() else Viewport.MSAA_2X


## Godot's own resolution scaling. Rendering a phone's full pixel count is
## wasted on flat cel-shaded colour; 0.8 is invisible here and buys a lot.
static func render_scale() -> float:
	return 0.8 if is_mobile() else 1.0


static func describe() -> String:
	return "MOBILE" if is_mobile() else "DESKTOP"
