// Pre-resolution GPU module/path metadata foundation.
//
// Scheduling contract:
// - Dispatch after parser-owned HIR item fields and name_id_by_token exist.
// - This pass marks candidate rows only. Later GPU projection passes select one
//   packed family bit at a time for prefix scans and compact scatters.
// - It does not resolve imports, decide declaration visibility, accept
//   qualified paths, perform same-source shortcuts, use hash-only lookup, or
//   ask the CPU to classify paths.

import type_checker.modules.record_candidates;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
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

RWStructuredBuffer<uint> record_family_bits;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes)
        return;

    if (i >= active_hir_node_count())
    {
        record_family_bits[i] = 0u;
        return;
    }

    ModuleRecordCandidate row;
    row.candidate_node_kind = node_kind[i];
    row.candidate_hir_kind = hir_kind[i];
    row.candidate_token_pos = hir_token_pos[i];
    row.candidate_token_end = hir_token_end[i];
    row.candidate_item_kind = hir_item_kind[i];
    row.candidate_item_name_token = hir_item_name_token[i];
    row.candidate_item_namespace = hir_item_namespace[i];
    row.candidate_item_path_start = hir_item_path_start[i];
    row.candidate_item_path_end = hir_item_path_end[i];
    row.candidate_import_target_kind = hir_item_import_target_kind[i];
    record_family_bits[i] = module_record_candidate_bits(row, gParams.n_tokens);
}
