// Variant payload lookups shared by the aggregate layout walk
// (function_layout_words.slang) and its validation
// (function_layout_enum_variants.slang). Included after the declaring
// kernel's buffers and gParams.
#include "function_layout_constants.slang"
#include "type_closure_graph.slang"

bool symbolic_payload_layout(uint type_node)
{
    uint tag = semantic_expr_ref_tag[type_node];
    if (tag == TYPE_REF_GENERIC_PARAM) return true;
    if (tag != 3u) return false;
    uint instance = semantic_expr_ref_payload[type_node];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity || type_instance_kind[instance] == 3u) return false;
    return !concrete_instance_is_closed<NativeTypeStructureGraph, CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(instance, capacity, gParams.n_tokens);
}

uint nominal_declaration(uint type_node, uint type_id, uint hir_count)
{
    uint token = semantic_aggregate_decl_token[type_node];
    uint declaration = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : INVALID;
    if (declaration < hir_count)
    {
        uint kind = compact_hir_core[declaration].kind;
        if (kind == HIR_STRUCT_ITEM || kind == HIR_ENUM_ITEM)
            return declaration;
    }
    uint enum_declaration = INVALID;
    if (type_id >= TY_ENUM_BASE)
    {
        token = type_id - TY_ENUM_BASE;
        if (token < gParams.n_tokens)
        {
            declaration = semantic_aggregate_hir_by_name_token[token];
            if (declaration < hir_count &&
                compact_hir_core[declaration].kind == HIR_ENUM_ITEM)
                enum_declaration = declaration;
        }
    }
    uint struct_declaration = INVALID;
    if (type_id >= TY_STRUCT_BASE)
    {
        token = type_id - TY_STRUCT_BASE;
        if (token < gParams.n_tokens)
        {
            declaration = semantic_aggregate_hir_by_name_token[token];
            if (declaration < hir_count &&
                compact_hir_core[declaration].kind == HIR_STRUCT_ITEM)
                struct_declaration = declaration;
        }
    }
    if (enum_declaration != INVALID && struct_declaration != INVALID)
        return INVALID;
    return enum_declaration != INVALID ? enum_declaration : struct_declaration;
}
