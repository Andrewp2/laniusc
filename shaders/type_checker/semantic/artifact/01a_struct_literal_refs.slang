// Project raw-HIR struct-literal inference contexts into dense semantic HIR.
// This is the sole raw-to-dense boundary for this fact; downstream semantic
// consumers never index parser rows.

import gpu_index;
import hir_records;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> struct_lit_context_decl_token;
StructuredBuffer<uint> struct_lit_context_instance;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_aggregate_decl_token_by_hir;
RWStructuredBuffer<uint> semantic_member_field_ordinal_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (dense >= gParams.n_hir_nodes) return;

    uint kind = compact_hir_core[dense].kind;
    if (kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[dense].c;
        if (valid_token(member_token))
            semantic_member_field_ordinal_by_hir[dense] =
                member_result_field_ordinal[member_token];
        return;
    }
    if (kind != HIR_STRUCT_LITERAL_EXPR) return;

    uint instance = struct_lit_context_instance[dense];
    uint contextual_decl = valid_token(instance)
        ? type_instance_decl_token[instance]
        : struct_lit_context_decl_token[dense];
    uint explicit_decl = semantic_aggregate_decl_token_by_hir[dense];
    // A bare generic constructor names the declaration while its arguments
    // come from the checked destination/return context. Preserve an explicit
    // instantiated constructor, but refine a matching scalar declaration to
    // the contextual instance.
    if (valid_token(instance) &&
        (semantic_expr_ref_tag_by_hir[dense] == TYPE_REF_INVALID ||
         explicit_decl == contextual_decl))
    {
        semantic_expr_ref_tag_by_hir[dense] = TYPE_REF_INSTANCE;
        semantic_expr_ref_payload_by_hir[dense] = instance;
        semantic_aggregate_decl_token_by_hir[dense] =
            type_instance_decl_token[instance];
        return;
    }
    if (semantic_expr_ref_tag_by_hir[dense] != TYPE_REF_INVALID)
        return;

    uint decl = contextual_decl;
    if (!valid_token(decl)) return;
    uint tag = decl_type_ref_tag[decl];
    if (tag == TYPE_REF_INVALID) return;
    semantic_expr_ref_tag_by_hir[dense] = tag;
    semantic_expr_ref_payload_by_hir[dense] = decl_type_ref_payload[decl];
    semantic_aggregate_decl_token_by_hir[dense] = decl;
}
