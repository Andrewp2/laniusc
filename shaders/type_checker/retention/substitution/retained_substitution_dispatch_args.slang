// Indirect arguments of the substitution kernels, written only by the
// single-lane planners (a kernel dispatched indirectly must not bind them).
import type_checker.retention.substitution.retained_substitution_workspace;

public globallycoherent RWStructuredBuffer<uint> sb_dispatch; // 3 words per SB_D_* slot

public void sb_set_dispatch(uint slot, uint lanes)
{
    uint groups = (lanes + 255u) / 256u;
    uint x = min(groups, 65535u);
    uint y = groups == 0u ? 0u : (groups + 65534u) / 65535u;
    uint at = 3u * slot;
    sb_dispatch[at] = x;
    sb_dispatch[at + 1u] = y;
    sb_dispatch[at + 2u] = 1u;
}
