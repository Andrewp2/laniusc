// GPU method-call key marking from parser/HIR call and member records.
//
// Scheduling contract:
// - Dispatch after visible declarations, type refs, name ids, and module-file
//   maps are available.
// - For each HIR call whose callee is a HIR member expression, this pass
//   publishes a lookup key from parser-owned member metadata:
//   (receiver type-ref tag/payload, interned method name id, call-site module
//   id). The resolver derives the receiver owner module from GPU type/module
//   maps and uses the call-site module id for private method visibility.
// - Receiver type refs are read from declaration-token keyed type-reference
//   records. A follow-up pass handles receiver expressions that are already
//   resolved calls. This pass does not inspect source bytes, hash token text,
//   perform CPU lookup, or compare names by spelling.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
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

bool receiver_decl_type_ref(uint receiver_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint decl_i = receiver_i < active_token_count() ? visible_decl[receiver_i] : INVALID;
    if (decl_i == INVALID || decl_i >= active_token_count())
        return false;

    tag = decl_type_ref_tag[decl_i];
    payload = decl_type_ref_payload[decl_i];
    return tag != TYPE_REF_INVALID && payload != INVALID;
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

uint module_for_decl_token(uint decl_i)
{
    uint file_id = decl_i < active_token_count() ? token_file_id[decl_i] : INVALID;
    uint module_id = file_id < gParams.n_hir_nodes ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
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

    uint receiver_i = hir_member_receiver_token[member_node];
    if (receiver_i == INVALID || receiver_i >= active_token_count())
        return;

    method_call_name_id[method_i] = name_id_by_token[method_i];
    uint decl_i = visible_decl[receiver_i];
    uint call_site_module = module_for_decl_token(decl_i);
    method_call_site_module_id[method_i] =
        call_site_module == INVALID ? module_for_hir_node(member_node) : call_site_module;

    uint tag;
    uint payload;
    if (!receiver_decl_type_ref(receiver_i, tag, payload))
        return;

    method_call_receiver_ref_tag[method_i] = tag;
    method_call_receiver_ref_payload[method_i] = payload;
}
