// Count public dependency declarations made visible by each resolved import.
// The packed dependency page carries a compact module-to-declaration index, so
// each lane reads one count without scanning or depending on artifact order.

import dependency_interface;
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
RWStructuredBuffer<uint> dependency_visible_count;

static const uint INVALID = 0xffffffffu;
static const uint IMPORT_STATUS_OK = 0u;
static const uint IMPORT_IDENTITY_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
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
    uint target = import_target_dependency_module_id[import_i * IMPORT_IDENTITY_STRIDE];
    if (target == INVALID)
        return;
    dependency_visible_count[import_i] =
        target < dependency_module_count()
            ? dependency_module_declaration_count(target)
            : 0u;
}
