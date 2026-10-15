// Solver wave planning on the GPU. The host records many solver rounds per
// submit instead of reading the row counters back after every step
// (dispatch/kernels.rs, SolverWave). At each point where the host loop read
// the counters (dispatch/mod.rs, run_solver_attempt), one thread computes the
// row spans of the next steps from the proof-store directory and the batch
// receipt, exactly as the host computed them from a counter readback
// (dispatch/proof.rs, ProofProgress), and writes each following step's
// dispatch parameters and indirect arguments into its slot. A stopped,
// quiescent, faulted or overflowed solver plans only empty dispatches, so the
// rest of the recorded rounds do nothing.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;

// Solver state, host-initialized every solver attempt.
public RWStructuredBuffer<uint> program_evidence_wave;
// One recorded template's step slots: PSW_SLOT_WORDS words each, the first
// eight bound as that step's ProgramEvidenceParams, then its indirect
// arguments and the host's static description of the step.
public RWStructuredBuffer<uint> program_evidence_wave_slots;
public struct SolverWavePlan
{
    public uint point; public uint slot_first; public uint slot_end; public uint reserved;
}
public ConstantBuffer<SolverWavePlan> program_evidence_wave_plan;

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
public static const uint PSW_SPAN_RECORDS = 32u;  // first, count per span
public static const uint PSW_STATE_WORDS = 64u;

// Slot words.
public static const uint PSW_SLOT_FIRST = 0u;     // ProgramEvidenceParams.dispatch_first
public static const uint PSW_SLOT_COUNT = 1u;     // ProgramEvidenceParams.dispatch_count
public static const uint PSW_SLOT_ARGS = 8u;      // three indirect dispatch words
public static const uint PSW_SLOT_SPAN = 11u;
public static const uint PSW_SLOT_CHUNK = 12u;    // 0: the whole span, c: its chunk c - 1
public static const uint PSW_SLOT_THREADS = 13u;  // 1 or 256
public static const uint PSW_SLOT_LIMIT = 14u;    // rows the template recorded for the span

public static const uint PSW_RUNNING = 0u;
public static const uint PSW_STOPPED = 1u;  // the batch or the store stopped building
public static const uint PSW_DONE = 2u;     // quiescent
public static const uint PSW_FAULT = 3u;
public static const uint PSW_OVERFLOW = 4u; // a span needs more chunk steps than recorded
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

// Spans (dispatch/kernels.rs, WaveSpan).
public static const uint PSW_SPAN_FIRST_WORK = 0u;
public static const uint PSW_SPAN_FIRST_ONE = 1u;
public static const uint PSW_SPAN_WORK = 2u;
public static const uint PSW_SPAN_WORK_ONE = 3u;
public static const uint PSW_SPAN_REQUIREMENTS = 4u;
public static const uint PSW_SPAN_SELECTED_WORK = 5u;
public static const uint PSW_SPAN_BINDINGS = 6u;
public static const uint PSW_SPAN_SELECTED_ONE = 7u;
public static const uint PSW_SPAN_EXPANDED_WORK = 8u;
public static const uint PSW_SPAN_EXPANDED_ONE = 9u;
public static const uint PSW_SPAN_QUEUE = 10u;
public static const uint PSW_SPAN_EMITTED_QUEUE = 11u;
public static const uint PSW_SPAN_PROOF_EDGES = 12u;
public static const uint PSW_SPAN_EMITTED_ONE = 13u;
public static const uint PSW_SPANS = 14u;

void psw_span(uint span, uint first, uint count)
{
    program_evidence_wave[PSW_SPAN_RECORDS + span * 2u] = first;
    program_evidence_wave[PSW_SPAN_RECORDS + span * 2u + 1u] = count;
}
void psw_fault(uint detail)
{
    program_evidence_wave[PSW_FAULT_DETAIL] = detail;
    program_evidence_wave[PSW_STOP] = PSW_FAULT;
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
    if (program_evidence_wave[PSW_STOP] != PSW_RUNNING) return false;
    if (!pps_identity_is_valid()) { psw_fault(PSW_FAULT_IDENTITY); return false; }
    uint receipt; uint serial; uint tail;
    if (!pev_output_read(10u, 0u, 0u, receipt) || !pev_output_read(10u, 0u, 6u, serial) ||
        !pev_output_read(10u, 0u, 7u, tail) || serial != proof_store_params.serial || tail != 0u)
    { psw_fault(PSW_FAULT_RECEIPT); return false; }
    bool layout = true;
    for (uint table = 0u; table < PPS_TABLES; table++)
    {
        uint4 span; uint accepted;
        layout = pps_descriptor(table, span, accepted) && layout;
    }
    if (!layout) { psw_fault(PSW_FAULT_LAYOUT); return false; }
    if (receipt != PEV_BATCH_BUILDING || program_evidence_proof_store[10u] != PPS_BUILDING)
    {
        program_evidence_wave[PSW_STOP] = PSW_STOPPED; return false;
    }
    return true;
}

// The spans of one point: the host loop's decisions between two readbacks.
void psw_plan_spans(uint point)
{
    uint admitted; uint reserved;
    if (point == PSW_POINT_FIRST_WORK)
    {
        if (!psw_running()) return;
        psw_table(PPS_WORK, admitted, reserved);
        psw_span(PSW_SPAN_FIRST_WORK, admitted, reserved - admitted);
        psw_span(PSW_SPAN_FIRST_ONE, 0u, 1u);
        return;
    }
    if (point == PSW_POINT_ROUND)
    {
        // The previous round's queue steps completed.
        if (program_evidence_wave[PSW_QUEUE_ACTIVE] != 0u)
            program_evidence_wave[PSW_QUEUE_CURSOR] =
                program_evidence_wave[PSW_QUEUE_FIRST] + program_evidence_wave[PSW_QUEUE_COUNT];
        program_evidence_wave[PSW_WORK_ACTIVE] = 0u;
        program_evidence_wave[PSW_QUEUE_ACTIVE] = 0u;
        if (!psw_running()) return;
        uint work; uint queue; uint requirements; uint unused;
        psw_table(PPS_WORK, work, unused);
        psw_table(PPS_REDUCTION_QUEUE, queue, unused);
        psw_table(PPS_REQUIREMENTS, requirements, unused);
        uint work_cursor = program_evidence_wave[PSW_WORK_CURSOR];
        uint requirement_cursor = program_evidence_wave[PSW_REQUIREMENT_CURSOR];
        // The previous round's quiescence test, then this round's work.
        if (work_cursor == work && program_evidence_wave[PSW_QUEUE_CURSOR] == queue)
        {
            if (requirement_cursor != requirements) { psw_fault(PSW_FAULT_REQUIREMENTS); return; }
            program_evidence_wave[PSW_STOP] = PSW_DONE; return;
        }
        if (work_cursor > work) { psw_fault(PSW_FAULT_CURSOR); return; }
        if (work_cursor == work) return;
        if (requirement_cursor > requirements) { psw_fault(PSW_FAULT_CURSOR); return; }
        program_evidence_wave[PSW_WORK_ACTIVE] = 1u;
        program_evidence_wave[PSW_WORK_FIRST] = work_cursor;
        program_evidence_wave[PSW_WORK_COUNT] = work - work_cursor;
        program_evidence_wave[PSW_REQUIREMENT_END] = requirements;
        psw_span(PSW_SPAN_WORK, work_cursor, work - work_cursor);
        psw_span(PSW_SPAN_WORK_ONE, 0u, 1u);
        psw_span(PSW_SPAN_REQUIREMENTS, requirement_cursor, requirements - requirement_cursor);
        return;
    }
    uint work_first = program_evidence_wave[PSW_WORK_FIRST];
    uint work_count = program_evidence_wave[PSW_WORK_COUNT];
    bool work_active = program_evidence_wave[PSW_WORK_ACTIVE] != 0u;
    if (point == PSW_POINT_SELECTED)
    {
        if (!work_active || !psw_running()) return;
        program_evidence_wave[PSW_REQUIREMENT_CURSOR] = program_evidence_wave[PSW_REQUIREMENT_END];
        psw_table(PPS_BINDINGS, admitted, reserved);
        psw_span(PSW_SPAN_SELECTED_WORK, work_first, work_count);
        psw_span(PSW_SPAN_BINDINGS, admitted, reserved - admitted);
        psw_span(PSW_SPAN_SELECTED_ONE, 0u, 1u);
        return;
    }
    if (point == PSW_POINT_EXPANDED)
    {
        if (!work_active || !psw_running()) return;
        psw_table(PPS_WORK, admitted, reserved);
        psw_span(PSW_SPAN_EXPANDED_WORK, admitted, reserved - admitted);
        psw_span(PSW_SPAN_EXPANDED_ONE, 0u, 1u);
        return;
    }
    if (point == PSW_POINT_QUEUE)
    {
        // Without work steps nothing ran since the round start, whose
        // counters this decode repeats.
        if (!psw_running()) return;
        if (work_active) program_evidence_wave[PSW_WORK_CURSOR] = work_first + work_count;
        uint queue_cursor = program_evidence_wave[PSW_QUEUE_CURSOR];
        psw_table(PPS_REDUCTION_QUEUE, admitted, reserved);
        if (queue_cursor > admitted) { psw_fault(PSW_FAULT_CURSOR); return; }
        if (queue_cursor == admitted) return;
        program_evidence_wave[PSW_QUEUE_ACTIVE] = 1u;
        program_evidence_wave[PSW_QUEUE_FIRST] = queue_cursor;
        program_evidence_wave[PSW_QUEUE_COUNT] = admitted - queue_cursor;
        psw_span(PSW_SPAN_QUEUE, queue_cursor, admitted - queue_cursor);
        return;
    }
    // PSW_POINT_EMITTED
    if (program_evidence_wave[PSW_QUEUE_ACTIVE] == 0u || !psw_running()) return;
    psw_table(PPS_PROOF_EDGES, admitted, reserved);
    psw_span(PSW_SPAN_EMITTED_QUEUE, program_evidence_wave[PSW_QUEUE_FIRST],
        program_evidence_wave[PSW_QUEUE_COUNT]);
    psw_span(PSW_SPAN_PROOF_EDGES, admitted, reserved - admitted);
    psw_span(PSW_SPAN_EMITTED_ONE, 0u, 1u);
}

// Plans one point, then writes the parameters of every step up to the next
// point. Planning is idempotent at its point: after an overflow the host
// records larger templates and runs the same point again.
public void psw_plan()
{
    uint point = program_evidence_wave_plan.point;
    // Every span of this point is empty unless planned below.
    uint first_span = select(point == PSW_POINT_FIRST_WORK, PSW_SPAN_FIRST_WORK,
        select(point == PSW_POINT_ROUND, PSW_SPAN_WORK,
        select(point == PSW_POINT_SELECTED, PSW_SPAN_SELECTED_WORK,
        select(point == PSW_POINT_EXPANDED, PSW_SPAN_EXPANDED_WORK,
        select(point == PSW_POINT_QUEUE, PSW_SPAN_QUEUE, PSW_SPAN_EMITTED_QUEUE)))));
    uint end_span = select(point == PSW_POINT_FIRST_WORK, PSW_SPAN_WORK,
        select(point == PSW_POINT_ROUND, PSW_SPAN_SELECTED_WORK,
        select(point == PSW_POINT_SELECTED, PSW_SPAN_EXPANDED_WORK,
        select(point == PSW_POINT_EXPANDED, PSW_SPAN_QUEUE,
        select(point == PSW_POINT_QUEUE, PSW_SPAN_EMITTED_QUEUE, PSW_SPANS)))));
    for (uint span = first_span; span < end_span; span++) psw_span(span, 0u, 0u);
    psw_plan_spans(point);

    uint stride = program_evidence_wave[PSW_SLOT_WORDS];
    uint rows = program_evidence_wave[PSW_CHUNK_ROWS];
    uint slot_first = program_evidence_wave_plan.slot_first;
    uint slot_end = program_evidence_wave_plan.slot_end;
    // A span longer than its recorded chunk steps stops here, before any
    // step of this point runs.
    uint overflow = 0u;
    for (uint slot = slot_first; slot < slot_end; slot++)
    {
        uint base = slot * stride;
        uint span = program_evidence_wave_slots[base + PSW_SLOT_SPAN];
        uint count = program_evidence_wave[PSW_SPAN_RECORDS + span * 2u + 1u];
        if (count > program_evidence_wave_slots[base + PSW_SLOT_LIMIT]) overflow = max(overflow, count);
    }
    if (overflow != 0u && program_evidence_wave[PSW_STOP] == PSW_RUNNING)
    {
        program_evidence_wave[PSW_STOP] = PSW_OVERFLOW;
        program_evidence_wave[PSW_OVERFLOW_POINT] = point;
        program_evidence_wave[PSW_OVERFLOW_ROWS] = overflow;
    }
    bool running = program_evidence_wave[PSW_STOP] == PSW_RUNNING;
    if (running && (point == PSW_POINT_ROUND))
        program_evidence_wave[PSW_ROUNDS] += 1u;
    for (uint slot = slot_first; slot < slot_end; slot++)
    {
        uint base = slot * stride;
        uint span = program_evidence_wave_slots[base + PSW_SLOT_SPAN];
        uint chunk = program_evidence_wave_slots[base + PSW_SLOT_CHUNK];
        uint first = program_evidence_wave[PSW_SPAN_RECORDS + span * 2u];
        uint count = select(running, program_evidence_wave[PSW_SPAN_RECORDS + span * 2u + 1u], 0u);
        // Chunk c - 1 of the span, as the host's chunk loop cut it.
        uint skip = select(chunk == 0u, 0u, min((chunk - 1u) * rows, count));
        uint rows_here = select(chunk == 0u, count, min(count - skip, rows));
        uint threads = program_evidence_wave_slots[base + PSW_SLOT_THREADS];
        program_evidence_wave_slots[base + PSW_SLOT_FIRST] = first + skip;
        program_evidence_wave_slots[base + PSW_SLOT_COUNT] = rows_here;
        program_evidence_wave_slots[base + PSW_SLOT_ARGS] = select(threads == 1u, rows_here,
            (rows_here >> 8u) + select((rows_here & 255u) != 0u, 1u, 0u));
        program_evidence_wave_slots[base + PSW_SLOT_ARGS + 1u] = 1u;
        program_evidence_wave_slots[base + PSW_SLOT_ARGS + 2u] = 1u;
    }
}
