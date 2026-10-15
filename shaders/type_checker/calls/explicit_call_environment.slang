// Source-owned explicit bindings are immutable evidence in caller scope.
// Declaration producers map the ordered application rows to lexical slots;
// ordinary value claims and receiving contexts cannot rewrite that mapping.
import type_checker.calls.claim_reference;

public StructuredBuffer<uint> call_explicit_application_status;
public StructuredBuffer<uint> call_explicit_application_owner_by_token;
public StructuredBuffer<uint4> call_explicit_environment;
StructuredBuffer<uint> call_explicit_binding_tag;
StructuredBuffer<uint> call_explicit_binding_payload;
// Bit per constant slot of each applying owner: its published reference passed
// the checked constant descriptor when 03a0 wrote the binding row.
StructuredBuffer<uint> call_explicit_constant_valid_mask;
StructuredBuffer<uint> explicit_environment_constant_kind;
StructuredBuffer<uint> explicit_environment_constant_payload;

// Declaration binding resolves ambiguous name operands to constants. This
// checked operand role is distinct from acceptance of the entire header; call
// readers below still require completed application status before consuming it.
public bool checked_source_constant_operand(uint operand, out uint kind, out uint payload)
{
    kind = 0u; payload = 0xffffffffu;
    uint capacity; uint stride;
    explicit_environment_constant_kind.GetDimensions(capacity, stride);
    if (operand >= capacity) return false;
    kind = explicit_environment_constant_kind[operand];
    payload = explicit_environment_constant_payload[operand];
    return (kind >= 1u && kind <= 3u) && payload != 0xffffffffu;
}

// Metadata uses the applying name even when the accepted environment is keyed
// by a projected head alias. Jobs without source applications retain that key.
public uint checked_call_application_owner(uint token)
{
    uint capacity; uint stride;
    call_explicit_application_owner_by_token.GetDimensions(capacity, stride);
    if (token >= capacity) return token;
    uint owner = call_explicit_application_owner_by_token[token];
    return owner < capacity ? owner : token;
}

// The producer decodes source syntax or normalized parent operands once.
// Recursive inference only reads checked rows, ordered by slot and domain.
bool explicit_environment_binding(uint environment, uint slot, bool constant,
    out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    if (environment == 0xffffffffu || (environment & 0x80000000u) == 0u || slot >= 32u) return false;
    uint token = environment & 0x7fffffffu;
    uint capacity; uint stride;
    call_explicit_application_status.GetDimensions(capacity, stride);
    if (token >= capacity) return false;
    token = call_explicit_application_owner_by_token[token];
    if (token >= capacity || call_explicit_application_status[token] != 1u) return false;
    uint4 descriptor = call_explicit_environment[token];
    uint mask = constant ? descriptor.w : descriptor.z;
    if (descriptor.x == 0u || (mask & (1u << slot)) == 0u) return false;
    uint ordinal = countbits(mask & ((1u << slot) - 1u));
    if (constant) ordinal += countbits(descriptor.z);
    call_explicit_binding_tag.GetDimensions(capacity, stride);
    uint start = descriptor.x - 1u;
    if (ordinal >= descriptor.y || start >= capacity || ordinal >= capacity - start) return false;
    uint row = start + ordinal;
    tag = call_explicit_binding_tag[row]; payload = call_explicit_binding_payload[row];
    if (constant) tag &= 0x7fffffffu;
    return true;
}

public bool checked_explicit_environment_argument(uint environment, uint slot,
    out uint tag, out uint payload)
{
    return explicit_environment_binding(environment, slot, false, tag, payload) &&
        checked_claim_reference(tag, payload);
}

public bool checked_explicit_environment_constant(uint environment, uint slot,
    out uint kind, out uint payload)
{
    return explicit_environment_binding(environment, slot, true, kind, payload) &&
        (kind >= 1u && kind <= 3u) && payload != 0xffffffffu;
}

// Presence as above, plus the descriptor admission recorded by the producer.
public bool checked_explicit_environment_constant_evidence(uint environment, uint slot,
    out uint kind, out uint payload, out bool valid)
{
    valid = false;
    if (!explicit_environment_binding(environment, slot, true, kind, payload) ||
        kind < 1u || kind > 3u || payload == 0xffffffffu) return false;
    // A present binding implies the owner lookup above was in range.
    uint owner = call_explicit_application_owner_by_token[environment & 0x7fffffffu];
    uint capacity; uint stride;
    call_explicit_constant_valid_mask.GetDimensions(capacity, stride);
    valid = owner < capacity && (call_explicit_constant_valid_mask[owner] & (1u << slot)) != 0u;
    return true;
}
