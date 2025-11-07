extends Node2D

var current:String

signal tool_changed(tool:String)

@onready var tools := {
	"maker": $Maker,
	"selector": $Selector,
	"painter": $Painter
}

func _ready() -> void:
	for tool_name in tools.keys():
		var button:TextureButton = tools[tool_name]
		# preload all states
		button.texture_normal  = _make_icon(tool_name, "passive")
		button.texture_hover   = _make_icon(tool_name, "hover")
		button.texture_pressed = _make_icon(tool_name, "clicked")
		# connect once
		button.pressed.connect(_on_tool_pressed.bind(tool_name))
	
	set_tool("selector") # start active tool

func _make_icon(icon: String, mode: String) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(get_icon(icon, mode))
	return ImageTexture.create_from_image(img)
	
func _on_tool_pressed(tool_name: String) -> void:
	set_tool(tool_name)

func set_tool(tool_name: String) -> void:
	if current == tool_name:
		return
	
	current = tool_name
	for n in tools.keys():
		var button:TextureButton = tools[n]
		var state := "active" if n == tool_name else "passive"
		button.texture_normal = _make_icon(n, state)

	# emit signal to main script if needed
	if has_signal("tool_changed"):
		emit_signal("tool_changed", tool_name)

	

func get_icon(icon:String, mode:String) -> String:
	
	var bordercolor:String = '#808080'
	var bgcolor:String = '#444444'
	match mode:
		"passive":
			pass
		"active":
			bgcolor = '#555555'
			bordercolor = '#cccc80'
		"hover":
			bgcolor = '#555555'
			bordercolor = '#bbbbbb'
		"clicked":
			bgcolor = '#555555'
			bordercolor = '#dddddd'
	
	var svgString:String = '<svg width="72" height="72" xmlns="http://www.w3.org/2000/svg">'
	
	# Background
	svgString += '<rect width="72" height="72" fill="'+ bgcolor +'" />'
	
	# Icon
	match icon:
		"maker":
			svgString += '<line x1="36" y1="0" x2="36"  y2="72" stroke="#808080" stroke-width="2" />'
			svgString += '<line x1="0"  y1="36" x2="71" y2="36" stroke="#808080" stroke-width="2" />'
			svgString += '<line x1="0"  y1="72" x2="36" y2="36" stroke="#000000" stroke-width="4" />'
			svgString += '<circle cx="36" cy="36" r="10" />'
		"selector":
			#svgString += '<line x1="0"  y1="49" x2="72"  y2="9"  stroke="#000000" stroke-width="4" />'
			svgString += '<path fill="#fff" stroke="#000" stroke-width="2" d="M32,32 l0,30 l7.5,-7.5 l10.5,0 l-18,-22.5 Z"/>'
	
	# Border
	svgString += '<line x1="1"  y1="1"  x2="71" y2="1"  stroke="'+ bordercolor +'" stroke-width="2" />'
	svgString += '<line x1="71" y1="1"  x2="71" y2="71" stroke="'+ bordercolor +'" stroke-width="2" />'
	svgString += '<line x1="71" y1="71" x2="1"  y2="71" stroke="'+ bordercolor +'" stroke-width="2" />'
	svgString += '<line x1="1"  y1="71" x2="1"  y2="1"  stroke="'+ bordercolor +'" stroke-width="2" />'
	
	svgString += '</svg>'
	
	return svgString
