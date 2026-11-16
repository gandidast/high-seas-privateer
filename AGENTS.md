# High Seas Pixel Privateer — Agent Architecture Index

Godot 4.7.2 (`gl_compatibility`, pure GDScript, zero external binary assets).
Hybrid rendering: `640x360` pixel-art world inside `SubViewport` (`stretch_shrink=2`, `TEXTURE_FILTER_NEAREST`) + crisp `1280x720` HD `CanvasLayer` UI.

## Commands

- **Godot Console Binary (Windows):** `"C:\games187+\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"`
- **Full Automated Test Suite (113 assertions):**
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/verify_game.gd`
- **Syntax Check (`--check-only`):**
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . --check-only --script res://main.gd` (pass multiple `--script` flags)
- **Headless Dedicated Server (30 Hz sim, 15 Hz WebSocket delta snapshots):**
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --server --port=8080` (optional `--seed=1337420`)

## Folder & Module Map

- **`main.gd` (`Main`)** — Scene entrypoint (`res://main.tscn`). Boots headless server (`--server`) or client/solo `SubViewport` + `UILayer`. Owns Solo/Server physics loop; delegates client snapshot reconciliation to `ClientSyncController` and start overlay to `StartMenuUI`.
- **`shared/contracts.gd` (`Contracts`, Autoload `EventBus`)** — Single source of truth for enums (`SlotType`, `ItemRarity`, `ItemAffix`, `ItemCategory`, `ShipClass`, `WeatherState`, `ShipFaction`, `SailState`, `AIState`, `QuestType`), data classes (`ShipStats`, `LootDropData`, `QuestData`, `IslandData`), deterministic `get_water_depth(world_pos, seed)` & 6-island generator, and all `EventBus` signals.
- **`sim/` (Headless-safe authoritative simulation)**
  - `world_map.gd` (`WorldMap`): Island/harbor queries, wind & weather state machine (`CLEAR`/`FOG`/`STORM`), lightning triggers.
  - `ship_physics.gd` (`ShipPhysics`): Buoyancy/sail thrust, wind leeway, island coast scraping, `apply_stats()`, `to_sync_dict()`.
  - `dredge_grid.gd` (`DredgeGrid`): Spatial inventory grid (tier-scaled up to 8x6), rotation, edge-slot cannon rule, powder-barrel adjacency synergy, stat compiler.
  - `item_database.gd` (`ItemDatabase`): 22 procedural items, rarity/affix rolls, harbor shop stock & quests.
  - `combat_system.gd` (`CombatSystem`) + `fort_defense_system.gd` (`FortDefenseSystem`): Broadside lead ballistics, Greek Fire/Harpoon, ramming, island fort bastions (`sync_revision` tracked).
  - `ai_director.gd` (`AIDirector`) + `sea_monster_director.gd` (`SeaMonsterDirector`): Merchant/pirate/Navy FSM, Royal Navy wanted stars (`0..3`), Giant Kraken boss FSM (`sync_revision` tracked).
  - `loot_system.gd` (`LootSystem`): Flotsam/salvage drops with `sync_revision` & incremental `apply_sync_array()` diffing.
- **`net/` (Authoritative WebSocket Multiplayer)**
  - `network_manager.gd` (`NetworkManager`): `Mode.{SOLO,SERVER,CLIENT}`. Sets `Engine.physics_ticks_per_second = 30` on server (`60` on client/solo). Sends `15 Hz` (`SYNC_INTERVAL=0.066`) delta snapshots + `3.0s` safety keyframes (`KEYFRAME_INTERVAL`), 1-key `{ship_id}` idle ship heartbeats, quantized floats, revision-gated `drops`/`forts`/`sea_monster`/`wanted_level`/wind/weather, and RPCs (`rpc_send_input`, `rpc_request_fire`, `rpc_sync_player_stats`, `rpc_upgrade_ship_class`, `rpc_repair_ship`).
  - `client_sync_controller.gd` (`ClientSyncController`): Coalesces same-frame snapshots (max 1 apply/frame), filters unchanged `EventBus` signals, reconciles local player (`add_visual_offset`), extrapolates moving remote ships at 60 Hz.
  - `local_host_runner.gd` (`LocalHostRunner`): TCP port probe + local headless server autostart (`OS.create_process`) & retry flow.
  - `server_config.gd` (`ServerConfig`): Default/HTML5 origin WebSocket URL resolution (`wss://`).
- **`visual/` (2D Pixel-Art Rendering, never loaded on `--server`)**
  - `ocean_renderer.gd` (`OceanRenderer`) + `ocean_shader.gdshader`: Bakes `1024x1024` world depth SDF `ImageTexture` once per seed (`_get_or_bake_depth_texture`), O(1) shader lookup, dirty-tracked uniforms, culled harbor piers/buoys/fort shadows.
  - `ship_stack_renderer.gd` (`ShipStackRenderer`): 24-layer 2D sprite-stacking with camera viewport culling (+180px margin), pooled wake `PackedVector2Array`, visual offset smoothing.
  - `fx_manager.gd` (`FxManager`) + `world_entities_renderer.gd` (`WorldEntitiesRenderer`): Camera-culled projectiles, particles (`MAX_PARTICLES=360`), loot crates, broadside aim cone, forts & Kraken rendering.
  - `pixel_camera.gd` (`PixelCamera`): Smooth follow camera, screen shake, `get_view_world_rect()`.
  - `procedural_ship_baker.gd` (`ProceduralShipBaker` facade) + `visual/baker/*`: Cached pixel-art generators (`pixel_draw_utils.gd`, `ship_hull_baker.gd`, `item_icon_baker.gd`, `item_weapon_painters.gd`, `item_cargo_painters.gd`, `entity_sprite_baker.gd`).
- **`ui/` (HD `1280x720` Overlay)**
  - `ui_theme_helper.gd` (`UIThemeHelper`): Shared palette, cached fallback `Font`, `StyleBoxFlat`/widget factories, chamfered polygon helpers.
  - `hud_overlay.gd` (`HudOverlay`) + `hud_labels_view.gd` (`HudLabelsView`) + `minimap_renderer.gd` (`MinimapRenderer`): Dirty-tracked HUD, cached `Label`s, static minimap baked once per seed.
  - `cargo_grid_ui.gd` (`CargoGridUI`) + `cargo_slot_renderer.gd` (`CargoSlotRenderer`): Drag/drop/rotate Dredge inventory UI (`TEXTURE_FILTER_NEAREST` icons).
  - `harbor_ui.gd` (`HarborUI`) + `harbor_shop_panel.gd` (`HarborShopPanel`) + `harbor_quest_panel.gd` (`HarborQuestPanel`): Dock shop, repairs (`send_ship_repair`), ship upgrades, quests.
  - `start_menu_ui.gd` (`StartMenuUI`): Solo/One-World start screen, saved captain/URL config, tunnel status polling.
- **`tests/verify_game.gd`**: Deterministic world, `DredgeGrid`, Combat/AI/Loot/Quest, `ProceduralShipBaker`, `OceanRenderer`, UI, and live headless WebSocket server checks.
- **`deploy/`**: Oracle Cloud setup (`oracle_cloud_setup.sh`, `Caddyfile`), `start_live_multiplayer.ps1`, `export_presets.cfg`.

## Key Signal & Network Contracts

- **EventBus (`Contracts.bus()`)**:
  - World: `world_initialized`, `wind_changed`, `weather_changed`, `lightning_flash`
  - Ships: `ship_spawned`, `ship_despawned`, `ship_state_updated`, `ship_stats_compiled`, `ship_grid_updated`, `ship_coast_scraped`, `ship_class_upgraded`, `ship_repaired`
  - Combat/Entities: `broadside_fired`, `cannonball_spawned`, `cannonball_impact`, `ship_damaged`, `ship_sunk`, `wanted_level_changed`, `fort_spawned`, `fort_damaged`, `fort_destroyed`, `sea_monster_spawned`, `sea_monster_updated`, `sea_monster_defeated`
  - Harbor/UI/Net: `loot_spawned`, `loot_collected`, `harbor_entered`, `harbor_exited`, `harbor_ui_requested`, `cargo_grid_toggled`, `gold_changed`, `quest_accepted`, `quest_completed`, `quest_list_updated`, `network_mode_changed`, `notification_posted`
- **Critical Invariants**:
  - Never run `world_map.step_wind()` / `step_weather()` on `Mode.CLIENT` (server authoritative via snapshots).
  - Keep `ProceduralShipBaker` public static signatures and `Contracts.get_water_depth()` deterministic math unchanged.
  - Re-run `tests/verify_game.gd` and `--check-only` after any edit.
