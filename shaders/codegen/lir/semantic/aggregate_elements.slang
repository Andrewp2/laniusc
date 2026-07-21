import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint element_capacity;
    uint n_hir_nodes;
    uint semantic_capacity;
    uint reserved;
};
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
struct HirArrayElement { uint array; uint value; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_ordinal_by_row;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
RWStructuredBuffer<uint> semantic_lir_aggregate_element_total;
RWStructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint lir_for_hir(uint node, uint hir_count)
{
    return node != LIR_INVALID && node < hir_count && semantic_lir_count[node] != 0u
        ? semantic_lir_offset[node]
        : LIR_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint array_count = min(compact_array_element_count[0u], gParams.element_capacity);
    uint field_count = min(compact_field_count[0u], gParams.element_capacity);
    if (row == 0u && (compact_array_element_count[0u] > gParams.element_capacity ||
                     compact_field_count[0u] > gParams.element_capacity))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_AGGREGATE_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity,
                       max(compact_array_element_count[0u], compact_field_count[0u]));
        InterlockedMin(lowering_status[0u].available_capacity, gParams.element_capacity);
    }
    uint total = array_count + field_count;
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
    }
    else
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
    }
    semantic_lir_aggregate_elements[row] = result;
}
