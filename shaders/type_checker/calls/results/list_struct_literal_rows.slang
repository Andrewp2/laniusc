// Lists, once per job before the inference rounds, the rows of the rounds'
// struct-literal passes (project_record_field_expectations_and_references, substitute_listed_struct_literal_field_expectations): the field rows owned by a struct
// literal, and the member and struct-literal HIR rows. The passes that give a
// field its expected type write only those field rows' name tokens
// (project_struct_init_fields, 04b, project_dependency_struct_literals), and the reference projection
// changes no other HIR row. One lane per HIR row and per field row;
// struct_literal_row_counts was cleared before.
import shared.syntax.hir_records;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
RWStructuredBuffer<uint> struct_literal_row_counts;
RWStructuredBuffer<uint> struct_literal_field_rows;
RWStructuredBuffer<uint> struct_literal_hir_rows;

static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

void append(uint list, uint row)
{
    uint slot; uint capacity; uint stride;
    InterlockedAdd(struct_literal_row_counts[list], 1u, slot);
    if (list == 0u)
    {
        struct_literal_field_rows.GetDimensions(capacity, stride);
        if (slot < capacity) struct_literal_field_rows[slot] = row;
    }
    else
    {
        struct_literal_hir_rows.GetDimensions(capacity, stride);
        if (slot < capacity) struct_literal_hir_rows[slot] = row;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint hir = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (lane < hir)
    {
        uint kind = compact_hir_core[lane].kind;
        if (kind == HIR_MEMBER_EXPR || kind == HIR_STRUCT_LITERAL_EXPR) append(1u, lane);
    }
    // The field rows the field expectation reads (struct_init_fields.slang).
    if (lane < min(compact_field_count[0u], gParams.n_tokens))
    {
        HirField field = compact_fields[lane];
        if (field.owner < hir && compact_hir_core[field.owner].kind == HIR_STRUCT_LITERAL_EXPR &&
            field.name_token < gParams.n_tokens)
            append(0u, lane);
    }
}
