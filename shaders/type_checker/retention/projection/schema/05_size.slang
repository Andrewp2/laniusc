// One lane, after the scan. Sizes the round's requests from the scan's
// total: it writes the substitution's request count and the request-lane
// dispatch, or zero of both when the round is not armed. A round without
// schema records converges. A round whose requests or fields exceed their
// buffers stops with PS_STOP_CAPACITY and its demands; the host grows the
// buffers and resumes the round (mode 1, which runs while the round is
// armed in ps_round even when its flag was cleared by a later gate).
import type_checker.retention.projection.schema.common;
RWStructuredBuffer<uint> ps_round;
RWStructuredBuffer<uint> ps_indirect;
RWStructuredBuffer<uint> sb_request_count;
[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    ps_write_dispatch(ps_indirect, 3u, 0u);
    sb_request_count[0] = 0u;
    bool resume = ps_config[PS_CFG_MODE] == 1u;
    if (ps_status[PS_STOP] != PS_STOP_RUNNING || (!resume && ps_round[4] == 0u)) return;
    if (ps_status[PS_ERROR] != 0u)
    {
        ps_status[PS_STOP] = PS_STOP_FAILED;
        return;
    }
    uint count = ps_scan_a[ps_round[1] - ps_round[0]];
    uint base = ps_round[2];
    ps_round[3] = count;
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
    ps_write_dispatch(ps_indirect, 3u, count);
}
