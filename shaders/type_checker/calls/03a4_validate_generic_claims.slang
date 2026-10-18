// Validate direct-call generic claims after final call resolution: each
// claim against the call's explicit and contextual arguments for its slot,
// and against the slot's canonical (first concrete) claim. Operands compare
// by canonical ID (docs/canonical-type-ids.md); rows written during
// inference are interned on demand.
import hir_records;
import status;
import type_checker.calls.claim_lookup;
import type_checker.calls.claim_reference;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.checked_type_identity;
import type_checker.checked_slots;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_arg_row;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
StructuredBuffer<uint> call_inference_state;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_SCALAR = 1u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint generic_claim_capacity()
{
    uint base = max(active_token_count(), active_hir_node_count());
    return base > INVALID / GENERIC_CLAIM_CAPACITY_MULTIPLIER ? INVALID : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint claim_error_token(uint row, uint fallback_token)
{
    uint arg_row = call_generic_claim_arg_row[row];
    uint arg_node = arg_row < active_hir_node_count() ? call_arg_row_node[arg_row] : INVALID;
    if (valid_node(arg_node))
    {
        uint token = compact_hir_core[arg_node].token_start;
        if (valid_token(token))
            return token;
    }
    return fallback_token;
}

bool concrete_claim(uint row)
{
    return call_generic_claim_callee[row] != INVALID && call_generic_claim_slot[row] < 32u &&
        checked_claim_reference(call_generic_claim_ref_tag[row], call_generic_claim_ref_payload[row]);
}

uint canonical_claim_row(uint row, uint active_count)
{
    uint callee = call_generic_claim_callee[row];
    uint slot = call_generic_claim_slot[row];
    uint bucket = call_claim_lookup_bucket(callee, slot, active_count);
    uint link = call_generic_claim_lookup_head[bucket];
    uint canonical = INVALID;
    for (uint step = 0u; step < active_count && link != 0u; step += 1u)
    {
        uint candidate = link - 1u;
        if (candidate >= active_count)
            break;
        if (concrete_claim(candidate) &&
            call_generic_claim_callee[candidate] == callee &&
            call_generic_claim_slot[candidate] == slot)
        {
            canonical = min(canonical, candidate);
        }
        link = call_generic_claim_lookup_next[candidate];
    }
    return canonical;
}

// The operand this claim must equal: 0 the explicit argument, 1 the
// contextual argument, 2 the canonical claim. False when there is none.
bool expected_operand(uint row, uint prev_row, uint which, out uint tag, out uint payload)
{
    uint environment = 0x80000000u | call_generic_claim_callee[row];
    uint slot = call_generic_claim_slot[row];
    tag = 0u; payload = INVALID;
    if (which == 0u) return checked_explicit_environment_argument(environment, slot, tag, payload);
    if (which == 1u) return checked_context_environment_argument(environment, slot, tag, payload);
    if (prev_row == INVALID || prev_row == row) return false;
    tag = call_generic_claim_ref_tag[prev_row];
    payload = call_generic_claim_ref_payload[prev_row];
    return true;
}

void validate_claim_at(uint row)
{
    uint active_count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    if (row >= active_count || !concrete_claim(row))
        return;

    uint prev_row = canonical_claim_row(row, active_count);
    uint tag = call_generic_claim_ref_tag[row];
    uint payload = call_generic_claim_ref_payload[row];
    uint spare = CT_NONE;
    uint id = ct_intern_checked<CtCheckedRows>(tag, payload, spare);
    // One comparison site, so the interning and identity readers inline once.
    [loop]
    for (uint which = 0u; which < 3u; which++)
    {
        uint expected_tag; uint expected_payload;
        if (!expected_operand(row, prev_row, which, expected_tag, expected_payload)) continue;
        uint expected = ct_intern_checked<CtCheckedRows>(expected_tag, expected_payload, spare);
        if (checked_types_equal_ids(CheckedSlots(), tag, payload, id,
                expected_tag, expected_payload, expected, false))
            continue;
        uint detail = which == 2u && tag == TYPE_REF_SCALAR && expected_tag == TYPE_REF_SCALAR
            ? expected_payload * 256u + payload : 0u;
        record_min_token_error(status, claim_error_token(row, call_generic_claim_callee[row]),
            ERR_ASSIGN_MISMATCH, detail);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (call_inference_state[0u] != 0u) return;
    validate_claim_at(linear_thread_id(dtid));
}
