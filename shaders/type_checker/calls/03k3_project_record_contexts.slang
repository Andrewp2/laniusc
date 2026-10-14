import type_checker.constant_constraints;
import hir_records;
import hir_expr_semantics;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import type_checker.checked_index_reference;
import type_checker.scoped_type_equality;
import type_checker.argument_context;
import type_checker.scoped_type_constraints;
import type_checker.calls.contextual_call_environment;
import type_checker.dependencies.canonical_field_types;
import type_checker.type.instances.struct_field_lookup;
import semantic_interface_layout;
import dependency_interface;
import status;
import type_checker.local_struct_layout;

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
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;

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
[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
[ForceInline]
bool valid_hir(uint node) { return node < active_hir_count(); }
[ForceInline]
bool valid_token(uint token) { return token < gParams.n_tokens; }
bool valid_instance(uint instance) { return instance < checked_type_capacity(); }

StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> struct_field_lookup_state;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;


RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;
#include "../checked_record_constructor_reference.slang"
#include "../result_expression_context.slang"
#include "../inference_expression_reference.slang"
#include "record_field_constraints.slang"

// One literal lane publishes its complete receiving type. Field/semantic
// projection runs in later dispatches and never reads a sibling lane's output.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    if (!valid_hir(node) || compact_hir_core[node].kind != 28u) return;
    uint source_tag; uint source_payload; uint source_decl;
    bool explicit_type = checked_record_constructor_reference(node, source_tag, source_payload, source_decl);
    // An explicit application already owns its ordered arguments, even when
    // they contain lexical parameters. Receiving context validates that actual
    // type elsewhere. Replacing it with an equivalent indexed instance would
    // oscillate with declaration field projection and prevent convergence.
    if (explicit_type && source_tag == 3u) return;
    uint2 expected;
    if (!result_expression_context<ScopedCheckedTypeGraph>(node, checked_type_capacity(), expected))
    {
        // Field evidence supplies the same ordered application environment as
        // callable arguments. Materialization runs after this dispatch.
        infer_record_field_constraints(node, source_decl);
        return;
    }
    uint declaration = expected.x == 3u && valid_instance(expected.y)
        ? type_instance_decl_token[expected.y]
        : expected.x == 1u && expected.y >= 4096u && expected.y < 6144u
        ? expected.y - 4096u : INVALID;
    uint instance = expected.x == 3u ? expected.y : INVALID;
    if (valid_token(source_decl))
    {
        if (declaration != source_decl)
        {
            // A receiving application cannot change nominal identity. Keep
            // provisional contexts deferred, but diagnose before codegen.
            if (call_inference_state[0u] == 0u)
                record_min_token_error(status, compact_hir_core[node].token_start, 3u, 0u);
            return;
        }
    }
    else
    {
        uint token = compact_hir_core[node].token_start;
        if (!valid_instance(instance) || !valid_token(token) ||
            external_type_library_id[instance] == INVALID ||
            external_type_library_id[instance] != external_type_library_id[token] ||
            external_type_unit_id[instance] != external_type_unit_id[token] ||
            external_type_local_index[instance] != external_type_local_index[token])
        {
            if (call_inference_state[0u] == 0u) record_min_token_error(status, token, 3u, 0u);
            return;
        }
    }
    if (struct_lit_context_decl_token[node] == declaration && struct_lit_context_instance[node] == instance) return;
    struct_lit_context_decl_token[node] = declaration;
    struct_lit_context_instance[node] = instance;
    uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored);
}
