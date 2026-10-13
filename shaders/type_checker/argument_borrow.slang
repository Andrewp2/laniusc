import type_checker.concrete_type_equality;

// A call may borrow an array as a slice at the outer argument boundary.
// Its element type is invariant: this does not convert elements, change
// nested aggregate types, or rebind parameters already in caller scope.
public bool checked_array_borrow_matches<Graph : IConcreteTypeGraph>(
    uint expected_tag, uint expected_payload, uint actual_tag, uint actual_payload,
    uint capacity)
{
    if (expected_tag != 3u || actual_tag != 3u ||
        expected_payload >= capacity || actual_payload >= capacity ||
        Graph.metadata(expected_payload, 0u) != 3u ||
        Graph.metadata(actual_payload, 0u) != 2u) return false;
    return concrete_type_refs_equal<Graph>(
        Graph.metadata(expected_payload, 3u), Graph.metadata(expected_payload, 4u),
        Graph.metadata(actual_payload, 3u), Graph.metadata(actual_payload, 4u), capacity);
}
