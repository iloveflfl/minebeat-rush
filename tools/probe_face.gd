extends SceneTree

## Headless check of the face polygons: does each one triangulate to a single
## complete shape at the parameter values the game actually uses?


func _init() -> void:
	for p in [
		{"n": "happy", "open": 0.05, "bow": 0.95},
		{"n": "blink-shut", "open": 0.0, "bow": 0.0},
		{"n": "surprised", "open": 1.0, "bow": 0.0},
		{"n": "determined", "open": 0.72, "bow": 0.0},
	]:
		var poly := FoxFace.eye(Vector2.ZERO, 0.058, 0.036, float(p["open"]),
				float(p["bow"]))
		var idx := Geometry2D.triangulate_polygon(poly)
		var area := 0.0
		for i in range(0, idx.size(), 3):
			var a := poly[idx[i]]
			var b := poly[idx[i + 1]]
			var c := poly[idx[i + 2]]
			area += absf((b - a).cross(c - a)) * 0.5
		# A complete ear-clip of an n-gon yields n-2 triangles. Anything less
		# means the triangulator bailed and part of the shape is simply absent.
		print("%-12s verts %d  tris %d (want %d)  area %.6f" % [
				p["n"], poly.size(), idx.size() / 3, poly.size() - 2, area])
	quit()
