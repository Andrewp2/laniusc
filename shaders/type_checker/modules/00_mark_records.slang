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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

RWStructuredBuffer<uint> record_family_bits;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
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
    HirCore core = compact_hir_core[i];
    HirPayload payload = compact_hir_payload[i];
    row.hir_kind = core.kind;
    row.item_kind = payload.a;
    row.name_token = payload.b;
    row.namespace_kind = payload.c;
    record_family_bits[i] = module_record_candidate_bits(row, gParams.n_tokens);
}
