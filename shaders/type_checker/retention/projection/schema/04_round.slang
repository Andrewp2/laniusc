// One lane. Mode 0 opens a round, mode 1 closes the last one.
//
// Every later pass of a round is sized by the indirect arguments written
// here and by 05_size, so a stopped round dispatches no workgroups. The
// gate: when ps_config names a run, the previous round's substitution must
// have published it (bound as sb_counts); otherwise the rounds stop with
// PS_STOP_UNPUBLISHED and the armed round stays in ps_round for the host,
// which substitutes it again. A gate that passes commits that round: its
// fields join the base.
//
// Mode 0 then arms the terms the store gained since the last round, or
// stops with PS_STOP_CONVERGED when there are none. Mode 1 converges when
// the store has no term past the last round; otherwise the rounds stay
// running and the host records more.
import type_checker.retention.projection.schema.common;
import type_checker.retention.substitution.sb_consumer;
RWStructuredBuffer<uint> ps_round;
RWStructuredBuffer<uint> ps_indirect;
[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    ps_write_dispatch(ps_indirect, 0u, 0u);
    ps_write_dispatch(ps_indirect, 3u, 0u);
    ps_round[4] = 0u;
    if (ps_status[PS_STOP] != PS_STOP_RUNNING) return;
    uint gate = ps_config[PS_CFG_GATE_RUN];
    if (gate != 0u)
    {
        if (!sb_publication_current(gate))
        {
            ps_status[PS_STOP] = PS_STOP_UNPUBLISHED;
            return;
        }
        ps_status[PS_BASE] = ps_round[2] + ps_round[3];
        ps_status[PS_ROUNDS] += 1u;
    }
    if (rt_counts[RT_C_READY] == 0u || rt_counts[RT_C_GENERATION] != ps_config[PS_CFG_GENERATION])
    {
        InterlockedOr(ps_status[PS_ERROR], 1u);
        ps_status[PS_STOP] = PS_STOP_FAILED;
        return;
    }
    uint lo = ps_status[PS_LO];
    uint hi = rt_counts[RT_A_TERMS];
    ps_status[PS_TERMS] = hi;
    if (hi <= lo)
    {
        ps_status[PS_STOP] = PS_STOP_CONVERGED;
        return;
    }
    if (ps_config[PS_CFG_MODE] == 1u) return;
    ps_status[PS_LO] = hi;
    ps_round[0] = lo;
    ps_round[1] = hi;
    ps_round[2] = ps_status[PS_BASE];
    ps_round[3] = 0u;
    ps_round[4] = 1u;
    ps_write_dispatch(ps_indirect, 0u, hi - lo + 1u);
}
