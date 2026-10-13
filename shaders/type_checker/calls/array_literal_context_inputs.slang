import hir_records;
import hir_expr_semantics;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import type_checker.checked_index_reference;
import type_checker.scoped_type_equality;
import type_checker.argument_context;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node < active_hir_count(); }
bool valid_token(uint token) { return token < gParams.n_tokens; }
bool valid_instance(uint instance) { return instance < checked_type_capacity(); }
#include "../array_literal_expected.slang"

// Nested literals consume the enclosing literal's expected type, including an
// annotation above multiple array layers. The accepted relation is a snapshot
// from a preceding dispatch, never another array producer lane's output.
uint expected_array_literal_instance(uint node)
{
    uint root = node; uint layers = 0u; uint expected = INVALID;
    for (uint depth = 0u; depth < 64u && valid_hir(root); depth++)
    {
        expected = declared_array_literal_instance(root);
        if (valid_instance(expected) && type_instance_kind[expected] == TYPE_INSTANCE_ARRAY) break;
        if (root != node && call_inference_result_tag[root] == TYPE_REF_INSTANCE)
        {
            expected = call_inference_result_payload[root];
            if (valid_instance(expected) && type_instance_kind[expected] == TYPE_INSTANCE_ARRAY) break;
        }
        uint parent = compact_hir_core[root].parent;
        if (!valid_hir(parent) || compact_hir_core[parent].kind != HIR_ARRAY_EXPR) return INVALID;
        layers++; root = parent;
    }
    for (uint i = 0u; i < layers; i++)
    {
        if (!valid_instance(expected) || type_instance_kind[expected] != TYPE_INSTANCE_ARRAY ||
            type_instance_elem_ref_tag[expected] != TYPE_REF_INSTANCE) return INVALID;
        expected = type_instance_elem_ref_payload[expected];
    }
    return valid_instance(expected) && type_instance_kind[expected] == TYPE_INSTANCE_ARRAY
        ? expected : INVALID;
}
