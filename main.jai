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

sprite_end_turn : Sprite;

init_sprites :: () {
    sprite_end_turn = Sprite.{
        tilemap     = tilemap_texture_general,
        active      = true,
        first_frame = 0,
        color       = WHITE,
    };
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Controls
////////////////////////////////////////////////////////////////////////////////////////////////////

move_camera_up    : bool;
move_camera_down  : bool;
move_camera_left  : bool;
move_camera_right : bool;
try_to_go_to_next_phase : bool;
select_entity_on_tile   : bool;
execute_action_on_tile  : bool;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Other
////////////////////////////////////////////////////////////////////////////////////////////////////

global_id_counter      : s32;
global_tile_id_counter : s32;

global_tile_pos_to_tile     : Table(string, *Tile);
global_tile_id_to_tile      : Table(s32, *Tile);
// TODO: maybe...
// global_tile_id_to_entity    : Table(s32, *Entity);
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

TILE_DIRECTION_DELTAS :: [2]float32.[
    .[0.0, -TILE_WORLD_HEIGHT],  // north
    .[0.0, +TILE_WORLD_HEIGHT],  // south
    .[+TILE_WORLD_WIDTH, 0.0],   // east
    .[-TILE_WORLD_WIDTH, 0.0],   // west
    .[+TILE_WORLD_WIDTH * 0.50, -TILE_WORLD_HEIGHT * 0.50], // north east
    .[-TILE_WORLD_WIDTH * 0.50, -TILE_WORLD_HEIGHT * 0.50], // north west
    .[+TILE_WORLD_WIDTH * 0.50, +TILE_WORLD_HEIGHT * 0.50], // south east
    .[-TILE_WORLD_WIDTH * 0.50, +TILE_WORLD_HEIGHT * 0.50], // south west
];

EntityType :: enum {
    PLATE_DIRTY;
    PLATE_WET;
    PLATE_DRY;

    SPONGE;
    FAUCET;
    TOWEL;
}

Entity :: struct {
    id   : s32;
    type : EntityType;
    pos : Vector2;

    bounding_rect  : Rectangle; // Used for collision
    sprite_rect    : Rectangle;

    texture_map_source_pos : Vector2;

    tile_moves_per_turn_max     : s32;
    tile_moves_per_turn_current : s32;
}

TileType :: enum {
    DEFAULT;
    OBSTACLE;
}

TileState :: enum {
    DEFAULT;
    ACTIVE;
}

Tile :: struct {
    id : s32;
    tile_type: TileType;
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
    init_sprites();

    // Initialize font
    {
        font := GetFontDefault();
        font.baseSize = 3;
        GuiSetFont(font);
    }

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
                tile.tile_type = .DEFAULT;
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
        create_entity(.PLATE_DIRTY, 0);
        create_entity(.PLATE_DIRTY, 10);
        create_entity(.PLATE_DIRTY, 20);
        create_entity(.PLATE_WET, 30);
        create_entity(.PLATE_WET, 40);
        create_entity(.PLATE_WET, 50);
        create_entity(.PLATE_DRY, 60);
        create_entity(.PLATE_DRY, 70);
        create_entity(.PLATE_DRY, 80);
        create_entity(.PLATE_DIRTY, 90);
    }

    // Initialize cleaners
    {
        create_entity(.SPONGE, 29);
        create_entity(.FAUCET, 49);
        create_entity(.TOWEL,  69);
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

    tile_id_to_move_count_remaining : Table(s32, s32);
    tile_id_to_move_count_remaining.allocator = temp;
    init(*tile_id_to_move_count_remaining);
    defer deinit(*tile_id_to_move_count_remaining);

    while !WindowShouldClose() {
        reset_temporary_storage();
        table_reset(*tile_id_to_move_count_remaining);

        time := GetTime();
        dt   := GetFrameTime();

        mouse_pos_in_ui    := GetMousePosition();
        mouse_pos_in_world := GetScreenToWorld2D(mouse_pos_in_ui, camera);
        mouse_wheel_move   := GetMouseWheelMove();

        // Populate moveable boundary for active entity
        if game_state.active_entity != null {
            // Check if there is a neighboring tile to the North. If there is, check if it can be inhabited. If so,
            // mark it down as part of the valid tile ids, and also mark down in a table the moves that would
            // be available if moved to that tile.
            check_if_neighbor_can_be_to_moved_to :: (tile: *Tile, dx: float32, dy: float32) -> (is_valid: bool, neighbor: *Tile) {
                neighbor_pos := Vector2.{ tile.pos.x + dx, tile.pos.y + dy };

                // First get a pointer to the thing if it exists
                neighbor_exists, neighbor := table_find(*global_tile_pos_to_tile, vector2_to_string_temp(neighbor_pos));

                if !neighbor_exists { return false, null; }

                // If it does exist, then check that there isn't anything on it
                if neighbor.tile_type == .OBSTACLE { return false, null; }
                
                found_cleaner, _ := find_entity_on_tile_by_pos(neighbor_pos, cleaners);
                if found_cleaner { return false, null; }

                found_dish, _ := find_entity_on_tile_by_pos(neighbor_pos, dishes);
                if found_dish { return false, null; }

                return true, neighbor;
            }

            populate_moveable_tiles :: (tile: *Tile, moves_remaining: s32, tile_id_to_move_count_remaining: *Table) {
                if moves_remaining < 0 return;

                for TILE_DIRECTION_DELTAS {
                    neighbor_valid, neighbor := check_if_neighbor_can_be_to_moved_to(tile, it[0], it[1]);

                    if neighbor_valid {
                        neighbor_already_visited := table_contains(tile_id_to_move_count_remaining, neighbor.id);
                        
                        if !neighbor_already_visited {
                            table_set(tile_id_to_move_count_remaining, neighbor.id, moves_remaining);
                        }
                    }
                }

                moves_remaining -= 1;
                
                for TILE_DIRECTION_DELTAS {
                    found_next_tile, next_tile := check_if_neighbor_can_be_to_moved_to(tile, it[0], it[1]);
                    if !found_next_tile continue;

                    populate_moveable_tiles(next_tile, moves_remaining, tile_id_to_move_count_remaining);
                }
            }

            starting_tile   := get_tile_by_pos(game_state.active_entity.pos);
            moves_remaining := game_state.active_entity.tile_moves_per_turn_current - 1;
            populate_moveable_tiles(starting_tile, moves_remaining, *tile_id_to_move_count_remaining);
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
            try_to_go_to_next_phase  = control_is_pressed(controls.go_to_next_phase);
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

            // Update active entity selection
            {
                // First off, just assume that there is nothing to do here.
                clicked_off_entities := false;
                
                if IsMouseButtonPressed(.MOUSE_BUTTON_LEFT) {
                    // If the user has clicked this frame, then assume they clicked off of an entity.
                    // Then check whether they clicked on any of the entities to prove that they did
                    // click something.
                    clicked_off_entities = true;

                    for cleaner: cleaners {
                        if CheckCollisionPointRec(mouse_pos_in_world, cleaner.sprite_rect) {
                            clicked_off_entities = false;
                            break;
                        }
                    }

                    for dish: dishes {
                        if CheckCollisionPointRec(mouse_pos_in_world, dish.sprite_rect) {
                            clicked_off_entities = false;
                            break;
                        }
                    }

                    if clicked_off_entities {
                        game_state.active_entity = null;
                    }
                }
            }

            // Update target tile
            hovering_over_tile := false;
            {
                for tile: tiles {
                    if CheckCollisionPointPoly(mouse_pos_in_world, *tile.bounding_points[0], 4) {
                        target_tile = tile;
                        hovering_over_tile = true;
                    }
                }
                if !hovering_over_tile { target_tile = null; }
            }

            if try_to_go_to_next_phase {
                go_to_next_phase(*game_state);
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
                    if game_state.active_entity != null {
                        tile := get_tile_by_pos(game_state.active_entity.pos);
                        has_entry, move_count_remaining := table_find(*tile_id_to_move_count_remaining, target_tile.id);
                        table_print(tile_id_to_move_count_remaining);
                        print_vars(tile.*, has_entry, move_count_remaining);

                        // Check if this tile is even within the active entity's range
                        if has_entry {
                            // Change tile before movement back to default
                            tile.tile_state = .DEFAULT;

                            // Then, move the entity to the target tile
                            move_entity_instantaneously(game_state.active_entity, target_tile.id);

                            // Remove the amount of tiles moved from the entity's current count
                            game_state.active_entity.tile_moves_per_turn_current = move_count_remaining;
                        }
                    }
                }
            }

            // Update tiles
            {
                for tile: tiles {
                    tile.tile_state = .DEFAULT;
                }

                if game_state.active_entity != null {
                    tile_that_should_be_active := get_tile_by_pos(game_state.active_entity.pos);
                    tile_that_should_be_active.tile_state = .ACTIVE;
                }
            }

            // Update cleaners
            {
                for cleaner: cleaners {
                    if game_state.active_entity == null || cleaner.id != game_state.active_entity.id {
                        cleaner.sprite_rect = get_default_sprite_rect(get_tile_by_pos(cleaner.pos).id);
                    }
                }
            }

            // Update active entity
            if game_state.active_entity != null {
                game_state.active_entity.sprite_rect.y -= xx sin(time * 3.0) / 10.0;
            }
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
                            tile_is_in_move_bounds := table_contains(*tile_id_to_move_count_remaining, tile.id);
                            if tile_is_in_move_bounds { tint = GREEN; }
                        }

                        DrawTexturePro(
                            tilemap_texture_general,
                            Rectangle.{0, 0, TILEMAP_GENERAL_TILE_WIDTH, TILEMAP_GENERAL_TILE_HEIGHT},
                            tile.sprite_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            tint,
                        );

                        if debug_mode {
                             DrawText(
                                tprint("%\0", tile.id).data,
                                xx (tile.pos.x),
                                xx (tile.pos.y),
                                12,
                                WHITE,
                            );
                        }
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
                for dish: dishes { draw_entity(dish); }

                // Draw cleaners
                for cleaner: cleaners { draw_entity(cleaner); }
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

                    if (did_find_cleaner || did_find_dish) && (game_state.active_entity == null || entity.id != game_state.active_entity.id) {
                        draw_entity_stats(entity, *stat_windows_drawn);
                    }
                }

                // Draw end turn button
                {
                    end_turn_margin :: 20;

                    screen_width   := GetScreenWidth();
                    screen_height  := GetScreenHeight();

                    end_turn_width  := screen_width  * 0.10;
                    end_turn_height := screen_height * 0.10;

                    end_turn_rect  := Rectangle.{
                        screen_width  - end_turn_width  - end_turn_margin,
                        screen_height - end_turn_height - end_turn_margin,
                        end_turn_width,
                        end_turn_height,
                    };

                    try_to_end_turn := GuiButton(end_turn_rect, "End turn");

                    if try_to_end_turn {
                        go_to_next_phase(*game_state);
                    }
                }
                // If there are no more moves left for the cleaners
            }

            // Draw debug
            if debug_mode {
                DrawFPS(10, 10);
            }
        }
    }
}

go_to_next_phase :: (game_state: *GameState) {
    // TODO: I kinda hate this, this should just be derivable from the game state, it shouldn't have to be
    // manually set like this.
    // tile := get_tile_by_pos(game_state.active_entity.pos);
    // tile.tile_state = .DEFAULT;

    if #complete game_state.phase == {
        case .CLEANERS;
            game_state.phase = .DISHES;
            game_state.active_entity = dishes[0];
        case .DISHES;
            game_state.phase = .CLEANERS;
            game_state.active_entity = cleaners[0];
    }
}

PLATE_DIRTY_NAME :: "Dirty plate";
PLATE_WET_NAME   :: "Wet plate";
PLATE_DRY_NAME   :: "Dry plate";
SPONGE_NAME      :: "Sponge";
FAUCET_NAME      :: "Faucet";
TOWEL_NAME       :: "Towel";

entity_type_to_name :: (entity_type: EntityType) -> string {
    if #complete entity_type == {
        case .PLATE_DIRTY; return PLATE_DIRTY_NAME;
        case .PLATE_WET;   return PLATE_WET_NAME;
        case .PLATE_DRY;   return PLATE_DRY_NAME;
        case .SPONGE;      return SPONGE_NAME;
        case .FAUCET;      return FAUCET_NAME;
        case .TOWEL;       return TOWEL_NAME;
    }
}

draw_entity_stats :: (entity: Entity, stat_windows_drawn: *s32) {
    font_size : s32 = 20;
    name_text := tprint("%\0", entity_type_to_name(entity.type)).data;
    moves_text  := tprint("Moves: % / %\0", entity.tile_moves_per_turn_current, entity.tile_moves_per_turn_max).data;

    name_text_length := MeasureText(name_text, font_size);
    moves_text_length  := MeasureText(moves_text,  font_size);

    longest_text_length := max(name_text_length, moves_text_length);

    margin_top := ifx stat_windows_drawn.* > 0 then 20 else 0;
    y_offset   := stat_windows_drawn.* * 100 + margin_top;

    DrawRectangleRounded(Rectangle.{ 20, xx (20 + y_offset), longest_text_length + 20.0, 100 }, 0.1, 0, Color.{ 18, 18, 18, 127 });

    // Draw name
    DrawText(name_text, 30, xx (30 + y_offset), font_size, WHITE);

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

find_tile_by_pos :: (pos: Vector2) -> (tile_exists: bool, tile: *Tile) {
    tile_exists, tile := table_find(*global_tile_pos_to_tile, vector2_to_string_temp(pos));
    return tile_exists, tile;
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
        case .PLATE_DIRTY; #through;
        case .PLATE_WET; #through;
        case .PLATE_DRY; #through;
        case .SPONGE; #through;
        case .FAUCET; #through;
        case .TOWEL;
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
    entity.bounding_rect          = Rectangle.{ pos.x, pos.y, TILEMAP_DISHES_WORLD_WIDTH, TILEMAP_DISHES_WORLD_HEIGHT };
    entity.sprite_rect            = get_default_sprite_rect(on_tile_id);
    // entity.texture_map_source_pos is set conditionally below
    entity.tile_moves_per_turn_max     = 2;
    entity.tile_moves_per_turn_current = 2;

    if #complete entity_type == {
        case .PLATE_DIRTY;
            entity.texture_map_source_pos = Vector2.{ 0, 0 };
            array_add(*dishes, entity);

        case .PLATE_WET;
            entity.texture_map_source_pos = Vector2.{ 1, 0 };
            array_add(*dishes, entity);

        case .PLATE_DRY;
            entity.texture_map_source_pos = Vector2.{ 2, 0 };
            array_add(*dishes, entity);

        case .SPONGE;
            entity.texture_map_source_pos = Vector2.{ 0, 1 };
            array_add(*cleaners, entity);
        // TODO
        case .FAUCET;
            entity.texture_map_source_pos = Vector2.{ 0, 2 };
            array_add(*cleaners, entity);

        case .TOWEL;
            entity.texture_map_source_pos = Vector2.{ 0, 3 };
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

