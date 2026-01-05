Sprite :: struct {
    map         : Texture;
    active      : bool;
    first_frame : s32; // Starts from 0
    color       : Color;
}

AnimatedSprite :: struct {
    #as using sprite  : Sprite;
    frame_count       : s32;
    frame_duration_ms : s32;
    timer_ms          : s32;
    loops             : bool;
}