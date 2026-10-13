import type_checker.constant_parameter_slots;
import semantic_interface_layout;
import dependency_interface;
import hir_records;
import gpu_index;
import type_checker.instance_arguments;
import type_checker.scoped_type_equality;
import type_checker.dependencies.canonical_field_types;
import type_checker.methods.candidate;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_state;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> method_call_source_ref_tag;
StructuredBuffer<uint> method_call_source_ref_payload;
StructuredBuffer<uint> method_call_selection_owned;
StructuredBuffer<uint> method_call_receiver_hir;
RWStructuredBuffer<MethodCandidate> method_candidate;
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_WORDS = 9u;
static const uint MEMBER_WORDS = SEMANTIC_INTERFACE_MEMBER_WORDS;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint DISPATCH_X_STRIDE = 16776960u;

#include "../methods/receiver_graph.slang"

uint active_hir_count()
{ return min(gParams.hir_capacity, compact_hir_count[0u]); }
bool valid_hir(uint node)
{ return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token)
{ return token != INVALID && token < gParams.visible_capacity; }

uint path_node_for_callee(uint callee)
{
    if (!valid_hir(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_PATH_EXPR) return callee;
    if (compact_hir_core[callee].kind != HIR_NAME_EXPR) return INVALID;
    uint child = compact_hir_links[callee].first_child;
    return valid_hir(child) && compact_hir_core[child].kind == HIR_PATH_EXPR ? child : INVALID;
}

// Recognition and parent normalization are owned by the common call-key
// producer. In particular, structural roots do not require a nominal import.
bool imported_method_call(uint call, out uint method_token,
    out uint qualified_owner_token, out uint receiver_hir, out bool dotted)
{
    method_token = INVALID; qualified_owner_token = INVALID;
    receiver_hir = INVALID; dotted = false;
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return false;
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return false;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    dotted = core.kind == HIR_MEMBER_EXPR;
    if (dotted)
    {
        method_token = payload.c;
        receiver_hir = payload.b;
    }
    else
    {
        uint path_node = path_node_for_callee(callee);
        uint path = valid_hir(path_node) ? path_id_by_owner_hir[path_node] : INVALID;
        qualified_owner_token = path < gParams.path_capacity
            ? path_owner_token[path] : core.token_start;
        if (valid_token(qualified_owner_token))
            method_token = module_value_path_associated_method_token[qualified_owner_token];
    }
    if (!valid_token(method_token) || method_call_selection_owned[method_token] == 0u) return false;
    // The key producer's expression identity also distinguishes an actual
    // dotted receiver from a qualified/static call without reinterpreting it.
    return method_call_receiver_hir[method_token] == (dotted ? receiver_hir : INVALID);
}
