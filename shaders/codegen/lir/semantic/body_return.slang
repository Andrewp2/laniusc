// Included after the checked function resources in count. A published block
// row is the private count/scatter contract for this synthetic return.
// A unit body has an executable fallthrough even when its syntax produces no
// other LIR row. Anchor that return to the real body block, never to a trait
// contract, extern declaration, or the function's parameter-place setup.
bool semantic_body_has_implicit_return(uint node, uint hir_count)
{
    if (node >= hir_count) return false;
    HirCore body = compact_hir_core[node];
    if (body.kind != 6u || body.parent >= hir_count ||
        compact_hir_core[body.parent].kind != 3u)
        return false;
    uint function_id = semantic_function_id[node];
    if (function_id == LIR_INVALID || function_id >= hir_count) return false;
    SemanticLirFunction function = semantic_lir_functions[function_id];
    return function.hir_function == body.parent &&
        (function.result_type == 1u ||
         (function.flags & SEMANTIC_FUNCTION_FLAG_ENTRYPOINT) != 0u);
}
