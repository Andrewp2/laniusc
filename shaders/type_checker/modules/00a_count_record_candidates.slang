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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<uint> compact_variant_count;
RWStructuredBuffer<uint> candidate_counts;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
groupshared uint candidate_prefix[WG_SIZE];

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
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
        HirCore core = compact_hir_core[node];
        HirPayload payload = compact_hir_payload[node];
        row.hir_kind = core.kind;
        row.item_kind = payload.a;
        row.name_token = payload.b;
        row.namespace_kind = payload.c;
        flag = module_record_candidate_bits(row, gParams.n_tokens) != 0u ? 1u : 0u;
    }
    uint inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, WG_SIZE>(
        ltid.x, flag, candidate_prefix);
    if (ltid.x + 1u == WG_SIZE && inclusive != 0u)
        atomic_u32_add(candidate_counts, 0u, inclusive);

    if (node == 0u)
    {
        // Paths are already a compact family. Add their exact row count to the
        // semantic item count so every downstream record family fits without
        // falling back to raw-tree capacity.
        atomic_u32_add(candidate_counts, 0u, compact_path_count[0u]);
        // Variants are a first-class compact family and each becomes exactly
        // one value-namespace declaration record.
        atomic_u32_add(candidate_counts, 0u, compact_variant_count[0u]);
        // Imported callees can contribute at most one parameter row per local
        // call-argument row. Reserve that semantic upper bound without sizing
        // the relation by the raw parse tree.
        candidate_counts[1u] = compact_param_count[0u] + compact_call_arg_count[0u];
        candidate_counts[2u] = compact_call_arg_count[0u];
    }
}
