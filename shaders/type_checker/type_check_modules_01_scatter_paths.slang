// Pre-resolution GPU path metadata foundation.
//
// Scheduling contract:
// - Dispatch after type_check_modules_00_mark_records.slang and a GPU
//   exclusive prefix scan over path_record_flag.
// - This pass scatters compact path records from parser-owned HIR spans.
// - The following segment pass copies path segment ids from name_id_by_token.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_item_path_start;
StructuredBuffer<uint> hir_item_path_end;
StructuredBuffer<uint> path_record_flag;
StructuredBuffer<uint> path_record_kind;
StructuredBuffer<uint> path_record_prefix;

RWStructuredBuffer<uint> path_start;
RWStructuredBuffer<uint> path_len;
RWStructuredBuffer<uint> path_segment_base;
RWStructuredBuffer<uint> path_owner_hir;
RWStructuredBuffer<uint> path_owner_token;
RWStructuredBuffer<uint> path_kind;
RWStructuredBuffer<uint> path_count_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;

static const uint HIR_TYPE = 5u;
static const uint HIR_PATH_EXPR = 33u;

static const uint PATH_RECORD_KIND_NONE = 0u;
static const uint PATH_RECORD_KIND_MODULE_DECL = 1u;
static const uint PATH_RECORD_KIND_IMPORT_PATH = 2u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;


uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_span(uint start, uint end_exclusive)
{
    return start != INVALID && end_exclusive != INVALID && start < end_exclusive &&
           end_exclusive <= gParams.n_tokens;
}


uint path_span_start(uint owner_hir, uint kind)
{
    if (kind == PATH_RECORD_KIND_MODULE_DECL || kind == PATH_RECORD_KIND_IMPORT_PATH)
        return hir_item_path_start[owner_hir];
    if (kind == PATH_RECORD_KIND_HIR_PATH_EXPR && hir_kind[owner_hir] == HIR_PATH_EXPR)
        return hir_token_pos[owner_hir];
    if (kind == PATH_RECORD_KIND_HIR_TYPE_EXPR && hir_kind[owner_hir] == HIR_TYPE)
        return hir_token_pos[owner_hir];
    return INVALID;
}

uint path_span_end(uint owner_hir, uint kind)
{
    if (kind == PATH_RECORD_KIND_MODULE_DECL || kind == PATH_RECORD_KIND_IMPORT_PATH)
        return hir_item_path_end[owner_hir];
    if (kind == PATH_RECORD_KIND_HIR_PATH_EXPR && hir_kind[owner_hir] == HIR_PATH_EXPR)
        return hir_token_end[owner_hir];
    if (kind == PATH_RECORD_KIND_HIR_TYPE_EXPR && hir_kind[owner_hir] == HIR_TYPE)
        return hir_token_end[owner_hir];
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes)
        return;

    uint active = active_hir_node_count();
    if (i >= active)
    {
        if (i == 0u && active == 0u)
            path_count_out[0] = 0u;
        return;
    }

    uint flag = path_record_flag[i];
    uint prefix = path_record_prefix[i];
    if (flag != 0u)
    {
        uint slot = prefix;
        uint kind = path_record_kind[i];
        uint start = path_span_start(i, kind);
        uint end_exclusive = path_span_end(i, kind);
        uint segment_base = slot * MAX_PATH_SEGMENTS;

        path_start[slot] = start;
        path_len[slot] = valid_span(start, end_exclusive) ? end_exclusive - start : 0u;
        path_segment_base[slot] = segment_base;
        path_owner_hir[slot] = i;
        path_owner_token[slot] = start;
        path_kind[slot] = kind;
    }

    if (i + 1u == active)
        path_count_out[0] = prefix + flag;
}
