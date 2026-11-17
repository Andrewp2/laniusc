//! The check of the reserved names before the frontend
//! (docs/state-machines-design.md, R5): the GPU lexer reads the files of one
//! load, and a kernel rejects the `__lanius_` prefix outside the files a
//! rewrite wrote. Machines and generators are desugared by the frontend
//! (crate::compiler::desugar), with the kernels of shaders/machines and the
//! constant strings below.

use anyhow::{Context, Result};

use super::closures::{Gpu, Readback};
use crate::{
    gpu::buffers::LaniusBuffer,
    lexer::{GpuToken, buffers::GpuBuffers, driver::try_global_lexer},
};

/// The strings the kernels insert, in the order of the `C_*` ids in
/// shaders/machines/machine_common.slang.
pub(in crate::compiler) const CONSTANTS: [&str; 77] = [
    "pub ",
    "enum ",
    "State { ",
    "struct ",
    " { ",
    "fn ",
    "_start(",
    "impl ",
    " {\n    ",
    "fn step(&mut self, __lanius_event: ",
    ")",
    " -> ",
    " {\n        ",
    "return match",
    "match",
    " (self.__lanius_state) {\n",
    "    ",
    "fn run(&mut self, __lanius_events: [",
    "], __lanius_count: i32) {\n        let __lanius_at: i32 = 0;\n        while (__lanius_at < __lanius_count) {\n            __lanius_at = match (self.__lanius_state) {\n",
    ": ",
    ", ",
    "(",
    " ",
    "            ",
    "State::",
    " -> { ",
    "return ",
    "self.__lanius_in_",
    "__lanius_event)",
    "; },\n",
    "; return; },\n",
    "    fn __lanius_in_",
    "(&mut self, ",
    "                ",
    " -> self.__lanius_run_",
    "__lanius_events, __lanius_at, __lanius_count),\n",
    "    fn __lanius_run_",
    "__lanius_data_",
    "__lanius_event: ",
    " (__lanius_event) {",
    "__lanius_events: [",
    "], __lanius_from: i32, __lanius_count: i32) -> i32 {\n",
    "        let ",
    " = __lanius_data_",
    ";\n",
    "        let __lanius_at: i32 = __lanius_from;\n        while (__lanius_at < __lanius_count) {\n            let __lanius_event: ",
    " = __lanius_events[__lanius_at];\n            __lanius_at += 1;\n            match (__lanius_event) {",
    "\n            ",
    "_ ",
    "{",
    " let ",
    " = __lanius_event;",
    " }",
    ",",
    "\n        ",
    "};\n    }\n",
    "};\n        }\n        self.__lanius_state = ",
    ";\n        return __lanius_at;\n    }\n",
    "}\n",
    "__lanius_state: ",
    "State }\n",
    ") -> ",
    " { return ",
    " }; }\n",
    "        };\n    }\n    ",
    "fn state(&self) -> ",
    "State { return self.__lanius_state; }\n",
    "            };\n        }\n    }\n",
    "self.__lanius_state = ",
    "; ",
    ";",
    "return;",
    "continue;",
    "; return __lanius_at;",
    " = ",
    "let __lanius_next_",
    " = __lanius_next_",
];

pub(in crate::compiler) const RECORD_WORDS: usize = 6;
pub(in crate::compiler) const NO_ERROR: u32 = u32::MAX;
/// The status words of the machine rules.
pub(in crate::compiler) const STATUS_WORDS: usize = 4;
pub(in crate::compiler) const DETAIL_WORDS: usize = 8;
pub(in crate::compiler) const INFO_WORDS: usize = 3;
pub(in crate::compiler) const STATE_ROW_WORDS: usize = 8;
/// A row of the transition graph has 256 bits, and 2^8 is 256.
pub(in crate::compiler) const REACH_STEPS: usize = 8;

/// File flags: the generator round or the closure pass wrote the file, so
/// it may use the reserved names of that pass.
pub(super) const FILE_GENERATORS: u32 = 1;
pub(super) const FILE_CLOSURES: u32 = 2;

/// A machine the rules reject, as a byte span of one file.
pub(super) struct Invalid {
    pub(super) file: usize,
    pub(super) start: usize,
    pub(super) len: usize,
    pub(super) message: String,
    pub(super) help: Option<String>,
}

pub(super) enum Outcome {
    Invalid(Invalid),
}

#[derive(encase::ShaderType)]
struct Params {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
}

/// The parameters of a kernel that checks rules. `explain` is the status
/// word and key of the error whose spans the kernel writes, or `NO_ERROR`
/// twice in the run that finds the errors.
fn check_params(gpu: &Gpu<'_>, label: &str, a: u32, b: u32, explain: [u32; 2]) -> LaniusBuffer<Params> {
    gpu.uniform(label, &Params { a, b, c: explain[0], d: explain[1] })
}

/// What the lexer's submission leaves for the check: the lexer's buffers and
/// the status words of the rule.
struct Marked {
    tokens: u32,
    tokens_out: LaniusBuffer<GpuToken>,
    token_file_id: LaniusBuffer<u32>,
    in_bytes: LaniusBuffer<u8>,
    file_flags: LaniusBuffer<u32>,
    status: LaniusBuffer<u32>,
    detail: LaniusBuffer<u8>,
    /// The status word, once `mark` records its read.
    reserved: Option<Readback>,
}

/// Checks the reserved names of `sources`, one GPU run for all of them.
/// `flags` holds `FILE_GENERATORS` and `FILE_CLOSURES` per file. `None` when
/// every name is allowed.
pub(super) fn expand(sources: &[&str], flags: &[u32]) -> Result<Option<Outcome>> {
    if sources.iter().all(|source| source.is_empty()) {
        return Ok(None);
    }
    let _run = super::closures::begin_run();
    let lexer = try_global_lexer()?;
    // The check reads the source tokens, so its lex does not desugar.
    crate::compiler::desugar::without_desugaring(|| {
        pollster::block_on(lexer.with_recorded_resident_source_pack_tokens_after_count(
            sources,
            |device, queue, buffers, token_count, encoder, _timer| {
                mark(&Gpu { device, queue }, buffers, encoder, token_count, flags)
            },
            |device, queue, marked| match marked {
                Some(marked) => write(&Gpu { device, queue }, sources, &marked),
                None => Ok(None),
            },
        ))
    })?
}

/// Records the kernel that checks the reserved names, and the read of its
/// status word.
fn mark(
    gpu: &Gpu<'_>,
    lexer: &GpuBuffers,
    encoder: &mut wgpu::CommandEncoder,
    tokens: u32,
    flags: &[u32],
) -> Result<Option<Marked>> {
    if tokens == 0 {
        return Ok(None);
    }
    let status = gpu.words_from("machines.status", &[NO_ERROR; STATUS_WORDS]);
    let detail = gpu.rows("machines.detail", DETAIL_WORDS, 1);
    let file_flags = gpu.words_from("machines.file_flags", flags);
    let check = |reserved| Marked {
        tokens,
        tokens_out: lexer.tokens_out.clone(),
        token_file_id: lexer.token_file_id.clone(),
        in_bytes: lexer.in_bytes.clone(),
        file_flags: file_flags.clone(),
        status: status.clone(),
        detail: detail.clone(),
        reserved,
    };
    record_reserved(gpu, encoder, &check(None), [NO_ERROR; 2])?;
    let reserved = gpu.read(encoder, &status, 0, 1);
    Ok(Some(check(Some(reserved))))
}

/// Records the kernel that checks the reserved names.
fn record_reserved(gpu: &Gpu<'_>, encoder: &mut wgpu::CommandEncoder, marked: &Marked, explain: [u32; 2]) -> Result<()> {
    let reserved_params = check_params(gpu, "machines.reserved.params", marked.tokens, 0, explain);
    gpu.dispatch(
        encoder,
        &gpu.kernel("machines/reserved")?,
        "machines.reserved",
        &[
            ("gReserved", reserved_params.as_entire_binding()),
            ("tokens_out", marked.tokens_out.as_entire_binding()),
            ("token_file_id", marked.token_file_id.as_entire_binding()),
            ("in_bytes", marked.in_bytes.as_entire_binding()),
            ("file_flags", marked.file_flags.as_entire_binding()),
            ("status", marked.status.as_entire_binding()),
            ("detail", marked.detail.as_entire_binding()),
        ],
        marked.tokens,
    )
}

/// The verdict on the reserved names.
fn write(gpu: &Gpu<'_>, sources: &[&str], marked: &Marked) -> Result<Option<Outcome>> {
    let reserved = gpu.words(marked.reserved.as_ref().context("the reserved names were not read")?)?[0];
    if reserved == NO_ERROR {
        return Ok(None);
    }
    let mut encoder = gpu.encoder("machines.explain");
    record_reserved(gpu, &mut encoder, marked, [0, reserved])?;
    explain(gpu, encoder, sources, marked, 0, reserved).map(Some)
}

/// Submits the run that explains the error `key` of status word `word` and
/// builds its message.
fn explain(
    gpu: &Gpu<'_>,
    mut encoder: wgpu::CommandEncoder,
    sources: &[&str],
    marked: &Marked,
    word: usize,
    key: u32,
) -> Result<Outcome> {
    let detail_read = gpu.read(&mut encoder, &marked.detail, 0, DETAIL_WORDS);
    gpu.submit("machines.explain", encoder);
    let detail = gpu.words(&detail_read)?;

    let mut file_starts = Vec::with_capacity(sources.len());
    let mut next = 0usize;
    for source in sources {
        file_starts.push(next);
        next += source.len();
    }
    let file_of = |offset: usize| file_starts.partition_point(|&start| start <= offset).saturating_sub(1);
    let text = |start: u32, len: u32| {
        let file = file_of(start as usize);
        let from = start as usize - file_starts[file];
        sources[file].get(from..from + len as usize).unwrap_or("").to_string()
    };
    let rule = rule_error(word, key, &detail, text);
    let file = file_of(rule.start);
    Ok(Outcome::Invalid(Invalid {
        file,
        start: rule.start - file_starts[file],
        len: rule.len,
        message: rule.message,
        help: rule.help,
    }))
}

/// A broken machine rule: a global byte span and its message.
pub(in crate::compiler) struct RuleError {
    pub(in crate::compiler) start: usize,
    pub(in crate::compiler) len: usize,
    pub(in crate::compiler) message: String,
    pub(in crate::compiler) help: Option<String>,
}

/// The message of the error `key` of status word `word`. The kernels that
/// explain it wrote the spans the message names into `detail`: the token of
/// the error, two more tokens and a number. `text` reads a global span.
pub(in crate::compiler) fn rule_error(
    word: usize,
    key: u32,
    detail: &[u32],
    text: impl Fn(u32, u32) -> String,
) -> RuleError {
    let label = text(detail[0], detail[1]);
    let a = text(detail[2], detail[3]);
    let b = text(detail[4], detail[5]);
    let number = detail[6];
    let mut len = detail[1] as usize;
    let mut help = None;
    let message = match (word, key & 31) {
        (0, _) => "identifiers starting with `__lanius_` are reserved for the compiler".to_string(),
        (1, 1) => "a machine has at most 256 states".to_string(),
        (1, 2) => "expected `{` here".to_string(),
        (1, 3) => format!("state `{label}` is declared twice"),
        (1, 4) => format!("no state is named `{label}`"),
        (1, 5) => "the start state takes no data, so construction never chooses a state".to_string(),
        (1, 6) => {
            // The event type runs to the end of token `a`.
            len = (detail[2] + detail[3] - detail[0]) as usize;
            "a machine's event type is an integer type or an enum declared in the machine's file".to_string()
        }
        (1, 7) => format!(
            "state `{a}` handles the remaining events with `_`; list each event, so adding one makes every state decide what it does"
        ),
        (1, 8) => {
            "a machine arm ends in a transition: `goto State` or `stay`, or a block whose every path does".to_string()
        }
        (1, 9) => "expected `,` after this block arm".to_string(),
        (1, 10) => "a machine arm leaves through `goto` or `stay`, not `return`".to_string(),
        (1, 11) => "expected `;` after this transition".to_string(),
        (1, 12) => "this machine has no output, so its transitions take no `with`".to_string(),
        (1, 13) => "this machine has an output: end the transition with `with value`".to_string(),
        (1, 14) => format!("state `{a}` takes {number} values"),
        (1, 15) => "`goto` and `stay` are the transitions of a machine: write them in the arms of a state".to_string(),
        (1, 16) => "a transition is a statement or the whole body of an arm, and it has no value".to_string(),
        (1, 17) => "expected a field name here".to_string(),
        (2, code @ (1 | 2)) => {
            help = Some(format!("add an arm, e.g. `{a}::{b} -> stay{}`", if code == 2 { " with ..." } else { "" }));
            format!("state `{label}` does not handle `{a}::{b}`")
        }
        (2, _) => format!("state `{label}` must end with a `_` or binding arm, since its events are integers"),
        (3, 1) => format!("state `{label}` is unreachable from `start {a}`"),
        (3, 2) => {
            help = Some(format!("mark it `final state {label}` if the machine is meant to stop here"));
            format!("state `{label}` has no `goto` to another state")
        }
        _ => format!("`final` state `{label}` has a `goto` to another state"),
    };
    RuleError { start: detail[0] as usize, len: len.max(1), message, help }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// What the rules say about `source`: the labeled text, the message and
    /// the help of a rejection.
    fn verdict(source: &str, flags: u32) -> String {
        match expand(&[source], &[flags]).expect("expand") {
            Some(Outcome::Invalid(invalid)) => format!(
                "`{}`: {}{}",
                &source[invalid.start..invalid.start + invalid.len],
                invalid.message,
                invalid.help.map_or(String::new(), |help| format!(" [{help}]"))
            ),
            None => "accepted".to_string(),
        }
    }

    /// The reserved names are checked here; the machine rules are checked
    /// in the token stream (crate::compiler::desugar).
    #[test]
    fn the_reserved_names_are_rejected() {
        let fixture = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/machines/reject_reserved.lani"),
        )
        .expect("read a fixture");
        let expected = "`__lanius_state`: identifiers starting with `__lanius_` are reserved for the compiler";
        assert_eq!(verdict("fn f() { let __lanius_state: i32 = 1; }", 0), expected);
        assert_eq!(verdict(&fixture, 0), expected);
    }

    /// A name with the reserved prefix is accepted in a file a rewrite wrote,
    /// when it is one of the names of that rewrite.
    #[test]
    fn the_names_of_a_rewrite_are_reserved_for_its_files() {
        let reserved = "identifiers starting with `__lanius_` are reserved for the compiler";
        let uses = |name: &str| format!("fn f() -> i32 {{ let {name}: i32 = 1; return {name}; }}\n");
        for (name, flags) in [
            ("__lanius_gen_i", FILE_GENERATORS),
            ("__lanius_closure_3", FILE_CLOSURES),
            ("__lanius_r", FILE_CLOSURES),
            ("__lanius_inst_7", 0),
        ] {
            assert_eq!(verdict(&uses(name), flags), "accepted", "{name}");
        }
        for (name, flags) in [
            ("__lanius_gen_i", 0),
            ("__lanius_gen_i", FILE_CLOSURES),
            ("__lanius_closure_3", FILE_GENERATORS),
            ("__lanius_r", 0),
            ("__lanius_rest", FILE_CLOSURES),
            ("__lanius_state", FILE_GENERATORS | FILE_CLOSURES),
        ] {
            assert_eq!(verdict(&uses(name), flags), format!("`{name}`: {reserved}"), "{name}");
        }
    }
}
