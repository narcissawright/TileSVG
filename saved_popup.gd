extends Label

var popup_tween: Tween = null

func _ready():
	get_parent().connect('saved', self.show_popup)
	visible = false

# Call this whenever your file is successfully saved
func show_popup():
	visible = true
	if popup_tween and popup_tween.is_valid():
		popup_tween.kill()  # stops and frees the old tween
	
	popup_tween = create_tween()
	modulate.a = 0.0
	popup_tween.tween_property(self, "modulate:a", 1.0, 0.15)  # fade in
	popup_tween.tween_interval(0.3)
	popup_tween.tween_property(self, "modulate:a", 0.0, 0.15)  # fade out
	popup_tween.tween_callback(self.hide_popup)

func hide_popup():
	visible = false
