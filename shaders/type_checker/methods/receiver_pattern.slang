import type_checker.constant_constraints;
// Method indexes select candidates by structural head and name, including a
// separate bucket for root-parameter patterns. Complete receiver patterns
// decide applicability, repeated parameters, and structural lengths through
// the ordinary checked constraint owners. Header admission owns lexical
// parameter scope; these shared operations also compare caller-owned graphs.
import type_checker.scoped_type_equality;
import type_checker.scoped_type_constraints;
import type_checker.scoped_type_hash;

public bool receiver_pattern_matches<Graph : IScopedTypeGraph>(
    uint pattern_tag, uint pattern_payload, uint actual_tag, uint actual_payload,
    uint capacity, uint tokens)
{
    uint2 inferred[32]; uint mask;
    InferredConstant constants[32]; uint constant_mask;
    return scoped_type_and_constant_constraints<Graph>(pattern_tag, pattern_payload,
        0xffffffffu, actual_tag, actual_payload, capacity, tokens,
        inferred, mask, constants, constant_mask, true);
}

public bool receiver_pattern_valid<Graph : IScopedTypeGraph>(
    uint tag, uint payload, uint capacity, uint tokens)
{
    uint hash;
    return scoped_type_ref_hash<Graph>(tag, payload, 0xffffffffu,
        capacity, tokens, hash);
}

public bool receiver_patterns_equivalent<Graph : IScopedTypeGraph>(
    uint left_tag, uint left_payload, uint right_tag, uint right_payload,
    uint capacity, uint tokens)
{
    // Both directions preserve independent/repeated type and constant leaves.
    // Token identities may differ between alpha-equivalent impl declarations.
    return receiver_pattern_matches<Graph>(left_tag, left_payload,
        right_tag, right_payload, capacity, tokens) &&
        receiver_pattern_matches<Graph>(right_tag, right_payload,
            left_tag, left_payload, capacity, tokens);
}
