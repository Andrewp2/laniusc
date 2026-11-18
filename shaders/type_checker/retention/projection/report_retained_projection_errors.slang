// Projection step 5b: one lane. Reduces the plan's rank errors and the
// check's row errors to the first error in (rank, row) order and maps it to
// its template location: the callable's DeclId, the body-relative row and
// token, the file id and the file-relative byte start of the row's first
// token. A rank error sorts before every row error of its rank. The state
// becomes CHECKED or FAILED.
import type_checker.retention.projection.retained_projection_workspace;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint n = pj_instance_count();
    uint r = pj_status[PJ_S_ERROR_RANK];
    uint g = pj_status[PJ_S_ERROR_ROW];
    for (uint w = 0u; w < 8u; w++) pj_status[PJ_S_FIRST + w] = RT_INVALID;
    pj_status[PJ_S_ERROR_JOB] = RT_INVALID;
    pj_status[PJ_S_ERROR_LEN] = 0u;
    if (r < n && (g == RT_INVALID || pj_base_at(r, PJ_C_ROWS) <= g))
    {
        uint4 e = pj_errors[r];
        pj_status[PJ_S_FIRST + 0u] = e.x;
        pj_status[PJ_S_FIRST + 1u] = e.y;
        pj_status[PJ_S_FIRST + 2u] = r;
        pj_status[PJ_S_FIRST + 3u] = pj_instances[r * PJ_INSTANCE_WORDS].x;
    }
    else if (g < pj_total(PJ_C_ROWS))
    {
        uint rank = pj_rank_of(PJ_C_ROWS, g, 0u, n);
        uint row = g - pj_base_at(rank, PJ_C_ROWS);
        uint2 e = pj_row_errors[g];
        uint token = pj_row(rank, row, 0u).z;
        uint4 i5 = pj_inf(rank, 5u);
        pj_status[PJ_S_FIRST + 0u] = e.x;
        pj_status[PJ_S_FIRST + 1u] = e.y;
        pj_status[PJ_S_FIRST + 2u] = rank;
        pj_status[PJ_S_FIRST + 3u] = pj_inf(rank, 0u).x;
        pj_status[PJ_S_FIRST + 4u] = row;
        pj_status[PJ_S_FIRST + 5u] = token;
        pj_status[PJ_S_FIRST + 6u] = i5.x;
        pj_status[PJ_S_ERROR_JOB] = rt_dir[pj_inf(rank,0u).z * RT_DIR_WORDS + 3u].z;
        if (token != RT_INVALID)
        {
            pj_status[PJ_S_FIRST + 7u] = i5.y + rt_seg_tokens[i5.w + token].y;
            pj_status[PJ_S_ERROR_LEN] = rt_seg_tokens[i5.w + token].z;
        }
    }
    pj_status[PJ_S_STATE] = pj_status[PJ_S_ERRORS] != 0u || pj_status[PJ_S_IDENTITY_OVERFLOW] != 0u
        ? PJ_STATE_FAILED : PJ_STATE_CHECKED;
}
