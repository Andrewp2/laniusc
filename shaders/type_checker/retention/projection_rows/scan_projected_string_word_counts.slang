// Parallel exclusive offsets of decoded string words in instance/row order.
// Each string includes its zero terminator and word padding. The host records
// only logarithmically many scan distances; it never reads string metadata.
import type_checker.retention.projection.retained_projection_workspace;
StructuredBuffer<uint> pj_string_scan_config; // distance, input buffer (0=a)

[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint i = pj_lane(id);
    uint rows = pj_total(PJ_C_ROWS);
    if (i > rows) return;
    uint distance = pj_string_scan_config[0];
    if (distance == 0u)
    {
        uint words = 0u;
        if (i != 0u)
        {
            uint rank = pj_rank_of(PJ_C_ROWS, i - 1u, 0u, pj_instance_count());
            uint row = i - 1u - pj_base_at(rank, PJ_C_ROWS);
            uint4 p = pj_row(rank,row,2u);
            if (pj_row(rank,row,0u).x == RT_HIR_LITERAL_EXPR && p.x == 28u &&
                p.y < pj_side_len(rank,PJ_SIDE_STRINGS))
            {
                uint length = pj_side(rank,PJ_SIDE_STRINGS,p.y,0u).z;
                if (length >= 0xfffffffbu) pj_row_fail(i-1u,PJ_E_INPUT_CAPACITY,length);
                else words = (length + 4u) >> 2u;
            }
        }
        pj_string_offsets[i] = words;
        return;
    }
    bool a = pj_string_scan_config[1] == 0u;
    uint own = a ? pj_string_offsets[i] : pj_string_scratch[i];
    uint prior = i >= distance ? (a ? pj_string_offsets[i-distance] : pj_string_scratch[i-distance]) : 0u;
    if (own > 0x3fffffffu || prior > 0x3fffffffu - min(own,0x3fffffffu))
    {
        pj_row_fail(min(i,rows-1u),PJ_E_INPUT_CAPACITY,own);
        own = prior = 0u;
    }
    if (a) pj_string_scratch[i] = own + prior;
    else pj_string_offsets[i] = own + prior;
}
