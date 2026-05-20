// Pre-resolution GPU path metadata foundation.
//
// Scheduling contract:
// - Dispatch after type_check_modules_00_mark_records.slang and a GPU
//   projection/prefix scan over the packed path-record family bit.
// - This pass scatters compact path records from parser-owned HIR spans.
// - The following segment count/scan/scatter passes pack path segment ids from
//   name_id_by_token into dense segment arrays.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import scatter;

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
StructuredBuffer<uint> record_family_bits;
StructuredBuffer<uint> path_record_prefix;

RWStructuredBuffer<uint> path_start;
RWStructuredBuffer<uint> path_len;
RWStructuredBuffer<uint> path_owner_hir;
RWStructuredBuffer<uint> path_owner_token;
RWStructuredBuffer<uint> path_id_by_owner_hir;
RWStructuredBuffer<uint> path_kind;
RWStructuredBuffer<uint> path_count_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_PATH_EXPR = 33u;

static const uint PATH_RECORD_KIND_NONE = 0u;
static const uint PATH_RECORD_KIND_MODULE_DECL = 1u;
static const uint PATH_RECORD_KIND_IMPORT_PATH = 2u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint RECORD_PATH_KIND_SHIFT = 8u;
static const uint RECORD_PATH_KIND_MASK = 0xffu;


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

uint packed_path_record_kind(uint owner_hir)
{
    return (record_family_bits[owner_hir] >> RECORD_PATH_KIND_SHIFT) & RECORD_PATH_KIND_MASK;
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

    path_id_by_owner_hir[i] = INVALID;

    uint flag = path_record_flag[i];
    uint prefix = path_record_prefix[i];
    CompactScatterSlot slot = compact_scatter_slot(flag, prefix);
    if (slot.active != 0u)
    {
        uint kind = packed_path_record_kind(i);
        uint start = path_span_start(i, kind);
        uint end_exclusive = path_span_end(i, kind);
        path_start[slot.dst] = start;
        path_len[slot.dst] = valid_span(start, end_exclusive) ? end_exclusive - start : 0u;
        path_owner_hir[slot.dst] = i;
        path_owner_token[slot.dst] = start;
        path_id_by_owner_hir[i] = slot.dst;
        path_kind[slot.dst] = kind;
    }

    if (i + 1u == active)
        path_count_out[0] = prefix + flag;
}
