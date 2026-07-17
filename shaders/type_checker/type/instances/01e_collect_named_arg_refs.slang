// Scatter named generic argument refs from the compact type-argument family.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirRange { uint start; uint count; };
struct HirTypeArg { uint owner; uint value; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;

RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_arg_row_start;
RWStructuredBuffer<uint> type_instance_arg_row_count_out;
RWStructuredBuffer<uint> type_instance_arg_row_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_compact_node(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint leaf_token_for_owner(uint owner)
{
    if (!valid_compact_node(owner))
        return INVALID;
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

void mark_instance_unsupported(uint owner, uint leaf_token)
{
    if (valid_token(leaf_token))
        type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
    uint owner_token = valid_compact_node(owner) ? compact_hir_core[owner].token_start : INVALID;
    if (valid_token(owner_token))
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_ERROR;
        type_expr_ref_payload[owner_token] = leaf_token;
    }
    if (valid_token(leaf_token))
    {
        type_expr_ref_tag[leaf_token] = TYPE_REF_ERROR;
        type_expr_ref_payload[leaf_token] = leaf_token;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arg_i = linear_thread_id(dtid);
    uint arg_count = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    if (arg_i >= arg_count)
        return;

    HirTypeArg arg = compact_type_args[arg_i];
    if (!valid_compact_node(arg.owner) || !valid_compact_node(arg.value))
        return;
    HirRange owner_args = compact_type_arg_ranges[arg.owner];
    uint leaf_token = leaf_token_for_owner(arg.owner);
    if (!valid_token(leaf_token) || owner_args.start == INVALID ||
        arg.ordinal >= owner_args.count ||
        type_instance_arg_count[leaf_token] != owner_args.count)
    {
        mark_instance_unsupported(arg.owner, leaf_token);
        return;
    }

    uint row_start = type_instance_arg_row_start[leaf_token];
    uint row_i = row_start == INVALID ? INVALID : row_start + arg.ordinal;
    uint arg_token = compact_hir_core[arg.value].token_start;
    if (row_i == INVALID || row_i >= type_instance_arg_row_count_out[0u] ||
        !valid_token(arg_token) || type_expr_ref_tag[arg_token] == TYPE_REF_INVALID)
    {
        mark_instance_unsupported(arg.owner, leaf_token);
        return;
    }

    uint tag = type_expr_ref_tag[arg_token];
    uint payload = type_expr_ref_payload[arg_token];
    type_instance_arg_row_ref_tag[row_i] = tag;
    type_instance_arg_row_ref_payload[row_i] = payload;
    if (arg.ordinal < TYPE_INSTANCE_ARG_REF_STRIDE)
    {
        uint legacy_i = leaf_token * TYPE_INSTANCE_ARG_REF_STRIDE + arg.ordinal;
        type_instance_arg_ref_tag[legacy_i] = tag;
        type_instance_arg_ref_payload[legacy_i] = payload;
    }
}
