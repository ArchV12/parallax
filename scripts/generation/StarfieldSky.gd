class_name StarfieldSky
extends RefCounted

# Procedural star-scatter panorama texture for a 3D scene's sky — shared by
# any Node3D-based screen that needs a starfield skybox (Cosmic Forge,
# Cockpit, ...) so the star-scatter logic only exists in one place.

const WIDTH := 2048
const HEIGHT := 1024
const STAR_COUNT := 4200  # dense enough for lots of faint single-pixel pinpricks, still sparse against 2M+ pixels

static func build_texture() -> ImageTexture:
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	img.fill(Color(0.005, 0.007, 0.012))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in STAR_COUNT:
		var x := rng.randi_range(0, WIDTH - 1)
		var y := rng.randi_range(0, HEIGHT - 1)
		# Weighted toward dim — most stars are faint single-pixel pinpricks;
		# only the brightest few get the cross treatment below.
		var b := rng.randf_range(0.15, 1.0) * rng.randf_range(0.5, 1.0)
		var col := Color(b, b, b * rng.randf_range(0.85, 1.0))
		img.set_pixel(x, y, col)
		if b > 0.85:  # brightest stars get a tiny cross of neighbors
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := x + off.x
				var py := y + off.y
				if px >= 0 and px < WIDTH and py >= 0 and py < HEIGHT:
					img.set_pixel(px, py, col * 0.4)
	return ImageTexture.create_from_image(img)
