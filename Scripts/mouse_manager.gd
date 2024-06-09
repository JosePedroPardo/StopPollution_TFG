class_name MouseManager
extends Node2D

@export var point_out: Resource = preload(PathsHelper.CURSOR_POINT_OUT)
@export var grab: Resource = preload(PathsHelper.CURSOR_GRAB)
@export var click: Resource = preload(PathsHelper.CURSOR_CLICK)
@export var smash: Resource = preload(PathsHelper.CURSOR_SMASH)
@export var death: Resource = preload(PathsHelper.CURSOR_DEATH)
@export var stop: Resource = preload(PathsHelper.CURSOR_STOP)

var cursor_map_position_relative_global: Vector2i
var cursor_map_position_relative_local: Vector2i

@onready var grid_sprite: AnimatedSprite2D = $GridSprite
@onready var tilemap: TileMap = get_tree().get_first_node_in_group("tilemap")

func _ready():
	Input.set_custom_mouse_cursor(point_out)
	grid_sprite.play("default")
	grid_sprite.visible = true

func _process(delta: float) -> void:
	_update_travel_grid()
	_move_cursor_grid()
	_change_sprite_according_cell()
	

func _change_sprite_according_cell():
	if tilemap.is_point_death_cells(cursor_map_position_relative_local):
		Input.set_custom_mouse_cursor(death)
		_activate_or_deactivate_grid_sprite(false) 
	elif tilemap.is_point_wall_cells(cursor_map_position_relative_local):
		Input.set_custom_mouse_cursor(stop)
		_activate_or_deactivate_grid_sprite(false) 
	elif not tilemap.is_point_wall_cells(cursor_map_position_relative_local) and not tilemap.is_point_death_cells(cursor_map_position_relative_local):
		_activate_or_deactivate_grid_sprite(true) 
	if Input.is_action_pressed(InputsHelper.LEFT_CLICK):
		Input.set_custom_mouse_cursor(grab)
	else: Input.set_custom_mouse_cursor(point_out)
	

## Muestra el grid en la posición del ratón, relativa al tilemap
func _update_travel_grid():
	cursor_map_position_relative_local = tilemap.local_to_map(get_local_mouse_position())
	cursor_map_position_relative_global = tilemap.map_to_local(cursor_map_position_relative_local)

func _move_cursor_grid():
	grid_sprite.global_position = cursor_map_position_relative_global

func _activate_or_deactivate_grid_sprite(activate_or_not: bool):
	if not activate_or_not: grid_sprite.stop() 
	else: grid_sprite.play("default")
	grid_sprite.visible = activate_or_not
