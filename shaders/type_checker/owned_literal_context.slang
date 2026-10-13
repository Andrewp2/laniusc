// Literal width can be owned by a checked generic operand or a const's own
// annotation before ordinary expression inference has assigned a scalar.
// This reader consumes immutable evidence and never republishes a context.
import hir_records;
import hir_expr_semantics;
import primitive_types;
import type_checker.calls.explicit_call_environment;
import type_checker.constant_atoms;
import type_checker.argument_context;

bool owned_literal_scalar_matches(uint scalar, bool floating)
{
    return floating ? scalar_is_float(scalar) : scalar_is_integer(scalar);
}

public uint checked_owned_numeric_literal_context(uint literal, uint count, uint tokens,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<uint> expression_parent, StructuredBuffer<uint> const_types,
    StructuredBuffer<uint> const_values, StructuredBuffer<uint> type_tags,
    StructuredBuffer<uint> type_payloads)
{
    if (literal >= count || cores[literal].kind != 23u ||
        (payloads[literal].a != 3u && payloads[literal].a != 27u)) return 0u;
    bool floating = payloads[literal].a == 27u;
    uint root = literal;
    // A source operand can include forwarding wrappers and unary minus. Its
    // checked atom supplies context only to that exact literal expression.
    // Never cross binary operators, calls, casts, or another expression root.
    for (uint step = 0u; step < count; step++)
    {
        uint kind; uint atom; uint3 value;
        if (checked_source_constant_operand(root, kind, atom) && kind == 1u &&
            checked_constant_atom_value(atom, value) &&
            owned_literal_scalar_matches(value.x, floating)) return value.x;
        uint parent = expression_parent[root];
        if (parent >= count) break;
        if (parent == root) return 0u;
        HirCore owner = cores[parent];
        HirPayload payload = payloads[parent];
        bool forward = hir_is_forward_expression(owner.kind, payload.a);
        bool negative = owner.kind == 17u && payload.a == 13u;
        if ((!forward && !negative) || payload.b != root) break;
        root = parent;
        if (step + 1u == count) return 0u;
    }
    uint value_root = argument_context_root(root, count, cores, payloads);
    if (value_root >= count) return 0u;
    uint ancestor = cores[root].parent;
    for (uint step = 0u; step < count && ancestor < count; step++)
    {
        HirCore owner = cores[ancestor];
        if (owner.kind == 25u)
        {
            // Only the exact literal initializer takes this annotation. A
            // generic literal in the annotation or another child cannot use it.
            if (argument_context_root(const_values[ancestor], count, cores, payloads) != value_root)
                return 0u;
            uint annotation = const_types[ancestor];
            if (annotation >= count) return 0u;
            uint anchor = cores[annotation].token_start;
            if (anchor >= tokens || type_tags[anchor] != 1u) return 0u;
            uint scalar = type_payloads[anchor];
            return owned_literal_scalar_matches(scalar, floating) ? scalar : 0u;
        }
        if (owner.kind == 3u || owner.kind == 1u || owner.parent == ancestor) return 0u;
        ancestor = owner.parent;
    }
    return 0u;
}
