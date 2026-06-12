extends Resource
class_name VoxelTerrainStrategy

func generate(_context) -> Dictionary:
	push_error("VoxelTerrainStrategy.generate must be implemented by a concrete strategy")
	return {}
