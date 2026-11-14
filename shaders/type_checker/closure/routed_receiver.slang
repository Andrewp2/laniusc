// The callee and receiver of a copy's routed method call (instance_row_calls):
// 08_exec_select checks them and 09_exec_rows writes them into the copy's
// call record. Included after the kernel's buffers: compact_hir_core,
// compact_param_ranges, compact_param_count, compact_params,
// semantic_param_ref_{tag,payload}_by_row, compact_method_cores and
// type_instance_{kind,elem_ref_tag,elem_ref_payload}.

// The receiver type a method call matched: `receiver` after `count`
// dereferences through reference instances; (EX_INVALID, 0) when one is not
// a reference.
uint2 ex_dereferenced(uint2 receiver, uint count)
{
    uint rows; uint stride;
    type_instance_kind.GetDimensions(rows, stride);
    for (uint step = 0u; step < count; step++)
    {
        if (receiver.x != 3u || receiver.y >= rows || type_instance_kind[receiver.y] != 4u)
            return uint2(EX_INVALID, 0u);
        receiver = uint2(type_instance_elem_ref_tag[receiver.y], type_instance_elem_ref_payload[receiver.y]);
    }
    return receiver;
}

// The template function row a routed call names: a table entry's function
// (IT_CALL_ENTRY) or a nongeneric method (IT_CALL_METHOD); EX_INVALID for
// any other call.
uint ex_routed_function(uint2 call)
{
    if (call.x == IT_CALL_ENTRY) return instance_table[2u * call.y].x;
    if (call.x != IT_CALL_METHOD) return EX_INVALID;
    uint rows; uint stride;
    compact_method_cores.GetDimensions(rows, stride);
    return call.y < rows ? compact_method_cores[call.y].node : EX_INVALID;
}

// The receiver parameter type of the function a routed call names: a table
// entry's realized receiver, stored at its function row (table_rows.slang),
// or a nongeneric method's checked `self` parameter; EX_INVALID when there is
// none.
uint2 ex_routed_receiver_parameter(uint2 call)
{
    if (call.x == IT_CALL_ENTRY)
    {
        uint2 parameter = instance_row_refs[instance_table[2u * call.y].w];
        return parameter.x == 0u || parameter.x == IT_ROW_FAILED
            ? uint2(EX_INVALID, 0u) : uint2(parameter.x - 1u, parameter.y);
    }
    uint function = ex_routed_function(call);
    uint hir_rows; uint stride;
    compact_hir_core.GetDimensions(hir_rows, stride);
    if (function >= hir_rows) return uint2(EX_INVALID, 0u);
    HirRange params = compact_param_ranges[function];
    uint rows;
    compact_params.GetDimensions(rows, stride);
    uint first = params.start;
    if (params.count == 0u || first >= min(compact_param_count[0u], rows) ||
        compact_params[first].owner != function || compact_params[first].type_node != 0xffffffffu)
        return uint2(EX_INVALID, 0u);
    uint tag = semantic_param_ref_tag_by_row[first];
    return tag == 0u ? uint2(EX_INVALID, 0u) : uint2(tag, semantic_param_ref_payload_by_row[first]);
}
