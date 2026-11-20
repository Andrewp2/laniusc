import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_store_lifecycle;
import type_checker.trait_solver.proof_frontier.proof_work;

// The wave state (proof_work.slang, PSW_*), bound read-only in the lanes.
RWStructuredBuffer<uint> trait_solver_wave_plan;

void psw_launch(uint at, uint groups)
{
    trait_solver_wave_plan[at] = groups;
    trait_solver_wave_plan[at + 1u] = 1u;
    trait_solver_wave_plan[at + 2u] = 1u;
}
uint psw_groups(uint rows, uint width) { return rows / width + (rows % width != 0u ? 1u : 0u); }

// The rows of the next step. The first step reserves the root Works. A
// stopped solver, and one with no row left, launches no lane.
void psw_plan_step()
{
    psw_launch(PSW_LANE_ARGS, 0u);
    trait_solver_wave_plan[PSW_CHUNK_COUNT] = 0u;
    if (trait_solver_wave_plan[PSW_STOP] != PSW_RUNNING || !pps_building() || !ts_batch_is_building())
        return;
    uint4 work; uint accepted;
    if (!pps_descriptor(PPS_WORK, work, accepted))
    { pps_store_failure(ts_invalid(66u, PPS_WORK, TS_INVALID)); return; }
    uint cursor = trait_solver_wave_plan[PSW_CURSOR];
    // The host's root count is a bound when the batch's counts were written
    // on the GPU (a deferred solve). The batch directory has the count.
    uint obligations; uint first = trait_solver_wave_plan[PSW_OBLIGATIONS_FIRST];
    if (!ts_table_count(16u, obligations) || first > obligations)
    { pps_store_failure(ts_invalid(1u, 16u, first)); return; }
    uint roots = min(trait_solver_wave_plan[PSW_ROOTS], obligations - first);
    trait_solver_wave_plan[PSW_ROOTS] = roots;
    uint reserved = work.y;
    if (cursor == 0u && reserved == 0u && roots != 0u)
    {
        if (roots > PPS_LOGICAL_WORK_LIMIT)
        { pps_store_failure(ts_limit(72u, PPS_WORK, roots, PPS_LOGICAL_WORK_LIMIT)); return; }
        if (roots > work.z) { pps_store_failure(ts_limit(69u, PPS_WORK, roots, work.z)); return; }
        trait_solver_proof_store[PPS_DIRECTORY + PPS_WORK * 6u + 1u] = roots;
        reserved = roots;
    }
    if (cursor >= reserved) return;
    uint count = min(reserved - cursor, PSW_CHUNK_ROWS);
    trait_solver_wave_plan[PSW_CHUNK_FIRST] = cursor;
    trait_solver_wave_plan[PSW_CHUNK_COUNT] = count;
    trait_solver_wave_plan[PSW_CURSOR] = cursor + count;
    trait_solver_wave_plan[PSW_STEPS] = trait_solver_wave_plan[PSW_STEPS] + 1u;
    psw_launch(PSW_LANE_ARGS, psw_groups(count, PSW_LANE_GROUP));
}

// After the recorded steps. When every Work ran, the rows of this batch
// become readable to the stages after the solver, and the roots, the call
// reduction and the batch receipt launch. With rows left the state stays
// RUNNING and the host records more steps.
void psw_plan_finish()
{
    psw_launch(PSW_PUBLISH_ARGS, 0u);
    psw_launch(PSW_REDUCE_ARGS, 0u);
    psw_launch(PSW_FINALIZE_ARGS, 0u);
    if (trait_solver_wave_plan[PSW_STOP] != PSW_RUNNING) return;
    uint4 work; uint accepted;
    if (!pps_building() || !ts_batch_is_building() || !pps_descriptor(PPS_WORK, work, accepted))
    { trait_solver_wave_plan[PSW_STOP] = PSW_STOPPED; return; }
    if (trait_solver_wave_plan[PSW_CURSOR] < work.y) return;
    uint publish = psw_groups(trait_solver_wave_plan[PSW_ROOTS], 256u);
    uint reduce = psw_groups(trait_solver_wave_plan[PSW_CALLS_COUNT], 256u);
    if (reduce > 65535u)
    {
        pps_store_failure(ts_limit(72u, 15u, trait_solver_wave_plan[PSW_CALLS_COUNT], 65535u * 256u));
        trait_solver_wave_plan[PSW_STOP] = PSW_STOPPED; return;
    }
    [loop]
    for (uint table = 0u; table < PPS_PERSISTENT_TABLES; table++)
    {
        uint directory = PPS_DIRECTORY + table * 6u;
        trait_solver_proof_store[directory + 3u] = trait_solver_proof_store[directory + 1u];
    }
    psw_launch(PSW_PUBLISH_ARGS, publish);
    psw_launch(PSW_REDUCE_ARGS, reduce);
    psw_launch(PSW_FINALIZE_ARGS, 1u);
    trait_solver_wave_plan[PSW_STOP] = PSW_DONE;
}

// One thread. dispatch_first selects the step plan (0) or the finish (1).
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 80u || proof_store_params.phase != 80u ||
        any(thread_id != uint3(0u))) return;
    if (trait_solver_params.dispatch_first == 0u) psw_plan_step(); else psw_plan_finish();
}
