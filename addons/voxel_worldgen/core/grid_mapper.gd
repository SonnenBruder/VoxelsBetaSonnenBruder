extends Object
class_name GridMapper

var settings : GenerationSettings
var noise_range := Vector2(99999, -99999) 
var random: RandomNumberGenerator

## Main entry point, Get all positions to spawn tiles on
func calculate_map_positions() -> Array[Voxel]:
	var voxels : Array[Voxel]
	settings = WorldMap.world_settings
	noise_range = Vector2(99999, -99999)
	if random == null:
		random = RandomNumberGenerator.new()
		random.seed = settings.noise.seed

	## Diamond and Circle also use the rectangular bounds. They carve our their shape from that rectangle
	## using their individual shape filters 
	var stagger : bool
	match settings.map_shape:
		0:
			stagger = false
			voxels = generate_map(hexagonal_bounds(), stagger, hexagonal_buffer_filter)
		1:
			stagger = true
			voxels = generate_map(rectangle_bounds(), stagger, rectangular_buffer_filter)
		2:
			stagger = true
			voxels = generate_map(rectangle_bounds(), stagger, diamond_buffer_filter, diamond_shape_filter)
		3:
			stagger = true
			voxels = generate_map(rectangle_bounds(), stagger, circular_buffer_filter, circle_shape_filter)

	print("Created ", voxels.size(), " positions")
	print("Noise Range: ", noise_range)
	WorldMap.noise_range = noise_range
	WorldMap.is_map_staggered = stagger
	return voxels


func generate_map(bounds: Callable, stagger: bool, buffer_filter: Callable, shape_filter: Callable = Callable()) -> Array[Voxel]:
	var voxel_array: Array[Voxel] = []
	for c in bounds.call():
		for r in bounds.call(c):
			for h in range(settings.max_height):
				if shape_filter and not shape_filter.call(c, r):
					continue
				var pos = Vector3(c, h, r) #column, height, row
				var voxel = generate_voxel(pos, stagger)
				modify_voxel(voxel, buffer_filter) #Hills, ocean, buffer
				voxel_array.append(voxel)
	return voxel_array


func generate_voxel(pos, stagger) -> Voxel:
	var new = Voxel.new()
	new.world_position = tile_to_world(pos, stagger)
	new.grid_position_xyz = Vector3i(pos.x, pos.y, pos.z)
	new.grid_position_xz = Vector2i(pos.x, pos.z)
	return new


## Apply ocean noise, hills noise and find buffer tiles
func modify_voxel(voxel : Voxel, buffer_filter):
	var c = voxel.grid_position_xz.x
	var r = voxel.grid_position_xz.y
	voxel.noise = noise_at_tile(voxel.world_position, settings.noise)
	
	if buffer_filter.call(c, r, settings.radius - settings.map_edge_buffer):
		voxel.buffer = true


func tile_to_world(pos, stagger: bool) -> Vector3:
	var SQRT3 = sqrt(3)
	var x: float = 3.0 / 2.0 * pos.x  # Horizontal spacing
	var z: float
	if stagger:
		z = pos.z * SQRT3 + ((int(pos.x) % 2 + 2) % 2) * (SQRT3 / 2)
	else:
		z = (pos.z * SQRT3 + (int(pos.x) * SQRT3 / 2))
	return Vector3(x * settings.voxel_size, pos.y * settings.voxel_height, z * settings.voxel_size)


# Get noise at position of tile
func noise_at_tile(pos : Vector3, texture : FastNoiseLite) -> float:
	var variance := 0.0
	if settings.variance > 0.0:
		variance = random.randf_range(-settings.variance, settings.variance)
	var value : float = texture.get_noise_3dv(pos) + variance
	#var normalized_value = (value + 1.0) * 0.5
	
	if value < noise_range.x:
		noise_range.x = value
	elif value > noise_range.y:
		noise_range.y = value
		
	return value


### Bounds
### # Specific bounds functions for each shape

func hexagonal_bounds() -> Callable:
	return func(col = null):
		if col == null:
			return range(-settings.radius, settings.radius + 1)
		else:
			return range(max(-settings.radius, -col - settings.radius), min(settings.radius, -col + settings.radius) + 1)


func rectangle_bounds() -> Callable:
	return func(_col = null):
		return range(-settings.radius, settings.radius + 1)


### Filters
### # Filters positions to keep only tiles inside a shape

func circle_shape_filter(col: int, row: int) -> bool:
	var dist = sqrt(col * col + row * row)
	return dist < settings.radius


func diamond_shape_filter(col: int, row: int) -> bool:
	var adjusted_row = row
	if col % 2 != 0:
		adjusted_row += 0.5 
	return abs(adjusted_row) + abs(col) < settings.radius


### Buffer-filters!
### Filter out buffer tiles

func hexagonal_buffer_filter(col: int, row: int, limit: int) -> bool:
	return abs(col + row) > limit or abs(col) > limit or abs(row) > limit


func rectangular_buffer_filter(col: int, row: int, limit: int) -> bool:
	return abs(col) > limit or abs(row) > limit


func diamond_buffer_filter(col: int, row: int, limit: int) -> bool:
	return abs(row) + abs(col) >= limit


func circular_buffer_filter(col: int, row: int, limit: int) -> bool:
	return col * col + row * row > limit * limit
