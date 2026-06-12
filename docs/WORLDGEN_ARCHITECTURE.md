# Voxel Worldgen Architecture Map

This document is the visual companion to [REUSE_GUIDE.md](REUSE_GUIDE.md). It shows how the addon generator pieces are wired together and where the remaining placement boundary should land.

## Component Wiring

```mermaid
flowchart LR
    subgraph Scene["Scene Nodes"]
        GeneratorNode["VoxelWorldGenerator<br/>addons/voxel_worldgen/world_generator.gd"]
        ChunksRoot["Chunks root<br/>Node3D"]
        ReportLabel["GenerationReportLabel<br/>optional UI listener"]
        ObjectPlacer["ObjectPlacer<br/>current placement listener"]
        Interaction["Interaction tracker<br/>legacy world_generated listener"]
    end

    subgraph Config["Config Resources"]
        Preset["VoxelWorldPreset<br/>optional aggregate config"]
        GenSettings["GenerationSettings<br/>terrain knobs"]
        AtlasSettings["VoxelAtlasSettings<br/>atlas dimensions"]
        TerrainStrategy["VoxelTerrainStrategy<br/>DefaultTerrainStrategy"]
        WeightStrategies["Array[VoxelWeightStrategy]<br/>No / Settlement / custom"]
    end

    subgraph Runtime["Generation Runtime"]
        Context["VoxelGenerationContext<br/>seed, RNG, settings, atlas, metadata"]
        GridMapper["GridMapper<br/>positions + noise"]
        VoxelGenerator["VoxelGenerator<br/>shape voxels + mesh"]
        Chunk["Chunk<br/>mesh, collider, voxel layers"]
    end

    subgraph Globals["Autoload Runtime State"]
        WorldMap["WorldMap<br/>map_as_dict, surface_layer"]
        VoxelData["VoxelData<br/>tile_map, neighbor tables"]
    end

    subgraph Result["Clean Output API"]
        WorldResult["VoxelWorldResult<br/>seed, maps, chunk, profile, metadata"]
        FullMap["full_voxels_by_grid<br/>Dictionary[Vector3i, Voxel]"]
        SurfaceMap["surface_tiles_by_coord<br/>Dictionary[Vector2i, VoxelSurfaceTile]"]
        SurfaceTile["VoxelSurfaceTile<br/>height, position, terrain, flags, weights"]
    end

    Preset -->|fills exports| GeneratorNode
    GenSettings --> GeneratorNode
    AtlasSettings --> GeneratorNode
    TerrainStrategy --> GeneratorNode
    WeightStrategies --> GeneratorNode

    GeneratorNode -->|parents chunk| ChunksRoot
    GeneratorNode -->|prepare_generation_context| Context
    Context -->|generate context| TerrainStrategy
    TerrainStrategy --> GridMapper
    TerrainStrategy --> VoxelGenerator
    Context -->|random| GridMapper
    Context -->|atlas_settings| VoxelGenerator
    GenSettings --> GridMapper
    GenSettings --> VoxelGenerator
    VoxelData --> GridMapper
    VoxelData --> VoxelGenerator

    GridMapper -->|Array Voxel| VoxelGenerator
    VoxelGenerator --> Chunk
    VoxelGenerator -->|set_map| WorldMap
    Chunk -->|init_chunk| ChunksRoot

    WorldMap -->|map_as_dict| FullMap
    WorldMap -->|surface_layer| SurfaceMap
    GeneratorNode -->|build_world_result| WorldResult
    WorldResult --> FullMap
    WorldResult --> SurfaceMap
    SurfaceMap --> SurfaceTile
    WeightStrategies -->|write weights| SurfaceTile

    GeneratorNode -->|generation_started| ReportLabel
    GeneratorNode -->|generation_profile_ready| ReportLabel
    GeneratorNode -->|world_result_ready| ObjectPlacer
    GeneratorNode -->|world_generated legacy| ObjectPlacer
    GeneratorNode -->|world_generated legacy| Interaction
```

## Generation Sequence

```mermaid
sequenceDiagram
    participant Caller as Caller / _ready / Button
    participant WG as WorldGenerator
    participant Preset as VoxelWorldPreset
    participant Context as VoxelGenerationContext
    participant Strategy as DefaultTerrainStrategy
    participant Mapper as GridMapper
    participant VG as VoxelGenerator
    participant WM as WorldMap
    participant Chunk as Chunk
    participant Result as VoxelWorldResult
    participant Listener as Result Listeners
    participant Legacy as Legacy Listeners

    Caller->>WG: regenerate_world()
    WG->>Preset: apply_preset() if assigned
    WG->>WM: clear_map()
    WG->>WG: clear old chunk children
    WG->>Context: create context
    WG->>Context: resolve seed + RNG + atlas + metadata
    WG-->>Listener: generation_started(seed_used)
    WG->>Strategy: generate(context)
    Strategy->>Mapper: calculate_map_positions()
    Mapper-->>Strategy: Array[Voxel]
    Strategy->>VG: generate_chunk(voxels, interval)
    VG->>VG: process_voxels()
    VG->>VG: assign_type()
    VG->>VG: build mesh with atlas settings
    VG->>WM: set_map(all_voxels, surface_voxels)
    VG-->>Strategy: Chunk
    Strategy-->>WG: {"chunk": chunk, "voxels": voxels}
    WG->>Chunk: add_child + init_chunk()
    Chunk->>Chunk: collider + voxel_layers
    WG->>Result: build_world_result()
    WG->>Result: apply_weight_strategies()
    WG-->>Listener: generation_profile_ready(profile)
    WG-->>Listener: world_result_ready(result)
    WG-->>Legacy: world_generated(chunk, voxel_count)
```

## Result Data Shape

```mermaid
flowchart TD
    Result["VoxelWorldResult"]

    Result --> Seed["seed_used: int"]
    Result --> Settings["settings: GenerationSettings"]
    Result --> ChunkRef["chunk: Chunk"]
    Result --> Counts["voxel_count / surface_count"]
    Result --> Profile["generation_profile: Dictionary"]
    Result --> Noise["noise_range: Vector2"]
    Result --> Metadata["metadata: Dictionary"]

    Result --> Full["full_voxels_by_grid"]
    Full --> FullKey["key: Vector3i"]
    Full --> Voxel["value: Voxel"]

    Result --> Surface["surface_tiles_by_coord"]
    Surface --> SurfaceKey["key: Vector2i"]
    Surface --> Tile["value: VoxelSurfaceTile"]

    Tile --> Coord["coord_2d: Vector2i"]
    Tile --> Top["top_grid_coord: Vector3i"]
    Tile --> Pos["world_position: Vector3"]
    Tile --> Height["height: int"]
    Tile --> Terrain["terrain_type: int"]
    Tile --> Flags["is_empty / passable / placeable"]
    Tile --> Weights["weights: Dictionary"]
    Tile --> TileMetadata["metadata: Dictionary"]
    Tile --> Source["source_voxel: Voxel"]

    Voxel --> Source
```

## Signal Wiring

```mermaid
flowchart LR
    WG["WorldGenerator"]

    WG -->|generation_started(seed_used)| SeedUI["Seed UI / debug log"]
    WG -->|generation_profile_ready(profile)| ProfileUI["GenerationReportLabel"]
    WG -->|world_result_ready(result)| Placement["ObjectPlacer / future placement addon"]
    WG -->|world_result_ready(result)| Battlefield["Battlefield generator request builder"]
    WG -->|world_result_ready(result)| Systems["Roads / loot / biome markers / units"]
    WG -->|world_generated(chunk, voxel_count)| Interaction["Interaction tracker"]
    WG -->|world_generated(chunk, voxel_count)| Legacy["Any old listeners"]

    Placement -->|reads| Surface["result.surface_tiles_by_coord"]
    Placement -->|reads| Weights["tile.weights[result_weight_id]"]
    Placement -->|spawns scenes| SceneTree["Villages / units / props"]
```

## Extension Seams

```mermaid
flowchart TB
    subgraph StableAPI["Stable API Layer"]
        WG["WorldGenerator"]
        Result["VoxelWorldResult"]
        Tile["VoxelSurfaceTile"]
    end

    subgraph ReplaceableResources["Replaceable Resources"]
        Preset["VoxelWorldPreset"]
        Atlas["VoxelAtlasSettings"]
        Terrain["VoxelTerrainStrategy"]
        Weights["VoxelWeightStrategy[]"]
    end

    subgraph CurrentDefaults["Current Defaults"]
        DefaultTerrain["DefaultTerrainStrategy"]
        GridMapper["GridMapper"]
        VoxelGenerator["VoxelGenerator"]
        Settlement["SettlementWeightStrategy"]
    end

    subgraph FutureModules["Future Modules"]
        PlacementAddon["Placement addon"]
        BattlefieldPreset["Battlefield preset"]
        TerrainRules["Terrain rule resources"]
        Palette["Material palette / tile map resource"]
    end

    Preset --> WG
    Atlas --> WG
    Terrain --> WG
    Weights --> WG
    WG --> Result
    Result --> Tile

    Terrain --> DefaultTerrain
    DefaultTerrain --> GridMapper
    DefaultTerrain --> VoxelGenerator
    Weights --> Settlement

    Result --> PlacementAddon
    Result --> BattlefieldPreset
    VoxelGenerator -.later.-> TerrainRules
    VoxelData["VoxelData.tile_map"] -.later.-> Palette
```

## Addon Boundary Target

```mermaid
flowchart LR
    subgraph WorldgenAddon["Voxel worldgen addon"]
        WG["WorldGenerator"]
        Result["VoxelWorldResult / VoxelSurfaceTile"]
        Preset["VoxelWorldPreset"]
        Terrain["Terrain strategies"]
        Weights["Weight strategies"]
        Atlas["VoxelAtlasSettings"]
        MapData["WorldMap + VoxelData autoloads"]
    end

    subgraph PlacementAddon["Future placement addon"]
        Placement["PlacementManager / ObjectPlacer successor"]
        Rules["Placement rule resources"]
        Scenes["Village / unit / prop scenes"]
    end

    subgraph GameProject["Game project"]
        Overworld["Overworld scene"]
        BattleScene["Battlefield scene"]
        UI["Profile / seed UI"]
        GameSystems["Combat, roads, loot, encounters"]
    end

    WorldgenAddon -->|world_result_ready(result)| PlacementAddon
    PlacementAddon -->|spawned nodes + metadata| GameProject
    WorldgenAddon -->|same generator, different preset| BattleScene
    WorldgenAddon --> Overworld
    WG --> UI
    Result --> GameSystems
```

## Reading The Map

- `WorldGenerator` is the orchestration node.
- `WorldMap` is still the runtime map store during generation.
- `VoxelWorldResult` is the public data contract after generation.
- `DefaultTerrainStrategy` keeps the existing `GridMapper` plus `VoxelGenerator` flow behind a resource interface.
- `VoxelAtlasSettings` removes hardcoded atlas dimensions from the generator path.
- `VoxelWeightStrategy` resources write generic score channels into `VoxelSurfaceTile.weights`.
- `ObjectPlacer` is already result-aware, but it should become a separate placement addon later.
