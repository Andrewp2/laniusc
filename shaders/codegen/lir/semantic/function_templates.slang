import type_checker.constant_atoms_identity;
import hir_records;
import gpu_index;
import type_checker.concrete_type_closure;
import checked_semantic_artifact;
import codegen.lowering_ir;

bool valid_instance(uint instance)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return instance < capacity;
}

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint replay_function; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> semantic_param_ref_tag_by_row;
StructuredBuffer<uint> semantic_param_ref_payload_by_row;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> semantic_value_decl_by_hir;
StructuredBuffer<uint> semantic_value_const_present_by_hir;
StructuredBuffer<uint> semantic_enclosing_fn_by_hir;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> semantic_value_used;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> semantic_function_flag;

static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint INVALID = 0xffffffffu;
static const uint SYMBOLIC_CONST_PARAMETER = 0x20000000u;

#include "type_closure_graph.slang"
#include "function_generic_environment.slang"

bool unclosed_type_reference(uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM) return true;
    if (tag != 3u) return false;
    if (!valid_instance(payload)) return true;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return !concrete_instance_is_closed<NativeTypeStructureGraph, CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(payload, capacity, gParams.n_tokens);
}

bool unclosed_type_layout(uint type_node, uint hir_count)
{
    return type_node < hir_count && unclosed_type_reference(
        semantic_expr_ref_tag_by_hir[type_node], semantic_expr_ref_payload_by_hir[type_node]);
}

bool symbolic_payload_layout(HirMatchPayload binding, uint hir_count, uint total)
{
    if (binding.pattern >= hir_count) return false;
    if (semantic_expr_ref_tag_by_hir[binding.pattern] == TYPE_REF_GENERIC_PARAM ||
        unclosed_type_layout(binding.pattern, hir_count))
        return true;
    if (binding.arm >= hir_count) return false;
    uint start = compact_match_payload_start[binding.arm];
    uint count = compact_match_payload_count[binding.arm];
    if (binding.ordinal >= count || start >= total || binding.ordinal >= total - start)
        return false;
    // A used concrete payload after an ignored T still has an unknown offset.
    // Deferring it follows the same rule as a used T, without guessing T's width.
    for (uint ordinal = 0u; ordinal < binding.ordinal; ordinal += 1u)
    {
        HirMatchPayload prior = compact_match_payloads[start + ordinal];
        if (prior.arm != binding.arm || prior.ordinal != ordinal || prior.pattern >= hir_count)
            return false;
        if (semantic_expr_ref_tag_by_hir[prior.pattern] == TYPE_REF_GENERIC_PARAM ||
            unclosed_type_layout(prior.pattern, hir_count))
            return true;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (gParams.replay_function != 0u && row < count &&
        compact_hir_core[row].kind == 3u &&
        row != gParams.replay_function - 1u &&
        function_has_generic_environment(row, count))
    {
        // Scratch substitutions can close sibling impl methods. The replay
        // request authorizes one concrete generic body, not those siblings.
        InterlockedAnd(semantic_function_flag[row], 0u);
    }
    if (row < count && compact_hir_core[row].kind == 19u &&
        semantic_calls_by_hir[row].intrinsic_tag == INTRINSIC_TYPED_SLICE_FROM_RAW_PARTS &&
        unclosed_type_layout(row, count))
    {
        // Constructing a raw view needs its element layout to publish stride.
        // Forwarding an existing view only copies the complete descriptor.
        uint encoded_function = semantic_enclosing_fn_by_hir[row];
        if (encoded_function != 0u && encoded_function - 1u < count)
            InterlockedAnd(semantic_function_flag[encoded_function - 1u], 0u);
    }
    if (row < count && compact_hir_core[row].kind == 19u)
    {
        CheckedCallArtifact call = semantic_calls_by_hir[row];
        bool adjusted_receiver = call.receiver_adjustment_kind != 0u ||
            call.receiver_deref_count != 0u;
        if (adjusted_receiver)
        {
            uint tag = call.receiver_parameter_ref_tag;
            uint payload = call.receiver_parameter_ref_payload;
            bool closed = call.receiver_hir < count && payload != INVALID &&
                ((tag == 1u && payload != 0u) || tag == 3u) &&
                !unclosed_type_reference(tag, payload);
            if (!closed)
            {
                // The original generic body remains a deferred template.
                // Selected replay must close the actual adjusted parameter
                // contract before publishing its executable definition; a
                // descriptor's known word width cannot establish its count.
                uint encoded_function = semantic_enclosing_fn_by_hir[row];
                if (encoded_function != 0u && encoded_function - 1u < count)
                    InterlockedAnd(semantic_function_flag[encoded_function - 1u], 0u);
            }
        }
    }
    // A constant parameter may have a fully concrete scalar type while its
    // value is still symbolic. Body closure therefore requires both checked
    // type layouts and bindings for every consumed constant parameter.
    if (row < count &&
        semantic_value_const_present_by_hir[row] == SYMBOLIC_CONST_PARAMETER)
    {
        uint encoded_function = semantic_enclosing_fn_by_hir[row];
        if (encoded_function != 0u && encoded_function - 1u < count)
            InterlockedAnd(semantic_function_flag[encoded_function - 1u], 0u);
    }
    // Forwarding a symbolic T also needs its concrete machine type and width;
    // guessing a scalar would lose string lengths and floating-point values.
    // Copying a generic aggregate result requires its concrete payload width.
    // Every parameter/result type must close before publishing a body. A
    // slice's fixed descriptor width does not make its symbolic element type
    // executable: forwarding can call another generic with that element type.
    if (row < count && compact_hir_core[row].kind == 3u)
    {
        uint return_type = compact_fn_return_type[row];
        if ((return_type < count &&
             semantic_expr_ref_tag_by_hir[return_type] == TYPE_REF_GENERIC_PARAM) ||
            unclosed_type_layout(return_type, count))
            InterlockedAnd(semantic_function_flag[row], 0u);
    }
    if (row < count &&
        (compact_hir_core[row].kind == 20u || compact_hir_core[row].kind == 30u) &&
        (semantic_expr_ref_tag_by_hir[row] == TYPE_REF_GENERIC_PARAM ||
         unclosed_type_layout(row, count)))
    {
        // Indexing and iteration need the element's concrete storage stride
        // even when the function returns only a status or count. A borrowed
        // descriptor's known width does not determine its element layout.
        uint encoded_function = semantic_enclosing_fn_by_hir[row];
        if (encoded_function != 0u && encoded_function - 1u < count)
            InterlockedAnd(semantic_function_flag[encoded_function - 1u], 0u);
    }
    if (row < count && compact_hir_core[row].kind == 21u &&
        unclosed_type_layout(compact_hir_payload[row].b, count))
    {
        // A concrete result field can still follow fields with symbolic widths.
        // Delay every such member load until its receiver layout is checked.
        uint encoded_function = semantic_enclosing_fn_by_hir[row];
        if (encoded_function != 0u && encoded_function - 1u < count)
            InterlockedAnd(semantic_function_flag[encoded_function - 1u], 0u);
    }
    uint parameter_count = min(compact_param_count[0u], gParams.param_capacity);
    if (row < parameter_count)
    {
        HirParam parameter = compact_params[row];
        if (parameter.owner < count && unclosed_type_reference(
            semantic_param_ref_tag_by_row[row], semantic_param_ref_payload_by_row[row]))
            InterlockedAnd(semantic_function_flag[parameter.owner], 0u);
    }
    uint payload_count = min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
    if (row >= payload_count) return;
    HirMatchPayload binding = compact_match_payloads[row];
    if (!symbolic_payload_layout(binding, count, payload_count)) return;
    uint pattern = binding.pattern;
    uint declaration = semantic_value_decl_by_hir[pattern];
    if (declaration >= gParams.n_tokens || semantic_value_used[declaration] == 0u)
        return;
    uint encoded_function = semantic_enclosing_fn_by_hir[pattern];
    if (encoded_function == 0u || encoded_function - 1u >= count) return;
    // A symbolic match payload has no concrete load width or scalar machine
    // type yet. Keep its checked interface and source as an uninstantiated
    // template, without publishing a native definition with a guessed body.
    // Unused bindings leave tag-only generic bodies executable.
    InterlockedAnd(semantic_function_flag[encoded_function - 1u], 0u);
}
