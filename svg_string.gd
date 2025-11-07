extends Label

var normal_color := Color(0.5, 0.5, 0.5)
var hover_color := Color(0.6, 0.6, 0.65)
var tween: Tween

@onready var popup = %CopiedPopup
var popup_active := false
var popup_timer := 0.0

func update_text(new_text:String) -> void:
	text = new_text
	size.y = get_line_count() * get_line_height()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	popup.modulate.a = 0.0  # hidden by default

	self.add_theme_color_override("font_color", normal_color)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func pretty_xml(xml: String, indent_str := "    ") -> String:
	var result := ""
	var indent := 0
	var tag_re := RegEx.new()
	tag_re.compile(r"(<[^>]+>)")
	
	# Split manually into tags + text
	var parts := []
	var last_pos := 0
	for match in tag_re.search_all(xml):
		var start := match.get_start()
		var end := match.get_end()
		if start > last_pos:
			parts.append(xml.substr(last_pos, start - last_pos))
		parts.append(xml.substr(start, end - start))
		last_pos = end
	if last_pos < xml.length():
		parts.append(xml.substr(last_pos, xml.length() - last_pos))

	for part in parts:
		part = part.strip_edges()
		if part == "":
			continue

		if part.begins_with("</"):
			indent = max(indent - 1, 0)
			result += indent_str.repeat(indent) + part + "\n"
		elif part.begins_with("<") and not part.ends_with("/>") and not part.begins_with("<?"):
			result += indent_str.repeat(indent) + part + "\n"
			indent += 1
		else:
			result += indent_str.repeat(indent) + part + "\n"

	return result.strip_edges()

func _process(delta):
	if popup_active:
		# Follow the mouse
		popup.global_position = get_global_mouse_position() + Vector2(8, -8)
		popup_timer -= delta
		if popup_timer <= 0.0:
			hide_copied_popup()

func _on_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.clipboard_set(text)
		show_copied_popup()
		
func show_copied_popup():
	popup.text = "Copied!"
	popup.visible = true
	popup_active = true
	popup_timer = 1.0  # display for ~1 second

	var copytween = create_tween()
	popup.modulate.a = 0.0
	copytween.tween_property(popup, "modulate:a", 1.0, 0.15)  # fade in
	copytween.tween_interval(0.3)
	copytween.tween_property(popup, "modulate:a", 0.0, 0.15)  # fade out

func hide_copied_popup():
	popup.visible = false
	popup_active = false
	
func _on_mouse_entered():
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "theme_override_colors/font_color", hover_color, 0.15)

func _on_mouse_exited():
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "theme_override_colors/font_color", normal_color, 0.15)
