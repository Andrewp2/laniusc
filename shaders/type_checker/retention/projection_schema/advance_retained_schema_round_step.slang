// One lane. Mode 0 opens a round, mode 1 closes the last one.
//
// The previous round's substitution must have published its run before the
// next round can start. Otherwise the rounds stop with
// PS_STOP_UNPUBLISHED and the armed round stays in ps_round for the host,
// which substitutes it again. A gate that passes commits that round: its
// fields join the base.
//
// Mode 0 then arms the terms the store gained since the last round, or
// stops with PS_STOP_CONVERGED when there are none. Mode 1 converges when
// the store has no term past the last round; otherwise the rounds stay
// running and the host records more.
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
public void advance_retained_schema_round(uint mode, uint gate, bool published, bool failed)
{
    ps_round[4] = 0u;
    if (gate != 0u && failed)
    {
        InterlockedOr(ps_status[PS_ERROR], 4u);
        ps_status[PS_STOP] = PS_STOP_FAILED;
        return;
    }
    if (ps_status[PS_STOP] != PS_STOP_RUNNING) return;
    if (gate != 0u)
    {
        if (!published)
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
    if (mode == 1u) return;
    ps_status[PS_LO] = hi;
    ps_round[0] = lo;
    ps_round[1] = hi;
    ps_round[2] = ps_status[PS_BASE];
    ps_round[3] = 0u;
    ps_round[4] = 1u;
}
