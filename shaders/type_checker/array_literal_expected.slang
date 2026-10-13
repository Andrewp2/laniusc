// Included by array fact producers with immutable declaration/field contexts.
import type_checker.checked_type_graph;
#include "declared_expression_context.slang"
uint declared_array_literal_instance(uint node)
{
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_ARRAY_EXPR)
        return INVALID;
    uint2 reference;
    return declared_expression_context<ScopedCheckedTypeGraph>(node, checked_type_capacity(), reference) && reference.x == TYPE_REF_INSTANCE
        ? reference.y : INVALID;
}
