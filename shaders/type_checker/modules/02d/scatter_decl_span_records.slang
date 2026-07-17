// Pre-resolution GPU declaration span scatter.
//
// Scheduling contract:
// - Dispatch after decl_record_flag has an exclusive GPU prefix scan.
// - This pass scatters declaration token spans into dense declaration records.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import scatter;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_record_flag;
StructuredBuffer<uint> decl_record_prefix;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

RWStructuredBuffer<uint> decl_name_token;
RWStructuredBuffer<uint> decl_token_start;
RWStructuredBuffer<uint> decl_token_end;
RWStructuredBuffer<uint> decl_id_by_name_token;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes)
        return;

    CompactScatterSlot slot = compact_scatter_slot(decl_record_flag[i], decl_record_prefix[i]);
    if (slot.active == 0u)
        return;

    HirCore core = compact_hir_core[i];
    uint name_token = compact_hir_payload[i].b;
    decl_name_token[slot.dst] = name_token;
    decl_token_start[slot.dst] = core.token_start;
    decl_token_end[slot.dst] = core.token_end;
    if (name_token < gParams.n_tokens)
        decl_id_by_name_token[name_token] = slot.dst;
}
