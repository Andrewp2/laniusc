import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

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
StructuredBuffer<uint> semantic_array_length;
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
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

uint lir_for_hir(uint node, uint hir_count)
{
    return node != LIR_INVALID && node < hir_count && semantic_lir_count[node] != 0u
        ? semantic_lir_offset[node]
        : LIR_INVALID;
}

uint value_metadata_for_hir(uint node, uint hir_count)
{
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
    uint scalar_type = semantic_lir_type(semantic_expr_type[node]);
    if (scalar_type >= TY_STRUCT_BASE && scalar_type < TY_ENUM_BASE)
        return scalar_type - TY_STRUCT_BASE;
    if (semantic_expr_ref_tag[node] == TYPE_REF_SCALAR)
    {
        uint type_id = semantic_expr_ref_payload[node];
        if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
            return type_id - TY_STRUCT_BASE;
    }
    uint token = semantic_aggregate_decl_token[node];
    return token < gParams.n_tokens ? token : LIR_INVALID;
}

uint aggregate_word_count_for_hir(uint node, uint hir_count)
{
    if (node >= hir_count) return 1u;
    uint instruction = lir_for_hir(node, hir_count);
    if (instruction != LIR_INVALID)
    {
        uint materialized = semantic_lir_core[instruction].value_word_count;
        if (materialized != 0u) return materialized;
    }
    uint array_length = semantic_array_length[node];
    if (array_length != LIR_INVALID) return array_length;
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

uint call_argument_word_offset(uint start, uint ordinal, uint hir_count)
{
    uint offset = 1u; // enum discriminant
    for (uint prior = 0u; prior < ordinal; prior += 1u)
    {
        HirCallArg argument = compact_call_args[start + prior];
        offset += aggregate_word_count_for_hir(argument.value, hir_count);
    }
    return offset;
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
    if (row < array_count)
    {
        HirArrayElement source = compact_array_elements[row];
        result.aggregate_instruction = lir_for_hir(source.array, hir_count);
        result.value_instruction = lir_for_hir(source.value, hir_count);
        result.ordinal = source.ordinal;
        result.name_token = LIR_INVALID;
        result.value_metadata = value_metadata_for_hir(source.value, hir_count);
        result.word_offset = source.ordinal;
        result.word_count = 1u;
    }
    else if (row < array_count + field_count)
    {
        HirField source = compact_fields[row - array_count];
        // Declaration fields deliberately remain non-executable metadata.
        // Only struct-literal owners resolve to an aggregate instruction.
        bool literal = source.owner < hir_count &&
            compact_hir_core[source.owner].kind == HIR_STRUCT_LITERAL_EXPR;
        result.aggregate_instruction = literal
            ? lir_for_hir(source.owner, hir_count) : LIR_INVALID;
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
        if (field_row < gParams.element_capacity)
        {
            result.word_offset = semantic_struct_field_word_offset_by_row[field_row];
            result.word_count = semantic_struct_field_word_count_by_row[field_row];
        }
    }
    else
    {
        uint call_row = row - array_count - field_count;
        HirCallArg source = compact_call_args[call_row];
        bool constructor = source.call < hir_count &&
            semantic_call_kind[source.call] == 5u;
        result.aggregate_instruction = constructor
            ? lir_for_hir(source.call, hir_count) : LIR_INVALID;
        result.value_instruction = constructor
            ? lir_for_hir(source.value, hir_count) : LIR_INVALID;
        result.ordinal = source.ordinal;
        result.name_token = LIR_INVALID;
        result.value_metadata = value_metadata_for_hir(source.value, hir_count);
        uint start = call_row >= source.ordinal ? call_row - source.ordinal : LIR_INVALID;
        result.word_offset = constructor && start != LIR_INVALID
            ? call_argument_word_offset(start, source.ordinal, hir_count) : LIR_INVALID;
        result.word_count = constructor
            ? max(aggregate_word_count_for_hir(source.value, hir_count), 1u) : 0u;
    }
    semantic_lir_aggregate_elements[row] = result;
}
