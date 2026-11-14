// Solver wave planning on the GPU. The host records many solver rounds per
// submit instead of reading the row counters back after every step
// (dispatch/kernels.rs, SolverWave). At each point where the host loop read
// the counters (dispatch/mod.rs, run_solver_attempt), one thread computes the
// row spans of the next steps from the proof-store directory and the batch
// receipt, exactly as the host computed them from a counter readback
// (dispatch/proof.rs, ProofProgress), and writes each following step's
// dispatch parameters and indirect arguments into its slot. A stopped,
// quiescent, faulted or overflowed solver plans only empty dispatches, so the
// rest of the recorded rounds do nothing. A finish point after the recorded
// rounds runs the round's quiescence test: a quiescent solve publishes its
// roots and the batch receipt there, and otherwise the host records more
// rounds. So a solve that ends within its recorded rounds takes one submit
// and one readback.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_demand;

// Solver state, host-initialized every solver attempt.
public RWStructuredBuffer<uint> trait_solver_wave;
// One recorded template's step slots: PSW_SLOT_WORDS words each, the first
// eight bound as that step's TraitSolverParams, then its indirect
// arguments and the host's static description of the step.
public RWStructuredBuffer<uint> trait_solver_wave_slots;
public struct SolverWavePlan
{
    public uint point; public uint slot_first; public uint slot_end; public uint reserved;
}
public ConstantBuffer<SolverWavePlan> trait_solver_wave_plan;

// State words.
public static const uint PSW_STOP = 0u;           // PSW_RUNNING .. PSW_OVERFLOW
public static const uint PSW_FAULT_DETAIL = 1u;
public static const uint PSW_WORK_CURSOR = 2u;
public static const uint PSW_REQUIREMENT_CURSOR = 3u;
public static const uint PSW_QUEUE_CURSOR = 4u;
public static const uint PSW_WORK_ACTIVE = 5u;    // this round's work steps run
public static const uint PSW_QUEUE_ACTIVE = 6u;   // this round's queue steps run
public static const uint PSW_WORK_FIRST = 7u;
public static const uint PSW_WORK_COUNT = 8u;
public static const uint PSW_REQUIREMENT_END = 9u;
public static const uint PSW_QUEUE_FIRST = 10u;
public static const uint PSW_QUEUE_COUNT = 11u;
public static const uint PSW_ROUNDS = 12u;        // rounds planned with work or queue rows
public static const uint PSW_OVERFLOW_POINT = 13u;
public static const uint PSW_OVERFLOW_ROWS = 14u; // largest span that did not fit
public static const uint PSW_CHUNK_ROWS = 15u;    // host: rows per scratch chunk
public static const uint PSW_SLOT_WORDS = 16u;    // host: slot stride
public static const uint PSW_CALLS_FIRST = 17u;   // host: the batch's new call rows
public static const uint PSW_CALLS_COUNT = 18u;
public static const uint PSW_SPAN_RECORDS = 32u;  // first, count per span
public static const uint PSW_STATE_WORDS = 80u;

// Slot words.
public static const uint PSW_SLOT_FIRST = 0u;     // TraitSolverParams.dispatch_first
public static const uint PSW_SLOT_COUNT = 1u;     // TraitSolverParams.dispatch_count
public static const uint PSW_SLOT_ARGS = 8u;      // three indirect dispatch words
public static const uint PSW_SLOT_SPAN = 11u;
public static const uint PSW_SLOT_CHUNK = 12u;    // 0: the whole span, c: its chunk c - 1
public static const uint PSW_SLOT_THREADS = 13u;  // 1 or 256
public static const uint PSW_SLOT_LIMIT = 14u;    // rows the template recorded for the span

public static const uint PSW_RUNNING = 0u;
public static const uint PSW_STOPPED = 1u;  // the batch or the store stopped building
public static const uint PSW_DONE = 2u;     // quiescent; the finish point published
public static const uint PSW_FAULT = 3u;
public static const uint PSW_OVERFLOW = 4u; // a span needs more chunk steps than recorded
public static const uint PSW_GROW = 5u;     // the next normalization's rows do not fit
// Fault details: dispatch/mod.rs maps each to the host's former error.
public static const uint PSW_FAULT_IDENTITY = 1u;
public static const uint PSW_FAULT_LAYOUT = 2u;
public static const uint PSW_FAULT_RECEIPT = 3u;
public static const uint PSW_FAULT_CURSOR = 4u;
public static const uint PSW_FAULT_REQUIREMENTS = 5u;

// Planning points, in recording order (the host's former readbacks).
public static const uint PSW_POINT_FIRST_WORK = 0u;  // after initial Work
public static const uint PSW_POINT_ROUND = 1u;       // round start: quiescence, work span
public static const uint PSW_POINT_SELECTED = 2u;    // after selection
public static const uint PSW_POINT_EXPANDED = 3u;    // after substitution and expansion
public static const uint PSW_POINT_QUEUE = 4u;       // after work admission: queue span
public static const uint PSW_POINT_EMITTED = 5u;     // after ready-proof emission
public static const uint PSW_POINT_FINISH = 6u;      // after the recorded rounds

// Spans (dispatch/kernels.rs, WaveSpan).
public static const uint PSW_SPAN_FIRST_WORK = 0u;
public static const uint PSW_SPAN_FIRST_ONE = 1u;
public static const uint PSW_SPAN_WORK = 2u;
public static const uint PSW_SPAN_WORK_ONE = 3u;
public static const uint PSW_SPAN_REQUIREMENTS = 4u;
public static const uint PSW_SPAN_ALL_WORK = 5u;      // every admitted Work, for the commit audits
public static const uint PSW_SPAN_SELECTED_WORK = 6u;
public static const uint PSW_SPAN_BINDINGS = 7u;
public static const uint PSW_SPAN_SELECTED_ONE = 8u;
public static const uint PSW_SPAN_SELECTED_ALL_WORK = 9u;
public static const uint PSW_SPAN_EXPANDED_WORK = 10u;
public static const uint PSW_SPAN_EXPANDED_ONE = 11u;
public static const uint PSW_SPAN_QUEUE = 12u;
public static const uint PSW_SPAN_EMITTED_QUEUE = 13u;
public static const uint PSW_SPAN_PROOF_EDGES = 14u;
public static const uint PSW_SPAN_EMITTED_ONE = 15u;
public static const uint PSW_SPAN_FINISH_ROOTS = 16u; // every admitted root, for 64
public static const uint PSW_SPAN_FINISH_CALLS = 17u; // the batch's new calls, for 18
public static const uint PSW_SPAN_FINISH_ONE = 18u;
public static const uint PSW_SPANS = 19u;

void psw_span(uint span, uint first, uint count)
{
    trait_solver_wave[PSW_SPAN_RECORDS + span * 2u] = first;
    trait_solver_wave[PSW_SPAN_RECORDS + span * 2u + 1u] = count;
}
void psw_fault(uint detail)
{
    trait_solver_wave[PSW_FAULT_DETAIL] = detail;
    trait_solver_wave[PSW_STOP] = PSW_FAULT;
}
// A table's admitted prefix and reservation from a valid descriptor.
void psw_table(uint table, out uint admitted, out uint reserved)
{
    uint4 span; uint accepted;
    pps_descriptor(table, span, accepted);
    admitted = span.w; reserved = span.y;
}
// The host's counter decode, then its building test: identity and layout
// failures were host errors, a stopped batch or store returned the progress.
bool psw_running()
{
    if (trait_solver_wave[PSW_STOP] != PSW_RUNNING) return false;
    if (!pps_identity_is_valid()) { psw_fault(PSW_FAULT_IDENTITY); return false; }
    uint receipt; uint serial; uint tail;
    if (!ts_output_read(10u, 0u, 0u, receipt) || !ts_output_read(10u, 0u, 6u, serial) ||
        !ts_output_read(10u, 0u, 7u, tail) || serial != proof_store_params.serial || tail != 0u)
    { psw_fault(PSW_FAULT_RECEIPT); return false; }
    bool layout = true;
    for (uint table = 0u; table < PPS_TABLES; table++)
    {
        uint4 span; uint accepted;
        layout = pps_descriptor(table, span, accepted) && layout;
    }
    if (!layout) { psw_fault(PSW_FAULT_LAYOUT); return false; }
    if (receipt != TS_BATCH_BUILDING || trait_solver_proof_store[10u] != PPS_BUILDING)
    {
        trait_solver_wave[PSW_STOP] = PSW_STOPPED; return false;
    }
    return true;
}

// The stepped host's growth test after a counted Work admission: every
// table must fit the rows the next normalization reserves (proof_demand).
// A fitting count is consumed here; otherwise the host grows the store in
// place, zeroes the count, and this point plans again.
bool psw_demand_fits()
{
    bool fits = true;
    for (uint table = 0u; table < PPS_TABLES; table++)
    {
        uint4 span; uint accepted;
        pps_descriptor(table, span, accepted);
        fits = (trait_solver_proof_demand[table] <= span.z - span.y) && fits;
    }
    if (fits)
        for (uint table = 0u; table < PPS_TABLES; table++) trait_solver_proof_demand[table] = 0u;
    return fits;
}

// The finish of a quiescent solve: root publication (64), call reduction
// (18) and the batch receipt (19), the host's former final submit.
void psw_plan_finish()
{
    trait_solver_wave[PSW_STOP] = PSW_DONE;
    uint admitted; uint reserved;
    psw_table(PPS_ROOT_LINKS, admitted, reserved);
    psw_span(PSW_SPAN_FINISH_ROOTS, 0u, admitted);
    psw_span(PSW_SPAN_FINISH_CALLS, trait_solver_wave[PSW_CALLS_FIRST], trait_solver_wave[PSW_CALLS_COUNT]);
    psw_span(PSW_SPAN_FINISH_ONE, 0u, 1u);
}

// What planning one point decided for psw_plan.
static const uint PSW_PLANNED = 0u;
static const uint PSW_PLANNED_ROUND = 1u;   // a round start with work or queue rows
static const uint PSW_PLANNED_FINISH = 2u;  // this finish point ended the solve

// The spans of one point: the host loop's decisions between two readbacks.
uint psw_plan_spans(uint point)
{
    uint admitted; uint reserved;
    if (point == PSW_POINT_FIRST_WORK)
    {
        if (!psw_running()) return PSW_PLANNED;
        psw_table(PPS_WORK, admitted, reserved);
        psw_span(PSW_SPAN_FIRST_WORK, admitted, reserved - admitted);
        psw_span(PSW_SPAN_FIRST_ONE, 0u, 1u);
        return PSW_PLANNED;
    }
    // A round start and the finish point share the quiescence test. Rounds
    // recorded after quiescence plan nothing; the finish point publishes.
    if (point == PSW_POINT_ROUND || point == PSW_POINT_FINISH)
    {
        // The previous round's queue steps completed.
        if (trait_solver_wave[PSW_QUEUE_ACTIVE] != 0u)
            trait_solver_wave[PSW_QUEUE_CURSOR] =
                trait_solver_wave[PSW_QUEUE_FIRST] + trait_solver_wave[PSW_QUEUE_COUNT];
        trait_solver_wave[PSW_WORK_ACTIVE] = 0u;
        trait_solver_wave[PSW_QUEUE_ACTIVE] = 0u;
        if (!psw_running()) return PSW_PLANNED;
        uint work; uint queue; uint requirements; uint unused;
        psw_table(PPS_WORK, work, unused);
        psw_table(PPS_REDUCTION_QUEUE, queue, unused);
        psw_table(PPS_REQUIREMENTS, requirements, unused);
        uint work_cursor = trait_solver_wave[PSW_WORK_CURSOR];
        uint requirement_cursor = trait_solver_wave[PSW_REQUIREMENT_CURSOR];
        // The previous round's quiescence test, then this round's work.
        if (work_cursor == work && trait_solver_wave[PSW_QUEUE_CURSOR] == queue)
        {
            if (requirement_cursor != requirements) { psw_fault(PSW_FAULT_REQUIREMENTS); return PSW_PLANNED; }
            if (point == PSW_POINT_FINISH) { psw_plan_finish(); return PSW_PLANNED_FINISH; }
            return PSW_PLANNED;
        }
        // Not quiescent: the host records more rounds after this finish.
        if (point == PSW_POINT_FINISH) return PSW_PLANNED;
        if (work_cursor > work) { psw_fault(PSW_FAULT_CURSOR); return PSW_PLANNED; }
        if (work_cursor == work) return PSW_PLANNED_ROUND;
        if (requirement_cursor > requirements) { psw_fault(PSW_FAULT_CURSOR); return PSW_PLANNED; }
        if (!psw_demand_fits())
        {
            trait_solver_wave[PSW_STOP] = PSW_GROW;
            trait_solver_wave[PSW_OVERFLOW_POINT] = PSW_POINT_ROUND;
            trait_solver_wave[PSW_OVERFLOW_ROWS] =
                max(work - work_cursor, requirements - requirement_cursor);
            return PSW_PLANNED;
        }
        trait_solver_wave[PSW_WORK_ACTIVE] = 1u;
        trait_solver_wave[PSW_WORK_FIRST] = work_cursor;
        trait_solver_wave[PSW_WORK_COUNT] = work - work_cursor;
        trait_solver_wave[PSW_REQUIREMENT_END] = requirements;
        psw_span(PSW_SPAN_WORK, work_cursor, work - work_cursor);
        psw_span(PSW_SPAN_WORK_ONE, 0u, 1u);
        psw_span(PSW_SPAN_REQUIREMENTS, requirement_cursor, requirements - requirement_cursor);
        psw_span(PSW_SPAN_ALL_WORK, 0u, work);
        return PSW_PLANNED_ROUND;
    }
    uint work_first = trait_solver_wave[PSW_WORK_FIRST];
    uint work_count = trait_solver_wave[PSW_WORK_COUNT];
    bool work_active = trait_solver_wave[PSW_WORK_ACTIVE] != 0u;
    if (point == PSW_POINT_SELECTED)
    {
        if (!work_active || !psw_running()) return PSW_PLANNED;
        trait_solver_wave[PSW_REQUIREMENT_CURSOR] = trait_solver_wave[PSW_REQUIREMENT_END];
        psw_table(PPS_BINDINGS, admitted, reserved);
        psw_span(PSW_SPAN_SELECTED_WORK, work_first, work_count);
        psw_span(PSW_SPAN_BINDINGS, admitted, reserved - admitted);
        psw_span(PSW_SPAN_SELECTED_ONE, 0u, 1u);
        psw_table(PPS_WORK, admitted, reserved);
        psw_span(PSW_SPAN_SELECTED_ALL_WORK, 0u, admitted);
        return PSW_PLANNED;
    }
    if (point == PSW_POINT_EXPANDED)
    {
        if (!work_active || !psw_running()) return PSW_PLANNED;
        psw_table(PPS_WORK, admitted, reserved);
        psw_span(PSW_SPAN_EXPANDED_WORK, admitted, reserved - admitted);
        psw_span(PSW_SPAN_EXPANDED_ONE, 0u, 1u);
        return PSW_PLANNED;
    }
    if (point == PSW_POINT_QUEUE)
    {
        // Without work steps nothing ran since the round start, whose
        // counters this decode repeats.
        if (!psw_running()) return PSW_PLANNED;
        if (work_active) trait_solver_wave[PSW_WORK_CURSOR] = work_first + work_count;
        uint queue_cursor = trait_solver_wave[PSW_QUEUE_CURSOR];
        psw_table(PPS_REDUCTION_QUEUE, admitted, reserved);
        if (queue_cursor > admitted) { psw_fault(PSW_FAULT_CURSOR); return PSW_PLANNED; }
        if (queue_cursor == admitted) return PSW_PLANNED;
        trait_solver_wave[PSW_QUEUE_ACTIVE] = 1u;
        trait_solver_wave[PSW_QUEUE_FIRST] = queue_cursor;
        trait_solver_wave[PSW_QUEUE_COUNT] = admitted - queue_cursor;
        psw_span(PSW_SPAN_QUEUE, queue_cursor, admitted - queue_cursor);
        return PSW_PLANNED;
    }
    // PSW_POINT_EMITTED
    if (trait_solver_wave[PSW_QUEUE_ACTIVE] == 0u || !psw_running()) return PSW_PLANNED;
    psw_table(PPS_PROOF_EDGES, admitted, reserved);
    psw_span(PSW_SPAN_EMITTED_QUEUE, trait_solver_wave[PSW_QUEUE_FIRST],
        trait_solver_wave[PSW_QUEUE_COUNT]);
    psw_span(PSW_SPAN_PROOF_EDGES, admitted, reserved - admitted);
    psw_span(PSW_SPAN_EMITTED_ONE, 0u, 1u);
    return PSW_PLANNED;
}

// Plans one point, then writes the parameters of every step up to the next
// point. Planning is idempotent at its point: after an overflow the host
// records larger templates and runs the same point again. A finish point
// overflows only while finishing; the host resets the state to running and
// records the finish point again, which repeats the same quiescence test.
public void psw_plan()
{
    uint point = trait_solver_wave_plan.point;
    // Every span of this point is empty unless planned below.
    uint first_span = select(point == PSW_POINT_FIRST_WORK, PSW_SPAN_FIRST_WORK,
        select(point == PSW_POINT_ROUND, PSW_SPAN_WORK,
        select(point == PSW_POINT_SELECTED, PSW_SPAN_SELECTED_WORK,
        select(point == PSW_POINT_EXPANDED, PSW_SPAN_EXPANDED_WORK,
        select(point == PSW_POINT_QUEUE, PSW_SPAN_QUEUE,
        select(point == PSW_POINT_EMITTED, PSW_SPAN_EMITTED_QUEUE, PSW_SPAN_FINISH_ROOTS))))));
    uint end_span = select(point == PSW_POINT_FIRST_WORK, PSW_SPAN_WORK,
        select(point == PSW_POINT_ROUND, PSW_SPAN_SELECTED_WORK,
        select(point == PSW_POINT_SELECTED, PSW_SPAN_EXPANDED_WORK,
        select(point == PSW_POINT_EXPANDED, PSW_SPAN_QUEUE,
        select(point == PSW_POINT_QUEUE, PSW_SPAN_EMITTED_QUEUE,
        select(point == PSW_POINT_EMITTED, PSW_SPAN_FINISH_ROOTS, PSW_SPANS))))));
    for (uint span = first_span; span < end_span; span++) psw_span(span, 0u, 0u);
    uint planned = psw_plan_spans(point);
    // The finish steps run only after the finish point that ended the solve.
    bool finishing = planned == PSW_PLANNED_FINISH;

    uint stride = trait_solver_wave[PSW_SLOT_WORDS];
    uint rows = trait_solver_wave[PSW_CHUNK_ROWS];
    uint slot_first = trait_solver_wave_plan.slot_first;
    uint slot_end = trait_solver_wave_plan.slot_end;
    // A span longer than its recorded chunk steps stops here, before any
    // step of this point runs.
    uint overflow = 0u;
    for (uint slot = slot_first; slot < slot_end; slot++)
    {
        uint base = slot * stride;
        uint span = trait_solver_wave_slots[base + PSW_SLOT_SPAN];
        uint count = trait_solver_wave[PSW_SPAN_RECORDS + span * 2u + 1u];
        if (count > trait_solver_wave_slots[base + PSW_SLOT_LIMIT]) overflow = max(overflow, count);
    }
    if (overflow != 0u && (trait_solver_wave[PSW_STOP] == PSW_RUNNING || finishing))
    {
        trait_solver_wave[PSW_STOP] = PSW_OVERFLOW;
        trait_solver_wave[PSW_OVERFLOW_POINT] = point;
        trait_solver_wave[PSW_OVERFLOW_ROWS] = overflow;
    }
    bool running = trait_solver_wave[PSW_STOP] == PSW_RUNNING ||
        (finishing && trait_solver_wave[PSW_STOP] == PSW_DONE);
    if (running && planned == PSW_PLANNED_ROUND)
        trait_solver_wave[PSW_ROUNDS] += 1u;
    for (uint slot = slot_first; slot < slot_end; slot++)
    {
        uint base = slot * stride;
        uint span = trait_solver_wave_slots[base + PSW_SLOT_SPAN];
        uint chunk = trait_solver_wave_slots[base + PSW_SLOT_CHUNK];
        uint first = trait_solver_wave[PSW_SPAN_RECORDS + span * 2u];
        uint count = select(running, trait_solver_wave[PSW_SPAN_RECORDS + span * 2u + 1u], 0u);
        // Chunk c - 1 of the span, as the host's chunk loop cut it.
        uint skip = select(chunk == 0u, 0u, min((chunk - 1u) * rows, count));
        uint rows_here = select(chunk == 0u, count, min(count - skip, rows));
        uint threads = trait_solver_wave_slots[base + PSW_SLOT_THREADS];
        trait_solver_wave_slots[base + PSW_SLOT_FIRST] = first + skip;
        trait_solver_wave_slots[base + PSW_SLOT_COUNT] = rows_here;
        trait_solver_wave_slots[base + PSW_SLOT_ARGS] = select(threads == 1u, rows_here,
            (rows_here >> 8u) + select((rows_here & 255u) != 0u, 1u, 0u));
        trait_solver_wave_slots[base + PSW_SLOT_ARGS + 1u] = 1u;
        trait_solver_wave_slots[base + PSW_SLOT_ARGS + 2u] = 1u;
    }
}
