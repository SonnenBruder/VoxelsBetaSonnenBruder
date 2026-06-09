extends Node
class_name VillageSpawnComponent

@export_category("Weighting")
## Optional custom strategy resource for voxel weighting.
@export var weight_strategy: VoxelWeightStrategy
## If true and no strategy assigned, use DefaultVoxelWeightStrategy.
@export var auto_create_default_weight_strategy := true


func _ready() -> void:
	ensure_weight_strategy()


func ensure_weight_strategy() -> void:
	if weight_strategy == null and auto_create_default_weight_strategy:
		weight_strategy = DefaultVoxelWeightStrategy.new()


func plan_villages(tiles: Array[Voxel], generation_settings: GenerationSettings, spawn_settings: SpawnSettings) -> Array[Voxel]:
	if tiles.is_empty() or generation_settings == null or spawn_settings == null:
		return []

	distribute_weights(tiles, generation_settings, spawn_settings)

	var ranked_tiles = tiles.duplicate(false)
	if spawn_settings.use_weighted_village_selection:
		ranked_tiles.sort_custom(Callable(self, "sort_voxels_by_weight_desc"))
	else:
		ranked_tiles.shuffle()

	var spacing = spawn_settings.resolve_village_spacing(generation_settings)
	var selected: Array[Voxel] = []
	var target_count = resolve_village_target_count(ranked_tiles.size(), spawn_settings)

	for candidate in ranked_tiles:
		if not candidate.placeable:
			continue
		if candidate.village_weight < spawn_settings.min_village_weight:
			continue
		if not is_village_spacing_valid(candidate, selected, spacing):
			continue

		selected.append(candidate)
		mark_village_exclusion(candidate)

		if spawn_settings.village_spawn_mode == SpawnSettings.VillageSpawnMode.TARGET_COUNT and selected.size() >= target_count:
			break

	return selected


func distribute_weights(tiles: Array[Voxel], generation_settings: GenerationSettings, spawn_settings: SpawnSettings) -> void:
	ensure_weight_strategy()
	for voxel in tiles:
		voxel.village_weight = weight_strategy.calculate_weight(voxel, generation_settings, spawn_settings)


func resolve_village_target_count(placeable_count: int, spawn_settings: SpawnSettings) -> int:
	if placeable_count <= 0:
		return 0
	if spawn_settings.village_spawn_mode == SpawnSettings.VillageSpawnMode.SPACING_FILL:
		return placeable_count
	if spawn_settings.dynamic_village_target:
		var dynamic_target = int(round(placeable_count * spawn_settings.villages_per_placeable_tile))
		return clampi(dynamic_target, 1, mini(spawn_settings.max_dynamic_village_target, placeable_count))
	return clampi(spawn_settings.fixed_village_target, 1, placeable_count)


func sort_voxels_by_weight_desc(a: Voxel, b: Voxel) -> bool:
	return a.village_weight > b.village_weight


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
