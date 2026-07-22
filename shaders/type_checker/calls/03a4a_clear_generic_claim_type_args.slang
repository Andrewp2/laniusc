// Clear the reusable aggregate-comparison request relation before generic
// claim validation publishes compound claim pairs into it.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> type_subtree_compare_scan_input;
RWStructuredBuffer<uint> type_subtree_compare_left_root;
RWStructuredBuffer<uint> type_subtree_compare_right_root;
RWStructuredBuffer<uint> type_subtree_compare_error_token;
RWStructuredBuffer<uint> type_subtree_compare_error_detail;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u
        ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (node >= active_hir_count())
        return;
    aggregate_compare_scan_input[node] = 0u;
    aggregate_compare_expected_instance[node] = INVALID;
    aggregate_compare_actual_instance[node] = INVALID;
    aggregate_compare_error_token[node] = INVALID;
    aggregate_compare_error_detail[node] = 0u;
    type_subtree_compare_scan_input[node] = 0u;
    type_subtree_compare_left_root[node] = INVALID;
    type_subtree_compare_right_root[node] = INVALID;
    type_subtree_compare_error_token[node] = INVALID;
    type_subtree_compare_error_detail[node] = 0u;
}
