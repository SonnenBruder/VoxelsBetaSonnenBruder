extends Node
class_name ObjectPlacer

signal spawn_plan_ready(plan: Dictionary)
signal spawns_completed(village_count: int, unit_count: int)

enum VillageSpawnMode {SPACING_FILL, TARGET_COUNT}
enum UnitSpawnMode {RADIUS_BASED, FIXED_COUNT, PER_VILLAGE}

@export_category("Dependencies")
## World generator node emitting world_result_ready/world_generated signals.
@export var world_generator : Node
## Fallback path used to locate world_generator when export unset.
@export var world_generator_path: NodePath = ^"../WorldGenerator"
## Auto-connect to generator signal on _ready.
@export var auto_connect := true
## Prefer VoxelWorldResult input when the generator supports it.
@export var prefer_world_result_signal := true

@export_category("Village Spawn Rules")
## Village placement strategy: fill by spacing or stop at target count.
@export var village_spawn_mode: VillageSpawnMode = VillageSpawnMode.SPACING_FILL
## If true, target villages scales with available placeable tiles.
@export var dynamic_village_target := true
## Fallback fixed target villages when dynamic target is disabled.
@export_range(1, 256, 1) var fixed_village_target := 8
## Dynamic villages ratio against placeable tile count.
@export_range(0.001, 0.2, 0.001) var villages_per_placeable_tile := 0.02
## Hard cap for dynamic village target.
@export_range(1, 512, 1) var max_dynamic_village_target := 64
## Enables weighted ranking for village candidate ordering.
@export var use_weighted_village_selection := true

@export_category("Village Weights (Placeholder)")
## Minimum weight required for village candidate eligibility.
@export_range(0.0, 1.0, 0.01) var min_village_weight := 0.0
## Contribution of center distance in placeholder weight function.
@export_range(0.0, 5.0, 0.05) var center_weight_factor := 0.45
## Contribution of voxel noise in placeholder weight function.
@export_range(0.0, 5.0, 0.05) var noise_weight_factor := 0.35
## Contribution of solidity proxy in placeholder weight function.
@export_range(0.0, 5.0, 0.05) var solidity_weight_factor := 0.20
## Weight channel to read from VoxelSurfaceTile.weights before falling back to placeholder scoring.
@export var result_weight_id: StringName = &"settlement"

@export_category("Unit Spawn Rules")
## Unit spawn strategy resolved after villages are selected.
@export var unit_spawn_mode: UnitSpawnMode = UnitSpawnMode.RADIUS_BASED
## Unit count used by FIXED_COUNT mode.
@export_range(1, 512, 1) var fixed_unit_count := 6
## Units-per-village ratio for PER_VILLAGE mode.
@export_range(0.0, 5.0, 0.1) var units_per_village := 0.8
## Max cap for PER_VILLAGE dynamic unit count.
@export_range(1, 512, 1) var max_dynamic_unit_count := 96

@export_category("Scenes")
## Village scene instantiated on selected placeable tiles.
@export var village : PackedScene
## Unit prototype scene spawned as starting units.
@export var proto_unit : PackedScene

var current_result: VoxelWorldResult


func _ready() -> void:
	if auto_connect:
		connect_to_world_generator()


func connect_to_world_generator() -> void:
	resolve_dependencies()
	if world_generator == null:
		push_warning("ObjectPlacer: world_generator missing, placement listener disabled")
		return

	if prefer_world_result_signal and world_generator.has_signal("world_result_ready"):
		var result_callback := Callable(self, "_on_world_result_ready")
		if not world_generator.is_connected("world_result_ready", result_callback):
			world_generator.connect("world_result_ready", result_callback)
		return

	if world_generator.has_signal("world_generated"):
		var callback := Callable(self, "_on_world_generated")
		if not world_generator.is_connected("world_generated", callback):
			world_generator.connect("world_generated", callback)
		return

	push_warning("ObjectPlacer: world_generator has no supported generation signal")


func resolve_dependencies() -> void:
	if world_generator == null and not world_generator_path.is_empty():
		world_generator = get_node_or_null(world_generator_path)


func _on_world_generated(_chunk: Chunk, _voxel_count: int) -> void:
	run_placement(null)


func _on_world_result_ready(result: VoxelWorldResult) -> void:
	run_placement(result)


func run_placement(result: VoxelWorldResult) -> void:
	current_result = result
	clear_objects()
	var settings := result.settings if result != null else WorldMap.world_settings
	if settings == null or not settings.spawn_villages_and_units:
		emit_signal("spawns_completed", 0, 0)
		return

	var placeable = get_placeable_voxels(result)
	if placeable.is_empty():
		emit_signal("spawns_completed", 0, 0)
		return

	if not apply_result_weights(placeable, result):
		distribute_village_weights_placeholder(placeable, settings)
	var selected_villages = select_village_tiles(placeable, settings.spacing)
	spawn_villages(selected_villages)

	var unit_count = resolve_unit_spawn_count(settings, selected_villages.size())
	create_starting_units(unit_count, placeable)

	emit_signal("spawn_plan_ready", {
		"selected_villages": selected_villages,
		"requested_unit_count": unit_count,
		"placeable_count": placeable.size()
	})
	emit_signal("spawns_completed", selected_villages.size(), unit_count)


func get_placeable_voxels(result: VoxelWorldResult = null) -> Array[Voxel]:
	var placeable_tiles : Array[Voxel] = []
	if result != null and not result.surface_tiles_by_coord.is_empty():
		for tile: VoxelSurfaceTile in result.surface_tiles_by_coord.values():
			if not tile.placeable or not tile.passable or tile.is_empty or tile.source_voxel == null:
				continue
			if not tile.source_voxel.placeable:
				continue
			placeable_tiles.append(tile.source_voxel)
		print(str(placeable_tiles.size()) + " placeable tiles")
		return placeable_tiles

	for key in WorldMap.surface_layer:
		var voxel = WorldMap.surface_layer[key]
		if voxel.buffer or not voxel.placeable:
			continue
		placeable_tiles.append(voxel)
	print(str(placeable_tiles.size()) + " placeable tiles")
	return placeable_tiles


func apply_result_weights(tiles: Array[Voxel], result: VoxelWorldResult) -> bool:
	if result == null or result.surface_tiles_by_coord.is_empty():
		return false

	var applied := false
	for voxel in tiles:
		var tile = result.surface_tiles_by_coord.get(voxel.grid_position_xz) as VoxelSurfaceTile
		if tile == null or not tile.weights.has(result_weight_id):
			continue
		voxel.village_weight = float(tile.weights[result_weight_id])
		applied = true
	return applied


func distribute_village_weights_placeholder(tiles: Array[Voxel], settings: GenerationSettings) -> void:
	for voxel in tiles:
		voxel.village_weight = calculate_village_weight_placeholder(voxel, settings)


func calculate_village_weight_placeholder(voxel: Voxel, settings: GenerationSettings) -> float:
	# Placeholder: swap this function later with biome/resource/pathing scoring.
	var q = voxel.grid_position_xz.x
	var r = voxel.grid_position_xz.y
	var ring = max(abs(q), abs(r), abs(q + r))
	var radius = maxi(settings.radius, 1)
	var center_factor = 1.0 - clampf(float(ring) / float(radius), 0.0, 1.0)
	var noise_factor = clampf(voxel.noise, 0.0, 1.0)
	var solidity_factor = 1.0 - clampf(voxel.air_probability, 0.0, 1.0)

	var weight_sum = center_weight_factor + noise_weight_factor + solidity_weight_factor
	if weight_sum <= 0.0:
		return 0.0

	var weighted_score = (
		center_factor * center_weight_factor +
		noise_factor * noise_weight_factor +
		solidity_factor * solidity_weight_factor
	) / weight_sum
	return clampf(weighted_score, 0.0, 1.0)


func sort_voxels_by_weight_desc(a: Voxel, b: Voxel) -> bool:
	return a.village_weight > b.village_weight


func select_village_tiles(tiles: Array[Voxel], spacing: int) -> Array[Voxel]:
	var ranked_tiles = tiles.duplicate(false)
	if use_weighted_village_selection:
		ranked_tiles.sort_custom(Callable(self, "sort_voxels_by_weight_desc"))
	else:
		ranked_tiles.shuffle()

	var selected: Array[Voxel] = []
	var target_count = resolve_village_target_count(ranked_tiles.size())

	for candidate in ranked_tiles:
		if not candidate.placeable:
			continue
		if candidate.village_weight < min_village_weight:
			continue
		if not is_village_spacing_valid(candidate, selected, spacing):
			continue

		selected.append(candidate)
		mark_village_exclusion(candidate)

		if village_spawn_mode == VillageSpawnMode.TARGET_COUNT and selected.size() >= target_count:
			break

	print("Selected ", selected.size(), " village candidates")
	return selected


func resolve_village_target_count(placeable_count: int) -> int:
	if placeable_count <= 0:
		return 0
	if village_spawn_mode == VillageSpawnMode.SPACING_FILL:
		return placeable_count
	if dynamic_village_target:
		var dynamic_target = int(round(placeable_count * villages_per_placeable_tile))
		return clampi(dynamic_target, 1, mini(max_dynamic_village_target, placeable_count))
	return clampi(fixed_village_target, 1, placeable_count)


func axial_ring_distance(a: Vector2i, b: Vector2i) -> int:
	var q_diff = abs(a.x - b.x)
	var r_diff = abs(a.y - b.y)
	var s_diff = abs((a.x + a.y) - (b.x + b.y))
	return maxi(q_diff, maxi(r_diff, s_diff))


func is_village_spacing_valid(candidate: Voxel, selected: Array[Voxel], spacing: int) -> bool:
	for previous in selected:
		if axial_ring_distance(candidate.grid_position_xz, previous.grid_position_xz) <= spacing:
			return false
	return true


func mark_village_exclusion(candidate: Voxel) -> void:
	candidate.placeable = false
	var neighbor_tiles = candidate.neighbors
	if neighbor_tiles == null or neighbor_tiles.is_empty():
		neighbor_tiles = WorldMap.get_tile_neighbors_planar(candidate)
	for n in neighbor_tiles:
		n.placeable = false


func spawn_villages(villages: Array[Voxel]) -> void:
	if village == null and villages.size() > 0:
		push_warning("ObjectPlacer: village scene missing")
		return
	for voxel in villages:
		spawn_on_tile(voxel, village)


func resolve_unit_spawn_count(settings: GenerationSettings, village_count: int) -> int:
	match unit_spawn_mode:
		UnitSpawnMode.FIXED_COUNT:
			return fixed_unit_count
		UnitSpawnMode.PER_VILLAGE:
			if village_count <= 0:
				return 0
			var dynamic_units = int(round(float(village_count) * units_per_village))
			return clampi(dynamic_units, 1, max_dynamic_unit_count)
		_:
			return maxi(floori(settings.radius * 0.5), 0)


## Placeholder functionality for placing units onto map.
func create_starting_units(count : int, candidate_tiles: Array[Voxel] = []):
	if proto_unit == null:
		push_warning("ObjectPlacer: proto_unit scene missing")
		return
	if count <= 0:
		return

	var tiles_for_spawn = candidate_tiles
	if tiles_for_spawn.is_empty():
		tiles_for_spawn = get_placeable_voxels(current_result)
	if tiles_for_spawn.is_empty():
		return

	var safety_count = 0 #Add safety counter in case no valid tiles
	var max_attempts = maxi(count * 10, 50)
	while count > 0 and safety_count < max_attempts:
		var voxel: Voxel = tiles_for_spawn.pick_random()
		if voxel == null:
			safety_count += 1
			continue

		if voxel.occupier != null or not voxel.placeable:
			safety_count += 1
			continue
			
		var unit : Unit = proto_unit.instantiate()
		add_child(unit)
		unit.place_unit(voxel)
		voxel.placeable = false
		count -= 1
		safety_count += 1


# Spawn an object on a tile
func spawn_on_tile(voxel : Voxel, scene : PackedScene):
	if not voxel or not scene:
		push_warning("tile not found!")
		return

	var instance = scene.instantiate()
	add_child(instance)
	call_deferred("position_object", instance, voxel.world_position, 1)


func position_object(object : Node3D, target_location : Vector3, add_height : float = 0):
	object.position = target_location
	object.position.y += add_height

func clear_objects():
	var children = get_children()
	for c in children:
		c.free()
