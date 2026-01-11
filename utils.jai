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

// TODO: A lot of things in this function are done in an inefficient manner. If it's slow, then I'll care.
dijkstra :: (start_id: s32, target_id: s32, edges: [] Edge) -> [] s32 {
    ids_to_distances    : Table(Key_Type = s32, Value_Type = float32); // id to distance from start value
    unvisited_nodes_set : Table(Key_Type = s32, Value_Type = Any);     // setting Value_Type as Any because we're using this as a Set

    for edge: edges {
        table_set(*ids_to_distances, edge.from, FLOAT32_INFINITY);
        table_set(*ids_to_distances, edge.to, FLOAT32_INFINITY);
    }
    table_set(*ids_to_distances, start_id, 0);

    for ids_to_distances {
        node_id := it_index;
        table_set(*unvisited_nodes_set, node_id, null);
    }

    // print("ids_to_distances:\n");
    // for ids_to_distances {
    //     key, value := it_index, it;
    //     print_vars(key, value);
    // }

    // print("unvisited_nodes_set:\n");
    // for unvisited_nodes_set {
    //     key, value := it_index, it;
    //     print_vars(key, value);
    // }

    find_closest_node_id :: (nodes: Table, ids_to_distances: Table) -> closest_node_id: s32, found_closest_node: bool {
        closest_node_id : s32 = -1;
        closest_node_distance := FLOAT32_INFINITY;

        for nodes {
            node_id := it_index;

            // print("checking if ")

            node_distance_exists, node_distance := table_find_new(*ids_to_distances, node_id);
            assert(node_distance_exists);

            if node_distance < closest_node_distance {
                closest_node_id = node_id;
                closest_node_distance = node_distance;
            }
        }

        return closest_node_id, closest_node_id != -1;
    }

    find_edges_for_node_id :: (node_id: s32, edges: [] Edge) -> [] Edge {
        edges_with_node_id : [..] Edge;

        for edges {
            if it.from == node_id array_add(*edges_with_node_id, it);
            if it.to == node_id   array_add(*edges_with_node_id, it);
        }

        return edges_with_node_id;
    }

    while unvisited_nodes_set.count > 0 {
        // Find the shortest node
        current_node_id, found_closest_node := find_closest_node_id(unvisited_nodes_set, ids_to_distances);
        print_vars(current_node_id, found_closest_node);
        if !found_closest_node break; // TODO: goto would be nice, mr. blow
        print("identified % as closest node\n", current_node_id);

        // Consider all of its neighbors and update their distances through the current node
        for edge: edges {
            print_vars(edge);
            node_id, neighbor_id : s32 = -1;

            if edge.from != current_node_id && edge.to != current_node_id continue;

            if edge.from == current_node_id {
                node_id     = edge.from;
                neighbor_id = edge.to;
            }

            if edge.to == current_node_id {
                node_id     = edge.to;
                neighbor_id = edge.from;
            }

            current_node_distance_exists, current_node_distance         := table_find_new(*ids_to_distances, node_id);
            current_neighbor_distance_exists, current_neighbor_distance := table_find_new(*ids_to_distances, neighbor_id);

            // Pretty sure these should always exist. Although, if you're running into this and realize that they can,
            // don't be afraid to change these asserts.
            assert(current_node_distance_exists);
            assert(current_neighbor_distance_exists);

            print_vars(node_id, neighbor_id, current_node_distance, current_neighbor_distance);

            potential_neighbor_distance := current_node_distance + edge.distance;

            if potential_neighbor_distance < current_neighbor_distance {
                print("updating % to %\n", neighbor_id, potential_neighbor_distance);
                table_set(*ids_to_distances, neighbor_id, potential_neighbor_distance);
            }
        }

        table_remove(*unvisited_nodes_set, current_node_id);
    }

    print("ids_to_distances:\n");
    for ids_to_distances {
        key, value := it_index, it;
        print_vars(key, value);
    }

    return .[];
}