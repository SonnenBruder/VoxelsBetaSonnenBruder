extends Node
class_name ObjectPlacer

signal spawn_plan_ready(plan: Dictionary)
signal spawns_completed(village_count: int, unit_count: int)

@export_category("Dependencies")
## World generator node emitting world_generated signal.
@export var world_generator : Node
## Fallback path used to locate world_generator when export unset.
@export var world_generator_path: NodePath = ^"../WorldGenerator"
## Auto-connect to world_generated signal on _ready.
@export var auto_connect := true

@export_category("Spawn Composition")
## Data-driven spawn rules. Keeps village/unit logic scene-configurable.
@export var spawn_settings: SpawnSettings
## Component responsible for village weighting and village tile selection.
@export var village_spawn_component: VillageSpawnComponent
## Optional fallback path for village spawn component.
@export var village_spawn_component_path: NodePath = ^"VillageSpawnComponent"
## Component responsible for unit count resolution and unit spawning.
@export var unit_spawn_component: UnitSpawnComponent
## Optional fallback path for unit spawn component.
@export var unit_spawn_component_path: NodePath = ^"UnitSpawnComponent"
## Creates default spawn settings/components when missing.
@export var auto_create_spawn_modules := true

@export_category("Scenes")
## Village scene instantiated on selected placeable tiles.
@export var village : PackedScene
## Unit prototype scene spawned as starting units.
@export var proto_unit : PackedScene


func _ready() -> void:
	if auto_connect:
		connect_to_world_generator()


func connect_to_world_generator() -> void:
	resolve_dependencies()
	if world_generator == null:
		push_warning("ObjectPlacer: world_generator missing, placement listener disabled")
		return
	if not world_generator.has_signal("world_generated"):
		push_warning("ObjectPlacer: world_generator has no world_generated signal")
		return
	var callback := Callable(self, "_on_world_generated")
	if not world_generator.is_connected("world_generated", callback):
		world_generator.connect("world_generated", callback)


func resolve_dependencies() -> void:
	if world_generator == null and not world_generator_path.is_empty():
		world_generator = get_node_or_null(world_generator_path)
	resolve_spawn_modules()


func resolve_spawn_modules() -> void:
	if spawn_settings == null and auto_create_spawn_modules:
		spawn_settings = SpawnSettings.new()

	if village_spawn_component == null and not village_spawn_component_path.is_empty():
		village_spawn_component = get_node_or_null(village_spawn_component_path) as VillageSpawnComponent
	if village_spawn_component == null and auto_create_spawn_modules:
		village_spawn_component = VillageSpawnComponent.new()
		village_spawn_component.name = "VillageSpawnComponent"
		add_child(village_spawn_component)

	if unit_spawn_component == null and not unit_spawn_component_path.is_empty():
		unit_spawn_component = get_node_or_null(unit_spawn_component_path) as UnitSpawnComponent
	if unit_spawn_component == null and auto_create_spawn_modules:
		unit_spawn_component = UnitSpawnComponent.new()
		unit_spawn_component.name = "UnitSpawnComponent"
		add_child(unit_spawn_component)


func _on_world_generated(_chunk: Chunk, _voxel_count: int) -> void:
	clear_objects()
	resolve_spawn_modules()
	var generation_settings := WorldMap.world_settings
	if spawn_settings == null:
		push_warning("ObjectPlacer: spawn_settings missing")
		emit_signal("spawns_completed", 0, 0)
		return
	if not spawn_settings.is_spawn_enabled(generation_settings):
		emit_signal("spawns_completed", 0, 0)
		return

	var placeable = get_placeable_voxels()
	if placeable.is_empty():
		emit_signal("spawns_completed", 0, 0)
		return

	if village_spawn_component == null:
		push_warning("ObjectPlacer: village_spawn_component missing")
		emit_signal("spawns_completed", 0, 0)
		return

	var selected_villages = village_spawn_component.plan_villages(placeable, generation_settings, spawn_settings)
	var spawned_village_count = spawn_villages(selected_villages)

	var requested_unit_count = 0
	var spawned_unit_count = 0
	if unit_spawn_component:
		requested_unit_count = unit_spawn_component.resolve_unit_spawn_count(
			generation_settings,
			spawn_settings,
			spawned_village_count
		)
		spawned_unit_count = unit_spawn_component.spawn_units(
			proto_unit,
			self,
			requested_unit_count,
			placeable,
			spawn_settings
		)
	else:
		push_warning("ObjectPlacer: unit_spawn_component missing")

	emit_signal("spawn_plan_ready", {
		"selected_villages": selected_villages,
		"selected_village_count": spawned_village_count,
		"requested_unit_count": requested_unit_count,
		"spawned_unit_count": spawned_unit_count,
		"placeable_count": placeable.size()
	})
	emit_signal("spawns_completed", spawned_village_count, spawned_unit_count)


func get_placeable_voxels() -> Array[Voxel]:
	var placeable_tiles : Array[Voxel] = []
	for key in WorldMap.surface_layer:
		var voxel = WorldMap.surface_layer[key]
		if voxel.buffer or not voxel.placeable:
			continue
		placeable_tiles.append(voxel)
	print(str(placeable_tiles.size()) + " placeable tiles")
	return placeable_tiles

func spawn_villages(villages: Array[Voxel]) -> int:
	if village == null and villages.size() > 0:
		push_warning("ObjectPlacer: village scene missing")
		return 0

	var spawned_count = 0
	for voxel in villages:
		if spawn_on_tile(voxel, village):
			spawned_count += 1
	return spawned_count


# Spawn an object on a tile
func spawn_on_tile(voxel : Voxel, scene : PackedScene) -> bool:
	if not voxel or not scene:
		push_warning("tile not found!")
		return false

	var instance = scene.instantiate()
	add_child(instance)
	call_deferred("position_object", instance, voxel.world_position, 1)
	return true


func position_object(object : Node3D, target_location : Vector3, add_height : float = 0):
	object.position = target_location
	object.position.y += add_height

func clear_objects():
	var children = get_children()
	for c in children:
		if c == village_spawn_component or c == unit_spawn_component:
			continue
		c.free()
