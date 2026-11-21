import type_checker.retention.discovery.discovery_workspace;

public void count_discovered_term(uint term, bool validate)
{
    if (rt_term_head[term].x == 0u || !rt_term_closed(term)) return;
    uint height = rt_term_height(term);
    if (height != 0u && height < 128u)
        InterlockedAdd(dg_levels[height], 1u);
    else if (validate)
        dg_status[10] = 8u;
}
