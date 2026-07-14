// Count public dependency declarations made visible by each resolved import.
// Dependency declarations are canonically grouped by module, so each lane
// performs two logarithmic bound queries rather than scanning an interface.

import gpu_index;

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
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_dependency_module_id;
StructuredBuffer<uint> dependency_declaration_words;
RWStructuredBuffer<uint> dependency_visible_count;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint IMPORT_STATUS_OK = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
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

uint upper_module_bound(uint module_i)
{
    uint first = 0u;
    uint count = gParams.declaration_count;
    while (count != 0u)
    {
        uint step = count >> 1u;
        uint probe = first + step;
        if (declaration_module(probe) <= module_i)
        {
            first = probe + 1u;
            count -= step + 1u;
        }
        else
            count = step;
    }
    return first;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= gParams.import_capacity)
        return;
    dependency_visible_count[import_i] = 0u;
    if (import_i >= min(import_count_out[0u], gParams.import_capacity) ||
        import_status[import_i] != IMPORT_STATUS_OK ||
        import_module_id[import_i] == INVALID)
        return;
    uint target = import_target_dependency_module_id[import_i];
    if (target == INVALID)
        return;
    dependency_visible_count[import_i] =
        upper_module_bound(target) - lower_module_bound(target);
}
