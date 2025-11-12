# PathCommands.gd
extends RefCounted
class_name PathCommands

var cmds: Array = []

func _init(d: String = ""):
	if d != "":
		cmds = PathCommands.parse_svg_path(d)

static func parse_svg_path(d: String) -> Array:
	var result := []
	var re := RegEx.new()
	re.compile(r"[MmLlHhVvCcQqSsTtAaZz]|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?")
	var tokens := []
	for m in re.search_all(d):
		tokens.append(m.get_string())

	var i := 0
	var cmd := ""
	var cur = Vector2.ZERO
	while i < tokens.size():
		if tokens[i].is_valid_ascii_identifier():
			cmd = tokens[i]
			i += 1
		var rel := cmd == cmd.to_lower()
		var c := cmd.to_upper()
		var nums := []
		while i < tokens.size() and not tokens[i].is_valid_ascii_identifier():
			nums.append(float(tokens[i]))
			i += 1

		# Convert H/V to absolute L coordinates immediately
		if c == "H":
			var new_nums := []
			for x in nums:
				new_nums.append(cur.x + (x if rel else 0))
				new_nums.append(cur.y)
				cur.x = new_nums[-2]
				cur.y = new_nums[-1]
			c = "L"
			nums = new_nums
		elif c == "V":
			var new_nums := []
			for y in nums:
				new_nums.append(cur.x)
				new_nums.append(cur.y + (y if rel else 0))
				cur.x = new_nums[-2]
				cur.y = new_nums[-1]
			c = "L"
			nums = new_nums
		elif rel:
			# Convert other relative commands to absolute
			if c in ["M", "L", "T"]:
				for j in range(0, nums.size(), 2):
					nums[j] += cur.x
					nums[j+1] += cur.y
					cur = Vector2(nums[j], nums[j+1])
			elif c == "C":
				for j in range(0, nums.size(), 6):
					nums[j] += cur.x
					nums[j+1] += cur.y
					nums[j+2] += cur.x
					nums[j+3] += cur.y
					nums[j+4] += cur.x
					nums[j+5] += cur.y
					cur = Vector2(nums[j+4], nums[j+5])
			elif c in ["Q","S"]:
				for j in range(0, nums.size(), 4):
					nums[j] += cur.x
					nums[j+1] += cur.y
					nums[j+2] += cur.x
					nums[j+3] += cur.y
					cur = Vector2(nums[j+2], nums[j+3])
			elif c == "A":
				for j in range(5, nums.size(), 7):
					nums[j] += cur.x
					nums[j+1] += cur.y
					cur = Vector2(nums[j], nums[j+1])
		else:
			# Absolute already
			if c in ["M","L","T"]:
				if nums.size() >= 2:
					cur = Vector2(nums[nums.size()-2], nums[nums.size()-1])
			elif c == "C":
				if nums.size() >= 6:
					cur = Vector2(nums[4], nums[5])
			elif c in ["Q","S"]:
				if nums.size() >= 4:
					cur = Vector2(nums[2], nums[3])
			elif c == "A":
				if nums.size() >= 7:
					cur = Vector2(nums[5], nums[6])
		result.append({"cmd": c, "nums": nums})
	return result

func write_path() -> String:
	var s := ""
	for c in cmds:
		s += c.cmd + " "
		match c.cmd:
			"M", "L", "T":
				for i in range(0, c.nums.size(), 2):
					s += "%s,%s " % [c.nums[i], c.nums[i+1]]
			"C":
				for i in range(0, c.nums.size(), 6):
					s += "%s,%s %s,%s %s,%s " % [
						c.nums[i], c.nums[i+1],
						c.nums[i+2], c.nums[i+3],
						c.nums[i+4], c.nums[i+5]
					]
			"Q","S":
				for i in range(0, c.nums.size(), 4):
					s += "%s,%s %s,%s " % [
						c.nums[i], c.nums[i+1],
						c.nums[i+2], c.nums[i+3]
					]
			"A":
				for i in range(0, c.nums.size(), 7):
					s += "%s %s %s %s %s %s,%s " % [
						c.nums[i], c.nums[i+1], c.nums[i+2], c.nums[i+3], c.nums[i+4],
						c.nums[i+5], c.nums[i+6]
					]
			"Z":
				pass
	return s.strip_edges()

func add_cmd(letter:String, nums:Array) -> void:
	cmds.append({"cmd": letter, "nums": nums})

func get_points(include_endpoints := true, include_controls := false) -> Array[Vector2]:
	var pts:Array[Vector2]
	@warning_ignore("unused_variable")
	var cur := Vector2.ZERO
	var subpath_start := Vector2.ZERO
	for c in cmds:
		match c.cmd:
			"M":
				for i in range(0, c.nums.size(), 2):
					var pt = Vector2(c.nums[i], c.nums[i+1])
					cur = pt
					if include_endpoints:
						pts.append(pt)
					if i == 0:
						subpath_start = pt
			"L","T":
				for i in range(0, c.nums.size(), 2):
					var pt = Vector2(c.nums[i], c.nums[i+1])
					cur = pt
					if include_endpoints:
						pts.append(pt)
			"C":
				for i in range(0, c.nums.size(), 6):
					var c1 = Vector2(c.nums[i], c.nums[i+1])
					var c2 = Vector2(c.nums[i+2], c.nums[i+3])
					var end = Vector2(c.nums[i+4], c.nums[i+5])
					if include_controls:
						pts.append(c1)
						pts.append(c2)
					if include_endpoints:
						pts.append(end)
					cur = end
			"Q","S":
				for i in range(0, c.nums.size(), 4):
					var c1 = Vector2(c.nums[i], c.nums[i+1])
					var end = Vector2(c.nums[i+2], c.nums[i+3])
					if include_controls:
						pts.append(c1)
					if include_endpoints:
						pts.append(end)
					cur = end
			"A":
				for i in range(0, c.nums.size(), 7):
					var end = Vector2(c.nums[i+5], c.nums[i+6])
					if include_endpoints:
						pts.append(end)
					cur = end
			"Z":
				cur = subpath_start
	return pts

func translate(offset: Vector2) -> void:
	for c in cmds:
		for i in range(c.nums.size()):
			if i % 2 == 0:
				c.nums[i] += offset.x
			else:
				c.nums[i] += offset.y

func transform(mode: String) -> void:
	if cmds.size() == 0:
		return

	var pts = get_points(true,false)
	if pts.size() == 0:
		return

	# Compute bounding box
	var min_x = pts[0].x
	var min_y = pts[0].y
	var max_x = pts[0].x
	var max_y = pts[0].y
	for p in pts:
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	var pivot = Vector2(min_x, min_y)
	var width = max_x - min_x
	var height = max_y - min_y

	# Apply transform while keeping top-left corner the same
	for c in cmds:
		for i in range(0, c.nums.size(), 2):
			var p = Vector2(c.nums[i], c.nums[i+1]) - pivot
			match mode:
				"flip_h":
					p.x = width - p.x
				"flip_v":
					p.y = height - p.y
				"rotate_cw":
					p = Vector2(height - p.y, p.x)
				"rotate_ccw":
					p = Vector2(p.y, width - p.x)
			c.nums[i] = p.x + pivot.x
			c.nums[i+1] = p.y + pivot.y
#
#func is_zero_area() -> bool:
	#var points := sampled_points(10,true)
	#points = PathCommands.unique_points(points)
	#if points.size() <= 2:
		#return true
	#var p0 = points[0]
	#var p1 = points[1]
	#var dx = p1.x - p0.x
	#var dy = p1.y - p0.y
	#for i in range(2, points.size()):
		#var pi = points[i]
		#if (pi.x - p0.x) * dy != (pi.y - p0.y) * dx:
			#return false
	#return true

func collapse_adjacent_duplicate_points() -> void:
	if cmds.is_empty():
		return

	var cleaned: Array = []
	var pts: Array = get_points(true, false)
	var pt_idx := 0
	var last_pt := Vector2(-999999, -999999)
	var first_set := false
	var closed := false

	for c in cmds:
		var keep := true
		if c.cmd == "Z":
			closed = true
		elif c.cmd != "Z":
			# only safe if we have a matching point
			if pt_idx < pts.size():
				if first_set and pts[pt_idx] == last_pt:
					keep = false
				last_pt = pts[pt_idx]
				first_set = true
			pt_idx += 1

		if keep or c.cmd == "M" or c.cmd == "Z":
			cleaned.append(c)

	if closed and (cleaned.is_empty() or cleaned[-1].cmd != "Z"):
		cleaned.append({"cmd": "Z", "nums": []})

	cmds = cleaned

func sampled_subpaths(curve_samples := 10, include_controls := false) -> Array:
	var subpaths: Array = []
	var pts: Array[Vector2] = []
	var cur := Vector2.ZERO
	var subpath_start := Vector2.ZERO

	for c in cmds:
		var step := 2
		if c.cmd == "C":
			step = 6
		elif c.cmd in ["Q", "S"]:
			step = 4
		elif c.cmd == "A":
			step = 7

		for i in range(0, c.nums.size(), step):
			var prev = cur
			var coords := []
			for j in range(step):
				coords.append(c.nums[i + j])
			var end = Vector2(coords[step - 2], coords[step - 1])

			match c.cmd:
				"M":
					if not pts.is_empty():
						subpaths.append(PathCommands.unique_points(pts))
						pts = []
					cur = end
					subpath_start = end
					pts.append(end)

				"L", "T":
					if prev != end:
						for t in range(1, curve_samples):
							var tt = float(t) / curve_samples
							pts.append(prev.lerp(end, tt))
					cur = end
					pts.append(end)

				"C":
					var c1 = Vector2(coords[0], coords[1])
					var c2 = Vector2(coords[2], coords[3])

					# Skip degenerate or zero-length segments
					if prev == end or (prev == c1 and c1 == c2 and c2 == end):
						continue

					if include_controls:
						pts.append(c1)
						pts.append(c2)

					for t in range(1, curve_samples):
						var tt = float(t) / curve_samples
						var x = pow(1-tt,3)*prev.x + 3*pow(1-tt,2)*tt*c1.x + 3*(1-tt)*pow(tt,2)*c2.x + pow(tt,3)*end.x
						var y = pow(1-tt,3)*prev.y + 3*pow(1-tt,2)*tt*c1.y + 3*(1-tt)*pow(tt,2)*c2.y + pow(tt,3)*end.y
						pts.append(Vector2(x, y))

					cur = end
					pts.append(end)

				"Q", "S":
					var c1 = Vector2(coords[0], coords[1])
					if prev == end or (prev == c1 and c1 == end):
						continue

					if include_controls:
						pts.append(c1)

					for t in range(1, curve_samples):
						var tt = float(t) / curve_samples
						var x = pow(1-tt,2)*prev.x + 2*(1-tt)*tt*c1.x + pow(tt,2)*end.x
						var y = pow(1-tt,2)*prev.y + 2*(1-tt)*tt*c1.y + pow(tt,2)*end.y
						pts.append(Vector2(x, y))

					cur = end
					pts.append(end)

				"A":
					if prev != end:
						for t in range(1, curve_samples):
							var tt = float(t) / curve_samples
							pts.append(Vector2(lerp(prev.x, end.x, tt), lerp(prev.y, end.y, tt)))
					cur = end
					pts.append(end)

				"Z":
					cur = subpath_start
					pts.append(cur)
					subpaths.append(PathCommands.unique_points(pts))
					pts = []

	if not pts.is_empty():
		subpaths.append(PathCommands.unique_points(pts))

	return subpaths

func is_point_inside(pt: Vector2, samples_per_curve: int = 10) -> bool:
	var subpaths := sampled_subpaths(samples_per_curve)
	for poly in subpaths:
		if poly.size() < 3:
			continue
		var intersections := 0
		for i in range(poly.size()):
			var a = poly[i]
			var b = poly[(i + 1) % poly.size()]
			if ((a.y > pt.y) != (b.y > pt.y)):
				var x_intersect = a.x + (pt.y - a.y) * (b.x - a.x) / (b.y - a.y)
				if pt.x < x_intersect:
					intersections += 1
		if intersections % 2 == 1:
			return true
	return false

func is_zero_area() -> bool:
	var subpaths := sampled_subpaths(10, true)
	for pts in subpaths:
		pts = PathCommands.unique_points(pts)
		if pts.size() <= 2:
			continue
		var p0 = pts[0]
		var p1 = pts[1]
		var dx = p1.x - p0.x
		var dy = p1.y - p0.y
		var flat := true
		for i in range(2, pts.size()):
			var pi = pts[i]
			if (pi.x - p0.x) * dy != (pi.y - p0.y) * dx:
				flat = false
				break
		if not flat:
			return false
	return true

# ------------------------------
# --- Static Helpers
# ------------------------------

static func str_to_v2i(s: String) -> Vector2i:
	var comps := s.split(",", false)
	if comps.size()<2: return Vector2i.ZERO
	return Vector2i(int(comps[0]), int(comps[1]))

static func unique_points(points: Array[Vector2]) -> Array[Vector2]:
	var seen := {}
	var result:Array[Vector2]
	for p in points:
		var key = str(p)
		if not seen.has(key):
			seen[key] = true
			result.append(p)
	return result
