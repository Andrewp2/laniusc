// Included walker body (not a module). The includer defines
// SCOPED_TYPE_EQUALITY_WALK (the function name), SCOPED_TYPE_EQUALITY_FRAMES
// (frame declarations), the readers SE_PAIR/SE_CONTEXT/SE_NEXT/SE_COUNT, the
// writer SE_SET_COUNT, SE_PUSH(d, pair, context) (next = INVALID),
// SE_CLASSIFIED(d, pair, context) (count = 0, next = 0) and
// SE_NEXT_INCREMENT(d), which returns the old next slot and advances it.
// scoped_type_equality.slang expands it over local arrays;
// scoped_type_scratch.slang expands it over the thread scratch table.
public bool SCOPED_TYPE_EQUALITY_WALK<
    LeftGraph : IParameterScopedTypeGraph, RightGraph : IParameterScopedTypeGraph>(
    uint left_tag, uint left_payload, uint left_context,
    uint right_tag, uint right_payload, uint right_context,
    uint left_type_capacity, uint right_type_capacity, uint token_capacity)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    SCOPED_TYPE_EQUALITY_FRAMES
    uint depth = 0u;
    SE_PUSH(0u, uint4(left_tag, left_payload, right_tag, right_payload),
        uint2(left_context, right_context));
    for (;;)
    {
        uint4 pair = SE_PAIR(depth);
        uint2 context = SE_CONTEXT(depth);
        bool classify = SE_NEXT(depth) == INVALID;
        if (classify)
        {
            if (pair.x == 2u && context.x != INVALID)
            {
                if (pair.y >= token_capacity ||
                    !LeftGraph.substitute_type_parameter(context.x, pair.y, pair.x, pair.y) ||
                    (pair.x != 1u && pair.x != 2u && pair.x != 3u)) return false;
                context.x = INVALID;
            }
            if (pair.z == 2u && context.y != INVALID)
            {
                if (pair.w >= token_capacity ||
                    !RightGraph.substitute_type_parameter(context.y, pair.w, pair.z, pair.w) ||
                    (pair.z != 1u && pair.z != 2u && pair.z != 3u)) return false;
                context.y = INVALID;
            }
            SE_CLASSIFIED(depth, pair, context);
        }
        // A node pair (both tag 3, in range) reads each side's fields once per
        // step: the headers when classified, then the child references.
        bool step = classify || SE_NEXT(depth) != SE_COUNT(depth);
        TypeNodeFields left = type_node_step_fields<LeftGraph>(pair.y,
            step && pair.x == 3u && pair.y < left_type_capacity, classify);
        TypeNodeFields right = type_node_step_fields<RightGraph>(pair.w,
            step && pair.z == 3u && pair.w < right_type_capacity, classify);
        if (classify)
        {
            // A constant argument (typed identity) or an array length (count
            // identity) is compared once, after classification, by one call.
            bool compare_constant = false; bool count_identity = false;
            uint2 constant_left = uint2(0u, INVALID); uint2 constant_right = uint2(0u, INVALID);
            if (application_argument_is_constant(pair.x) || application_argument_is_constant(pair.z))
            {
                if (!application_constant_argument(pair.x, pair.y, constant_left.x, constant_left.y) ||
                    !application_constant_argument(pair.z, pair.w, constant_right.x, constant_right.y))
                    return false;
                compare_constant = true;
            }
            else if (pair.x == 0u || pair.x != pair.z || pair.y == INVALID || pair.w == INVALID)
                return false;
            else if (pair.x != 3u)
            {
                if (pair.x != 1u && pair.x != 2u && !application_argument_is_constant(pair.x)) return false;
                if (pair.y != pair.w) return false;
                if (pair.x == 2u && (pair.y >= token_capacity ||
                    (!LeftGraph.parameter_is_valid(pair.y, false) ||
                        !RightGraph.parameter_is_valid(pair.w, false)))) return false;
            }
            else
            {
                if (pair.y >= left_type_capacity || pair.w >= right_type_capacity) return false;
                uint kind = left.kind;
                if (kind < 1u || kind > 4u || kind != right.kind) return false;
                if (kind == 1u)
                {
                    if (left.declaration != INVALID || right.declaration != INVALID)
                    {
                        if (left.declaration >= token_capacity || left.declaration != right.declaration) return false;
                    }
                    else if (any(left.identity == INVALID) || any(left.identity != right.identity)) return false;
                    SE_SET_COUNT(depth, left.count);
                    if (left.count > NOMINAL_APPLICATION_ARGUMENT_LIMIT || left.count != right.count) return false;
                }
                else
                {
                    if (kind == 2u)
                    {
                        constant_left = left.length; constant_right = right.length;
                        compare_constant = true; count_identity = true;
                    }
                    SE_SET_COUNT(depth, 1u);
                }
            }
            if (compare_constant && !scoped_constant_refs_or_counts_equal<LeftGraph, RightGraph>(
                uint3(constant_left, context.x), uint3(constant_right, context.y), token_capacity,
                count_identity)) return false;
        }
        if (SE_NEXT(depth) == SE_COUNT(depth))
        {
            if (depth == 0u) return true;
            depth--;
            continue;
        }
        uint slot = SE_NEXT_INCREMENT(depth);
        uint tag_l = left.element.x; uint payload_l = left.element.y;
        uint tag_r = right.element.x; uint payload_r = right.element.y;
        if (left.kind == 1u && (!LeftGraph.argument(pair.y, slot, tag_l, payload_l) ||
            !RightGraph.argument(pair.w, slot, tag_r, payload_r))) return false;
        if (depth + 1u == DEPTH_LIMIT) return false;
        depth++;
        SE_PUSH(depth, uint4(tag_l, payload_l, tag_r, payload_r), context);
    }
}
