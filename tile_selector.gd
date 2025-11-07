extends Node2D

signal tile_selected(tile_idx: int)
signal copypaste_tile(from: int)
signal clear_tile()

const TILE_COLUMNS := 32
const TILE_ROWS := 8
const TILE_WIDTH := 8
const TILE_HEIGHT := 12
const PREVIEW_SCALE := 2.0 # this is defined in two places, a bit annoying.

var selected_idx: int = -1
var copy_idx:int = -1

var selection_rect: ColorRect
var background_rect: ColorRect

var tileset_is_last_click_context:bool = false

func _ready():
	background_rect = ColorRect.new()
	background_rect.color = Color("#484848") # dark gray background
	background_rect.size = Vector2(
		TILE_COLUMNS * TILE_WIDTH * PREVIEW_SCALE,
		TILE_ROWS * TILE_HEIGHT * PREVIEW_SCALE
	)
	background_rect.z_index = -2  # behind all
	add_child(background_rect)

	# Add highlight rectangle (only one)
	selection_rect = ColorRect.new()
	selection_rect.color = Color(0.2, 0.6, 1.0, 0.3) # bluish translucent
	selection_rect.size = Vector2(TILE_WIDTH * PREVIEW_SCALE, TILE_HEIGHT * PREVIEW_SCALE)
	add_child(selection_rect)
	selection_rect.visible = false
	selection_rect.z_index = -1  # behind tiles
	select_tile(0)

	# Create tile sprites
	for y in range(TILE_ROWS):
		for x in range(TILE_COLUMNS):
			var idx = x + y * TILE_COLUMNS
			var tile_sprite = Sprite2D.new()
			tile_sprite.name = "Tile_%d" % idx
			tile_sprite.position = Vector2(x * TILE_WIDTH * PREVIEW_SCALE, y * TILE_HEIGHT * PREVIEW_SCALE)
			tile_sprite.centered = false
			add_child(tile_sprite)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tileset_is_last_click_context = false
		var local_pos = to_local(event.position)
		var tile_x = int(local_pos.x / (TILE_WIDTH * PREVIEW_SCALE))
		var tile_y = int(local_pos.y / (TILE_HEIGHT * PREVIEW_SCALE))
		
		if tile_x >= 0 and tile_x < TILE_COLUMNS and tile_y >= 0 and tile_y < TILE_ROWS:
			tileset_is_last_click_context = true
			var tile_idx = tile_x + tile_y * TILE_COLUMNS
			select_tile(tile_idx)
			#emit_signal("tile_selected", tile_idx)
	
	elif event is InputEventKey:
		if not event.pressed: 
			return
		
		match event.keycode:
			KEY_C:
				if event.ctrl_pressed:
					if tileset_is_last_click_context:
						copy_idx = selected_idx
					else:
						copy_idx = -1
			KEY_V:
				if event.ctrl_pressed:
					if is_in_bounds(copy_idx):
						emit_signal("copypaste_tile", copy_idx)
			KEY_UP:
				if is_in_bounds(selected_idx - TILE_COLUMNS) and tileset_is_last_click_context:
					select_tile(selected_idx - TILE_COLUMNS)
			KEY_DOWN:
				if is_in_bounds(selected_idx + TILE_COLUMNS) and tileset_is_last_click_context:
					select_tile(selected_idx + TILE_COLUMNS)
			KEY_LEFT:
				if is_in_bounds(selected_idx - 1) and tileset_is_last_click_context:
					select_tile(selected_idx - 1)
			KEY_RIGHT:
				if is_in_bounds(selected_idx + 1) and tileset_is_last_click_context:
					select_tile(selected_idx + 1)
			KEY_HOME:
				if tileset_is_last_click_context:
					select_tile(0)
			KEY_END:
				if tileset_is_last_click_context:
					select_tile(255)
			KEY_DELETE:
				if tileset_is_last_click_context:
					emit_signal("clear_tile")

func is_in_bounds(idx:int) -> bool:
	return idx >= 0 and idx <= 255

func select_tile(idx: int) -> void:
	if idx == selected_idx:
		return
	selected_idx = idx
	var x = idx % TILE_COLUMNS
	@warning_ignore("integer_division")
	var y = idx / TILE_COLUMNS
	selection_rect.position = Vector2(x * TILE_WIDTH * PREVIEW_SCALE, y * TILE_HEIGHT * PREVIEW_SCALE)
	selection_rect.visible = true
	emit_signal("tile_selected", idx)
	
