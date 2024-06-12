class_name BehaviourPuf
extends CharacterBody2D

signal cell_ocuppied(cood_cell: Vector2i)
signal cell_unocuppied(cood_cell: Vector2i)
signal puf_dead(puf: Vector2i)
signal puf_smashed(puf: Node2D)
signal pufs_rich_at_my_side(puf_rich_at_my_side: Array[Node2D])
signal pufs_poor_at_my_side(puf_poor_at_my_side: Array[Node2D])
signal puf_dragging
signal puf_undragging

@export var minimum_poor_pufs_to_join: int = 3 ## Unidades mínimas de puf pobres para unirse
@export var minimum_rich_pufs_to_join: int = 2 ## Unidades mínimas de puf ricos para unirse
@export var wait_time_move: float = 0.4 ## Tiempo de espera entre un movimiento y el siguiente
@export var wait_time_finish_celebration: float = 2 ## Tiempo de espera entre un movimiento y el siguiente
@export var move_grid_speed: float = 1 ## Velocidad a la que se desplaza el puf por el grid
@export var move_drag_speed: float = 80 ## Velocidad a la que se desplaza el puf al ser arrastrado
@export var degress_rotation: float = 90 ## Grados de rotación del sprite al arrastrarlo
@export var in_or_out_zoom: float = 0.5 ## Valor por el que se incrementa el texto a través del zoom de la cámara
@export var can_assemble: bool = false ## ¿Los Pufs se pueden unir?
@export var is_in_or_out_zoom: bool ## Booleana que controla si se incrementa o decrementa el zoom
@export var knockback_strength: float = 30 ## Fuerza del knockback

var myself: Puf: 
	get: return myself
	set(_myself):
		myself = _myself
var is_baby: bool = false:
	get: return is_baby
	set(_is_baby):
		is_baby = _is_baby

var social_class: int = DefinitionsHelper.INDEX_RANDOM_SOCIAL_CLASS:
	set(_social_class):
		social_class = _social_class

var way_diying: String = DefinitionsHelper.WAY_DYING_NEEDS
var is_dragging: bool = false
var is_can_grid_move: bool = false
var is_your_moving: bool = false
var is_look_to_target_position: bool = false
var is_mouse_top: bool = false
var puf_rich_at_my_side: Array[Node2D]
var puf_poor_at_my_side: Array[Node2D]
var ocuppied_cells: Array[Vector2i]
var death_cells: Array[Vector2i]
var current_paths: Array[Vector2i]
var global_cursor_map_position_relative_local_tilemap: Vector2i
var local_cursor_map_position_relative_local_tilemap: Vector2i
var global_cursor_map_position_relative_global_tilemap: Vector2i
var current_position_relative_to_local_tilemap: Vector2i
var current_clic_position: Vector2
var target_grid_position: Vector2

@onready var wait_timer: Timer = $WaitTime
@onready var interact_label: Label = $InteractLabel
@onready var name_label: Label = $NameLabel
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var manager_puf: Node2D = get_tree().get_first_node_in_group("manager_pufs")
@onready var smash_sprite: Sprite2D = $SmashSprite
@onready var sprite_puf: Sprite2D = $SpritePuf
@onready var smash_animation_player: AnimationPlayer = smash_sprite.get_child(0)
@onready var assemble_shape: CollisionShape2D = $InteractionAreas/AssembleArea/AssembleShape
@onready var repulsion_shape: CollisionShape2D = $InteractionAreas/RepulsionArea/RepulsionShape
@onready var shape_puf: CollisionShape2D = $ShapePuf
@onready var tilemap: TileMap = get_tree().get_first_node_in_group(DefinitionsHelper.GROUP_TILEMAP)
@onready var astar_grid: AStarGrid2D = tilemap.astar_grid
@onready var camera: Camera2D = get_tree().get_first_node_in_group(DefinitionsHelper.GROUP_CAMERA)

func _init():
	myself = Puf.new(social_class, is_baby)

func _ready():
	social_class = myself.social_class
	_change_sprite_according_social_class()
	var initial_grid_cell: Vector2i = tilemap.local_to_map(self.position)
	
	shape_puf.shape = RectangleShape2D.new()
	shape_puf.shape.size = Vector2(16, 16)
	if is_myself_rich():
		assemble_shape.shape = RectangleShape2D.new()
		assemble_shape.shape.size = Vector2(32, 32)
		repulsion_shape.shape = RectangleShape2D.new()
		repulsion_shape.shape.size = Vector2(24, 24)
	
	emit_signal("cell_ocuppied", initial_grid_cell)
	manager_puf.connect("ocuppied_cells_array", Callable(self, "_on_ocuppied_cells"))
	manager_puf.connect("celebration_all_pufs", Callable(self, "_on_celebration_all_pufs"))
	tilemap.connect("death_coordinates", Callable(self, "_on_death_cells"))
	camera.connect("change_zoom", Callable(self, "_on_change_zoom"))
	
	animation_player.play(DefinitionsHelper.ANIMATION_IDLE_PUF)

func _change_sprite_according_social_class():
	var path_texture: String
	if social_class == DefinitionsHelper.INDEX_RICH_SOCIAL_CLASS:
		path_texture = RandomHelper.get_random_string_in_array(DefinitionsHelper.texture_rich_pufs)
	elif social_class == DefinitionsHelper.INDEX_POOR_SOCIAL_CLASS:
		path_texture = RandomHelper.get_random_string_in_array(DefinitionsHelper.texture_poor_pufs)
	sprite_puf.texture = load(path_texture)

func _process(delta):
	_update_all_position_grid()
	
	if Input.is_action_pressed(InputsHelper.LEFT_CLICK):
		current_clic_position = get_global_mouse_position()
	
	if Input.is_action_just_released(InputsHelper.LEFT_CLICK):
		if is_dragging:
			is_dragging = false
			_reproduce_animation(DefinitionsHelper.ANIMATION_IDLE_PUF, true)
	
	if is_mouse_top:
		if is_myself_rich():
			if Input.is_action_just_pressed(InputsHelper.SMASH_PUF):
				_smash_rich()
				_die(way_diying)
		else: 
			if Input.is_action_just_pressed(InputsHelper.ASSEMBLE_PUF) and can_assemble:
				_change_interact_ui_label(InteractHelper.INTERACTION_ASSEMBLE_TEXT)

func _physics_process(delta):
	if is_dragging:
		_move_to_clic_position(current_clic_position)
	else: stop_immediately()
	
	if not is_myself_rich():
		if not puf_poor_at_my_side.is_empty():
			if (puf_poor_at_my_side.size() % minimum_poor_pufs_to_join) == 0:
				_assemble_pufs()

func _on_mouse_area_input_event(viewport, event, shape_idx):  #Cuando un evento interactua con el area
	if Input.is_action_pressed(InputsHelper.LEFT_CLICK):
		is_dragging = true

func _assemble_pufs():
	var interact_text: String = ""
	match puf_poor_at_my_side.size():
		minimum_poor_pufs_to_join: interact_text = InteractHelper.INTERACTION_ASSEMBLE_TEXT
		_: interact_text = InteractHelper.INTERACTION_ASSEMBLE_TEXT
	_change_interact_ui_label(interact_text)

func _look_to_mouse(clic_position: Vector2):
	#var direction = (clic_position - self.global_position).normalized()
	sprite_puf.flip_h = clic_position.x < 0

func _move_to_clic_position(clic_position: Vector2):
	_look_to_mouse(get_local_mouse_position())
	var animation_to_play = ""
	var new_position = tilemap.map_to_local(tilemap.local_to_map(clic_position))
	var direction = (new_position - self.position).normalized()
	if not _is_not_ocuppied_position(new_position):
		if not is_myself_rich():
			if _is_wall_position(new_position) or _is_death_position(new_position):
				return
	
	if is_myself_rich(): animation_to_play = DefinitionsHelper.ANIMATION_RUN_PUF
	else: animation_to_play = DefinitionsHelper.ANIMATION_JUMP_PUF
	_reproduce_animation(animation_to_play, false)
	self.velocity = (direction * move_drag_speed)
	move_and_slide()

func _calculate_current_paths_through_clic_position(clic_position: Vector2):
	var myself_local_position = tilemap.local_to_map(self.position)
	var current_clic_local_position = tilemap.local_to_map(clic_position)
	if tilemap.is_point_walkable_map_local_position(current_clic_local_position):
		if _is_not_ocuppied_position(current_clic_local_position):
			#if not _is_death_position(current_clic_local_position):
			current_paths = tilemap.get_current_path(myself_local_position, current_clic_local_position).slice(1)
			is_can_grid_move = false if current_paths.is_empty() else true

func _move_to_grid_position_through_current_paths():
	if current_paths.is_empty():
		is_your_moving = false
		is_look_to_target_position = false
		return
	_reproduce_animation(DefinitionsHelper.ANIMATION_RUN_PUF, false)
	var target_position = tilemap.map_to_local(current_paths.front())
	is_look_to_target_position = true
	_emit_signal_with_ocuppied_grid_position(tilemap.local_to_map(self.global_position), true)
	self.global_position = self.global_position.move_toward(target_position, move_grid_speed)
	await get_tree().create_timer(wait_time_move).timeout
	if self.global_position == target_position:
		_reproduce_animation(DefinitionsHelper.ANIMATION_IDLE_PUF, false)
		is_your_moving = true
		current_paths.pop_front()
		_emit_signal_with_ocuppied_grid_position(target_position, true)

func _is_not_ocuppied_position(current_position: Vector2i) -> bool:
	current_position = tilemap.local_to_map(current_position)
	return not ocuppied_cells.has(current_position)

func _is_wall_position(current_position: Vector2i) -> bool:
	current_position = tilemap.local_to_map(current_position)
	return tilemap.is_point_wall_cells(current_position)

func _is_death_position(current_position: Vector2i) -> bool:
	current_position = tilemap.local_to_map(current_position)
	return not tilemap.is_point_death_cells(current_position)

func _reproduce_animation(animation: String, play_immediately: bool):
	if play_immediately: 
		animation_player.stop()
		animation_player.play(animation)
	elif not animation_player.get_queue().has(animation):
		animation_player.play(animation)

func _add_animation_to_queue(animation: String):
	if animation_player.has_animation(animation):
		animation_player.queue(animation)

func _die(die: String):
	var animation_to_reproduce: String = ""
	match die:
		DefinitionsHelper.WAY_DYING_SMASH: animation_to_reproduce = DefinitionsHelper.ANIMATION_DEATH_BY_SMASH_PUF
		DefinitionsHelper.WAY_DYING_BY_FALL_PUF: animation_to_reproduce = DefinitionsHelper.ANIMATION_DEATH_BY_FALL_PUF
		DefinitionsHelper.WAY_DYING_NEEDS: animation_to_reproduce = DefinitionsHelper.ANIMATION_DIE_PUF
	_reproduce_animation(animation_to_reproduce, true)
	stop_immediately()
	_destroy_after_time(2)

func _smash_rich():
	emit_signal("puf_smashed", self)
	smash_sprite.visible = true
	smash_animation_player.play(DefinitionsHelper.ANIMATION_DEATH_BY_SMASH_CURSOR)
	way_diying = DefinitionsHelper.WAY_DYING_SMASH

func _update_all_position_grid():
	local_cursor_map_position_relative_local_tilemap = tilemap.local_to_map(get_local_mouse_position())
	global_cursor_map_position_relative_local_tilemap = tilemap.local_to_map(get_global_mouse_position())
	global_cursor_map_position_relative_global_tilemap = tilemap.map_to_local(local_cursor_map_position_relative_local_tilemap)
	current_position_relative_to_local_tilemap = tilemap.local_to_map(self.position)

func _destroy_after_time(time: float):
	await get_tree().create_timer(time).timeout
	emit_signal("cell_unocuppied", tilemap.local_to_map(self.position))
	self.queue_free()
	
func _invisible_after(node: Node2D, time: float):
	await get_tree().create_timer(time).timeout
	node.visible = false
	
func _change_interact_ui_label(text: String):
	if text: 
		interact_label.visible = true
		interact_label.text = text
	else: 
		interact_label.visible = false
		interact_label.text = ""

func stop_immediately():
	is_dragging = false
	self.velocity = Vector2.ZERO
	_reproduce_animation(DefinitionsHelper.ANIMATION_DROP_PUF, false)

''' Métodos de señales '''
func _emit_signal_with_ocuppied_grid_position(current_grid_cell: Vector2, free_or_not: bool):
	var signal_name = "cell_unocuppied" if free_or_not else "cell_ocuppied"  
	emit_signal(signal_name, Vector2i(current_grid_cell))

func _emit_signal_to_rich_at_my_side(body, is_add: bool):
	if body != self:
		if is_add:
			if not puf_rich_at_my_side.has(body):
				puf_rich_at_my_side.append(body)
				emit_signal("pufs_rich_at_my_side", puf_rich_at_my_side)
		else: 
			if puf_rich_at_my_side.has(body):
				puf_rich_at_my_side.erase(body)
	emit_signal("pufs_rich_at_my_side", puf_rich_at_my_side)

func _emit_signal_to_poor_at_my_side(body, is_add: bool):
	if body != self:
		if is_add:
			if puf_poor_at_my_side.has(body):
				puf_poor_at_my_side.append(body)
				print(puf_poor_at_my_side)
		else: 
			if puf_poor_at_my_side.has(body):
				puf_poor_at_my_side.erase(body)
	emit_signal("pufs_poor_at_my_side", puf_poor_at_my_side)

func _kockback(body: CharacterBody2D):
	var knockback_direction = (body.velocity - self.velocity).normalized() * -knockback_strength
	body.velocity = knockback_direction
	#await get_tree().create_timer(0.05).timeout
	body.global_position += body.velocity
	body.stop_immediately()

func _on_ocuppied_cells(_ocuppied_cells):
	ocuppied_cells = _ocuppied_cells

func _on_death_cells(_death_cells):
	death_cells = _death_cells

func _on_mouse_area_mouse_entered():
	is_mouse_top = true
	name_label.text = get_name_of_puf()
	self.position.y += -2
	if is_myself_rich():
		_reproduce_animation(DefinitionsHelper.ANIMATION_TERROR_PUF, false)
		_change_interact_ui_label(InteractHelper.INTERACTION_SMASH_TEXT)
	else: 
		_reproduce_animation(DefinitionsHelper.ANIMATION_PICK_ME, false)

func _on_mouse_area_mouse_exited():
	is_mouse_top = false
	name_label.text = ""
	self.position.y += +2
	if is_myself_rich():
		_change_interact_ui_label("")
	_reproduce_animation(DefinitionsHelper.ANIMATION_DROP_PUF, true)
	_add_animation_to_queue(DefinitionsHelper.ANIMATION_IDLE_PUF)

func _on_celebration_all_pufs(type_celebration: String):
	var animation_to_play: String = ""
	match type_celebration:
		DefinitionsHelper.TYPE_CELEBRATION_SMASH_PUF:
			if not is_myself_rich(): animation_to_play = DefinitionsHelper.ANIMATION_CELEBRATION_PUF
			else: animation_to_play = DefinitionsHelper.ANIMATION_TERROR_PUF
			await get_tree().create_timer(1).timeout
			_reproduce_animation(animation_to_play, true)
	await get_tree().create_timer(wait_time_finish_celebration).timeout
	_reproduce_animation(DefinitionsHelper.ANIMATION_IDLE_PUF, true)

func _on_assemble_area_body_entered(body):
	if is_myself_rich():
		_emit_signal_to_rich_at_my_side(body, true)
	else: _emit_signal_to_poor_at_my_side(body, true)

func _on_assemble_area_body_exited(body):
	if is_myself_rich():
		_emit_signal_to_rich_at_my_side(body, false)
	else: _emit_signal_to_poor_at_my_side(body, false)

func _on_repulsion_area_body_entered(body): ##TODO: Poner un globo de alegria si se acerca un rico, de asco si es un pobre
	if is_myself_rich():
		if not body.is_myself_rich():
			_kockback(body)

func _on_repulsion_area_body_exited(body):
	if is_myself_rich():
		if not body.is_myself_rich():
			_kockback(body)


##TODO: Hacer que los label se ajusten al tamaño del zoom de la cámara
func _on_change_zoom(in_out: bool): 
	pass

''' Getters del Puf asociado a este CharacterBody2D '''
func get_social_class():
	match(myself.social_class):
		0: return DefinitionsHelper.POOR_SOCIAL_CLASS
		1: return DefinitionsHelper.RICH_SOCIAL_CLASS
		_: return "null"

func is_myself_rich():
	return get_social_class() == DefinitionsHelper.RICH_SOCIAL_CLASS

func get_background() -> String:
	return _get_variable_by_name("background")

func get_name_of_puf() -> String:
	return _get_variable_by_name("name_of_puf")

func get_surname() -> String:
	return _get_variable_by_name("surname")

func get_noble_title() -> String:
	return _get_variable_by_name("noble_title")

func get_profession() -> String:
	return _get_variable_by_name("profession")

func get_place() -> String:
	return _get_variable_by_name("place")

func get_hunger() -> float:
	return _get_variable_by_name("hunger")

func get_thirst() -> float:
	return _get_variable_by_name("thirst")

func get_height() -> float:
	return _get_variable_by_name("height")

func get_birth_year() -> int:
	return _get_variable_by_name("birth_year")

func get_years() -> int:
	return _get_variable_by_name("years")

func get_is_interactive() -> bool:
	return _get_variable_by_name("is_interactive")

func get_constitution() -> Puf.Constitution:
	return _get_variable_by_name("constitution")

func get_mood() -> Puf.Mood:
	return _get_variable_by_name("mood")

func get_health_status() -> Puf.Health_status:
	return _get_variable_by_name("health_status")

func get_ascendant() -> Puf:
	return _get_variable_by_name("ascendant")

func get_descendant() -> Array[Puf]:
	return _get_variable_by_name("descendant")

func get_full_name() -> String:
	return _get_variable_by_name("get_full_name")

func get_percentage_of_thrist() -> String:
	return _get_variable_by_name("get_percentage_of_thrist")

func get_percentage_of_hunger() -> String:
	return _get_variable_by_name("get_percentage_of_hunger")

func get_json_serialize() -> String:
	return _get_variable_by_name("get_json_serialize")

func _get_variable_by_name(name: String):
	match name:
		"background":
			return myself.background
		"name_of_puf":
			return myself.name_of_puf
		"surname":
			return myself.surname
		"noble_title":
			return myself.noble_title
		"profession":
			return myself.profession
		"place":
			return myself.place
		"hunger":
			return myself.hunger
		"thirst":
			return myself.thirst
		"height":
			return myself.height
		"birth_year":
			return myself.birth_year
		"years":
			return myself.years
		"is_interactive":
			return myself.is_interactive
		"constitution":
			return myself.constitution
		"social_class":
			return myself.social_class
		"mood":
			return myself.mood
		"mood":
			return myself.health_status
		"ascendant":
			return myself.ascendant
		"descendant":
			return myself.descendant
		"get_full_name":
			return myself.get_full_name()
		"get_percentage_of_thrist":
			return myself.get_percentage_of_thrist()
		"get_percentage_of_hunger":
			return myself.get_percentage_of_hunger()
		"get_json_serialize":
			return myself.jsonSerialize()		
		_:
			return null
	
