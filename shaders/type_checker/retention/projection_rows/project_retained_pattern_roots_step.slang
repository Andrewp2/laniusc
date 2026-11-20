// One lane per arm/payload. Roots take the scrutinee's type; each payload
// records membership and contributes to its parent's exact payload arity.
import type_checker.retention.projection.retained_projection_results;
import type_checker.retention.projection_rows.retained_pattern_projection;

public void project_retained_pattern_roots(uint lane)
{
    uint column = PJ_C_SIDE+PJ_SIDE_MATCH_ARMS;
    if (lane < pj_total(column))
    {
        uint rank = pj_rank_of(column,lane,0u,pj_instance_count());
        uint4 arm = pj_side(rank,PJ_SIDE_MATCH_ARMS,lane-pj_base_at(rank,column),0u);
        uint base = pj_base_at(rank,PJ_C_ROWS);
        uint rows = pj_inf(rank,1u).x;
        if (arm.x >= rows || arm.y >= rows || arm.z >= rows)
        { pj_row_fail(base,PJ_E_INCOMPLETE,lane); return; }
        uint4 match = pj_row(rank,arm.x,2u);
        uint status;
        uint t = match.x < rows ? pj_result(pj_req_row(rank,match.x),status) : RT_INVALID;
        pj_g_aux[base+arm.y].w = pj_referent(t);
    }
    column = PJ_C_SIDE+PJ_SIDE_MATCH_PAYLOADS;
    if (lane < pj_total(column))
    {
        uint rank = pj_rank_of(column,lane,0u,pj_instance_count());
        uint4 payload = pj_side(rank,PJ_SIDE_MATCH_PAYLOADS,lane-pj_base_at(rank,column),0u);
        uint base = pj_base_at(rank,PJ_C_ROWS);
        uint rows = pj_inf(rank,1u).x;
        if (payload.x >= pj_side_len(rank,PJ_SIDE_MATCH_ARMS) || payload.y >= rows || payload.w >= rows)
        { pj_row_fail(base,PJ_E_INCOMPLETE,lane); return; }
        pj_g_aux[base+payload.y].w = RT_INVALID;
        InterlockedAdd(pj_g_facts[base+payload.w].w,1u);
    }
}
