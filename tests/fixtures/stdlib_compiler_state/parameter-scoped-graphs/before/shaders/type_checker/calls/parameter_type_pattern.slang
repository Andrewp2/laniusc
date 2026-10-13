import type_checker.concrete_type_equality;
import type_checker.constant_parameter_slots;
// Declaration patterns and accepted argument types share the complete checked
// graph. Each argument infers independently; the existing claim validator
// checks agreement across arguments after all rows have been published.
import type_checker.scoped_type_equality;
import type_checker.scoped_type_constraints;
import type_checker.instance_arguments;
import type_checker.dependencies.canonical_field_types;

struct ParameterTypeGraph : IScopedTypeGraph
{
    static uint constant_parameter_slot(uint token)
    { return token < gParams.n_tokens ? type_const_param_slot_by_token[token] : 0xffffffffu; }
    static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { kind = 0u; value = 0xffffffffu; return false; }
    static uint parameter_slot(uint token)
    { return generic_slot_for_type_ref(2u, token); }
    static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = 0xffffffffu; return false; }
    static uint metadata(uint instance, uint field)
    {
        switch (field)
        {
        case 0u: return type_instance_kind[instance];
        case 1u: return type_instance_decl_token[instance];
        case 2u: return type_instance_arg_count[instance];
        case 3u: return type_instance_elem_ref_tag[instance];
        case 4u: return type_instance_elem_ref_payload[instance];
        case 5u: return type_instance_len_kind[instance];
        case 6u: return type_instance_len_payload[instance];
        case 7u: return external_type_library_id[instance];
        case 8u: return external_type_unit_id[instance];
        case 9u: return external_type_local_index[instance];
        default: return 0xffffffffu;
        }
    }
    static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        uint tokens; uint stride;
        type_generic_param_slot_by_token.GetDimensions(tokens, stride);
        return checked_instance_argument(instance, slot, tokens,
            type_instance_arg_count, type_instance_arg_start,
            type_instance_arg_ref_tag, type_instance_arg_ref_payload,
            type_instance_arg_row_start, type_instance_arg_row_count_out,
            type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload, tag, payload);
    }
}

uint parameter_type_capacity()
{ uint capacity; uint stride; type_instance_kind.GetDimensions(capacity, stride); return capacity; }

// Walk each pattern node once, retaining independent 32-bit use masks for
// type parameters and constant lengths.
bool parameter_type_pattern_mask(uint tag, uint payload, out uint mask, out uint constant_mask, out uint failure)
{
    static const uint LIMIT = 64u;
    mask = 0u; constant_mask = 0u; failure = 0u;
    uint2 stack[LIMIT]; uint next[LIMIT]; uint counts[LIMIT];
    uint2 seen[LIMIT]; uint seen_count = 0u; uint depth = 0u;
    stack[0u] = uint2(tag, payload); next[0u] = 0xffffffffu;
    for (;;)
    {
        uint2 ref = stack[depth];
        if (next[depth] == 0xffffffffu)
        {
            next[depth] = 0u; counts[depth] = 0u;
            bool visited = false;
            for (uint i = 0u; i < seen_count; i++)
                if (all(seen[i] == ref)) { visited = true; break; }
            if (!visited)
            {
                if (seen_count == LIMIT) { failure = 2u; return false; }
                seen[seen_count++] = ref;
                uint slot = 0xffffffffu;
                if (application_argument_is_constant(ref.x))
                {
                    uint kind; uint value;
                    if (!application_constant_argument(ref.x, ref.y, kind, value))
                    { failure = 3u; return false; }
                    if (kind == 2u)
                    {
                        uint constant_slot = ParameterTypeGraph.constant_parameter_slot(value);
                        if (constant_slot >= 32u)
                        { failure = constant_slot == 0xffffffffu ? 3u : 2u; return false; }
                        constant_mask |= 1u << constant_slot;
                    }
                }
                else if (ref.x == 2u) slot = ParameterTypeGraph.parameter_slot(ref.y);
                else if (ref.x == 6u) slot = ref.y;
                else if (ref.x == 5u)
                {
                    uint root = canonical_field_root(ref.y);
                    if (root == 0xffffffffu) { failure = 4u; return false; }
                    ref.y = root; stack[depth] = ref;
                    uint kind = dependency_type_word(root * 9u);
                    if (kind == 8u)
                    {
                        uint constant_slot = dependency_generic_const_slot(root);
                        if (constant_slot >= 32u) { failure = constant_slot == 0xffffffffu ? 3u : 2u; return false; }
                        constant_mask |= 1u << constant_slot;
                    }
                    else if (kind == 9u)
                    {
                        if (dependency_type_word(root * 9u + 1u) == 0xffffffffu) { failure = 3u; return false; }
                    }
                    else if (kind == 2u) slot = dependency_generic_type_slot(root);
                    else if (kind >= 3u && kind <= 6u)
                    {
                        if (kind == 4u && dependency_type_word(root * 9u + 5u) == 2u)
                        {
                            uint constant_slot = dependency_generic_const_slot(root);
                            if (constant_slot >= 32u) { failure = constant_slot == 0xffffffffu ? 3u : 2u; return false; }
                            constant_mask |= 1u << constant_slot;
                        }
                        counts[depth] = dependency_type_word(root * 9u + 4u);
                    }
                    else if (kind != 1u) { failure = 4u; return false; }
                }
                else if (ref.x == 3u)
                {
                    if (ref.y >= parameter_type_capacity()) { failure = 4u; return false; }
                    uint kind = ParameterTypeGraph.metadata(ref.y, 0u);
                    if (kind == 1u) counts[depth] = ParameterTypeGraph.metadata(ref.y, 2u);
                    else if (kind == 2u || kind == 3u || kind == 4u)
                    {
                        if (kind == 2u && ParameterTypeGraph.metadata(ref.y, 5u) == 2u)
                        {
                            uint constant_slot = ParameterTypeGraph.constant_parameter_slot(ParameterTypeGraph.metadata(ref.y, 6u));
                            if (constant_slot >= 32u) { failure = constant_slot == 0xffffffffu ? 3u : 2u; return false; }
                            constant_mask |= 1u << constant_slot;
                        }
                        counts[depth] = 1u;
                    }
                    else { failure = 4u; return false; }
                }
                else if (ref.x != 1u) { failure = 4u; return false; }
                if (slot != 0xffffffffu)
                {
                    if (slot >= 32u) { failure = 2u; return false; }
                    mask |= 1u << slot;
                }
                else if (ref.x == 2u) { failure = 3u; return false; }
                if (counts[depth] > 32u) { failure = 2u; return false; }
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return true;
            depth--; continue;
        }
        uint slot = next[depth]++;
        uint2 child;
        if (ref.x == 5u)
        {
            uint start = dependency_type_word(ref.y * 9u + 3u);
            uint edges = dependency_count(5u);
            if (start > edges || counts[depth] > edges - start) { failure = 4u; return false; }
            child = uint2(5u, dependency_type_edge_word(start + slot));
        }
        else if (ParameterTypeGraph.metadata(ref.y, 0u) == 1u)
        {
            if (!ParameterTypeGraph.argument(ref.y, slot, child.x, child.y))
                { failure = 4u; return false; }
        }
        else child = uint2(ParameterTypeGraph.metadata(ref.y, 3u), ParameterTypeGraph.metadata(ref.y, 4u));
        if (depth + 1u == LIMIT) { failure = 2u; return false; }
        depth++; stack[depth] = child; next[depth] = 0xffffffffu;
    }
}


bool parameter_argument_mask(uint tag, uint payload, out uint mask, out uint constant_mask, out uint failure)
{
    return parameter_type_pattern_mask(tag, payload, mask, constant_mask, failure);
}

uint parameter_root_type_slot(uint tag, uint payload)
{
    if (tag == 2u) return ParameterTypeGraph.parameter_slot(payload);
    if (tag == 6u) return payload;
    if (tag == 5u)
    {
        uint root = canonical_field_root(payload);
        if (root != 0xffffffffu && dependency_type_word(root * 9u) == 2u)
            return dependency_generic_type_slot(root);
    }
    return 0xffffffffu;
}

bool parameter_argument_constraints(uint tag, uint payload, uint actual_tag, uint actual_payload,
    out uint2 inferred[32], out uint mask, out uint2 constants[32], out uint constant_mask)
{
    // One complete structural walk infers independent type and constant domains.
    // Symbolic lengths never truncate the element pattern.
    mask = 0u; constant_mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++)
    { inferred[slot] = uint2(0u, 0xffffffffu); constants[slot] = uint2(0u, 0xffffffffu); }
    if (tag == 5u)
    {
        uint root = canonical_field_root(payload);
        if (root != 0xffffffffu)
        {
            uint kind = dependency_type_word(root * 9u);
            if (kind == 2u) { tag = 6u; payload = dependency_generic_type_slot(root); }
            else if (kind == 1u) { tag = 1u; payload = dependency_type_word(root * 9u + 1u); }
        }
    }
    if (tag == 6u)
    {
        if (payload >= 32u || actual_tag == 0u || actual_payload == 0xffffffffu) return false;
        inferred[payload] = uint2(actual_tag, actual_payload);
        mask = 1u << payload;
        return true;
    }
    if (tag == 5u)
        return canonical_type_and_constant_constraints<ParameterTypeGraph>(0xffffffffu,
            payload, actual_tag, actual_payload, parameter_type_capacity(), gParams.n_tokens,
            true, inferred, mask, constants, constant_mask, true, true);
    return scoped_type_and_constant_constraints<ParameterTypeGraph>(tag, payload, 0xffffffffu,
        actual_tag, actual_payload, parameter_type_capacity(), gParams.n_tokens,
        inferred, mask, constants, constant_mask, true, true);
}
