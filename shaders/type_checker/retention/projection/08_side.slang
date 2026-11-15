// Projection step 8: one lane per side-table index of the current batch,
// for each table. Copies call arguments, fields and parameters with batch
// indices; a field keeps its struct-init ordinal and a parameter receives
// its substituted declared type as the lowering's parameter reference.
// Array elements retain their owner, value and ordinal.
// Match arm and payload indices retain canonical order within each body.
import type_checker.retention.projection.pj_out;

void copy(Batch b, uint k, uint index)
{
    if (index >= pj_batch_side(k)) return;
    uint gi = pj_base_at(b.lo, PJ_C_SIDE + k) + index;
    uint rank = pj_rank_of(PJ_C_SIDE + k, gi, b.lo, b.hi);
    uint rel = gi - pj_base_at(rank, PJ_C_SIDE + k);
    Map m = pj_map(b, rank);
    uint4 record = pj_side(rank, k, rel, 0u);
    uint4 extra = pj_side(rank, k, rel, 1u);
    if (k == PJ_SIDE_CALL_ARGS)
        ob_call_args[index] = uint4(pj_abs_row(m, record.x), pj_abs_row(m, record.y), record.z, 0u);
    else if (k == PJ_SIDE_FIELDS)
    {
        ob_fields[index] = uint4(pj_abs_row(m, record.x), pj_abs_token(m, record.y), pj_abs_row(m, record.z), record.w);
        ob_struct_init_field_ordinal[index] = extra.x;
    }
    else if (k == PJ_SIDE_PARAMS)
    {
        ob_params[index] = uint4(pj_abs_row(m, record.x), pj_abs_token(m, record.y), pj_abs_row(m, record.z), record.w);
        uint status;
        uint2 ref = pj_ref_of(pj_result(pj_req_param(rank, record.w), status));
        ob_param_ref_tag[index] = ref.x;
        ob_param_ref_payload[index] = ref.y;
    }
    else if (k == PJ_SIDE_MATCH_ARMS)
    {
        ob_match_arms[index] = uint4(pj_abs_row(m,record.x),pj_abs_row(m,record.y),pj_abs_row(m,record.z),record.w);
        ob_match_payload_start[index] = pj_abs_side(m,PJ_SIDE_MATCH_PAYLOADS,extra.x);
        ob_match_payload_count[index] = extra.y;
    }
    else if (k == PJ_SIDE_MATCH_PAYLOADS)
        ob_match_payloads[index] = uint4(pj_abs_side(m,PJ_SIDE_MATCH_ARMS,record.x),pj_abs_row(m,record.y),record.z,pj_abs_row(m,record.w));
    else if (k == PJ_SIDE_ARRAY_ELEMENTS)
        ob_array_elements[index] = uint4(pj_abs_row(m, record.x), pj_abs_row(m, record.y), record.z, record.w);
    else if (k == PJ_SIDE_STRINGS)
    {
        uint global = pj_base_at(rank,PJ_C_ROWS) + record.x;
        uint offset = pj_string_offsets[global] - pj_string_offsets[pj_base_at(b.lo,PJ_C_ROWS)];
        ob_strings[index] = uint4(pj_abs_row(m,record.x),offset*4u,record.z,0u);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = pj_lane(dtid);
    Batch b = pj_batch();
    if (b.lo >= b.hi) return;
    copy(b, PJ_SIDE_CALL_ARGS, index);
    copy(b, PJ_SIDE_FIELDS, index);
    copy(b, PJ_SIDE_PARAMS, index);
    copy(b, PJ_SIDE_MATCH_ARMS, index);
    copy(b, PJ_SIDE_MATCH_PAYLOADS, index);
    copy(b, PJ_SIDE_ARRAY_ELEMENTS, index);
    copy(b, PJ_SIDE_STRINGS, index);
}
