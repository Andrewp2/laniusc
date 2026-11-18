// One lane per payload, one dependent level per dispatch. A lane that
// resolves its payload sets PJ_S_PATTERN_CHANGED, which the host clears
// before the last round: a set word means more levels may remain. Types are read
// only from parents and are immutable once resolved. A nested pattern uses
// its parent's realized variant schema, never the outer scrutinee's type.
import type_checker.retention.projection_rows.retained_pattern_projection;

[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = pj_lane(dtid);
    uint column = PJ_C_SIDE+PJ_SIDE_MATCH_PAYLOADS;
    if (lane >= pj_total(column)) return;
    uint rank = pj_rank_of(column,lane,0u,pj_instance_count());
    uint4 payload = pj_side(rank,PJ_SIDE_MATCH_PAYLOADS,lane-pj_base_at(rank,column),0u);
    uint base = pj_base_at(rank,PJ_C_ROWS);
    uint rows = pj_inf(rank,1u).x;
    if (payload.y >= rows || payload.w >= rows || pj_g_aux[base+payload.y].w != RT_INVALID) return;
    uint parent = pj_g_aux[base+payload.w].w;
    if (!rt_is_term(parent)) return;
    uint4 schema = pj_variant_schema(parent,pj_pattern_variant(rank,payload.w));
    if (schema.x == RT_INVALID || payload.z >= schema.z)
    { pj_row_fail(base+payload.y,PJ_E_FIELD,payload.z); return; }
    pj_g_aux[base+payload.y].w = pj_schema_type(parent,schema.w+payload.z);
    pj_status[PJ_S_PATTERN_CHANGED] = 1u;
}
