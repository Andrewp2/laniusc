// Initialize dependency projection workspace for one compilation job.
//
// Buffer creation used to supply INVALID sentinels implicitly. Graph-owned
// workspace is zeroed and reused, so sentinel state is now an explicit GPU
// pass before the first dependency page is projected.

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace_value;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> dependency_visible_count;
RWStructuredBuffer<uint> dependency_visible_prefix;
RWStructuredBuffer<uint> dependency_visible_total;
RWStructuredBuffer<uint> dependency_visible_owner_module;
RWStructuredBuffer<uint> dependency_visible_decl;
RWStructuredBuffer<uint> dependency_visible_lookup;
RWStructuredBuffer<uint> dependency_resolved_type_decl;
RWStructuredBuffer<uint> dependency_resolved_value_decl;
RWStructuredBuffer<uint> resolved_dependency_library_id;
RWStructuredBuffer<uint> resolved_dependency_unit_id;
RWStructuredBuffer<uint> resolved_dependency_local_index;
RWStructuredBuffer<uint> resolved_dependency_value_metadata;
RWStructuredBuffer<uint> dependency_call_compare_scan_input;
RWStructuredBuffer<uint> dependency_call_compare_prefix;
RWStructuredBuffer<uint> dependency_call_compare_total;
RWStructuredBuffer<uint> dependency_call_compare_expected_type;
RWStructuredBuffer<uint> dependency_call_compare_actual_instance;
RWStructuredBuffer<uint> dependency_call_compare_error_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (i < gParams.import_capacity)
    {
        dependency_visible_count[i] = 0u;
        dependency_visible_prefix[i] = 0u;
    }
    if (i < gParams.visible_capacity)
    {
        dependency_visible_owner_module[i] = INVALID;
        dependency_visible_decl[i] = INVALID;
    }
    if (i < gParams.lookup_capacity)
        dependency_visible_lookup[i] = INVALID;
    if (i < gParams.path_capacity)
    {
        dependency_resolved_type_decl[i] = INVALID;
        dependency_resolved_value_decl[i] = INVALID;
        resolved_dependency_library_id[i] = INVALID;
        resolved_dependency_unit_id[i] = INVALID;
        resolved_dependency_local_index[i] = INVALID;
        uint value_base = i * 3u;
        resolved_dependency_value_metadata[value_base] = INVALID;
        resolved_dependency_value_metadata[value_base + 1u] = 0u;
        resolved_dependency_value_metadata[value_base + 2u] = 0u;
    }
    if (i < gParams.hir_capacity)
    {
        dependency_call_compare_scan_input[i] = 0u;
        dependency_call_compare_prefix[i] = 0u;
        dependency_call_compare_expected_type[i] = INVALID;
        dependency_call_compare_actual_instance[i] = INVALID;
        dependency_call_compare_error_token[i] = INVALID;
    }
    if (i == 0u)
    {
        dependency_visible_total[0u] = 0u;
        dependency_call_compare_total[0u] = 0u;
    }
}
