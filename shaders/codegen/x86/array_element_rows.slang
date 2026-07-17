// Dense array-element value to compact family-row projection.
//
// Every downstream x86 pass starts with either a dense HIR value or a raw
// executable node that maps to one. This table lets those passes recover the
// compact array-element record without retaining parser-owned raw columns.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct HirArrayElement
{
    uint array;
    uint value;
    uint ordinal;
    uint file_id;
};
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> raw_to_compact_hir;
RWStructuredBuffer<uint> x86_array_element_row_by_hir;
RWStructuredBuffer<uint> x86_struct_literal_field_row_by_hir;
RWStructuredBuffer<uint> x86_compact_expr_wrapper;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint element_count = min(compact_array_element_row_count[0u], gParams.n_hir_nodes);
    if (row < element_count)
    {
        HirArrayElement element = compact_array_elements[row];
        if (element.value != INVALID && element.value < hir_count)
            atomic_u32_min(x86_array_element_row_by_hir, element.value, row);
    }
    uint field_count = min(compact_field_count[0u], gParams.n_hir_nodes);
    if (row < field_count)
    {
        HirField field = compact_fields[row];
        if (field.value != INVALID && field.value < hir_count &&
            field.owner != INVALID && field.owner < hir_count &&
            compact_hir_core[field.owner].kind == HIR_STRUCT_LITERAL_EXPR)
            atomic_u32_min(x86_struct_literal_field_row_by_hir, field.value, row);
    }
    if (row < gParams.n_hir_nodes)
    {
        uint dense = raw_to_compact_hir[row];
        if (dense != INVALID && dense < hir_count)
        {
            uint raw_kind = hir_kind[row];
            if (raw_kind == HIR_EXPR)
                atomic_u32_min(x86_compact_expr_wrapper, dense, row);
        }
    }
}
