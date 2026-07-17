// Collect named generic instances from dense HIR owners and compact type args.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirRange { uint start; uint count; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint leaf_token_for_owner(uint owner)
{
    uint path_i = path_id_by_owner_hir[owner];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path_i == INVALID || path_i >= path_count)
        return INVALID;
    uint count = path_segment_count[path_i];
    if (count == 0u)
        return INVALID;
    uint row = path_segment_base[path_i] + count - 1u;
    return row < gParams.n_tokens ? path_segment_token[row] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint owner = linear_thread_id(dtid);
    if (owner >= active_hir_count())
        return;
    if (compact_hir_core[owner].kind != HIR_TYPE ||
        compact_hir_payload[owner].a != HIR_TYPE_FORM_PATH)
        return;

    HirRange args = compact_type_arg_ranges[owner];
    if (args.count == 0u || args.start == INVALID)
        return;

    uint owner_token = compact_hir_core[owner].token_start;
    uint leaf_token = leaf_token_for_owner(owner);
    if (!valid_token(owner_token) || !valid_token(leaf_token))
        return;

    type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[owner_token] = leaf_token;
    type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[leaf_token] = leaf_token;
    type_instance_kind[leaf_token] = TYPE_INSTANCE_NAMED;
    type_instance_head_token[leaf_token] = leaf_token;
    // The compact-row scan overwrites this provisional value before argument
    // refs are scattered. Keeping a non-invalid seed preserves the existing
    // scan contract without imposing a fixed argument width.
    type_instance_arg_start[leaf_token] = args.start;
    type_instance_arg_count[leaf_token] = args.count;
    type_instance_state[leaf_token] = TYPE_INSTANCE_UNRESOLVED;
}
