// Projection step 9: one lane. Publishes the current batch's lowering
// counts and its figures in the status words.
import type_checker.retention.projection.pj_out;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    Batch b = pj_batch();
    ob_count_rows[0u] = b.rows;
    ob_count_call_args[0u] = pj_batch_side(PJ_SIDE_CALL_ARGS);
    ob_count_fields[0u] = pj_batch_side(PJ_SIDE_FIELDS);
    ob_count_match_arms[0u] = 0u;
    ob_count_match_payloads[0u] = 0u;
    ob_count_array_elements[0u] = 0u;
    ob_count_strings[0u] = 0u;
    ob_count_params[0u] = pj_batch_side(PJ_SIDE_PARAMS);
    pj_status[PJ_S_BATCH + 0u] = b.lo;
    pj_status[PJ_S_BATCH + 1u] = b.hi;
    pj_status[PJ_S_BATCH + 2u] = b.rows;
    pj_status[PJ_S_BATCH + 3u] = b.tokens;
}
