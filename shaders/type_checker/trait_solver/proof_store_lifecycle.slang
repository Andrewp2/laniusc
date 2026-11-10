// Serial lifecycle transitions. Dispatch barriers separate initialization,
// frozen-wave validation, admitted-prefix publication, and final acceptance.
// A reserved row and a successful allocation are never proof authority.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.proof_store_abi;

public void pps_store_failure(SolverStatus status)
{
    if (status.state == TS_VALID) return;
    // Even a rejected identity must not produce a successful arena header.
    // This write is independently bounded and cannot touch a table payload.
    if (pps_physical_header()) trait_solver_proof_store[10u] = status.state;
    ts_batch_failure(status);
}

public SolverStatus pps_initialize_store()
{
    if (!ts_batch_is_building()) return ts_invalid(66u, TS_INVALID, TS_INVALID);
    SolverStatus status = pps_admit_layout();
    if (status.state != TS_VALID) return status;
    if (proof_store_params.epoch_low != trait_solver_batch[2u] ||
        proof_store_params.epoch_high != trait_solver_batch[3u] ||
        proof_store_params.serial != trait_solver_batch[4u] ||
        trait_solver_proof_store[10u] != 0u ||
        trait_solver_proof_store[7u] >= proof_store_params.serial ||
        (proof_store_params.epoch_low | proof_store_params.epoch_high) == 0u ||
        (proof_store_params.arena_low | proof_store_params.arena_high) == 0u)
        return ts_invalid(66u, TS_INVALID, TS_INVALID);
    // Upload/growth copies only the latest accepted prefix. A retry cannot
    // turn rows from a failed submission into already-admitted input.
    for (uint table = 0u; table < PPS_PERSISTENT_TABLES; table++)
    {
        uint4 span; uint accepted;
        if (!pps_descriptor(table, span, accepted) || span.y != accepted || span.w != accepted ||
            (trait_solver_proof_store[7u] == 0u && accepted != 0u))
            return ts_invalid(66u, table, TS_INVALID);
    }
    uint4 buckets; uint unused;
    if (!pps_descriptor(PPS_GOAL_BUCKETS, buckets, unused) || buckets.z == TS_INVALID ||
        (buckets.z != 0u && (buckets.z & (buckets.z - 1u)) != 0u))
        return ts_invalid(66u, PPS_GOAL_BUCKETS, TS_INVALID);
    // All layout/identity checks precede any payload mutation. No other stage
    // reads these temporary rows until this dispatch has completed.
    for (uint table = PPS_PERSISTENT_TABLES; table < PPS_TABLES; table++)
    {
        uint base = PPS_DIRECTORY + table * 6u;
        trait_solver_proof_store[base + 1u] = 0u;
        trait_solver_proof_store[base + 3u] = 0u;
        trait_solver_proof_store[base + 4u] = 0u;
    }
    [loop]
    for (uint bucket = 0u; bucket < buckets.z; bucket++)
        trait_solver_proof_store[buckets.x + bucket] = TS_INVALID;
    uint bucket_directory = PPS_DIRECTORY + PPS_GOAL_BUCKETS * 6u;
    trait_solver_proof_store[bucket_directory + 1u] = buckets.z;
    trait_solver_proof_store[bucket_directory + 3u] = buckets.z;
    trait_solver_proof_store[10u] = PPS_BUILDING;
    return ts_ok();
}

// The producer supplies the frozen wave endpoints, never a caller-chosen new
// count. Every row in [expected_admitted,frozen_reserved) must have completed
// its typed validator, with all failures reduced to the sticky batch status.
public SolverStatus pps_check_validated_prefix(uint table, uint expected_admitted, uint frozen_reserved)
{
    uint4 span; uint accepted;
    if (!ts_batch_is_building() || !pps_building() ||
        !pps_descriptor(table, span, accepted) || span.w != expected_admitted || span.y != frozen_reserved)
        return ts_invalid(66u, table, frozen_reserved);
    return ts_ok();
}
public SolverStatus pps_publish_validated_prefix(uint table, uint expected_admitted, uint frozen_reserved)
{
    SolverStatus status = pps_check_validated_prefix(table, expected_admitted, frozen_reserved);
    if (status.state != TS_VALID) return status;
    trait_solver_proof_store[PPS_DIRECTORY + table * 6u + 3u] = frozen_reserved;
    return ts_ok();
}

// Called exactly once after the complete root/call reduction, including empty
// batches. Earlier failure dispatches have already replaced batch BUILDING.
// The host's exact table-row inventory and barriers are part of this protocol.
public SolverStatus pps_accept_submission()
{
    if (!ts_batch_is_building() || !pps_building() ||
        trait_solver_proof_store[7u] >= proof_store_params.serial)
        return ts_invalid(66u, TS_INVALID, TS_INVALID);
    SolverStatus status = pps_admit_layout();
    if (status.state != TS_VALID) return status;
    for (uint table = 0u; table < PPS_PERSISTENT_TABLES; table++)
    {
        uint4 span; uint accepted;
        if (!pps_descriptor(table, span, accepted) || span.y != span.w)
            return ts_invalid(66u, table, TS_INVALID);
    }
    // Preflight the whole closure before publishing any acceptance. Ordinary
    // readers remain behind this serial dispatch's completion barrier.
    for (uint table = 0u; table < PPS_PERSISTENT_TABLES; table++)
    {
        uint base = PPS_DIRECTORY + table * 6u;
        trait_solver_proof_store[base + 4u] = trait_solver_proof_store[base + 3u];
    }
    trait_solver_proof_store[7u] = proof_store_params.serial;
    trait_solver_proof_store[10u] = TS_VALID;
    return ts_ok();
}
