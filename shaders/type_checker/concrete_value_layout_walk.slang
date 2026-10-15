// Included walker body (not a module). The includer defines
// CONCRETE_VALUE_WORDS_WALK (the function name), CONCRETE_VALUE_WORDS_FRAMES
// (frame declarations), the readers VL_REF/VL_GROUPS/VL_GROUP/VL_ORDINAL/
// VL_TOTALS/VL_MAXIMA, the writers VL_SET_GROUPS/VL_SET_MAXIMA/VL_ADD_TOTALS,
// VL_PUSH(d, ref) (groups = INVALID), VL_OPENED(d, overhead) (group = 0,
// ordinal = 0, totals = overhead, maxima = 0), VL_NEXT_GROUP(d, overhead)
// (group + 1, ordinal = 0, totals = overhead) and VL_ORDINAL_INCREMENT(d),
// which returns the old ordinal and advances it. concrete_value_layout.slang
// expands it over local arrays; concrete_value_layout_scratch.slang expands it
// over the thread scratch table.
public uint CONCRETE_VALUE_WORDS_WALK<Graph : IConcreteValueLayout>(uint tag, uint payload)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    CONCRETE_VALUE_WORDS_FRAMES
    uint depth = 0u;
    uint completed = 0u;
    bool ready = false;
    VL_PUSH(0u, uint2(tag, payload));
    for (;;)
    {
        uint2 current = VL_REF(depth);
        if (VL_GROUPS(depth) == INVALID)
        {
            uint leaf = Graph.leaf_words(current.x, current.y);
            if (leaf != INVALID)
            {
                completed = leaf;
                ready = true;
            }
            else
            {
                VL_SET_GROUPS(depth, Graph.group_count(current.x, current.y));
                if (VL_GROUPS(depth) == 0u || VL_GROUPS(depth) == INVALID) return INVALID;
                VL_OPENED(depth, Graph.overhead(current.x, current.y));
            }
        }
        if (!ready)
        {
            if (VL_GROUP(depth) == VL_GROUPS(depth))
            {
                completed = VL_MAXIMA(depth);
                ready = true;
            }
            else
            {
                uint count = Graph.payload_count(current.x, current.y, VL_GROUP(depth));
                if (count == INVALID || VL_ORDINAL(depth) == count)
                {
                    if (count != INVALID) VL_SET_MAXIMA(depth, max(VL_MAXIMA(depth), VL_TOTALS(depth)));
                    VL_NEXT_GROUP(depth, Graph.overhead(current.x, current.y));
                    continue;
                }
                uint child_tag; uint child_payload;
                if (!Graph.payload_ref(current.x, current.y, VL_GROUP(depth), VL_ORDINAL_INCREMENT(depth),
                    child_tag, child_payload) || depth + 1u == DEPTH_LIMIT) return INVALID;
                // Finite concrete type arguments cannot contain themselves by
                // value. Detect a cycle before extending the traversal stack.
                for (uint ancestor = 0u; ancestor <= depth; ancestor++)
                    if (VL_REF(ancestor).x == child_tag && VL_REF(ancestor).y == child_payload) return INVALID;
                depth++;
                VL_PUSH(depth, uint2(child_tag, child_payload));
                continue;
            }
        }
        if (completed == INVALID) return INVALID;
        uint repetitions = Graph.repetitions(current.x, current.y);
        if (repetitions == INVALID ||
            (repetitions != 0u && completed > (INVALID - 1u) / repetitions))
            return INVALID;
        completed *= repetitions;
        if (depth == 0u) return completed;
        depth--;
        if (VL_TOTALS(depth) >= INVALID - completed) return INVALID;
        VL_ADD_TOTALS(depth, completed);
        completed = 0u;
        ready = false;
    }
}
