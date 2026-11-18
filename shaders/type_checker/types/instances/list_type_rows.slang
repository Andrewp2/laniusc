// Lists the source rows that hold a type, before the inference rounds
// (live_type_row_list.slang). type_live_row_count[0] was cleared before.
#include "live_type_rows.slang"

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> type_live_rows;
RWStructuredBuffer<uint> type_live_row_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint lanes = live_type_row_lanes(gParams.n_tokens, token_count[0u]);
    uint source_rows; uint rows; uint list; uint stride;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    type_instance_kind.GetDimensions(rows, stride);
    type_live_rows.GetDimensions(list, stride);
    uint source = min(gParams.n_tokens, min(source_rows, rows));
    // Every lane of a wave runs the same number of steps, so the wave's
    // append stays one atomic per step.
    uint first = lane - WaveGetLaneIndex();
    if (first >= lanes) return;
    for (uint base = first; base < source; base += lanes)
    {
        uint row = base + WaveGetLaneIndex();
        bool hold = lane < lanes && row < source && type_instance_kind[row] != 0u;
        uint count = WaveActiveCountBits(hold);
        uint slot = 0u;
        if (WaveIsFirstLane() && count != 0u) InterlockedAdd(type_live_row_count[0u], count, slot);
        slot = WaveReadLaneFirst(slot) + WavePrefixCountBits(hold);
        if (hold && slot < list) type_live_rows[slot] = row;
    }
}
