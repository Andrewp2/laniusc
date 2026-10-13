// Included after canonical checked graph/storage resources in count and scatter.
uint receiver_kind(uint tag, uint payload)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return tag == 3u && payload < capacity ? type_instance_kind[payload] : 0u;
}

uint receiver_native_words(uint tag, uint payload, uint hir_count)
{
    uint kind = receiver_kind(tag, payload);
    if (kind == 4u) return 1u;
    if (kind == 3u) return NATIVE_SLICE_WORDS;
    if (kind == 1u || kind == 2u) return type_instance_native_words[payload];
    if (tag == 1u && payload != 0u && payload < 128u) return payload == 7u ? 2u : 1u;
    if (tag == 1u && payload >= 4096u)
    {
        uint token = payload - 4096u;
        uint owner = token < gParams.n_tokens ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
        if (owner < hir_count && compact_hir_core[owner].kind == 27u)
            return semantic_struct_word_count_by_hir[owner];
        token = payload >= 6144u ? payload - 6144u : LIR_INVALID;
        owner = token < gParams.n_tokens ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
        if (owner < hir_count && compact_hir_core[owner].kind == 26u)
            return semantic_struct_word_count_by_hir[owner];
    }
    return LIR_INVALID;
}

bool receiver_aggregate(uint tag, uint payload)
{
    uint kind = receiver_kind(tag, payload);
    return kind == 1u || kind == 2u || kind == 3u || (tag == 1u && payload >= 128u);
}

uint receiver_machine_type(uint tag, uint payload)
{
    uint kind = receiver_kind(tag, payload);
    if (kind == 4u) return SEMANTIC_LIR_TY_POINTER;
    if (kind == 2u) return type_instance_elem_ref_tag[payload] == 1u &&
        type_instance_elem_ref_payload[payload] == 3u ? 131u : 128u;
    if (kind == 3u) return 128u;
    if (kind == 1u) return 4096u;
    return tag == 1u ? payload : 0u;
}

bool receiver_needs_abi_copy(uint tag, uint payload)
{
    // PLACE_LOAD already owns one snapshot. Only this existing call ABI
    // requires a second representation conversion from canonical words.
    return receiver_kind(tag, payload) == 2u &&
        type_instance_elem_ref_tag[payload] == 1u &&
        type_instance_elem_ref_payload[payload] == 3u;
}

uint receiver_adjustment_rows(CheckedCallArtifact call)
{
    if (call.receiver_deref_count == 0u) return 0u;
    if (call.receiver_adjustment_kind == 2u) return call.receiver_deref_count - 1u;
    return call.receiver_deref_count +
        (receiver_needs_abi_copy(call.receiver_matched_ref_tag, call.receiver_matched_ref_payload) ? 1u : 0u);
}

// A member/index consumes its base at the same checked referent as method
// lookup. Aggregate referents remain live addresses; descriptor referents
// must become complete values before the projection reads descriptor lanes.
// Method-callee member syntax is owned by the call's explicit adjustment.
bool receiver_is_projection_base(uint node, uint hir_count)
{
    uint cursor = node;
    for (uint depth = 0u; depth < 64u && cursor < hir_count; depth++)
    {
        uint parent = compact_expr_parent[cursor];
        if (parent >= hir_count) return false;
        HirCore core = compact_hir_core[parent];
        HirPayload payload = compact_hir_payload[parent];
        if ((core.kind == HIR_MEMBER_EXPR || core.kind == HIR_INDEX_EXPR) && payload.b == cursor)
        {
            uint consumer = compact_expr_parent[parent];
            if (core.kind == HIR_MEMBER_EXPR && consumer < hir_count &&
                compact_hir_core[consumer].kind == HIR_CALL_EXPR &&
                compact_hir_payload[consumer].a == parent)
                return false;
            return true;
        }
        if (payload.a != HIR_EXPR_FORWARD || payload.b != cursor) return false;
        cursor = parent;
    }
    return false;
}

uint projection_adjustment_rows(uint node, uint hir_count)
{
    if (!receiver_is_projection_base(node, hir_count)) return 0u;
    uint tag = semantic_expr_ref_tag[node];
    uint payload = semantic_expr_ref_payload[node];
    uint depth = 0u;
    while (receiver_kind(tag, payload) == 4u && depth < 64u)
    {
        uint reference = payload;
        tag = type_instance_elem_ref_tag[reference];
        payload = type_instance_elem_ref_payload[reference];
        depth++;
    }
    if (receiver_kind(tag, payload) == 4u) return LIR_INVALID;
    if (depth == 0u) return 0u;
    uint kind = receiver_kind(tag, payload);
    bool descriptor = kind == 3u || (tag == 1u && payload == SEMANTIC_LIR_TY_STRING);
    return descriptor ? depth : depth - 1u;
}

void projection_adjusted_ref(uint node, uint loads, out uint tag, out uint payload)
{
    tag = semantic_expr_ref_tag[node];
    payload = semantic_expr_ref_payload[node];
    for (uint depth = 0u; depth < loads && depth < 64u; depth++)
    {
        if (receiver_kind(tag, payload) != 4u) { tag = 0u; payload = 0u; return; }
        uint reference = payload;
        tag = type_instance_elem_ref_tag[reference];
        payload = type_instance_elem_ref_payload[reference];
    }
}
