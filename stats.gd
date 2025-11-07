extends Label

var savecount:int = 0
var rendercount:int = 0
var history_size:int = 0
var future_size:int = 0

func _ready() -> void:
	get_parent().connect('saved', self._saved)
	get_parent().connect('rendered', self._rendered)
	get_parent().connect('history_modified', self._history_modified)

func _history_modified(_history_size:int, _future_size:int) -> void:
	history_size = _history_size
	future_size = _future_size
	update_label()

func _saved() -> void:
	savecount += 1
	update_label()
func _rendered() -> void:
	rendercount += 1
	update_label()

func update_label() -> void:
	text = "RenderCount: " + str(rendercount) + '\n'
	text += "SaveCount: " + str(savecount) + '\n'
	var futuretext = ''
	if future_size > 0:
		futuretext = ' (' + str(future_size) + ')'
	text += "HistorySize: " + str(history_size) + futuretext + '\n'
	
