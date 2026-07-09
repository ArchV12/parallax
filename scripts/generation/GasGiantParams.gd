class_name GasGiantParams
extends RefCounted

# Input knobs for GasGiantGenerator. Covers both Gas Giant and Ice Giant —
# the two are the same generation pipeline; only the palette defaults (and
# this "ice" flag) differ. The Cosmic Forge drives these from sliders; the
# eventual game will derive them from system-generation data.

var seed_value: int = 0  # named to avoid shadowing the built-in seed() function
var radius: float = 1.6
var band_scale: float = 1.2     # latitude band frequency — higher = more, thinner bands
var turbulence: float = 0.4     # swirl distortion strength
var storminess: float = 0.35    # contrast/blotchiness of storm features
var band_contrast: float = 1.0  # 0 = flat/featureless (Uranus, Neptune), 1 = full bands (Jupiter, Saturn)
var atmosphere: float = 0.15    # optional extra limb glow shell; the shader's own limb darkening carries the "gas planet" look, so 0 is fine
var atmo_falloff: float = 1.2
var rings: float = 0.0          # 0 = no ring system; higher = denser, more visible, wider rings
var ice: bool = false            # true = cooler palette, calmer bands (Ice Giant)
