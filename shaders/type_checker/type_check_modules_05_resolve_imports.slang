// GPU import-to-module lookup.
//
// Scheduling contract:
// - Dispatch after import records have been scattered and module key rows have
//   been sorted by the GPU radix passes.
// - Each path import performs a sorted-table lookup against
//   sorted_module_key_order using path segment name ids.
// - This pass writes import_target_module_id and import_status only. It does
//   not make declarations visible, resolve value/type paths, perform CPU path
//   lookup, scan source bytes, use hashes, or apply same-source shortcuts.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_kind;
StructuredBuffer<uint> import_path_id;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_target_module_id;
RWStructuredBuffer<uint> import_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;
static const uint SORT_PATH_SEGMENTS = 8u;

static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint IMPORT_STATUS_UNRESOLVED = 1u;
static const uint IMPORT_STATUS_UNSUPPORTED_STRING = 2u;
static const uint IMPORT_STATUS_PATH_TOO_DEEP = 3u;

static const uint ERR_BAD_HIR = 6u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.module_capacity);
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

uint path_segment_value(uint path_id, uint segment_i)
{
    if (path_id >= gParams.module_capacity)
        return 0u;
    if (segment_i >= min(path_segment_count[path_id], MAX_PATH_SEGMENTS))
        return 0u;

    uint base = path_segment_base[path_id];
    uint name_id = path_segment_name_id[base + segment_i];
    return name_id == INVALID ? 0u : name_id + 1u;
}

uint module_segment_value(uint module_i, uint segment_i)
{
    if (module_i >= active_module_count())
        return 0u;
    if (segment_i >= min(module_key_segment_count[module_i], MAX_PATH_SEGMENTS))
        return 0u;

    uint base = module_key_segment_base[module_i];
    uint name_id = module_key_segment_name_id[base + segment_i];
    return name_id == INVALID ? 0u : name_id + 1u;
}

int compare_path_to_module(uint path_id, uint module_i)
{
    [loop]
    for (uint segment_i = 0u; segment_i < SORT_PATH_SEGMENTS; segment_i += 1u)
    {
        uint left = path_segment_value(path_id, segment_i);
        uint right = module_segment_value(module_i, segment_i);
        if (left < right)
            return -1;
        if (left > right)
            return 1;
    }
    return 0;
}

uint find_module_for_path(uint path_id)
{
    uint lo = 0u;
    uint hi = active_module_count();
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint module_i = sorted_module_key_order[mid];
        int cmp = compare_path_to_module(path_id, module_i);
        if (cmp == 0)
            return module_i;
        if (cmp < 0)
            hi = mid;
        else
            lo = mid + 1u;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= active_import_count())
        return;

    import_target_module_id[import_i] = INVALID;

    if (import_kind[import_i] != HIR_ITEM_IMPORT_TARGET_PATH)
    {
        import_status[import_i] = IMPORT_STATUS_UNSUPPORTED_STRING;
        record_error(import_i, ERR_BAD_HIR, IMPORT_STATUS_UNSUPPORTED_STRING);
        return;
    }

    uint path_id = import_path_id[import_i];
    if (path_id >= gParams.module_capacity)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        record_error(import_i, ERR_BAD_HIR, IMPORT_STATUS_UNRESOLVED);
        return;
    }

    uint count = path_segment_count[path_id];
    if (count == 0u)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        record_error(path_owner_token[path_id], ERR_BAD_HIR, IMPORT_STATUS_UNRESOLVED);
        return;
    }
    if (count > SORT_PATH_SEGMENTS)
    {
        import_status[import_i] = IMPORT_STATUS_PATH_TOO_DEEP;
        record_error(path_owner_token[path_id], ERR_BAD_HIR, IMPORT_STATUS_PATH_TOO_DEEP);
        return;
    }

    uint module_i = find_module_for_path(path_id);
    if (module_i == INVALID)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        record_error(path_owner_token[path_id], ERR_BAD_HIR, IMPORT_STATUS_UNRESOLVED);
        return;
    }

    import_target_module_id[import_i] = module_i;
    import_status[import_i] = IMPORT_STATUS_OK;
}
