// A result constraint belongs to the expression receiving the value. Compose
// immutable argument/field/declaration contexts through array elements and
// match results; never infer an expectation from the call's actual result.
import type_checker.scoped_type_equality;
#include "declared_expression_context.slang"

uint receiving_container(uint node)
{
    for (uint depth = 0u; depth < 32u && valid_hir(node); depth++)
    {
        uint parent = compact_hir_core[node].parent;
        if (!valid_hir(parent) || parent == node) return INVALID;
        uint kind = compact_hir_core[parent].kind;
        if (kind == 24u || kind == 34u) return parent;
        if (kind == 28u || kind == HIR_STMT || kind == HIR_LET_STMT ||
            kind == HIR_RETURN_STMT || kind == 3u || kind == 1u) return INVALID;
        node = parent;
    }
    return INVALID;
}

bool result_expression_context<TGraph : IScopedTypeGraph>(uint node,
    uint type_capacity, out uint2 reference)
{
    reference = uint2(0u, INVALID);
    uint current = node; uint array_layers = 0u;
    for (uint depth = 0u; depth < 64u && valid_hir(current); depth++)
    {
        if (declared_expression_context<TGraph>(current, type_capacity, reference))
        {
            for (uint layer = 0u; layer < array_layers; layer++)
            {
                if (reference.x != 3u || reference.y >= type_capacity ||
                    TGraph.metadata(reference.y, 0u) != 2u) return false;
                reference = uint2(TGraph.metadata(reference.y, 3u), TGraph.metadata(reference.y, 4u));
            }
            return reference.x != 0u && reference.y != INVALID;
        }
        uint parent = receiving_container(current);
        if (!valid_hir(parent)) return false;
        uint kind = compact_hir_core[parent].kind;
        if (kind == 24u)
        {
            uint start = compact_array_element_start[parent];
            uint count = compact_array_element_count[parent];
            uint total = min(compact_array_element_row_count[0u], active_hir_count());
            if (start > total || count > total - start) return false;
            bool value = false;
            for (uint row = start; row < start + count; row++)
            {
                HirArrayElement element = compact_array_elements[row];
                if (element.array == parent && argument_context_root(element.value,
                    active_hir_count(), compact_hir_core, compact_hir_payload) == current)
                { value = true; break; }
            }
            if (!value) return false;
            array_layers++;
        }
        else if (kind == 34u)
        {
            HirPayload match = compact_hir_payload[parent];
            uint count = min(compact_match_arm_count[0u], active_hir_count());
            if (match.b > count || match.c > count - match.b) return false;
            bool result = false;
            for (uint row = match.b; row < match.b + match.c; row++)
            {
                HirMatchArm arm = compact_match_arms[row];
                if (arm.owner == parent && argument_context_root(arm.result,
                    active_hir_count(), compact_hir_core, compact_hir_payload) == current)
                { result = true; break; }
            }
            if (!result) return false;
        }
        else return false;
        current = parent;
    }
    return false;
}
