// The result-type edge shared by symbolic operator projection and instance
// realization. This is the left-operand chain already used by resolve_scalar_expression_types.
import hir_records;
import hir_expr_semantics;

public bool expression_inherits_operand_type(uint kind, uint form)
{
    if (kind != 14u && kind != 16u && kind != 17u) return false;
    return hir_is_forward_expression(kind, form) ||
        (form >= 13u && form <= 16u) || (form >= 19u && form <= 25u);
}

public uint inherited_expression_type_leaf(uint node, uint count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads)
{
    for (uint step = 0u; step < count && node < count; step++)
    {
        if (!expression_inherits_operand_type(cores[node].kind, payloads[node].a)) return node;
        uint child = payloads[node].b;
        if (child == node) break;
        node = child;
    }
    return 0xffffffffu;
}
