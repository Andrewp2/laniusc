// Indirect arguments of the export steps, written only by the one-lane
// planning steps. A kernel dispatched indirectly must not bind this buffer
// (a dispatch cannot use one buffer as storage and as indirect arguments),
// so only the planning steps import this module.
import type_checker.retention.retention_job;

public globallycoherent RWStructuredBuffer<uint> rt_x_dispatch; // 3 words per RT_D_* slot

public void set_dispatch(uint slot, uint lanes)
{
    uint groups = (lanes + 255u) / 256u;
    uint x = min(groups, 65535u);
    uint y = groups == 0u ? 0u : (groups + 65534u) / 65535u;
    uint at = 3u * slot;
    rt_x_dispatch[at] = x;
    rt_x_dispatch[at + 1u] = y;
    rt_x_dispatch[at + 2u] = 1u;
}
