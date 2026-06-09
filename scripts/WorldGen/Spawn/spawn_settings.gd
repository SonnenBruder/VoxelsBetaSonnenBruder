extends Resource
class_name SpawnSettings

## Modes for selecting how villages are distributed.
enum VillageSpawnMode {SPACING_FILL, TARGET_COUNT}
## Modes for selecting how many units spawn.
enum UnitSpawnMode {RADIUS_BASED, FIXED_COUNT, PER_VILLAGE}
## Presets for placeholder village voxel weighting.
enum WeightingProfile {BALANCED, CENTER_FOCUS, NOISE_FOCUS, SOLIDITY_FOCUS, CUSTOM}

@export_category("Global")
## If true, read spawn enable switch from GenerationSettings.
@export var use_generation_spawn_toggle := true
## Fallback toggle used when generation toggle is ignored.
@export var spawn_enabled_override := true

@export_category("Village Rules")
## Village distribution mode.
@export var village_spawn_mode: VillageSpawnMode = VillageSpawnMode.SPACING_FILL
## If >= 0 this overrides GenerationSettings.spacing.
@export_range(-1, 99, 1) var village_spacing_override := -1
## If true, target village count scales with placeable tile count.
@export var dynamic_village_target := true
## Fallback target villages when dynamic target is disabled.
@export_range(1, 256, 1) var fixed_village_target := 8
## Dynamic villages ratio against placeable tile count.
@export_range(0.001, 0.2, 0.001) var villages_per_placeable_tile := 0.02
## Hard cap for dynamic village target.
@export_range(1, 512, 1) var max_dynamic_village_target := 64
## Enables weighted ranking for village candidate ordering.
@export var use_weighted_village_selection := true
## Minimum weight required for village candidate eligibility.
@export_range(0.0, 1.0, 0.01) var min_village_weight := 0.0

@export_category("Weighting")
## Placeholder weighting profile for village ranking.
@export var weighting_profile: WeightingProfile = WeightingProfile.BALANCED
## Custom center-distance factor used when profile is CUSTOM.
@export_range(0.0, 5.0, 0.05) var custom_center_weight := 0.45
## Custom noise factor used when profile is CUSTOM.
@export_range(0.0, 5.0, 0.05) var custom_noise_weight := 0.35
## Custom solidity factor used when profile is CUSTOM.
@export_range(0.0, 5.0, 0.05) var custom_solidity_weight := 0.20

@export_category("Unit Rules")
## Unit count mode resolved after village planning.
@export var unit_spawn_mode: UnitSpawnMode = UnitSpawnMode.RADIUS_BASED
## Unit count used by FIXED_COUNT mode.
@export_range(1, 512, 1) var fixed_unit_count := 6
## Units-per-village ratio for PER_VILLAGE mode.
@export_range(0.0, 5.0, 0.1) var units_per_village := 0.8
## Hard cap for PER_VILLAGE dynamic unit count.
@export_range(1, 512, 1) var max_dynamic_unit_count := 96
## Safety attempts per requested unit when spawning units.
@export_range(1, 50, 1) var max_unit_spawn_attempts_per_unit := 10


func is_spawn_enabled(generation_settings: GenerationSettings) -> bool:
	if use_generation_spawn_toggle:
		return generation_settings != null and generation_settings.spawn_villages_and_units
	return spawn_enabled_override


func resolve_village_spacing(generation_settings: GenerationSettings) -> int:
	if village_spacing_override >= 0:
		return village_spacing_override
	if generation_settings == null:
		return 0
	return generation_settings.spacing


func resolve_weight_factors() -> Vector3:
	match weighting_profile:
		WeightingProfile.CENTER_FOCUS:
			return Vector3(0.70, 0.20, 0.10)
		WeightingProfile.NOISE_FOCUS:
			return Vector3(0.20, 0.70, 0.10)
		WeightingProfile.SOLIDITY_FOCUS:
			return Vector3(0.20, 0.15, 0.65)
		WeightingProfile.CUSTOM:
			return Vector3(custom_center_weight, custom_noise_weight, custom_solidity_weight)
		_:
			return Vector3(0.45, 0.35, 0.20)
