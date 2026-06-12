extends Resource
class_name VoxelWeightStrategy

func get_weight_id() -> StringName:
	return &"weight"


func calculate_weight(_surface_tile: VoxelSurfaceTile, _result: VoxelWorldResult, _settings: GenerationSettings) -> float:
	return 0.0
