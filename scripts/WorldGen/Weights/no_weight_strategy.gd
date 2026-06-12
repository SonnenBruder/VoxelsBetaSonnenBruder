extends "res://scripts/WorldGen/Weights/voxel_weight_strategy.gd"
class_name NoVoxelWeightStrategy

func get_weight_id() -> StringName:
	return &"none"


func calculate_weight(_surface_tile: VoxelSurfaceTile, _result: VoxelWorldResult, _settings: GenerationSettings) -> float:
	return 0.0
