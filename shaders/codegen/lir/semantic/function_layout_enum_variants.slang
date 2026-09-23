// One lane computes one variant's tagged-union width, then publishes the
// maximum for its enum. Declaration collection initializes even empty enums
// to the discriminant width before this pass.

import hir_records;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
RWStructuredBuffer<uint> semantic_struct_word_count_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ENUM_ITEM = 26u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row >= min(compact_variant_count[0u], hir_count)) return;
    HirVariant variant = compact_variants[row];
    if (variant.owner >= hir_count ||
        compact_hir_core[variant.owner].kind != HIR_ENUM_ITEM) return;

    uint start = compact_variant_payload_start[row];
    uint count = compact_variant_payload_count[row];
    uint payload_total = min(compact_variant_payload_row_count[0u], hir_count);
    uint words = 1u; // discriminant
    if (count != 0u && (start >= payload_total || count > payload_total - start))
        words = INVALID;
    for (uint ordinal = 0u; ordinal < count && words != INVALID; ordinal += 1u)
    {
        HirVariantPayload payload = compact_variant_payloads[start + ordinal];
        if (payload.variant != row || payload.ordinal != ordinal ||
            payload.type_node >= hir_count ||
            semantic_expr_ref_tag[payload.type_node] != TYPE_REF_SCALAR)
        {
            words = INVALID;
            break;
        }
        uint type_id = semantic_expr_ref_payload[payload.type_node];
        // Recursive nominal payloads need a dependency-ordered layout pass.
        if (type_id >= TY_STRUCT_BASE)
        {
            words = INVALID;
            break;
        }
        uint payload_words = type_id == SEMANTIC_LIR_TY_STRING ? 2u : 1u;
        words = words > INVALID - payload_words
            ? INVALID : words + payload_words;
    }
    uint ignored;
    InterlockedMax(semantic_struct_word_count_by_hir[variant.owner], words, ignored);
}
