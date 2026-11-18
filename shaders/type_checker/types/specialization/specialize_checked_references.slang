// Apply the selected body's lexical environment to an accepted reference
// column. Every compound type is a graph of these same references, so replacing
// its parameter edges specializes arbitrary nesting without copying or guessing
// layouts. Declaration signatures are not bound to this operation.
//
// gReferenceExtent selects the rows a pass visits. A column whose producers
// allocate rows from a GPU-written count is visited only below that count,
// over a fixed grid of `lanes` lanes (late_semantics.rs,
// BODY_REFERENCE_LANES); every other column is visited in full, one lane
// per row (`lanes` 0).
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
struct ReferenceExtent { uint mode; uint lanes; uint reserved0; uint reserved1; };
ConstantBuffer<ReferenceExtent> gReferenceExtent;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
// The counts the bounded modes read. Not written by this pass.
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_application_count;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> call_explicit_binding_count;
StructuredBuffer<uint> imported_field_ref_total;
RWStructuredBuffer<uint> reference_tag;
RWStructuredBuffer<uint> reference_payload;

static const uint EXTENT_ALL = 0u;
// Source rows hold four arguments per token row; generated rows 32 each from
// there, one block per allocated application (type_checker/types/instances/allocate_application.slang,
// checked_row_realization.slang).
static const uint EXTENT_TYPE_ARGUMENTS = 1u;
// Generic claims, below the scanned claim total (emit_generic_claims).
static const uint EXTENT_CLAIMS = 2u;
// 32 slots per HIR call node (offer_bound_method_members, checked_match_context_publication).
static const uint EXTENT_CALL_CONTEXTS = 3u;
// Explicit bindings, below their allocation counter (03a0).
static const uint EXTENT_EXPLICIT_BINDINGS = 4u;
// Imported field references, below their allocation total (imported_fields).
static const uint EXTENT_IMPORTED_FIELDS = 5u;

uint live_rows(uint capacity)
{
    uint mode = gReferenceExtent.mode;
    uint rows = capacity;
    if (mode == EXTENT_TYPE_ARGUMENTS)
    {
        uint token_rows; uint stride;
        type_generic_param_slot_by_token.GetDimensions(token_rows, stride);
        uint source = min(token_rows, capacity / 4u) * 4u;
        uint blocks = (capacity - source) / 32u;
        rows = source + min(type_application_count[0u], blocks) * 32u;
    }
    else if (mode == EXTENT_CLAIMS)
        rows = call_generic_claim_count_out[0u];
    else if (mode == EXTENT_CALL_CONTEXTS)
        rows = min(compact_hir_count[0u], gParams.n_hir_nodes) * 32u;
    else if (mode == EXTENT_EXPLICIT_BINDINGS)
        rows = call_explicit_binding_count[0u];
    else if (mode == EXTENT_IMPORTED_FIELDS)
        rows = imported_field_ref_total[0u];
    return min(rows, capacity);
}

void specialize(uint row)
{
    if (reference_tag[row] != 2u) return;
    uint parameter = reference_payload[row];
    if (parameter >= gParams.n_tokens) return;
    // apply_body_specialization publishes concrete roots only for the selected declaration's
    // parameters. A same-named parameter in another scope remains symbolic.
    uint tag = type_expr_ref_tag[parameter];
    if (tag != 1u && tag != 3u) return;
    reference_payload[row] = type_expr_ref_payload[parameter];
    reference_tag[row] = tag;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint capacity; uint stride;
    reference_tag.GetDimensions(capacity, stride);
    uint lanes = gReferenceExtent.lanes;
    if (lanes == 0u)
    {
        if (lane < capacity) specialize(lane);
        return;
    }
    uint rows = live_rows(capacity);
    for (uint row = lane; row < rows; row += lanes)
        specialize(row);
}
