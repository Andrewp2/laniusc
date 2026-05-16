// GPU imported declaration visibility scatter for one namespace table.
//
// Scheduling contract:
// - Dispatch once for type imports and once for value imports after per-import
//   visibility counts have been prefix-scanned on the GPU.
// - For each resolved path import, scatter public declarations from the target
//   module into compact imported-visibility rows keyed by the importing module.
// - This pass seeds row-order arrays for later stable radix sorting. It does
//   not resolve paths, scan source bytes, use hashes, append with atomics,
//   perform CPU lookup, or apply same-source shortcuts.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> import_visible_prefix;
StructuredBuffer<uint> decl_key_count_out;
StructuredBuffer<uint> decl_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_visibility;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_visible_module_id;
RWStructuredBuffer<uint> import_visible_name_id;
RWStructuredBuffer<uint> import_visible_decl_id;
RWStructuredBuffer<uint> import_visible_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;
static const uint ERR_NAME_LIMIT = 11u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.capacity);
}

uint active_decl_count()
{
    return min(decl_key_count_out[0], gParams.capacity);
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

uint decl_module_for_table_row(uint row)
{
    uint decl_i = decl_key_to_decl_id[row];
    return decl_i >= gParams.capacity ? INVALID : decl_module_id[decl_i];
}

uint lower_bound_module(uint module_id)
{
    uint lo = 0u;
    uint hi = active_decl_count();
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_module = decl_module_for_table_row(mid);
        uint key = mid_module == INVALID ? 0u : mid_module + 1u;
        uint target = module_id == INVALID ? 0u : module_id + 1u;
        if (key < target)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

uint upper_bound_module(uint module_id)
{
    uint lo = 0u;
    uint hi = active_decl_count();
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_module = decl_module_for_table_row(mid);
        uint key = mid_module == INVALID ? 0u : mid_module + 1u;
        uint target = module_id == INVALID ? 0u : module_id + 1u;
        if (key <= target)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

void clear_row(uint row)
{
    import_visible_module_id[row] = INVALID;
    import_visible_name_id[row] = INVALID;
    import_visible_decl_id[row] = INVALID;
    import_visible_key_order[row] = row;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= gParams.capacity)
        return;

    clear_row(import_i);

    if (import_i >= active_import_count())
        return;

    uint importing_module = import_module_id[import_i];
    uint target_module = import_target_module_id[import_i];
    if (import_status[import_i] != IMPORT_STATUS_OK || importing_module == INVALID ||
        target_module == INVALID)
        return;

    uint begin = lower_bound_module(target_module);
    uint end = upper_bound_module(target_module);
    uint local_i = 0u;
    [loop]
    for (uint row = begin; row < end; row += 1u)
    {
        uint decl_i = decl_key_to_decl_id[row];
        if (decl_i >= gParams.capacity || decl_visibility[decl_i] != HIR_ITEM_VIS_PUBLIC)
            continue;

        uint dst = import_visible_prefix[import_i] + local_i;
        local_i += 1u;
        if (dst >= gParams.capacity)
        {
            record_error(importing_module, ERR_NAME_LIMIT, dst);
            continue;
        }

        import_visible_module_id[dst] = importing_module;
        import_visible_name_id[dst] = decl_name_id[decl_i];
        import_visible_decl_id[dst] = decl_i;
        import_visible_key_order[dst] = dst;
    }
}
