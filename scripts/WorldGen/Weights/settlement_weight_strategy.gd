extends "res://scripts/WorldGen/Weights/voxel_weight_strategy.gd"
class_name SettlementWeightStrategy

@export var weight_id: StringName = &"settlement"
@export_range(0.0, 5.0, 0.05) var center_weight_factor := 0.45
@export_range(0.0, 5.0, 0.05) var noise_weight_factor := 0.35
@export_range(0.0, 5.0, 0.05) var solidity_weight_factor := 0.20


func get_weight_id() -> StringName:
	return weight_id


func calculate_weight(surface_tile: VoxelSurfaceTile, _result: VoxelWorldResult, settings: GenerationSettings) -> float:
	var voxel := surface_tile.source_voxel
	if voxel == null:
		return 0.0

	var q = surface_tile.coord_2d.x
	var r = surface_tile.coord_2d.y
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
