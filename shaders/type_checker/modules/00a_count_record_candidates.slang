// Count the union of compact module/import/declaration/path candidate rows.

import atomics;
import prefix_scan;
import type_checker.modules.record_candidates;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_item_namespace;
StructuredBuffer<uint> hir_item_path_start;
StructuredBuffer<uint> hir_item_path_end;
StructuredBuffer<uint> hir_item_import_target_kind;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_call_arg_parent_call;
RWStructuredBuffer<uint> candidate_counts;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_PARAM = 4u;
groupshared uint candidate_prefix[WG_SIZE];

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint node = linear_thread_id(dtid);
    uint flag = 0u;
    if (node < active_hir_count())
    {
        ModuleRecordCandidate row;
        row.candidate_node_kind = node_kind[node];
        row.candidate_hir_kind = hir_kind[node];
        row.candidate_token_pos = hir_token_pos[node];
        row.candidate_token_end = hir_token_end[node];
        row.candidate_item_kind = hir_item_kind[node];
        row.candidate_item_name_token = hir_item_name_token[node];
        row.candidate_item_namespace = hir_item_namespace[node];
        row.candidate_item_path_start = hir_item_path_start[node];
        row.candidate_item_path_end = hir_item_path_end[node];
        row.candidate_import_target_kind = hir_item_import_target_kind[node];
        flag = module_record_candidate_bits(row, gParams.n_tokens) != 0u ? 1u : 0u;
    }
    uint inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, WG_SIZE>(
        ltid.x, flag, candidate_prefix);
    if (ltid.x + 1u == WG_SIZE && inclusive != 0u)
        atomic_u32_add(candidate_counts, 0u, inclusive);

    uint param_flag = node < active_hir_count() && hir_kind[node] == HIR_PARAM &&
                              hir_param_record[node].x != INVALID
                          ? 1u
                          : 0u;
    inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, WG_SIZE>(
        ltid.x, param_flag, candidate_prefix);
    if (ltid.x + 1u == WG_SIZE && inclusive != 0u)
        atomic_u32_add(candidate_counts, 1u, inclusive);

    uint arg_flag = node < active_hir_count() &&
                            hir_call_arg_parent_call[node] != INVALID
                        ? 1u
                        : 0u;
    inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, WG_SIZE>(
        ltid.x, arg_flag, candidate_prefix);
    if (ltid.x + 1u == WG_SIZE && inclusive != 0u)
        atomic_u32_add(candidate_counts, 2u, inclusive);
}
