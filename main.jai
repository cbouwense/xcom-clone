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

#load "controls.jai";
#load "sprites.jai";

SQRT_2 : float32 : 1.4142135;

window_width  := 1600;
window_height := 800;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Metagame state
////////////////////////////////////////////////////////////////////////////////////////////////////
should_quit_game := false;
paused           := false;
debug_mode       := false;
render_walls     := true;
free_cam_pos     := Vector2.{ 0, 0 };

// Controls


// Textures and texture maps
player_head_map           : Texture;

player_sprite_head_idle                 : Sprite;
player_animation_head_running           : AnimatedSprite;

player_sprites    : [..] *Sprite;
player_animations : [..] *AnimatedSprite;

TRANSPARENT_WHITE :: Color.{ 255, 255, 255, 100 };

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

ItemType :: enum {
    UNSPECIFIED :: -1;
}

ItemStack :: struct {
    item_type      : ItemType;
    stack_capacity : s32; // -1 means this isn't really a stack, but just an item. e.g. a pickaxe
    stack_count    : s32;
}

EMPTY_ITEM_STACK :: ItemStack.{ -1, -1, 0 };

Inventory :: struct {
    item_stacks         : [INVENTORY_SLOTS] ItemStack;
    selected_item_stack : s32;
    is_inventory_open   : bool;
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

    inventory : Inventory;
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

vector2_equal :: (v1: Vector2, v2: Vector2) -> bool {
    return v1.x == v2.x && v1.y == v2.y;
}

vector2_to_string_permanent :: (v: Vector2) -> string {
    key := sprint("%,%", v.x, v.y);
    return key;
}

vector2_to_string_temp :: (v: Vector2) -> string {
    key := tprint("%,%", v.x, v.y);
    return key;
}

data_folder: string;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Globals
////////////////////////////////////////////////////////////////////////////////////////////////////

main :: () {

#pragma region initialization
    random_seed(123456789);

    InitWindow(1600, 900, "XCOM Clone");
    defer CloseWindow();

    // TODO
    // HideCursor(); // We render a custom one from a texture.
    SetTargetFPS(144);

    base_path := path_strip_filename(get_path_of_running_executable());
    data_folder = join(base_path, "data");

    init_textures();

    player := respawn_player();

    // Initialize camera
    camera: Camera2D;
    camera.target   = player.pos;
    camera.offset   = Vector2.{ GetScreenWidth()/2.0 + player.bounding_rect.width/2.0, GetScreenHeight()/2.0 };
    camera.rotation = 0.0;
    camera.zoom     = 1;

    // Initialize controls
    controls: Controls;

    derive_active_entities(*active_blocks, *active_walls, *collidable_blocks, camera);

#pragma endregion // initialization

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
            // Meta controls
            if IsKeyPressed(.KEY_P) paused          = !paused;
            if IsKeyPressed(.KEY_G) debug_mode      = !debug_mode;
            if IsKeyPressed(.KEY_L) shadows_enabled = !shadows_enabled;
            if IsKeyPressed(.KEY_N) render_blocks   = !render_blocks;
            if IsKeyPressed(.KEY_M) render_walls    = !render_walls;
            if IsKeyPressed(.KEY_R) player          = respawn_player();

            move_player_left   = control_down(controls.move_player_left);
            move_player_right  = control_down(controls.move_player_right);
            try_to_jump        = control_pressed(controls.jump);
            try_to_attack      = control_down(controls.attack);
            try_to_interact    = control_down(controls.interact); // place blocks, open doors, etc.
            open_inventory     = control_pressed(controls.open_inventory);
            drag_cam           = control_down(controls.drag_cam);
            scroll_as_zoom     = control_down(controls.scroll_as_zoom); // modifier to hold down to use scroll wheel as zoom.
            hotbar_swap_next   = mouse_wheel_move < 0 && !scroll_as_zoom; // scroll down to shift one up (think shifting right on minecraft hotbar).
            hotbar_swap_prev   = mouse_wheel_move > 0 && !scroll_as_zoom; // scroll up to shift one down (think shifting left on minecraft hotbar).

            hotbar_slot_1     := control_pressed(controls.hotbar_slot_1);
            hotbar_slot_2     := control_pressed(controls.hotbar_slot_2);
            hotbar_slot_3     := control_pressed(controls.hotbar_slot_3);
            hotbar_slot_4     := control_pressed(controls.hotbar_slot_4);
            hotbar_slot_5     := control_pressed(controls.hotbar_slot_5);
            hotbar_slot_6     := control_pressed(controls.hotbar_slot_6);
            hotbar_slot_7     := control_pressed(controls.hotbar_slot_7);
            hotbar_slot_8     := control_pressed(controls.hotbar_slot_8);
            hotbar_slot_9     := control_pressed(controls.hotbar_slot_9);
            hotbar_slot_10    := control_pressed(controls.hotbar_slot_10);
        
            if hotbar_slot_1  { player.inventory.selected_item_stack = 0; }
            if hotbar_slot_2  { player.inventory.selected_item_stack = 1; }
            if hotbar_slot_3  { player.inventory.selected_item_stack = 2; }
            if hotbar_slot_4  { player.inventory.selected_item_stack = 3; }
            if hotbar_slot_5  { player.inventory.selected_item_stack = 4; }
            if hotbar_slot_6  { player.inventory.selected_item_stack = 5; }
            if hotbar_slot_7  { player.inventory.selected_item_stack = 6; }
            if hotbar_slot_8  { player.inventory.selected_item_stack = 7; }
            if hotbar_slot_9  { player.inventory.selected_item_stack = 8; }
            if hotbar_slot_10 { player.inventory.selected_item_stack = 9; }
        }

        //
        // Update
        //
        if !paused {
            // Update camera
            {
                if drag_cam {
                    free_cam_pos = Vector2Add(free_cam_pos, Vector2Scale(GetMouseDelta(), -1.0 * DEBUG_CAM_SPEED));
                }

                if scroll_as_zoom {
                    camera.zoom += mouse_wheel_move * 0.2;
                }

                if camera.zoom > 3.0 camera.zoom = 3.0;
                else if debug_mode && camera.zoom < 0.02 camera.zoom = 0.02;
                else if !debug_mode && camera.zoom < 0.4 camera.zoom = 0.4;

                if debug_mode {
                    camera.offset = Vector2.{ GetScreenWidth() / 2.0, GetScreenHeight() / 2.0 };
                    camera.target = free_cam_pos;
                } else {
                    update_camera_center(*camera, *player, GetScreenWidth(), GetScreenHeight());
                    free_cam_pos = player.pos;
                }
            }

            derive_active_entities(*active_blocks, *active_walls, *collidable_blocks, camera);

            should_update_player := true;
            if debug_mode {
                window_start := GetScreenToWorld2D(Vector2.{ 0, 0 }, camera);
                window_end   := GetScreenToWorld2D(Vector2.{ cast(float) GetScreenWidth(), cast(float) GetScreenHeight()}, camera);

                if      player.pos.x + PLAYER_WORLD_BOUNDING_WIDTH  < window_start.x should_update_player = false;
                else if player.pos.x - PLAYER_WORLD_BOUNDING_WIDTH  > window_end.x   should_update_player = false;
                else if player.pos.y - PLAYER_WORLD_BOUNDING_HEIGHT > window_end.y   should_update_player = false;
                else if player.pos.y + PLAYER_WORLD_BOUNDING_HEIGHT < window_start.y should_update_player = false;
            }
           
            // Update player
            if should_update_player {
                // Movement
                {
                    player.vel.x = 0;

                    if move_player_left {
                        player.vel.x -= PLAYER_SPEED_MOVE;
                        player.is_facing_left = true;
                    }

                    if move_player_right {
                        player.vel.x += PLAYER_SPEED_MOVE;
                        player.is_facing_left = false;
                    }

                    if try_to_jump && can_jump(player) {
                        player.vel.y = -PLAYER_SPEED_JUMP;
                        player.jumps_remaining -= 1;
                    }

                    if player.vel.y < PLAYER_SPEED_MAX player.vel.y += ACCEL_DUE_TO_GRAVITY * dt * 0.5;

                    collided_horizontally := try_to_move(*player, player.vel.x * dt, collidable_blocks, true)  != null;
                    collided_vertically   := try_to_move(*player, player.vel.y * dt, collidable_blocks, false) != null;

                    if collided_horizontally player.vel.x = 0;
                    if collided_vertically {
                        player.vel.y = 0;
                    } else {
                        if player.vel.y < PLAYER_SPEED_MAX player.vel.y += ACCEL_DUE_TO_GRAVITY * dt * 0.5;
                    }

                    // Respawn player if they fall through the world
                    if player.pos.y > 500000 {
                        player = respawn_player();
                    }

                    // Update position-dependent fields on player entity
                    player.bounding_rect.x = player.pos.x - PLAYER_WORLD_BOUNDING_WIDTH     / 2.0;
                    player.bounding_rect.y = player.pos.y - PLAYER_WORLD_BOUNDING_HEIGHT    / 2.0 + 10;
                    player.sprite_rect.x   = player.pos.x - PLAYER_WORLD_HEAD_SPRITE_WIDTH  / 2.0;
                    player.sprite_rect.y   = player.pos.y - PLAYER_WORLD_HEAD_SPRITE_HEIGHT / 2.0;

                    player_is_grounded = is_grounded(player, collidable_blocks);
                    if player_is_grounded {
                        player.jumps_remaining = player.jumps_capacity;
                        player.vel.y = 0;
                    }
                }

                if try_to_attack {
                    is_on_cooldown := player.cooldown_attack_current_ms > 0;

                    if debug_mode || (!is_on_cooldown && Vector2Distance(mouse_pos_in_world, player.pos) < PLAYER_REACH_DISTANCE) {
                        torch_mouse_is_over := get_colliding_entity_by_vec2(mouse_pos_in_world, torches); // TODO: active torches

                        // Destroy torch
                        if torch_mouse_is_over != null {
                            try_to_add_to_inventory(*player.inventory, .TORCH);
                            destroy_entity(torch_mouse_is_over, *player);
                        }
                        // No torches, so check blocks next
                        else {
                            block_mouse_is_over : *Block = get_colliding_entity_by_vec2(mouse_pos_in_world, active_blocks);

                            if block_mouse_is_over != null {
                                block_type := block_mouse_is_over.block_type;
                                selected_item_stack, result := get_selected_item_stack(player.inventory);
                                has_an_item_selected := result == xx ReturnStatus.SUCCESS;

                                if has_an_item_selected {
                                    tool_type := selected_item_stack.item_type;
                                    can_item_break_block := can_item_break_blocks(tool_type);

                                    if debug_mode || can_item_break_block {
                                        breaking_speed : float32;
                                        if debug_mode {
                                            breaking_speed = 9000.1;
                                        } else if has_an_item_selected {
                                            breaking_speed = get_item_breaking_speed(tool_type);
                                        } else {
                                            breaking_speed = 1.0;  
                                        }

                                        damage := breaking_speed / block_mouse_is_over.hardness;
                                        if block_mouse_is_over.weak_to_tool == tool_type {
                                            damage *= BLOCK_WEAKNESS_MULTIPLIER;
                                        }
                                        block_mouse_is_over.health_curr -= damage;
                                        
                                        // Destroy block
                                        if block_mouse_is_over.health_curr <= 0 {
                                            try_to_add_to_inventory(*player.inventory, block_type_to_item_type(block_type));

                                            destroy_block(block_mouse_is_over, *player);
                                        }
                                    }
                                }
                            }
                            // No block, so check walls next
                            else {
                                wall_mouse_is_over := get_colliding_entity_by_vec2(mouse_pos_in_world, active_walls);

                                if wall_mouse_is_over != null {
                                    block_type := wall_mouse_is_over.block_type;
                                    selected_item_stack, result := get_selected_item_stack(player.inventory);
                                    has_an_item_selected := result == xx ReturnStatus.SUCCESS;

                                    if has_an_item_selected {
                                        tool_type := selected_item_stack.item_type;
                                        can_item_break_wall := can_item_break_walls(tool_type);

                                        if can_item_break_wall {
                                            neighbor_exists_north_wall, _ := get_neighbor(wall_mouse_is_over.pos, .NORTH, true);
                                            neighbor_exists_south_wall, _ := get_neighbor(wall_mouse_is_over.pos, .SOUTH, true);
                                            neighbor_exists_east_wall,  _ := get_neighbor(wall_mouse_is_over.pos, .EAST,  true);
                                            neighbor_exists_west_wall,  _ := get_neighbor(wall_mouse_is_over.pos, .WEST,  true);
                                            is_completely_surrounded_by_neighbors := neighbor_exists_north_wall && neighbor_exists_south_wall && neighbor_exists_east_wall && neighbor_exists_west_wall;

                                            if !is_completely_surrounded_by_neighbors {

                                                breaking_speed := ifx has_an_item_selected then get_item_breaking_speed(tool_type) else 1;

                                                damage := breaking_speed / wall_mouse_is_over.hardness;
                                                if wall_mouse_is_over.weak_to_tool == tool_type {
                                                    damage *= BLOCK_WEAKNESS_MULTIPLIER;
                                                }
                                                wall_mouse_is_over.health_curr -= damage;
                                                
                                                if wall_mouse_is_over.health_curr <= 0 {
                                                    try_to_add_to_inventory(*player.inventory, block_type_to_item_type(block_type));

                                                    destroy_block(wall_mouse_is_over, *player);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        player.cooldown_attack_current_ms = PLAYER_COOLDOWN_ATTACK_DURATION_MS;
                    }
                }

                // @TODO: This should actually not place down blocks, but interact with interactable items like doors.
                if try_to_interact {

                    is_on_cooldown := player.cooldown_interact_current_ms > 0;

                    if !is_on_cooldown {

                        selected_item_stack, result := get_selected_item_stack(player.inventory);
                        has_an_item_selected        := result == xx ReturnStatus.SUCCESS;

                        if has_an_item_selected {

                            item_can_be_placed_down     := can_item_be_placed_down(selected_item_stack.item_type);
                            is_wall                     := get_is_wall_item(selected_item_stack.item_type);
                            
                            if selected_item_stack.stack_count > 0 && item_can_be_placed_down {

                                new_rect    := create_rect_for_tile_from_point(mouse_pos_in_world, BLOCK_WORLD_WIDTH, BLOCK_WORLD_HEIGHT, is_wall);
                                new_pos     := get_rect_center(new_rect);
                                entity_type := item_type_to_entity_type(selected_item_stack.item_type);

                                if entity_type == {
                                    case Block;
                                        // Check if the new block would be placed on the player
                                        would_be_on_player := !is_wall && CheckCollisionRecs(new_rect, player.bounding_rect);

                                        // Check if the new block would be placed on an existing block
                                        block_already_exists_at_location, _ := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(new_pos));
                                        wall_already_exists_at_location, _  := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(new_pos));

                                        neighbor_exists_north_block, _ := get_neighbor(new_pos, .NORTH, false);
                                        neighbor_exists_south_block, _ := get_neighbor(new_pos, .SOUTH, false);
                                        neighbor_exists_east_block,  _ := get_neighbor(new_pos, .EAST,  false);
                                        neighbor_exists_west_block,  _ := get_neighbor(new_pos, .WEST,  false);

                                        neighbor_exists_north_wall, _ := get_neighbor(new_pos, .NORTH, true);
                                        neighbor_exists_south_wall, _ := get_neighbor(new_pos, .SOUTH, true);
                                        neighbor_exists_east_wall,  _ := get_neighbor(new_pos, .EAST,  true);
                                        neighbor_exists_west_wall,  _ := get_neighbor(new_pos, .WEST,  true);

                                        neighbor_exists_north := neighbor_exists_north_wall || neighbor_exists_north_block;
                                        neighbor_exists_south := neighbor_exists_south_wall || neighbor_exists_south_block;
                                        neighbor_exists_east  := neighbor_exists_east_wall  || neighbor_exists_east_block;
                                        neighbor_exists_west  := neighbor_exists_west_wall  || neighbor_exists_west_block;

                                        is_position_placeable :=
                                            !would_be_on_player &&
                                            ((!is_wall && !block_already_exists_at_location) || (is_wall && !wall_already_exists_at_location)) &&
                                            (neighbor_exists_north || neighbor_exists_south || neighbor_exists_east || neighbor_exists_west);

                                        is_within_reach := Vector2Distance(mouse_pos_in_world, player.pos) < PLAYER_REACH_DISTANCE;

                                        can_place_block := debug_mode || (is_position_placeable && is_within_reach);

                                        // Place block down
                                        if can_place_block {
                                            new_block_type := item_type_to_block_type(selected_item_stack.item_type);

                                            new_block := generate_block(new_block_type, new_rect.x, new_rect.y);

                                            selected_item_stack.stack_count -= 1;

                                            player.cooldown_interact_current_ms = PLAYER_COOLDOWN_INTERACT_DURATION_MS;

                                            set_block_shadow_relative_to_neighbors(new_pos);
                                            
                                            update_block_shadows_around_pos(new_pos);

                                            new_block.texture_map_source_pos = get_texture_map_source_coords_for_block(new_block);
                                            update_texture_map_source_pos_around_pos(new_pos, false);
                                        }
                                    
                                    case Torch;
                                        torch_already_exists_at_location, _ := table_find_new(*global_torch_pos_to_torch, vector2_to_string_temp(new_pos));

                                        center_block_exists, center_block := get_neighbor(new_pos, .CENTER, false);
                                        south_block_exists,  south_block  := get_neighbor(new_pos, .SOUTH,  false);
                                        east_block_exists,   east_block   := get_neighbor(new_pos, .EAST,   false);
                                        west_block_exists,   west_block   := get_neighbor(new_pos, .WEST,   false);
                                        center_wall_exists,  center_wall  := get_neighbor(new_pos, .CENTER, true);

                                        is_position_placeable :=
                                            !torch_already_exists_at_location &&
                                            !center_block_exists &&
                                            (south_block_exists || east_block_exists || west_block_exists || center_wall_exists);

                                        is_within_reach := Vector2Distance(mouse_pos_in_world, player.pos) < PLAYER_REACH_DISTANCE;

                                        can_place_torch := debug_mode || (is_position_placeable && is_within_reach);

                                        // Place torch down
                                        if can_place_torch {
                                            new_torch := generate_torch(new_rect.x, new_rect.y);

                                            player.inventory.item_stacks[player.inventory.selected_item_stack].stack_count -= 1;

                                            player.cooldown_interact_current_ms = PLAYER_COOLDOWN_INTERACT_DURATION_MS;

                                            // Illuminate blocks and walls within one hop.
                                            north_block_exists, north_block := get_neighbor(new_pos, .NORTH, false);
                                            north_wall_exists,  north_wall  := get_neighbor(new_pos, .NORTH, true);
                                            south_wall_exists,  south_wall  := get_neighbor(new_pos, .SOUTH, true);
                                            east_wall_exists,   east_wall   := get_neighbor(new_pos, .EAST,  true);
                                            west_wall_exists,   west_wall   := get_neighbor(new_pos, .WEST,  true);

                                            row_hops := 0;
                                            for col: -6..6 {
                                                for row: (row_hops*-1)..-1 {
                                                    pos := Vector2.{ new_pos.x + col * BLOCK_WORLD_WIDTH, xx (new_pos.y + row * BLOCK_WORLD_HEIGHT) };

                                                    block_exists, block := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(pos));
                                                    wall_exists, wall := table_find_new(*global_wall_pos_to_wall, vector2_to_string_temp(pos));

                                                    if block_exists block.shadow = min(cast(u8) (abs(col) - row), block.shadow);
                                                    if wall_exists  wall.shadow  = min(cast(u8) (abs(col) - row), wall.shadow);
                                                }
                                                for row: 0..row_hops {
                                                    pos := Vector2.{ new_pos.x + col * BLOCK_WORLD_WIDTH, xx (new_pos.y + row * BLOCK_WORLD_HEIGHT) };

                                                    block_exists, block := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(pos));
                                                    wall_exists, wall := table_find_new(*global_wall_pos_to_wall, vector2_to_string_temp(pos));

                                                    if block_exists block.shadow = min(cast(u8) (abs(col) + row), block.shadow);
                                                    if wall_exists  wall.shadow  = min(cast(u8) (abs(col) + row), wall.shadow);
                                                }
                                                row_hops += 1;
                                            }
                                        }

                                    case;
                                        assert(false, "forgot entity type to place down.");
                                }
                            }
                        }
                    }
                }

                // Update sprites and animations
                {
                    trying_to_move_horizontally := move_player_left != move_player_right;
                    trying_to_run               := trying_to_move_horizontally && player_is_grounded;
                    airborne_or_idle            := !trying_to_move_horizontally || !player_is_grounded;
                    idle_on_ground              := !trying_to_move_horizontally && player_is_grounded;
                    falling_quickly             := player.vel.y > 325.0;

                    // Arms swinging
                    {
                        // TODO: this is duplicated, can/should this be a function?
                        interacting_with_inventory := false;
                        interactable_inventory_slots := ifx player.inventory.is_inventory_open then INVENTORY_SLOTS-1 else INVENTORY_SLOTS_PER_ROW-1;
                        for 0..interactable_inventory_slots {
                            slot_pane := build_inventory_slot_rect(it);

                            if CheckCollisionPointRec(mouse_pos_in_ui, slot_pane) {
                                interacting_with_inventory = true;
                                break;
                            }
                        }

                        was_previously_active      := player_animation_hands_swinging.active;
                        player_began_action        := !interacting_with_inventory && (try_to_attack || try_to_interact) && !was_previously_active;
                        still_playing_out          := player_animation_hands_swinging.timer_ms <= animation_get_total_duration_ms(player_animation_hands_swinging) &&
                                                      player_animation_hands_swinging.timer_ms > 0;
                        should_start_now := player_began_action;
                        should_continue  := was_previously_active && still_playing_out;
                        
                        player_is_swinging = should_start_now || should_continue;

                        player_animation_hands_swinging.active      = player_is_swinging;
                        player_animation_undershirt_swinging.active = player_is_swinging;

                        // Update item type that the player is swinging
                        if should_start_now {
                            global_item_type_swinging = get_selected_item_stack(player.inventory).item_type;
                        } else if was_previously_active && !should_continue {
                            global_item_type_swinging = ItemType.UNSPECIFIED;
                        }
                    }

                    // Idle (or airborne)
                    {
                        player_sprite_head_idle.active           = airborne_or_idle;
                        player_sprite_hair_1_idle.active         = airborne_or_idle;
                        player_sprite_eye_white_idle.active      = airborne_or_idle;
                        player_sprite_eye_iris_idle.active       = airborne_or_idle;
                        player_sprite_pants_idle.active          = idle_on_ground;
                        player_sprite_shoes_idle.active          = idle_on_ground;
                        player_sprite_chest_grounded_idle.active = idle_on_ground || (!player_is_grounded && !falling_quickly);
                        player_sprite_undershirt_idle.active     = idle_on_ground && !player_is_swinging;
                        player_sprite_hands_idle.active          = idle_on_ground && !player_is_swinging;
                    }

                    // Running
                    {
                        player_animation_head_running.active           = trying_to_run;
                        player_animation_hair_1_running.active         = trying_to_run;
                        player_animation_eye_white_running.active      = trying_to_run;
                        player_animation_eye_iris_running.active       = trying_to_run;
                        player_animation_chest_grounded_running.active = trying_to_run;
                        player_animation_pants_running.active          = trying_to_run;
                        player_animation_shoes_running.active          = trying_to_run;
                        player_animation_undershirt_running.active     = trying_to_run && !player_is_swinging;
                        player_animation_hands_running.active          = trying_to_run && !player_is_swinging;
                    }

                    // Airborne
                    {
                        player_sprite_pants_airborne.active      = !player_is_grounded;
                        player_sprite_shoes_airborne.active      = !player_is_grounded;
                        player_sprite_undershirt_airborne.active = !player_is_grounded && !falling_quickly && !player_is_swinging;
                        player_sprite_hands_airborne.active      = !player_is_grounded && !falling_quickly && !player_is_swinging;
                    }

                    // Falling
                    {
                        player_sprite_chest_falling.active      = falling_quickly;
                        player_sprite_undershirt_falling.active = falling_quickly && !player_is_swinging;
                        player_sprite_hands_falling.active      = falling_quickly && !player_is_swinging;
                    }

                    // Update active animation timers
                    for player_animations {
                        if it.active {
                            it.timer_ms += xx (dt * 1000);

                            if !it.loops && it.timer_ms > animation_get_total_duration_ms(it.*) {
                                it.timer_ms = 0;
                                it.active   = false;
                            }   
                        } else {
                            it.timer_ms = 0;
                        };
                    }

                    if player_is_swinging {
                        global_swing_timer_ms += xx (dt * 1000);
                    } else {
                        global_swing_timer_ms = 0;
                    }
                }

                // Update player cooldowns
                {
                    if player.cooldown_attack_current_ms > 0 {
                        player.cooldown_attack_current_ms -= xx (dt * 1000);
                    }

                    if player.cooldown_interact_current_ms > 0 {
                        player.cooldown_interact_current_ms -= xx (dt * 1000);
                    }
                }
            }

            // Update torches
            {
                for torches {
                    // Generate spark particles
                    if it.cooldown_spawn_spark_ms <= 0 {
                        rect := Rectangle.{ it.bounding_rect.x, it.bounding_rect.y, PARTICLE_SPARK_WORLD_WIDTH, PARTICLE_SPARK_WORLD_HEIGHT };

                        new_particle := New(Particle);
                        new_particle.type              = Particle;
                        new_particle.particle_type     = .SPARK;
                        new_particle.pos               = get_rect_center(rect);
                        new_particle.vel               = Vector2.{ random_get_within_range(-40, 40), random_get_within_range(-300, -1000) };
                        new_particle.bounding_rect     = rect;
                        new_particle.sprite_rect       = rect;
                        new_particle.time_remaining_ms = 1200;

                        array_add(*particles, new_particle);

                        it.cooldown_spawn_spark_ms = xx random_get_within_range(TORCH_COOLDOWN_SPAWN_SPARK_MS / 3, TORCH_COOLDOWN_SPAWN_SPARK_MS);
                    } else {
                        it.cooldown_spawn_spark_ms -= xx (dt * 1000);
                    }
                }
            }

            // Update particles
            {
                for particles {
                    if it.time_remaining_ms <= 0 {
                        destroy_entity(it, *player);
                    } else {

                        it.time_remaining_ms -= xx (dt * 1000);

                        it.vel.y += ACCEL_DUE_TO_GRAVITY/2.0 * dt * 0.5;

                        it.pos.x += it.vel.x * dt;
                        it.pos.y += it.vel.y * dt;

                        it.vel.y += ACCEL_DUE_TO_GRAVITY/2.0 * dt * 0.5;

                        // Update position-dependent fields on player entity
                        it.bounding_rect.x = it.pos.x - it.bounding_rect.width  / 2.0;
                        it.bounding_rect.y = it.pos.y - it.bounding_rect.height / 2.0;
                        it.sprite_rect.x   = it.pos.x - it.bounding_rect.width  / 2.0;
                        it.sprite_rect.y   = it.pos.y - it.bounding_rect.height / 2.0;
                    }
                }
            }

            // Update inventory
            {
                if hotbar_swap_next {
                    player.inventory.selected_item_stack = (player.inventory.selected_item_stack + 1) % INVENTORY_SLOTS_PER_ROW;
                }

                if hotbar_swap_prev {
                    // Can't simply modulo this because of underflow.
                    player.inventory.selected_item_stack = ifx player.inventory.selected_item_stack == 0
                        then INVENTORY_SLOTS_PER_ROW - 1
                        else player.inventory.selected_item_stack - 1;
                }

                if open_inventory {
                    player.inventory.is_inventory_open = !player.inventory.is_inventory_open;
                }

                interactable_inventory_slots := ifx player.inventory.is_inventory_open then INVENTORY_SLOTS-1 else INVENTORY_SLOTS_PER_ROW-1;
                for 0..interactable_inventory_slots {
                    slot_pane := build_inventory_slot_rect(it);

                    if CheckCollisionPointRec(mouse_pos_in_ui, slot_pane) {
                        global_item_stack_hovered_by_mouse = player.inventory.item_stacks[it];

                        if IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT) {
                            if (
                                !item_stack_is_empty(*global_item_stack_selected_by_mouse)            &&
                                !item_stack_is_empty(*global_item_stack_hovered_by_mouse)             &&
                                item_type_is_stackable(global_item_stack_selected_by_mouse.item_type) &&
                                item_type_is_stackable(global_item_stack_hovered_by_mouse.item_type)  &&
                                global_item_stack_selected_by_mouse.item_type == global_item_stack_hovered_by_mouse.item_type 
                            ) {
                                potential_new_hovered_stack_count := global_item_stack_hovered_by_mouse.stack_count + global_item_stack_selected_by_mouse.stack_count;

                                amount_to_transfer_to_inventory := ifx potential_new_hovered_stack_count <= global_item_stack_hovered_by_mouse.stack_capacity
                                    then global_item_stack_selected_by_mouse.stack_count
                                    else global_item_stack_selected_by_mouse.stack_count + global_item_stack_hovered_by_mouse.stack_capacity - potential_new_hovered_stack_count;

                                player.inventory.item_stacks[it].stack_count    += amount_to_transfer_to_inventory;
                                global_item_stack_selected_by_mouse.stack_count -= amount_to_transfer_to_inventory;
                            } else {
                                // Place down any stack you were just holding (if not holding anything, it'll be empty)
                                player.inventory.item_stacks[it] = *global_item_stack_selected_by_mouse;

                                // Pick up the item stack you were just hovering
                                global_item_stack_selected_by_mouse = *global_item_stack_hovered_by_mouse;
                            }
                        }

                        if IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_RIGHT) {
                            // Pick up half the stack you are hovering
                            if item_stack_is_empty(*global_item_stack_selected_by_mouse) {
                                if !item_stack_is_empty(*global_item_stack_hovered_by_mouse) {
                                    count_diff := ifx global_item_stack_hovered_by_mouse.stack_count == 1 then 1 else global_item_stack_hovered_by_mouse.stack_count / 2;
                                    
                                    global_item_stack_selected_by_mouse = ItemStack.{
                                        item_type      = global_item_stack_hovered_by_mouse.item_type,
                                        stack_capacity = global_item_stack_hovered_by_mouse.stack_capacity,
                                        stack_count    = count_diff,
                                    };

                                    player.inventory.item_stacks[it].stack_count -= count_diff;
                                }
                            }
                            // Place down one count of what you are holding
                            else {
                                if item_stack_is_empty(*global_item_stack_hovered_by_mouse) {
                                    player.inventory.item_stacks[it] = ItemStack.{
                                        item_type      = global_item_stack_selected_by_mouse.item_type,
                                        stack_capacity = global_item_stack_selected_by_mouse.stack_capacity,
                                        stack_count    = 1,
                                    };

                                    if item_type_is_stackable(global_item_stack_selected_by_mouse.item_type) {
                                        global_item_stack_selected_by_mouse.stack_count -= 1;
                                    } else {
                                        global_item_stack_selected_by_mouse = EMPTY_ITEM_STACK;
                                    }
                                } else if global_item_stack_hovered_by_mouse.item_type == global_item_stack_selected_by_mouse.item_type {
                                    if item_type_is_stackable(global_item_stack_selected_by_mouse.item_type) {
                                        if global_item_stack_hovered_by_mouse.stack_count != global_item_stack_hovered_by_mouse.stack_capacity {
                                            player.inventory.item_stacks[it] = ItemStack.{
                                                item_type      = global_item_stack_selected_by_mouse.item_type,
                                                stack_capacity = global_item_stack_selected_by_mouse.stack_capacity,
                                                stack_count    = global_item_stack_hovered_by_mouse.stack_count + 1,
                                            };

                                            global_item_stack_selected_by_mouse.stack_count -= 1;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Sanity checks
                #if !RELEASE {
                    // @PERF
                    for 0..interactable_inventory_slots {
                        assert(player.inventory.item_stacks[it].stack_count >= -1, "There is an item stack with a count less than -1 in inventory slot % (got %).", it, player.inventory.item_stacks[it].stack_count);
                    }

                    assert(global_item_stack_selected_by_mouse.stack_count >= -1, "The item stack selected by the mouse has a count less than -1 somehow. (got %)", global_item_stack_selected_by_mouse.stack_count);
                }
            }

            // Update crafting
            if player.inventory.is_inventory_open {
                // Determine which recipes are craftable with the item stacks in the player's inventory.
                for recipe: CRAFTING_RECIPES_WITHOUT_WORKBENCH {

                    inventory_has_all_ingredients := true;

                    for ingredient: recipe.ingredients {
                        
                        // Assume the inventory does not have this ingredient until proven otherwise.
                        inventory_has_this_ingredient := false;

                        for inventory_stack: player.inventory.item_stacks {
                            if inventory_stack.item_type == ingredient.item_type && inventory_stack.stack_count >= ingredient.item_count {
                                inventory_has_this_ingredient = true;
                                break;
                            }
                        }

                        if !inventory_has_this_ingredient {
                            inventory_has_all_ingredients = false;
                            break;
                        }
                    }

                    if inventory_has_all_ingredients array_add(*craftable_recipes, recipe);
                }

                near_workbench := false; // TODO
                if near_workbench {
                    for recipe: CRAFTING_RECIPES_WITH_WORKBENCH {

                        inventory_has_all_ingredients := true;

                        for ingredient: recipe.ingredients {
                            
                            // Assume the inventory does not have this ingredient until proven otherwise.
                            inventory_has_this_ingredient := false;

                            for inventory_stack: player.inventory.item_stacks {
                                if inventory_stack.item_type == ingredient.item_type && inventory_stack.stack_count >= ingredient.item_count {
                                    inventory_has_this_ingredient = true;
                                    break;
                                }
                            }

                            if !inventory_has_this_ingredient {
                                inventory_has_all_ingredients = false;
                                break;
                            }
                        }

                        if inventory_has_all_ingredients array_add(*craftable_recipes, recipe);
                    }
                }

                // Select crafting pane if a user clicks one
                for recipe: craftable_recipes {
                    hotbar_pane_rect := build_inventory_slot_rect(INVENTORY_SLOTS + INVENTORY_SLOTS_PER_ROW + it_index);

                    // If the user clicks on this crafting panel and they aren't holding anything then they should
                    // pick up the output of the recipe, we should remove the ingredients from their inventory, etc.
                    if (
                        CheckCollisionPointRec(mouse_pos_in_ui, hotbar_pane_rect) &&
                        IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT)
                    ) {
                        if item_stack_is_empty(*global_item_stack_selected_by_mouse) {
                            // Give them the output of the recipe.
                            global_item_stack_selected_by_mouse = recipe.output;

                            // Remove the ingredients from their inventory.
                            // @PERF lots of nested loops here
                            for recipe.ingredients {
                                remove_from_inventory(*player.inventory, it.item_type, it.item_count);
                            }
                        }
                        else if global_item_stack_selected_by_mouse.item_type == recipe.output.item_type {
                            new_count := min(
                                global_item_stack_selected_by_mouse.stack_capacity,
                                global_item_stack_selected_by_mouse.stack_count + recipe.output.stack_count,
                            );

                            count_to_add := new_count - global_item_stack_selected_by_mouse.stack_count;

                            if count_to_add > 0 {
                                global_item_stack_selected_by_mouse.stack_count += count_to_add;

                                // Remove the ingredients from their inventory.
                                // @PERF lots of nested loops here
                                for recipe.ingredients {
                                    remove_from_inventory(*player.inventory, it.item_type, it.item_count);
                                }
                            }
                        }
                    }
                }
            }

        }

        //
        // Draw
        //
        {
            BeginDrawing();
            defer EndDrawing();

            ClearBackground(SKYBLUE);

            block_to_debug : *Block = null;

            // Draw world
            {
                BeginMode2D(camera);
                defer EndMode2D();
                
                // Draw walls
                if render_walls {
                    for active_walls {
                        if draw_block(it, player, mouse_pos_in_world) {
                            block_to_debug = it;
                        }
                    }
                }

                // Draw blocks
                if render_blocks {
                    for active_blocks {
                        if draw_block(it, player, mouse_pos_in_world) {
                            block_to_debug = it;
                        }
                    }
                }

                // Draw torches
                for torches {
                    draw_torch(it);
                }

                // Draw particles
                for particles {
                    if #complete it.particle_type == {
                        case .SPARK;
                            t := it.time_remaining_ms * 0.001;

                            DrawRectangleV(
                                it.pos,
                                Vector2.{
                                    xx (it.sprite_rect.width  * t),
                                    xx (it.sprite_rect.height * t)
                                },
                                Color.{ 255, xx (255 * t), 0, 255 }
                            );
                        case .BLOCK_BIT;
                            DrawRectangleRec(it.sprite_rect, DARKBROWN);
                    }
                }

                // Draw player
                {
                    for player_sprites    { draw_sprite(it, player, PLAYER_MAP_TILE_WIDTH, PLAYER_MAP_TILE_HEIGHT); }
                    for player_animations { draw_sprite(it, player, PLAYER_MAP_TILE_WIDTH, PLAYER_MAP_TILE_HEIGHT); }

                    // Draw item wielded by player
                    if player_is_swinging {
                        if global_item_type_swinging != ItemType.UNSPECIFIED {
                            item_texture_map, item_source_rect := get_texture_map_by_item_type(global_item_type_swinging, player.is_facing_left);

                            length := get_item_world_length(global_item_type_swinging);
                            rotation : float;
                            destination_rect : Rectangle;
                            origin   := Vector2.{ xx ifx player.is_facing_left then length else 0, length - 10.0 };

                            if global_swing_timer_ms < 3 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                destination_rect = Rectangle.{
                                    ifx player.is_facing_left then player.pos.x + 25.0 else player.pos.x - 25.0,
                                    player.pos.y - 10.0,
                                    length,
                                    length,
                                };
                                
                                if global_swing_timer_ms < PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then 105.0 else -105.0;
                                }
                                else if global_swing_timer_ms < 2 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then 90.0 else  -90.0;
                                } else {
                                    rotation = ifx player.is_facing_left then 75.0 else  -75.0;
                                }
                            }
                            else if global_swing_timer_ms < 6 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                destination_rect = Rectangle.{
                                    ifx player.is_facing_left then player.pos.x - 5.0 else player.pos.x + 5.0,
                                    player.pos.y - 15.0,
                                    length,
                                    length,
                                };
                                
                                if global_swing_timer_ms < 4 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then 45.0 else -45.0;
                                }
                                else if global_swing_timer_ms < 5 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then 30.0 else -30.0;
                                } else {
                                    rotation = ifx player.is_facing_left then 0.0  else 0.0;
                                }
                            }
                            else if global_swing_timer_ms < 9 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                destination_rect = Rectangle.{
                                    ifx player.is_facing_left then player.pos.x - 15.0 else player.pos.x + 15.0,
                                    player.pos.y + 10.0,
                                    length,
                                    length,
                                };
                                
                                if global_swing_timer_ms < 7 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then -15.0 else 15.0;
                                }
                                else if global_swing_timer_ms < 8 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then -45.0 else 45.0;
                                } else {
                                    rotation = ifx player.is_facing_left then -60.0 else 60.0;
                                }
                            }
                            else if global_swing_timer_ms < 12 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                destination_rect = Rectangle.{
                                    ifx player.is_facing_left then player.pos.x - 20.0 else player.pos.x + 20.0,
                                    player.pos.y + 20.0,
                                    length,
                                    length,
                                };
                                
                                if global_swing_timer_ms < 10 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then -75.0  else 75.0;
                                }
                                else if global_swing_timer_ms < 11 * PLAYER_ANIMATION_WIELD_DURATION_MS {
                                    rotation = ifx player.is_facing_left then -90.0  else 90.0;
                                } else {
                                    rotation = ifx player.is_facing_left then -105.0 else 105.0;
                                }
                            }

                            DrawTexturePro(item_texture_map, item_source_rect, destination_rect, origin, rotation, WHITE);
                        }
                    }

                    if debug_mode {
                        DrawRectangleLinesEx(player.bounding_rect, 1.0, LIME);
                        // DrawCircleV(player.pos, 3.0, RED);
                    }
                }
            }

            // Draw UI
            {
                DrawFPS(GetScreenWidth() - 100, 10);

                // Draw hotbar
                for 0..9 draw_inventory_slot(xx it, player, true);

                // Draw inventory
                if player.inventory.is_inventory_open {
                    for 10..19 draw_inventory_slot(xx it, player, false);
                    for 20..29 draw_inventory_slot(xx it, player, false);
                    for 30..39 draw_inventory_slot(xx it, player, false);
                    for 40..49 draw_inventory_slot(xx it, player, false);
                }

                // Draw crafting tiles
                if player.inventory.is_inventory_open {
                    for recipe: craftable_recipes {
                        slot_index := INVENTORY_SLOTS + INVENTORY_SLOTS_PER_ROW + it_index;
                        hotbar_pane_rect := build_inventory_slot_rect(slot_index);

                        DrawTexturePro(
                            inventory_back_texture,
                            Rectangle.{ 0, 0, INVENTORY_BACK_TEXTURE_WIDTH, INVENTORY_BACK_TEXTURE_HEIGHT },
                            hotbar_pane_rect,
                            Vector2.{ 0, 0 },
                            0.0,
                            Color.{ 255, 255, 255, 200 },
                        );

                        if player.inventory.selected_item_stack == slot_index {
                            DrawRectangleRoundedLinesEx(hotbar_pane_rect, 0.1, 1, HOTBAR_PANE_THICKNESS, WHITE);
                        }

                        item_texture_map, item_source_rect := get_texture_map_by_item_type(recipe.output.item_type);
                        DrawTexturePro(item_texture_map, item_source_rect, hotbar_pane_rect, Vector2.{ 0, 0 }, 0.0, WHITE);
                        
                        if item_type_is_stackable(recipe.output.item_type) {
                            DrawText(
                                tprint("%\0", recipe.output.stack_count).data,
                                xx (hotbar_pane_rect.x + 0.50 * HOTBAR_PANE_LENGTH),    
                                xx (hotbar_pane_rect.y + 0.67 * HOTBAR_PANE_LENGTH),    
                                18,
                                WHITE,
                            );
                        }
                    }
                }

                // Draw selected item
                if !item_stack_is_empty(*global_item_stack_selected_by_mouse) {
                    item_texture_map, item_source_rect := get_texture_map_by_item_type(global_item_stack_selected_by_mouse.item_type);
                    south_east_of_cursor := Rectangle.{
                        mouse_pos_in_ui.x + 10,
                        mouse_pos_in_ui.y + 10,
                        HOTBAR_PANE_LENGTH, HOTBAR_PANE_LENGTH,
                    };
                    DrawTexturePro(item_texture_map, item_source_rect, south_east_of_cursor, Vector2.{ 0, 0 }, 0.0, WHITE);

                    if item_type_is_stackable(global_item_stack_selected_by_mouse.item_type) {
                        DrawText(
                            tprint("%\0", global_item_stack_selected_by_mouse.stack_count).data,
                            xx (south_east_of_cursor.x + 0.50 * HOTBAR_PANE_LENGTH),
                            xx (south_east_of_cursor.y + 0.67 * HOTBAR_PANE_LENGTH),
                            18,
                            WHITE,
                        );
                    }
                }

                if debug_mode {
                    DrawText(tprint("(%, %)\0", mouse_pos_in_world.x, mouse_pos_in_world.y).data, 10, 30, 18, LIME);

                    // Draw debug block
                    if block_to_debug != null {
                        y : s32 = 50;
                        INCREMENT :: 20;
                        FONT_SIZE :: 20;
                        // @TODO: metaprogram?
                        DrawRectangle(0, 0, GetScreenWidth() / 4, GetScreenHeight(), Color.{ 0, 0, 0, 150 });
                        DrawText(tprint("id: %\0", block_to_debug.id).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("type: %\0", block_to_debug.type).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("pos: %\0", block_to_debug.pos).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("vel: %\0", block_to_debug.vel).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("is_facing_left: %\0", block_to_debug.is_facing_left).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("bounding_rect: %\0", block_to_debug.bounding_rect).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("sprite_rect: %\0", block_to_debug.sprite_rect).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("texture_map_source_pos: %\0", block_to_debug.texture_map_source_pos).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("health_max: %\0", block_to_debug.health_max).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("health_curr: %\0", block_to_debug.health_curr).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("block_type: %\0", block_to_debug.block_type).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("hardness: %\0", block_to_debug.hardness).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("weak_to_tool: %\0", block_to_debug.weak_to_tool).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("shadow: %\0", block_to_debug.shadow).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("neighbor_north_count: %\0", block_to_debug.neighbor_north_count).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("neighbor_south_count: %\0", block_to_debug.neighbor_south_count).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("neighbor_east_count: %\0", block_to_debug.neighbor_east_count).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        DrawText(tprint("neighbor_west_count: %\0", block_to_debug.neighbor_west_count).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        if block_to_debug.type == TreeBlock {
                            DrawText(tprint("tree_block_type: %\0", (cast(*TreeBlock)block_to_debug).tree_block_type).data, 10, read_then_increment(*y, INCREMENT), FONT_SIZE, WHITE);
                        }
                    }
                }

                // @TODO: Draw pause menu
                if paused {

                }

                // Draw cursor
                DrawTexturePro(
                    cursor_texture,
                    Rectangle.{ 0, 0, CURSOR_TEXTURE_WIDTH, CURSOR_TEXTURE_HEIGHT },
                    Rectangle.{ mouse_pos_in_ui.x, mouse_pos_in_ui.y, CURSOR_WORLD_WIDTH, CURSOR_WORLD_HEIGHT },
                    Vector2.{ 0, 0 },
                    0.0,
                    RED,
                );
            }
        }
    }
}

read_then_increment :: (x: *s32, increment: s32 = 1) -> s32 {
    defer x.* += increment;
    return x.*;
}

draw_sprite :: (sprite: $T/Sprite, entity: Entity, texture_map_tile_width: s32, texture_map_tile_height: s32) {
    assert(texture_map_tile_width > 0,  "You probably want a positive width. If not, delete this assertion");
    assert(texture_map_tile_height > 0, "You probably want a positive height. If not, delete this assertion");
    if !sprite.active return;

    frame        := animation_get_current_frame(sprite);
    source_width : float = ifx entity.is_facing_left then cast(float) texture_map_tile_width * -1 else cast(float) texture_map_tile_width;
    source_rect  := Rectangle.{xx (frame * texture_map_tile_width), 0.0, source_width, xx texture_map_tile_height};
    // Without this +1 to its y pos, the player looks like he's floating off the ground by 1 pixel.
    dest_rect    := Rectangle.{ entity.sprite_rect.x, entity.sprite_rect.y + 1, entity.sprite_rect.width, entity.sprite_rect.height }; 

    DrawTexturePro(sprite.map, source_rect, dest_rect, Vector2.{ 0, 0 }, 0.0, sprite.color);
}

init_textures :: () {
    player_head_map           = LoadTexture("data/Player_Head_Release.png");
    player_hair_1_map         = LoadTexture("data/Player_Hair_1_Release.png");
    player_eye_white_map      = LoadTexture("data/Player_Eye_White_Release.png");
    player_eye_iris_map       = LoadTexture("data/Player_Eye_Iris_Release.png");
    player_chest_grounded_map = LoadTexture("data/Player_Chest_Grounded_Release.png");
    player_chest_airborne_map = LoadTexture("data/Player_Chest_Airborne_Release.png");
    player_undershirt_map     = LoadTexture("data/Player_Undershirt_Release.png");
    player_pants_map          = LoadTexture("data/Player_Pants_Release.png");
    player_hands_map          = LoadTexture("data/Player_Hands_Release.png");
    player_shoes_map          = LoadTexture("data/Player_Shoes_Release.png");
    dirt_map                  = LoadTexture("data/Tiles_0_debug.png");
    rock_map                  = LoadTexture("data/Tiles_1.png");
    grass_map                 = LoadTexture("data/Tiles_2.png");
    wood_map                  = LoadTexture("data/Tiles_30.png");
    tree_map                  = LoadTexture("data/Tiles_5.png");
    tree_branch_map           = LoadTexture("data/Tree_Branches.png");
    tree_top_map              = LoadTexture("data/Tree_Tops.png");
    copper_ore_map            = LoadTexture("data/Tiles_7.png");
    wall_rock_map             = LoadTexture("data/Wall_1.png");
    wall_dirt_map             = LoadTexture("data/Wall_2.png");
    damage_map                = LoadTexture("data/Damage.png");
    torch_map                 = LoadTexture("data/Tiles_4.png");
    dirt_item_texture         = LoadTexture("data/Dirt_Item.png");
    rock_item_texture         = LoadTexture("data/Rock_Item.png");
    wood_item_texture         = LoadTexture("data/Wood_Item.png");
    copper_ore_item_texture   = LoadTexture("data/Copper_Ore_Item.png");
    wall_rock_item_texture    = LoadTexture("data/Rock_Wall_Item.png"); // @TODO
    wall_dirt_item_texture    = LoadTexture("data/Rock_Wall_Item.png");
    pickaxe_texture           = LoadTexture("data/Pickaxe.png");
    axe_texture               = LoadTexture("data/Axe.png");
    sword_texture             = LoadTexture("data/Sword.png");
    hammer_texture            = LoadTexture("data/Hammer.png");
    torch_texture             = LoadTexture("data/Torch.png");
    cursor_texture            = LoadTexture("data/Cursor_0.png");
    inventory_back_texture    = LoadTexture("data/Inventory_Back.png");
}

control_down :: (haystack: [] Control) -> bool {
    for haystack {
        if it.type == KeyboardKey && IsKeyDown(xx it.value) return true;
        if it.type == MouseButton && IsMouseButtonDown(xx it.value) return true;
    }

    return false;
}

control_pressed :: (haystack: [] Control) -> bool {
    for haystack {
        if it.type == KeyboardKey && IsKeyPressed(xx it.value) return true;
        if it.type == MouseButton && IsMouseButtonPressed(xx it.value) return true;
    }

    return false;
}

round_to_int :: (f: float) -> int {
    i := cast(int) f;
    decimal_part := abs(f) - abs(i);

    if decimal_part >= 0.5 {
        if f >= 0 return i + 1;
        else      return i - 1;
    }

    return i;
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

// Returns a pointer to the entity the subject collided with, if anything.
try_to_move :: (entity: *Entity, distance: float, collidables: [] $T/interface *Entity, horizontal: bool) -> *Entity {
    move := round_to_int(distance);
    if move == 0 return null;

    sign := ifx move > 0 then 1 else -1;

    entity_rect_if_move := entity.bounding_rect;

    while move != 0 {
        if horizontal {
            entity_rect_if_move.x += sign;
        } else {
            entity_rect_if_move.y += sign;
        }

        entity_subject_would_have_collided_with := get_colliding_by_rect(entity_rect_if_move, collidables);
        if entity_subject_would_have_collided_with != null return entity_subject_would_have_collided_with;

        if horizontal {
            entity.pos.x += sign;
        } else {
            entity.pos.y += sign;
        }
        
        move -= sign;
    }

    return null;
}

can_jump :: (player: Player) -> bool {
    return player.jumps_remaining > 0;
}

is_grounded :: (entity: Entity, collidables: [] $T/interface Entity) -> bool {
    entity_rect_if_move := entity.bounding_rect;
    entity_rect_if_move.y += 1;
    return get_colliding_by_rect(entity_rect_if_move, collidables) != null;
}

update_camera_center :: (camera: *Camera2D, player: *Player, width: s32, height: s32) {
    camera.offset = Vector2.{ width/2.0 - player.bounding_rect.width/2.0, height/2.0 + 100 };
    camera.target = player.pos;
}

update_camera_center_smooth_follow :: (camera: *Camera2D, player: *Player, delta: float, width: s32, height: s32) {
    minSpeed: float = 100;
    minEffectLength: float = 1;
    fractionSpeed: float = 1.5;

    camera.offset = Vector2.{ width/2.0, height/2.0 };
    diff: Vector2 = Vector2Subtract(Vector2.{player.bounding_rect.x,player.bounding_rect.y}, camera.target);
    length: float = Vector2Length(diff);

    if (length > minEffectLength) {
        speed: float = ifx fractionSpeed*length > minSpeed then fractionSpeed*length else minSpeed;
        camera.target = Vector2Add(camera.target, Vector2Scale(diff, speed*delta/length));
    }
}

create_rect_for_tile_from_point :: (pos: Vector2, tile_width: s32, tile_height: s32, is_wall: bool) -> Rectangle {
    // First of all, chop off any decimal info from the pos. Placing blocks should only ever occur with on int coords.
    int_pos_x : int = cast(int) floor(pos.x);
    int_pos_y : int = cast(int) floor(pos.y);

    // Next calculate the amount we need to subtract to the position to get axis aligned.
    // In this diagram, dX is the amount to shift the pos to the left, and dY is the amount to shift up.
    //  +-----------+
    //  |   ^       |
    //  |   |       |
    //  |   |       |
    //  |<~~o       |
    //  |           |
    //  +-----------+
    d_x : int = int_pos_x % (tile_width );
    d_y : int = int_pos_y % (tile_height);

    if d_x < 0 { d_x += tile_width;  };
    if d_y < 0 { d_y += tile_height; };

    if is_wall {
        d_x += BLOCK_WORLD_WIDTH  / 2;
        d_y += BLOCK_WORLD_HEIGHT / 2;
    }

    x := int_pos_x - d_x;
    y := int_pos_y - d_y;

    new_rect := Rectangle.{
        x      = xx x,
        y      = xx y,
        width  = xx ifx is_wall then tile_width  * 2 else tile_width,
        height = xx ifx is_wall then tile_height * 2 else tile_height,
    };

    return new_rect;
}

get_rect_center :: (rect: Rectangle) -> Vector2 {
    return Vector2.{ rect.x + rect.width / 2.0, rect.y + rect.height / 2.0 };
}

smootherstep :: (x: float) -> float {
    if x <= 0.0 return 0.0;
    if x >= 1.0 return 1.0;
    return (6 * x * x * x * x * x) - (15 * x * x * x * x) + (10 * x * x * x); 
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

animation_get_current_frame :: (sprite: $T/Sprite) -> s32 {
    #if type_of(sprite) == Sprite {
        return sprite.first_frame;
    } else {
        if sprite.frame_duration_ms == 0 return 0;
        return ((sprite.timer_ms / sprite.frame_duration_ms) % sprite.frame_count) + sprite.first_frame;
    }
}

// Returns the duration of one full playing of the animation. So, if there are 10 frames, each 50 ms long, the
// duration would be 500ms
animation_get_total_duration_ms :: (animation: AnimatedSprite) -> s32 {
    return animation.frame_count * animation.frame_duration_ms;
}

respawn_player :: () -> Player {
    // Initialize player
    pos := Vector2.{ GetScreenWidth() / 2.0, -1.0 * GetScreenHeight() };

    player := Player.{
        type = Player,

        pos  = pos,
        vel  = Vector2.{ 0, 0 },

        bounding_rect = Rectangle.{
            pos.x - floor(PLAYER_WORLD_BOUNDING_WIDTH / 2.0),
            pos.y - floor(PLAYER_WORLD_BOUNDING_HEIGHT / 2.0) + 5,
            xx PLAYER_WORLD_BOUNDING_WIDTH,
            xx PLAYER_WORLD_BOUNDING_HEIGHT,
        },
        sprite_rect = Rectangle.{
            pos.x - floor(PLAYER_WORLD_HEAD_SPRITE_WIDTH / 2.0),
            pos.y - floor(PLAYER_WORLD_HEAD_SPRITE_HEIGHT / 2.0),
            xx PLAYER_WORLD_HEAD_SPRITE_WIDTH,
            xx PLAYER_WORLD_HEAD_SPRITE_HEIGHT,
        },

        jumps_capacity  = 2,
        jumps_remaining = 2,

        is_facing_left = false,

        cooldown_attack_current_ms   = 0,
        cooldown_interact_current_ms = 0,
    };

    // Initialize inventory
    {
        player.inventory.is_inventory_open = false;

        // Fill in the rest of the item stacks with invalid data
        for *player.inventory.item_stacks {
            it = null;
        }

        // Add in various items for dev purposes
        player.inventory.selected_item_stack = 0;
        
        player.inventory.item_stacks[0] = ItemStack.{
            item_type     = .SWORD,
            stack_capacity = SWORD_STACK_CAPACITY,
            stack_count    = SWORD_STACK_CAPACITY,
        };
        player.inventory.item_stacks[1] = ItemStack.{
            item_type     = .PICKAXE,
            stack_capacity = PICKAXE_STACK_CAPACITY,
            stack_count    = PICKAXE_STACK_CAPACITY,
        };
        player.inventory.item_stacks[2] = ItemStack.{
            item_type     = .AXE,
            stack_capacity = AXE_STACK_CAPACITY,
            stack_count    = AXE_STACK_CAPACITY,
        };
        player.inventory.item_stacks[3] = ItemStack.{
            item_type     = .HAMMER,
            stack_capacity = HAMMER_STACK_CAPACITY,
            stack_count    = HAMMER_STACK_CAPACITY,
        };
        player.inventory.item_stacks[4] = ItemStack.{
            item_type     = .DIRT_ITEM,
            stack_capacity = DIRT_STACK_CAPACITY,
            stack_count    = DIRT_STACK_CAPACITY,
        };
        player.inventory.item_stacks[5] = ItemStack.{
            item_type     = .ROCK_ITEM,
            stack_capacity = ROCK_STACK_CAPACITY,
            stack_count    = ROCK_STACK_CAPACITY,
        };
        player.inventory.item_stacks[6] = ItemStack.{
            item_type     = .WALL_DIRT_ITEM,
            stack_capacity = WALL_DIRT_STACK_CAPACITY,
            stack_count    = WALL_DIRT_STACK_CAPACITY,
        };
        player.inventory.item_stacks[7] = ItemStack.{
            item_type     = .TORCH,
            stack_capacity = TORCH_STACK_CAPACITY,
            stack_count    = TORCH_STACK_CAPACITY,
        };
        player.inventory.item_stacks[8] = ItemStack.{
            item_type     = .AXE,
            stack_capacity = AXE_STACK_CAPACITY,
            stack_count    = AXE_STACK_CAPACITY,
        };
        player.inventory.item_stacks[9] = ItemStack.{
            item_type     = .WOOD_ITEM,
            stack_capacity = WOOD_ITEM_STACK_CAPACITY,
            stack_count    = WOOD_ITEM_STACK_CAPACITY,
        };
    }

    return player;
}

perlin_noise_1d :: (desired_values: s32, starting_frequency: s32, starting_amplitude: float32, octaves: s32, min_value := 0.0) -> [..] float {
    assert(desired_values > 0,     "You probably want a positive desired_values. If not, delete this assertion.");
    assert(starting_frequency > 0, "You probably want a positive starting_frequency. If not, delete this assertion.");
    assert(octaves > 0,            "You probably want a positive octaves. If not, delete this assertion.");
    assert(desired_values % starting_frequency == 0, "The perlin noise frequency must be a divisor of the number of desired values.");

    results : [..] float;
    for i: 0..desired_values {
        array_add(*results, 0.0);
    }

    for o: 0..octaves {
        octave_factor      := pow(2.0, cast(float) o);
        amplitude          := starting_amplitude / octave_factor;
        frequency          := starting_frequency * octave_factor;
        ratio              := desired_values / frequency;
        blocks_per_section := cast(int) (desired_values / frequency);

        random_grid_scalars: [..]float;
        for i: 0..(xx frequency-1) {
            array_add(*random_grid_scalars, random_get_within_range(-1, 1));
        }

        // @TODO: maybe loop around to the first section's left gradient?
        for i: 0..(desired_values - (blocks_per_section + 1)) {
            // Get distance from current tile to each grid corner
            f := floor(cast(float) i / ratio);
            delta_l := (i - ratio * f) / blocks_per_section;
            delta_r := (ratio * (f + 1) - i) / blocks_per_section;

            // Get dot products of grid corner vectors and distances
            l_scalar := random_grid_scalars[cast(int) (f)];
            r_scalar := random_grid_scalars[cast(int) (f + 1)];
            l_dot : float = l_scalar * delta_l;
            r_dot : float = r_scalar * delta_r;

            perlin := lerp(l_dot, r_dot, smootherstep(delta_l));
            results[i] += amplitude * perlin;
        }
    }

    // @PERF
    for *results {
        if it.* < min_value {
            it.* = min_value + abs(it.*);
        }
    }

    return results;
}

/**
 * frequency: how many blocks before the next gradient. The higher the frequency, the less blocks in between gradients
 */
perlin_noise_2d :: ($DESIRED_VALUES: s32, starting_frequency: s32 = 1, starting_amplitude: float32 = 1.0, octaves: s32 = 1) -> perlin_2d: [] float {
    assert(DESIRED_VALUES > 0,     "You probably want a positive DESIRED_VALUES. If not, delete this assertion.");
    assert(starting_frequency > 0, "You probably want a positive starting_frequency. If not, delete this assertion.");
    assert(octaves > 0,            "You probably want a positive octaves. If not, delete this assertion.");
    assert(DESIRED_VALUES % starting_frequency == 0, "The perlin noise frequency must be a divisor of the number of desired values.");

    results : [..] float;
    random_grid_gradients: [..] Vector2;
    for i: 0..(DESIRED_VALUES * DESIRED_VALUES - 1) {
        array_add(*results, 0.0);
    }

    for octave: 1..octaves {
        octave_factor       := pow(2.0, cast(float) octave - 1);
        amplitude           := starting_amplitude / octave_factor;
        frequency           := cast(int) (starting_frequency * octave_factor);
        blocks_per_section  := cast(int) (DESIRED_VALUES / frequency);
        max_raw_noise_value := blocks_per_section * SQRT_2 / 2;

        assert(blocks_per_section > 0, "Got zero blocks per section during 2d perlin noise generation. You probably have too many octaves.");
        
        for row: 0..frequency {
            for col: 0..frequency {
                gradient_x := random_get_within_range(-1, 1);
                gradient_y := random_get_within_range(-1, 1);
                gradient   := Vector2Normalize(Vector2.{ gradient_x, gradient_y });

                array_add(*random_grid_gradients, gradient);
            }
        }

        for row: 0..DESIRED_VALUES-1 {
            for col: 0..DESIRED_VALUES-1 {
                curr := Vector2.{ xx col, xx row };
                
                // The absolute coordinates of the current grid's corners that the point is within. 
                north_west := Vector2.{ xx (col - (col % blocks_per_section)), xx (row - (row % blocks_per_section)) }; 
                north_east := Vector2.{ xx (col - (col % blocks_per_section) + blocks_per_section), xx (row - (row % blocks_per_section)) };
                south_west := Vector2.{ xx (col - (col % blocks_per_section)), xx (row - (row % blocks_per_section) + blocks_per_section) };
                south_east := Vector2.{ xx (col - (col % blocks_per_section) + blocks_per_section), xx (row - (row % blocks_per_section) + blocks_per_section) };
                
                // The absolute distance between the current point and the grid's corners.
                north_west_delta := Vector2Subtract(north_west, curr);
                north_east_delta := Vector2Subtract(north_east, curr);
                south_west_delta := Vector2Subtract(south_west, curr);
                south_east_delta := Vector2Subtract(south_east, curr);

                // The indices of the array holding the gradient vectors for each of the grid corners.
                north_west_gradient_index := cast(int) ((north_west.x / blocks_per_section) + (north_west.y / blocks_per_section * (frequency + 1)));
                north_east_gradient_index := cast(int) ((north_east.x / blocks_per_section) + (north_east.y / blocks_per_section * (frequency + 1)));
                south_west_gradient_index := cast(int) ((south_west.x / blocks_per_section) + (south_west.y / blocks_per_section * (frequency + 1)));
                south_east_gradient_index := cast(int) ((south_east.x / blocks_per_section) + (south_east.y / blocks_per_section * (frequency + 1)));

                // The gradient vectors for each of the grid corners.
                north_west_gradient := random_grid_gradients[north_west_gradient_index];
                north_east_gradient := random_grid_gradients[north_east_gradient_index];
                south_west_gradient := random_grid_gradients[south_west_gradient_index];
                south_east_gradient := random_grid_gradients[south_east_gradient_index];

                // The dot product of each gradient vector with the corresponding distance vector.
                north_west_dot := dot_product(north_west_gradient, north_west_delta);
                north_east_dot := dot_product(north_east_gradient, north_east_delta);
                south_west_dot := dot_product(south_west_gradient, south_west_delta);
                south_east_dot := dot_product(south_east_gradient, south_east_delta);

                // Percent traveled the grid in each direction. So if 30% of the way through the x coords,
                // t_x would be 0.300000.
                t_x := abs((curr.x - north_west.x) / blocks_per_section);
                t_y := abs((curr.y - north_west.y) / blocks_per_section);

                north_lerp := lerp(north_west_dot, north_east_dot, smootherstep(t_x));
                south_lerp := lerp(south_west_dot, south_east_dot, smootherstep(t_x));
                perlin     := lerp(north_lerp, south_lerp, smootherstep(t_y));

                results[row * DESIRED_VALUES + col] += amplitude * (perlin / max_raw_noise_value);
            }
        }
    }

    return results;
}

ReturnStatus :: enum u16 {
    SUCCESS;
    NOT_FOUND;
}

get_selected_item_stack :: (inventory: Inventory) -> item_stack: *ItemStack, return_status: ReturnStatus {
    item_stack := *inventory.item_stacks[inventory.selected_item_stack];

    if item_stack_is_empty(item_stack) && item_stack_is_empty(*global_item_stack_selected_by_mouse) {
        return null, ReturnStatus.NOT_FOUND;
    }
    else if !item_stack_is_empty(*global_item_stack_selected_by_mouse) {
        return *global_item_stack_selected_by_mouse, ReturnStatus.SUCCESS;
    }
    else {
        return item_stack, ReturnStatus.SUCCESS;
    }
    
}

get_block_hardness :: (block_type: BlockType) -> float {
    if #complete block_type == {
        case .DIRT;        return DIRT_HARDNESS;
        case .GRASS;       return GRASS_HARDNESS;
        case .ROCK;        return ROCK_HARDNESS;
        case .WOOD;        return WOOD_HARDNESS;
        case .TREE;        return WOOD_HARDNESS;
        case .TREE_BRANCH; return WOOD_HARDNESS;
        case .TREE_TOP;    return WOOD_HARDNESS;
        case .COPPER_ORE;  return COPPER_ORE_HARDNESS;

        case .WALL_DIRT;   return WALL_DIRT_HARDNESS;
        case .WALL_ROCK;   return WALL_ROCK_HARDNESS;

        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
            return -1; // Unreachable
    }
}

can_item_be_placed_down :: (item_type: ItemType) -> bool {
    if #complete item_type == {
        case .DIRT_ITEM;       return true;
        case .ROCK_ITEM;       return true;
        case .WOOD_ITEM;       return true;
        case .COPPER_ORE_ITEM; return false;
        case .WALL_DIRT_ITEM;  return true;
        case .WALL_ROCK_ITEM;  return true;
        case .PICKAXE;         return false;
        case .AXE;             return false;
        case .SWORD;           return false;
        case .HAMMER;          return false;
        case .TORCH;           return true;

        case .UNSPECIFIED;
            assert(false, "Invalid block type");
            return false; // Unreachable
    }
}

can_item_break_blocks :: (item_type: ItemType) -> bool {
    if #complete item_type == {
        case .DIRT_ITEM;       return false;
        case .ROCK_ITEM;       return false;
        case .WOOD_ITEM;       return false;
        case .COPPER_ORE_ITEM; return false;
        case .WALL_DIRT_ITEM;  return false;
        case .WALL_ROCK_ITEM;  return false;
        case .PICKAXE;         return true;
        case .AXE;             return true;
        case .SWORD;           return false;
        case .HAMMER;          return false;
        case .TORCH;           return false;

        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
            return false; // Unreachable
    }
}

can_item_break_walls :: (item_type: ItemType) -> bool {
    if #complete item_type == {
        case .DIRT_ITEM;       return false;
        case .ROCK_ITEM;       return false;
        case .WOOD_ITEM;       return false;
        case .COPPER_ORE_ITEM; return false;
        case .WALL_DIRT_ITEM;  return false;
        case .WALL_ROCK_ITEM;  return false;
        case .PICKAXE;         return false;
        case .AXE;             return false;
        case .SWORD;           return false;
        case .HAMMER;          return true;
        case .TORCH;           return false;

        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
            return false; // Unreachable
    }
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
derive_active_entities :: (active_blocks: *[..] *Block, active_walls: *[..] *Block, collidable_blocks: *[..] *Block, camera: Camera2D) {
    window_start := GetScreenToWorld2D(Vector2.{ 0, 0 }, camera);
    window_end   := GetScreenToWorld2D(Vector2.{ cast(float) GetScreenWidth(), cast(float) GetScreenHeight()}, camera);

    array_reset(active_blocks);
    array_reset(collidable_blocks);
    array_reset(active_walls);
    
    // Derive active blocks
    // NOTE: The order in which blocks are added to active_blocks matters!
    // The first will be furthest away in the z ordering.
    {
        for block: blocks_tree {
            // Notice that these widths and heights are different than the other blocks.
            if block.pos.x + TREE_TOP_WORLD_WIDTH < window_start.x continue;
            if block.pos.x - TREE_TOP_WORLD_WIDTH > window_end.x continue;
            
            if block.pos.y - TREE_TOP_WORLD_HEIGHT > window_end.y continue;
            if block.pos.y + TREE_TOP_WORLD_HEIGHT < window_start.y continue;

            array_add(active_blocks, block);
            // Trees are not collidable!
        }

        for block: blocks_dirt {
            if block.pos.x + BLOCK_WORLD_WIDTH < window_start.x continue;
            if block.pos.x - BLOCK_WORLD_WIDTH > window_end.x continue;
            
            if block.pos.y - BLOCK_WORLD_HEIGHT > window_end.y continue;
            if block.pos.y + BLOCK_WORLD_HEIGHT < window_start.y continue;

            array_add(active_blocks, block);
            array_add(collidable_blocks, block);
        }

        for block: blocks_grass {
            if block.pos.x + BLOCK_WORLD_WIDTH < window_start.x continue;
            if block.pos.x - BLOCK_WORLD_WIDTH > window_end.x continue;
            
            if block.pos.y - BLOCK_WORLD_HEIGHT > window_end.y continue;
            if block.pos.y + BLOCK_WORLD_HEIGHT < window_start.y continue;

            array_add(active_blocks, block);
            array_add(collidable_blocks, block);
        }

        for block: blocks_rock {
            if block.pos.x + BLOCK_WORLD_WIDTH < window_start.x continue;
            if block.pos.x - BLOCK_WORLD_WIDTH > window_end.x continue;
            
            if block.pos.y - BLOCK_WORLD_HEIGHT > window_end.y continue;
            if block.pos.y + BLOCK_WORLD_HEIGHT < window_start.y continue;

            array_add(active_blocks, block);
            array_add(collidable_blocks, block);
        }

        for block: blocks_wood {
            if block.pos.x + BLOCK_WORLD_WIDTH < window_start.x continue;
            if block.pos.x - BLOCK_WORLD_WIDTH > window_end.x continue;
            
            if block.pos.y - BLOCK_WORLD_HEIGHT > window_end.y continue;
            if block.pos.y + BLOCK_WORLD_HEIGHT < window_start.y continue;

            array_add(active_blocks, block);
            array_add(collidable_blocks, block);
        }

        for block: blocks_copper_ore {
            if block.pos.x + BLOCK_WORLD_WIDTH < window_start.x continue;
            if block.pos.x - BLOCK_WORLD_WIDTH > window_end.x continue;
            
            if block.pos.y - BLOCK_WORLD_HEIGHT > window_end.y continue;
            if block.pos.y + BLOCK_WORLD_HEIGHT < window_start.y continue;

            array_add(active_blocks, block);
            array_add(collidable_blocks, block);
        }
    }

    // Derive active walls
    {
        for wall: walls_dirt {
            if wall.pos.x + WALL_WORLD_WIDTH < window_start.x continue;
            if wall.pos.x - WALL_WORLD_WIDTH > window_end.x continue;
            
            if wall.pos.y - WALL_WORLD_HEIGHT > window_end.y continue;
            if wall.pos.y + WALL_WORLD_HEIGHT < window_start.y continue;
            
            array_add(active_walls, wall);
            // Walls are not collidable!
        }

        for wall: walls_rock {
            if wall.pos.x + WALL_WORLD_WIDTH < window_start.x continue;
            if wall.pos.x - WALL_WORLD_WIDTH > window_end.x continue;
            
            if wall.pos.y - WALL_WORLD_HEIGHT > window_end.y continue;
            if wall.pos.y + WALL_WORLD_HEIGHT < window_start.y continue;
            
            array_add(active_walls, wall);
            // Walls are not collidable!
        }
    }
}

item_stack_is_empty :: (item_stack: *ItemStack) -> bool {
    return item_stack == null || item_stack.stack_count == 0;
}

get_stack_capacity_by_item_type :: (item_type: ItemType) -> s32 {
    if #complete item_type == {
        case .DIRT_ITEM;       return DIRT_STACK_CAPACITY;
        case .ROCK_ITEM;       return ROCK_STACK_CAPACITY;
        case .WOOD_ITEM;       return WOOD_STACK_CAPACITY;
        case .COPPER_ORE_ITEM; return COPPER_ORE_STACK_CAPACITY;
        case .WALL_DIRT_ITEM;  return WALL_DIRT_STACK_CAPACITY;
        case .WALL_ROCK_ITEM;  return WALL_ROCK_STACK_CAPACITY;
        case .TORCH;           return TORCH_STACK_CAPACITY;

        case .PICKAXE; #through;
        case .AXE;     #through;
        case .SWORD;   #through;
        case .HAMMER;  #through;
        case .UNSPECIFIED;
            assert(false, "Unspecified item type");
            return -1;
    }
}

get_item_breaking_speed :: (item_type: ItemType) -> float32 {
    if #complete item_type == {
        // Blocks (they don't break anything any faster)
        case .DIRT_ITEM;       return 1;
        case .ROCK_ITEM;       return 1;
        case .WOOD_ITEM;       return 1;
        case .COPPER_ORE_ITEM; return 1;
        case .WALL_DIRT_ITEM;  return 1;
        case .WALL_ROCK_ITEM;  return 1;
        case .TORCH;           return 1;

        // Tools
        case .PICKAXE; return PICKAXE_MINING_MULTIPLIER;
        case .AXE;     return AXE_MINING_MULTIPLIER;
        case .SWORD;   return SWORD_MINING_MULTIPLIER;
        case .HAMMER;  return HAMMER_MINING_MULTIPLIER;

        case .UNSPECIFIED;
            assert(false, "Unspecified item type");
            return -1;
    }
}

get_is_wall :: (block_type: BlockType) -> bool {
    if #complete block_type == {
        case .DIRT;        return false;
        case .GRASS;       return false;
        case .ROCK;        return false;
        case .WOOD;        return false;
        case .TREE;        return false;
        case .TREE_BRANCH; return false;
        case .TREE_TOP;    return false;
        case .COPPER_ORE;  return false;

        case .WALL_DIRT;   return true;
        case .WALL_ROCK;   return true;
    
        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
            return false; // Unreachable
    }
}

get_is_wall_item :: (item_type: ItemType) -> bool {
    if #complete item_type == {
        case .PICKAXE;         return false;
        case .SWORD;           return false;
        case .AXE;             return false;
        case .HAMMER;          return false;
        case .DIRT_ITEM;       return false;
        case .ROCK_ITEM;       return false;
        case .WOOD_ITEM;       return false;
        case .COPPER_ORE_ITEM; return false;
        case .TORCH;           return false;

        case .WALL_DIRT_ITEM;  return true;
        case .WALL_ROCK_ITEM;  return true;
    
        case .UNSPECIFIED;
            assert(false, "Unspecified item type");
            return false; // Unreachable
    }
}

get_texture_map_source_coords_for_entity :: (entity: Entity) -> Vector2 {
    if entity.type == {
        case Block;
            return get_texture_map_source_coords_for_block(cast(Block) entity);

        case Torch;
            // If there are walls on either side, attach it to them, otherwise attach it to the wall behind it.
            // If there's neither walls on one of its sides nor a wall behind it, then we're in an error state.

            south_block_exists, _ := get_neighbor(entity.pos, .SOUTH , false);
            if south_block_exists {
               return Vector2.{ cast(float) (0 * TORCH_MAP_TILE_WIDTH), 0.0 };
            }

            east_block_exists, _ := get_neighbor(entity.pos, .EAST , false);
            if east_block_exists {
               return Vector2.{ cast(float) (2 * TORCH_MAP_TILE_WIDTH), 0.0 };
            }
            
            west_block_exists, _ := get_neighbor(entity.pos, .WEST , false);
            if west_block_exists {
               return Vector2.{ cast(float) (1 * TORCH_MAP_TILE_WIDTH), 0.0 };
            }

            wall_exists, _ := get_neighbor(entity.pos, .CENTER , true);
            if wall_exists {
               return Vector2.{ cast(float) (0 * TORCH_MAP_TILE_WIDTH), 0.0 };
            }

            // @TODO: if torch exists and we hit this point, I think we actually want to destroy it.
            assert(false, "Tried placing a torch down without anything to put it on");
            return Vector2.{}; 

        case;
            assert(false, "You forgot some entity type for which to get source coords");
            return Vector2.{}; 
    }
}

get_texture_map_source_coords_for_block :: (block: Block) -> Vector2 {
    x := -1;
    y := -1;

    // Tree madness
    if block.type == TreeBlock {
        north_exists, north := get_neighbor_tree(block.pos, .NORTH);
        south_exists, south := get_neighbor_tree(block.pos, .SOUTH);
        east_exists,  east  := get_neighbor_tree(block.pos, .EAST );
        west_exists,  west  := get_neighbor_tree(block.pos, .WEST );

        tree_block := cast(TreeBlock) block;
        // Center stump
        if #complete tree_block.tree_block_type == {
            case .TREE_STUMP_CENTER;
                if north_exists && east_exists && west_exists {
                    x = 4;
                    y = cast(int) random_get_within_range(6, 8);
                }
                else if north_exists && east_exists && !west_exists {
                    x = 0;
                    y = cast(int) random_get_within_range(6, 8);
                }
                else if north_exists && !east_exists && west_exists {
                    x = 3;
                    y = cast(int) random_get_within_range(6, 8);
                }
                else if north_exists && !east_exists && !west_exists {
                    x = 0;  
                    y = cast(int) random_get_within_range(0, 2);
                }
                else if !north_exists && east_exists && west_exists {
                    x = 7;
                    y = cast(int) random_get_within_range(6, 8);
                }
                else if !north_exists && east_exists && !west_exists {
                    x = 7;
                    y = cast(int) random_get_within_range(3, 5);
                }
                else if !north_exists && !east_exists && west_exists {
                    x = 7;
                    y = cast(int) random_get_within_range(0, 2);
                }
                else if !north_exists && !east_exists && !west_exists {
                    x = 5;
                    y = cast(int) random_get_within_range(0, 2);
                }
                else {
                    print_vars(north_exists, south_exists, east_exists, west_exists, north, south, east, west);
                    assert(false, "you forgot a case in the condition chain for center tree stump texture coordinates.");
                }

            case .TREE_STUMP_EAST;
                x = 1;
                y = cast(int) random_get_within_range(6, 8);

            case .TREE_STUMP_WEST;
                x = 2;
                y = cast(int) random_get_within_range(6, 8);

            case .TREE_TRUNK_MIDDLE;
                if east_exists && west_exists {
                    x = 5;
                    y = cast(int) random_get_within_range(3, 5);
                }
                if east_exists && !west_exists {
                    x = 3;
                    y = cast(int) random_get_within_range(3, 5);
                }
                if !east_exists && west_exists {
                    x = 4;
                    y = cast(int) random_get_within_range(0, 2);
                }
                else {
                    x = cast(int) random_get_within_range(0, 2);
                    if x == 0 {
                        y = cast(int) random_get_within_range(3, 5);
                    }
                    else if x == 1 {
                        y = cast(int) random_get_within_range(0, 5);
                    }
                    else {
                        y = cast(int) random_get_within_range(3, 5);
                    }
                }

            case .TREE_TRUNK_TOP;
                if east_exists && west_exists {
                    x = 6;
                    y = cast(int) random_get_within_range(6, 8);
                }
                if east_exists && !west_exists {
                    x = 6;
                    y = cast(int) random_get_within_range(3, 5);
                }
                if !east_exists && west_exists {
                    x = 6;
                    y = cast(int) random_get_within_range(0, 2);
                }
                else {
                    x = 0;
                    y = cast(int) random_get_within_range(9, 11);
                }

            case .TREE_TOP;
                x = cast(int) random_get_within_range(0, 2);
                y = 0;

            case .TREE_BRANCH;
                if east_exists && west_exists {
                    assert(false, "Found a branch with tree blocks on both sides. At the time of writing this, I am assuming this is undesirable because how will we know which way to draw the branch? However, it's possible that drawing trees is not as simple as just checking the tiles around whatever block is in question (e.g. we may need designated tree structures with IDs and associated blocks, etc).");
                }
                else if east_exists && !west_exists {
                    x = 0;
                    y = cast(int) random_get_within_range(0, 2);
                }
                else if !east_exists && west_exists {
                    x = 1;
                    y = cast(int) random_get_within_range(0, 2);
                }
                else { // !east_exists && !west_exists
                    assert(false, "Found a branch without tree blocks on either side.");
                }
        }
    }
    else {
        is_wall := get_is_wall(block.block_type);

        north_exists, north := get_neighbor(block.pos, .NORTH, is_wall);
        south_exists, south := get_neighbor(block.pos, .SOUTH, is_wall);
        east_exists,  east  := get_neighbor(block.pos, .EAST , is_wall);
        west_exists,  west  := get_neighbor(block.pos, .WEST , is_wall);

        if north_exists && south_exists && east_exists && west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = cast(int) random_get_within_range(1, 3);
                y = 1;
            }
            // Block-entrappable blocks (rock, ore, etc).
            else {
                if north.block_type == .DIRT && south.block_type == .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    // grass magically lines up
                    x = cast(int) random_get_within_range(6, 8);
                    y = 11;
                }
                else if north.block_type == .DIRT && south.block_type == .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(11, 13);
                        y = 17;
                    }
                    else {
                        x = 12;
                        y = cast(int) random_get_within_range(8, 10);
                    }
                }
                else if north.block_type == .DIRT && south.block_type == .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(8, 10);
                        y = 17;
                    }
                    else {
                        x = 12;
                        y = cast(int) random_get_within_range(5, 7);
                    }
                }
                else if north.block_type == .DIRT && south.block_type == .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    x = cast(int) random_get_within_range(8, 10);
                    y = 10;
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(11, 13);
                        y =  15;
                    } else {
                        x = 11;
                        y = cast(int) random_get_within_range(5, 7);
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    random_number := cast(int) random_get_within_range(1, 3);
                    x = 3;

                    if random_number == 1 {
                        y = 5;
                    }
                    else if random_number == 2 {
                        y = 7;
                    }
                    else if random_number == 3 {
                        y = 9;
                    }
                    else {
                        assert(false, "dawg");
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    random_number := cast(int) random_get_within_range(0, 2);

                    x = 2;

                    if random_number == 0 {
                        y = 5;
                    }
                    else if random_number == 1 {
                        y = 7;
                    }
                    else {
                        y = 9;
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    x = cast(int) random_get_within_range(8, 10);
                    y = 6;
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(11, 13);
                        y = 16;
                    } else {
                        x = 11;
                        y = cast(int) random_get_within_range(8, 10);
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    // grass works like this too
                    random_number := cast(int) random_get_within_range(1, 3);
                    x = 3;

                    if random_number == 1 {
                        y = 6;
                    }
                    else if random_number == 2 {
                        y = 8;
                    }
                    else if random_number == 3 {
                        y = 10;
                    }
                    else {
                        assert(false, "dawg");
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    // grass good to go
                    random_number := cast(int) random_get_within_range(1, 3);
                    x = 2;

                    if random_number == 1 {
                        y = 6;
                    }
                    else if random_number == 2 {
                        y = 8;
                    }
                    else if random_number == 3 {
                        y = 10;
                    }
                    else {
                        assert(false, "dawg");
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 1;
                    } else {
                        x = cast(int) random_get_within_range(8, 10);
                        y = 5;
                    }
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    // grass works with this
                    x = 10;
                    y = cast(int) random_get_within_range(7, 9);
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    // grass works with this
                    x = 8;
                    y = cast(int) random_get_within_range(7, 9);
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    x = 9;
                    y = cast(int) random_get_within_range(7, 9);
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    x = cast(int) random_get_within_range(1, 3);
                    y = 1;
                }
            }
        }
        else if north_exists && south_exists && east_exists && !west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = 0;
                y = cast(int) random_get_within_range(0, 2);
            }
            // Block-entrappable blocks (rock, ore, etc).
            else {
                if north.block_type == .DIRT && south.block_type == .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 0;
                        y = cast(int) random_get_within_range(15, 17);
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if north.block_type == .DIRT && south.block_type == .DIRT && east.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = 0;
                        y = cast(int) random_get_within_range(15, 17);
                    } else {
                        x = 9;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 4;
                        y = cast(int) random_get_within_range(8, 10);
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 0;
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && east.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = 4;
                        y = cast(int) random_get_within_range(8, 10);
                    } else {
                        x = 4;
                        y = cast(int) random_get_within_range(8, 10);
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 4;
                        y = cast(int) random_get_within_range(5, 7);
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 3;
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && east.block_type != .DIRT {
                    // grass actually magically lines up for this one
                    x = 4;
                    y = cast(int) random_get_within_range(5, 7);
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 0;
                        y = cast(int) random_get_within_range(0, 2);
                    } else {
                        x = cast(int) random_get_within_range(13, 15);
                        y = 2;
                    }
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && east.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);

                        y = 13; 

                        if random_number == 0 {
                            x = 7;
                        } else if random_number == 1 {
                            x = 10;
                        } else {
                            x = 13;
                        }
                    } else {
                        x = 0;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
            }
        }
        else if north_exists && south_exists && !east_exists && west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = 4;
                y = cast(int) random_get_within_range(0, 2);
            } else {
                if north.block_type == .DIRT && south.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 1;
                        y = cast(int) random_get_within_range(15, 17);
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if north.block_type == .DIRT && south.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = 1;
                        y = cast(int) random_get_within_range(15, 17);
                    } else {
                        x = 12;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 5;
                        y = cast(int) random_get_within_range(8, 10);
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 0;
                    }
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = 5;
                        y = cast(int) random_get_within_range(8, 10);
                    } else {
                        x = 5;
                        y = cast(int) random_get_within_range(8, 10);
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 5;
                        y = cast(int) random_get_within_range(5, 7);
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 3;
                    }
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = 5;
                        y = cast(int) random_get_within_range(5, 7);
                    } else {
                        x = 5;
                        y = cast(int) random_get_within_range(5, 7);
                    }
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 4;
                        y = cast(int) random_get_within_range(0, 2);
                    } else {
                        x = cast(int) random_get_within_range(13, 15);
                        y = 3;
                    }
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 13;

                        if random_number == 0 {
                            x = 9;
                        }
                        else if random_number == 1 {
                            x = 12;
                        }
                        else {
                            x = 15;
                        }
                    } else {
                        x = 4;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
            }
        }
        else if north_exists && south_exists && !east_exists && !west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = 5;
                y = cast(int) random_get_within_range(0, 2);
            }
            else {
                if north.block_type == .DIRT && south.block_type == .DIRT {
                    x = 6;
                    y = cast(int) random_get_within_range(12, 14);
                }
                else if north.block_type == .DIRT && south.block_type != .DIRT {
                    x = 7;
                    y = cast(int) random_get_within_range(8, 10);
                }
                else if north.block_type != .DIRT && south.block_type == .DIRT {
                    x = 7;
                    y = cast(int) random_get_within_range(5, 7);
                }
                else if north.block_type != .DIRT && south.block_type != .DIRT {
                    x = 5;
                    y = cast(int) random_get_within_range(0, 2);
                }
            }
        }
        else if north_exists && !south_exists && east_exists && west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = cast(int) random_get_within_range(1, 3);
                y = 2;
            }
            else {
                if north.block_type == .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(2, 4);
                        y = 16; 
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;   
                    }
                }
                else if north.block_type == .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(3, 5);
                        y = 12; 
                    } else {
                        x = 12;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if north.block_type == .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(0, 2);
                        y = 12; 
                    } else {
                        x = 9;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if north.block_type == .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(1, 3);
                        y = 2; 
                    } else {
                        x = cast(int) random_get_within_range(13, 15);
                        y = 1;
                    }
                }
                else if north.block_type != .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(2, 4);
                        y = 16; 
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 3;
                    }
                }
                else if north.block_type != .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(3, 5);
                        y = 12; 
                    } else {
                        x = cast(int) random_get_within_range(3, 5);
                        y = 12;
                    }
                }
                else if north.block_type != .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(0, 2);
                        y = 12; 
                    } else {
                        x = cast(int) random_get_within_range(0, 2);
                        y = 12;
                    }
                }
                else if north.block_type != .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 14;
                        if random_number == 0 {
                            x = 8;
                        }
                        else if random_number == 1 {
                            x = 11;
                        }
                        else {// if random_number == 2 {
                            x = 14;
                        }
                    } else {
                        x = cast(int) random_get_within_range(1, 3);
                        y = 2;
                    }
                }
            }
        }
        else if north_exists && !south_exists && east_exists && !west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                random_number := cast(int) random_get_within_range(0, 2);
                
                y = 4;
                if random_number == 0 {
                    x = 0;
                }
                else if random_number == 1 {
                    x = 2;
                }
                else {// if random_number == 2 {
                    x = 4;
                }
            }
            else {
                if north.block_type == .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if north.block_type == .DIRT && east.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    } else {
                        x = 9;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if north.block_type != .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 3;
                    }
                }
                else if north.block_type != .DIRT && east.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 14;
                        if random_number == 0 {
                            x = 7;
                        }
                        else if random_number == 1 {
                            x = 10;
                        }
                        else {// if random_number == 2 {
                            x = 13;
                        }
                    } else {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 4;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    }
                }
            }
        }
        else if north_exists && !south_exists && !east_exists && west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                random_number := cast(int) random_get_within_range(0, 2);
                
                y = 4;
                if random_number == 0 {
                    x = 1;
                }
                else if random_number == 1 {
                    x = 3;
                }
                else {// if random_number == 2 {
                    x = 5;
                }
            }
            else {
                if north.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if north.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    } else {
                        x = 12;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if north.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 3;
                    }
                }
                else if north.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 14;
                        if random_number == 0 {
                            x = 9;
                        }
                        else if random_number == 1 {
                            x = 12;
                        }
                        else {// if random_number == 2 {
                            x = 15;
                        }
                    } else {
                        random_number := cast(int) random_get_within_range(0, 2);
                
                        y = 4;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    }
                }
            }
        }
        else if north_exists && !south_exists && !east_exists && !west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = cast(int) random_get_within_range(6, 8);
                y = 3;
            }
            else {
                if north.block_type == .DIRT {
                    x = 6;
                    y = cast(int) random_get_within_range(8, 10);
                } else {
                    x = cast(int) random_get_within_range(6, 8);
                    y = 3;
                }
            }
        }
        else if !north_exists && south_exists && east_exists && west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = cast(int) random_get_within_range(1, 3);
                y = 0;
            }
            else {
                if south.block_type == .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(2, 4);
                        y = 15;
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if south.block_type == .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(3, 5);
                        y = 11;
                    } else {
                        x = 12;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if south.block_type == .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(0, 2);
                        y = 11;
                    } else {
                        x = 9;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if south.block_type == .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(1, 3);
                        y = 0;
                    } else {
                        x = cast(int) random_get_within_range(13, 15);
                        y = 0;
                    }
                }
                else if south.block_type != .DIRT && east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(2, 4);
                        y = 15;
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 0;
                    }
                }
                else if south.block_type != .DIRT && east.block_type == .DIRT && west.block_type != .DIRT {
                    x = cast(int) random_get_within_range(3, 5);
                    y = 11;
                }
                else if south.block_type != .DIRT && east.block_type != .DIRT && west.block_type == .DIRT {
                    x = cast(int) random_get_within_range(0, 2);
                    y = 11;
                }
                else if south.block_type != .DIRT && east.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number: = cast(int) random_get_within_range(1, 3);
                        
                        y = 12;

                        if random_number == 1 {
                            x = 8;
                        }
                        else if random_number == 2 {
                            x = 11;
                        }
                        else if random_number == 3 {
                            x = 14;
                        }
                    } else {
                        x = cast(int) random_get_within_range(1, 3);
                        y = 0;
                    }
                }
            }
        }
        else if !north_exists && south_exists && east_exists && !west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT  || block.block_type == .WOOD {
                random_number := cast(int) random_get_within_range(0, 2);
                
                y = 3;
                if random_number == 0 {
                    x = 0;
                }
                else if random_number == 1 {
                    x = 2;
                }
                else {// if random_number == 2 {
                    x = 4;
                }
            }
            else {
                if south.block_type == .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if south.block_type == .DIRT && east.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    } else {
                        x = 9;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if south.block_type != .DIRT && east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 0;
                        }
                        else if random_number == 1 {
                            x = 2;
                        }
                        else {// if random_number == 2 {
                            x = 4;
                        }
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 0;
                    }
                }
                else if south.block_type != .DIRT && east.block_type != .DIRT {
                    random_number := cast(int) random_get_within_range(0, 2);
                
                    y = 3;
                    if random_number == 0 {
                        x = 0;
                    }
                    else if random_number == 1 {
                        x = 2;
                    }
                    else {// if random_number == 2 {
                        x = 4;
                    }
                }
            }
        }
        else if !north_exists && south_exists && !east_exists && west_exists {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                random_number := cast(int) random_get_within_range(0, 2);
                
                y = 3;
                if random_number == 0 {
                    x = 1;
                }
                else if random_number == 1 {
                    x = 3;
                }
                else {// if random_number == 2 {
                    x = 5;
                }
            }
            else {
                if south.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if south.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    } else {
                        x = 12;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if south.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    } else {
                        x = cast(int) random_get_within_range(6, 8);
                        y = 0;
                    }
                }
                else if south.block_type != .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(8, 10);
                        y = 15;
                    } else {
                        random_number := cast(int) random_get_within_range(0, 2);
                    
                        y = 3;
                        if random_number == 0 {
                            x = 1;
                        }
                        else if random_number == 1 {
                            x = 3;
                        }
                        else {// if random_number == 2 {
                            x = 5;
                        }
                    }
                }
            }
        }
        else if !north_exists && south_exists && !east_exists && !west_exists  {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = cast(int) random_get_within_range(6, 8);
                y = 0;
            }
            else {
                if south.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = 6;
                        y = cast(int) random_get_within_range(5, 7);
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else {
                    x = cast(int) random_get_within_range(6, 8);
                    y = 0;
                }
            }
        }
        else if !north_exists && !south_exists && east_exists && west_exists   {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = cast(int) random_get_within_range(6, 8);
                y = 4;
            }
            else {
                if east.block_type == .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 11;
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else if east.block_type == .DIRT && west.block_type != .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(3, 5);
                        y = 14;
                    } else {
                        x = 12;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if east.block_type != .DIRT && west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(0, 2);
                        y = 14;
                    } else {
                        x = 9;
                        y = cast(int) random_get_within_range(0, 2);
                    }
                }
                else if east.block_type != .DIRT && west.block_type != .DIRT {
                    x = cast(int) random_get_within_range(6, 8);
                    y = 4;
                }
            }
        }
        else if !north_exists && !south_exists && east_exists && !west_exists  {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = 9;
                y = cast(int) random_get_within_range(0, 2);
            }
            else {
                if east.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(3, 5);
                        y = 13;
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else {
                    x = 9;
                    y = cast(int) random_get_within_range(0, 2);
                }
            }
        }
        else if !north_exists && !south_exists && !east_exists && west_exists  {
            if block.block_type == .DIRT || block.block_type == .WALL_DIRT || block.block_type == .WOOD {
                x = 12;
                y = cast(int) random_get_within_range(0, 2);
            }
            else {
                if west.block_type == .DIRT {
                    if block.block_type == .GRASS {
                        x = cast(int) random_get_within_range(0, 2);
                        y = 13;
                    } else {
                        x = cast(int) random_get_within_range(9, 11);
                        y = 3;
                    }
                }
                else {
                    x = 12;
                    y = cast(int) random_get_within_range(0, 2);
                }
            }
        }
        else if !north_exists && !south_exists && !east_exists && !west_exists {
            x = cast(int) random_get_within_range(9, 11);
            y = 3;
        }
        else {
            print_vars(north_exists, south_exists, east_exists, west_exists);
            assert(false, "You forgot some combination of north south east west");
        }
    }

    width  := -1;
    height := -1;

    if #complete block.block_type == {
        case .DIRT;       
            width  = DIRT_MAP_TILE_WIDTH;
            height = DIRT_MAP_TILE_HEIGHT;
        case .GRASS;      
            width  = GRASS_MAP_TILE_WIDTH;
            height = GRASS_MAP_TILE_HEIGHT;
        case .ROCK;       
            width  = ROCK_MAP_TILE_WIDTH;
            height = ROCK_MAP_TILE_HEIGHT;
        case .WOOD;       
            width  = WOOD_MAP_TILE_WIDTH;
            height = WOOD_MAP_TILE_HEIGHT;
        // TODO: move?
        case .TREE;       
            width  = TREE_MAP_TILE_WIDTH;
            height = TREE_MAP_TILE_HEIGHT;
        case .TREE_BRANCH;
            width  = TREE_BRANCH_MAP_TILE_WIDTH;
            height = TREE_BRANCH_MAP_TILE_HEIGHT;
        case .TREE_TOP;
            width  = TREE_TOP_MAP_TILE_WIDTH;
            height = TREE_TOP_MAP_TILE_HEIGHT;
        case .COPPER_ORE; 
            width  = COPPER_ORE_MAP_TILE_WIDTH;
            height = COPPER_ORE_MAP_TILE_HEIGHT;
        case .WALL_DIRT; 
            width  = WALL_DIRT_MAP_TILE_WIDTH;
            height = WALL_DIRT_MAP_TILE_HEIGHT;
        case .WALL_ROCK; 
            width  = WALL_ROCK_MAP_TILE_WIDTH;
            height = WALL_ROCK_MAP_TILE_HEIGHT;
        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
    }

    assert(x >= 0 && y >= 0, "Something is fucked up with your texture coordinates (%, %).", x, y);

    return Vector2.{ cast(float) (x * width), cast(float) (y * height) };
}

get_texture_map_for_entity :: (entity: Entity) -> texture: Texture, source: Rectangle {
    if entity.type == {
        case Block;
            map_texture, map_source := get_texture_map_for_block(cast(Block) entity);
            return map_texture, map_source;

        case Torch;
            map_source := Rectangle.{
                get_texture_map_source_coords_for_entity(entity).x,
                0.0,
                TORCH_MAP_TILE_WIDTH  - TORCH_MAP_TILE_PADDING,
                TORCH_MAP_TILE_HEIGHT - TORCH_MAP_TILE_PADDING,
            };

            return torch_map, map_source;
        
        case;
            assert(false, "You forgot some entity type to get a texture map for");
            return Texture.{}, Rectangle.{};
    }
}

get_texture_map_for_block :: (block: Block) -> texture: Texture, source: Rectangle {
    map_texture : Texture;
    map_source  : Rectangle;

    source_pos := ifx block.texture_map_source_pos.x == -1 && block.texture_map_source_pos.y == -1
        then get_texture_map_source_coords_for_block(block)
        else block.texture_map_source_pos;

    if block.block_type == {
        case .DIRT;
            map_texture = dirt_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                DIRT_MAP_TILE_WIDTH - DIRT_MAP_TILE_PADDING,
                DIRT_MAP_TILE_HEIGHT - DIRT_MAP_TILE_PADDING,
            };

        case .GRASS;
            map_texture = grass_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                GRASS_MAP_TILE_WIDTH - GRASS_MAP_TILE_PADDING,
                GRASS_MAP_TILE_HEIGHT - GRASS_MAP_TILE_PADDING,
            };

        case .ROCK;
            map_texture = rock_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                ROCK_MAP_TILE_WIDTH - ROCK_MAP_TILE_PADDING,
                ROCK_MAP_TILE_HEIGHT - ROCK_MAP_TILE_PADDING,
            };

        case .WOOD;
            map_texture = wood_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                WOOD_MAP_TILE_WIDTH - WOOD_MAP_TILE_PADDING,
                WOOD_MAP_TILE_HEIGHT - WOOD_MAP_TILE_PADDING,
            };

        case .TREE;
            map_texture = tree_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                TREE_MAP_TILE_WIDTH  - TREE_MAP_TILE_PADDING,
                TREE_MAP_TILE_HEIGHT - TREE_MAP_TILE_PADDING,
            };

        case .TREE_BRANCH;
            map_texture = tree_branch_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                TREE_BRANCH_MAP_TILE_WIDTH  - TREE_BRANCH_MAP_TILE_PADDING,
                TREE_BRANCH_MAP_TILE_HEIGHT - TREE_BRANCH_MAP_TILE_PADDING,
            };

        case .TREE_TOP;
            map_texture = tree_top_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                TREE_TOP_MAP_TILE_WIDTH  - TREE_TOP_MAP_TILE_PADDING,
                TREE_TOP_MAP_TILE_HEIGHT - TREE_TOP_MAP_TILE_PADDING,
            };

        case .COPPER_ORE;
            map_texture = copper_ore_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                COPPER_ORE_MAP_TILE_WIDTH  - COPPER_ORE_MAP_TILE_PADDING,
                COPPER_ORE_MAP_TILE_HEIGHT - COPPER_ORE_MAP_TILE_PADDING,
            };

        case .WALL_DIRT;
            map_texture = wall_dirt_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                WALL_DIRT_MAP_TILE_WIDTH  - WALL_DIRT_MAP_TILE_PADDING,
                WALL_DIRT_MAP_TILE_HEIGHT - WALL_DIRT_MAP_TILE_PADDING,
            };

        case .WALL_ROCK;
            map_texture = wall_rock_map;
            map_source  = Rectangle.{
                source_pos.x, source_pos.y,
                WALL_ROCK_MAP_TILE_WIDTH  - WALL_ROCK_MAP_TILE_PADDING,
                WALL_ROCK_MAP_TILE_HEIGHT - WALL_ROCK_MAP_TILE_PADDING,
            };

        case;
            assert(false, "You forgot a block type in your switch statement");
    }

    return map_texture, map_source;
};

get_texture_map_by_item_type :: (item_type: ItemType, is_facing_left: bool = false) -> texture: Texture, source: Rectangle {
    map_texture : Texture;
    map_source  : Rectangle;

    if #complete item_type == {
        case .PICKAXE;
            map_texture = pickaxe_texture;
            map_source  = Rectangle.{ 0, 0, PICKAXE_TEXTURE_WIDTH, PICKAXE_TEXTURE_HEIGHT };

        case .AXE;
            map_texture = axe_texture;
            map_source  = Rectangle.{ 0, 0, AXE_TEXTURE_WIDTH, AXE_TEXTURE_HEIGHT };

        case .SWORD;
            map_texture = sword_texture;
            map_source  = Rectangle.{ 0, 0, SWORD_TEXTURE_WIDTH, SWORD_TEXTURE_HEIGHT };

        case .HAMMER;
            map_texture = hammer_texture;
            map_source  = Rectangle.{ 0, 0, HAMMER_TEXTURE_WIDTH, HAMMER_TEXTURE_HEIGHT };

        case .TORCH;
            map_texture = torch_texture;
            map_source  = Rectangle.{ 0, 0, TORCH_TEXTURE_WIDTH, TORCH_TEXTURE_HEIGHT };

        case .DIRT_ITEM;
            map_texture = dirt_item_texture;
            map_source = Rectangle.{
                0, 0, DIRT_ITEM_TEXTURE_WIDTH, DIRT_ITEM_TEXTURE_HEIGHT,
            };

        case .ROCK_ITEM;
            map_texture = rock_item_texture;
            map_source = Rectangle.{
                0, 0, ROCK_ITEM_TEXTURE_WIDTH, ROCK_ITEM_TEXTURE_HEIGHT,
            };

        case .WOOD_ITEM;
            map_texture = wood_item_texture;
            map_source = Rectangle.{
                0, 0, WOOD_ITEM_TEXTURE_WIDTH, WOOD_ITEM_TEXTURE_HEIGHT,
            };

        case .COPPER_ORE_ITEM;
            map_texture = copper_ore_item_texture;
            map_source = Rectangle.{
                0, 0, COPPER_ORE_ITEM_TEXTURE_WIDTH, COPPER_ORE_ITEM_TEXTURE_HEIGHT,
            };

        case .WALL_DIRT_ITEM;
            map_texture = wall_dirt_item_texture;
            map_source = Rectangle.{
                0, 0, DIRT_ITEM_TEXTURE_WIDTH, DIRT_ITEM_TEXTURE_HEIGHT,
            };

        case .WALL_ROCK_ITEM;
            map_texture = wall_rock_item_texture;
            map_source = Rectangle.{
                0, 0, ROCK_ITEM_TEXTURE_WIDTH, ROCK_ITEM_TEXTURE_HEIGHT,
            };

        case .UNSPECIFIED;
            assert(false, "Unspecified item type");
    }

    if is_facing_left map_source.width *= -1;

    return map_texture, map_source;
}

item_type_is_stackable :: (item_type: ItemType) -> bool {
    if #complete item_type == {
        case .DIRT_ITEM;       return true;
        case .ROCK_ITEM;       return true;
        case .WOOD_ITEM;       return true;
        case .COPPER_ORE_ITEM; return true;
        case .WALL_DIRT_ITEM;  return true;
        case .WALL_ROCK_ITEM;  return true;
        case .PICKAXE;         return false;
        case .AXE;             return false;
        case .SWORD;           return false;
        case .HAMMER;          return false;
        case .TORCH;           return true;

        case .UNSPECIFIED; #through;
        case;
            print_vars(item_type);
            assert(false, "Forgot an item type in your switch statement");
            return false; // Unreachable
    } 
}

get_item_world_length :: (item_type: ItemType) -> float {
    if #complete item_type == {
        // Blocks
        case .DIRT_ITEM;       return WIELDED_BLOCK_WORLD_LENGTH;
        case .ROCK_ITEM;       return WIELDED_BLOCK_WORLD_LENGTH;
        case .WOOD_ITEM;       return WIELDED_BLOCK_WORLD_LENGTH;
        case .COPPER_ORE_ITEM; return WIELDED_BLOCK_WORLD_LENGTH;
        case .WALL_DIRT_ITEM;  return WIELDED_BLOCK_WORLD_LENGTH;
        case .WALL_ROCK_ITEM;  return WIELDED_BLOCK_WORLD_LENGTH;

        // Items
        case .PICKAXE; return WIELDED_TOOL_WORLD_LENGTH;
        case .AXE;     return WIELDED_TOOL_WORLD_LENGTH;
        case .SWORD;   return WIELDED_TOOL_WORLD_LENGTH;
        case .HAMMER;  return WIELDED_TOOL_WORLD_LENGTH;
        case .TORCH;   return WIELDED_TORCH_WORLD_LENGTH;

        case .UNSPECIFIED;
            assert(false, "Unspecified item type");
            return -1; // Unreachable
    } 
}

get_block_weak_to_tool :: (block_type: BlockType) -> ItemType {
    if #complete block_type == {
        case .DIRT;        return .PICKAXE;
        case .GRASS;       return .PICKAXE;
        case .ROCK;        return .PICKAXE;
        case .WOOD;        return .AXE;
        case .TREE;        return .AXE;
        case .TREE_BRANCH; return .AXE;
        case .TREE_TOP;    return .AXE;
        case .COPPER_ORE;  return .PICKAXE;
        
        case .WALL_DIRT;   return .HAMMER;
        case .WALL_ROCK;   return .HAMMER;

        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
            return .ROCK_ITEM; // Unreachable
    } 
}

item_type_to_entity_type :: (item_type: ItemType) -> Type {
    if #complete item_type == {
        case .DIRT_ITEM;       return Block;
        case .ROCK_ITEM;       return Block;
        case .WOOD_ITEM;       return Block;
        case .COPPER_ORE_ITEM; return Block;
        case .WALL_DIRT_ITEM;  return Block;
        case .WALL_ROCK_ITEM;  return Block;

        case .TORCH; return Torch;

        case .PICKAXE; #through;
        case .AXE;     #through;
        case .SWORD;   #through;
        case .HAMMER;  #through;
        case .UNSPECIFIED;
            assert(false, "Unspecified item type, or tried to place unplaceable thing");
            return Entity; // Unreachable
    }
}

item_type_to_block_type :: (item_type: ItemType) -> BlockType {
    if #complete item_type == {
        case .DIRT_ITEM;       return BlockType.DIRT;
        case .ROCK_ITEM;       return BlockType.ROCK;
        case .WOOD_ITEM;       return BlockType.WOOD;
        case .COPPER_ORE_ITEM; return BlockType.COPPER_ORE;
        case .WALL_DIRT_ITEM;  return BlockType.WALL_DIRT;
        case .WALL_ROCK_ITEM;  return BlockType.WALL_ROCK;
        case .TORCH;           return BlockType.ROCK; // @TODO: probably need a concept for non block placeable things

        case .PICKAXE; #through;
        case .AXE;     #through;
        case .SWORD;   #through;
        case .HAMMER;  #through;
        case .UNSPECIFIED;
            assert(false, "Didn't specify item type to turn into a block type, or tried to place unplaceable thing");
            return BlockType.DIRT; // Unreachable
    }
}

block_type_to_item_type :: (block_type: BlockType) -> ItemType {
    if #complete block_type == {
        case .DIRT;        return ItemType.DIRT_ITEM;
        case .GRASS;       return ItemType.DIRT_ITEM;
        case .ROCK;        return ItemType.ROCK_ITEM;
        case .WOOD;        return ItemType.WOOD_ITEM;
        case .TREE;        return ItemType.WOOD_ITEM;
        case .TREE_BRANCH; return ItemType.WOOD_ITEM;
        case .TREE_TOP;    return ItemType.WOOD_ITEM;
        case .COPPER_ORE;  return ItemType.COPPER_ORE_ITEM;
        case .WALL_DIRT;   return ItemType.WALL_DIRT_ITEM;
        case .WALL_ROCK;   return ItemType.WALL_ROCK_ITEM;

        case .UNSPECIFIED;
            assert(false, "Unspecified block type");
            return ItemType.UNSPECIFIED; // Unreachable
    }
}

TryToAddToInventoryReturnStatus :: enum u16 {
    SUCCESS;
    INVENTORY_FULL;
}

// @TODO: might need a quantity param
try_to_add_to_inventory :: (inventory: *Inventory, item_type : ItemType) -> TryToAddToInventoryReturnStatus {
    // First, try to find an existing stack that has room.
    for *inventory.item_stacks {
        if it.item_type == item_type {
            if it.stack_count < it.stack_capacity {
                it.stack_count += 1;
                return TryToAddToInventoryReturnStatus.SUCCESS;
            }
        }
    }

    // If there is no existing stack with space, then just try to find an empty slot.
    for *inventory.item_stacks {
        if item_stack_is_empty(it) {
            it.item_type      = item_type;
            it.stack_count    = 1;
            it.stack_capacity = get_stack_capacity_by_item_type(item_type);

            return TryToAddToInventoryReturnStatus.SUCCESS;
        }
    }

    // If there are neither existing stacks with space nor empty slots, we can't add the
    // block to the inventory.
    return TryToAddToInventoryReturnStatus.INVENTORY_FULL;
}

// This function assumes that there are enough mats in your inventory to fully remove the item_count and
// crashes the program if it can't.
remove_from_inventory :: (inventory: *Inventory, item_type: ItemType, item_count: s32) {
    count_to_remove := item_count;
    
    // First, try to find an existing stack that has room.
    for *inventory.item_stacks {
        if it.item_type == item_type {
            // If the stack has more count than we need to remove, then we wanna remove the whole count_to_remove.
            // If it doesn't, then we want to remove the stack's count and continue onto the next stack.
            to_remove_from_this_stack := min(count_to_remove, it.stack_count);
            
            count_to_remove -= to_remove_from_this_stack;
            it.stack_count  -= to_remove_from_this_stack;

            assert(count_to_remove >= 0, "Count to remove is negative, you fucked up your math or something");

            if count_to_remove == 0 break;
        }
    }

    assert(count_to_remove == 0, "Ended remove_from_inventory with more count to remove. remove_from_inventory assumes that the inventory contains enough mats to remove the supplied count. item_type: %, item_count: %, count_to_remove: %", item_type, item_count, count_to_remove);
}

get_neighbor :: (pos: Vector2, direction: Direction, is_wall: bool) -> neighbor_exists: bool, neighbor: *Block {
    potential_neighbor_pos: Vector2;
    if #complete direction == {
        case .NORTH;      potential_neighbor_pos = Vector2.{ pos.x,                     pos.y - BLOCK_WORLD_HEIGHT };
        case .NORTH_EAST; potential_neighbor_pos = Vector2.{ pos.x + BLOCK_WORLD_WIDTH, pos.y - BLOCK_WORLD_HEIGHT };
        case .NORTH_WEST; potential_neighbor_pos = Vector2.{ pos.x - BLOCK_WORLD_WIDTH, pos.y - BLOCK_WORLD_HEIGHT };
        case .SOUTH;      potential_neighbor_pos = Vector2.{ pos.x,                     pos.y + BLOCK_WORLD_HEIGHT };
        case .SOUTH_EAST; potential_neighbor_pos = Vector2.{ pos.x + BLOCK_WORLD_WIDTH, pos.y + BLOCK_WORLD_HEIGHT };
        case .SOUTH_WEST; potential_neighbor_pos = Vector2.{ pos.x - BLOCK_WORLD_WIDTH, pos.y + BLOCK_WORLD_HEIGHT };
        case .EAST;       potential_neighbor_pos = Vector2.{ pos.x + BLOCK_WORLD_WIDTH, pos.y };
        case .WEST;       potential_neighbor_pos = Vector2.{ pos.x - BLOCK_WORLD_WIDTH, pos.y };
        case .CENTER;     potential_neighbor_pos = Vector2.{ pos.x,                     pos.y };
    }
    
    if is_wall {
        neighbor_exists, neighbor := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(potential_neighbor_pos));
        return neighbor_exists, neighbor;
    } else {
        neighbor_exists, neighbor := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(potential_neighbor_pos));
        neighbor_exists = neighbor_exists && neighbor.type == Block; // TODO: feels like there's some elegant solution here that I'm not seeing
        return neighbor_exists, neighbor;
    }
}

get_neighbor_torch :: (pos: Vector2, direction: Direction) -> neighbor_exists: bool, neighbor: *Torch {
    potential_neighbor_pos: Vector2;
    if #complete direction == {
        case .NORTH;      potential_neighbor_pos = Vector2.{ pos.x,                     pos.y - TORCH_WORLD_HEIGHT };
        case .NORTH_EAST; potential_neighbor_pos = Vector2.{ pos.x + TORCH_WORLD_WIDTH, pos.y - TORCH_WORLD_HEIGHT };
        case .NORTH_WEST; potential_neighbor_pos = Vector2.{ pos.x - TORCH_WORLD_WIDTH, pos.y - TORCH_WORLD_HEIGHT };
        case .SOUTH;      potential_neighbor_pos = Vector2.{ pos.x,                     pos.y + TORCH_WORLD_HEIGHT };
        case .SOUTH_EAST; potential_neighbor_pos = Vector2.{ pos.x + TORCH_WORLD_WIDTH, pos.y + TORCH_WORLD_HEIGHT };
        case .SOUTH_WEST; potential_neighbor_pos = Vector2.{ pos.x - TORCH_WORLD_WIDTH, pos.y + TORCH_WORLD_HEIGHT };
        case .EAST;       potential_neighbor_pos = Vector2.{ pos.x + TORCH_WORLD_WIDTH, pos.y };
        case .WEST;       potential_neighbor_pos = Vector2.{ pos.x - TORCH_WORLD_WIDTH, pos.y };
        case .CENTER;     potential_neighbor_pos = Vector2.{ pos.x,                     pos.y };
    }

    neighbor_exists, neighbor := table_find_new(*global_torch_pos_to_torch, vector2_to_string_temp(potential_neighbor_pos));
    return neighbor_exists, neighbor;
}

get_neighbor_tree :: (pos: Vector2, direction: Direction) -> neighbor_exists: bool, neighbor: *TreeBlock {
    potential_neighbor_pos: Vector2;
    if #complete direction == {
        case .NORTH;      potential_neighbor_pos = Vector2.{ pos.x,                     pos.y - BLOCK_WORLD_HEIGHT };
        case .NORTH_EAST; potential_neighbor_pos = Vector2.{ pos.x + BLOCK_WORLD_WIDTH, pos.y - BLOCK_WORLD_HEIGHT };
        case .NORTH_WEST; potential_neighbor_pos = Vector2.{ pos.x - BLOCK_WORLD_WIDTH, pos.y - BLOCK_WORLD_HEIGHT };
        case .SOUTH;      potential_neighbor_pos = Vector2.{ pos.x,                     pos.y + BLOCK_WORLD_HEIGHT };
        case .SOUTH_EAST; potential_neighbor_pos = Vector2.{ pos.x + BLOCK_WORLD_WIDTH, pos.y + BLOCK_WORLD_HEIGHT };
        case .SOUTH_WEST; potential_neighbor_pos = Vector2.{ pos.x - BLOCK_WORLD_WIDTH, pos.y + BLOCK_WORLD_HEIGHT };
        case .EAST;       potential_neighbor_pos = Vector2.{ pos.x + BLOCK_WORLD_WIDTH, pos.y };
        case .WEST;       potential_neighbor_pos = Vector2.{ pos.x - BLOCK_WORLD_WIDTH, pos.y };
        case .CENTER;     potential_neighbor_pos = Vector2.{ pos.x,                     pos.y };
    }

    neighbor_exists, neighbor := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(potential_neighbor_pos));
    neighbor_exists = neighbor_exists && neighbor.type == TreeBlock;
    return neighbor_exists, cast(*TreeBlock) neighbor;
}

// @TODO: max_hops is probably the way to stop the stack overflows
get_and_recursively_set_block_neighbor_counts :: (block: *Block, direction: Direction) -> s32 {
    neighbor_block_exists, neighbor_block := get_neighbor(block.pos, direction, false);
    neighbor_wall_exists,  neighbor_wall  := get_neighbor(block.pos, direction, true);

    neighbor_block_is_relevant := neighbor_block_exists && neighbor_block.type != TreeBlock;
    neighbor_wall_is_relevant  := !neighbor_block_is_relevant && neighbor_wall_exists;

    // @TODO: DRY this up?
    if direction == {
        case .NORTH;
            if neighbor_block_is_relevant {
                // If this block already knows its north neighbor count, we don't need to keep going
                if neighbor_block.neighbor_north_count > -1 {
                    result := neighbor_block.neighbor_north_count + 1;
                    block.neighbor_north_count = result;
                    return result;
                }
                else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_block, direction) + 1;
                    block.neighbor_north_count = result;
                    return result;
                }
            }
            else if neighbor_wall_is_relevant {
                // If this block already knows its north neighbor count, we don't need to keep going
                if neighbor_wall.neighbor_north_count > -1 {
                    result := neighbor_wall.neighbor_north_count + 1;
                    block.neighbor_north_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_wall, direction) + 1;
                    block.neighbor_north_count = result;
                    return result;
                }
            }
            else {
                block.neighbor_north_count = 0;
                block.shadow = 0;
                return 0;
            }
        case .SOUTH;
            if neighbor_block_is_relevant {
                // If this block already knows its south neighbor count, we don't need to keep going
                if neighbor_block.neighbor_south_count > -1 {
                    result := neighbor_block.neighbor_south_count + 1;
                    block.neighbor_south_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_block, direction) + 1;
                    block.neighbor_south_count = result;
                    return result;
                }
            }
            else if neighbor_wall_is_relevant {
                // If this block already knows its south neighbor count, we don't need to keep going
                if neighbor_wall.neighbor_south_count > -1 {
                    result := neighbor_wall.neighbor_south_count + 1;
                    block.neighbor_south_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_wall, direction) + 1;
                    block.neighbor_south_count = result;
                    return result;
                }
            }
            else {
                block.neighbor_south_count = 0;
                block.shadow = 0;
                return 0;
            }
        case .EAST;
            if neighbor_block_is_relevant {
                // If this block already knows its east neighbor count, we don't need to keep going
                if neighbor_block.neighbor_east_count > -1 {
                    result := neighbor_block.neighbor_east_count + 1;
                    block.neighbor_east_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_block, direction) + 1;
                    block.neighbor_east_count = result;
                    return result;
                }
            }
            else if neighbor_wall_is_relevant {
                // If this block already knows its east neighbor count, we don't need to keep going
                if neighbor_wall.neighbor_east_count > -1 {
                    result := neighbor_wall.neighbor_east_count + 1;
                    block.neighbor_east_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_wall, direction) + 1;
                    block.neighbor_east_count = result;
                    return result;
                }
            }
            else {
                block.neighbor_east_count = 0;
                block.shadow = 0;
                return 0;
            }
        case .WEST;
            if neighbor_block_is_relevant {
                // If this block already knows its east neighbor count, we don't need to keep going
                if neighbor_block.neighbor_west_count > -1 {
                    result := neighbor_block.neighbor_west_count + 1;
                    block.neighbor_west_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_block, direction) + 1;
                    block.neighbor_west_count = result;
                    return result;
                }
            }
            else if neighbor_wall_is_relevant {
                // If this block already knows its west neighbor count, we don't need to keep going
                if neighbor_wall.neighbor_west_count > -1 {
                    result := neighbor_wall.neighbor_west_count + 1;
                    block.neighbor_west_count = result;
                    return result;
                } else {
                    result := get_and_recursively_set_block_neighbor_counts(neighbor_wall, direction) + 1;
                    block.neighbor_west_count = result;
                    return result;
                }
            }
            else {
                block.neighbor_west_count = 0;
                block.shadow = 0;
                return 0;
            }
        case;
            assert(false, "Invalid direction for doing neighbor count thing");
            return -1;
    }
}

set_block_shadow_relative_to_neighbors :: (block_pos: Vector2) {
    block_pos_string := vector2_to_string_temp(block_pos);

    block_exists, block := table_find_new(*global_block_pos_to_block, block_pos_string);
    wall_exists,  wall  := table_find_new(*global_wall_pos_to_wall,   block_pos_string);
    torch_exists,    _  := table_find_new(*global_torch_pos_to_torch, block_pos_string);

    if (!block_exists && !wall_exists) || torch_exists return;

    neighbor_north_pos := Vector2.{ block_pos.x, block_pos.y - BLOCK_WORLD_HEIGHT };
    neighbor_north_block_exists, neighbor_north_block := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(neighbor_north_pos));
    neighbor_north_wall_exists,  neighbor_north_wall  := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(neighbor_north_pos));
    neighbor_shadow_north : int;
    if neighbor_north_block_exists && neighbor_north_wall_exists {
        neighbor_shadow_north = min(neighbor_north_block.shadow, neighbor_north_wall.shadow);
    } else if neighbor_north_block_exists {
        neighbor_shadow_north = neighbor_north_block.shadow;
    } else if neighbor_north_wall_exists {
        neighbor_shadow_north = neighbor_north_wall.shadow;
    } else {
        neighbor_shadow_north = -1;
    }

    neighbor_south_pos := Vector2.{ block_pos.x, block_pos.y + BLOCK_WORLD_HEIGHT };
    neighbor_south_block_exists, neighbor_south_block := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(neighbor_south_pos));
    neighbor_south_wall_exists,  neighbor_south_wall  := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(neighbor_south_pos));
    neighbor_shadow_south : int;
    if neighbor_south_block_exists && neighbor_south_wall_exists {
        neighbor_shadow_south = min(neighbor_south_block.shadow, neighbor_south_wall.shadow);
    } else if neighbor_south_block_exists {
        neighbor_shadow_south = neighbor_south_block.shadow;
    } else if neighbor_south_wall_exists {
        neighbor_shadow_south = neighbor_south_wall.shadow;
    } else {
        neighbor_shadow_south = -1;
    }

    neighbor_east_pos := Vector2.{ block_pos.x + BLOCK_WORLD_WIDTH, block_pos.y };
    neighbor_east_block_exists, neighbor_east_block := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(neighbor_east_pos));
    neighbor_east_wall_exists,  neighbor_east_wall  := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(neighbor_east_pos));
    neighbor_shadow_east : int;
    if neighbor_east_block_exists && neighbor_east_wall_exists {
        neighbor_shadow_east = min(neighbor_east_block.shadow, neighbor_east_wall.shadow);
    } else if neighbor_east_block_exists {
        neighbor_shadow_east = neighbor_east_block.shadow;
    } else if neighbor_east_wall_exists {
        neighbor_shadow_east = neighbor_east_wall.shadow;
    } else {
        neighbor_shadow_east = -1;
    }

    neighbor_west_pos := Vector2.{ block_pos.x - BLOCK_WORLD_WIDTH, block_pos.y };
    neighbor_west_block_exists, neighbor_west_block := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(neighbor_west_pos));
    neighbor_west_wall_exists,  neighbor_west_wall  := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(neighbor_west_pos));
    neighbor_shadow_west : int;
    if neighbor_west_block_exists && neighbor_west_wall_exists {
        neighbor_shadow_west = min(neighbor_west_block.shadow, neighbor_west_wall.shadow);
    } else if neighbor_west_block_exists {
        neighbor_shadow_west = neighbor_west_block.shadow;
    } else if neighbor_west_wall_exists {
        neighbor_shadow_west = neighbor_west_wall.shadow;
    } else {
        neighbor_shadow_west = -1;
    }

    min_neighbor_shadow := min(
        min(neighbor_shadow_north, neighbor_shadow_south),
        min(neighbor_shadow_east,  neighbor_shadow_west),
    );
    shadow := cast(u8) clamp(0, min_neighbor_shadow + 1, 7);

    if block_exists { block.shadow = shadow; }
    if wall_exists  { wall.shadow  = shadow; }
}

update_block_shadows_around_pos :: (block_pos: Vector2) {
    // First, darken all the blocks and walls in the splash zone.
    for col: -7..7 {
        for row: -7..7 {
            pos_to_update       := Vector2.{ block_pos.x + col * BLOCK_WORLD_WIDTH, block_pos.y + row * BLOCK_WORLD_HEIGHT };

            block_exists, block  := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(pos_to_update));
            wall_exists,  wall   := table_find_new(*global_wall_pos_to_wall,   vector2_to_string_temp(pos_to_update));
            torch_exists,  torch := table_find_new(*global_torch_pos_to_torch, vector2_to_string_temp(pos_to_update));

            if !torch_exists {
                if block_exists block.shadow = 7;
                if wall_exists  wall.shadow  = 7;
            }
        }
    }

    for col: -7..7 {
        for row: -7..7 {
            block_to_update_pos := Vector2.{ block_pos.x + col * BLOCK_WORLD_WIDTH, block_pos.y + row * BLOCK_WORLD_HEIGHT };
            set_block_shadow_relative_to_neighbors(block_to_update_pos);
        }
    }

    for col: -7..7 {
        for row: -7..7 {
            col *= -1;
            row *= -1;
            defer col *= -1;
            defer row *= -1;

            block_to_update_pos := Vector2.{ block_pos.x + col * BLOCK_WORLD_WIDTH, block_pos.y + row * BLOCK_WORLD_HEIGHT };
            set_block_shadow_relative_to_neighbors(block_to_update_pos);
        }
    }
}

update_texture_map_source_pos_around_pos :: (block_pos: Vector2, is_wall: bool) {
    potential_neighbor_pos_north := Vector2.{ block_pos.x, block_pos.y - BLOCK_WORLD_HEIGHT };
    potential_neighbor_pos_south := Vector2.{ block_pos.x, block_pos.y + BLOCK_WORLD_HEIGHT };
    potential_neighbor_pos_east  := Vector2.{ block_pos.x + BLOCK_WORLD_WIDTH, block_pos.y };
    potential_neighbor_pos_west  := Vector2.{ block_pos.x - BLOCK_WORLD_WIDTH, block_pos.y };

    if is_wall {
        neighbor_exists_north, neighbor_north := table_find_new(*global_wall_pos_to_wall, vector2_to_string_temp(potential_neighbor_pos_north));
        neighbor_exists_south, neighbor_south := table_find_new(*global_wall_pos_to_wall, vector2_to_string_temp(potential_neighbor_pos_south));
        neighbor_exists_east,  neighbor_east  := table_find_new(*global_wall_pos_to_wall, vector2_to_string_temp(potential_neighbor_pos_east));
        neighbor_exists_west,  neighbor_west  := table_find_new(*global_wall_pos_to_wall, vector2_to_string_temp(potential_neighbor_pos_west));

        if neighbor_exists_north { neighbor_north.texture_map_source_pos = get_texture_map_source_coords_for_block(neighbor_north); }
        if neighbor_exists_south { neighbor_south.texture_map_source_pos = get_texture_map_source_coords_for_block(neighbor_south); }
        if neighbor_exists_east  { neighbor_east.texture_map_source_pos  = get_texture_map_source_coords_for_block(neighbor_east);  }
        if neighbor_exists_west  { neighbor_west.texture_map_source_pos  = get_texture_map_source_coords_for_block(neighbor_west);  }
    } else {
        neighbor_exists_north, neighbor_north := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(potential_neighbor_pos_north));
        neighbor_exists_south, neighbor_south := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(potential_neighbor_pos_south));
        neighbor_exists_east,  neighbor_east  := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(potential_neighbor_pos_east));
        neighbor_exists_west,  neighbor_west  := table_find_new(*global_block_pos_to_block, vector2_to_string_temp(potential_neighbor_pos_west));

        if neighbor_exists_north { neighbor_north.texture_map_source_pos = get_texture_map_source_coords_for_block(neighbor_north); }
        if neighbor_exists_south { neighbor_south.texture_map_source_pos = get_texture_map_source_coords_for_block(neighbor_south); }
        if neighbor_exists_east  { neighbor_east.texture_map_source_pos  = get_texture_map_source_coords_for_block(neighbor_east);  }
        if neighbor_exists_west  { neighbor_west.texture_map_source_pos  = get_texture_map_source_coords_for_block(neighbor_west);  }
    }
}

generate_torch :: (x: float32, y: float32) -> *Torch {
    rect := Rectangle.{
        xx x,
        xx y,
        xx TORCH_WORLD_WIDTH,
        xx TORCH_WORLD_HEIGHT,
    }; 

    new_torch := New(Torch);
    // new_torch.id                     = s32;
    new_torch.type                    = Torch;
    new_torch.pos                     = get_rect_center(rect);
    new_torch.vel                     = Vector2.{ 0, 0 };
    new_torch.is_facing_left          = false;
    new_torch.bounding_rect           = rect;
    new_torch.sprite_rect             = rect;
    new_torch.texture_map_source_pos  = get_texture_map_source_coords_for_entity(new_torch);
    new_torch.health_max              = 1;
    new_torch.health_curr             = 1;
    new_torch.cooldown_spawn_spark_ms = TORCH_COOLDOWN_SPAWN_SPARK_MS;

    table_add(*global_torch_pos_to_torch, vector2_to_string_permanent(new_torch.pos), new_torch);
    array_add(*torches, new_torch);

    return new_torch;
}

generate_block :: (block_type: BlockType, x: float32, y: float32) -> *Block {
    is_wall := get_is_wall(block_type);
    
    width  : float;
    height : float;

    if is_wall {
        width  = xx WALL_WORLD_WIDTH;
        height = xx WALL_WORLD_HEIGHT;
    }
    else if block_type == .TREE_TOP {
        width  = xx TREE_TOP_WORLD_WIDTH;
        height = xx TREE_TOP_WORLD_HEIGHT;
    }
    else {
        // Normal blocks
        width  = xx BLOCK_WORLD_WIDTH;
        height = xx BLOCK_WORLD_HEIGHT;
    }

    rect := Rectangle.{ xx x, xx y, width, height, };

    new_block : *Block;
    if block_type == .TREE || block_type == .TREE_BRANCH || block_type == .TREE_TOP {
        new_block      = New(TreeBlock);
        new_block.type = TreeBlock;
    } else {
        new_block      = New(Block);
        new_block.type = Block;
    }

    new_block.pos           = get_rect_center(rect);
    new_block.bounding_rect = rect;
    new_block.sprite_rect   = rect;
    new_block.health_max    = BLOCK_HEALTH_MAX;
    new_block.health_curr   = BLOCK_HEALTH_MAX;
    new_block.block_type    = block_type;
    new_block.hardness      = get_block_hardness(block_type);
    new_block.weak_to_tool  = get_block_weak_to_tool(block_type);
    // shadow is not defined here, we define it in a second pass since we need to know about neighbors
    new_block.neighbor_north_count   = -1;
    new_block.neighbor_south_count   = -1;
    new_block.neighbor_east_count    = -1;
    new_block.neighbor_west_count    = -1;
    new_block.texture_map_source_pos = Vector2.{ -1, -1 };

    if is_wall {   
        table_add(*global_wall_pos_to_wall, vector2_to_string_permanent(new_block.pos), new_block);
    } else {
        table_add(*global_block_pos_to_block, vector2_to_string_permanent(new_block.pos), new_block);
    }

    if #complete block_type == {
        case .DIRT;        array_add(*blocks_dirt,       new_block);
        case .GRASS;       array_add(*blocks_grass,      new_block);
        case .ROCK;        array_add(*blocks_rock,       new_block);
        case .WOOD;        array_add(*blocks_wood,       new_block);
        case .TREE;        array_add(*blocks_tree,       new_block);
        case .TREE_BRANCH; array_add(*blocks_tree,       new_block);
        case .TREE_TOP;    array_add(*blocks_tree,       new_block);
        case .COPPER_ORE;  array_add(*blocks_copper_ore, new_block);
        case .WALL_DIRT;   array_add(*walls_dirt,        new_block);
        case .WALL_ROCK;   array_add(*walls_rock,        new_block);

        case .UNSPECIFIED; assert(false, "Unspecified block type");
    }

    return new_block;
}

draw_torch :: (torch: Torch) {
    map_texture, map_source := get_texture_map_for_entity(torch);

    DrawTexturePro(map_texture, map_source, torch.sprite_rect, Vector2.{ 0, 0 }, 0.0, WHITE);
}

draw_block :: (block: Block, player: Player, mouse_pos_in_world: Vector2) -> should_debug_block: bool {
    block_map_texture, block_map_source := get_texture_map_for_block(block);

    destination_rect := block.sprite_rect;
    if block.type == TreeBlock {
        // NOTE: The tree texture tiles have transparency in them on the tiles' sides. I don't exactly understand why,
        // I guess it's so that they appear skinnier than the normal blocks. But, this means that we need to
        // nudge them by that transparency length when the tree tiles should conjoin. Thus, these fudges.
        destination_rect.x      -= destination_rect.width * 0.125;
        destination_rect.width  *= 1.25;
        destination_rect.height *= 1.25;
    }

    color: Color = WHITE;
    if shadows_enabled {
        color = Color.{ 255 - block.shadow * 36, 255 - block.shadow * 36, 255 - block.shadow * 36, 255 };
    }

    // Draw block texture
    DrawTexturePro(block_map_texture, block_map_source, destination_rect, Vector2.{ 0, 0 }, 0.0, color);

    // Damage block overlay (cracks)
    if block.health_curr < block.health_max {
        frame := DAMAGE_MAP_COLS-1 - floor(cast(float32) block.health_curr * DAMAGE_MAP_COLS / block.health_max);
        damage_map_source := Rectangle.{cast(float32) frame * DAMAGE_MAP_TILE_WIDTH, 0, DAMAGE_MAP_TILE_WIDTH, DAMAGE_MAP_TILE_HEIGHT};
        DrawTexturePro(damage_map, damage_map_source, block.sprite_rect, Vector2.{ 0, 0 }, 0.0, WHITE);
    }

    // Mouse block overlay (hover)
    is_within_reach := Vector2Distance(mouse_pos_in_world, player.pos) < PLAYER_REACH_DISTANCE;

    selected_item_stack, result := get_selected_item_stack(player.inventory);
    has_an_item_selected := result == xx ReturnStatus.SUCCESS;
    is_wall := get_is_wall(block.block_type);
    is_wielding_tool_for_block_type := ifx is_wall
        then false // Never show hover for walls, it's messy. 
        else has_an_item_selected && can_item_break_blocks(selected_item_stack.item_type);

    show_block_hover := debug_mode || (is_wielding_tool_for_block_type && is_within_reach && block.block_type != .TREE_TOP);
    if show_block_hover {
        if CheckCollisionPointRec(mouse_pos_in_world, block.bounding_rect) {
            DrawRectangleRec(block.sprite_rect, TRANSPARENT_WHITE);
            return true;
        }
    }

    return false;
}

initialize_block :: (block: *Block) {
    // Define initial shadows for walls
    {
        // @TODO: add a max_depth param, probably, I think that'd fix the stack overflow
        block.neighbor_north_count = get_and_recursively_set_block_neighbor_counts(block, .NORTH);
        block.neighbor_south_count = get_and_recursively_set_block_neighbor_counts(block, .SOUTH);
        block.neighbor_east_count  = get_and_recursively_set_block_neighbor_counts(block, .EAST);
        block.neighbor_west_count  = get_and_recursively_set_block_neighbor_counts(block, .WEST);

        min_neighbor_count := min(
            min(block.neighbor_north_count, block.neighbor_south_count),
            min(block.neighbor_east_count,  block.neighbor_west_count)
        );

        block.shadow = ifx min_neighbor_count < 8 then cast(u8) min_neighbor_count else 7;
    }

    // Initialize texture source pos
    {
        block.texture_map_source_pos = get_texture_map_source_coords_for_block(block);
    }
}

destroy_entity :: (entity: *Entity, player: *Player) {
     if entity.type == {
        case Block;
            destroy_block(cast(*Block) entity, player);

        case Torch;
            table_remove(*global_torch_pos_to_torch, vector2_to_string_temp(entity.pos));
            array_unordered_remove_by_value(*torches, cast(*Torch) entity);
            update_block_shadows_around_pos(entity.pos);
            free(entity);

        case Particle;
            array_unordered_remove_by_value(*particles, cast(*Particle) entity);
            free(entity);

        case;
            assert(false, "You forgot some entity type for which to get source coords");
    }
}

destroy_block :: (block: *Block, player: *Player) {
    is_wall := get_is_wall(block.block_type);

    if is_wall table_remove(*global_wall_pos_to_wall,   vector2_to_string_temp(block.pos));
    else       table_remove(*global_block_pos_to_block, vector2_to_string_temp(block.pos));

    if #complete block.block_type == {
        case .DIRT;        array_unordered_remove_by_value(*blocks_dirt,       block);
        case .GRASS;       array_unordered_remove_by_value(*blocks_grass,      block);
        case .ROCK;        array_unordered_remove_by_value(*blocks_rock,       block);
        case .WOOD;        array_unordered_remove_by_value(*blocks_wood,       block);
        case .TREE;        array_unordered_remove_by_value(*blocks_tree,       block);
        case .TREE_BRANCH; array_unordered_remove_by_value(*blocks_tree,       block);
        case .TREE_TOP;    array_unordered_remove_by_value(*blocks_tree,       block);
        case .COPPER_ORE;  array_unordered_remove_by_value(*blocks_copper_ore, block);

        case .WALL_DIRT;   array_unordered_remove_by_value(*walls_dirt, block);
        case .WALL_ROCK;   array_unordered_remove_by_value(*walls_rock, block);

        case .UNSPECIFIED; assert(false, "Unspecified block type to remove");
    }

    update_block_shadows_around_pos(block.pos);

    update_texture_map_source_pos_around_pos(block.pos, is_wall);

    // Destroy torch if this block was the last anchor for it
    if is_wall {
        torch_exists_center, torch_center := get_neighbor_torch(block.pos, .CENTER);
        if torch_exists_center destroy_torch_if_it_has_no_anchor(torch_center, player);
    } else {
        torch_exists_north, torch_north := get_neighbor_torch(block.pos, .NORTH);
        if torch_exists_north destroy_torch_if_it_has_no_anchor(torch_north, player);

        torch_exists_east, torch_east := get_neighbor_torch(block.pos, .EAST);
        if torch_exists_east destroy_torch_if_it_has_no_anchor(torch_east, player);

        torch_exists_west, torch_west := get_neighbor_torch(block.pos, .WEST);
        if torch_exists_west destroy_torch_if_it_has_no_anchor(torch_west, player);
    }
    
    // Spawn particles
    for 1..10 {
        size_modifier := random_get_within_range(0.2, 1);
        rect := Rectangle.{ block.pos.x, block.pos.y, PARTICLE_BLOCK_BIT_WORLD_WIDTH * size_modifier, PARTICLE_BLOCK_BIT_WORLD_HEIGHT * size_modifier };

        new_particle := New(Particle);
        new_particle.type              = Particle;
        new_particle.particle_type     = .BLOCK_BIT;
        new_particle.pos               = get_rect_center(rect);
        new_particle.vel               = Vector2.{ random_get_within_range(-200, 200), random_get_within_range(-350, 100) };
        new_particle.bounding_rect     = rect;
        new_particle.sprite_rect       = rect;
        new_particle.time_remaining_ms = 1000;

        array_add(*particles, new_particle);
    }

    free(block);
}

destroy_torch_if_it_has_no_anchor :: (torch: *Torch, player: *Player) {
    neighbor_block_exists_south, _ := get_neighbor(torch.pos, .SOUTH,  false);
    neighbor_block_exists_east,  _ := get_neighbor(torch.pos, .EAST,   false);
    neighbor_block_exists_west,  _ := get_neighbor(torch.pos, .WEST,   false);
    neighbor_wall_exists_center, _ := get_neighbor(torch.pos, .CENTER, true);

    if !neighbor_block_exists_south && !neighbor_block_exists_east && !neighbor_block_exists_west && !neighbor_wall_exists_center {
        try_to_add_to_inventory(*player.inventory, .TORCH);
        destroy_entity(torch, player);
    }
}

draw_inventory_slot :: (slot_index: s32, player: Player, draw_hotbar_slot: bool) {
    assert(slot_index >= 0, "You probably want a non-negative slot_index. If not, delete this assertion.");

    hotbar_pane_rect  := build_inventory_slot_rect(slot_index);
    
    DrawTexturePro(
        inventory_back_texture,
        Rectangle.{ 0, 0, INVENTORY_BACK_TEXTURE_WIDTH, INVENTORY_BACK_TEXTURE_HEIGHT },
        hotbar_pane_rect,
        Vector2.{ 0, 0 },
        0.0,
        Color.{ 255, 255, 255, 200 },
    );
    
    if player.inventory.selected_item_stack == slot_index {
        DrawRectangleRoundedLinesEx(hotbar_pane_rect, 0.1, 1, HOTBAR_PANE_THICKNESS, WHITE);
    }

    item_stack_in_slot := player.inventory.item_stacks[slot_index];
    if !item_stack_is_empty(*item_stack_in_slot) {
        
        item_texture_map, item_source_rect := get_texture_map_by_item_type(item_stack_in_slot.item_type);
        DrawTexturePro(item_texture_map, item_source_rect, hotbar_pane_rect, Vector2.{ 0, 0 }, 0.0, WHITE);
        
        if item_type_is_stackable(item_stack_in_slot.item_type) {
            DrawText(
                tprint("%\0", item_stack_in_slot.stack_count).data,
                xx (hotbar_pane_rect.x + 0.50 * HOTBAR_PANE_LENGTH),    
                xx (hotbar_pane_rect.y + 0.67 * HOTBAR_PANE_LENGTH),    
                18,
                WHITE,
            );
        }
    }

    // Draw hotbar number
    if draw_hotbar_slot {
        DrawText(
            tprint("%\0", slot_index + 1).data,
            xx (hotbar_pane_rect.x + HOTBAR_PANE_THICKNESS * 1.5),
            xx (hotbar_pane_rect.y + HOTBAR_PANE_THICKNESS * 1.5),
            18,
            WHITE,
        );
    }
}

build_inventory_slot_rect :: (slot_index: int) -> Rectangle {
    x := slot_index % INVENTORY_SLOTS_PER_ROW;
    y := cast(int) slot_index / INVENTORY_SLOTS_PER_ROW;

    return Rectangle.{
        x * (INVENTORY_BACK_WORLD_WIDTH + 3 * HOTBAR_PANE_THICKNESS) + HOTBAR_PANE_MARGIN * HOTBAR_PANE_THICKNESS,
        y * (INVENTORY_BACK_WORLD_WIDTH + 3 * HOTBAR_PANE_THICKNESS) + HOTBAR_PANE_MARGIN * HOTBAR_PANE_THICKNESS,
        INVENTORY_BACK_WORLD_WIDTH,// HOTBAR_PANE_LENGTH,
        INVENTORY_BACK_WORLD_WIDTH,// HOTBAR_PANE_LENGTH,
    };
}
