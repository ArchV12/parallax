class_name MoonParams
extends RefCounted

# Input knobs for MoonGenerator. Airless rocky body — no ocean, no
# atmosphere — dominated by impact craters rather than continents.

var seed_value: int = 0  # named to avoid shadowing the built-in seed() function
var radius: float = 0.35             # moons default much smaller than planets
var surface_roughness: float = 0.02  # base undulation, independent of craters — can be 0 (no ocean to z-fight with)
var crater_density: float = 0.5      # 0 = nearly pristine, 1 = saturated crater field
var crater_size: float = 0.18        # average crater radius as a fraction of moon radius
var crater_depth: float = 0.05       # bowl depth / rim height as a fraction of radius
var detail: int = 4                  # icosphere subdivisions (3..6)
