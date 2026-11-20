// Projection step 4a: one lane per global row. Clears the row's error,
// facts and expression parent before the edges (4b) and the check (5).
import type_checker.retention.projection.retained_projection_workspace;

public void clear_projected_row_errors(uint g)
{
    if (g >= pj_total(PJ_C_ROWS)) return;
    pj_row_errors[g] = uint2(0u, 0u);
    pj_g_facts[g] = uint4(0u, RT_INVALID, RT_INVALID, 0u);
    pj_g_aux[g] = uint4(RT_INVALID, RT_INVALID, RT_INVALID, 0u);
}
