class_name StarParams
extends RefCounted

# Input knobs for StarGenerator. Self-luminous plasma sphere — no terrain, no
# external lighting dependency; the shader is unshaded and emissive, so the
# star looks the same from every angle.

var seed_value: int = 0  # named to avoid shadowing the built-in seed() function
var radius: float = 1.4          # stars read as the dominant body in frame by default
var temperature: float = 5800.0  # Kelvin — drives color, red dwarf to blue-white giant
var turbulence: float = 0.4      # granulation/convective roil strength
var spot_activity: float = 0.15  # sunspot coverage and darkness
var corona: float = 0.5          # glow shell size/intensity
var corona_falloff: float = 1.5  # same falloff concept as a planet's atmosphere shell
