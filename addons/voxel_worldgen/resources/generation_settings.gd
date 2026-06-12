extends Resource
class_name GenerationSettings

## Supported 2D footprint shapes for generated map bounds.
enum shape {HEXAGONAL, RECTANGULAR, DIAMOND, CIRCLE}

@export_category("Map")
## Footprint shape used when generating tile coordinates.
@export var map_shape : shape = shape.HEXAGONAL
## Deterministic map seed. Use 0 for random seed each generation.
@export var map_seed : int
## Radius/half-size of map footprint in grid coordinates.
@export_range(0, 64, 1) var radius: int = 5
## Number of vertical voxel layers generated per tile.
@export_range(1, 128, 1) var max_height: int = 3
## Step size used by terrace-shaping pass.
@export_range(0, 8) var terrace_steps = 1
## Removes floating overhang voxels during shaping.
@export var remove_overhang = true
## Blend between terrain noise and normalized height when classifying air.
@export_range(0.0, 1.0) var noise_height_bias : float = 0.5
## Air threshold. Higher value keeps more solid ground.
@export_range(0.0, 1.0) var ground_to_air_ratio : float = 0.5
## Flattens/removes edge buffer area around map.
@export var flat_buffer = true
#@export var debug : bool = false
## Noise source sampled for terrain shaping.
@export var noise : FastNoiseLite
## Random jitter added to sampled noise per voxel.
@export_range(0.0, 1.0) var variance = 0.0

@export_category("Voxel")
## Horizontal scale multiplier for each hex voxel.
@export_range(0.5, 10) var voxel_size : float = 1
## Vertical height of each voxel layer.
@export_range(0.5, 10) var voxel_height : float = 1
## Mesh smoothing group: -1 flat shading, 0 smooth shading.
@export_range(-1, 0, 1.0) var shading : int = -1
## Material override applied to generated chunk mesh.
@export var material : Material
## Generates bottom faces when exposed.
@export var draw_bottom = false
## Forces first layer (y=0) to remain solid.
@export var solid_first_layer = true

@export_category("Villages")
## Enables optional village and unit placement systems.
@export var spawn_villages_and_units = true
## Border thickness excluded from placement.
@export var map_edge_buffer = 2
## Minimum ring-distance spacing between placed villages.
@export_range(1, 99) var spacing = 6
