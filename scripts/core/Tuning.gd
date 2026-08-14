class_name Tuning
extends RefCounted

## GDD 28: initial tuning values. These are [TUNE], not [LOCK] - they exist in
## one place so playtest changes never have to be hunted across the codebase.

# --- space -------------------------------------------------------------------
const TILE := 2.0                     ## GDD 28: 1.8~2.2 m per tile edge
const DECK_THICKNESS := 0.55
const COVERED_RISE := 0.34            ## raised unopened slab vs. opened slab

# --- ground movement ---------------------------------------------------------
const DASH_TIME := 0.11               ## GDD 28: 0.10~0.16 s per one-tile dash
const DASH_TIME_SAND := 0.19          ## GDD 9.2 [TEST]: sand-covered tile
const INPUT_BUFFER := 0.14            ## one queued input, so 연타 never drops

# --- beat structure (GDD 6 [LOCK]) -------------------------------------------
const GROUND_BEATS := 4               ## landing GO -> 3 -> 2 -> 1 -> launch GO
const AIR_BEATS := 4                  ## launch GO -> 3 -> 2 (apex) -> 1 -> landing GO
const APEX_BEAT_OFFSET := 2           ## [LOCK] apex sits on air beat 2

# --- level validation --------------------------------------------------------
## Fraction of the ground phase reserved for *reading* the clues rather than
## dashing. The rest is the dash budget used by MineGrid reachability checks.
const READ_RESERVE_FRAC := 0.42

# --- mine launch -------------------------------------------------------------
const LAUNCH_GRAVITY := 20.0          ## drives apex height: h = g*(T/2)^2 / 2
const GLIDE_DROP := 7.5               ## how far below the deck a scarf glide sags
const GLIDE_WOBBLE := 1.15            ## lateral wobble amplitude of a scarf glide

# --- judgement (GDD 11.2: cosmetic only, never changes distance or airtime) ---
const PERFECT_WINDOW := 0.20          ## seconds early, arriving on the mine
const GOOD_WINDOW := 0.50

# --- stage timeline (song beats) ---------------------------------------------
const ACCIDENT_GO_BEAT := 32          ## the first blast, always on this downbeat
const FIRST_GROUND_BEAT := 36         ## first landing GO = accident + AIR_BEATS
const CYCLE_BEATS := GROUND_BEATS + AIR_BEATS


static func ground_dash_budget(ground_seconds: float) -> int:
	return int(floor(ground_seconds * (1.0 - READ_RESERVE_FRAC) / DASH_TIME))


static func sector_ground_beat(index: int) -> float:
	return float(FIRST_GROUND_BEAT + CYCLE_BEATS * index)
