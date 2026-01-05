Control :: struct {
    type:  Type;
    value: s32; // KeyboardKey | MouseButton;
}

Controls :: struct {
    move_player_left  : [3] Control;
    move_player_right : [3] Control;
    jump              : [3] Control;
    attack            : [3] Control;
    interact          : [3] Control;
    open_inventory    : [3] Control;
    drag_cam          : [3] Control;
    scroll_as_zoom    : [3] Control;
    hotbar_slot_1     : [3] Control;
    hotbar_slot_2     : [3] Control;
    hotbar_slot_3     : [3] Control;
    hotbar_slot_4     : [3] Control;
    hotbar_slot_5     : [3] Control;
    hotbar_slot_6     : [3] Control;
    hotbar_slot_7     : [3] Control;
    hotbar_slot_8     : [3] Control;
    hotbar_slot_9     : [3] Control;
    hotbar_slot_10    : [3] Control;
}