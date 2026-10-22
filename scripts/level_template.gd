@tool
extends Node2D
class_name Level


# PROPERTIES

signal goal_reached(player: Player)

const SURFACE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/images/BG/Double/background_color_trees.png"),
	preload("res://assets/images/BG/Double/background_color_hills.png"),
	preload("res://assets/images/BG/Double/background_color_desert.png"),
	preload("res://assets/images/BG/Double/background_color_mushrooms.png")
]

const GROUND_COLORS: PackedColorArray = [
	Color("#2ECC71"),
	Color("#2ECC71"),
	Color("#F3C7A5"),
	Color("#DE7E4F")
]

const SKY_COLOR: Color = Color("#C3E3FF")

enum Background {
	TREES = 0,
	HILLS = 1,
	DESERT = 2,
	MUSHROOMS = 3
}

@onready var coins = $Coins
@onready var enemies = $Enemies

@export var display_name: String = "Untitled Level"
@export var world_number: int = 0
@export var level_number: int = 0
@export var background: Background = Background.TREES:
	set(value):
		background = value
		$Background/Surface.texture = SURFACE_TEXTURES[value]
		$Background/Ground.color = GROUND_COLORS[value]
		$Background/Sky.color = SKY_COLOR


# PUBLIC HELPER FUNCTIONS

func get_spawn_position() -> Vector2:
	return $Spawn.global_position


# EVENT FUNCTIONS

func _on_goal_body_entered(body: Node2D) -> void:
	if body is Player:
		goal_reached.emit(body)
