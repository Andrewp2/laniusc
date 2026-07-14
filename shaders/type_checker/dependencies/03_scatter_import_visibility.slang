// Scatter the import/declaration relation after its per-import count scan.

import gpu_index;
import status;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_dependency_module_id;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_visible_count;
StructuredBuffer<uint> dependency_visible_prefix;
StructuredBuffer<uint> dependency_visible_total;
RWStructuredBuffer<uint> dependency_visible_owner_module;
RWStructuredBuffer<uint> dependency_visible_decl;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint ERR_NAME_LIMIT = 11u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_import_count()
{
    return min(import_count_out[0u], gParams.import_capacity);
}

uint declaration_module(uint declaration_i)
{
    return dependency_declaration_words[declaration_i * DECL_WORDS];
}

uint lower_module_bound(uint module_i)
{
    uint first = 0u;
    uint count = gParams.declaration_count;
    while (count != 0u)
    {
        uint step = count >> 1u;
        uint probe = first + step;
        if (declaration_module(probe) < module_i)
        {
            first = probe + 1u;
            count -= step + 1u;
        }
        else
            count = step;
    }
    return first;
}

uint import_for_visible_row(uint visible_i)
{
    uint first = 0u;
    uint count = active_import_count();
    while (count != 0u)
    {
        uint step = count >> 1u;
        uint probe = first + step;
        if (dependency_visible_prefix[probe] <= visible_i)
        {
            first = probe + 1u;
            count -= step + 1u;
        }
        else
            count = step;
    }
    return first == 0u ? INVALID : first - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint visible_i = linear_thread_id(dtid);
    uint total = dependency_visible_total[0u];
    if (visible_i == 0u && total > gParams.visible_capacity)
        record_min_token_error(status, 0u, ERR_NAME_LIMIT, total);
    if (visible_i >= min(total, gParams.visible_capacity))
        return;
    uint import_i = import_for_visible_row(visible_i);
    if (import_i == INVALID)
        return;
    uint local_i = visible_i - dependency_visible_prefix[import_i];
    if (local_i >= dependency_visible_count[import_i])
        return;
    uint target = import_target_dependency_module_id[import_i];
    uint declaration_i = lower_module_bound(target) + local_i;
    if (declaration_i >= gParams.declaration_count ||
        declaration_module(declaration_i) != target)
        return;
    dependency_visible_owner_module[visible_i] = import_module_id[import_i];
    dependency_visible_decl[visible_i] = declaration_i;
}
