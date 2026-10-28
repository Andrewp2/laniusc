// Distinct types, step 1: map the tokens the brand check looks up to their
// compact HIR rows. A type node is keyed by its first token, a `let` by its
// name and a parameter by its name. The table is workspace: the check pass
// accepts an entry only when the row's kind and token agree with the key, so
// stale values from an earlier use of the buffer are never read as rows.

import hir_records;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
RWStructuredBuffer<uint> distinct_hir_node_by_token;

static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_STMT_LET = 1u;
static const uint DISPATCH_X_STRIDE = 16776960u;

void publish(uint token, uint node)
{
    if (token < gParams.n_tokens) distinct_hir_node_by_token[token] = node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= min(gParams.n_hir_nodes, compact_hir_count[0u])) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_TYPE) publish(core.token_start, node);
    else if ((core.kind == HIR_LET_STMT || core.kind == HIR_STMT) && payload.a == HIR_STMT_LET)
        publish(payload.b, node);
    else if (core.kind == HIR_PARAM) publish(payload.c, node);
}
