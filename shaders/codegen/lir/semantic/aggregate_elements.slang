import native_value_layout;
import type_checker.native_nominal_identity;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;
import codegen.lir.semantic.concrete_struct_layout;

struct Params
{
    uint element_capacity;
    uint n_hir_nodes;
    uint semantic_capacity;
    uint n_tokens;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_ordinal_by_row;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> semantic_call_kind;
StructuredBuffer<uint> semantic_expr_type;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_word_count;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
StructuredBuffer<uint> semantic_struct_field_start_by_hir;
StructuredBuffer<uint> semantic_struct_field_word_offset_by_row;
StructuredBuffer<uint> semantic_struct_field_word_count_by_row;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<uint> semantic_lir_aggregate_element_total;
RWStructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

uint lir_for_hir(uint node, uint hir_count)
{
    return node != LIR_INVALID && node < hir_count && semantic_lir_count[node] != 0u
        ? semantic_lir_offset[node] + semantic_lir_count[node] - 1u
        : LIR_INVALID;
}

uint value_metadata_for_hir(uint node, uint hir_count)
{
    if (node < hir_count && semantic_expr_ref_tag[node] == 3u &&
        semantic_expr_ref_payload[node] < checked_type_capacity() &&
        type_instance_kind[semantic_expr_ref_payload[node]] == 4u)
        return SEMANTIC_LIR_TY_POINTER;
    return node < hir_count
        ? semantic_lir_value_metadata(
            semantic_lir_type(semantic_expr_type[node]),
            semantic_expr_ref_tag[node],
            semantic_expr_ref_payload[node])
        : 0u;
}

uint aggregate_decl_token_for_hir(uint node, uint hir_count)
{
    if (node >= hir_count) return LIR_INVALID;
    // The checked declaration token is authoritative. Numeric type-code
    // windows can alias once a declaration's global token index exceeds 2048.
    uint token = semantic_aggregate_decl_token[node];
    if (token < gParams.n_tokens &&
        semantic_aggregate_hir_by_name_token[token] < hir_count)
        return token;
    uint scalar_type = semantic_lir_type(semantic_expr_type[node]);
    if (scalar_type >= TY_STRUCT_BASE && scalar_type < TY_ENUM_BASE)
    {
        token = scalar_type - TY_STRUCT_BASE;
        if (token < gParams.n_tokens &&
            semantic_aggregate_hir_by_name_token[token] < hir_count)
            return token;
    }
    if (semantic_expr_ref_tag[node] == TYPE_REF_SCALAR)
    {
        uint type_id = semantic_expr_ref_payload[node];
        if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
        {
            token = type_id - TY_STRUCT_BASE;
            if (token < gParams.n_tokens &&
                semantic_aggregate_hir_by_name_token[token] < hir_count)
                return token;
        }
    }
    return LIR_INVALID;
}

uint aggregate_word_count_for_hir(uint node, uint hir_count)
{
    if (node >= hir_count) return 1u;
    uint instruction = lir_for_hir(node, hir_count);
    if (semantic_argument_mode_by_hir[node] == 4u && instruction != LIR_INVALID)
    {
        // The checked source remains an array, but an accepted outer-boundary
        // borrow stores the captured slice descriptor in its destination.
        // Keep the original row's width for the backing storage and stride.
        SemanticLirCore value = semantic_lir_core[instruction];
        uint view_flags = SEMANTIC_LIR_FLAG_ARRAY_PAIR | SEMANTIC_LIR_FLAG_PLACE_VIEW;
        if (semantic_lir_op(value) == SEMANTIC_LIR_OP_AGGREGATE_COPY &&
            (value.flags & view_flags) == view_flags)
            return value.value_word_count;
    }
    // Native str values contain a pointer and length even though their
    // checked type is classified as a concrete scalar reference.
    if (semantic_lir_type(semantic_expr_type[node]) == SEMANTIC_LIR_TY_STRING ||
        (semantic_expr_ref_tag[node] == TYPE_REF_SCALAR &&
         semantic_expr_ref_payload[node] == SEMANTIC_LIR_TY_STRING))
        return 2u;
    uint tag = semantic_expr_ref_tag[node];
    uint payload = semantic_expr_ref_payload[node];
    if (tag == 3u && payload < checked_type_capacity())
        return type_instance_native_words[payload];
    if (tag == TYPE_REF_SCALAR && payload >= TY_STRUCT_BASE)
    {
        uint token = native_nominal_declaration_token(payload, gParams.n_tokens,
            hir_count, semantic_aggregate_hir_by_name_token, compact_hir_core);
        if (token != LIR_INVALID)
            return semantic_struct_word_count_by_hir[semantic_aggregate_hir_by_name_token[token]];
    }
    if (instruction != LIR_INVALID)
    {
        uint materialized = semantic_lir_core[instruction].value_word_count;
        if (materialized != 0u) return materialized;
    }
    uint array_length = semantic_array_length[node];
    if (array_length != LIR_INVALID &&
        array_length != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
        return array_length;
    uint projected = semantic_aggregate_word_count[node];
    if (projected != 0u) return projected;
    uint token = aggregate_decl_token_for_hir(node, hir_count);
    uint struct_hir = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
    uint words = struct_hir < hir_count
        ? semantic_struct_word_count_by_hir[struct_hir]
        : 0u;
    return max(words, 1u);
}

bool borrowed_array_argument(uint node, uint hir_count)
{
    return node < hir_count && semantic_argument_mode_by_hir[node] == 2u &&
        semantic_expr_ref_tag[node] == 3u &&
        semantic_expr_ref_payload[node] < checked_type_capacity() &&
        type_instance_kind[semantic_expr_ref_payload[node]] == 2u;
}

uint call_argument_word_count(uint node, uint hir_count)
{
    return borrowed_array_argument(node, hir_count) ? NATIVE_SLICE_WORDS
        : aggregate_word_count_for_hir(node, hir_count);
}

uint call_argument_word_offset(uint start, uint ordinal, uint hir_count)
{
    uint offset = 1u; // enum discriminant
    for (uint prior = 0u; prior < ordinal; prior += 1u)
    {
        HirCallArg argument = compact_call_args[start + prior];
        offset += call_argument_word_count(argument.value, hir_count);
    }
    return offset;
}

struct CheckedRecordFields : IConcreteStructFields
{
    static uint field_words(uint instance, uint owner, uint ordinal)
    {
        uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
        uint start = owner < hir_count ? semantic_struct_field_start_by_hir[owner] : LIR_INVALID;
        uint count = min(compact_field_count[0u], gParams.element_capacity);
        if (start >= count || ordinal >= count - start) return LIR_INVALID;
        HirField field = compact_fields[start + ordinal];
        if (field.owner != owner || field.ordinal != ordinal || field.value >= hir_count) return LIR_INVALID;
        uint tag = semantic_expr_ref_tag[field.value];
        uint payload = semantic_expr_ref_payload[field.value];
        if (!checked_scoped_reference(tag, payload, instance,
            gParams.n_tokens, tag, payload)) return LIR_INVALID;
        if (tag == 3u && payload < checked_type_capacity())
            return type_instance_kind[payload] == 3u ? NATIVE_SLICE_WORDS : type_instance_native_words[payload];
        if (tag != 1u || payload == 0u) return LIR_INVALID;
        if (payload < 128u) return payload == 7u ? 2u : 1u;
        uint token = native_nominal_declaration_token(payload, gParams.n_tokens,
            hir_count, semantic_aggregate_hir_by_name_token, compact_hir_core);
        return token != LIR_INVALID
            ? semantic_struct_word_count_by_hir[semantic_aggregate_hir_by_name_token[token]] : LIR_INVALID;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint array_count = min(compact_array_element_count[0u], gParams.element_capacity);
    uint field_count = min(compact_field_count[0u], gParams.element_capacity);
    uint call_arg_count = min(compact_call_arg_count[0u], gParams.element_capacity);
    if (row == 0u && (compact_array_element_count[0u] > gParams.element_capacity ||
                     compact_field_count[0u] > gParams.element_capacity ||
                     compact_call_arg_count[0u] > gParams.element_capacity))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_AGGREGATE_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity,
                       max(compact_array_element_count[0u],
                           max(compact_field_count[0u], compact_call_arg_count[0u])));
        InterlockedMin(lowering_status[0u].available_capacity, gParams.element_capacity);
    }
    uint total = array_count + field_count + call_arg_count;
    if (row == 0u) semantic_lir_aggregate_element_total[0u] = total;
    if (row >= total) return;

    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    SemanticLirAggregateElement result;
    result.slice_array_length = LIR_INVALID;
    if (row < array_count)
    {
        HirArrayElement source = compact_array_elements[row];
        result.aggregate_instruction = source.array < hir_count && semantic_lir_count[source.array] != 0u
            ? semantic_lir_offset[source.array] : LIR_INVALID;
        result.value_instruction = lir_for_hir(source.value, hir_count);
        result.ordinal = source.ordinal;
        result.name_token = LIR_INVALID;
        result.value_metadata = value_metadata_for_hir(source.value, hir_count);
        // Arrays are homogeneous, so every element has the same checked ABI
        // width. Dense element ordinals therefore map directly to dense word
        // ranges without a serial prefix walk.
        result.word_count = aggregate_word_count_for_hir(source.value, hir_count);
        result.word_offset = source.ordinal * result.word_count;
    }
    else if (row < array_count + field_count)
    {
        HirField source = compact_fields[row - array_count];
        // Declaration fields deliberately remain non-executable metadata.
        // Only struct-literal owners resolve to an aggregate instruction.
        bool literal = source.owner < hir_count &&
            compact_hir_core[source.owner].kind == HIR_STRUCT_LITERAL_EXPR;
        result.aggregate_instruction = literal && semantic_lir_count[source.owner] != 0u
            ? semantic_lir_offset[source.owner] : LIR_INVALID;
        result.value_instruction = literal
            ? lir_for_hir(source.value, hir_count) : LIR_INVALID;
        result.ordinal = struct_init_field_ordinal_by_row[row - array_count];
        result.name_token = source.name_token;
        result.value_metadata = value_metadata_for_hir(source.value, hir_count);
        result.word_offset = result.ordinal;
        result.word_count = 1u;
        uint decl_token = aggregate_decl_token_for_hir(source.owner, hir_count);
        uint struct_hir = decl_token < gParams.n_tokens
            ? semantic_aggregate_hir_by_name_token[decl_token] : LIR_INVALID;
        uint field_start = struct_hir < hir_count
            ? semantic_struct_field_start_by_hir[struct_hir] : LIR_INVALID;
        uint field_row = field_start != LIR_INVALID ? field_start + result.ordinal : LIR_INVALID;
        uint instance = source.owner < hir_count ? semantic_expr_ref_payload[source.owner] : LIR_INVALID;
        if (literal && source.owner < hir_count && semantic_expr_ref_tag[source.owner] == 3u &&
            instance < checked_type_capacity() && type_instance_decl_token[instance] == LIR_INVALID &&
            external_type_library_id[instance] != LIR_INVALID)
        {
            // Imported declaration fields have already been checked and mapped
            // to ordinals on the owning interface page. Sum their value widths
            // in declaration order, independently of the written field order.
            result.word_count = aggregate_word_count_for_hir(source.value, hir_count);
            result.word_offset = 0u;
            HirPayload literal_payload = compact_hir_payload[source.owner];
            for (uint prior = 0u; prior < literal_payload.c; prior++)
            {
                uint prior_row = literal_payload.b + prior;
                if (prior_row >= field_count) break;
                if (struct_init_field_ordinal_by_row[prior_row] < result.ordinal)
                    result.word_offset += aggregate_word_count_for_hir(compact_fields[prior_row].value, hir_count);
            }
        }
        if (field_row < gParams.element_capacity)
        {
            result.word_offset = semantic_struct_field_word_offset_by_row[field_row];
            result.word_count = semantic_struct_field_word_count_by_row[field_row];
            // Deferred generic bodies have checked literal metadata but no
            // executable aggregate instruction until their body is rebound.
            if (result.aggregate_instruction != LIR_INVALID &&
                source.owner < hir_count && semantic_expr_ref_tag[source.owner] == 3u &&
                instance < checked_type_capacity() && type_instance_kind[instance] == 1u &&
                type_instance_arg_count[instance] != 0u)
            {
                uint2 range = concrete_struct_field_range<CheckedRecordFields>(
                    instance, struct_hir, result.ordinal, field_count);
                result.word_offset = range.x; result.word_count = range.y;
                if (range.x == LIR_INVALID || range.y == LIR_INVALID)
                {
                    result.word_count = 0u;
                    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
                    InterlockedMin(lowering_status[0u].first_unsupported_hir, source.owner);
                }
            }
            HirField declaration = compact_fields[field_row];
            bool slice_field = declaration.value < hir_count &&
                compact_hir_core[declaration.value].kind == HIR_TYPE &&
                compact_hir_payload[declaration.value].a == HIR_TYPE_FORM_SLICE;
            uint source_length = source.value < hir_count
                ? semantic_array_length[source.value] : LIR_INVALID;
            bool source_array = source.value < hir_count &&
                semantic_expr_ref_tag[source.value] == 3u &&
                semantic_expr_ref_payload[source.value] < checked_type_capacity() &&
                type_instance_kind[semantic_expr_ref_payload[source.value]] == 2u;
            if (slice_field && source_array && source_length != LIR_INVALID &&
                source_length != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME &&
                result.value_instruction < gParams.semantic_capacity &&
                (semantic_lir_core[result.value_instruction].flags &
                    SEMANTIC_LIR_FLAG_ARRAY_PAIR) == 0u)
                result.slice_array_length = source_length;
        }
    }
    else
    {
        uint call_row = row - array_count - field_count;
        HirCallArg source = compact_call_args[call_row];
        bool constructor = source.call < hir_count &&
            semantic_call_kind[source.call] == 5u;
        result.aggregate_instruction = constructor && semantic_lir_count[source.call] != 0u
            ? semantic_lir_offset[source.call] : LIR_INVALID;
        result.value_instruction = constructor
            ? lir_for_hir(source.value, hir_count) : LIR_INVALID;
        result.ordinal = source.ordinal;
        result.name_token = LIR_INVALID;
        result.value_metadata = value_metadata_for_hir(source.value, hir_count);
        uint start = call_row >= source.ordinal ? call_row - source.ordinal : LIR_INVALID;
        result.word_offset = constructor && start != LIR_INVALID
            ? call_argument_word_offset(start, source.ordinal, hir_count) : LIR_INVALID;
        result.word_count = constructor
            ? call_argument_word_count(source.value, hir_count) : 0u;
        if (constructor && borrowed_array_argument(source.value, hir_count))
        {
            // Use the existing aggregate view conversion, including the source
            // place's signed stride. The payload stores a slice descriptor,
            // and following payloads start after that descriptor's full width.
            uint length = semantic_array_length[source.value];
            if (length == LIR_INVALID || length == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
            {
                InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
                InterlockedMin(lowering_status[0u].first_unsupported_hir, source.call);
            }
            else result.slice_array_length = length;
        }
    }
    semantic_lir_aggregate_elements[row] = result;
}
