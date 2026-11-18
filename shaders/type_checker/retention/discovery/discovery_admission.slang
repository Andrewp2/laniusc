__exported import type_checker.retention.discovery.discovery_workspace;
import type_checker.trait_solver.retained_catalog.retained_route_abi;

public StructuredBuffer<uint> dg_proofs;
// enabled, epoch lo/hi, arena lo/hi, serial, generation, reserved.
public StructuredBuffer<uint> dg_proof_identity;

public bool dg_proofs_current()
{
    if (dg_proof_identity[0] == 0u ||
        dg_proofs[RP_H_MAGIC] != RP_MAGIC || dg_proofs[RP_H_VERSION] != RP_VERSION ||
        dg_proofs[RP_H_STATUS] != RP_VALID || rt_counts[RT_C_READY] != 1u) return false;
    for (uint i = 0u; i < 6u; i++)
        if (dg_proofs[RP_H_EPOCH + i] != dg_proof_identity[1u+i]) return false;
    return dg_proofs[RP_H_GENERATION] == rt_counts[RT_C_GENERATION] &&
        dg_proofs[RP_H_USES] == rt_counts[RT_A_USES] &&
        dg_proofs[RP_H_STORE_DIRS] == rt_counts[RT_A_DIR] &&
        dg_proofs[RP_H_STORE_TRAITS] == rt_counts[RT_A_TRAITS] &&
        dg_proofs[RP_H_STORE_JOBS] == rt_counts[RT_C_JOBS] &&
        dg_proofs[RP_H_STORE_DECLS] == rt_counts[RT_A_DECLS];
}

// A template's direct call is proved under its caller's declared bounds.
// Closed root calls discharge those assumptions, so the same proof applies
// after substitution. This gate authorizes the direct callee only: it never
// chooses a concrete implementation for a bound-member call.
public bool dg_use_proven(uint use, uint callee, bool root)
{
    if (!dg_proofs_current() || use >= dg_proofs[RP_H_USES]) return false;
    uint at = dg_proofs[RP_H_USE_MAP] + use * RP_USE_WORDS;
    uint call = dg_proofs[at];
    uint status = dg_proofs[at+3u];
    if (call == 0u || call > dg_proofs[RP_H_CALLS] ||
        (root ? status != 1u : (status != 1u && status != 2u))) return false;
    uint count = rt_dir_trait[callee].y;
    uint parent = dg_entry(rt_dir[callee * RT_DIR_WORDS].z);
    if (parent != RT_INVALID) count += rt_dir_trait[parent].y;
    uint first = dg_proofs[at+1u];
    uint total = dg_proofs[RP_H_OBLIGATIONS];
    if (count == 0u || dg_proofs[at+2u] != count || first > total || count > total-first) return false;
    for (uint k = 0u; k < count; k++)
    {
        uint state = dg_proofs[dg_proofs[RP_H_ROUTES] + (first+k)*RP_ROUTE_WORDS];
        if (state != 1u && (root || state != 2u)) return false;
    }
    return true;
}
