extends Node

var map_as_dict : Dictionary[Vector3i, Voxel] = {}
var is_map_staggered = false
var world_settings : GenerationSettings
var noise_range : Vector2
var surface_layer: Dictionary[Vector3i, Voxel] = {}


## Construct a dictionary for our 2d top layer of voxels
func set_map(all_voxels, top_voxels):
	map_as_dict.clear()
	surface_layer.clear()
	for voxel : Voxel in all_voxels:
		map_as_dict[Vector3i(voxel.grid_position_xyz)] = voxel
	for t_voxel in top_voxels:
		surface_layer[Vector3i(t_voxel.grid_position_xyz)] = t_voxel


func clear_map():
	map_as_dict.clear()
	surface_layer.clear()
	noise_range = Vector2.ZERO
	world_settings = null


## Handy function for finding all neigbors of a voxel
func get_tile_neighbors_planar(voxel : Voxel) -> Array[Voxel]:
	var neighbors : Array[Voxel] = []
	var neighbor_positions = VoxelData.HEXAGONAL_NEIGHBOR_DIRECTIONS
	if is_map_staggered:
		if voxel.grid_position_xz.x % 2 == 0:
			neighbor_positions = VoxelData.NEIGHBOR_DIRECTIONS_EVEN
		else:
			neighbor_positions = VoxelData.NEIGHBOR_DIRECTIONS_ODD
			
	for direction in neighbor_positions:
		var neighbor_coords = Vector3i(
			voxel.grid_position_xz.x + int(direction.x), #x + dir
			 int(voxel.grid_position_xyz.y), # same y
			 voxel.grid_position_xz.y + int(direction.y)) #z + dir
			
		if neighbor_coords in map_as_dict:
			neighbors.append(map_as_dict[neighbor_coords])
	return neighbors
