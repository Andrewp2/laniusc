// Immutable checked call environments, indexed by complete (callee, slot).
// Their namespace is separate from type-instance IDs. A substituted argument
// is already in caller scope and must not receive this environment again.
import type_checker.calls.claim_lookup;
import type_checker.calls.claim_reference;
import type_checker.calls.explicit_call_environment;

public StructuredBuffer<uint> call_generic_claim_count_out;
public StructuredBuffer<uint> call_generic_claim_callee;
public StructuredBuffer<uint> call_generic_claim_slot;
public StructuredBuffer<uint> call_generic_claim_ref_tag;
public StructuredBuffer<uint> call_generic_claim_ref_payload;
public StructuredBuffer<uint> call_generic_claim_lookup_head;
public StructuredBuffer<uint> call_generic_claim_lookup_next;
// A context producer can rank provisional claims using its expression domain.
// Selection remains indexed by complete (callee, slot); strict validation still
// compares every accepted claim. The ordinary value view preserves stable order.
public interface ICheckedCallClaimPriority
{
    static uint rank(uint row);
}

public struct StableCheckedCallClaimOrder : ICheckedCallClaimPriority
{
    public static uint rank(uint row) { return 0u; }
}

public bool prioritized_checked_call_environment_argument<TPriority : ICheckedCallClaimPriority>(uint environment, uint slot,
    out uint tag, out uint payload)
{
    static const uint INVALID = 0xffffffffu;
    tag = 0u; payload = INVALID;
    if (checked_explicit_environment_argument(environment, slot, tag, payload)) return true;
    if (environment == INVALID || (environment & 0x80000000u) == 0u || slot >= 32u) return false;
    uint callee = environment & 0x7fffffffu;
    uint capacity; uint stride;
    call_generic_claim_callee.GetDimensions(capacity, stride);
    uint count = min(call_generic_claim_count_out[0u], capacity);
    if (count == 0u) return false;
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    uint accepted = INVALID;
    uint accepted_priority = INVALID;
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) return false;
        if (call_generic_claim_callee[row] == callee && call_generic_claim_slot[row] == slot &&
            checked_claim_reference(call_generic_claim_ref_tag[row], call_generic_claim_ref_payload[row]))
        {
            uint priority = TPriority.rank(row);
            if (priority < accepted_priority || (priority == accepted_priority && row < accepted))
            { accepted = row; accepted_priority = priority; }
        }
        link = call_generic_claim_lookup_next[row];
    }
    if (accepted == INVALID) return false;
    tag = call_generic_claim_ref_tag[accepted]; payload = call_generic_claim_ref_payload[accepted];
    return true;
}

public bool checked_call_environment_argument(uint environment, uint slot,
    out uint tag, out uint payload)
{
    return prioritized_checked_call_environment_argument<StableCheckedCallClaimOrder>(
        environment, slot, tag, payload);
}

// Explicit rejected-argument marker; never a binding for a generic slot.
// Called only on a failed materialization, so valid calls add no probes.
public bool checked_call_environment_rejected(uint callee)
{
    uint capacity; uint stride;
    call_generic_claim_callee.GetDimensions(capacity, stride);
    uint count = min(call_generic_claim_count_out[0u], capacity);
    if (count == 0u) return false;
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(callee, 32u, count)];
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) return false;
        if (call_generic_claim_callee[row] == callee && call_generic_claim_slot[row] == 32u &&
            call_generic_claim_ref_tag[row] == 4u) return true;
        link = call_generic_claim_lookup_next[row];
    }
    return false;
}
