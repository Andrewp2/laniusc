import type_checker.constant_parameter_slots;
// One constant reference round, resolve phase: a name or path use of a local
// constant whose initializer root is present takes its value and is staged
// (type_checker.semantic.artifact.const_fold). Staged rows become present in
// 00b2, so this round's result never depends on workgroup order. The first
// round also projects constant-parameter values.

import hir_records;
import type_checker.semantic.artifact.constant_reference;
import type_checker.semantic.artifact.const_fold;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
RWStructuredBuffer<uint> semantic_expr_scalar_type_by_hir;
// (rounds started, constants staged in the current round).
RWStructuredBuffer<uint> local_const_fold_state;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = const_fold_hir_count(gParams.n_hir_nodes);
    if (row >= hir_count) return;
    HirCore core = compact_hir_core[row];
    HirPayload payload = compact_hir_payload[row];
    bool name_reference = core.kind == HIR_NAME_EXPR ||
        core.kind == HIR_PATH_EXPR ||
        (core.kind == HIR_EXPR && payload.a == HIR_EXPR_NAME);
    if (!name_reference || payload.d >= gParams.n_tokens) return;

    uint declaration_token = visible_decl[payload.d];
    // This name/path projection owns constant uses, including parser path
    // wrappers. Concrete replay publishes selected parameter values once;
    // symbolic parameters retain their type without an executable value.
    if (declaration_token < gParams.n_tokens &&
        type_const_param_slot_by_token[declaration_token] < 32u)
    {
        if (local_const_fold_state[0u] != 1u) return;
        uint4 constant = project_checked_constant_value(2u, declaration_token, gParams.n_tokens);
        semantic_value_const_by_hir[row] = constant.yz;
        if (constant.w != 0u) semantic_expr_scalar_type_by_hir[row] = packed_checked_constant_scalar(constant.x);
        // The presence column is a tagged fact: a literal value, an imported
        // variant ordinal, or an unbound constant-parameter declaration. The
        // last case keeps the checked body symbolic until concrete replay.
        semantic_value_const_present_by_hir[row] = constant.w;
        return;
    }
    // Resolved in an earlier round, or an imported constant's path.
    uint present = semantic_value_const_present_by_hir[row];
    if (present == CONST_PRESENT || present == CONST_STAGED) return;
    uint decl = declaration_token < gParams.n_tokens
        ? decl_id_by_name_token[declaration_token] : INVALID;
    if (decl >= gParams.n_hir_nodes || decl_kind[decl] != HIR_ITEM_KIND_CONST)
        return;
    uint decl_hir = decl_hir_node[decl];
    uint value_hir = decl_hir < hir_count ? compact_const_value[decl_hir] : INVALID;
    if (value_hir >= hir_count ||
        semantic_value_const_present_by_hir[value_hir] != CONST_PRESENT)
        return;
    semantic_value_const_by_hir[row] = semantic_value_const_by_hir[value_hir];
    semantic_value_const_present_by_hir[row] = CONST_STAGED;
    InterlockedAdd(local_const_fold_state[1u], 1u);
}
