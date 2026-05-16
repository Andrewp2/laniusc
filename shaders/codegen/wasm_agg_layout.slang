// Derive bounded aggregate projection metadata for HIR-driven WASM lowering.
//
// This pass stays below the WebGPU storage-buffer limit by publishing only the
// executable projection artifacts consumed by the current body emitter. It uses
// parser-owned HIR aggregate metadata, interned name ids, and GPU type refs;
// it does not inspect source bytes or recognize stdlib names.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> type_instance_decl_token;

RWStructuredBuffer<uint> struct_init_field_index;
RWStructuredBuffer<uint> member_result_field_index;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_ITEM = 27u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint struct_decl_name_token(uint struct_node)
{
    uint start = valid_node(struct_node) ? hir_token_pos[struct_node] : INVALID;
    return start != INVALID && start + 1u < gParams.n_tokens ? start + 1u : INVALID;
}

uint field_name_token(uint field_node)
{
    uint token_i = valid_node(field_node) ? hir_token_pos[field_node] : INVALID;
    return token_i < gParams.n_tokens ? token_i : INVALID;
}

uint field_index_for_decl_and_name(uint decl_i, uint name_id)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        uint struct_node = hir_struct_field_parent_struct[node];
        if (!valid_node(struct_node))
            continue;
        uint field_i = field_name_token(node);
        if (field_i >= gParams.n_tokens)
            continue;
        if (struct_decl_name_token(struct_node) == decl_i &&
            name_id_by_token[field_i] == name_id)
            return hir_struct_field_ordinal[node];
    }
    return INVALID;
}

uint decl_token_for_type_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || payload >= gParams.n_tokens)
        return INVALID;
    uint decl_i = type_instance_decl_token[payload];
    return decl_i < gParams.n_tokens ? decl_i : INVALID;
}

void receiver_ref_for_local_member(uint dot_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (dot_i == 0u)
        return;

    uint receiver_i = dot_i - 1u;
    uint decl_i = receiver_i < gParams.n_tokens ? visible_decl[receiver_i] : INVALID;
    if (decl_i == INVALID || decl_i + 2u >= gParams.n_tokens)
        return;

    uint ref_tag = type_expr_ref_tag[decl_i + 2u];
    uint ref_payload = type_expr_ref_payload[decl_i + 2u];
    if (decl_token_for_type_ref(ref_tag, ref_payload) != INVALID)
    {
        tag = ref_tag;
        payload = ref_payload;
    }
}

void receiver_ref_for_method_receiver(uint dot_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (dot_i == 0u)
        return;

    uint receiver_i = dot_i - 1u;
    uint decl_i = receiver_i < gParams.n_tokens ? visible_decl[receiver_i] : INVALID;
    if (decl_i == INVALID)
        return;

    [loop]
    for (uint fn_i = 0u; fn_i < gParams.n_tokens; fn_i += 1u)
    {
        if (method_decl_param_offset[fn_i] != decl_i)
            continue;

        uint receiver_tag = method_decl_receiver_ref_tag[fn_i];
        uint receiver_payload = method_decl_receiver_ref_payload[fn_i];
        if (decl_token_for_type_ref(receiver_tag, receiver_payload) == INVALID)
            continue;

        tag = receiver_tag;
        payload = receiver_payload;
        return;
    }
}

void receiver_ref_for_member(uint dot_i, out uint tag, out uint payload)
{
    receiver_ref_for_local_member(dot_i, tag, payload);
    if (tag != TYPE_REF_INVALID && payload != INVALID)
        return;

    receiver_ref_for_method_receiver(dot_i, tag, payload);
}

void publish_member_projection(uint member_node)
{
    uint dot_i = valid_node(member_node) ? hir_token_pos[member_node] : INVALID;
    uint member_i = dot_i == INVALID ? INVALID : dot_i + 1u;
    if (member_i >= gParams.n_tokens)
        return;

    uint tag;
    uint payload;
    receiver_ref_for_member(dot_i, tag, payload);
    uint decl_i = decl_token_for_type_ref(tag, payload);
    if (decl_i == INVALID)
        return;

    uint index = field_index_for_decl_and_name(decl_i, name_id_by_token[member_i]);
    if (index != INVALID)
        member_result_field_index[member_i] = index;
}

uint literal_struct_decl_for_field(uint field_node)
{
    uint literal_node = hir_struct_lit_field_parent_lit[field_node];
    uint open_i = valid_node(literal_node) ? hir_token_pos[literal_node] : INVALID;
    uint head_i = open_i != INVALID && open_i > 0u ? open_i - 1u : INVALID;
    uint head_name = head_i < gParams.n_tokens ? name_id_by_token[head_i] : INVALID;
    if (head_name == INVALID)
        return INVALID;

    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        if (hir_kind[node] != HIR_STRUCT_ITEM)
            continue;
        uint decl_i = struct_decl_name_token(node);
        if (decl_i < gParams.n_tokens && name_id_by_token[decl_i] == head_name)
            return decl_i;
    }
    return INVALID;
}

void publish_struct_init_projection(uint field_node)
{
    uint field_i = field_name_token(field_node);
    if (field_i == INVALID || field_i >= gParams.n_tokens)
        return;

    uint decl_i = literal_struct_decl_for_field(field_node);
    uint index = decl_i == INVALID
                     ? INVALID
                     : field_index_for_decl_and_name(decl_i, name_id_by_token[field_i]);
    if (index != INVALID)
        struct_init_field_index[field_i] = index;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i >= active_hir_node_count())
        return;

    if (hir_struct_lit_field_parent_lit[i] != INVALID)
        publish_struct_init_projection(i);
    else if (hir_kind[i] == HIR_MEMBER_EXPR)
        publish_member_projection(i);
}
