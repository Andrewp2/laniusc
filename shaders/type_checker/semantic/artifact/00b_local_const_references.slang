// Project already-evaluated local constant roots onto their name/path uses.
// This is deliberately ordered after expression evaluation: combining the two
// would make a reference's result depend on cross-workgroup scheduling.

import hir_records;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_hir_node;
RWStructuredBuffer<uint> semantic_value_const_by_hir;
RWStructuredBuffer<uint> semantic_value_const_present_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_NAME = 2u;
static const uint CONST_PRESENT = 0x80000000u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row >= hir_count) return;
    HirCore core = compact_hir_core[row];
    HirPayload payload = compact_hir_payload[row];
    bool name_reference = core.kind == HIR_NAME_EXPR ||
        core.kind == HIR_PATH_EXPR ||
        (core.kind == HIR_EXPR && payload.a == HIR_EXPR_NAME);
    if (!name_reference || payload.d >= gParams.n_tokens) return;

    uint declaration_token = visible_decl[payload.d];
    uint decl = declaration_token < gParams.n_tokens
        ? decl_id_by_name_token[declaration_token] : INVALID;
    uint decl_hir = decl < gParams.n_hir_nodes ? decl_hir_node[decl] : INVALID;
    uint value_hir = decl_hir < hir_count ? compact_const_value[decl_hir] : INVALID;
    if (value_hir >= hir_count ||
        semantic_value_const_present_by_hir[value_hir] != CONST_PRESENT)
        return;
    semantic_value_const_by_hir[row] = semantic_value_const_by_hir[value_hir];
    semantic_value_const_present_by_hir[row] = CONST_PRESENT;
}
