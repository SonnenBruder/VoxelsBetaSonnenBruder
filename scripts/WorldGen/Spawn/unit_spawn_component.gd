extends Node
class_name UnitSpawnComponent


func resolve_unit_spawn_count(generation_settings: GenerationSettings, spawn_settings: SpawnSettings, village_count: int) -> int:
	if generation_settings == null or spawn_settings == null:
		return 0

	match spawn_settings.unit_spawn_mode:
		SpawnSettings.UnitSpawnMode.FIXED_COUNT:
			return spawn_settings.fixed_unit_count
		SpawnSettings.UnitSpawnMode.PER_VILLAGE:
			if village_count <= 0:
				return 0
			var dynamic_units = int(round(float(village_count) * spawn_settings.units_per_village))
			return clampi(dynamic_units, 1, spawn_settings.max_dynamic_unit_count)
		_:
			return maxi(floori(generation_settings.radius * 0.5), 0)


func spawn_units(
	proto_unit: PackedScene,
	spawn_parent: Node,
	count: int,
	candidate_tiles: Array[Voxel],
	spawn_settings: SpawnSettings
) -> int:
	if proto_unit == null or spawn_parent == null or spawn_settings == null:
		return 0
	if count <= 0 or candidate_tiles.is_empty():
		return 0

	var requested_count = count
	var spawned_count = 0
	var attempts = 0
	var max_attempts = maxi(requested_count * spawn_settings.max_unit_spawn_attempts_per_unit, requested_count)

	while count > 0 and attempts < max_attempts:
		var voxel: Voxel = candidate_tiles.pick_random()
		attempts += 1
		if voxel == null or voxel.occupier != null or not voxel.placeable:
			continue

		var unit = proto_unit.instantiate()
		spawn_parent.add_child(unit)
		if unit.has_method("place_unit"):
			unit.call("place_unit", voxel)
		else:
			unit.position = voxel.world_position
		voxel.placeable = false
		count -= 1
		spawned_count += 1

	return spawned_count
