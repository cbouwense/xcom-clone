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

Edge :: struct {
    from     : s32;
    to       : s32;
    distance : float32;
}

dijkstra :: (start_id: s32, target_id: s32, edges: [] Edge) -> [] s32 {
    // id to distance from start value
    unvisited_nodes : Table(Key_Type = s32, Value_Type = float32);
    init(*unvisited_nodes);
    defer deinit(*unvisited_nodes);

    // Populate table with all nodes and set their distances to infinity by default, except
    // for the starting node.
    // TODO: This is terribly inefficient. But, I don't think I care? If it's slow, then I'll care.
    for edge: edges {
        table_set(*unvisited_nodes, edge.from, ifx edge.from == start_id then 0.0 else FLOAT32_INFINITY);
        table_set(*unvisited_nodes, edge.to, ifx edge.to == start_id then 0.0 else FLOAT32_INFINITY);
    }

    for unvisited_nodes {
        key, value := it_index, it;
        print_vars(key, value);
    }

    

    return .[];
}