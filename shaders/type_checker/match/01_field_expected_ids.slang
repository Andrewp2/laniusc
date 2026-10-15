// Substitute each struct-literal field's declaration-side expected type under
// its literal's application, as a canonical ID with a checked row
// (field_expected.slang). Recorded after every 04_struct_init_fields that a
// reader of the column follows. One lane per token, and every token is
// written, so the column always follows its inputs.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.mutable_checked_type_graph;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;
import type_checker.match.field_expected;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;

static const uint INVALID = 0xffffffffu;

uint field_expected_id(uint token)
{
    uint tag = struct_init_field_expected_ref_tag[token];
    uint payload = struct_init_field_expected_ref_payload[token];
    uint scope = struct_init_field_expected_context_instance[token];
    if (scope == INVALID || tag == 0u || payload == INVALID) return CT_NONE;
    // A context is a checked application row of the caller.
    if ((scope & 0x80000000u) != 0u || scope >= mutable_type_capacity()) return CT_UNKNOWN;
    // One interning site: the application, then the field's declaration-side
    // reference when it has no ID yet.
    CtSpare spare = ct_spare_none();
    uint env = CT_UNKNOWN;
    uint term = ct_ref(tag, payload);
    [loop]
    for (uint operand = 0u; operand < 2u; operand++)
    {
        if (operand == 1u && term != CT_PENDING && term != CT_NONE) break;
        uint2 reference = operand == 0u ? uint2(3u, scope) : uint2(tag, payload);
        uint id = ct_intern_checked<CtMutableRows>(reference.x, reference.y, spare.record);
        if (operand == 0u) env = id;
        else term = id;
    }
    // The application's operands bind the declaration's parameters by slot.
    if (!ct_is_record(env) || ct_kind(env) != CT_KIND_NAMED) return CT_UNKNOWN;
    SourceSlots slots;
    uint id = ct_subst<SourceSlots>(slots, env, term, true, spare);
    if (!ct_is_resolved(id)) return CT_UNKNOWN;
    // Readers take the field's checked row from ct_row_of; a row another lane
    // is still writing is there by the next round.
    uint failure;
    ct_realize(id, failure);
    return id;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = dtid.x + dtid.y * 16776960u;
    uint count; uint stride;
    struct_init_field_expected_ct.GetDimensions(count, stride);
    if (token >= gParams.n_tokens || token >= count) return;
    struct_init_field_expected_ct[token] = field_expected_id(token);
}
