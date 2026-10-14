// Publish each complete constant argument binding once per claim index.
// Bindings are selected by evidence strength, not dispatch/lookup order:
// exact before count identity, then the lowest claim row. Every published
// claim must pass the checked descriptor and agree with the current selection;
// otherwise the relation is rejected. One lane per claim row; the first row of
// each (callee, slot) chain group validates the group and stores the outcome
// in its own row, which is the row every reader reaches first.
import type_checker.calls.claim_lookup;
import type_checker.concrete_type_equality;
import type_checker.calls.constant_claim_identity;
import type_checker.constant_atoms_identity;

StructuredBuffer<uint> call_const_claim_count_out;
StructuredBuffer<uint> call_const_claim_callee;
StructuredBuffer<uint> call_const_claim_slot;
StructuredBuffer<uint> call_const_claim_ref_kind;
StructuredBuffer<uint> call_const_claim_ref_payload;
StructuredBuffer<uint> call_const_claim_identity_mode;
StructuredBuffer<uint> call_const_claim_lookup_head;
StructuredBuffer<uint> call_const_claim_lookup_next;
// x=kind, y=value, z=identity mode | ACCEPTED, w=selected row.
RWStructuredBuffer<uint4> call_const_env_binding;

static const uint INVALID = 0xffffffffu;
static const uint ACCEPTED = 0x80000000u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint capacity; uint stride;
    call_const_claim_callee.GetDimensions(capacity, stride);
    uint count = min(call_const_claim_count_out[0u], capacity);
    if (row >= count) return;
    uint callee = call_const_claim_callee[row];
    uint slot = call_const_claim_slot[row];
    if (slot >= 32u) return;
    uint tokens = checked_source_constant_parameter_capacity();
    uint kind = 0u; uint value = INVALID; uint identity_mode = 0u; uint selected_row = INVALID;
    ConstantReferenceDescriptor selected; uint selected_scalar = 0u;
    bool first = true;
    uint link = call_const_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    [loop]
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint candidate_row = link - 1u;
        if (candidate_row >= count) break;
        if (call_const_claim_callee[candidate_row] == callee && call_const_claim_slot[candidate_row] == slot)
        {
            // Another lane owns the group unless this row is its first match.
            if (first && candidate_row != row) return;
            first = false;
            uint2 candidate = uint2(call_const_claim_ref_kind[candidate_row],
                call_const_claim_ref_payload[candidate_row]);
            uint mode = call_const_claim_identity_mode[candidate_row];
            // An unproduced provisional claim is not evidence. Every published
            // reference, including a projection, must pass the descriptor check.
            if (candidate.x != 0u || candidate.y != INVALID)
            {
                ConstantReferenceDescriptor descriptor; uint scalar;
                if (!checked_constant_claim_descriptor(candidate, mode, tokens, descriptor, scalar) ||
                    (selected_row != INVALID && (selected_scalar != scalar ||
                        !constant_reference_descriptors_equal<CheckedSourceConstantGraph,
                            CheckedSourceConstantEnvironment, CheckedSourceConstantGraph,
                            CheckedSourceConstantEnvironment>(selected, descriptor, tokens,
                                identity_mode == 1u || mode == 1u)))) break;
                if (selected_row == INVALID || mode < identity_mode ||
                    (mode == identity_mode && candidate_row < selected_row))
                {
                    kind = candidate.x; value = candidate.y;
                    identity_mode = mode; selected_row = candidate_row;
                    selected = descriptor; selected_scalar = scalar;
                }
            }
        }
        link = call_const_claim_lookup_next[candidate_row];
    }
    if (first) return;
    bool accepted = link == 0u && selected_row != INVALID;
    call_const_env_binding[row] = uint4(kind, value, identity_mode | (accepted ? ACCEPTED : 0u),
        selected_row);
}
