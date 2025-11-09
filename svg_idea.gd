extends Node2D

const gridsize := Vector2i(8, 12)

var gridpos := Vector2(0,0)
var zoomscale:float = 36.0

var svgSprite:Sprite2D
var svgOverlay:Sprite2D
var svgInterface:Sprite2D
var svgPreview:Sprite2D
var svgString:String

const PREVIEW_SCALE = 2.0
const PREVIEW_COPIES_X = 32
const PREVIEW_COPIES_Y = 8
const HOVER_DIST = 0.35

const CANVAS_X = 164.0
const LAYERS_X = 514.0

var layercolor = "#CCC"

var history:Array # for undo
var future:Array # for redo
var paths:Array[String]

var clickdrag:bool = false
var clickdrag_startpos:Vector2
var pre_drag_state:Dictionary # a history state

var selected_point:PackedInt32Array # path index, segment index, coord index
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

func delete_path_if_zero_area(path_idx:int) -> void:
	if path_exists(path_idx):
		var segments:PackedStringArray = get_segments(path_idx)
		if is_zero_area_path(segments):
			delete_path(path_idx)

func _ready() -> void:
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
			#"painter":
				#if Rect2(Vector2.ZERO, gridsize).has_point(mousegrid.floor()):
					#if Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_RIGHT == MOUSE_BUTTON_MASK_RIGHT:
						#paint(Vector2i(mousegrid), 'empty')
					#else:
						#paint(Vector2i(mousegrid))
		# Clickdrag has been handled, return
		return
	
	# Mouse Motion but not clicking+dragging:
	var nearest:Vector2i = mousegrid_round()
	var dist:float = (mousegrid() - Vector2(nearest)).length()
	match $Tool.current:
		"maker":
			if dist < HOVER_DIST and within_grid(nearest):
				activate_interface(nearest) # any valid grid coord is highlighted.
		
		"selector":
			if dist < HOVER_DIST:
				handle_selector_mousemotion(nearest) # only points on the path are highlighted
				
		#"painter":
			#if Rect2(Vector2.ZERO, gridsize).has_point(mousegrid.floor()):
				#activate_tile(mousegrid.floor())

func handle_mouse_button(event:InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if $TileSelector.tileset_is_last_click_context:
					return
				if svgInterface.visible:
					match $Tool.current:
						"maker": makepath()
						"selector": left_click_select()
						#"painter": paint()
				else:
					if $Tool.current == "selector":
						var prev_selected = selected_path_idx
						deselect_path()
						for i in range (paths.size()):
							if is_point_in_fill(paths[i], mousegrid()):
								selected_path_idx = i
						if prev_selected != selected_path_idx:
							render_svg()
				if $Tool.current == 'maker':
					if svgInterface.visible:
						start_drag()
				else:
					start_drag()
			else:
				end_drag()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if svgInterface.visible:
					match $Tool.current:
						"selector":
							right_click_select()
						#"painter":
							#paint(Vector2i(mousegrid), 'empty')
					start_drag()
			else:
				end_drag()
		
		#MOUSE_BUTTON_MIDDLE:
			#mid_clickdrag = event.pressed
		#MOUSE_BUTTON_WHEEL_UP:
			#zoom_out(event.factor)
		#MOUSE_BUTTON_WHEEL_DOWN:
			#zoom_in(event.factor)
			
	

func keycheck(event:InputEventKey) -> bool:
	return event.pressed and not $TileSelector.tileset_is_last_click_context

func handle_key(event:InputEventKey) -> void:
	match event.keycode:
		KEY_Z:
			if event.pressed and event.ctrl_pressed and not $TileSelector.tileset_is_last_click_context:
				if event.shift_pressed:
					redo()
				else:
					undo()
		KEY_C:
			if event.pressed and event.ctrl_pressed: # and $Tool.current == "selector":
				if $TileSelector.tileset_is_last_click_context:
					copied_path = ''
				else:
					copy_selected_path()
		KEY_V:
			if event.pressed and event.ctrl_pressed: # and $Tool.current == "selector":
				paste_copied_path()
		KEY_UP:
			if keycheck(event):
				try_move(0,-1)
		KEY_DOWN:
			if keycheck(event):
				try_move(0,1)
		KEY_LEFT:
			if keycheck(event):
				try_move(-1,0)
		KEY_RIGHT:
			if keycheck(event):
				try_move(1,0)
		KEY_DELETE:
			if keycheck(event):
				delete_path(selected_path_idx)
		KEY_BRACKETLEFT:
			if keycheck(event):
				transform_path(selected_path_idx, 'rotate_ccw')
		KEY_BRACKETRIGHT:
			if keycheck(event):
				transform_path(selected_path_idx, 'rotate_cw')
		KEY_H:
			if keycheck(event):
				transform_path(selected_path_idx, 'flip_h')
		KEY_F:
			if keycheck(event):
				transform_path(selected_path_idx, 'flip_v')

func transform_path(path_idx: int, mode: String) -> void:
	if not path_exists(path_idx):
		return

	var segs = paths[path_idx].split('|', false)

	# Collect points
	var points: Array[Vector2i] = []
	for seg in segs:
		var parts = seg.split(' ')
		for i in range(1, parts.size()):
			points.append(str_to_v2i(parts[i]))

	if points.is_empty():
		return

	# Bounding box
	var min_x = points[0].x
	var max_x = points[0].x
	var min_y = points[0].y
	var max_y = points[0].y
	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)

	var pivot = Vector2i(min_x, min_y)
	var width = max_x - min_x
	var height = max_y - min_y

	# Transform points
	for i in range(points.size()):
		var p = points[i] - pivot
		match mode:
			"flip_h":
				p.x = width - p.x
			"flip_v":
				p.y = height - p.y
			"rotate_cw":
				p = Vector2i(height - p.y, p.x)
			"rotate_ccw":
				p = Vector2i(p.y, width - p.x)
		points[i] = p + pivot

	# Rebuild the path
	var new_segs: Array[String] = []
	var idx = 0
	for seg in segs:
		var parts = seg.split(' ')
		var cmd = parts[0]
		var new_seg: Array[String] = [cmd]
		for i in range(1, parts.size()):
			var p = points[idx]
			new_seg.append("%d,%d" % [p.x, p.y])
			idx += 1
		new_segs.append(' '.join(new_seg))

	add_history()
	paths[path_idx] = '|'.join(new_segs)
	render_svg()
	save_svg()

func copy_selected_path() -> void:
	if path_exists(selected_path_idx):
		copied_path = paths[selected_path_idx]

func paste_copied_path() -> void:
	if copied_path.is_empty():
		return
	
	add_history()

	# Offset path a little so it's visible and not overlapping perfectly
	var offset_path = move_path(copied_path, PASTE_OFFSET.x, PASTE_OFFSET.y)
	paths.append(offset_path)
	selected_path_idx = paths.size() - 1
	render_svg()
	save_svg()

func handle_selector_mousemotion(nearest:Vector2i) -> void:
	# All this does, is activate_interface(nearest) if nearest is a point or ctrl_pt position.
	var points:Array = []
	var ctrl_pts:Array = []
	if path_exists(selected_path_idx):
		var path = paths[selected_path_idx]
		var segments:PackedStringArray = path.split('|', false)
		for segment in segments:
			match segment[0]:
				'M':
					points.append(segment.split(' ', false)[1])
				'C':
					var split:PackedStringArray = segment.split(' ', false)
					ctrl_pts.append(split[1])
					ctrl_pts.append(split[2])
					points.append(split[3])
		for point in points:
			if nearest == str_to_v2i(point):
				activate_interface(nearest)
		for point in ctrl_pts:
			if nearest == str_to_v2i(point):
				activate_interface(nearest)

func handle_maker_clickdrag() -> void:
	var coord:Vector2i = mousegrid_round()
	if paths.is_empty(): return
	var segments:PackedStringArray = get_segments(paths.size()-1)
	if segments.is_empty(): return
	var final_segment:String = segments[segments.size()-1]
	var components:PackedStringArray = final_segment.split(' ', false)
	if components.size() < 3: return
	var ctrl_pt_2:Vector2i = str_to_v2i(components[2])
	if coord != ctrl_pt_2:
		components[2] = v2i_to_str(coord)
		final_segment = ' '.join(components)
		segments[segments.size()-1] = final_segment
		paths[paths.size()-1] = '|'.join(segments)
		render_svg()

func handle_selector_clickdrag() -> void:
	if selected_point.size() == 3:
		# moving a single point
		var path_idx:int = selected_point[0]
		var seg_idx:int = selected_point[1]
		var comp_idx:int = selected_point[2]
		
		var segments:PackedStringArray = paths[path_idx].split('|', false)
		
		var components:PackedStringArray = segments[seg_idx].split(' ', false)
		var current_pos:Vector2i = str_to_v2i(components[comp_idx])
		var diff:Vector2i = mousegrid_round() - current_pos
		
		if diff != Vector2i.ZERO:
			adjust_segment(seg_idx, comp_idx, diff, segments)
			
			# Now logic to determine which other points to adjust (control pts, etc).
			var is_closed:bool = segments[segments.size()-1] == 'Z'
			var last_idx:int = segments.size() - (2 if is_closed else 1)
			var is_first:bool = (seg_idx == 0)
			var is_last:bool = (seg_idx == last_idx)
			var element_status := "normal"
			if is_closed:
				if is_first: element_status = "first_closed"
				elif is_last: element_status = "last_closed"
			elif is_first and is_last:
				element_status = "only"
			elif is_first:
				element_status = "first"
			elif is_last:
				element_status = "last"
			
			if comp_idx == 3 or element_status == "first" or element_status == "first_closed":
				match element_status:
					"normal":
						# adjust current point control point 2
						adjust_segment(seg_idx, 2, diff, segments)
						# and next point control point 1
						adjust_segment(seg_idx+1, 1, diff, segments)
					"last_closed":
						# adjust final point control point 2
						adjust_segment(seg_idx, 2, diff, segments)
						# we're treating the first and last point as a unified point.
						# need to move the M point, (0, 1) and the first C cmd control point (1, 1)
						adjust_segment(0, 1, diff, segments)
						adjust_segment(1, 1, diff, segments)
					"first_closed":
						# NOTE the selection tool probably won't ever hit this
						# as it will always overlap and prioritize the last pt
						adjust_segment(seg_idx+1, 1, diff, segments)
						adjust_segment(last_idx, 2, diff, segments)
					"first":
						adjust_segment(seg_idx+1, 1, diff, segments)
					"last":
						adjust_segment(seg_idx, 2, diff, segments)
					"only":
						pass
			paths[path_idx] = '|'.join(segments)

			render_svg()
			#save_svg()
	
	elif selected_point.size() == 0:
		# moving the entire path
		if selected_path_idx >= 0 and selected_path_idx < paths.size():
			var diff:Vector2 = (mousegrid() - clickdrag_startpos).round()
			clickdrag_startpos += diff
			if not diff.is_equal_approx(Vector2.ZERO):
				paths[selected_path_idx] = move_path(paths[selected_path_idx], int(diff.x), int(diff.y))
				render_svg()
				#save_svg()

func collapse_adjacent_duplicate_points(segments: PackedStringArray) -> PackedStringArray:
	var points: Array[Vector2i] = []
	var closed := false

	# Extract representative endpoints (M and C end points)
	for segment in segments:
		var comps := segment.split(" ", false)
		if comps.size() == 0:
			points.append(null)
			continue
		match comps[0]:
			"M":
				points.append(str_to_v2i(comps[1]))
			"C":
				if comps.size() > 3:
					points.append(str_to_v2i(comps[3])) # end point
				else:
					points.append(null)
			"Z":
				closed = true
				# don't append a point for Z
			_:
				points.append(null)

	# If empty or only M, nothing to do
	if points.size() == 0:
		return segments.duplicate()

	var cleaned := PackedStringArray()
	
	# Keep the first segment (usually "M ...")
	cleaned.append(segments[0])
	var last_kept_point := points[0]

	# For subsequent segments, keep them only if their endpoint differs from last_kept_point.
	for i in range(1, points.size()):
		var p := points[i]
		if p == null:
			# If we can't determine the endpoint safely, keep the segment to be conservative
			cleaned.append(segments[i])
			# don't change last_kept_point
		else:
			if last_kept_point == null or p != last_kept_point:
				cleaned.append(segments[i])
				last_kept_point = p
			else:
				# Skip this segment (it is redundant — its endpoint duplicates the previous)
				# Do nothing (this is the key difference from your old code)
				pass

	# Handle closed: if path is closed and last kept endpoint equals first endpoint,
	# we may want to ensure Z is present and not duplicate endpoints. Append "Z" if original had it.
	if closed:
		#if cleaned.size() > 2:
			## Keep it open if it is merely a line.
		cleaned.append("Z")

	return cleaned

func activate_interface(where:Vector2i) -> void:
	svgInterface.show()

	# Yellow circle at cursor
	var circle1 = '<circle r="0.2" cx="' + str(where.x+1) + '" cy="' + str(where.y+1) + '" stroke="#ffff99" stroke-width="0.1" fill="none" />'

	# Red circle at nearest control point using offset
	var nearest_cp_offset:Vector2
	var best_dist:float = INF
	var visual_offset:float = 0.1

	if path_exists(selected_path_idx):
		var segments:PackedStringArray = paths[selected_path_idx].split('|', false)
		var mouse_pos:Vector2 = mousegrid()

		for j in range(segments.size()):
			var s = segments[j].split(' ', false)
			if s[0] != "C":
				continue

			for which in [1, 2]:
				var offset_point:Vector2 = get_control_offset(j, which, segments, visual_offset)
				var dist:float = mouse_pos.distance_to(offset_point)
				if dist < best_dist:
					best_dist = dist
					nearest_cp_offset = offset_point

	var circle2 = ""
	if nearest_cp_offset != null:
		circle2 = '<circle r="0.1" cx="' + str(nearest_cp_offset.x+1) + '" cy="' + str(nearest_cp_offset.y+1) + '" stroke="none" fill="#ffffff" />'

	var interfaceString = svgHead(true) + circle1 + circle2 + '</svg>'
	var img := Image.new()
	img.load_svg_from_string(interfaceString, zoomscale)
	svgInterface.texture = ImageTexture.create_from_image(img)

func get_control_offset_along_curve(seg_idx:int, which:int, segments:PackedStringArray, offset_amount:float) -> Vector2:
	var s:PackedStringArray = segments[seg_idx].split(' ', false)

	var control:Vector2
	if which == 1:
		control = str_to_v2i(s[1])
	else:
		control = str_to_v2i(s[2])

	# Previous segment
	var prev_idx:int = seg_idx - 1
	if prev_idx < 0:
		prev_idx = segments.size() - 1
	var ps:PackedStringArray = segments[prev_idx].split(' ', false)
	var prev_anchor:Vector2
	if ps[0] == "C":
		prev_anchor = str_to_v2i(ps[3])
	else:
		prev_anchor = str_to_v2i(ps[1])

	var next_anchor:Vector2 = str_to_v2i(s[3])

	var tangent:Vector2

	if which == 1:
		tangent = 3 * (control - prev_anchor)
	else:
		tangent = 3 * (next_anchor - control)

	if tangent.length() > 0.0001:
		tangent = tangent.normalized()
	else:
		tangent = Vector2.ZERO

	# Offset along curve
	var offset_point:Vector2 = control + tangent * offset_amount
	return offset_point

# Helper to compute the "offset" position for a control point
func get_control_offset(seg_idx:int, which:int, segments:PackedStringArray, visual_offset:float) -> Vector2:
	var s:PackedStringArray = segments[seg_idx].split(' ', false)

	# Control coordinate
	var control:Vector2
	if which == 1:
		control = str_to_v2i(s[1])
	else:
		control = str_to_v2i(s[2])

	# Previous segment
	var prev_idx:int = seg_idx - 1
	if prev_idx < 0:
		prev_idx = segments.size() - 1
	var ps:PackedStringArray = segments[prev_idx].split(' ', false)
	var prev_anchor:Vector2
	if ps[0] == "C":
		prev_anchor = str_to_v2i(ps[3])
	else:
		prev_anchor = str_to_v2i(ps[1])

	var next_anchor:Vector2 = str_to_v2i(s[3])

	# Determine offset
	var offset_point:Vector2
	if (which == 1 and control == prev_anchor) or (which == 2 and control == next_anchor):
		# Control coincides with anchor → offset toward next anchor
		var target_anchor:Vector2
		if which == 1:
			target_anchor = next_anchor
		else:
			target_anchor = prev_anchor

		var dir:Vector2 = target_anchor - control
		if dir.length() > 0.0001:
			dir = dir.normalized()
		else:
			dir = Vector2.ZERO
		offset_point = control + dir * visual_offset
	else:
		# Control not at anchor → offset back toward its anchor
		var anchor:Vector2
		if which == 1:
			anchor = prev_anchor
		else:
			anchor = next_anchor

		var dir:Vector2 = anchor - control
		if dir.length() > 0.0001:
			dir = dir.normalized()
		else:
			dir = Vector2.ZERO
		offset_point = control + dir * visual_offset

	return offset_point

func activate_interface3(where:Vector2i) -> void:
	# This shows the interface (which is used as a flag elsewhere), 
	# and visually draws a circle at that location.
	svgInterface.show()
	var circle = '<circle r="0.2" cx="'+str(where.x+1)+'" cy="'+str(where.y+1)+'" stroke="#ffff99" stroke-width="0.1" fill="none" />'
	var interfaceString = svgHead(true) + circle + '</svg>'
	var img := Image.new()
	img.load_svg_from_string(interfaceString, zoomscale)
	svgInterface.texture = ImageTexture.create_from_image(img)

func try_move(x:int, y:int) -> void:
	if path_exists(selected_path_idx):
		add_history()
		paths[selected_path_idx] = move_path(paths[selected_path_idx], x, y)
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
	future.clear()
	emit_signal('history_modified', history.size(), future.size())

func start_drag() -> void:
	clickdrag = true
	clickdrag_startpos = mousegrid()
	pre_drag_state = get_snapshot()

func get_segments(path_idx:int) -> PackedStringArray:
	if path_exists(path_idx):
		return paths[path_idx].split('|', false)
	return PackedStringArray()

func end_drag() -> void:
	# moving a single point
	if selected_point.size() == 3:
		var path_idx:int = selected_point[0]
		var segments:PackedStringArray = get_segments(path_idx)
		segments = collapse_adjacent_duplicate_points(segments)
		
		if is_zero_area_path(segments):
			delete_path(path_idx)
		else:
			paths[path_idx] = '|'.join(segments)
	
	clickdrag = false
	selected_point.clear()
	
	if pre_drag_state.is_empty():
		return
	if paths != pre_drag_state.paths:
		append_to_history(pre_drag_state.duplicate(true))
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
		hex_node.text = colorstring
		hex_node.path_index = i

func adjust_segment(idx:int, pos:int, diff:Vector2i, segments:PackedStringArray) -> void:
	var components:PackedStringArray = segments[idx].split(' ', false)
	components[pos] = v2i_to_str(str_to_v2i(components[pos]) + diff)
	segments[idx] = ' '.join(components)

func left_click_select() -> void:
	if not path_exists(selected_path_idx): 
		return
	var segments:PackedStringArray = paths[selected_path_idx].split('|', false)
	var coord:Vector2i = mousegrid_round()
	for j in range(segments.size()):
		var s = segments[j].split(' ', false)
		# s[0] is the letter, s[1,2,3] are the coords.
		match s[0]:
			'M':
				if coord == str_to_v2i(s[1]):
					selected_point = [selected_path_idx,j,1]
			'C':
				if coord == str_to_v2i(s[3]):
					selected_point = [selected_path_idx,j,3]

func right_click_select() -> void:
	if not path_exists(selected_path_idx):
		return

	var segments:PackedStringArray = paths[selected_path_idx].split('|', false)
	var mouse_pos:Vector2 = mousegrid()
	var coord:Vector2i = mousegrid_round()
	var candidates:Array = []

	# collect candidates under cursor
	for j in range(segments.size()):
		var s = segments[j].split(' ', false)
		if s[0] != "C":
			continue

		var c1:Vector2i = str_to_v2i(s[1])
		var c2:Vector2i = str_to_v2i(s[2])

		if coord == c1:
			candidates.append([selected_path_idx, j, 1])
		if coord == c2:
			candidates.append([selected_path_idx, j, 2])

	if candidates.size() == 0:
		return

	var best_candidate = null
	var best_dist:float = INF
	var visual_offset:float = 0.1

	for cand in candidates:
		var seg_idx:int = cand[1]
		var which:int = cand[2]
		var offset_point:Vector2 = get_control_offset(seg_idx, which, segments, visual_offset)
		var dist:float = mouse_pos.distance_to(offset_point)

		if dist < best_dist:
			best_dist = dist
			best_candidate = cand

	if best_candidate != null:
		selected_point = best_candidate

func makepath() -> void:
	var coord:Vector2i = mousegrid_round()
	if not within_grid(coord):
		return
	
	add_history()
	
	var path:String = ''
	if not paths.is_empty():
		if not paths.back().ends_with('Z'):
			path = paths.back()
	
	var nextpoint:String = v2i_to_str(coord)
	if path.is_empty():
		path = 'M ' + nextpoint
		paths.append(path)
	else:
		# This is fragile and could be reworked.
		var numbers_only:String = path.replace('M', '').replace('C', '').replace('Z', '').replace('|', '')
		var pairs:PackedStringArray = numbers_only.split(' ', false)
		var prevpoint:String = pairs[pairs.size()-1]
		
		if nextpoint == prevpoint:
			return
		
		# for now the control points will be at the prevpoint and the nextpoint, making it straight
		path += '|'
		path += ' '.join(['C', prevpoint, nextpoint, nextpoint])
		# check initial point to see if it matches new point:
		var first_coord:String = path.get_slice('|', 0).get_slice(' ', 1)
		if str_to_v2i(first_coord) == coord:
			path += '|Z'  # Close Path
			var segments:PackedStringArray = get_segments(selected_path_idx)
			if is_zero_area_path(segments):
				delete_path(selected_path_idx)
				return
			
		paths[paths.size()-1] = path
	
	selected_path_idx = paths.size() - 1
	render_svg()
	save_svg()

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


func paint(tile:Vector2i, tiletype:String = 'pixel') -> void:
	add_history()
	
	var path:String = ''
	#var path:Dictionary = {
		#'d': '',
		#'fill': layercolor
	#}
	
	if not paths.is_empty():
		path = paths.back()
	
	var nextpoint:String = v2i_to_str(tile)
	if path.is_empty():
		paths.append(path)
	
	match tiletype:
		'pixel':
			var segments:PackedStringArray = path.split('|', false)
			for i in range (segments.size()):
				if segments[i] == ('M ' + nextpoint):
					return
			path += 'M ' + nextpoint + '|' 
			path += 'L ' + v2i_to_str(tile + Vector2i.RIGHT) + '|'
			path += 'L ' + v2i_to_str(tile + Vector2i(1,1)) + '|'
			path += 'L ' + v2i_to_str(tile + Vector2i.DOWN) + '|'
			path += 'Z' + '|'
		'empty':
			var segments:PackedStringArray = path.split('|', false)
			for i in range (segments.size()):
				if segments[i] == ('M ' + nextpoint):
					var removecount:int = 1
					while segments[i+removecount][0] != 'Z':
						removecount += 1
					for j in range (removecount+1):
						segments.remove_at(i)
					break
			path = '|'.join(segments) + '|'
	
	render_svg()
	

func render_svg() -> void:
	if $Layers.get_child_count() != paths.size():
		sync_layers_ui()
	
	var circles:String = ''
	var controlpts:String = ''
	
	var overlay:String = ''
	
	if selected_path_idx != -1 and not paths.is_empty():
		# Make Overlay
		var prev_pt:Vector2i
		var pathviz:String = ''
		var segments:PackedStringArray = paths[selected_path_idx].split('|', false)
		for segment in segments:
			var s = segment.split(' ', false)
			# s[0] is the letter, s[1,2,3] are the coords.
			match s[0]:
				'M':
					var start_pt:Vector2i = str_to_v2i(s[1])
					prev_pt = start_pt
					circles += circle_at_coord(Vector2(start_pt) + Vector2.ONE,  Color(0,0,0), 0.2) 
					pathviz += 'M ' + v2i_to_str(start_pt + Vector2i.ONE)
				'L':
					var end_pt:Vector2i = str_to_v2i(s[1])
					circles += circle_at_coord(Vector2(end_pt) + Vector2.ONE,  Color(0,0,0), 0.2)
					pathviz += 'L ' + v2i_to_str(end_pt + Vector2i.ONE)
					prev_pt = end_pt
				'C':
					var ctrl_pt_1:Vector2i = str_to_v2i(s[1])
					var ctrl_pt_2:Vector2i = str_to_v2i(s[2])
					var end_pt:Vector2i    = str_to_v2i(s[3])
					
					var ctrl_viz_1:Vector2 = Vector2(ctrl_pt_1)
					var ctrl_viz_2:Vector2 = Vector2(ctrl_pt_2)
					
					var diff:Vector2i = end_pt - prev_pt
					
					var move_amt:float = 0.1
					if ctrl_pt_1 == prev_pt:
						ctrl_viz_1 = Vector2(prev_pt) + (Vector2(diff).normalized() * move_amt)
					else:
						ctrl_viz_1 = ctrl_viz_1.move_toward(prev_pt, move_amt)
					if ctrl_pt_2 == end_pt:
						ctrl_viz_2 = Vector2(end_pt) - (Vector2(diff).normalized() * move_amt)
					else:
						ctrl_viz_2 = ctrl_viz_2.move_toward(end_pt, move_amt)
					
					controlpts += line_from_to(ctrl_viz_1 + Vector2.ONE, Vector2(prev_pt) + Vector2.ONE)
					controlpts += line_from_to(ctrl_viz_2 + Vector2.ONE, Vector2(end_pt) + Vector2.ONE)
							
					circles += circle_at_coord(Vector2(end_pt) + Vector2.ONE,  Color(0,0,0), 0.2)
					controlpts += circle_at_coord(ctrl_viz_1 + Vector2.ONE,  Color(1,0,0), 0.1)
					controlpts += circle_at_coord(ctrl_viz_2 + Vector2.ONE,  Color(1,0,0), 0.1)
					
					pathviz += ' '
					pathviz += 'C ' + v2i_to_str(ctrl_pt_1 + Vector2i.ONE) + ' '
					pathviz += v2i_to_str(ctrl_pt_2 + Vector2i.ONE) + ' '
					pathviz += v2i_to_str(end_pt    + Vector2i.ONE) + ' '
						
					prev_pt = end_pt
				'Z':
					pathviz += 'Z'
			
		overlay = '<path d="'+ pathviz.replace('|', ' ') +'" style="stroke:#000;stroke-width:0.1;fill:none" />'
	
	var complete_paths:PackedStringArray
	var nostyle_paths:PackedStringArray
	
	for path in paths:
		complete_paths.append('<path d="'+ path.replace('|', ' ') +'" style="stroke:none;fill:'+ layercolor +'" />')
	for path in paths:
		nostyle_paths.append('<path d="'+ path.replace('|', ' ') +'" />')
	
	var nostyleString = svgHead(false)
	for path in nostyle_paths:
		nostyleString += path
	nostyleString += '</svg>'
	
	svgString = svgHead(false)
	for path in complete_paths:
		svgString += path
	svgString += '</svg>'
	
	$XML.update_text(nostyleString)

	var img := Image.new()
	img.load_svg_from_string(svgString, zoomscale)
	svgSprite.texture = ImageTexture.create_from_image(img)
	
	img = Image.new()
	img.load_svg_from_string(svgString, PREVIEW_SCALE)
	$TileSelector.get_node("Tile_" + str(current_tile_idx)).texture = ImageTexture.create_from_image(img)
	
	#for c in get_children():
		#if c.name.begins_with('prev'):
			#c.texture = svgPreview.texture
	
	svgString = svgHead(true)
	svgString += overlay
	svgString += circles
	svgString += controlpts
	svgString += '</svg>'
	
	img = Image.new()
	img.load_svg_from_string(svgString, zoomscale)
	svgOverlay.texture = ImageTexture.create_from_image(img)
	
	emit_signal('rendered')

func delete_invisible_or_zero_area_paths(rect: Rect2i) -> void:
	var kept_paths: Array[String] = []
	for path in paths:
		var segments: PackedStringArray = path.split("|", false)
		var has_area := not is_zero_area_path(segments)
		var bbox := get_path_bounds(segments)
		var in_canvas := rect.intersects(bbox)
		
		if has_area and in_canvas:
			kept_paths.append(path)
		else:
			print("Removed hidden/empty path:", path)
	
	if kept_paths.size() != paths.size():
		paths = kept_paths
		render_svg()
		save_svg()

func get_path_bounds(segments: PackedStringArray) -> Rect2i:
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for seg in segments:
		var comps = seg.split(" ", false)
		match comps[0]:
			"M", "C":
				for i in range(1, comps.size()):
					if comps[i].find(",") != -1:
						var p = str_to_v2i(comps[i])
						min_x = min(min_x, p.x)
						min_y = min(min_y, p.y)
						max_x = max(max_x, p.x)
						max_y = max(max_y, p.y)
	
	if min_x == INF:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x, max_y - min_y))

func mousepos() -> Vector2:
	return get_tree().root.get_mouse_position()
func mousegrid() -> Vector2:
	return (mousepos() - gridpos) / zoomscale  # mousepos in grid coordinates
func mousegrid_round() -> Vector2i:
	return Vector2i(mousegrid().round())

func within_grid(point:Vector2i) -> bool:
	return point.x >= 0 and point.x <= gridsize.x and point.y >= 0 and point.y <= gridsize.y

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

func set_paths(svg_text:String) -> void:
	paths.clear()
	var regex = RegEx.new()
	regex.compile('<path[^>]*d="([^"]+)"[^>]*/?>')
	for result in regex.search_all(svg_text):
		var svg_d = result.get_string(1)
		# Convert from SVG syntax to internal format (' ' -> '|')
		var internal_d = svg_to_internal_d(svg_d)
		paths.append(internal_d)
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
	
	var segments: PackedStringArray = paths[path_idx].split("|", false)
	
	if is_zero_area_path(segments):
		delete_path(path_idx)
	selected_path_idx = -1

func is_zero_area_path(segments: PackedStringArray) -> bool:
	var points: Array = []

	for segment in segments:
		var components = segment.split(' ')
		match components[0]:
			"M", "L":
				points.append(str_to_v2i(components[1]))
			"C":
				for i in range(1, 4):
					points.append(str_to_v2i(components[i]))

	# remove duplicates
	var unique_points := []
	for p in points:
		if not p in unique_points:
			unique_points.append(p)
	points = unique_points

	if points.size() <= 2:
		return true

	# check collinearity
	var p0 = points[0]
	var p1 = points[1]
	var dx = p1.x - p0.x
	var dy = p1.y - p0.y

	for i in range(2, points.size()):
		var pi = points[i]
		if (pi.x - p0.x) * dy != (pi.y - p0.y) * dx:
			return false

	return true

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

func svg_to_internal_d(svg_d:String) -> String:
	svg_d = svg_d.strip_edges()
	
	# Remove spaces immediately before command letters
	var regex_cleanup = RegEx.new()
	regex_cleanup.compile(r"\s+(?=[MLCQZmlcqz])")
	svg_d = regex_cleanup.sub(svg_d, "", true)
	
	# Insert '|' before command letters (except first)
	var regex_insert = RegEx.new()
	regex_insert.compile("(?<!^)(?=[MLCQZmlcqz])")
	svg_d = regex_insert.sub(svg_d, "|", true)
	
	# Normalize remaining extra spaces inside coords
	var regex_spaces = RegEx.new()
	regex_spaces.compile("\\s+")
	svg_d = regex_spaces.sub(svg_d, " ", true)
	
	return svg_d

func parse_svg_path(d: String) -> Array:
	var cmds := []
	var re := RegEx.new()
	re.compile(r"[MmLlHhVvCcQqAaZz]|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?")
	var t := []
	for m in re.search_all(d): t.append(m.get_string())
	var i := 0
	var cmd := ""
	while i < t.size():
		if t[i].is_valid_ascii_identifier(): cmd = t[i]; i += 1
		var rel := cmd == cmd.to_lower()
		var c := cmd.to_upper()
		var n := []
		while i < t.size() and not t[i].is_valid_ascii_identifier():
			n.append(float(t[i])); i += 1
		cmds.append({"cmd": c, "rel": rel, "nums": n})
	return cmds

func is_point_in_fill(d: String, point:Vector2) -> bool:
	var path := parse_svg_path(d)
	var pts := []
	var x := 0.0
	var y := 0.0
	var sx := 0.0
	var sy := 0.0

	for seg in path:
		var n = seg.nums
		match seg.cmd:
			"M":
				x = n[0]; y = n[1]
				if seg.rel: x += sx; y += sy
				sx = x; sy = y
				pts.append(Vector2(x, y))
			"L":
				for i in range(0, n.size(), 2):
					var nx = n[i]; var ny = n[i+1]
					if seg.rel: nx += x; ny += y
					x = nx; y = ny
					pts.append(Vector2(x, y))
			"H":
				for v in n:
					if seg.rel: x += v
					else: x = v
					pts.append(Vector2(x, y))
			"V":
				for v in n:
					if seg.rel: y += v
					else: y = v
					pts.append(Vector2(x, y))
			"C":
				for i in range(0, n.size(), 6):
					var x1=n[i]; var y1=n[i+1]; var x2=n[i+2]; var y2=n[i+3]; var x3=n[i+4]; var y3=n[i+5]
					if seg.rel: x1+=x; y1+=y; x2+=x; y2+=y; x3+=x; y3+=y
					for t in range(1, 11):
						var tt = t/10.0
						var xt = pow(1-tt,3)*x + 3*pow(1-tt,2)*tt*x1 + 3*(1-tt)*pow(tt,2)*x2 + pow(tt,3)*x3
						var yt = pow(1-tt,3)*y + 3*pow(1-tt,2)*tt*y1 + 3*(1-tt)*pow(tt,2)*y2 + pow(tt,3)*y3
						pts.append(Vector2(xt, yt))
					x=x3; y=y3
			"Q":
				for i in range(0, n.size(), 4):
					var x1=n[i]; var y1=n[i+1]; var x2=n[i+2]; var y2=n[i+3]
					if seg.rel: x1+=x; y1+=y; x2+=x; y2+=y
					for t in range(1, 11):
						var tt = t/10.0
						var xt = pow(1-tt,2)*x + 2*(1-tt)*tt*x1 + pow(tt,2)*x2
						var yt = pow(1-tt,2)*y + 2*(1-tt)*tt*y1 + pow(tt,2)*y2
						pts.append(Vector2(xt, yt))
					x=x2; y=y2
			# WARNING apparently this isn't complete but I'm not using A right now so it's fine.
			"A": # simple circle/ellipse arc approximation 
				for i in range(0, n.size(), 7):
					var rx=n[i]; var ry=n[i+1]; var phi=deg_to_rad(n[i+2])
					var _large_arc=n[i+3]; var sweep=n[i+4]
					var x2=n[i+5]; var y2=n[i+6]
					if seg.rel: x2+=x; y2+=y
					for t in range(1, 11):
						var tt = t/10.0
						var ang = phi + tt * TAU/8 * (sweep*2-1)
						var xt = lerp(x, x2, tt) + cos(ang)*rx
						var yt = lerp(y, y2, tt) + sin(ang)*ry
						pts.append(Vector2(xt, yt))
					x=x2; y=y2
			"Z":
				pts.append(Vector2(sx, sy))
				x=sx; y=sy

	# --- Ray casting test ---
	var inside := false
	for i in range(pts.size()):
		var a = pts[i]
		var b = pts[(i + 1) % pts.size()]
		if ((a.y > point.y) != (b.y > point.y)) and (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y + 0.000001) + a.x):
			inside = !inside
	return inside


func move_path(path: String, dx: int, dy: int) -> String:
	var result := []
	for seg in path.split("|", false):
		if seg.strip_edges() == "":
			continue
		var cmd = seg[0]
		if cmd == "Z" or cmd == "z":
			result.append(cmd)
			continue
		var coords = seg.substr(1).strip_edges().split(" ", false)
		var out = []
		for c in coords:
			var xy = c.split(",", false)
			if xy.size() == 2:
				var x:int = int(xy[0]) + dx
				var y:int = int(xy[1]) + dy
				out.append("%s,%s" % [x, y])
		result.append("%s %s" % [cmd, " ".join(out)])
	return "|".join(result)

# Thanks ChatGPT
