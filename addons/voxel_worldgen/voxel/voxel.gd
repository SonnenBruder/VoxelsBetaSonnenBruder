class_name Voxel

var grid_position_xyz : Vector3i
var grid_position_xz : Vector2i

var world_position : Vector3
var type = VoxelData.voxel_type.GRASS
var noise : float = 0.0
var buffer : bool = false
var water : bool = false
var air_probability : float = 0
## Placeholder ranking score for weighted village placement.
var village_weight : float = 0.0
var surface_voxel := false

var neighbors = []
var placeable = true
var occupier : Unit
var collider
