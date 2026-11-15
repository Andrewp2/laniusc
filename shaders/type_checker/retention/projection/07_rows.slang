// Projection step 7: one lane per row of the current batch. Row 0 is the
// batch root; the ranks' function rows follow in rank order, each body
// contiguous behind its function row. A lane copies its template row with
// every row, token, context and side-table reference made a batch index,
// and writes the row's semantic columns from the checked facts (step 5):
// the realized reference, its native width and scalar, the binding, the
// member's field range, the call record routed to the target's native
// symbol, the function's result and entry tag, and the tree relations
// (expression parent and root, nearest loop, control depth).
import type_checker.retention.projection.pj_out;

void defaults(uint row)
{
    ob_fn_return_type[row] = RT_INVALID;
    ob_const_value[row] = RT_INVALID;
    ob_expr_parent[row] = RT_INVALID;
    ob_expr_root[row] = row;
    ob_nearest_loop[row] = RT_INVALID;
    ob_param_ranges[row] = uint2(RT_INVALID, 0u);
    ob_generic_param_ranges[row] = uint2(RT_INVALID, 0u);
    ob_array_element_start[row] = RT_INVALID;
    ob_array_element_count[row] = 0u;
    ob_value_decl[row] = RT_INVALID;
    ob_value_type[row] = 0u;
    ob_value_const[row] = uint2(0u, 0u);
    ob_value_const_present[row] = 0u;
    ob_argument_mode[row] = 0u;
    ob_enclosing_fn[row] = 0u;
    ob_function_return_type[row] = 0u;
    ob_function_entrypoint[row] = 0u;
    ob_function_host_service[row] = 0u;
    ob_function_native_abi[row] = 0u;
    ob_control_depth[row] = 0u;
    for (uint w = 0u; w < PJ_CALL_WORDS; w++) ob_calls[row * PJ_CALL_WORDS + w] = 0u;
    ob_call_native_abi[row] = 0u;
    ob_expr_ref_tag[row] = 0u;
    ob_expr_ref_payload[row] = RT_INVALID;
    ob_aggregate_decl_token[row] = RT_INVALID;
    ob_aggregate_word_count[row] = 0u;
    ob_array_length[row] = RT_INVALID;
    ob_member_field_ordinal[row] = RT_INVALID;
    ob_member_field_word_offset[row] = RT_INVALID;
    ob_member_field_word_count[row] = RT_INVALID;
    ob_iterable_kind[row] = 0u;
    ob_function_result_word_count[row] = 0u;
    ob_expr_scalar_type[row] = PJ_SCALAR_LINK_NONE;
    ob_public_decl_index[row] = RT_INVALID;
}

uint decode(Map m, uint cls, uint word)
{
    if (word == RT_INVALID) return word;
    if (cls == RT_CLASS_ROW) return pj_abs_row(m, word);
    if (cls == RT_CLASS_TOKEN) return pj_abs_token(m, word);
    if (cls == RT_CLASS_CONTEXT)
    {
        uint id = word & 0x7fffffffu;
        if (id == 0x7fffffffu) return word;
        return (word & 0x80000000u) | (pj_abs_row(m, id) & 0x7fffffffu);
    }
    if (cls >= RT_CLASS_SIDE) return pj_abs_side(m, cls - RT_CLASS_SIDE, word);
    return word;
}

void write_call(uint row, uint rank, uint rel, uint4 facts)
{
    uint use = pj_row(rank, rel, 3u).y;
    uint4 q1 = pj_instances[rank * PJ_INSTANCE_WORDS + 1u];
    uint4 route = pj_routes[q1.x + use];
    uint4 p = pj_row(rank, rel, 2u);
    uint b = row * PJ_CALL_WORDS;
    ob_calls[b + 0u] = RT_INVALID;      // target token
    ob_calls[b + 1u] = route.x;         // dependency library
    ob_calls[b + 2u] = route.y;         // dependency unit (instance namespace)
    ob_calls[b + 3u] = route.z;         // dependency local (rank)
    ob_calls[b + 4u] = RT_INVALID;      // host service
    ob_calls[b + 5u] = 0u;              // intrinsic
    ob_calls[b + 6u] = facts.w;         // return type (scalar code)
    ob_calls[b + 7u] = RT_INVALID;      // receiver row
    ob_calls[b + 8u] = p.z;             // arguments
    ob_calls[b + 9u] = facts.x;         // return reference
    ob_calls[b + 10u] = facts.y;
    ob_calls[b + 11u] = 3u;             // CHECKED_CALLABLE_DEPENDENCY
    ob_calls[b + 12u] = RT_INVALID;     // generic requirements
    ob_calls[b + 13u] = RT_INVALID;     // callable row
    ob_calls[b + 14u] = RT_INVALID;     // callable ordinal
    ob_calls[b + 15u] = 0u;             // receiver adjustment
    ob_calls[b + 16u] = 0u;
    ob_calls[b + 17u] = 0u;
    ob_calls[b + 18u] = RT_INVALID;
    ob_calls[b + 19u] = 0u;
    ob_calls[b + 20u] = RT_INVALID;
    ob_calls[b + 21u] = 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = pj_lane(dtid);
    Batch b = pj_batch();
    uint capacity; uint s;
    ob_core.GetDimensions(capacity, s);
    if (row >= b.rows || row >= capacity) return;
    defaults(row);
    if (row == 0u)
    {
        ob_core[0u] = uint4(1u, RT_INVALID, 0u, b.tokens);
        ob_links[0u] = uint4(b.rows > 1u ? 1u : RT_INVALID, RT_INVALID, b.rows, 0u);
        ob_payload[0u] = uint4(RT_INVALID, RT_INVALID, RT_INVALID, RT_INVALID);
        ob_expr_root[0u] = 0u;
        return;
    }
    uint g = pj_base_at(b.lo, PJ_C_ROWS) + row - 1u;
    uint rank = pj_rank_of(PJ_C_ROWS, g, b.lo, b.hi);
    uint rel = g - pj_base_at(rank, PJ_C_ROWS);
    Map m = pj_map(b, rank);
    uint4 r0 = pj_row(rank, rel, 0u);
    uint4 r1 = pj_row(rank, rel, 1u);
    uint4 p = pj_row(rank, rel, 2u);
    uint4 r4 = pj_row(rank, rel, 4u);
    uint4 r5 = pj_row(rank, rel, 5u);
    uint4 r6 = pj_row(rank, rel, 6u);
    uint4 facts = pj_g_facts[g];
    uint4 aux = pj_g_aux[g];
    uint kind = r0.x;
    bool function = rel == 0u;

    uint next = rank + 1u < b.hi ? pj_map(b, rank + 1u).row : RT_INVALID;
    ob_core[row] = uint4(kind, function ? 0u : pj_abs_row(m, r0.y), pj_abs_token(m, r0.z), pj_abs_token(m, r0.w));
    ob_links[row] = uint4(pj_abs_row(m, r1.x), function ? next : pj_abs_row(m, r1.y), pj_abs_row(m, r1.z), 0u);
    uint classes = rt_payload_classes(kind, p.x, function);
    ob_payload[row] = uint4(decode(m, rt_word_class(classes, 0u), p.x), decode(m, rt_word_class(classes, 1u), p.y),
        decode(m, rt_word_class(classes, 2u), p.z), decode(m, rt_word_class(classes, 3u), p.w));
    ob_fn_return_type[row] = pj_abs_row(m, r4.x);
    ob_const_value[row] = pj_abs_row(m, r4.y);

    // Tree relations.
    ob_expr_parent[row] = pj_batch_row(b, aux.x);
    uint root = g;
    for (uint step = 0u; step < PJ_EXPR_DEPTH; step++)
    {
        uint parent = pj_g_aux[root].x;
        if (parent == RT_INVALID) break;
        root = parent;
    }
    ob_expr_root[row] = pj_batch_row(b, root);
    uint depth = kind == RT_HIR_IF_STMT ? 1u : 0u;
    uint loop = RT_INVALID;
    uint up = function ? RT_INVALID : r0.y;
    for (uint step = 0u; step < PJ_EXPR_DEPTH && up != RT_INVALID && up != 0u; step++)
    {
        uint up_kind = pj_row(rank, up, 0u).x;
        if (up_kind == RT_HIR_IF_STMT) depth++;
        if (loop == RT_INVALID && (up_kind == RT_HIR_WHILE_STMT || up_kind == RT_HIR_FOR_STMT)) loop = up;
        up = pj_row(rank, up, 0u).y;
    }
    ob_nearest_loop[row] = pj_abs_row(m, loop);
    ob_control_depth[row] = depth;
    ob_enclosing_fn[row] = m.row + 1u;

    // Checked facts.
    ob_value_decl[row] = r5.x == RT_BIND_LOCAL ? pj_abs_token(m, r5.y) : RT_INVALID;
    ob_value_const[row] = r6.zw;
    ob_value_const_present[row] = r6.y;
    ob_argument_mode[row] = r6.x & 0xffu;
    ob_member_field_ordinal[row] = r5.w;
    if (kind == RT_HIR_MEMBER_EXPR)
    {
        ob_member_field_word_offset[row] = aux.y;
        ob_member_field_word_count[row] = aux.z;
    }
    if (facts.x != 0u)
    {
        ob_expr_ref_tag[row] = facts.x;
        ob_expr_ref_payload[row] = facts.y;
        ob_value_type[row] = facts.x == PJ_REF_SCALAR ? facts.y : 0u;
        ob_expr_scalar_type[row] = (facts.w << SCALAR_TYPE_SHIFT) | PJ_SCALAR_LINK_NONE;
        ob_aggregate_word_count[row] = facts.x == PJ_REF_INSTANCE ? facts.z : 0u;
    }
    if (function)
    {
        uint status;
        uint result = pj_result(pj_req_result(rank), status);
        uint4 i1 = pj_inf(rank, 1u);
        ob_param_ranges[row] = i1.z != 0u ? uint2(pj_abs_side(m, PJ_SIDE_PARAMS, 0u), i1.z) : uint2(RT_INVALID, 0u);
        ob_function_return_type[row] = result < RT_FIRST_TERM ? result : 0u;
        ob_function_entrypoint[row] = (pj_inf(rank, 4u).w & PJ_FLAG_ENTRY) != 0u ? 1u : 0u;
        ob_function_host_service[row] = RT_INVALID;
        ob_public_decl_index[row] = rank;
        ob_value_type[row] = facts.y;
        ob_expr_scalar_type[row] = (facts.y << SCALAR_TYPE_SHIFT) | PJ_SCALAR_LINK_NONE;
    }
    if (kind == RT_HIR_CALL_EXPR) write_call(row, rank, rel, facts);
}
