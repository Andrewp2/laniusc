// GPU method-call key marking for call-result receivers.
//
// Scheduling contract:
// - Dispatch after function and module-qualified call resolution have populated
//   call_fn_index and after type-instance collection has populated
//   fn_return_ref_*.
// - For each HIR call whose callee is a HIR member expression and whose
//   receiver is itself a resolved call expression, publish the method lookup
//   key from the resolved callee's declared return type ref.
// - This pass complements type_check_methods_06_mark_call_keys.slang without
//   exceeding the adapter storage-buffer binding limit. It does not inspect
//   source bytes, hash token text, perform CPU lookup, or compare names by
//   spelling.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> module_id_by_file_id;

RWStructuredBuffer<uint> method_call_receiver_ref_tag;
RWStructuredBuffer<uint> method_call_receiver_ref_payload;
RWStructuredBuffer<uint> method_call_name_id;
RWStructuredBuffer<uint> method_call_site_module_id;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint module_for_hir_node(uint node)
{
    uint token_i = node < active_hir_node_count() ? hir_token_pos[node] : INVALID;
    uint file_id = token_i < active_token_count() ? token_file_id[token_i] : INVALID;
    uint module_id = file_id < gParams.n_hir_nodes ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
}

bool receiver_call_return_type_ref(uint receiver_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    if (receiver_i >= active_token_count())
        return false;

    uint fn_i = call_fn_index[receiver_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
        return false;

    tag = fn_return_ref_tag[fn_i];
    payload = fn_return_ref_payload[fn_i];
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);

    if (i >= active_hir_node_count() || hir_kind[i] != HIR_CALL_EXPR)
        return;

    uint member_node = hir_call_callee_node[i];
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        return;

    uint method_i = hir_member_name_token[member_node];
    if (method_i >= active_token_count())
        return;

    if (method_call_receiver_ref_tag[method_i] != TYPE_REF_INVALID)
        return;

    uint receiver_i = hir_member_receiver_token[member_node];
    if (receiver_i == INVALID || receiver_i >= active_token_count())
        return;

    uint tag;
    uint payload;
    if (!receiver_call_return_type_ref(receiver_i, tag, payload))
        return;

    method_call_name_id[method_i] = name_id_by_token[method_i];
    method_call_site_module_id[method_i] = module_for_hir_node(member_node);
    method_call_receiver_ref_tag[method_i] = tag;
    method_call_receiver_ref_payload[method_i] = payload;
}
