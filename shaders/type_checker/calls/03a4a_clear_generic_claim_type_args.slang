// Clear the reusable aggregate-comparison request relation before generic
// claim validation publishes compound claim pairs into it.

import gpu_index;
import type_checker.calls.inference_activity;
import type_checker.calls.inference_blocks;
import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_hir_count;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;

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
    uint node = inference_listed_hir_row(linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE));
    // A node keeps its comparison row while its function is unchanged: the
    // contextual result requests (03a4b) would publish it again.
    if (node >= active_hir_count() || !inference_item_active(compact_hir_core[node].token_start))
        return;
    aggregate_compare_scan_input[node] = 0u;
    aggregate_compare_expected_instance[node] = INVALID;
    aggregate_compare_actual_instance[node] = INVALID;
    aggregate_compare_error_token[node] = INVALID;
    aggregate_compare_error_detail[node] = 0u;
}
