// Project one canonical checked type reference per dense expression HIR row.
// Downstream validation consumes this artifact instead of reconstructing an
// expression's type from token-keyed declaration and call work tables.

import hir_records;
import gpu_index;
import checked_semantic_artifact;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_scalar_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_array_length_by_hir;
RWStructuredBuffer<uint> semantic_member_field_ordinal_by_hir;
RWStructuredBuffer<uint> semantic_iterable_kind_by_hir;
RWStructuredBuffer<uint> semantic_function_result_word_count_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_PATH_EXPR = 33u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

void name_token_ref(uint token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token)) return;

    uint decl = visible_decl[token];
    if (!valid_token(decl)) decl = token;
    tag = decl_type_ref_tag[decl];
    payload = decl_type_ref_payload[decl];
    if (tag != TYPE_REF_INVALID) return;

    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    semantic_member_field_ordinal_by_hir[node] = INVALID;
    semantic_iterable_kind_by_hir[node] = 0u;
    semantic_function_result_word_count_by_hir[node] = 0u;

    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (valid_hir(node))
    {
        HirCore core = compact_hir_core[node];
        HirPayload hir_payload = compact_hir_payload[node];
        uint scalar = compact_expr_scalar_type[node] >> SCALAR_TYPE_SHIFT;
        if (scalar != 0u)
        {
            tag = TYPE_REF_SCALAR;
            payload = scalar;
        }
        else if (core.kind == HIR_CALL_EXPR)
        {
            CheckedCallArtifact call = semantic_calls_by_hir[node];
            tag = call.return_ref_tag;
            payload = call.return_ref_payload;
        }
        // Scalar index results were derived from the compact base operand by
        // expression typing. Aggregate index results are projected by the
        // dense array/slice reference pass that follows this pass.
        else if (core.kind == HIR_INDEX_EXPR) { }
        else if (core.kind == HIR_MEMBER_EXPR)
        {
            uint token = hir_payload.c;
            if (valid_token(token))
            {
                tag = member_result_ref_tag[token];
                payload = member_result_ref_payload[token];
            }
        }
        else if (core.kind == HIR_NAME_EXPR)
        {
            name_token_ref(hir_payload.d, tag, payload);
        }
        // Array literals are contextually typed and validated by the
        // array-literal projection pass. A punctuation-token type row is not
        // a canonical expression reference and must not enter the general
        // aggregate comparator as though it were an inferred instance.
        else if (core.kind == HIR_ARRAY_EXPR)
        {
        }
        else if (core.kind == HIR_PATH_EXPR)
        {
            name_token_ref(core.token_start, tag, payload);
        }
    }
    semantic_expr_ref_tag_by_hir[node] = tag;
    semantic_expr_ref_payload_by_hir[node] = payload;
    semantic_array_length_by_hir[node] = INVALID;
}
