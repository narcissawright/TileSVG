extends Node

var pos = Vector2(20, 100)
const COLOR_SIZE = Vector2(40, 40)
const COLUMNS = 4
const SPACING = 12

func _ready():
	var _color_names = [
		"Black", "White", "Gray", "Red",
		"Green", "Blue", "Yellow", "Orange",
		"Pink", "Cyan", "Purple", "Brown",
		"Light Green", "Sky Blue", "Dark Gray", "Dark Red"
	]

	var palette = [
		Color(0.0, 0.0, 0.0),       # Black
		Color(1.0, 1.0, 1.0),       # White
		Color(0.5, 0.5, 0.5),       # Gray
		Color(1.0, 0.0, 0.0),       # Red
		Color(0.0, 1.0, 0.0),       # Green
		Color(0.0, 0.0, 1.0),       # Blue
		Color(1.0, 1.0, 0.0),       # Yellow
		Color(1.0, 0.5, 0.0),       # Orange
		Color(1.0, 0.4, 0.7),       # Pink
		Color(0.0, 1.0, 1.0),       # Cyan
		Color(0.5, 0.0, 0.5),       # Purple
		Color(0.6, 0.3, 0.1),       # Brown
		Color(0.5, 1.0, 0.5),       # Light Green
		Color(0.4, 0.7, 1.0),       # Sky Blue
		Color(0.25, 0.25, 0.25),    # Dark Gray
		Color(0.5, 0.0, 0.0)        # Dark Red
	]

	var bgrect = ColorRect.new()
	bgrect.color = Color("#333333")
	bgrect.size.x = 2 + (40 + 2) * 4
	bgrect.size.y = bgrect.size.x
	bgrect.position = pos
	add_child(bgrect)

	for i in palette.size():
		var color = palette[i]

		var x = i % COLUMNS
		@warning_ignore("integer_division")
		var y = i / COLUMNS

		# Create ColorRect
		var rect = ColorRect.new()
		rect.color = color
		rect.size = COLOR_SIZE
		rect.position = pos + Vector2(2,2) + Vector2(x, y) * (COLOR_SIZE + Vector2(2,2))
		add_child(rect)

		## Create Label
		#var label = Label.new()
		#label.text = name
		#label.position = rect.position + Vector2(0, COLOR_SIZE.y + 2)
		#label.set("theme_override_colors/font_color", Color(1, 1, 1))
		#label.set("theme_override_font_sizes/font_size", 12)
		#add_child(label)
