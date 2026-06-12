extends "res://scripts/WorldGen/Terrain/voxel_terrain_strategy.gd"
class_name DefaultTerrainStrategy

func generate(context) -> Dictionary:
	var mapper = GridMapper.new()
	mapper.random = context.random
	var voxels = mapper.calculate_map_positions()
	context.interval["Calculate Map Positions -- "] = Time.get_ticks_msec()

	var voxel_generator = VoxelGenerator.new()
	voxel_generator.atlas_settings = context.atlas_settings
	var chunk = voxel_generator.generate_chunk(voxels, context.interval)

	return {
		"chunk": chunk,
		"voxels": voxels
	}
