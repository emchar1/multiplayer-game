extends CanvasLayer


# PROPERTIES

@onready var lobby: Lobby = get_parent()
@onready var toggle_button = $ToggleButton
@onready var enet_console = $Start/ENet
@onready var websocket_console = $Start/WebSocket
@onready var wss_label = $WssLabel

@export var is_enet: bool = true
@export var use_tls: bool = true

var protocol: String


# FUNCTIONS

func _ready() -> void:
	_update_protocol_ui()

func _update_protocol_ui() -> void:
	protocol = "wss://" if use_tls else "ws://"
	wss_label.text = protocol
	
	enet_console.visible = is_enet
	websocket_console.visible = not is_enet
	wss_label.visible = not is_enet
	toggle_button.text = "Show WebSocket" if is_enet else "Show ENet"


# ENet FUNCTIONS

func _on_enet_join_pressed() -> void:
	var address: String = $Start/ENet/Join/VBox/Options/Address.text
	var port: int = $Start/ENet/Join/VBox/Options/Port.value
	lobby.start_enet_client(address, port)
	hide()

func _on_enet_host_pressed() -> void:
	var port: int = $Start/ENet/Host/VBox/Options/Port.value
	lobby.start_enet_server(port)
	hide()


# WebSocket FUNCTIONS

func _on_websocket_join_pressed() -> void:
	var url: String = protocol + $Start/WebSocket/Join/VBox/Options/Url.text \
	+ ":" + str(int($Start/WebSocket/Join/VBox/Options/Port.value))
	lobby.start_websocket_client(url)
	hide()

func _on_websocket_host_pressed() -> void:
	var port: int = $Start/WebSocket/Host/VBox/Options/Port.value
	lobby.start_websocket_server(port)
	hide()

func _on_toggle_button_pressed() -> void:
	is_enet = not is_enet
	_update_protocol_ui()
