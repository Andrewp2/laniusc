//! The machine round of the desugaring: the rules of
//! docs/state-machines-design.md and the pieces of each machine's text.

use anyhow::Result;

use super::{
    Constants,
    LastRun,
    Round,
    S_F0,
    S_F1,
    S_LIVE,
    SIZE_WORDS,
    constants,
    last_sizes,
    read_words,
};
use crate::{
    compiler::machine_elaboration::{
        closures::Gpu,
        machines::{
            CONSTANTS,
            DETAIL_WORDS,
            INFO_WORDS,
            NO_ERROR,
            REACH_STEPS,
            RECORD_WORDS,
            RuleError,
            STATE_ROW_WORDS,
            STATUS_WORDS,
            rule_error,
        },
    },
    gpu::buffers::LaniusBuffer,
};

const READ: &str = "machines/read";
const MARKS: &str = "machines/marks";
const LISTS: &str = "machines/lists";
const CONTEXT: &str = "machines/context";
const RESOLVE: &str = "machines/resolve";
const ARMS: &str = "machines/arms";
const REACH: &str = "machines/reach";
const STATES: &str = "machines/states";
const PIECES: &str = "machines/pieces";

// Plan modes and the machine layout of shaders/desugar/plan.slang.
const PLAN_MACHINES: u32 = 8;
const PLAN_PIECES: u32 = 9;
const A_TOKENS: u32 = 16;
const A_TOKEN_SCAN: u32 = 17;
const A_TOKEN_SCAN_ONE: u32 = 18;
const A_RECORD_WORDS: u32 = 19;
const A_LIVE: u32 = 20;
const A_LIVE_SCAN: u32 = 21;
const A_LIVE_SCAN_ONE: u32 = 22;
const A_INFO_WORDS: u32 = 23;
const A_STATES: u32 = 24;
const A_STATE_WORDS: u32 = 25;
const A_WRITE: u32 = 26;
const P_TOKENS: u32 = 16;
const P_CLEAR_RECORDS: u32 = 17;
const P_SCAN_TOKENS: u32 = 18;
const P_LIVE: u32 = 21;
const P_LISTS_A: u32 = 22;
const P_LISTS_B: u32 = 23;
const P_SCAN_LIVE: u32 = 24;
const P_CLEAR_INFO: u32 = 27;
const P_CLEAR_STATES: u32 = 28;
const P_RESOLVE: u32 = 29;
const P_CHECK: u32 = 30;
const P_STATES: u32 = 31;
const P_STATE_CHECK: u32 = 32;
const P_COUNT: u32 = 33;
const P_WRITE: u32 = 34;

/// The buffers the rules of the machine round read and wrote, kept for the
/// explanation of a broken rule.
#[derive(Clone)]
pub(super) struct Run {
    slot: usize,
    status: LaniusBuffer<u8>,
    detail: LaniusBuffer<u8>,
    records: LaniusBuffer<u8>,
    scan_a: LaniusBuffer<u8>,
    scan_b: LaniusBuffer<u8>,
    machines: LaniusBuffer<u8>,
    states: LaniusBuffer<u8>,
    arms: LaniusBuffer<u8>,
    variants: LaniusBuffer<u8>,
    machine_info: LaniusBuffer<u8>,
    arm_event: LaniusBuffer<u8>,
    adjacency: LaniusBuffer<u8>,
    reach: LaniusBuffer<u8>,
}

/// The constant strings the machine pieces insert.
pub(super) fn machine_constants(gpu: &Gpu<'_>) -> Constants {
    constants(gpu, "desugar.machines", &CONSTANTS, |_| None)
}

/// The constant strings, for the test of the token table.
#[cfg(test)]
pub(super) fn constant_strings() -> &'static [&'static str] {
    &CONSTANTS
}

/// Records the machine round: the records of the stream, the rules, the
/// pieces of every machine's text and the shared stages.
pub(super) fn record(round: &Round<'_>, encoder: &mut wgpu::CommandEncoder) -> Result<Run> {
    let gpu = round.gpu;
    let bufs = round.bufs;
    let shared = round.shared;
    let rows = round.caps.tokens;
    // A machine or a state takes at least four tokens; the plan checks it.
    let machine_rows = rows / 4 + 1;
    let label = |name: &str| format!("desugar.machines.{name}");
    let storage = |name: &str, rows: usize, words: usize| round.storage(&label(name), rows, words);
    let list = |name: &str| storage(name, rows, 1);

    let records = storage("records", rows, RECORD_WORDS);
    let marks = storage("marks", rows, 4);
    let work_a = round.scan_work(&label("scan_a"), rows);
    let marks_b = storage("marks_b", rows, 4);
    let work_b = round.scan_work(&label("scan_b"), rows);
    let (machines, states, transitions, unused) = (
        list("machines"),
        list("states"),
        list("transitions"),
        storage("unused", 1, 1),
    );
    let (arms, fields, arguments, variants) = (
        list("arms"),
        list("fields"),
        list("arguments"),
        list("variants"),
    );
    let status = gpu.fixed_words_from(&label("status"), &[NO_ERROR; STATUS_WORDS + 1]);
    let detail = storage("detail", DETAIL_WORDS, 1);
    let machine_info = storage("machine_info", machine_rows, INFO_WORDS);
    let arm_event = list("arm_event");
    let adjacency = storage("adjacency", machine_rows, STATE_ROW_WORDS);
    let reach_work = [
        storage("reach.0", machine_rows, STATE_ROW_WORDS),
        storage("reach.1", machine_rows, STATE_ROW_WORDS),
    ];
    let counts = [storage("counts0", rows, 4), storage("counts1", rows, 4)];
    let count_work = [
        round.scan_work(&label("counts0"), rows),
        round.scan_work(&label("counts1"), rows),
    ];
    let constants = machine_constants(gpu);
    let scan_a = &work_a[0];
    let scan_b = &work_b[0];
    let none = &shared.fpieces;

    let lists = |encoder: &mut wgpu::CommandEncoder,
                 params: u32,
                 marks: &LaniusBuffer<u8>,
                 scan: &LaniusBuffer<u8>,
                 out: [&LaniusBuffer<u8>; 4]|
     -> Result<()> {
        round.indirect(
            encoder,
            LISTS,
            &[
                ("gLists", round.block(params)),
                ("marks", marks.as_entire_binding()),
                ("scan", scan.as_entire_binding()),
                ("list_x", out[0].as_entire_binding()),
                ("list_y", out[1].as_entire_binding()),
                ("list_z", out[2].as_entire_binding()),
                ("list_w", out[3].as_entire_binding()),
            ],
            A_LIVE,
        )
    };

    // Records and the numbering of machines, states and transitions.
    round.plan(encoder, super::PLAN_START, [none; 4])?;
    round.clear(encoder, &records, P_CLEAR_RECORDS, A_RECORD_WORDS)?;
    round.indirect(
        encoder,
        READ,
        &[
            ("gRead", round.block(P_TOKENS)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("records", records.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    round.indirect(
        encoder,
        MARKS,
        &[
            ("gMarks", round.block(P_TOKENS)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    round.scan(
        encoder,
        &marks,
        &work_a,
        P_SCAN_TOKENS,
        A_TOKEN_SCAN,
        A_TOKEN_SCAN_ONE,
    )?;

    // The lists, then the rules.
    round.plan(encoder, PLAN_MACHINES, [scan_a, none, none, none])?;
    round.clear(encoder, &machine_info, P_CLEAR_INFO, A_INFO_WORDS)?;
    round.clear(encoder, &adjacency, P_CLEAR_STATES, A_STATE_WORDS)?;
    round.clear(encoder, &arm_event, P_LIVE, A_LIVE)?;
    lists(
        encoder,
        P_LISTS_A,
        &marks,
        scan_a,
        [&machines, &states, &transitions, &unused],
    )?;
    round.indirect(
        encoder,
        CONTEXT,
        &[
            ("gContext", round.block(P_LIVE)),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("transitions", transitions.as_entire_binding()),
            ("marks", marks_b.as_entire_binding()),
        ],
        A_LIVE,
    )?;
    round.scan(
        encoder,
        &marks_b,
        &work_b,
        P_SCAN_LIVE,
        A_LIVE_SCAN,
        A_LIVE_SCAN_ONE,
    )?;
    lists(
        encoder,
        P_LISTS_B,
        &marks_b,
        scan_b,
        [&arms, &fields, &arguments, &variants],
    )?;
    round.indirect(
        encoder,
        RESOLVE,
        &[
            ("gResolve", round.block(P_RESOLVE)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("scan_b", scan_b.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("arms", arms.as_entire_binding()),
            ("machine_info", machine_info.as_entire_binding()),
            ("adjacency", adjacency.as_entire_binding()),
            ("status", status.as_entire_binding()),
            ("detail", detail.as_entire_binding()),
        ],
        A_LIVE,
    )?;
    round.indirect(
        encoder,
        ARMS,
        &[
            ("gArms", round.block(P_CHECK)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("scan_b", scan_b.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("arms", arms.as_entire_binding()),
            ("variants", variants.as_entire_binding()),
            ("machine_info", machine_info.as_entire_binding()),
            ("arm_event", arm_event.as_entire_binding()),
            ("status", status.as_entire_binding()),
            ("detail", detail.as_entire_binding()),
        ],
        A_LIVE,
    )?;
    let mut reach = &adjacency;
    for step in 0..REACH_STEPS {
        let next = &reach_work[step % 2];
        round.indirect(
            encoder,
            REACH,
            &[
                ("gReach", round.block(P_STATES)),
                ("records", records.as_entire_binding()),
                ("scan_a", scan_a.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("rows_in", reach.as_entire_binding()),
                ("rows_out", next.as_entire_binding()),
            ],
            A_STATES,
        )?;
        reach = next;
    }
    round.indirect(
        encoder,
        STATES,
        &[
            ("gStates", round.block(P_STATE_CHECK)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("scan_b", scan_b.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("variants", variants.as_entire_binding()),
            ("machine_info", machine_info.as_entire_binding()),
            ("arm_event", arm_event.as_entire_binding()),
            ("adjacency", adjacency.as_entire_binding()),
            ("reach", reach.as_entire_binding()),
            ("status", status.as_entire_binding()),
            ("detail", detail.as_entire_binding()),
        ],
        A_STATES,
    )?;

    // The pieces of every machine's text.
    let record_pieces = |encoder: &mut wgpu::CommandEncoder, params: u32, triple: u32| {
        round.indirect(
            encoder,
            PIECES,
            &[
                ("gPieces", round.block(params)),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("in_bytes", bufs.in_bytes.as_entire_binding()),
                ("records", records.as_entire_binding()),
                ("scan_a", scan_a.as_entire_binding()),
                ("scan_b", scan_b.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("transitions", transitions.as_entire_binding()),
                ("arms", arms.as_entire_binding()),
                ("fields", fields.as_entire_binding()),
                ("arguments", arguments.as_entire_binding()),
                ("count_scan0", count_work[0][0].as_entire_binding()),
                ("count_scan1", count_work[1][0].as_entire_binding()),
                ("counts0", counts[0].as_entire_binding()),
                ("counts1", counts[1].as_entire_binding()),
                ("pieces", shared.fpieces.as_entire_binding()),
                ("piece_owner", shared.fpiece_owner.as_entire_binding()),
                ("drop", shared.drop.as_entire_binding()),
            ],
            triple,
        )
    };
    record_pieces(encoder, P_COUNT, A_LIVE)?;
    for (counts, work) in counts.iter().zip(&count_work) {
        round.scan(
            encoder,
            counts,
            work,
            P_SCAN_LIVE,
            A_LIVE_SCAN,
            A_LIVE_SCAN_ONE,
        )?;
    }
    round.plan(
        encoder,
        PLAN_PIECES,
        [none, &count_work[0][0], &count_work[1][0], &status],
    )?;
    record_pieces(encoder, P_WRITE, A_WRITE)?;
    round.finish(encoder, &constants)?;

    let reach = reach.clone();
    Ok(Run {
        slot: round.slot,
        status,
        detail,
        records,
        scan_a: scan_a.clone(),
        scan_b: scan_b.clone(),
        machines,
        states,
        arms,
        variants,
        machine_info,
        arm_event,
        adjacency,
        reach,
    })
}

#[derive(encase::ShaderType)]
struct ExplainParams {
    a: u32,
    b: u32,
    word: u32,
    key: u32,
}

/// Runs the rules of the machine round again to write the spans of its
/// first error, and builds the message. `None` when no machine rule failed.
pub(super) fn explain(
    gpu: &Gpu<'_>,
    last: &LastRun,
    run: &Run,
    text: &impl Fn(usize, usize) -> String,
) -> Result<Option<RuleError>> {
    let sizes = last_sizes(last)?;
    let status = read_words(&[(&run.status, 0, STATUS_WORDS)], None)?.remove(0);
    let Some(word) = status.iter().position(|&key| key != NO_ERROR) else {
        return Ok(None);
    };
    let key = status[word];
    let sizes = &sizes[run.slot * SIZE_WORDS..];
    let (live, machine_count, state_count) = (sizes[S_LIVE], sizes[S_F0], sizes[S_F1]);

    let mut encoder = gpu.encoder("desugar.explain");
    let params = |label: &str, a: u32, b: u32| {
        gpu.fixed_uniform(
            label,
            &ExplainParams {
                a,
                b,
                word: word as u32,
                key,
            },
        )
    };
    let resolve_params = params("desugar.explain.resolve", live, machine_count);
    gpu.fixed_dispatch(
        &mut encoder,
        &gpu.kernel(RESOLVE)?,
        RESOLVE,
        &[
            ("gResolve", resolve_params.as_entire_binding()),
            ("tokens_out", last.tokens_out.as_entire_binding()),
            ("token_file_id", last.token_file_id.as_entire_binding()),
            ("in_bytes", last.in_bytes.as_entire_binding()),
            ("records", run.records.as_entire_binding()),
            ("scan_a", run.scan_a.as_entire_binding()),
            ("scan_b", run.scan_b.as_entire_binding()),
            ("machines", run.machines.as_entire_binding()),
            ("states", run.states.as_entire_binding()),
            ("arms", run.arms.as_entire_binding()),
            ("machine_info", run.machine_info.as_entire_binding()),
            ("adjacency", run.adjacency.as_entire_binding()),
            ("status", run.status.as_entire_binding()),
            ("detail", run.detail.as_entire_binding()),
        ],
        live,
    )?;
    let arm_params = params("desugar.explain.arms", live, 0);
    gpu.fixed_dispatch(
        &mut encoder,
        &gpu.kernel(ARMS)?,
        ARMS,
        &[
            ("gArms", arm_params.as_entire_binding()),
            ("tokens_out", last.tokens_out.as_entire_binding()),
            ("in_bytes", last.in_bytes.as_entire_binding()),
            ("records", run.records.as_entire_binding()),
            ("scan_a", run.scan_a.as_entire_binding()),
            ("scan_b", run.scan_b.as_entire_binding()),
            ("machines", run.machines.as_entire_binding()),
            ("states", run.states.as_entire_binding()),
            ("arms", run.arms.as_entire_binding()),
            ("variants", run.variants.as_entire_binding()),
            ("machine_info", run.machine_info.as_entire_binding()),
            ("arm_event", run.arm_event.as_entire_binding()),
            ("status", run.status.as_entire_binding()),
            ("detail", run.detail.as_entire_binding()),
        ],
        live,
    )?;
    if state_count > 0 {
        let state_params = params("desugar.explain.states", state_count, 0);
        gpu.fixed_dispatch(
            &mut encoder,
            &gpu.kernel(STATES)?,
            STATES,
            &[
                ("gStates", state_params.as_entire_binding()),
                ("tokens_out", last.tokens_out.as_entire_binding()),
                ("records", run.records.as_entire_binding()),
                ("scan_a", run.scan_a.as_entire_binding()),
                ("scan_b", run.scan_b.as_entire_binding()),
                ("machines", run.machines.as_entire_binding()),
                ("states", run.states.as_entire_binding()),
                ("variants", run.variants.as_entire_binding()),
                ("machine_info", run.machine_info.as_entire_binding()),
                ("arm_event", run.arm_event.as_entire_binding()),
                ("adjacency", run.adjacency.as_entire_binding()),
                ("reach", run.reach.as_entire_binding()),
                ("status", run.status.as_entire_binding()),
                ("detail", run.detail.as_entire_binding()),
            ],
            state_count,
        )?;
    }
    let detail = read_words(&[(&run.detail, 0, DETAIL_WORDS)], Some(encoder))?.remove(0);
    Ok(Some(rule_error(word, key, &detail, |start, len| {
        text(start as usize, len as usize)
    })))
}
