import primitive_types;
import type_checker.concrete_type_equality;
import type_checker.constant_atoms_identity;
import hir_records;
import type_checker.checked_array_counts;
import checked_semantic_artifact;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_call_args; uint n_hir_nodes; uint lir_capacity; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> semantic_call_receiver;
StructuredBuffer<uint> semantic_call_target;
StructuredBuffer<uint> semantic_call_kind;
StructuredBuffer<uint> semantic_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_call_arg_prefix_by_hir;
StructuredBuffer<uint> semantic_expr_type;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint2> semantic_argument_value_layout;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_place_original_count;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
RWStructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint SEMANTIC_CALL_FUNCTION = 1u;
static const uint DISPATCH_X_STRIDE = 16776960u;

#include "receiver_source.slang"

void invalid_array_contract(uint node)
{
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
    InterlockedMin(lowering_status[0u].first_unsupported_hir, node);
}

bool array_contract_length(uint instance, out uint length)
{
    length = INVALID;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity) return false;
    uint kind = type_instance_kind[instance];
    if (kind == 3u)
    {
        length = SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME;
        return true;
    }
    if (kind != 2u) return false;
    // This pass has no token-count parameter. The producer clears the entire
    // scalar buffer before publishing active declarations, so its physical
    // capacity is a safe bound and inactive declarations remain inadmissible.
    uint tokens = checked_source_constant_parameter_capacity();
    uint count;
    if (checked_source_array_count(type_instance_len_kind[instance],
        type_instance_len_payload[instance], tokens, count))
    {
        if (count >= SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME) return false;
        length = count;
        return true;
    }
    // Deferred original generic bodies retain ARRAY_PAIR + INVALID. The
    // function-publication closure gate must discharge this contract before
    // a selected executable body can publish a native definition.
    ConstantReferenceDescriptor descriptor;
    return inspect_constant_reference<CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(
        uint3(type_instance_len_kind[instance], type_instance_len_payload[instance], 0u),
        tokens, descriptor) && descriptor.disposition == CONSTANT_REFERENCE_SYMBOLIC &&
        scalar_is_integer(descriptor.terminal_scalar);
}

uint array_length_for_hir(uint node)
{
    if (node >= gParams.n_hir_nodes) return INVALID;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    uint instance = semantic_expr_ref_payload[node];
    if (semantic_expr_ref_tag[node] != 3u || instance >= capacity ||
        (type_instance_kind[instance] != 2u && type_instance_kind[instance] != 3u))
        return semantic_array_length[node];
    uint length;
    if (!array_contract_length(instance, length)) invalid_array_contract(node);
    return length;
}

uint lir_for_hir(uint node)
{
    if (node == INVALID || node >= gParams.n_hir_nodes ||
        semantic_place_original_count[node] == 0u)
        return INVALID;
    uint first = semantic_lir_offset[node];
    // This must use the same HIR-to-value convention as semantic
    // materialization. Most expression identities name their first row;
    // structured match and short-circuit recipes publish a final VALUE_GET.
    return semantic_argument_value_layout[node].x != 0u ||
        compact_hir_core[node].kind == HIR_MATCH_EXPR ||
        semantic_lir_is_short_circuit(
            compact_hir_core[node], compact_hir_payload[node])
        ? first + semantic_place_original_count[node] - 1u : first;
}

uint value_metadata_for_hir(uint node)
{
    if (node >= gParams.n_hir_nodes) return 0u;
    uint result = semantic_lir_value_metadata(
            semantic_lir_type(semantic_expr_type[node]),
            semantic_expr_ref_tag[node],
            semantic_expr_ref_payload[node]);
    // Array-length metadata also annotates scalar index projections with the
    // base array's length for bounds checking. Inspect the final materialized
    // producer as well as the HIR node so forwarding wrappers stay scalar.
    uint instruction = lir_for_hir(node);
    bool indexed_scalar = instruction < gParams.lir_capacity &&
        semantic_lir_op(semantic_lir_core[instruction]) == SEMANTIC_LIR_OP_LOAD &&
        (semantic_lir_core[instruction].flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u;
    uint materialized_type = instruction < gParams.lir_capacity
        ? semantic_lir_core[instruction].type_id : 0u;
    bool slice_pair = instruction < gParams.lir_capacity &&
        (semantic_lir_core[instruction].flags &
            SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u;
    uint instance = semantic_expr_ref_payload[node];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    // Copy rows preserve the complete checked reference even when the legacy
    // scalar cache has no code for a native array (e.g. [str; N]). Its type
    // graph, not that cache, determines the pointer/length call contract.
    bool checked_array = semantic_expr_ref_tag[node] == 3u &&
        instance < capacity && type_instance_kind[instance] == 2u;
    bool array_value = checked_array || (materialized_type >= 128u &&
        materialized_type < 4096u &&
        compact_hir_core[node].kind != HIR_INDEX_EXPR && !indexed_scalar);
    if (slice_pair || checked_array ||
        (array_value && semantic_array_length[node] != INVALID))
        // Arrays cross function boundaries as a view, not as an aggregate
        // pointer. Keeping these two ABI categories disjoint also keeps the
        // runtime length component a narrow integer.
        result = (result & ~SEMANTIC_LIR_VALUE_AGGREGATE) |
            SEMANTIC_LIR_VALUE_ARRAY_PAIR;
    else if (!indexed_scalar)
    {
        // A resolved aggregate-return call can retain only its compact scalar
        // type code in the expression side table. Materialization has already
        // recovered the concrete ABI word count, so use that canonical fact
        // instead of truncating the aggregate storage pointer at a call site.
        if (instruction < gParams.lir_capacity &&
            semantic_lir_core[instruction].value_word_count != 0u)
            result |= SEMANTIC_LIR_VALUE_AGGREGATE;
    }
    if (semantic_expr_ref_tag[node] == 3u && instance < capacity &&
        type_instance_kind[instance] == 4u)
        return SEMANTIC_LIR_TY_POINTER;
    return result;
}

uint value_metadata_for_parameter(uint call, uint ordinal, uint fallback)
{
    // A direct callee's parameter is the ABI contract. Expression-side
    // array-length metadata is also used for bounds authentication and can
    // therefore make an indexed scalar look slice-shaped. Do not let that
    // auxiliary fact change the number of words crossing a call boundary.
    if (call >= gParams.n_hir_nodes ||
        semantic_call_kind[call] != SEMANTIC_CALL_FUNCTION)
        return fallback;
    uint target = semantic_call_target[call];
    if (target >= gParams.n_hir_nodes) return fallback;
    SemanticLirFunction function = semantic_lir_functions[target];
    if (ordinal >= function.param_count || function.param_start == INVALID)
        return fallback;
    uint parameter_row = function.param_start + ordinal;
    if (parameter_row >= gParams.n_hir_nodes) return fallback;
    SemanticLirParam parameter = semantic_lir_params[parameter_row];
    if (parameter.function_id != target || parameter.ordinal != ordinal)
        return fallback;

    uint contract = semantic_lir_value_metadata(
        parameter.type_id, SEMANTIC_TYPE_REF_INVALID, INVALID);
    if ((parameter.value_metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) != 0u)
        contract = (contract & ~SEMANTIC_LIR_VALUE_AGGREGATE) |
            SEMANTIC_LIR_VALUE_ARRAY_PAIR;
    return contract;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint explicit_count = min(gParams.n_call_args, compact_call_arg_count[0u]);
    if (row < explicit_count)
    {
        HirCallArg source = compact_call_args[row];
        if (source.call < gParams.n_hir_nodes &&
            semantic_call_arg_count_by_hir[source.call] != 0u)
        {
            uint receiver_shift = semantic_call_receiver[source.call] != INVALID ? 1u : 0u;
            uint destination = semantic_call_arg_prefix_by_hir[source.call] +
                receiver_shift + source.ordinal;
            SemanticLirCallArg result;
            result.call_instruction = semantic_lir_offset[source.call];
            result.value_instruction = lir_for_hir(source.value);
            result.ordinal = source.ordinal + receiver_shift;
            result.value_metadata = value_metadata_for_parameter(
                source.call, result.ordinal,
                value_metadata_for_hir(source.value));
            result.array_length = array_length_for_hir(source.value);
            // A descriptor's storage width is not its element count. Keep the
            // runtime marker so target lowering reads the actual length;
            // fixed arrays already carry their checked literal length here.
            if (destination < gParams.n_call_args)
                semantic_lir_call_args[destination] = result;
        }
    }

    if (row < gParams.n_hir_nodes &&
        semantic_call_receiver[row] != INVALID &&
        semantic_call_arg_count_by_hir[row] != 0u)
    {
        uint destination = semantic_call_arg_prefix_by_hir[row];
        SemanticLirCallArg receiver;
        receiver.call_instruction = semantic_lir_offset[row];
        uint source = receiver_source_hir(semantic_call_receiver[row], gParams.n_hir_nodes);
        if (source >= gParams.n_hir_nodes)
        {
            invalid_array_contract(row);
            return;
        }
        CheckedCallArtifact checked = semantic_calls_by_hir[row];
        bool adjusted = semantic_lir_count[source] > semantic_place_original_count[source];
        receiver.value_instruction = adjusted
            ? semantic_lir_offset[source] + semantic_lir_count[source] - 1u
            : lir_for_hir(source);
        receiver.ordinal = 0u;
        receiver.value_metadata = value_metadata_for_parameter(
            row, 0u, value_metadata_for_hir(source));
        receiver.array_length = array_length_for_hir(source);
        if (checked.receiver_adjustment_kind == 2u)
        {
            receiver.value_metadata = SEMANTIC_LIR_TY_POINTER;
            receiver.array_length = INVALID;
        }
        else if (checked.receiver_deref_count != 0u)
        {
            uint tag = checked.receiver_parameter_ref_tag;
            uint instance = checked.receiver_parameter_ref_payload;
            uint capacity; uint stride;
            type_instance_kind.GetDimensions(capacity, stride);
            uint kind = tag == 3u && instance < capacity ? type_instance_kind[instance] : 0u;
            if (kind == 4u) receiver.value_metadata = SEMANTIC_LIR_TY_POINTER;
            else if (kind == 2u || kind == 3u)
            {
                receiver.value_metadata = 128u | SEMANTIC_LIR_VALUE_ARRAY_PAIR;
                if (!array_contract_length(instance, receiver.array_length))
                    invalid_array_contract(row);
            }
            else receiver.value_metadata = semantic_lir_value_metadata(
                tag == 1u ? instance : 4096u, tag, instance);
        }
        if (destination < gParams.n_call_args)
            semantic_lir_call_args[destination] = receiver;
    }
}
