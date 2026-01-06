read_then_increment :: (x: *s32, increment: s32 = 1) -> s32 {
    defer x.* += increment;
    return x.*;
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
