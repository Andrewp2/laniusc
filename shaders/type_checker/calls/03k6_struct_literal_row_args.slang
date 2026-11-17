// Sizes the rounds' struct-literal passes over the rows 03k5 listed (one
// lane): match/01b over the field rows, 03k4 over the field rows and the
// HIR rows. A count past its list's capacity is clamped to it.
StructuredBuffer<uint> struct_literal_field_rows;
StructuredBuffer<uint> struct_literal_hir_rows;
RWStructuredBuffer<uint> struct_literal_row_counts;
RWStructuredBuffer<uint> struct_literal_field_args;
RWStructuredBuffer<uint> struct_literal_record_args;

void write_args(RWStructuredBuffer<uint> args, uint lanes)
{
    uint groups = (lanes + 255u) / 256u;
    uint x = min(groups, 65535u);
    args[0u] = x;
    args[1u] = x == 0u ? 0u : (groups + 65534u) / 65535u;
    args[2u] = 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint field_capacity; uint hir_capacity; uint stride;
    struct_literal_field_rows.GetDimensions(field_capacity, stride);
    struct_literal_hir_rows.GetDimensions(hir_capacity, stride);
    uint fields = min(struct_literal_row_counts[0u], field_capacity);
    uint rows = min(struct_literal_row_counts[1u], hir_capacity);
    struct_literal_row_counts[0u] = fields;
    struct_literal_row_counts[1u] = rows;
    write_args(struct_literal_field_args, fields);
    write_args(struct_literal_record_args, fields + rows);
}
