// Projection step 9: one lane. Publishes the current batch's lowering
// counts and its figures in the status words.
//
// With the gate on (PJ_CFG_GATE), the host recorded this batch and its
// lowering before it read the check back, with the capacities in the
// configuration. The gate passes the batch only when the check passed and
// the batch fits those capacities. Otherwise it publishes zero counts, so
// the lowering recorded behind it finds no rows, and the host discards that
// lowering and lowers the batch again after the readback.
import type_checker.retention.projection.retained_lowering_columns;

uint verdict(Batch b, uint string_words)
{
    uint gate = pj_config[PJ_CFG_GATE];
    if (gate == PJ_GATE_OFF) return PJ_VERDICT_NONE;
    if (gate == PJ_GATE_FORCE_FAIL || pj_status[PJ_S_STATE] != PJ_STATE_CHECKED)
        return PJ_VERDICT_FAILED;
    uint side = 0u;
    for (uint k = 0u; k < PJ_SIDE_TABLES; k++) side = max(side, pj_batch_side(b, k));
    uint string_capacity; uint stride;
    ob_string_data.GetDimensions(string_capacity, stride);
    bool fits = b.rows <= pj_config[PJ_CFG_ROW_CAP]
        && b.tokens < pj_config[PJ_CFG_TOKEN_CAP]
        && side <= pj_config[PJ_CFG_SIDE_CAP]
        && string_words <= string_capacity;
    return fits ? PJ_VERDICT_PASSED : PJ_VERDICT_CAPACITY;
}

public void publish_retained_lowering_batch(Batch b)
{
    uint string_words = pj_string_offsets[pj_base_at(b.hi,PJ_C_ROWS)] -
        pj_string_offsets[pj_base_at(b.lo,PJ_C_ROWS)];
    uint gate = verdict(b, string_words);
    pj_status[PJ_S_GATE] = gate;
    bool open = gate == PJ_VERDICT_NONE || gate == PJ_VERDICT_PASSED;
    ob_count_rows[0u] = open ? b.rows : 0u;
    ob_count_call_args[0u] = open ? pj_batch_side(b, PJ_SIDE_CALL_ARGS) : 0u;
    ob_count_fields[0u] = open ? pj_batch_side(b, PJ_SIDE_FIELDS) : 0u;
    ob_count_match_arms[0u] = open ? pj_batch_side(b, PJ_SIDE_MATCH_ARMS) : 0u;
    ob_count_match_payloads[0u] = open ? pj_batch_side(b, PJ_SIDE_MATCH_PAYLOADS) : 0u;
    ob_count_array_elements[0u] = open ? pj_batch_side(b, PJ_SIDE_ARRAY_ELEMENTS) : 0u;
    ob_count_strings[0u] = open ? pj_batch_side(b, PJ_SIDE_STRINGS) : 0u;
    ob_string_pool_len[0u] = open ? 4u * string_words : 0u;
    ob_count_params[0u] = open ? pj_batch_side(b, PJ_SIDE_PARAMS) : 0u;
    pj_status[PJ_S_BATCH + 0u] = b.lo;
    pj_status[PJ_S_BATCH + 1u] = b.hi;
    pj_status[PJ_S_BATCH + 2u] = b.rows;
    pj_status[PJ_S_BATCH + 3u] = b.tokens;
}
