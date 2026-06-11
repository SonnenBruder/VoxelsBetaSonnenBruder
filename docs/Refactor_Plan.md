**Recommended Data Shape**
Use dictionary + result resource, not 3D array.

Reason: your map has negative coordinates, hex/circle/diamond shapes, holes/air, variable height. 3D arrays waste space and get annoying. Dictionary key fits Godot better.

Best split:

- Full voxel map: Dictionary keyed by Vector3i.
- Surface map: Dictionary keyed by Vector2i.
- Result wrapper: Resource or RefCounted object holding both maps plus seed, profile, chunk refs, metadata.

Surface tile record should look like:

- coord_2d: Vector2i, hex coordinate on surface.
- top_grid_coord: Vector3i, actual top prism grid position.
- world_position: Vector3, actual scene position.
- height: int, top y layer.
- terrain_type: int or StringName.
- passable: bool.
- placeable: bool.
- is_empty: bool.
- weights: Dictionary, for example village = 0.72, battlefield_cover = 0.44.
- metadata: Dictionary, open extension bag for later.

This gives other addon enough info to place villages, battlefields, roads, units, loot, biome markers, anything.

**Plan Content**

# Voxel Worldgen Addon Plan

## Goal

Build full plug-and-play Godot addon for voxel hex world generation.

Addon must let another project add one generator node, assign one settings resource, generate 3D terrain, and receive clean output data for gameplay systems.

Target uses:

- Main overworld generation.
- Smaller subterrain generation, like battlefields entered from overworld encounters.
- Optional metadata and scoring output for external placement systems.
- Low-effort export into new projects.

## Core Decisions

1. Keep globals.

WorldMap and VoxelData stay as autoloads. This is acceptable for addon because worldgen needs central runtime map state.

Current autoloads live in [project.godot](project.godot#L24).

2. Split placement out.

Object placement must become separate addon/module. Worldgen only generates terrain and output data.

Current ObjectPlacer in [scripts/WorldGen/object_placer.gd](scripts/WorldGen/object_placer.gd) should move out of core worldgen later.

3. Weight is optional.

Worldgen can calculate weights, but must not know about villages specifically.

Replace village-only weight with generic weight channels.

Current field is village-specific in [scripts/WorldGen/Voxel/voxel.gd](scripts/WorldGen/Voxel/voxel.gd#L13). Future should become weights dictionary or metadata dictionary.

4. Use strategy resources.

Terrain algorithm and weight algorithm should be swappable through Resource classes.

This fits Godot editor workflow better than raw functions because resources are inspector-assignable, savable, reusable, and exportable.

5. Output must be stable API.

Other addons should depend on generated result data, not internal generator scripts.

Worldgen emits result. Placement addon listens and decides what to place.

## Current State

World generation flow:

1. [scripts/WorldGen/world_gen.gd](scripts/WorldGen/world_gen.gd) starts generation.
2. [scripts/WorldGen/grid_mapper.gd](scripts/WorldGen/grid_mapper.gd) creates voxel positions.
3. [scripts/WorldGen/Voxel/voxel_generator.gd](scripts/WorldGen/Voxel/voxel_generator.gd) shapes voxels and builds mesh.
4. [scripts/Global/world.gd](scripts/Global/world.gd) stores map dictionaries.
5. [scripts/WorldGen/world_gen.gd](scripts/WorldGen/world_gen.gd#L78) emits world_generated.
6. Optional listeners react.

Good existing parts:

- Signals already decouple systems.
- GenerationSettings already exists in [scripts/WorldGen/generation_settings.gd](scripts/WorldGen/generation_settings.gd).
- WorldMap already stores full map and surface layer in [scripts/Global/world.gd](scripts/Global/world.gd).
- Reuse guide exists in [docs/REUSE_GUIDE.md](docs/REUSE_GUIDE.md).

Weak parts to fix:

- Atlas constants hardcoded in [scripts/WorldGen/Voxel/voxel_generator.gd](scripts/WorldGen/Voxel/voxel_generator.gd#L9).
- Random seed uses global randi in [scripts/WorldGen/world_gen.gd](scripts/WorldGen/world_gen.gd#L54).
- Noise variance uses global randf_range in [scripts/WorldGen/grid_mapper.gd](scripts/WorldGen/grid_mapper.gd#L81).
- Weight is village-specific in [scripts/WorldGen/object_placer.gd](scripts/WorldGen/object_placer.gd#L120).
- Placement logic lives inside worldgen folder.

## Target Addon Shape

Worldgen addon contains:

- Generator node.
- Generator scene.
- Generation settings resource.
- Atlas settings resource.
- Terrain strategy resources.
- Weight strategy resources.
- Result data classes.
- WorldMap autoload.
- VoxelData autoload.
- Demo preset resources.

Placement addon contains:

- Placement manager node.
- Placement rule resources.
- Scene spawning logic.
- Village placement.
- Battlefield placement.
- Unit/object placement.
- Listeners for worldgen result signal.

## Public API

Worldgen node exports:

- settings: main generation settings resource.
- chunks_root: where generated chunk nodes are added.
- generate_on_ready: auto generate toggle.
- output_surface_data: bool.
- output_full_voxel_data: bool.
- weight_strategy: optional resource.
- terrain_strategy: optional resource.
- atlas_settings: atlas resource.
- generation_seed: int.

Worldgen node methods:

- regenerate_world.
- generate_world.
- clear_world.
- get_last_result.
- get_surface_tile_at_coord.
- get_voxel_at_grid_coord.

Worldgen node signals:

- generation_started.
- generation_profile_ready.
- world_generated.
- world_result_ready.

Prefer new signal:

world_result_ready(result)

Keep old signal:

world_generated(chunk, voxel_count)

Reason: old signal keeps current project working while new result signal powers addon systems.

## Result Data Model

Create VoxelWorldResult.

Fields:

- seed_used: int.
- settings: GenerationSettings.
- chunk: Chunk.
- voxel_count: int.
- surface_count: int.
- full_voxels_by_grid: Dictionary.
- surface_tiles_by_coord: Dictionary.
- generation_profile: Dictionary.
- noise_range: Vector2.
- metadata: Dictionary.

Create VoxelSurfaceTile.

Fields:

- coord_2d: Vector2i.
- top_grid_coord: Vector3i.
- world_position: Vector3.
- height: int.
- terrain_type: int or StringName.
- is_empty: bool.
- passable: bool.
- placeable: bool.
- weights: Dictionary.
- metadata: Dictionary.
- source_voxel: Voxel optional runtime reference.

Recommended keying:

- full_voxels_by_grid uses Vector3i.
- surface_tiles_by_coord uses Vector2i.

Reason: placement mostly cares about surface map, not every buried voxel.

## Weight Strategy Design

Do not pass raw function first. Use Resource strategy.

Base strategy:

class_name VoxelWeightStrategy
extends Resource

Main method:

calculate_weight(surface_tile, result, settings) -> float

Optional method:

get_weight_id() -> StringName

Examples:

- NoWeightStrategy returns 0.
- CenterWeightStrategy favors center.
- VillageWeightStrategy uses center + noise + solidity.
- BattlefieldWeightStrategy favors flat area, distance from villages, biome rules.
- RoadWeightStrategy favors passable slopes.

Store output:

surface_tile.weights[strategy_id] = calculated_weight

For many scores, use list of strategies:

- weight_strategies: Array[VoxelWeightStrategy]

Reason: village weight and battlefield weight can both exist on same tile.

## Terrain Strategy Design

Current generation algorithm becomes default strategy.

Base strategy:

- calculate_positions.
- shape_voxels.
- assign_types.
- build_mesh or return shaped voxels for mesh builder.

Do this gradually. Do not rewrite all at once.

Step 1:

Keep [scripts/WorldGen/grid_mapper.gd](scripts/WorldGen/grid_mapper.gd) and [scripts/WorldGen/Voxel/voxel_generator.gd](scripts/WorldGen/Voxel/voxel_generator.gd), but wrap them behind DefaultTerrainStrategy.

Step 2:

WorldGenerator calls terrain_strategy.generate(context).

Step 3:

Add BattlefieldTerrainStrategy later.

Battlefield settings can use same generator with smaller radius, different terrain rules, different seed derived from overworld encounter.

## Atlas Settings Resource

Move these from [scripts/WorldGen/Voxel/voxel_generator.gd](scripts/WorldGen/Voxel/voxel_generator.gd#L9):

- atlas_resolution.
- tile_size.
- tile_stride.
- tile_margin.
- tile_map.

Current tile map is in [scripts/Global/voxel_data.gd](scripts/Global/voxel_data.gd#L6).

Decision needed:

Option A: Keep tile_map in VoxelData, move only UV dimensions into AtlasSettings.

Option B: Move tile_map too into TerrainMaterialPalette resource.

Recommendation: Option B long-term.

Reason: another project will have different terrain types and atlas layout.

Short-term: Option A, less breakage.

## Deterministic RNG

Create RNG context per generation.

Fields:

- requested_seed.
- seed_used.
- random: RandomNumberGenerator.

Replace global randi in [scripts/WorldGen/world_gen.gd](scripts/WorldGen/world_gen.gd#L54).

Replace global randf_range in [scripts/WorldGen/grid_mapper.gd](scripts/WorldGen/grid_mapper.gd#L81).

Rules:

- If generation_seed is 0, make random seed once and store seed_used.
- All random calls use same RNG context.
- Noise seed gets seed_used.
- Subterrains derive seed from parent seed plus encounter id.

Example seed derivation idea:

- overworld seed = 12345.
- battlefield seed = hash of overworld seed, region coord, encounter id.

Result: same overworld battle always creates same battlefield.

## Settings Design

Create VoxelWorldPreset resource.

Contains:

- generation_seed.
- generation_settings.
- atlas_settings.
- terrain_strategy.
- weight_strategies.
- output_options.
- metadata_defaults.

Keep existing GenerationSettings for terrain knobs.

Add output options:

- include_full_voxel_map.
- include_surface_map.
- include_mesh_chunk.
- include_debug_profile.
- write_to_world_map.

Add battlefield support:

- generation_role: overworld or battlefield.
- parent_world_seed.
- parent_surface_coord.
- battlefield_size.
- battlefield_context metadata.

## Voxel Placement Rules

User request: which voxels get placed where.

Create terrain placement rule resource.

Concept:

- Input: voxel noise, height, neighbors, buffer flag, biome context.
- Output: voxel type, passable, placeable, metadata.

Rule examples:

- Bedrock rule for y 0.
- Air rule for high air probability.
- Grass surface rule.
- Dirt underground rule.
- Sand near low/noise areas.
- Water future rule.

This replaces hardcoded assign_type logic in [scripts/WorldGen/Voxel/voxel_generator.gd](scripts/WorldGen/Voxel/voxel_generator.gd).

Do later, after addon shell works.

## Decoupling Placement

Remove village-specific generation responsibility from worldgen.

Worldgen outputs:

- surface tiles.
- weights.
- metadata.
- terrain mesh.

Placement addon consumes:

- VoxelWorldResult.
- chosen placement rules.
- scene references.

Placement addon decides:

- village candidates.
- battlefield entrances.
- roads.
- units.
- props.
- resources.

Move current village selection from [scripts/WorldGen/object_placer.gd](scripts/WorldGen/object_placer.gd) into placement addon.

Worldgen should never instantiate village scenes.

## Battlebrothers-Style Battlefield Flow

Overworld generation:

1. Generate overworld result.
2. Placement addon places villages, roads, encounter points.
3. Encounter stores surface coord and metadata.

Battle starts:

1. Create battlefield generation request.
2. Request derives seed from overworld seed plus encounter id.
3. Use smaller battlefield preset.
4. Terrain strategy can consider overworld tile metadata.
5. Generate battlefield chunk in battle scene.
6. Placement addon places units, cover, objectives based on battlefield result.

Important: battlefield is not special hardcoded world. It is same generator with different preset and context.

## Implementation Phases

### Phase 1: Addon Boundary

Goal: package current generator as addon without behavior changes.

Tasks:

1. Create addon folder.
2. Move or duplicate core worldgen scripts into addon structure.
3. Add plugin config and optional plugin script.
4. Keep WorldMap and VoxelData autoload requirement documented.
5. Keep existing scene working.
6. Add minimal demo scene with generator node and chunks root.

Acceptance:

- Current map still generates.
- Another empty project can copy addon and generate terrain after adding autoloads.
- No placement dependency needed.

### Phase 2: Result API

Goal: emit useful output data.

Tasks:

1. Create VoxelWorldResult data class.
2. Create VoxelSurfaceTile data class.
3. Build surface_tiles_by_coord from WorldMap.surface_layer.
4. Keep full_voxels_by_grid from WorldMap.map_as_dict.
5. Add world_result_ready(result) signal.
6. Keep old world_generated signal.

Acceptance:

- Consumer can inspect top surface by Vector2i.
- Consumer can read height, world position, terrain type, passable, placeable, metadata.
- Current ObjectPlacer can be adapted to use result later.

### Phase 3: Deterministic RNG

Goal: reproducible generation.

Tasks:

1. Add seed_used to result.
2. Add RNG context.
3. Replace global randi.
4. Replace global randf_range.
5. Store random seed when input seed is 0.
6. Add repeat-generation test checklist.

Acceptance:

- Same seed gives same terrain and same weights.
- Random seed still possible but reported.

### Phase 4: Atlas Resource

Goal: remove hardcoded atlas constants.

Tasks:

1. Create atlas settings resource.
2. Move atlas dimensions from voxel generator into resource.
3. Expose atlas settings on generator or preset.
4. Later move tile map from VoxelData into palette resource.

Acceptance:

- Different atlas dimensions can be assigned in inspector.
- Existing atlas still works with default resource.

### Phase 5: Weight Strategies

Goal: optional generic weights.

Tasks:

1. Create base weight strategy resource.
2. Create no-op strategy.
3. Create default village-like strategy using current calculation from [scripts/WorldGen/object_placer.gd](scripts/WorldGen/object_placer.gd#L125).
4. Store weights by strategy id.
5. Remove village_weight dependency from generator output.
6. Keep compatibility by writing village_weight temporarily if needed.

Acceptance:

- No weight strategy means valid result with empty weights.
- One or more strategies can write weights.
- Placement addon can choose which weight channel to use.

### Phase 6: Placement Addon Split

Goal: move placement out of worldgen.

Tasks:

1. Create separate placement addon/module.
2. Move ObjectPlacer logic there.
3. Change ObjectPlacer input from WorldMap to VoxelWorldResult.
4. Scene spawning remains in placement addon.
5. Add placement rules for villages and units.

Acceptance:

- Worldgen addon has zero village/unit scene refs.
- Placement addon can place villages after world_result_ready.
- Worldgen can be used alone.

### Phase 7: Terrain Strategy Interface

Goal: support overworld and battlefields behind same generator.

Tasks:

1. Define terrain strategy resource.
2. Wrap current grid mapper and voxel generator as default terrain strategy.
3. Add generation context object.
4. Add battlefield preset.
5. Add battlefield seed derivation.

Acceptance:

- Same WorldGenerator can use different terrain strategy resources.
- Battlefield terrain can generate in separate scene with same API.

### Phase 8: Terrain Rules and Metadata

Goal: make voxel type/passability/placeability configurable.

Tasks:

1. Add terrain rule resources.
2. Move assign_type logic into rule system.
3. Surface tile gets terrain_type, passable, placeable, metadata.
4. Add metadata tags like forest, road_candidate, settlement_candidate, cover_candidate.

Acceptance:

- Placement addon no longer guesses from raw Voxel fields.
- Game systems use stable metadata.

## Migration Order Recommendation

Best order for low pain:

1. Result API first.
2. Deterministic RNG second.
3. Atlas settings third.
4. Weight strategies fourth.
5. Split placement addon fifth.
6. Terrain strategy sixth.
7. Terrain rules seventh.

Reason: result API creates stable contract. Everything else can migrate behind it.

## Risks

1. Refactor too much at once.

Fix: keep old signals and WorldMap while adding new result signal.

2. Resource strategy can get too abstract.

Fix: start with one default strategy and one weight strategy only.

3. Placement and generation get mixed again.

Fix: rule: worldgen never instantiates gameplay scenes.

4. Godot dictionaries with Vector keys are runtime-friendly but not nice for saved resources.

Fix: result object can be runtime RefCounted first. Add save/export format later if needed.

5. Voxel references in result can become stale after regeneration.

Fix: result is valid until next regeneration. On regeneration, emit new result and clear old consumers.

## Done Definition

Worldgen addon is ready when:

- New project can install addon.
- User assigns one preset resource.
- User adds one generator node.
- Terrain generates.
- Result signal gives surface dictionary and full voxel dictionary.
- Same seed generates same result.
- Placement addon can consume result without touching generator internals.
- Battlefields can use same generator with different preset and seed context.

**Next Best Step**
Start with Phase 2 before moving files. Add result API while current project still runs. This gives clean contract for placement addon and battlefield generator before addon packaging creates path churn.
