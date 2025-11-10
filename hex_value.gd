extends LineEdit

var path_index:int
var prev_valid_color:String = ''

func _ready() -> void:
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0, 0, 0, 0) # transparent background
	stylebox.set_border_width_all(0)
	add_theme_stylebox_override("focus", stylebox)

func valid_color(fillcolor:String) -> bool:
	if fillcolor == '': return true # it's ok for it to be nothing.
	if not fillcolor.is_valid_html_color(): return false
	if fillcolor.length() == 3 or fillcolor.length() == 6:
		return true
	return false

func _on_text_changed(new_text:String) -> void:
	var old_caret := caret_column

	var filtered:String = ''
	for ch in new_text:
		var up := ch.to_upper()
		if up in "0123456789ABCDEF":
			filtered += up

	if filtered != new_text:
		text = filtered
		caret_column = min(old_caret, filtered.length())
	
	if text.length() == 3 or text.length() == 6 or text.length() == 0:
		prev_valid_color = text
		Events.emit_signal('layer_color_changed', path_index, text)
		if text == '':
			get_parent().get_node('LayerColor').color = Color(Palette.DEFAULT)
		else:
			get_parent().get_node('LayerColor').color = Color(text)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(get_global_mouse_position()):
			release_focus()

func _on_text_submitted(_new_text):
	release_focus()

func _on_focus_exited():
	if text != prev_valid_color:
		text = prev_valid_color
