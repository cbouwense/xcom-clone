#import "Basic";
#import "Hash_Table";
#import "Input";
#import "Math";
#import "Print_Vars";
#import "Random";
#import "Sort";
#import "String";
#import "System";

#import "raylib";

#load "constants.jai";
#load "utils.jai";
#load "raylib-utils.jai";
#load "controls.jai";
#load "sprites.jai";

window_width  := 1600;
window_height := 800;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Constants
////////////////////////////////////////////////////////////////////////////////////////////////////

CAMERA_MOVE_SPEED :: 4;
CAMERA_ZOOM_SPEED :: 0.3;

MAP_ROW_COUNT :: 10;
MAP_COL_COUNT :: 10;

SCALE :: 2;

TRANSPARENT_WHITE :: Color.{ 255, 255, 255, 100 };

////////////////////////////////////////////////////////////////////////////////////////////////////
// Metagame state
////////////////////////////////////////////////////////////////////////////////////////////////////

should_quit_game := false;
paused           := false;
debug_mode       := false;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Textures
////////////////////////////////////////////////////////////////////////////////////////////////////

TILEMAP_GENERAL_MAP_WIDTH    :: 320;
TILEMAP_GENERAL_MAP_HEIGHT   :: 320;
TILEMAP_GENERAL_TILE_WIDTH   :: 32;
TILEMAP_GENERAL_TILE_HEIGHT  :: 32;
TILEMAP_GENERAL_WORLD_WIDTH  :: TILEMAP_GENERAL_TILE_WIDTH * SCALE;
TILEMAP_GENERAL_WORLD_HEIGHT :: TILEMAP_GENERAL_TILE_HEIGHT * SCALE;

TILE_WORLD_WIDTH  :: TILEMAP_GENERAL_WORLD_WIDTH;
TILE_WORLD_HEIGHT :: TILEMAP_GENERAL_WORLD_HEIGHT * 0.50;

TILEMAP_DISHES_MAP_WIDTH    :: 320;
TILEMAP_DISHES_MAP_HEIGHT   :: 320;
TILEMAP_DISHES_TILE_WIDTH   :: 32;
TILEMAP_DISHES_TILE_HEIGHT  :: 32;
TILEMAP_DISHES_WORLD_WIDTH  :: TILEMAP_DISHES_TILE_WIDTH; // Intentionally no scale
TILEMAP_DISHES_WORLD_HEIGHT :: TILEMAP_DISHES_TILE_HEIGHT; // Intentionally no scale

tilemap_texture_general : Texture;
tilemap_texture_dishes  : Texture;

init_textures :: () {
    tilemap_texture_general = LoadTexture("data/tilemap-general.png");
    tilemap_texture_dishes  = LoadTexture("data/tilemap-dishes.png");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Sprites
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// Controls
////////////////////////////////////////////////////////////////////////////////////////////////////

move_camera_up    : bool;
move_camera_down  : bool;
move_camera_left  : bool;
move_camera_right : bool;
go_to_next_phase  : bool;
select_entity_on_tile  : bool;
execute_action_on_tile : bool;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Other
////////////////////////////////////////////////////////////////////////////////////////////////////

global_id_counter      : s32;
global_tile_id_counter : s32;
global_tile_pos_to_tile     : Table(string, *Tile);
global_tile_id_to_tile      : Table(s32, *Tile);
global_tile_id_to_neighbors : Table(s32, *[..] *Tile);

BOUNDING_POINT_INDEX_NORTH :: 0;
BOUNDING_POINT_INDEX_SOUTH :: 2;
BOUNDING_POINT_INDEX_EAST  :: 1;
BOUNDING_POINT_INDEX_WEST  :: 3;

GameStatePhase :: enum {
    CLEANERS;
    DISHES;
}

GameState :: struct {
    phase : GameStatePhase;
    active_entity : *Entity;
}

UnitStatePhase :: enum {
    DECIDING;
    ACTING;
}

UnitState :: struct {
    phase : UnitStatePhase;
}

Direction :: enum {
    NORTH;
    NORTH_EAST;
    NORTH_WEST;
    SOUTH;
    SOUTH_EAST;
    SOUTH_WEST;
    EAST;
    WEST;
    CENTER; // essentially no direction
}

EntityType :: enum {
    DIRTY_PLATE;
    SPONGE;
}

Entity :: struct {
    id   : s32;
    type : EntityType;

    pos : Vector2;
    vel : Vector2;

    is_facing_south_east : bool;

    bounding_rect  : Rectangle; // Used for collision
    sprite_rect    : Rectangle;

    texture_map_source_pos : Vector2;

    health_max     : float32;
    health_current : float32;

    tile_moves_per_turn_max     : s32;
    tile_moves_per_turn_current : s32;
}

TileState :: enum {
    DEFAULT;
    ACTIVE;
}

Tile :: struct {
    id : s32;
    tile_state: TileState;
    pos : Vector2;
    sprite_rect : Rectangle;
    bounding_points : [4] Vector2;
}

ParticleType :: enum {
    SPARK;
    BLOCK_BIT;
}

Particle :: struct {
    #as using entity  : Entity;
    particle_type     : ParticleType;
    time_remaining_ms : s32;
}

data_folder: string;

tiles    : [..] *Tile;
dishes   : [..] *Entity;
cleaners : [..] *Entity;
edges    : [..] Edge; // List of edges between tiles for pathfinding

target_tile : *Tile = null;

main :: () {
    random_seed(123456789);

    InitWindow(1600, 900, "XCOM Clone");
    defer CloseWindow();

    // TODO
    // HideCursor(); // We render a custom one from a texture.
    SetTargetFPS(144);

    base_path := path_strip_filename(get_path_of_running_executable());
    data_folder = join(base_path, "data");

    init_textures();

    // Initialize controls
    controls: Controls;
    {
        controls.move_camera_up[0]    = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_UP             };
        controls.move_camera_up[1]    = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_W              };
        controls.move_camera_down[0]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_DOWN           };
        controls.move_camera_down[1]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_S              };
        controls.move_camera_left[0]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_LEFT           };
        controls.move_camera_left[1]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_A              };
        controls.move_camera_right[0] = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_RIGHT          };
        controls.move_camera_right[1] = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_D              };
        controls.go_to_next_phase[0]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_N              };
        controls.select_entity_on_tile[0]  = Control.{ type = MouseButton, value = cast(s32) MouseButton.MOUSE_BUTTON_LEFT  };
        controls.execute_action_on_tile[0] = Control.{ type = MouseButton, value = cast(s32) MouseButton.MOUSE_BUTTON_RIGHT };
    }

    // Initialize tiles
    {
        x := 0.0;
        for col: 0..MAP_COL_COUNT-1 {
            defer x += TILEMAP_GENERAL_WORLD_WIDTH / 2.0;

            y := 0.0;
            if col % 2 == 1 {
                y += TILEMAP_GENERAL_WORLD_HEIGHT / 4.0;
            }
        
            for row: 0..MAP_ROW_COUNT-1 {
                defer y += TILEMAP_GENERAL_WORLD_HEIGHT / 2.0;

                north := Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 0.50), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.25) };
                south := Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 0.50), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.75) };
                east  := Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 1.00), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.50) };
                west  := Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 0.00), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.50) };

                tile := New(Tile);
                tile.id = read_then_increment(*global_tile_id_counter);
                tile.tile_state = .DEFAULT;
                tile.pos = Vector2.{ north.x, north.y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.25 }; // 25% because the actual sprite height is only half its tile height
                tile.bounding_points = .[north, east, south, west];
                tile.sprite_rect = Rectangle.{ x, y, TILEMAP_GENERAL_WORLD_WIDTH, TILEMAP_GENERAL_WORLD_HEIGHT };

                array_add(*tiles, tile);
                table_add(*global_tile_pos_to_tile, vector2_to_string_permanent(tile.pos), tile);
                table_add(*global_tile_id_to_tile, tile.id, tile);

                neighbor_list := New([..] *Tile);
                table_add(*global_tile_id_to_neighbors, tile.id, neighbor_list);
            }
        }

        // Initialize tile neighbor table
        for tile: tiles {
            neighbor_list_exists, neighbor_list := table_find(*global_tile_id_to_neighbors, tile.id);
            assert(neighbor_list_exists, "Could not find neighbor list for tile id %\n", tile.id);

            add_neighbor_if_it_exists :: (tile: *Tile, neighbor_list: *[..] *Tile, dx: float32, dy: float32) {
                neighbor_pos := Vector2.{ tile.pos.x + dx, tile.pos.y + dy };
                neighbor_exists, neighbor := table_find(*global_tile_pos_to_tile, vector2_to_string_temp(neighbor_pos));
                if neighbor_exists array_add(neighbor_list, neighbor);
            }
 
            add_neighbor_if_it_exists(tile, neighbor_list, 0.0, -TILE_WORLD_HEIGHT); // north
            add_neighbor_if_it_exists(tile, neighbor_list, 0.0, +TILE_WORLD_HEIGHT); // south
            add_neighbor_if_it_exists(tile, neighbor_list, +TILE_WORLD_WIDTH, 0.0); // east
            add_neighbor_if_it_exists(tile, neighbor_list, -TILE_WORLD_WIDTH, 0.0); // west
            add_neighbor_if_it_exists(tile, neighbor_list, +TILE_WORLD_WIDTH * 0.50, -TILE_WORLD_HEIGHT * 0.50); // north east
            add_neighbor_if_it_exists(tile, neighbor_list, -TILE_WORLD_WIDTH * 0.50, -TILE_WORLD_HEIGHT * 0.50); // north west
            add_neighbor_if_it_exists(tile, neighbor_list, +TILE_WORLD_WIDTH * 0.50, +TILE_WORLD_HEIGHT * 0.50); // south east
            add_neighbor_if_it_exists(tile, neighbor_list, -TILE_WORLD_WIDTH * 0.50, +TILE_WORLD_HEIGHT * 0.50); // south west
        }

        // Initialize edge list
        {
            for global_tile_id_to_neighbors {
                tile_id, neighbors := it_index, it;
                for neighbor: neighbors.* {
                    distance := 1.0;

                    // Cardinal neighbors are actually farther away than diagonal neighbors
                    if neighbor.id == tile_id - 1  distance = 1.414; // north
                    if neighbor.id == tile_id + 1  distance = 1.414; // south
                    if neighbor.id == tile_id + 2 * MAP_ROW_COUNT distance = 1.414; // east
                    if neighbor.id == tile_id - 2 * MAP_ROW_COUNT distance = 1.414; // west

                    array_add(*edges, Edge.{ from = tile_id, to = neighbor.id, distance = distance });
                }
            }
        }
    }

    // Initialize dishes
    {
        tile_id_to_spawn_on : s32 = 0;
        while tile_id_to_spawn_on < MAP_ROW_COUNT*MAP_COL_COUNT-1 {
            create_entity(.DIRTY_PLATE, tile_id_to_spawn_on);
            tile_id_to_spawn_on += MAP_COL_COUNT * 2;
        }
    }

    // Initialize cleaners
    {
        tile_id_to_spawn_on : s32 = MAP_ROW_COUNT-1;
        while tile_id_to_spawn_on < MAP_ROW_COUNT*MAP_COL_COUNT-1 {
            create_entity(.SPONGE, tile_id_to_spawn_on);
            tile_id_to_spawn_on += MAP_COL_COUNT * 2;
        }
    }

    // Initialize camera
    camera: Camera2D;
    camera.target   = tiles[50].bounding_points[BOUNDING_POINT_INDEX_EAST];
    camera.offset   = Vector2.{};
    camera.rotation = 0.0;
    camera.zoom     = 2;

    // Initialize game
    game_state := GameState.{
        phase = .CLEANERS,
        active_entity = cleaners[0],
    };

    while !WindowShouldClose() {
        defer reset_temporary_storage();

        time := GetTime();
        dt   := GetFrameTime();

        mouse_pos_in_ui    := GetMousePosition();
        mouse_pos_in_world := GetScreenToWorld2D(mouse_pos_in_ui, camera);
        mouse_wheel_move   := GetMouseWheelMove();

        tile_path : [] s32;
        if target_tile != null {
            tile := get_tile_by_pos(game_state.active_entity.pos);
            tile_path = dijkstra(tile.id, target_tile.id, edges);
        }

        //
        // Input
        //
        {
            // Metagame controls
            if IsKeyPressed(.KEY_P) paused     = !paused;
            if IsKeyPressed(.KEY_G) debug_mode = !debug_mode;

            // Game controls
            move_camera_up    = control_is_down(controls.move_camera_up);
            move_camera_down  = control_is_down(controls.move_camera_down);
            move_camera_left  = control_is_down(controls.move_camera_left);
            move_camera_right = control_is_down(controls.move_camera_right);
            go_to_next_phase  = control_is_pressed(controls.go_to_next_phase);
            select_entity_on_tile  = control_is_pressed(controls.select_entity_on_tile);
            execute_action_on_tile = control_is_pressed(controls.execute_action_on_tile);

            camera.zoom += mouse_wheel_move * CAMERA_ZOOM_SPEED;
        }

        //
        // Update
        //
        if !paused {
            // Update camera
            {
                if move_camera_up    camera.target.y -= CAMERA_MOVE_SPEED;
                if move_camera_down  camera.target.y += CAMERA_MOVE_SPEED;
                if move_camera_left  camera.target.x -= CAMERA_MOVE_SPEED;
                if move_camera_right camera.target.x += CAMERA_MOVE_SPEED;

                camera.offset = Vector2.{ GetScreenWidth() / 2.0, GetScreenHeight() / 2.0 };
            }

            // Update target tile
            hovering_over_tile := false;
            for tile: tiles {
                if CheckCollisionPointPoly(mouse_pos_in_world, *tile.bounding_points[0], 4) {
                    target_tile = tile;
                    hovering_over_tile = true;
                }
            }
            if !hovering_over_tile { target_tile = null; }

            if go_to_next_phase {
                tile := get_tile_by_pos(game_state.active_entity.pos);

                tile.tile_state = .DEFAULT;

                if #complete game_state.phase == {
                    case .CLEANERS;
                        game_state.phase = .DISHES;
                        game_state.active_entity = dishes[0];
                    case .DISHES;
                        game_state.phase = .CLEANERS;
                        game_state.active_entity = cleaners[0];
                }
            }
            else if select_entity_on_tile {
                if hovering_over_tile {
                    if game_state.phase == .CLEANERS {
                        found, new_active_cleaner := find_entity_on_tile_by_pos(target_tile.pos, cleaners);
                        if found {
                            game_state.active_entity = new_active_cleaner;
                        }
                    }
                }
            } 
            else if execute_action_on_tile {
                if hovering_over_tile {
                    // First, check if this tile is even within the active entity's range
                    if tile_path.count <= game_state.active_entity.tile_moves_per_turn_current {
                        // Change tile before movement back to default
                        tile_on_before_movement := get_tile_by_pos(game_state.active_entity.pos);
                        tile_on_before_movement.tile_state = .DEFAULT;

                        // Then, move the entity to the target tile
                        move_entity_instantaneously(game_state.active_entity, target_tile.id);

                        // Remove the amount of tiles moved from the entity's current count
                        game_state.active_entity.tile_moves_per_turn_current -= xx tile_path.count;
                    }
                }
            }

            // Update tiles
            {
                for tile: tiles {
                    tile.tile_state = .DEFAULT;
                }

                tile_that_should_be_active := get_tile_by_pos(game_state.active_entity.pos);
                tile_that_should_be_active.tile_state = .ACTIVE;
            }

            // Update cleaners
            {
                for cleaner: cleaners {
                    if cleaner.id != game_state.active_entity.id {
                        cleaner.sprite_rect = get_default_sprite_rect(get_tile_by_pos(cleaner.pos).id);
                    }
                }
            }

            // Update active entity
            game_state.active_entity.sprite_rect.y -= xx sin(time * 3.0) / 10.0;
        }

        //
        // Draw
        //
        {
            BeginDrawing();
            defer EndDrawing();

            ClearBackground(SKYBLUE);

            // Draw world
            {
                BeginMode2D(camera);
                defer EndMode2D();

                // Draw tiles
                {
                    for tile: tiles {
                        tint: Color;
                        // Determine tile tint
                        {
                            if #complete tile.tile_state == {
                                case .DEFAULT; tint = LIGHTGRAY;
                                case .ACTIVE;  tint = GOLD;
                            }

                            // Limit the tiles drawn to the amount the entity can move
                            tile_path_view := tile_path;
                            tile_path_view.count = min(tile_path.count, game_state.active_entity.tile_moves_per_turn_current);

                            tile_is_in_path, _ := array_find(tile_path_view, tile.id);
                            if tile_is_in_path tint = LIME;
                        }

                        DrawTexturePro(
                            tilemap_texture_general,
                            Rectangle.{0, 0, TILEMAP_GENERAL_TILE_WIDTH, TILEMAP_GENERAL_TILE_HEIGHT},
                            tile.sprite_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            tint,
                        );

                        

                        // if debug_mode {
                        //      DrawText(
                        //         tprint("%\0", tile.id).data,
                        //         xx (tile.pos.x),
                        //         xx (tile.pos.y),
                        //         12,
                        //         WHITE,
                        //     );
                        // }
                    }

                    // Redraw hovered tile so it is drawn above all other tiles.
                    if target_tile != null {
                        DrawTexturePro(
                            tilemap_texture_general,
                            Rectangle.{0, 0, TILEMAP_GENERAL_TILE_WIDTH, TILEMAP_GENERAL_TILE_HEIGHT},
                            target_tile.sprite_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            GRAY,
                        );
                    }
                }

                // Draw dishes
                for dish: dishes draw_entity(dish);

                // Draw cleaners
                for cleaner: cleaners draw_entity(cleaner);
            }

            // Draw UI
            {
                stat_windows_drawn : s32 = 0;

                // Draw stats for active_entity
                if game_state.active_entity != null {
                    draw_entity_stats(game_state.active_entity, *stat_windows_drawn);
                }

                if target_tile != null {
                    did_find_cleaner, cleaner := find_entity_on_tile_by_pos(target_tile.pos, cleaners);
                    did_find_dish, dish := find_entity_on_tile_by_pos(target_tile.pos, dishes);

                    entity := ifx did_find_cleaner then cleaner else ifx did_find_dish then dish else null;

                    if (did_find_cleaner || did_find_dish) && entity.id != game_state.active_entity.id {
                        draw_entity_stats(entity, *stat_windows_drawn);
                    }
                }
            }

            // Draw debug
            if debug_mode {
                DrawFPS(10, 10);
            }
        }
    }
}

draw_entity_stats :: (entity: Entity, stat_windows_drawn: *s32) {
    font_size : s32 = 20;
    health_text := tprint("Health: % / %\0", entity.health_current, entity.health_max).data;
    moves_text  := tprint("Moves: % / %\0", entity.tile_moves_per_turn_current, entity.tile_moves_per_turn_max).data;

    health_text_length := MeasureText(health_text, font_size);
    moves_text_length  := MeasureText(moves_text,  font_size);

    longest_text_length := max(health_text_length, moves_text_length);

    margin_top := ifx stat_windows_drawn.* > 0 then 20 else 0;
    y_offset   := stat_windows_drawn.* * 100 + margin_top;

    DrawRectangleRounded(Rectangle.{ 20, xx (20 + y_offset), longest_text_length + 20.0, 100 }, 0.1, 0, Color.{ 18, 18, 18, 127 });

    // Draw health
    DrawText(health_text, 30, xx (30 + y_offset), font_size, WHITE);

    // Draw moves
    DrawText(moves_text, 30, xx (50 + y_offset), font_size, WHITE);

    stat_windows_drawn.* += 1;
}

is_entity_on_tile :: (entity: Entity, tile: Tile) -> bool {
    return entity.pos.x == tile.pos.x && entity.pos.y == tile.pos.y;
}

get_tile_pos_by_id :: (id: s32) -> Vector2 {
    return tiles[id].pos; // TODO: this will probably not work if/when tiles can be changed
}

get_tile_by_pos :: (pos: Vector2) -> *Tile {
    tile_exists, tile := table_find(*global_tile_pos_to_tile, vector2_to_string_temp(pos));
    assert(tile_exists);
    return tile;
}

find_entity_on_tile_by_pos :: (tile_pos: Vector2, entities: []*Entity) -> (found: bool, entity: *Entity) {
    for entities {
        if it.pos.x == tile_pos.x && it.pos.y == tile_pos.y {
            return true, it;
        }
    }

    return false, null;
}

get_entity_on_tile_by_tile_id :: (tile_id: s32, entities: []*Entity) -> (found: bool, entity: *Entity) {
    tile_pos := get_tile_pos_by_id(tile_id);

    found, entity := find_entity_on_tile_by_pos(tile_pos, entities);
    return found, entity;
}

get_colliding_by_rect :: (subject_rect: Rectangle, collidables: [] $T/interface *Entity) -> *Entity {
    for collidables {
        if CheckCollisionRecs(it.bounding_rect, subject_rect) {
            return it;
        }
    }

    return null;
}

get_colliding_entity_by_vec2 :: (subject_vec2: Vector2, collidables: [] *$T/interface Entity) -> result: *T {
    for collidables {
        if CheckCollisionPointRec(subject_vec2, it.bounding_rect) {
            return it;
        }
    }

    return null;
}

array_unordered_remove_entity_by_id :: inline (array: *[] $Entity, item: Entity, $stop_after_first := false) -> s64 {
    removed := 0;
    for array.*  if it.id == item.id {
        removed += 1;
        remove it;

        #if stop_after_first  break;   // Early-out optimization.
    }

    return removed;
}

get_draw_info_for_entity :: (entity: Entity) -> texture: Texture, source: Rectangle {
    if #complete entity.type == {
        // TODO: DRY up?
        case .DIRTY_PLATE; #through;
        case .SPONGE;
            map_texture := tilemap_texture_dishes;

            map_source := Rectangle.{
                entity.texture_map_source_pos.x * TILEMAP_DISHES_TILE_WIDTH,
                entity.texture_map_source_pos.y * TILEMAP_DISHES_TILE_HEIGHT,
                TILEMAP_DISHES_TILE_WIDTH,
                TILEMAP_DISHES_TILE_HEIGHT,
            };

            return map_texture, map_source;
    }
}

draw_entity :: (entity: Entity) {
    texture, source_rect := get_draw_info_for_entity(entity);

    DrawTexturePro(
        texture,
        source_rect,
        entity.sprite_rect,
        Vector2.{ 0, 0 },
        0.0,
        WHITE,
    );

    if debug_mode {
        DrawRectangleLinesEx(entity.sprite_rect, 1.0, LIME);
    }
}

create_entity :: (entity_type: EntityType, on_tile_id: s32) -> *Entity {
    pos := get_tile_pos_by_id(on_tile_id);

    entity := New(Entity);
    entity.id                     = read_then_increment(*global_id_counter);
    entity.type                   = entity_type;
    entity.pos                    = pos;
    entity.vel                    = Vector2.{};
    entity.is_facing_south_east   = true; // TODO: ?
    entity.bounding_rect          = Rectangle.{ pos.x, pos.y, TILEMAP_DISHES_WORLD_WIDTH, TILEMAP_DISHES_WORLD_HEIGHT };
    entity.sprite_rect            = get_default_sprite_rect(on_tile_id);
    // entity.texture_map_source_pos is set conditionally below
    entity.health_max             = 100.0;
    entity.health_current         = 100.0;
    entity.tile_moves_per_turn_max     = 5;
    entity.tile_moves_per_turn_current = 5;

    if #complete entity_type == {
        case .DIRTY_PLATE;
            entity.texture_map_source_pos = Vector2.{ 0, 0 };
            array_add(*dishes, entity);

        case .SPONGE;
            entity.texture_map_source_pos = Vector2.{ 0, 1 };
            array_add(*cleaners, entity);
    }

    return entity;
}

move_entity_instantaneously :: (entity: *Entity, tile_id: s32) {
    pos := get_tile_pos_by_id(tile_id);

    entity.pos           = pos;
    entity.bounding_rect = Rectangle.{ pos.x, pos.y, TILEMAP_DISHES_WORLD_WIDTH, TILEMAP_DISHES_WORLD_HEIGHT };
    entity.sprite_rect   = get_default_sprite_rect(tile_id);
}

get_default_sprite_rect :: (on_tile_id: s32) -> Rectangle {
    pos := get_tile_pos_by_id(on_tile_id);
    return Rectangle.{
        pos.x - TILEMAP_DISHES_WORLD_WIDTH  * 0.50,
        pos.y - TILEMAP_DISHES_WORLD_HEIGHT * 0.75,
        TILEMAP_DISHES_WORLD_WIDTH,
        TILEMAP_DISHES_WORLD_HEIGHT,
    };
}

