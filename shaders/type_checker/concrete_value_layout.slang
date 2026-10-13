// Evaluate a concrete value layout from checked payload references. Each
// group is a record's fields or one enum variant. Groups sum their payload
// widths; the value uses the largest group. Descriptors are terminal values.
public interface IConcreteValueLayout
{
    // INVALID means the node needs expansion or has no supported layout.
    // Zero is a complete leaf with no native payload words.
    static uint leaf_words(uint tag, uint payload);
    static uint group_count(uint tag, uint payload);
    static uint overhead(uint tag, uint payload);
    static uint repetitions(uint tag, uint payload);
    // INVALID marks a row belonging to a different declaration.
    static uint payload_count(uint tag, uint payload, uint group);
    static bool payload_ref(uint tag, uint payload, uint group, uint ordinal,
        out uint child_tag, out uint child_payload);
}

public uint concrete_value_words<Graph : IConcreteValueLayout>(uint tag, uint payload)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint2 refs[DEPTH_LIMIT];
    uint group[DEPTH_LIMIT];
    uint groups[DEPTH_LIMIT];
    uint ordinal[DEPTH_LIMIT];
    uint totals[DEPTH_LIMIT];
    uint maxima[DEPTH_LIMIT];
    uint depth = 0u;
    uint completed = 0u;
    bool ready = false;
    refs[0u] = uint2(tag, payload);
    groups[0u] = INVALID;
    for (;;)
    {
        uint2 current = refs[depth];
        if (groups[depth] == INVALID)
        {
            uint leaf = Graph.leaf_words(current.x, current.y);
            if (leaf != INVALID)
            {
                completed = leaf;
                ready = true;
            }
            else
            {
                groups[depth] = Graph.group_count(current.x, current.y);
                if (groups[depth] == 0u || groups[depth] == INVALID) return INVALID;
                group[depth] = 0u;
                ordinal[depth] = 0u;
                totals[depth] = Graph.overhead(current.x, current.y);
                maxima[depth] = 0u;
            }
        }
        if (!ready)
        {
            if (group[depth] == groups[depth])
            {
                completed = maxima[depth];
                ready = true;
            }
            else
            {
                uint count = Graph.payload_count(current.x, current.y, group[depth]);
                if (count == INVALID || ordinal[depth] == count)
                {
                    if (count != INVALID) maxima[depth] = max(maxima[depth], totals[depth]);
                    group[depth]++;
                    ordinal[depth] = 0u;
                    totals[depth] = Graph.overhead(current.x, current.y);
                    continue;
                }
                uint child_tag; uint child_payload;
                if (!Graph.payload_ref(current.x, current.y, group[depth], ordinal[depth]++,
                    child_tag, child_payload) || depth + 1u == DEPTH_LIMIT) return INVALID;
                // Finite concrete type arguments cannot contain themselves by
                // value. Detect a cycle before extending the traversal stack.
                for (uint ancestor = 0u; ancestor <= depth; ancestor++)
                    if (refs[ancestor].x == child_tag && refs[ancestor].y == child_payload) return INVALID;
                depth++;
                refs[depth] = uint2(child_tag, child_payload);
                groups[depth] = INVALID;
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
        if (totals[depth] >= INVALID - completed) return INVALID;
        totals[depth] += completed;
        completed = 0u;
        ready = false;
    }
}
