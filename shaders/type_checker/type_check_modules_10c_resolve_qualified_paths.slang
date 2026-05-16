// GPU qualified path resolution for one namespace table.
//
// Scheduling contract:
// - Dispatch after module keys and declaration namespace lookup tables are
//   sorted and materialized.
// - Multi-segment HIR path expressions resolve by looking up the prefix as a
//   module path and then looking up the leaf in that module's declaration
//   table. One-segment paths are handled by local/imported lookup passes.
// - It does not scan source bytes, use hashes, perform CPU lookup, or apply
//   same-source shortcuts.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> decl_key_count_out;
StructuredBuffer<uint> decl_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;

RWStructuredBuffer<uint> resolved_decl;
RWStructuredBuffer<uint> resolved_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_MODULE = 5u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint PATH_RESOLVE_STATUS_PATH_TOO_DEEP = 7u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.capacity);
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.capacity);
}

uint active_decl_count()
{
    return min(decl_key_count_out[0], gParams.capacity);
}

uint encoded_id(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

uint path_segment_value(uint path_i, uint segment_i)
{
    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (segment_i >= count)
        return 0u;
    uint name_id = path_segment_name_id[path_segment_base[path_i] + segment_i];
    return encoded_id(name_id);
}

uint module_segment_value(uint module_i, uint segment_i)
{
    if (module_i >= active_module_count())
        return 0u;
    if (segment_i >= min(module_key_segment_count[module_i], MAX_PATH_SEGMENTS))
        return 0u;
    uint name_id = module_key_segment_name_id[module_key_segment_base[module_i] + segment_i];
    return encoded_id(name_id);
}

int compare_path_prefix_to_module(uint path_i, uint prefix_count, uint module_i)
{
    [loop]
    for (uint segment_i = 0u; segment_i < SORT_PATH_SEGMENTS; segment_i += 1u)
    {
        uint left = segment_i < prefix_count ? path_segment_value(path_i, segment_i) : 0u;
        uint right = module_segment_value(module_i, segment_i);
        if (left < right)
            return -1;
        if (left > right)
            return 1;
    }
    return 0;
}

uint find_module_for_path_prefix(uint path_i, uint prefix_count)
{
    uint lo = 0u;
    uint hi = active_module_count();
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint module_i = sorted_module_key_order[mid];
        int cmp = compare_path_prefix_to_module(path_i, prefix_count, module_i);
        if (cmp == 0)
            return module_i;
        if (cmp < 0)
            hi = mid;
        else
            lo = mid + 1u;
    }
    return INVALID;
}

int compare_decl_key(uint row, uint module_id, uint name_id)
{
    uint decl_i = decl_key_to_decl_id[row];
    uint row_module = decl_i < gParams.capacity ? decl_module_id[decl_i] : INVALID;
    uint row_name = decl_i < gParams.capacity ? decl_name_id[decl_i] : INVALID;
    uint left_module = encoded_id(row_module);
    uint right_module = encoded_id(module_id);
    if (left_module < right_module)
        return -1;
    if (left_module > right_module)
        return 1;

    uint left_name = encoded_id(row_name);
    uint right_name = encoded_id(name_id);
    if (left_name < right_name)
        return -1;
    if (left_name > right_name)
        return 1;
    return 0;
}

uint find_decl(uint module_id, uint name_id)
{
    uint lo = 0u;
    uint hi = active_decl_count();
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        int cmp = compare_decl_key(mid, module_id, name_id);
        if (cmp < 0)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo < active_decl_count() && compare_decl_key(lo, module_id, name_id) == 0)
        return decl_key_to_decl_id[lo];
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count() ||
        (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR &&
         path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR))
        return;

    uint count = path_segment_count[path_i];
    if (count <= 1u)
        return;
    if (count - 1u > SORT_PATH_SEGMENTS)
    {
        resolved_status[path_i] = PATH_RESOLVE_STATUS_PATH_TOO_DEEP;
        return;
    }

    uint module_i = find_module_for_path_prefix(path_i, count - 1u);
    if (module_i == INVALID)
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED_MODULE;
        return;
    }

    uint leaf_name_id = path_segment_name_id[path_segment_base[path_i] + count - 1u];
    uint decl_i = find_decl(module_i, leaf_name_id);
    if (decl_i == INVALID)
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    resolved_decl[path_i] = decl_i;
    resolved_status[path_i] = PATH_RESOLVE_STATUS_OK;
}
