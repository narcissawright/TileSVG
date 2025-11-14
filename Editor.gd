extends Node2D

const gridsize := Vector2i(8, 12)

var gridpos := Vector2(0,0)
var zoomscale:float = 36.0

var svgSprite:Sprite2D
var svgOverlay:Sprite2D
var svgInterface:Sprite2D
var svgPreview:Sprite2D

const PREVIEW_SCALE:float = 2.0
const PREVIEW_COPIES_X:int = 32
const PREVIEW_COPIES_Y:int = 8
const HOVER_DIST:float = 0.3
const CTRL_PT_OFFSET:float = 0.075

const CANVAS_X = 164.0
const LAYERS_X = 514.0

var layercolor:String

var history:Array # for undo
var future:Array # for redo
var paths:Array[String]

var clickdrag:bool = false
var clickdrag_startpos:Vector2
var pre_drag_state:Dictionary # a history state

#var selected_point_old:PackedInt32Array # path index, segment index, coord index
var selected_point := SelectedPoint.new()
var selected_path_idx:int = -1 

var next_path_id: int = 1 # for "layer" names on the UI

var current_tile_idx: int = 0
const TILE_COLUMNS: int = 32
const TILE_ROWS: int = 8
const TILE_WIDTH: int = 8
const TILE_HEIGHT: int = 12

var tiles = []  # 256 entries, each only holds svg_text

var copied_path: String = ""
const PASTE_OFFSET := Vector2i(1, 1)

signal saved
signal rendered
signal history_modified (historysize:int, futuresize:int)

class SelectedPoint:
	var path_idx: int
	var seg_idx: int
	var kind: String  # "main", "control1", "control2"
	
	func _init(p: int = -1, s: int = -1, k: String = "") -> void:
		path_idx = p
		seg_idx = s
		kind = k
	
	func clear() -> void:
		path_idx = -1
		seg_idx = -1
		kind = ''
	
	func is_valid() -> bool:
		return path_idx >= 0 and seg_idx >= 0 and kind != ""

	func duplicate() -> SelectedPoint:
		return SelectedPoint.new(path_idx, seg_idx, kind)

func _on_tool_change(tool:String) -> void:
	if tool == "maker":
		if not paths.is_empty():
			if paths.back().ends_with('Z'):
				deselect_path()
			else:
				selected_path_idx = paths.size() - 1
				render_svg()
	if tool == "selector":
		delete_path_if_zero_area(selected_path_idx)

func delete_path_if_zero_area(idx: int) -> void:
	if path_exists(idx):
		var path_cmds := PathCommands.new(paths[idx])
		if path_cmds.is_zero_area():
			delete_path(idx)

func _ready() -> void:
	layercolor = Palette.DEFAULT
	
	$TileSelector.connect("tile_selected", Callable(self, "_on_tile_selected"))
	$TileSelector.connect("copypaste_tile", Callable(self, "_on_copypaste_tile"))
	$TileSelector.connect("clear_tile", Callable(self, "_on_clear_tile"))
	Events.connect('layer_color_changed', layer_color_changed)
	$Tool.connect("tool_changed", Callable(self, "_on_tool_change"))
	
	
	$CanvasBorder.hide()

	# Calculate default position
	#gridpos.x = (DisplayServer.window_get_size().x - zoomscale * gridsize.x) / 2.0
	#gridpos.y = (DisplayServer.window_get_size().y - zoomscale * gridsize.y) / 2.0
	gridpos.x = CANVAS_X
	gridpos.y = 72.0
	
	# Make Grid
	var startingpos := Vector2(gridpos.x, gridpos.y)
	var penpos = startingpos
	var hline := Vector2(gridsize.x * zoomscale, 0)
	var vline := Vector2(0, gridsize.y * zoomscale)
	
	for i in range (gridsize.y + 1):
		make_line(penpos, penpos + hline, "h", i)
		penpos += Vector2(0, zoomscale)
	penpos = startingpos
	for i in range (gridsize.x + 1):
		make_line(penpos + vline, penpos, "v", i)
		penpos += Vector2(zoomscale, 0)
	
	svgSprite = Sprite2D.new()
	svgSprite.name = "SVGSprite"
	svgSprite.position = gridpos
	svgSprite.centered = false
	svgSprite.z_index = 3
	add_child(svgSprite)
	
	svgOverlay = Sprite2D.new()
	svgOverlay.name = "SVGOverlay"
	# The Overlay/Interface is offset by 1 grid tile
	# in order to draw on the border without the image clipping.
	svgOverlay.position = gridpos - Vector2(zoomscale, zoomscale)
	svgOverlay.centered = false
	svgOverlay.z_index = 4
	add_child(svgOverlay)
	
	svgInterface = Sprite2D.new()
	svgInterface.name = "SVGInterface"
	svgInterface.position = gridpos - Vector2(zoomscale, zoomscale)
	svgInterface.centered = false
	svgInterface.z_index = 5
	add_child(svgInterface)
	
	load_all_tiles()
	select_tile(0) # optional, starts you on tile 0

func make_line(start:Vector2, end:Vector2, type:String, i:int) -> void:
	var line = Line2D.new()
	line.begin_cap_mode = Line2D.LINE_CAP_BOX
	line.end_cap_mode = Line2D.LINE_CAP_BOX
	line.width = 2.0
	if i % 4 == 0:
		line.modulate = Color(0.5,0.5,0.5)
		line.z_index = 2
	else:
		line.modulate = Color(0.4,0.4,0.4)
	line.add_point(start)
	line.add_point(end)
	match type:
		"h": $HContainer.add_child(line)
		"v": $VContainer.add_child(line)

func _input(event) -> void:
	# might want to store mouspos here once and not read it again.
	if event is InputEventMouseMotion:
		handle_mouse_motion()
	elif event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventKey:
		handle_key(event)

func handle_mouse_motion() -> void:
	svgInterface.hide()
	if clickdrag:
		match $Tool.current:
			"maker": handle_maker_clickdrag()
			"selector": handle_selector_clickdrag()
			"painter": handle_painter_clickdrag()
		return # Clickdrag has been handled, return
	
	# Mouse Motion but not clicking+dragging:
	var nearest:Vector2i = mousegrid_round()
	var dist:float = (mousegrid() - Vector2(nearest)).length()
	match $Tool.current:
		"maker":
			if dist < HOVER_DIST and within_grid(nearest):
				activate_interface(nearest, "maker") # any valid grid coord is highlighted.
		
		"selector":
			if dist < HOVER_DIST:
				handle_selector_mousemotion(nearest) # only points on the path are highlighted
		
		"painter":
			var pixelcoord := Vector2(mousegrid())
			if within_pixel_grid(pixelcoord):
				activate_tile(pixelcoord)



func handle_painter_clickdrag() -> void:
	var erasing: bool = Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_RIGHT == MOUSE_BUTTON_MASK_RIGHT
	var start_pos: Vector2 = clickdrag_startpos
	var end_pos: Vector2 = mousegrid()  # float mouse position in grid coords
	
	# Generate all pixels along the line
	for pixelcoord in get_line_pixels(start_pos, end_pos):
		if within_pixel_grid(pixelcoord):
			if erasing:
				remove_pixel(pixelcoord)
			else:
				add_pixel(pixelcoord)
	
	clickdrag_startpos = end_pos  # Update drag start

func get_line_pixels(a: Vector2, b: Vector2) -> Array:
	var pixels = []

	var x0 = a.x
	var y0 = a.y
	var x1 = b.x
	var y1 = b.y

	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)

	var step_x = 1
	if x1 < x0:
		step_x = -1
	var step_y = 1
	if y1 < y0:
		step_y = -1

	var x = x0
	var y = y0
	var last_pix = Vector2i(-1, -1)

	if dx > dy:
		var error = dx / 2.0
		while floor(x) != floor(x1):
			var pix = Vector2i(floor(x), floor(y))
			if pix != last_pix:
				pixels.append(pix)
				last_pix = pix

			x += step_x
			error -= dy
			if error < 0:
				y += step_y
				error += dx
	else:
		var error = dy / 2.0
		while floor(y) != floor(y1):
			var pix = Vector2i(floor(x), floor(y))
			if pix != last_pix:
				pixels.append(pix)
				last_pix = pix

			y += step_y
			error -= dx
			if error < 0:
				x += step_x
				error += dy

	# Append the last pixel
	var final_pix = Vector2i(floor(x1), floor(y1))
	if pixels.size() == 0 or pixels[pixels.size() - 1] != final_pix:
		pixels.append(final_pix)

	return pixels

func handle_mouse_button(event:InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if $TileSelector.tileset_is_last_click_context:
					return
				if svgInterface.visible:
					match $Tool.current:
						"maker": 
							makepath()
							start_drag()
						"selector": 
							left_click_select()
							start_drag()
						"painter": 
							start_drag()
							add_pixel(Vector2i(mousegrid()))
							svgInterface.hide()
				else:
					if $Tool.current == "selector":
						var mouse_pt: Vector2 = mousegrid()
						var prev_selected = selected_path_idx
						# Check if previous selection still contains the mouse
						var keep_prev = false
						if prev_selected != -1 and path_exists(prev_selected):
							var prev_cmds = PathCommands.new(paths[prev_selected])
							if prev_cmds.is_point_inside(mouse_pt):
								keep_prev = true
						if not keep_prev:
							deselect_path()
							selected_path_idx = -1
							for i in range(paths.size()):
								var path_cmds = PathCommands.new(paths[i])
								if path_cmds.is_point_inside(mouse_pt):
									selected_path_idx = i
									break
						if prev_selected != selected_path_idx:
							render_svg()
						start_drag()
			else:
				end_drag()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if svgInterface.visible:
					start_drag()
					match $Tool.current:
						'selector': right_click_select()
						'painter': 
							remove_pixel(Vector2i(mousegrid()))
							svgInterface.hide()
			else:
				end_drag()

#func keycheck(event:InputEventKey) -> bool:
	#return event.pressed and not $TileSelector.tileset_is_last_click_context

func handle_key(event:InputEventKey) -> void:
	var local_context:bool = not $TileSelector.tileset_is_last_click_context
	match event.keycode:
		KEY_Z:
			if event.pressed and event.ctrl_pressed and local_context:
				if event.shift_pressed:
					redo()
				else:
					undo()
		KEY_C:
			if event.pressed and event.ctrl_pressed: # and $Tool.current == "selector":
				if local_context:
					copy_selected_path()
				else:
					copied_path = ''
		KEY_V:
			# Handles both paste (control v) and vertical flip (v)
			if event.pressed: # and $Tool.current == "selector":
				if event.ctrl_pressed:
					# it's okay to paste a copied path if you just switched to a new tile
					paste_copied_path()
				elif local_context:
					transform_path(selected_path_idx, 'flip_v')
		KEY_UP:
			if event.pressed and local_context:
				try_move(0,-1)
		KEY_DOWN:
			if event.pressed and local_context:
				try_move(0,1)
		KEY_LEFT:
			if event.pressed and local_context:
				try_move(-1,0)
		KEY_RIGHT:
			if event.pressed and local_context:
				try_move(1,0)
		KEY_DELETE:
			if event.pressed and local_context:
				delete_path(selected_path_idx)
		KEY_BRACKETLEFT:
			if event.pressed and local_context:
				transform_path(selected_path_idx, 'rotate_ccw')
		KEY_BRACKETRIGHT:
			if event.pressed and local_context:
				transform_path(selected_path_idx, 'rotate_cw')
		KEY_H, KEY_M:
			if event.pressed and local_context:
				transform_path(selected_path_idx, 'flip_h')
		KEY_F:
			if event.pressed and local_context:
				transform_path(selected_path_idx, 'flip_v')

func transform_path(path_idx: int, mode: String) -> void:
	if not path_exists(path_idx):
		return

	add_history()

	var cmds = PathCommands.new(paths[path_idx])
	cmds.transform(mode)  # already handles pivot + bounding box preservation
	paths[path_idx] = cmds.write_path()

	render_svg()
	save_svg()

func copy_selected_path() -> void:
	if path_exists(selected_path_idx):
		# Don't copy the pixel path.
		if get_pixel_path_index() != selected_path_idx:
			copied_path = paths[selected_path_idx]

func paste_copied_path() -> void:
	if copied_path.is_empty():
		return
	add_history()
	
	var path_cmds = PathCommands.new(copied_path)
	# Offset path a little so it's visible and not overlapping perfectly
	path_cmds.translate(PASTE_OFFSET)
	paths.append(path_cmds.write_path())
	selected_path_idx = paths.size() - 1

	render_svg()
	save_svg()

func handle_selector_mousemotion(nearest: Vector2i) -> void:
	if not path_exists(selected_path_idx):
		return

	var cmds = PathCommands.new(paths[selected_path_idx])
	var points = cmds.get_points(true, true)  # endpoints + control points

	for pt in points:
		if nearest == Vector2i(pt.x, pt.y):
			activate_interface(nearest, "selector")
			return

func nearest_in_bounds(point:Vector2i) -> Vector2i:
	return point.clamp(Vector2i.ZERO, gridsize)

func handle_maker_clickdrag() -> void:
	if paths.is_empty():
		return

	var path_idx := paths.size() - 1
	var cmds := PathCommands.new(paths[path_idx])

	# Find the last "C" segment
	var last_c_idx := -1
	for i in range(cmds.cmds.size() - 1, -1, -1):
		if cmds.cmds[i]["cmd"] == "C":
			last_c_idx = i
			break

	if last_c_idx == -1:
		return  # no C segment to adjust

	var coord: Vector2 = mousegrid_round()
	var c_cmd = cmds.cmds[last_c_idx]

	# second control point is nums[2], nums[3] (x,y)
	var current_cp2 = Vector2(c_cmd["nums"][2], c_cmd["nums"][3])
	if current_cp2 != coord:
		c_cmd["nums"][2] = coord.x
		c_cmd["nums"][3] = coord.y
		paths[path_idx] = cmds.write_path()
		render_svg()

func get_pixel_path_index() -> int:
	for i in range(paths.size()):
		# will break if h and v lines are added to another tool.
		if paths[i].contains("L") or paths[i].contains("h"):
			return i
	return -1

func add_pixel(coord: Vector2i) -> void:
	var idx := get_pixel_path_index()
	var cmds: PathCommands

	if idx == -1:
		# No pixel path yet → create new
		cmds = PathCommands.new("")
		paths.append(cmds.write_path())
		idx = paths.size() - 1
	else:
		cmds = PathCommands.new(paths[idx])

	# Build the rectangle using L commands
	var x = coord.x
	var y = coord.y
	var rect_cmds := [
		{"cmd":"M", "nums":[x, y]},
		{"cmd":"L", "nums":[x+1, y]},
		{"cmd":"L", "nums":[x+1, y+1]},
		{"cmd":"L", "nums":[x, y+1]},
		{"cmd":"Z", "nums":[]}
	]

	# Check if this pixel already exists (by starting M point)
	for i in range(cmds.cmds.size()):
		var c = cmds.cmds[i]
		if c.cmd == "M" and Vector2(c.nums[0], c.nums[1]) == Vector2(x, y):
			return  # already present, do nothing

	# Append rectangle to path
	for c in rect_cmds:
		cmds.cmds.append(c)

	# Write back to paths
	paths[idx] = cmds.write_path()
	render_svg()

func remove_pixel(coord: Vector2i) -> void:
	var idx := get_pixel_path_index()
	if idx == -1:
		return

	# Load path as PathCommands
	var path := PathCommands.new(paths[idx])
	var removed := false

	for i in range(path.cmds.size() - 1, -1, -1):
		var cmd = path.cmds[i]
		if cmd.cmd == "M" and cmd.nums.size() >= 2:
			var start = Vector2i(cmd.nums[0], cmd.nums[1])
			if start == coord:
				# Remove the whole pixel block: M + H/V/C + ... + Z
				var j := i + 1
				while j < path.cmds.size() and path.cmds[j].cmd != "M":
					j += 1
				# Remove range from i to j-1
				for k in range(j - 1, i - 1, -1):
					path.cmds.remove_at(k)
				removed = true
				break

	if removed:
		if path.cmds.is_empty():
			delete_path(idx)
		else:
			paths[idx] = path.write_path()
		render_svg()

func make_highlight_circle(where:Vector2i) -> String:
	return '<circle r="0.2" cx="' + str(where.x+1) + '" cy="' + str(where.y+1) + '" stroke="#ffff99" stroke-width="0.1" fill="none" />'

func get_final_point(segments:PackedStringArray) -> Vector2i:
	if segments.is_empty():
		return Vector2i.ZERO
	# Start from the last segment and walk backwards
	for i in range(segments.size() - 1, -1, -1):
		var s = segments[i].split(' ', false)
		if s[0] == "M":
			return str_to_v2i(s[1])
		elif s[0] == "C":
			return str_to_v2i(s[3])
	# Fallback
	return Vector2i.ZERO

func activate_tile(coord:Vector2i) -> void:
	svgInterface.show()
	var interfaceString:String = svgHead(true)
	interfaceString += '<path d="'
	interfaceString += 'M %d,%d h1 v1 h-1 Z' % [coord.x+1, coord.y+1]
	interfaceString += '" style="fill:#888"/>'
	interfaceString += '</svg>'
	svgInterface.texture = svg_to_texture(interfaceString, zoomscale)


func activate_interface(where: Vector2i, tool: String) -> void:
	svgInterface.show()
	var circle1 := ""
	var circle2 := ""

	if not path_exists(selected_path_idx):
		if tool == "maker":
			circle1 = make_highlight_circle(where)
		var interface_string := svgHead(true) + circle1 + circle2 + "</svg>"
		svgInterface.texture = svg_to_texture(interface_string, zoomscale)
		return

	var cmds := PathCommands.new(paths[selected_path_idx])

	match tool:
		"maker":
			var pts := cmds.get_points(true, false)
			if pts.is_empty() or where != Vector2i(pts.back()):
				circle1 = make_highlight_circle(where)

		"selector":
			var mouse_pos := mousegrid()
			
			var pixelpath := selected_path_idx == get_pixel_path_index()
			if pixelpath:
				# We don't want to interact with pixelpath individual points.
				svgInterface.hide()
				return
			
			# --- Check if a regular anchor exists at `where` ---
			var found_anchor := false
			for c in cmds.cmds:
				match c.cmd:
					"M", "L", "T":
						for i in range(0, c.nums.size(), 2):
							if Vector2i(c.nums[i], c.nums[i+1]) == where:
								found_anchor = true
								break
					"C":
						if Vector2i(c.nums[4], c.nums[5]) == where:
							found_anchor = true
							break
				if found_anchor:
					break

			if found_anchor:
				circle1 = make_highlight_circle(where)

			# --- Red circle at nearest control point using PathCommands ---
			var nearest_cp_offset := Vector2.ZERO
			var best_dist := INF
			for j in range(cmds.cmds.size()):
				var c = cmds.cmds[j]
				if c.cmd != "C":
					continue
				for which in [1, 2]:
					# use the new helper
					var offset_point := get_control_offset(cmds, j, which)
					var dist := mouse_pos.distance_to(offset_point)
					if dist < best_dist:
						best_dist = dist
						nearest_cp_offset = offset_point

			if best_dist < HOVER_DIST:
				circle2 = '<circle r="0.1125" cx="%f" cy="%f" stroke="none" fill="#ffffff" />' % [nearest_cp_offset.x + 1, nearest_cp_offset.y + 1]

	var interfaceString := svgHead(true) + circle1 + circle2 + "</svg>"
	svgInterface.texture = svg_to_texture(interfaceString, zoomscale)

# Helper to compute the "offset" position for a control point
func get_control_offset(cmds: PathCommands, seg_idx: int, which: int) -> Vector2:
	if seg_idx < 0 or seg_idx >= cmds.cmds.size():
		return Vector2.ZERO

	var c_cmd = cmds.cmds[seg_idx]
	if c_cmd["cmd"] != "C":
		return Vector2.ZERO

	# Second or first control point
	var control_idx = 2 if which == 2 else 0
	var control = Vector2(c_cmd["nums"][control_idx], c_cmd["nums"][control_idx + 1])

	# Previous anchor
	var prev_idx = seg_idx - 1
	if prev_idx < 0:
		prev_idx = cmds.cmds.size() - 1
	var prev_cmd = cmds.cmds[prev_idx]
	var prev_anchor: Vector2
	if prev_cmd["cmd"] == "C":
		prev_anchor = Vector2(prev_cmd["nums"][4], prev_cmd["nums"][5])
	else:
		prev_anchor = Vector2(prev_cmd["nums"][0], prev_cmd["nums"][1])

	# Next anchor
	var next_anchor = Vector2(c_cmd["nums"][4], c_cmd["nums"][5])

	# Determine offset
	var target: Vector2
	if (which == 1 and control == prev_anchor) or (which == 2 and control == next_anchor):
		target = next_anchor if which == 1 else prev_anchor
	else:
		target = prev_anchor if which == 1 else next_anchor

	var dir = target - control
	if dir.length() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector2.ZERO

	return control + dir * CTRL_PT_OFFSET

func try_move(x:int, y:int) -> void:
	if not path_exists(selected_path_idx):
		return
		
	add_history()
	
	var cmds = PathCommands.new(paths[selected_path_idx])
	cmds.translate(Vector2(x, y))
	paths[selected_path_idx] = cmds.write_path()
	render_svg()
	save_svg()

func path_exists(idx:int) -> bool:
	if idx >= 0 and idx < paths.size():
		return true
	return false

func get_snapshot() -> Dictionary:
	return {
		"paths": paths.duplicate(true),
		"tool": $Tool.current,
		"selected_path_idx": selected_path_idx,
		"selected_point": selected_point.duplicate()
	}

func undo() -> void:
	if history.is_empty(): 
		return
	var state:Dictionary = history.pop_back()
	future.append(get_snapshot())
	emit_signal('history_modified', history.size(), future.size())
	restore_state(state)

func redo() -> void:
	if future.is_empty(): return
	var state:Dictionary = future.pop_back()
	history.append(get_snapshot())  # current state goes to undo stack
	emit_signal('history_modified', history.size(), future.size())
	restore_state(state)

func restore_state(state: Dictionary) -> void:
	paths = state.paths.duplicate(true)
	$Tool.set_tool(state.tool)
	selected_path_idx = state.selected_path_idx
	selected_point = state.selected_point.duplicate()
	render_svg()
	save_svg()

func add_history() -> void:
	append_to_history(get_snapshot())

func append_to_history(state:Dictionary) -> void:
	history.append(state)
	pre_drag_state.clear()
	future.clear()
	emit_signal('history_modified', history.size(), future.size())

func start_drag() -> void:
	clickdrag = true
	clickdrag_startpos = mousegrid()
	pre_drag_state = get_snapshot()

func end_drag() -> void:
	if selected_point.is_valid():
		var path_idx: int = selected_point.path_idx
		if not path_exists(path_idx):
			selected_point.clear()
			clickdrag = false
			return

		var cmds = PathCommands.new(paths[path_idx])
		
		# Collapse duplicate points in the command structure
		cmds.collapse_adjacent_duplicate_points()
		
		# If the path is zero-area, delete it
		if cmds.is_zero_area():
			delete_path(path_idx)
		else:
			paths[path_idx] = cmds.write_path()

	clickdrag = false
	selected_point.clear()

	if pre_drag_state.is_empty():
		return

	# Record history only if paths changed
	if paths != pre_drag_state.paths:
		append_to_history(pre_drag_state.duplicate(true))
		# if path oob delete
		render_svg()
		save_svg()
	
	pre_drag_state.clear()

func sync_layers_ui() -> void:
	# Remove extra nodes if paths shrunk
	while $Layers.get_child_count() > paths.size():
		var node = $Layers.get_child($Layers.get_child_count() - 1)
		$Layers.remove_child(node)
		node.free()

	# Add missing nodes if paths grew
	for i in range($Layers.get_child_count(), paths.size()):
		var layer = preload("res://layer.tscn").instantiate()
		layer.position = Vector2(LAYERS_X, 360 + (30 * i))
		layer.name = "Path_" + str(next_path_id)
		next_path_id += 1
		$Layers.add_child(layer)

	# Update all nodes to match paths
	for i in range(paths.size()):
		var layer = $Layers.get_child(i)
		layer.get_node("LayerColor").color = Color(layercolor)
		layer.get_node("LayerName").text = "Path " + str(i)
		var colorstring = layercolor
		if colorstring.begins_with("#"):
			colorstring = colorstring.substr(1)
		var hex_node = layer.get_node("HexValue")
		#hex_node.text = colorstring
		hex_node.path_index = i

func left_click_select() -> void:
	if not path_exists(selected_path_idx):
		return

	var path = PathCommands.new(paths[selected_path_idx])
	var coord: Vector2i = mousegrid_round()

	selected_point.clear()

	for seg_idx in range(path.cmds.size()):
		var cmd = path.cmds[seg_idx]
		match cmd.cmd:
			"M":
				var pt = Vector2i(cmd.nums[0], cmd.nums[1])
				if coord == pt:
					selected_point = SelectedPoint.new()
					selected_point.path_idx = selected_path_idx
					selected_point.seg_idx = seg_idx
					selected_point.kind = 'main'
					return
			"C":
				var endpoint = Vector2i(cmd.nums[4], cmd.nums[5])
				if coord == endpoint:
					selected_point.path_idx = selected_path_idx
					selected_point.seg_idx = seg_idx
					selected_point.kind = 'main'
					return

func right_click_select() -> void:
	if not path_exists(selected_path_idx):
		return

	var path = PathCommands.new(paths[selected_path_idx])
	var mouse_pos: Vector2 = mousegrid()
	var coord: Vector2i = mousegrid_round()
	var candidates: Array = []

	# collect candidates under cursor (C segment control points)
	for seg_idx in range(path.cmds.size()):
		var cmd = path.cmds[seg_idx]
		if cmd.cmd != "C":
			continue

		var c1 = Vector2i(cmd.nums[0], cmd.nums[1])
		var c2 = Vector2i(cmd.nums[2], cmd.nums[3])

		if coord == c1:
			candidates.append(SelectedPoint.new(selected_path_idx, seg_idx, 'control1'))
		if coord == c2:
			candidates.append(SelectedPoint.new(selected_path_idx, seg_idx, 'control2'))

	if candidates.size() == 0:
		return

	var best_candidate = null
	var best_dist: float = INF

	for cand in candidates:
		var which = 1 if cand.kind == "control1" else 2
		var offset_point: Vector2 = get_control_offset(path, cand.seg_idx, which)
		var dist: float = mouse_pos.distance_to(offset_point)
		if dist < best_dist:
			best_dist = dist
			best_candidate = cand

	if best_candidate != null:
		selected_point = best_candidate

func handle_selector_clickdrag() -> void:

	# --- Single point movement ---
	if selected_point.is_valid():
		var path_idx:int = selected_point.path_idx
		var seg_idx:int = selected_point.seg_idx
		var kind:String = selected_point.kind

		if not path_exists(path_idx):
			return

		var path_cmds: PathCommands = PathCommands.new(paths[path_idx])
		if seg_idx >= path_cmds.cmds.size():
			return

		var cmd = path_cmds.cmds[seg_idx]

		# Map selected_point[2] to nums index exactly like original
		var nums_idx := 0
		match cmd.cmd:
			"C":
				if kind == 'control1': nums_idx = 0
				elif kind == 'control2': nums_idx = 2
				elif kind == 'main': nums_idx = 4
			"M":
				if kind == 'main': nums_idx = 0
			#"L","T":
				#nums_idx = comp_idx * 2
			#"Q","S":
				#if comp_idx == 0: nums_idx = 0
				#elif comp_idx == 1: nums_idx = 2

		var current_pos: Vector2i = Vector2i(cmd.nums[nums_idx], cmd.nums[nums_idx+1])
		var target_pos: Vector2i = mousegrid_round()
		var diff: Vector2i = target_pos - current_pos

		if diff == Vector2i.ZERO:
			return

		# Move the selected point
		cmd.nums[nums_idx] += diff.x
		cmd.nums[nums_idx+1] += diff.y

		# --- Mirror control points for C segments like original code ---
		var is_closed: bool = path_cmds.cmds.size() > 0 and path_cmds.cmds[-1].cmd == "Z"
		var last_idx = path_cmds.cmds.size() - (2 if is_closed else 1)
		var is_first = (seg_idx == 0)
		var is_last = (seg_idx == last_idx)
		var element_status := "normal"
		if is_closed:
			if is_first:
				element_status = "first_closed"
			elif is_last:
				element_status = "last_closed"
		elif is_first and is_last:
			element_status = "only"
		elif is_first:
			element_status = "first"
		elif is_last:
			element_status = "last"

		if kind == 'main':
		#if comp_idx == 3 or element_status in ["first", "first_closed"]:
			match element_status:
				"normal":
					# Move current segment's control point 2
					if cmd.cmd == "C":
						cmd.nums[2] += diff.x
						cmd.nums[3] += diff.y
					# Move next segment's control point 1
					if seg_idx + 1 < path_cmds.cmds.size():
						var next_cmd = path_cmds.cmds[seg_idx + 1]
						if next_cmd.cmd == "C":
							next_cmd.nums[0] += diff.x
							next_cmd.nums[1] += diff.y

				"last_closed":
					# Move last segment's control point 2
					if cmd.cmd == "C":
						cmd.nums[2] += diff.x
						cmd.nums[3] += diff.y
						cmd.nums[4] += diff.x  # also move the endpoint itself
						cmd.nums[5] += diff.y

					# Move first segment's control point 1 and its endpoint
					if path_cmds.cmds.size() > 1:
						var first_cmd = path_cmds.cmds[0]
						if first_cmd.cmd == "C":
							first_cmd.nums[0] += diff.x
							first_cmd.nums[1] += diff.y
							first_cmd.nums[4] += diff.x  # move main point clone
							first_cmd.nums[5] += diff.y

				"first_closed":
					# Move next segment's control point 1
					if seg_idx + 1 < path_cmds.cmds.size():
						var next_cmd = path_cmds.cmds[seg_idx + 1]
						if next_cmd.cmd == "C":
							next_cmd.nums[0] += diff.x
							next_cmd.nums[1] += diff.y

					# Move last segment's control point 2 and its endpoint
					if path_cmds.cmds.size() > last_idx:
						var last_cmd = path_cmds.cmds[last_idx]
						if last_cmd.cmd == "C":
							last_cmd.nums[2] += diff.x
							last_cmd.nums[3] += diff.y
							last_cmd.nums[4] += diff.x  # move main point clone
							last_cmd.nums[5] += diff.y

				"first":
					# Move next segment's control point 1
					if seg_idx + 1 < path_cmds.cmds.size():
						var next_cmd = path_cmds.cmds[seg_idx + 1]
						if next_cmd.cmd == "C":
							next_cmd.nums[0] += diff.x
							next_cmd.nums[1] += diff.y

				"last":
					# Move last segment's control point 2
					if cmd.cmd == "C":
						cmd.nums[2] += diff.x
						cmd.nums[3] += diff.y

				"only":
					pass  # nothing extra to adjust

		paths[path_idx] = path_cmds.write_path()
		render_svg()

	# --- Entire path movement ---
	#elif selected_point.size() == 0:
	else:
		if selected_path_idx >= 0 and selected_path_idx < paths.size():
			var diff: Vector2 = (mousegrid() - clickdrag_startpos).round()
			clickdrag_startpos += diff
			if diff != Vector2.ZERO:
				var path_cmds: PathCommands = PathCommands.new(paths[selected_path_idx])
				path_cmds.translate(diff)
				paths[selected_path_idx] = path_cmds.write_path()
				render_svg()


func makepath() -> void:
	var coord:Vector2i = mousegrid_round()
	if not within_grid(coord):
		return

	add_history() # always record history before modifying anything

	var cmds: PathCommands
	var open_path_exists: bool = not paths.is_empty() and not paths.back().ends_with("Z")

	if open_path_exists:
		cmds = PathCommands.new(paths.back())
	else:
		cmds = PathCommands.new("")

	# --- Create or extend the path ---
	if cmds.cmds.is_empty():
		# Start a new path
		cmds.add_cmd("M", [coord.x, coord.y])
	else:
		var pts := cmds.get_points(true, false)
		if pts.is_empty():
			return

		var prev := Vector2i(pts.back())
		if prev == coord:
			return

		# Straight cubic between prev and coord (control points = endpoints)
		cmds.add_cmd("C", [prev.x, prev.y, coord.x, coord.y, coord.x, coord.y])

		# --- Check if closing path ---
		var first := Vector2i(cmds.get_points(true, false)[0])
		if first == coord:
			cmds.add_cmd("Z", [])
			if cmds.is_zero_area(): # You’ll adapt this later
				if selected_path_idx >= 0 and selected_path_idx < paths.size():
					delete_path(selected_path_idx)
				return

	# --- Write back into `paths` array ---
	var new_path_str := cmds.write_path() # Assuming this returns a string representation
	if open_path_exists:
		paths[paths.size() - 1] = new_path_str
	else:
		paths.append(new_path_str)

	selected_path_idx = paths.size() - 1

	render_svg()
	save_svg()
	svgInterface.hide()

func delete_path(idx: int) -> void:
	if not path_exists(idx):
		return
	
	add_history()
	
	# Remove the data first
	paths.remove_at(idx)
	
	# Remove the corresponding UI node immediately
	var ui_node := $Layers.get_child(idx)
	$Layers.remove_child(ui_node)
	ui_node.free()
	
	# Reindex remaining layers (they shifted up)
	for i in range(idx, $Layers.get_child_count()):
		var node := $Layers.get_child(i)
		node.position = Vector2(LAYERS_X, 360 + (30 * i))
		node.get_node("HexValue").path_index = i
	
	selected_path_idx = -1
	render_svg()
	save_svg()


# --- Convert pixels into edges (clockwise around each pixel) ---
func extract_pixel_edges(pixels: Dictionary, offset: Vector2 = Vector2(1,1)) -> Array:
	var edges := []
	for pixel in pixels.keys():
		var x = pixel.x
		var y = pixel.y
		if not pixels.has(Vector2i(x + 1, y)):
			edges.append([Vector2(x + 1, y) + offset, Vector2(x + 1, y + 1) + offset])
		if not pixels.has(Vector2i(x - 1, y)):
			edges.append([Vector2(x, y + 1) + offset, Vector2(x, y) + offset])
		if not pixels.has(Vector2i(x, y - 1)):
			edges.append([Vector2(x, y) + offset, Vector2(x + 1, y) + offset])
		if not pixels.has(Vector2i(x, y + 1)):
			edges.append([Vector2(x + 1, y + 1) + offset, Vector2(x, y + 1) + offset])
	return edges

# --- Connect edges into loops ---
func edges_to_loops(edges: Array) -> Array:
	var loops := []
	var unused_edges := edges.duplicate()
	while unused_edges.size() > 0:
		var loop := []
		var e = unused_edges.pop_front()
		loop.append(e[0])
		loop.append(e[1])
		var extended = true
		while extended:
			extended = false
			for i in range(unused_edges.size()):
				var edge = unused_edges[i]
				if loop[-1] == edge[0]:
					loop.append(edge[1])
					unused_edges.remove_at(i)
					extended = true
					break
				elif loop[-1] == edge[1]:
					loop.append(edge[0])
					unused_edges.remove_at(i)
					extended = true
					break
		loops.append(loop)
	return loops

# --- Convert loops to SVG ---
func loops_to_svg(loops: Array, stroke_color: String = "#002050", stroke_width: float = 0.1) -> String:
	var svg := ""
	for loop in loops:
		if loop.size() < 2:
			continue
		var path = "M %s,%s " % [str(loop[0].x), str(loop[0].y)]
		for i in range(1, loop.size()):
			path += "L %s,%s " % [str(loop[i].x), str(loop[i].y)]
		path += "Z"
		svg += '<path d="%s" fill="none" stroke="%s" stroke-width="%s"/>\n' % [path, stroke_color, str(stroke_width)]
	return svg
# --- Build overlay from pixel commands ---
func get_pixel_overlay(cmds) -> String:
	var pixel_dict := {}
	var subpath_points := []

	for c in cmds.cmds:
		if c.cmd == "Z":
			# End of subpath — compute top-left corner
			if subpath_points.size() > 0:
				var min_x = subpath_points[0].x
				var min_y = subpath_points[0].y
				for p in subpath_points:
					min_x = min(min_x, p.x)
					min_y = min(min_y, p.y)
				pixel_dict[Vector2i(min_x, min_y)] = true
			subpath_points.clear()
		else:
			# Collect points from this command
			for i in range(0, c.nums.size(), 2):
				subpath_points.append(Vector2(c.nums[i], c.nums[i+1]))

	# Handle any subpath that didn't end with Z
	if subpath_points.size() > 0:
		var min_x = subpath_points[0].x
		var min_y = subpath_points[0].y
		for p in subpath_points:
			min_x = min(min_x, p.x)
			min_y = min(min_y, p.y)
		pixel_dict[Vector2i(min_x, min_y)] = true

	var edges = extract_pixel_edges(pixel_dict)
	var loops = edges_to_loops(edges)
	return loops_to_svg(loops)

func render_svg() -> void:
	if $Layers.get_child_count() != paths.size():
		sync_layers_ui()
	var overlay := ""
	var circles := ""
	var controlpts := ""
	var pixelpath := selected_path_idx == get_pixel_path_index()
	if selected_path_idx != -1 and not paths.is_empty():
		var cmds := PathCommands.new(paths[selected_path_idx])
		
		if pixelpath:
			overlay = get_pixel_overlay(cmds)
		else:
			var pathviz := ''
			var prev_pt := Vector2i.ZERO
			for c in cmds.cmds:
				match c.cmd:
					"M":
						var pt := Vector2i(c.nums[0], c.nums[1])
						prev_pt = pt
						circles += circle_at_coord(Vector2(pt) + Vector2.ONE, Color(0,0,0), 0.2)
						pathviz += "M " + v2i_to_str(pt + Vector2i.ONE)
					"L", "T":
						var pt := Vector2i(c.nums[0], c.nums[1])
						circles += circle_at_coord(Vector2(pt) + Vector2.ONE, Color(0,0,0), 0.2)
						pathviz += "L " + v2i_to_str(pt + Vector2i.ONE)
						prev_pt = pt
					"C":
						var c1 := Vector2i(c.nums[0], c.nums[1])
						var c2 := Vector2i(c.nums[2], c.nums[3])
						var end := Vector2i(c.nums[4], c.nums[5])
						var diff := end - prev_pt
						var ctrl_viz_1 := Vector2(c1)
						var ctrl_viz_2 := Vector2(c2)

						if c1 == prev_pt:
							ctrl_viz_1 = Vector2(prev_pt) + Vector2(diff).normalized() * CTRL_PT_OFFSET
						else:
							ctrl_viz_1 = ctrl_viz_1.move_toward(prev_pt, CTRL_PT_OFFSET)
						if c2 == end:
							ctrl_viz_2 = Vector2(end) - Vector2(diff).normalized() * CTRL_PT_OFFSET
						else:
							ctrl_viz_2 = ctrl_viz_2.move_toward(end, CTRL_PT_OFFSET)

						controlpts += line_from_to(ctrl_viz_1 + Vector2.ONE, Vector2(prev_pt) + Vector2.ONE)
						controlpts += line_from_to(ctrl_viz_2 + Vector2.ONE, Vector2(end) + Vector2.ONE)
						circles += circle_at_coord(Vector2(end) + Vector2.ONE, Color(0,0,0), 0.2)
						controlpts += circle_at_coord(ctrl_viz_1 + Vector2.ONE, Color(1,0,0), 0.1)
						controlpts += circle_at_coord(ctrl_viz_2 + Vector2.ONE, Color(1,0,0), 0.1)

						pathviz += " C %s %s %s" % [
							v2i_to_str(c1 + Vector2i.ONE),
							v2i_to_str(c2 + Vector2i.ONE),
							v2i_to_str(end + Vector2i.ONE)
						]
						prev_pt = end
					"Z":
						pathviz += "Z"
			overlay = '<path d="%s" style="stroke:#000;stroke-width:0.1;fill:none" />' % pathviz.replace("|", " ")

	# --- Build SVG content from cmds ---
	var raw_paths := ""
	var complete_paths := ""
	for p in paths:
		var cmd_path := PathCommands.new(p)
		var path_str := cmd_path.write_path()
		raw_paths += '<path d="%s" />' % path_str
		complete_paths += '<path d="%s" style="stroke:none;fill:%s" />' % [path_str, layercolor]

	var svgRawString := svgHead(false) + raw_paths + "</svg>"
	var svgBaseString := svgHead(false) + complete_paths + "</svg>"

	var overlayString := svgHead(true) + overlay
	if not pixelpath:
		overlayString += circles + controlpts
	overlayString += "</svg>"
	
	$XML.update_text(svgRawString)
	svgSprite.texture = svg_to_texture(svgBaseString, zoomscale)
	$TileSelector.get_node("Tile_" + str(current_tile_idx)).texture = svg_to_texture(svgBaseString, PREVIEW_SCALE)
	svgOverlay.texture = svg_to_texture(overlayString, zoomscale)
	emit_signal("rendered")

func svg_to_texture(xml:String, scale_multiplier:float) -> ImageTexture:
	var img = Image.new()
	img.load_svg_from_string(xml, scale_multiplier)
	return ImageTexture.create_from_image(img)

func mousepos() -> Vector2:
	return get_tree().root.get_mouse_position()
func mousegrid() -> Vector2:
	return (mousepos() - gridpos) / zoomscale  # mousepos in grid coordinates
func mousegrid_round() -> Vector2i:
	return Vector2i(mousegrid().round())

func within_grid(point:Vector2i) -> bool:
	return point.x >= 0 and point.x <= gridsize.x and point.y >= 0 and point.y <= gridsize.y
func within_pixel_grid(point:Vector2i) -> bool:
	return point.x >= 0 and point.x < gridsize.x and point.y >= 0 and point.y < gridsize.y

func v2i_to_str(v:Vector2i) -> String:
	return str(v.x) + ',' + str(v.y)
func v2_to_str(v:Vector2) -> String:
	return str(v.x) + ',' + str(v.y)
func str_to_v2i(s:String) -> Vector2i:
	var split:PackedStringArray = s.split(',', false)
	return Vector2i(int(split[0]), int(split[1]))
func str_to_v2(s:String) -> Vector2:
	var split:PackedStringArray = s.split(',', false)
	return Vector2(float(split[0]), float(split[1]))

func circle_at_coord(coord:Vector2, c:Color, size:float) -> String:
	return '<circle r="'+str(size)+'" cx="'+str(coord.x)+'" cy="'+str(coord.y)+'" fill="#'+c.to_html(false)+'" />'

func line_from_to(coord1:Vector2, coord2:Vector2) -> String:
	return '<line x1="'+str(coord1.x)+'" y1="'+str(coord1.y)+'" x2="'+str(coord2.x)+'" y2="'+str(coord2.y)+'" style="stroke:#880000;stroke-width:0.1" />'

func svgHead(interface:bool) -> String:
	var padding:int = 0
	if interface:
		padding = 2
	return '<svg width="'+str(gridsize.x + padding) +'" height="'+str(gridsize.y + padding)+'" xmlns="http://www.w3.org/2000/svg">'

func zoom_in(factor:float) -> void:
	zoomscale -= factor * 1.0
	zoomscale = max(8.0, zoomscale)
	gridpos = mousepos() - (mousegrid() * zoomscale)
	update_grid()
func zoom_out(factor:float) -> void:
	zoomscale += factor * 1.0
	gridpos = mousepos() - (mousegrid() * zoomscale)
	update_grid()

func update_grid() -> void:
	var startingpos := Vector2(gridpos.x, gridpos.y)
	var penpos = startingpos
	var hline := Vector2(gridsize.x * zoomscale, 0)
	var vline := Vector2(0, gridsize.y * zoomscale)
	
	for line in $HContainer.get_children():
		line.set_point_position(0, penpos)
		line.set_point_position(1, penpos + hline)
		penpos += Vector2(0, zoomscale)
	penpos = startingpos
	for line in $VContainer.get_children():
		line.set_point_position(0, penpos)
		line.set_point_position(1, penpos + vline)
		penpos += Vector2(zoomscale, 0)
	
	render_svg()

	svgSprite.position = gridpos
	svgOverlay.position = gridpos - Vector2(zoomscale, zoomscale) # Consistent with _ready
	svgInterface.position = gridpos - Vector2(zoomscale, zoomscale) # Consistent with _ready



func layer_color_changed(_layerid, c) -> void:
	if c == '':
		layercolor = Palette.DEFAULT
	else:
		layercolor = '#' + c
	add_history()
	#paths[layerid].fill = layercolor
	render_svg()

func _on_save_button_pressed() -> void:
	save_svg()

func save_svg() -> void:
	var dir_path = "user://tiles"
	DirAccess.make_dir_recursive_absolute(dir_path)

	var current_file_path = "user://tiles/%03d.svg" % current_tile_idx
	var file = FileAccess.open(current_file_path, FileAccess.WRITE)
	file.store_string($XML.text)
	file.close()
	tiles[current_tile_idx] = $XML.text
	
	emit_signal('saved')
	

func _on_load_button_pressed() -> void:
	var svg_text:String = load_svg_text(current_tile_idx)
	set_paths(svg_text)

func load_svg_text(tile_idx:int) -> String:
	var current_file_path = "user://tiles/%03d.svg" % tile_idx
	if not FileAccess.file_exists(current_file_path):
		return ''
	var file = FileAccess.open(current_file_path, FileAccess.READ)
	var svg_text:String = file.get_as_text()
	file.close()
	return svg_text

func set_paths(svg_markup:String) -> void:
	# Takes in the full SVG Document, extracts each path data and appends those d strings to paths.
	paths.clear()
	var regex = RegEx.new()
	regex.compile('<path[^>]*d="([^"]+)"[^>]*/?>')
	for result in regex.search_all(svg_markup):
		var svg_d = result.get_string(1)
		paths.append(svg_d)
	render_svg()

func load_all_tiles() -> void:
	tiles.clear()
	for i in range(256):
		var svg_text:String = load_svg_text(i)
		tiles.append(svg_text)
		if not svg_text.is_empty():
			make_tile_texture(i, svg_text)

func get_tile_texture(idx: int) -> Texture2D:
	var svg_text = tiles[idx]
	if svg_text == '':
		return null
	var image = Image.new()
	if image.load_svg_from_string(svg_text, PREVIEW_SCALE) != OK:
		return null
	var tex = ImageTexture.create_from_image(image)
	return tex

func make_tile_texture(idx:int, svg_text:String) -> void:
	if not svg_text.is_empty():
		var img := Image.new()
		img.load_svg_from_string(svg_text, PREVIEW_SCALE)
		$TileSelector.get_node("Tile_" + str(idx)).texture = ImageTexture.create_from_image(img)

func select_tile(idx: int) -> void:
	make_tile_texture(current_tile_idx, tiles[current_tile_idx]) # make it black
	deselect_path()
	current_tile_idx = idx
	var svg_text = tiles[idx]
	set_paths(svg_text)
	history.clear()
	future.clear()
	emit_signal('history_modified', history.size(), future.size())

func deselect_path() -> void:
	var path_idx = selected_path_idx
	if not path_exists(path_idx):
		return
	var path_cmds := PathCommands.new(paths[path_idx])
	if path_cmds.is_zero_area():
		delete_path(path_idx)

	selected_path_idx = -1

func _on_tile_selected(idx: int) -> void:
	select_tile(idx)

func _on_clear_tile() -> void:
	add_history()
	paths.clear()
	render_svg()
	save_svg()

func _on_copypaste_tile(from:int) -> void:
	var svg_text = tiles[from]
	set_paths(svg_text) # also renders.
	save_svg()
