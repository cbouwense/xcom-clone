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

TILEMAP_DISHES_MAP_WIDTH    :: 320;
TILEMAP_DISHES_MAP_HEIGHT   :: 320;
TILEMAP_DISHES_TILE_WIDTH   :: 32;
TILEMAP_DISHES_TILE_HEIGHT  :: 32;
TILEMAP_DISHES_WORLD_WIDTH  :: TILEMAP_GENERAL_TILE_WIDTH * SCALE;
TILEMAP_DISHES_WORLD_HEIGHT :: TILEMAP_GENERAL_TILE_HEIGHT * SCALE;

tilemap_texture_general : Texture;
tilemap_texture_dishes  : Texture;

init_textures :: () {
    tilemap_texture_general = LoadTexture("data/tilemap-general.png");
    tilemap_texture_dishes  = LoadTexture("data/tilemap-dishes.png");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Sprites
////////////////////////////////////////////////////////////////////////////////////////////////////

// SPRITE_DISH_FIRST_FRAME :: 0;

// active_sprites_dishes : [..] *Sprite; // TODO: unsure

// sprite_dish    : Sprite;

// init_sprites :: () {
//     sprite_dish = Sprite.{
//         tilemap     = tilemap_texture_dishes,
//         first_frame = SPRITE_DISH_FIRST_FRAME,
//         color       = WHITE,
//     };

//     array_add(*active_sprites_dishes, *sprite_dish);
// }

////////////////////////////////////////////////////////////////////////////////////////////////////
// Controls
////////////////////////////////////////////////////////////////////////////////////////////////////

move_camera_up    : bool;
move_camera_down  : bool;
move_camera_left  : bool;
move_camera_right : bool;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Other
////////////////////////////////////////////////////////////////////////////////////////////////////

global_id_counter : s32;

BOUNDING_POINT_INDEX_NORTH :: 0;
BOUNDING_POINT_INDEX_SOUTH :: 2;
BOUNDING_POINT_INDEX_EAST  :: 1;
BOUNDING_POINT_INDEX_WEST  :: 3;

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

Entity :: struct {
    id   : s32;
    type : Type;

    pos : Vector2;
    vel : Vector2;

    is_facing_south_east : bool;

    bounding_rect  : Rectangle; // Used for collision
    sprite_rect    : Rectangle;

    texture_map_source_pos : Vector2;

    health_max     : float32;
    health_curr    : float32;
}

Tile :: struct {
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

tiles  : [..] *Tile;
dishes : [..] *Entity;

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
    controls.move_camera_up[0]    = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_UP    };
    controls.move_camera_up[1]    = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_W     };
    controls.move_camera_down[0]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_DOWN  };
    controls.move_camera_down[1]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_S     };
    controls.move_camera_left[0]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_LEFT  };
    controls.move_camera_left[1]  = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_A     };
    controls.move_camera_right[0] = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_RIGHT };
    controls.move_camera_right[1] = Control.{ type = KeyboardKey, value = cast(s32) KeyboardKey.KEY_D     };

    active_tiles : [..] *Tile;
    active_tiles.allocator = temp; // TODO: this is wrong

    // Initialize tiles
    {
        x := 0.0;
        for col: 0..10 {
            defer x += TILEMAP_GENERAL_WORLD_WIDTH / 2.0;

            y := 0.0;
            if col % 2 == 1 {
                y += TILEMAP_GENERAL_WORLD_HEIGHT / 4.0;
            }
        
            for row: 0..10 {
                defer y += TILEMAP_GENERAL_WORLD_HEIGHT / 2.0;

                tile := New(Tile);
                tile.bounding_points = .[
                    Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 0.50), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.25) }, // north
                    Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 1.00), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.50) }, // east
                    Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 0.50), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.75) }, // south
                    Vector2.{ xx (x + TILEMAP_GENERAL_WORLD_WIDTH * 0.00), xx (y + TILEMAP_GENERAL_WORLD_HEIGHT * 0.50) }, // west
                ];
                tile.sprite_rect = Rectangle.{ x, y, TILEMAP_GENERAL_WORLD_WIDTH, TILEMAP_GENERAL_WORLD_HEIGHT };

                array_add(*tiles, tile);
            }
        }
    }

    // Initialize dishes
    {
        dish := New(Entity);
        dish.id = read_then_increment(*global_id_counter);
        // dish.type : Type;
        dish.pos                    = Vector2.{ 100, 100 };
        dish.vel                    = Vector2.{};
        dish.is_facing_south_east   = true; // TODO: ?
        dish.bounding_rect          = Rectangle.{ 0, 0, TILEMAP_DISHES_WORLD_WIDTH, TILEMAP_DISHES_WORLD_HEIGHT };
        dish.sprite_rect            = Rectangle.{ 0, 0, TILEMAP_DISHES_WORLD_WIDTH, TILEMAP_DISHES_WORLD_HEIGHT };
        dish.texture_map_source_pos = Vector2.{ 0, 0 };
        dish.health_max             = 100.0;
        dish.health_curr            = 100.0;

        array_add(*dishes, dish);
    }

    // Initialize camera
    camera: Camera2D;
    camera.target   = tiles[50].bounding_points[BOUNDING_POINT_INDEX_EAST];
    camera.offset   = Vector2.{};
    camera.rotation = 0.0;
    camera.zoom     = 2;

    derive_active_entities(*active_tiles, camera);

    while !WindowShouldClose() {
        defer reset_temporary_storage();

        time := GetTime();
        dt   := GetFrameTime();

        mouse_pos_in_ui    := GetMousePosition();
        mouse_pos_in_world := GetScreenToWorld2D(mouse_pos_in_ui, camera);
        mouse_wheel_move   := GetMouseWheelMove();

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

            camera.zoom += mouse_wheel_move * CAMERA_ZOOM_SPEED;
        }

        //
        // Update
        //
        if !paused {
            derive_active_entities(*active_tiles, camera);

            // Update camera
            {
                if move_camera_up    camera.target.y -= CAMERA_MOVE_SPEED;
                if move_camera_down  camera.target.y += CAMERA_MOVE_SPEED;
                if move_camera_left  camera.target.x -= CAMERA_MOVE_SPEED;
                if move_camera_right camera.target.x += CAMERA_MOVE_SPEED;

                camera.offset = Vector2.{ GetScreenWidth() / 2.0, GetScreenHeight() / 2.0 };
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
                    hovered_tile : *Tile;
                    for tile: active_tiles {
                        // first_point : *Vector2 = 
                        if CheckCollisionPointPoly(mouse_pos_in_world, *tile.bounding_points[0], 4) {
                            hovered_tile = tile;
                        }

                        DrawTexturePro(
                            tilemap_texture_general,
                            Rectangle.{0, 0, TILEMAP_GENERAL_TILE_WIDTH, TILEMAP_GENERAL_TILE_HEIGHT},
                            tile.sprite_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            WHITE,
                        );
                    }

                    // Redraw hovered tile so it is drawn above all other tiles.
                    if hovered_tile != null {
                        DrawTexturePro(
                            tilemap_texture_general,
                            Rectangle.{0, 0, TILEMAP_GENERAL_TILE_WIDTH, TILEMAP_GENERAL_TILE_HEIGHT},
                            hovered_tile.sprite_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            GRAY,
                        );
                    }
                }

                // Draw dishes
                {
                    for dish: dishes {
                        DrawTexturePro(
                            tilemap_texture_dishes,
                            Rectangle.{ 0, 0, TILEMAP_DISHES_WORLD_WIDTH, TILEMAP_DISHES_WORLD_HEIGHT },
                            dish.sprite_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            WHITE,
                        );
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

/**
 * derive_active_entities determines which entities should be processed each frame based on if they fall within the
 * viewport or not. If they don't they are neither updated nor drawn to save frames. Every time there is a new entity
 * type, it should probably be added to this function. It clears the arrays of active entities passed into it and adds
 * in the entities that should be processed that frame.
 * 
 * This function has to be called every frame, so it has to be reasonably performant. There is a tradeoff between
 * accurate culling and not spending too much time processing what should be culled.
 */
derive_active_entities :: (active_tiles: *[..] *Tile, camera: Camera2D) {
    window_start := GetScreenToWorld2D(Vector2.{ 0, 0 }, camera);
    window_end   := GetScreenToWorld2D(Vector2.{ cast(float) GetScreenWidth(), cast(float) GetScreenHeight()}, camera);

    array_reset(active_tiles);

    {
        for tile: tiles {
            if tile.bounding_points[0].y > window_end.y   continue; // north
            if tile.bounding_points[1].y < window_start.y continue; // south
            if tile.bounding_points[2].x < window_start.x continue; // east
            if tile.bounding_points[3].x > window_end.x   continue; // west

            array_add(active_tiles, tile);
        }
    }
}
