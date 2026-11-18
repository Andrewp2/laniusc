// Sizes the listed row passes of the inference rounds (one lane): a lane per
// listed source row and per generated row so far. Rows generated later are
// visited by striding (live_type_row_list.slang).
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_application_count;
StructuredBuffer<uint> type_live_rows;
RWStructuredBuffer<uint> type_live_row_count;
RWStructuredBuffer<uint> type_live_row_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint source_rows; uint rows; uint list; uint stride;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    type_instance_kind.GetDimensions(rows, stride);
    type_live_rows.GetDimensions(list, stride);
    uint tail = source_rows >= rows ? 0u : min(type_application_count[0u], rows - source_rows);
    uint live = max(min(type_live_row_count[0u], list) + tail, 1u);
    uint groups = (live + 255u) / 256u;
    uint x = min(groups, 65535u);
    uint y = (groups + 65534u) / 65535u;
    type_live_row_args[0u] = x;
    type_live_row_args[1u] = y;
    type_live_row_args[2u] = 1u;
    type_live_row_count[1u] = x * y * 256u;
}
