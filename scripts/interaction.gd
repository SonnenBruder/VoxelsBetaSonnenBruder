extends Node3D

enum mode {SELECT, BUILD}
## Current interaction mode for click behavior.
var interact_mode : mode = mode.SELECT
@export_category("Dependencies")
## World generator node that emits world_generated.
@export var world_generator : Node
## Fallback path for resolving world_generator.
@export var world_generator_path: NodePath = ^"../WorldGenerator"
## Auto-connect listener to world generation signal.
@export var auto_connect_world_generator := true

@export_category("Cursor")
## Scene used for voxel selection cursor.
@export var voxel_cursor_scene : PackedScene
## Scene used for unit selection cursor.
@export var unit_cursor_scene : PackedScene
## Camera used for mouse raycasting into world.
@export var main_camera : Camera3D
## Pathfinder used for movement range and highlights.
@export var p_finder : Pathfinder
## HUD indicator sprite switched by interaction mode.
@export var selection_indicator : TextureRect
## Sprite shown when build mode is active.
const BUILDSPRITE = preload("uid://cgpb4pbfvd0q3")
## Sprite shown when select mode is active.
const SELECTSPRITE = preload("uid://cctpnojcm20kn")

## Currently selected voxel under cursor.
var selected_voxel : Voxel
## Currently selected unit for movement commands.
var selected_unit : Unit
## Cached reachable tiles for selected unit.
var unit_moves : Array[Voxel]
# Cursors
## Instanced voxel cursor node.
var voxel_cursor : Node3D
## Instanced unit cursor node.
var unit_cursor : Node3D
## True after cursors and state finished first-time init.
var initialized = false


func _ready() -> void:
	if auto_connect_world_generator:
		connect_to_world_generator()


func connect_to_world_generator() -> void:
	resolve_dependencies()
	if world_generator == null:
		push_warning("Interaction: world_generator missing, init listener disabled")
		return
	if not world_generator.has_signal("world_generated"):
		push_warning("Interaction: world_generator has no world_generated signal")
		return
	var callback := Callable(self, "_on_world_generated")
	if not world_generator.is_connected("world_generated", callback):
		world_generator.connect("world_generated", callback)


func resolve_dependencies() -> void:
	if world_generator == null and not world_generator_path.is_empty():
		world_generator = get_node_or_null(world_generator_path)


func _on_world_generated(_chunk: Chunk, _voxel_count: int) -> void:
	init()

func init():
	if not voxel_cursor or voxel_cursor == null:
		voxel_cursor = voxel_cursor_scene.instantiate()
		add_child(voxel_cursor)
	if not unit_cursor:
		unit_cursor = unit_cursor_scene.instantiate()
		add_child(unit_cursor)
	if WorldMap.world_settings == null:
		push_warning("Interaction: world settings missing, cannot init cursors")
		return
	
	var scalar = WorldMap.world_settings.voxel_size
	voxel_cursor.scale = Vector3(scalar, 1.0, scalar)
	deselect()
	if selection_indicator:
		selection_indicator.texture = SELECTSPRITE
	initialized = true


func _process(_delta: float) -> void:
	if not initialized:
		return

	#mode select
	if Input.is_action_just_pressed("Build"):
		interact_mode = mode.BUILD
		if selection_indicator:
			selection_indicator.texture = BUILDSPRITE
	elif Input.is_action_just_pressed("Select"):
		interact_mode = mode.SELECT
		if selection_indicator:
			selection_indicator.texture = SELECTSPRITE
		
	# Setup raycast
	if Input.is_action_just_pressed("Click") or Input.is_action_just_pressed("RightClick"):
		var mouse_pos = get_viewport().get_mouse_position()
		var origin = main_camera.project_ray_origin(mouse_pos)
		var dir = main_camera.project_ray_normal(mouse_pos)
		var end = origin + dir * 1000
		var hit_data = raycast_at_mouse(origin, end)
		if not hit_data:
			print("hit data is empty")
			return

		if Input.is_action_just_pressed("Click"):
			if interact_mode == mode.SELECT:
				attempt_select(hit_data)
			elif interact_mode == mode.BUILD:
				attempt_build(hit_data.object)
		elif Input.is_action_just_pressed("RightClick"):
			attempt_move_unit(hit_data)


func raycast_at_mouse(origin, end) -> HitData:
		var query = PhysicsRayQueryParameters3D.create(origin, end)
		var collision = get_world_3d().direct_space_state.intersect_ray(query)
		if collision and collision.has("collider"):
			var hit = collision.collider
			var data = HitData.new()
			data.object = hit
			data.point = collision.position
			data.normal = collision.normal
			return data
		else:
			deselect()
			return null


func attempt_build(hit_object):
	if hit_object.is_in_group("voxels"):
		build_voxel(hit_object)


func build_voxel(hit_object):
	print(hit_object)


func deselect():
	hide_cursor(voxel_cursor)
	hide_cursor(unit_cursor)
	unit_moves.clear()
	selected_unit = null
	if p_finder:
		p_finder.clear_highlight()


func attempt_select(hit: HitData):
	deselect()
	if hit.object.is_in_group("voxels") or hit.object.get_parent().is_in_group("voxels"):
		highlight_voxel(hit)
		return
	if hit.object.is_in_group("units"):
		select_unit(hit.object)
	elif hit.object.get_parent().is_in_group("units"):
		select_unit(hit.object.get_parent())


func attempt_move_unit(hitdata : HitData):
	if not selected_unit:
		print("Select a unit first")
		return
	
	var hit_chunk : Chunk = hitdata.object.get_parent()
	var hit_voxel : Voxel = hit_chunk.voxel_at_point(hitdata)
	if hit_voxel == null:
		print("Hit voxel is null!")
		return
	
	if unit_moves.has(hit_voxel):
		selected_unit.place_unit(hit_voxel)
	else:
		print("Invalid Voxel")
	deselect()


func select_unit(unit : Unit):
	selected_voxel = null
	selected_unit = unit
	hide_cursor(voxel_cursor)
	if unit is Unit:
		highlight_unit(unit)
		if p_finder:
			unit_moves = p_finder.find_reachable_voxels(unit.occupied_voxel, unit)
			p_finder.highlight_voxel(unit_moves)


# We have clicked somewhere on a chunk of voxels
func highlight_voxel(hit: HitData): #hit is hit_data
	selected_unit = null
	hide_cursor(unit_cursor)
	var hit_chunk : Chunk = hit.object.get_parent()
	var hit_voxel : Voxel = hit_chunk.voxel_at_point(hit)
	if hit_voxel == null:
		print("Hit voxel is null!")
		return
	selected_voxel = hit_voxel
	move_cursor(voxel_cursor, hit_voxel.world_position, 1)
	voxel_cursor.visible = true
	animate_cursor(voxel_cursor)


func highlight_unit(unit):
	move_cursor(unit_cursor, unit.position)
	unit_cursor.visible = true


## move cursor with optional height difference
func move_cursor(cursor : Node3D, pos : Vector3, height : float = 0):
	cursor.position = pos
	if height != 0:
		voxel_cursor.position.y += height


func animate_cursor(cursor : Node3D):
	var tween = get_tree().create_tween()
	var initial_scale = cursor.scale
	var target_scale = initial_scale * 1.15
	tween.set_trans(Tween.TRANS_SPRING)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cursor, "scale", target_scale, 0.175)
	tween.tween_property(cursor, "scale", initial_scale, 0.2)


func hide_cursor(cursor : Node3D):
	if cursor:
		move_cursor(cursor, Vector3.ZERO, -10)
		cursor.visible = false
