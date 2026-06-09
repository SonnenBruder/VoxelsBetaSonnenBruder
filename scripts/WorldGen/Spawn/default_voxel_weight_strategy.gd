extends VoxelWeightStrategy
class_name DefaultVoxelWeightStrategy


func calculate_weight(voxel: Voxel, generation_settings: GenerationSettings, spawn_settings: SpawnSettings) -> float:
	if voxel == null or generation_settings == null or spawn_settings == null:
		return 0.0

	var q = voxel.grid_position_xz.x
	var r = voxel.grid_position_xz.y
	var ring = max(abs(q), abs(r), abs(q + r))
	var radius = maxi(generation_settings.radius, 1)
	var center_factor = 1.0 - clampf(float(ring) / float(radius), 0.0, 1.0)
	var noise_factor = clampf(voxel.noise, 0.0, 1.0)
	var solidity_factor = 1.0 - clampf(voxel.air_probability, 0.0, 1.0)

	var factors = spawn_settings.resolve_weight_factors()
	var center_weight = factors.x
	var noise_weight = factors.y
	var solidity_weight = factors.z

	var weight_sum = center_weight + noise_weight + solidity_weight
	if weight_sum <= 0.0:
		return 0.0

	var weighted_score = (
		center_factor * center_weight +
		noise_factor * noise_weight +
		solidity_factor * solidity_weight
	) / weight_sum

	return clampf(weighted_score, 0.0, 1.0)
