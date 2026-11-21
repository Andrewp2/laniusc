// One lane, after emitting requests, publishes the allocated count,
// or zero when the
// round is not armed. A round without
// schema records converges. A round whose requests or fields exceed their
// buffers stops with PS_STOP_CAPACITY and its demands; the host grows the
// buffers and resumes the round (mode 1, which runs while the round is
// armed in ps_round even when its flag was cleared by a later gate).
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
public RWStructuredBuffer<uint> sb_request_count;
public void reserve_retained_schema_requests(bool resume)
{
    sb_request_count[0] = 0u;
    if (ps_status[PS_STOP] != PS_STOP_RUNNING || (!resume && ps_round[4] == 0u)) return;
    if (ps_status[PS_ERROR] != 0u)
    {
        ps_status[PS_STOP] = PS_STOP_FAILED;
        return;
    }
    uint count = ps_round_count();
    uint base = ps_round[2];
    if (count == 0u)
    {
        ps_round[4] = 0u;
        ps_status[PS_STOP] = PS_STOP_CONVERGED;
        return;
    }
    bool fields = base <= 0xffffffffu - count && base + count <= ps_config[PS_CFG_FIELD_CAPACITY];
    if (count > ps_config[PS_CFG_REQUEST_CAPACITY] || !fields)
    {
        ps_status[PS_DEMAND_REQUESTS] = count;
        ps_status[PS_DEMAND_FIELDS] = base <= 0xffffffffu - count ? base + count : 0xffffffffu;
        ps_status[PS_STOP] = PS_STOP_CAPACITY;
        return;
    }
    sb_request_count[0] = count;
}
