// Fold the call constants a body replay made concrete. Call inference ran
// before the replay installed the selected body's constants (00f), so a
// constant claim or a contextual call constant that reaches a body parameter
// through count projections is still a projection: the count of `[V; L]` is
// CountProjection(usize, CountProjection(u32, L)). With L bound, the source
// constant reader (checked_source_constant_value) substitutes it, replays each
// projection's fit, and yields the outer target's value; that value is
// published as an atom, as call inference publishes a concrete count. A
// reference that is not closed under the body's constants, or whose count
// does not fit, is left as it is. The reader binds exactly the parameters 00f
// published (type_const_param_value_by_token), the same table the host reads
// for a bare parameter, so a fold is per replay entry wherever that table is.
import constant_value;
import type_checker.constant_atoms;
import type_checker.constant_atoms_identity;
import type_checker.constant_publication;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> call_const_claim_count_out;
StructuredBuffer<uint> call_const_claim_selected;
RWStructuredBuffer<uint> call_const_claim_ref_kind;
RWStructuredBuffer<uint> call_const_claim_ref_payload;
StructuredBuffer<uint> call_context_constant_mask;
RWStructuredBuffer<uint> call_context_constant_kind;
RWStructuredBuffer<uint> call_context_constant_payload;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint claims; uint contexts; uint selected; uint masks; uint stride;
    call_const_claim_ref_kind.GetDimensions(claims, stride);
    call_const_claim_selected.GetDimensions(selected, stride);
    call_context_constant_kind.GetDimensions(contexts, stride);
    call_context_constant_mask.GetDimensions(masks, stride);
    claims = min(min(claims, selected), call_const_claim_count_out[0u]);
    // Lanes [0, claims) read the selected constant claims; the next lanes the
    // contextual constants, 32 slots per call.
    bool claim = lane < claims;
    uint row = claim ? lane : lane - claims;
    if (claim)
    {
        if (call_const_claim_selected[row] == 0u) return;
    }
    else
    {
        if (lane - claims >= contexts || row / 32u >= masks ||
            (call_context_constant_mask[row / 32u] & (1u << (row % 32u))) == 0u) return;
    }
    uint kind = claim ? call_const_claim_ref_kind[row] : call_context_constant_kind[row];
    uint payload = claim ? call_const_claim_ref_payload[row] : call_context_constant_payload[row];
    // A bare parameter is substituted by its readers; only projections fold.
    if (kind != 3u) return;
    uint3 value;
    if (!checked_source_constant_value(kind, payload, gParams.n_tokens, value)) return;
    uint atom; uint2 reference;
    if (!reserve_checked_constant_row(atom) ||
        !publish_checked_constant_atom_at(atom, value, reference)) return;
    if (claim)
    {
        call_const_claim_ref_kind[row] = reference.x;
        call_const_claim_ref_payload[row] = reference.y;
    }
    else
    {
        call_context_constant_kind[row] = reference.x;
        call_context_constant_payload[row] = reference.y;
    }
}
