//! `gen fn` (docs/state-machines-design.md, phase M5): a function that
//! suspends at each `yield` is sugar for a `machine`, expanded on the GPU.
//!
//! `gen fn name(params) -> T { body }` becomes, before machines expand,
//!
//! ```text
//! enum NameResume { Next }
//! machine Name on NameResume -> core::option::Option<T> {
//!     params...,                       // fields, read-only in the body
//!     start Start;
//!     state Start { NameResume::Next -> { body from the top } }
//!     state YieldK(locals in scope at the k-th yield) { NameResume::Next -> { body after it } }
//!     final state Done { NameResume::Next -> stay with core::option::None() }
//! }
//! fn name(params) -> Name { return name_start(params); }
//! impl Name { fn next(&mut self) -> core::option::Option<T> { return self.step(NameResume::Next); } }
//! ```
//!
//! In every arm `yield v;` is `goto YieldK(locals) with core::option::Some(v);`
//! and the end of the body, or `return;`, is `goto Done with
//! core::option::None();`. The arm of `YieldK` declares the locals from the
//! state's data, runs the rest of the yield's block, and then the rest of each
//! enclosing statement outward: a `while` around the yield runs again in
//! full. So each state's code is a copy of the body from its point to the
//! next yield, and the machine rules (R2-R5) and proofs apply unchanged.
//!
//! The subset, checked by shaders/generators/check.slang: every local is
//! declared once with a type (`let x: T = e;`), parameters are not assigned,
//! `return` has no value, and a loop that contains a `yield` is a `while`
//! with no `break` or `continue` of its own (the rest of its body after a
//! yield runs outside the loop). `yield` and `return` are not allowed inside
//! a `match`, a `for` or a plain block.
//!
//! The kernels in shaders/generators read the generators from the parse tree
//! of the machine pass. Prefix sums over the tokens give each `yield` its
//! number, its depth and the locals in scope, and one thread per piece of
//! output writes the piece table. The host records the commands, sizes the
//! buffers from the counts the kernels publish, and reads back the text.

use anyhow::{Context, Result, bail};

use super::{
    closures::Gpu,
    machines::{Invalid, Marked, NO_ERROR, Outcome, check_params, params, split_files},
};
use crate::gpu::{
    buffers::{LaniusBuffer, storage_ro_from_bytes, storage_ro_from_u32s},
    passes_core::PassData,
};

/// The strings the kernels insert, in the order of the `GC_*` ids in
/// shaders/generators/generator_common.slang.
const CONSTANTS: [&str; 43] = [
    "",
    "pub ",
    "enum ",
    "Resume { Next }\n",
    "machine ",
    " on ",
    "Resume -> core::option::Option<",
    "> {\n",
    "    ",
    ",\n",
    "    start Start;\n    state Start {\n        ",
    "Resume::Next -> { ",
    "let ",
    " = self.",
    "; ",
    " goto Done with core::option::None(); },\n    }\n",
    "    state Yield",
    "(__lanius_gen_",
    ", __lanius_gen_",
    ") {\n        ",
    " {\n        ",
    "{ ",
    " = __lanius_gen_",
    " } ",
    "    final state Done {\n        ",
    "Resume::Next -> stay with core::option::None(),\n    }\n}\n",
    "fn ",
    "(",
    ", ",
    ") -> ",
    " { return ",
    "_start(",
    "); }\n",
    "impl ",
    " {\n    ",
    "fn next(&mut self) -> core::option::Option<",
    "> { return self.step(",
    "Resume::Next); }\n}\n",
    "goto Yield",
    ") with core::option::Some(",
    " with core::option::Some(",
    ")",
    "goto Done with core::option::None()",
];

const RECORD_WORDS: usize = 7;
const DETAIL_WORDS: usize = 4;

/// Records the kernel that writes each marked token into its two lists.
fn lists(
    gpu: &Gpu<'_>,
    encoder: &mut wgpu::CommandEncoder,
    kernel: &PassData,
    tokens: u32,
    marks: &LaniusBuffer<u8>,
    scan: &LaniusBuffer<u8>,
    label: &str,
) -> Result<[LaniusBuffer<u8>; 2]> {
    let rows = tokens as usize;
    let out = [gpu.rows(label, rows, 1), gpu.rows(label, rows, 1)];
    let list_params = params(gpu, "generators.lists.params", tokens, 0);
    gpu.dispatch(
        encoder,
        kernel,
        "generators.lists",
        &[
            ("gLists", list_params.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
            ("scan", scan.as_entire_binding()),
            ("list_x", out[0].as_entire_binding()),
            ("list_y", out[1].as_entire_binding()),
        ],
        tokens,
    )?;
    Ok(out)
}

/// Rewrites the generators of the pack `marked` holds into machines.
pub(super) fn expand(gpu: &Gpu<'_>, sources: &[&str], marked: &Marked) -> Result<Option<Outcome>> {
    let tokens = marked.tokens;
    let rows = tokens as usize;
    let tree = &marked.tree;
    let scan_kernel = gpu.kernel("closures/scan")?;
    let list_kernel = gpu.kernel("generators/lists")?;
    let piece_kernel = gpu.kernel("generators/pieces")?;
    let check_kernel = gpu.kernel("generators/check")?;
    let (const_index, const_bytes) = constant_table(gpu.device);

    let records = gpu.rows("generators.records", rows * RECORD_WORDS, 1);
    let file_option = gpu.rows("generators.file_option", sources.len(), 1);
    let marks1 = gpu.rows("generators.marks", rows, 4);
    let work1 = [gpu.rows("generators.scan1.a", rows, 4), gpu.rows("generators.scan1.b", rows, 4)];
    let direct = gpu.rows("generators.direct", rows, 1);
    let marks2 = gpu.rows("generators.context", rows, 4);
    let work2 = [gpu.rows("generators.scan2.a", rows, 4), gpu.rows("generators.scan2.b", rows, 4)];
    let marks3 = gpu.rows("generators.counts", rows, 4);
    let work3 = [gpu.rows("generators.scan3.a", rows, 4), gpu.rows("generators.scan3.b", rows, 4)];
    let counts = gpu.rows("generators.piece_counts", rows, 4);
    let count_work = [gpu.rows("generators.piece_counts.a", rows, 4), gpu.rows("generators.piece_counts.b", rows, 4)];
    let status = storage_ro_from_u32s(gpu.device, "generators.status", &[NO_ERROR]);
    let detail = gpu.rows("generators.detail", DETAIL_WORDS, 1);
    let nothing = [
        gpu.rows("generators.no_scope", 1, 1),
        gpu.rows("generators.no_pieces", 1, 4),
        gpu.rows("generators.no_sources", 1, 4),
    ];

    // The records, then the generators and yields with their depths.
    let mut encoder = gpu.encoder("generators.count");
    let node_params = params(gpu, "generators.nodes.params", tree.capacity, tokens);
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("generators/nodes")?,
        "generators.nodes",
        &[
            ("gNodes", node_params.as_entire_binding()),
            ("tree_count_status", tree.status.as_entire_binding()),
            ("node_kind", tree.node_kind.as_entire_binding()),
            ("parent", tree.parent.as_entire_binding()),
            ("first_child", tree.first_child.as_entire_binding()),
            ("next_sibling", tree.next_sibling.as_entire_binding()),
            ("hir_token_pos", tree.hir_token_pos.as_entire_binding()),
            ("hir_token_end", tree.hir_token_end.as_entire_binding()),
            ("semantic_token_kinds", marked.semantic_token_kinds.as_entire_binding()),
            ("records", records.as_entire_binding()),
        ],
        tree.capacity,
    )?;
    let token_params = params(gpu, "generators.token.params", tokens, 0);
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("generators/marks")?,
        "generators.marks",
        &[
            ("gMarks", token_params.as_entire_binding()),
            ("tokens_out", marked.tokens_out.as_entire_binding()),
            ("token_file_id", marked.token_file_id.as_entire_binding()),
            ("in_bytes", marked.in_bytes.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("marks", marks1.as_entire_binding()),
            ("file_option", file_option.as_entire_binding()),
        ],
        tokens,
    )?;
    let scan1 = gpu.scan(&mut encoder, &scan_kernel, &marks1, &work1, tokens)?;
    let [gens, yields] = lists(gpu, &mut encoder, &list_kernel, tokens, &marks1, scan1, "generators.lists.a")?;

    // The parameters and locals, and the locals in scope at each token.
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("generators/direct")?,
        "generators.direct",
        &[
            ("gDirect", token_params.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", marked.scan.as_entire_binding()),
            ("scan1", scan1.as_entire_binding()),
            ("gens", gens.as_entire_binding()),
            ("direct", direct.as_entire_binding()),
        ],
        tokens,
    )?;
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("generators/context")?,
        "generators.context",
        &[
            ("gContext", token_params.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", marked.scan.as_entire_binding()),
            ("scan1", scan1.as_entire_binding()),
            ("gens", gens.as_entire_binding()),
            ("direct", direct.as_entire_binding()),
            ("marks", marks2.as_entire_binding()),
        ],
        tokens,
    )?;
    let scan2 = gpu.scan(&mut encoder, &scan_kernel, &marks2, &work2, tokens)?;
    let [param_list, lets] = lists(gpu, &mut encoder, &list_kernel, tokens, &marks2, scan2, "generators.lists.b")?;

    // The rules. The kernel runs again to explain an error, with the same
    // buffers: every write of the first run repeats its value.
    let record_check = |encoder: &mut wgpu::CommandEncoder, explain: [u32; 2]| -> Result<()> {
        let rule_params = check_params(gpu, "generators.check.params", tokens, 0, explain);
        gpu.dispatch(
            encoder,
            &check_kernel,
            "generators.check",
            &[
                ("gCheck", rule_params.as_entire_binding()),
                ("tokens_out", marked.tokens_out.as_entire_binding()),
                ("token_file_id", marked.token_file_id.as_entire_binding()),
                ("in_bytes", marked.in_bytes.as_entire_binding()),
                ("records", records.as_entire_binding()),
                ("scan_a", marked.scan.as_entire_binding()),
                ("scan1", scan1.as_entire_binding()),
                ("scan2", scan2.as_entire_binding()),
                ("gens", gens.as_entire_binding()),
                ("params", param_list.as_entire_binding()),
                ("lets", lets.as_entire_binding()),
                ("file_option", file_option.as_entire_binding()),
                ("marks", marks3.as_entire_binding()),
                ("status", status.as_entire_binding()),
                ("detail", detail.as_entire_binding()),
            ],
            tokens,
        )
    };
    record_check(&mut encoder, [NO_ERROR; 2])?;
    let scan3 = gpu.scan(&mut encoder, &scan_kernel, &marks3, &work3, tokens)?;

    let record_pieces = |encoder: &mut wgpu::CommandEncoder,
                         shape: [u32; 3],
                         count_scan: &LaniusBuffer<u8>,
                         scope: &LaniusBuffer<u8>,
                         pieces: &LaniusBuffer<u8>,
                         piece_sources: &LaniusBuffer<u8>,
                         threads: u32| {
        let [write, piece_count, gen_count] = shape;
        let piece_params = check_params(gpu, "generators.pieces.params", tokens, write, [piece_count, gen_count]);
        gpu.dispatch(
            encoder,
            &piece_kernel,
            "generators.pieces",
            &[
                ("gPieces", piece_params.as_entire_binding()),
                ("tokens_out", marked.tokens_out.as_entire_binding()),
                ("token_file_id", marked.token_file_id.as_entire_binding()),
                ("in_bytes", marked.in_bytes.as_entire_binding()),
                ("source_file_start", marked.source_file_start.as_entire_binding()),
                ("source_file_len", marked.source_file_len.as_entire_binding()),
                ("records", records.as_entire_binding()),
                ("scan1", scan1.as_entire_binding()),
                ("scan2", scan2.as_entire_binding()),
                ("scan3", scan3.as_entire_binding()),
                ("gens", gens.as_entire_binding()),
                ("params", param_list.as_entire_binding()),
                ("scope", scope.as_entire_binding()),
                ("const_index", const_index.as_entire_binding()),
                ("count_scan", count_scan.as_entire_binding()),
                ("counts", counts.as_entire_binding()),
                ("pieces", pieces.as_entire_binding()),
                ("piece_sources", piece_sources.as_entire_binding()),
            ],
            threads,
        )
    };
    // The counting run reads no prefix sums of the counts and no scopes: it
    // binds the buffer the sums are written to afterwards.
    record_pieces(&mut encoder, [0; 3], &count_work[0], &nothing[0], &nothing[1], &nothing[2], tokens)?;
    let count_scan = gpu.scan(&mut encoder, &scan_kernel, &counts, &count_work, tokens)?;
    let status_read = gpu.read(&mut encoder, &status, 0, 1);
    let totals1 = gpu.read(&mut encoder, scan1, (rows - 1) * 4, 4);
    let totals3 = gpu.read(&mut encoder, scan3, (rows - 1) * 4, 4);
    let piece_total = gpu.read(&mut encoder, count_scan, (rows - 1) * 4, 4);
    gpu.submit("generators.count", encoder);

    let key = gpu.words(&status_read)?[0];
    if key != NO_ERROR {
        let mut encoder = gpu.encoder("generators.explain");
        record_check(&mut encoder, [0, key])?;
        let detail_read = gpu.read(&mut encoder, &detail, 0, DETAIL_WORDS);
        gpu.submit("generators.explain", encoder);
        return Ok(Some(Outcome::Invalid(invalid(sources, key, &gpu.words(&detail_read)?))));
    }
    let gen_count = gpu.words(&totals1)?[0];
    let (slot_count, pair_count) = {
        let totals = gpu.words(&totals3)?;
        (totals[0], totals[1])
    };
    let piece_count = gpu.words(&piece_total)?[0];
    if gen_count == 0 || piece_count == 0 {
        bail!("the pack has a `gen` or `yield` token and no generator");
    }

    // The locals in scope at each yield, then the pieces and their lengths.
    let pieces_len = piece_count as usize;
    let scope = gpu.rows("generators.scope", slot_count as usize, 1);
    let pieces = gpu.rows("generators.pieces", pieces_len, 4);
    let piece_sources = gpu.rows("generators.piece_sources", pieces_len, 4);
    let piece_work = [gpu.rows("generators.pieces.a", pieces_len, 4), gpu.rows("generators.pieces.b", pieces_len, 4)];
    let mut encoder = gpu.encoder("generators.pieces");
    if pair_count != 0 {
        let scope_params = params(gpu, "generators.scope.params", tokens, pair_count);
        gpu.dispatch(
            &mut encoder,
            &gpu.kernel("generators/scope")?,
            "generators.scope",
            &[
                ("gScope", scope_params.as_entire_binding()),
                ("scan1", scan1.as_entire_binding()),
                ("scan2", scan2.as_entire_binding()),
                ("scan3", scan3.as_entire_binding()),
                ("yields", yields.as_entire_binding()),
                ("scope", scope.as_entire_binding()),
            ],
            pair_count,
        )?;
    }
    record_pieces(&mut encoder, [1, piece_count, gen_count], count_scan, &scope, &pieces, &piece_sources, piece_count)?;
    let piece_scan = gpu.scan(&mut encoder, &scan_kernel, &pieces, &piece_work, piece_count)?;
    let pieces_read = gpu.read(&mut encoder, &pieces, 0, pieces_len * 4);
    let piece_scan_read = gpu.read(&mut encoder, piece_scan, 0, pieces_len * 4);
    let piece_sources_read = gpu.read(&mut encoder, &piece_sources, 0, pieces_len * 4);
    gpu.submit("generators.pieces", encoder);
    let piece_rows = gpu.words(&pieces_read)?;
    let piece_ends = gpu.words(&piece_scan_read)?;
    let piece_anchors = gpu.words(&piece_sources_read)?;
    let out_len = piece_ends[(pieces_len - 1) * 4];

    // The rewritten bytes.
    let out_words = (out_len as usize).div_ceil(4);
    let output = gpu.rows("generators.output", out_words, 1);
    let emit_params = params(gpu, "generators.emit.params", out_len, piece_count);
    let mut encoder = gpu.encoder("generators.emit");
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("generators/emit")?,
        "generators.emit",
        &[
            ("gEmit", emit_params.as_entire_binding()),
            ("in_bytes", marked.in_bytes.as_entire_binding()),
            ("tokens_out", marked.tokens_out.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
            ("piece_scan", piece_scan.as_entire_binding()),
            ("const_index", const_index.as_entire_binding()),
            ("const_bytes", const_bytes.as_entire_binding()),
            ("out_words", output.as_entire_binding()),
        ],
        u32::try_from(out_words.max(1)).context("rewritten source is too large")?,
    )?;
    let output_read = gpu.read(&mut encoder, &output, 0, out_words);
    gpu.submit("generators.emit", encoder);
    let mut bytes: Vec<u8> = gpu.words(&output_read)?.into_iter().flat_map(u32::to_le_bytes).collect();
    bytes.truncate(out_len as usize);

    split_files(sources, &piece_rows, &piece_ends, &piece_anchors, &bytes).map(|files| Some(Outcome::Generators(files)))
}

/// The message of the error `key`. The kernel wrote the spans the message
/// names: the token of the error and one more token.
fn invalid(sources: &[&str], key: u32, detail: &[u32]) -> Invalid {
    let mut file_starts = Vec::with_capacity(sources.len());
    let mut next = 0usize;
    for source in sources {
        file_starts.push(next);
        next += source.len();
    }
    let file = file_starts.partition_point(|&start| start <= detail[0] as usize).saturating_sub(1);
    let start = detail[0] as usize - file_starts[file];
    let label = sources[file].get(start..start + detail[1] as usize).unwrap_or("");
    let message = match key & 31 {
        1 => "`yield` is a statement of a generator: write it in a `gen fn`".to_string(),
        2 => "a generator yields and returns only in its body's own statements, `if` and `while`, not inside a `match`, `for` or plain block".to_string(),
        3 => "a generator's locals declare their type: `let name: Type = value;`".to_string(),
        4 => format!("a generator declares each local once; `{label}` is declared again here"),
        5 => "a loop that yields has no `break` or `continue`: the code after a yield runs outside the loop".to_string(),
        6 => "a generator's `return` takes no value; it ends the sequence".to_string(),
        7 => "a generator declares the type it yields: `gen fn name(...) -> T`".to_string(),
        8 => "a generator's parameters are read-only; copy one into a local to change it".to_string(),
        9 => "a file with a `gen fn` imports `core::option`: its `next` returns `core::option::Option`".to_string(),
        _ => "a generator has no type parameters, `where` clause or contracts".to_string(),
    };
    Invalid { file, start, len: (detail[1] as usize).max(1), message, help: None }
}

fn constant_table(device: &wgpu::Device) -> (LaniusBuffer<u32>, LaniusBuffer<u8>) {
    let mut index = Vec::with_capacity(CONSTANTS.len() * 2);
    let mut bytes = Vec::new();
    for text in CONSTANTS {
        index.extend([bytes.len() as u32, text.len() as u32]);
        bytes.extend_from_slice(text.as_bytes());
    }
    bytes.resize(bytes.len().next_multiple_of(4), 0);
    let count = bytes.len();
    (
        storage_ro_from_u32s(device, "generators.const_index", &index),
        storage_ro_from_bytes(device, "generators.const_bytes", &bytes, count),
    )
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::super::{CompileError, elaborate_source, machines};

    const EVENS: &str = "import core::option;
gen fn evens(limit: i32) -> i32 {
    let i: i32 = 0;
    while (i < limit) {
        yield i;
        i += 2;
    }
}
";

    /// The machines the generators of `source` become.
    fn machines_of(source: &str) -> String {
        match machines::expand(&[source], &[0]).unwrap() {
            Some(machines::Outcome::Generators(mut files)) => files.remove(0).expect("the file has a generator").text,
            Some(machines::Outcome::Invalid(invalid)) => panic!("{}", invalid.message),
            _ => panic!("the pass found no generator"),
        }
    }

    fn rejected(source: &str) -> String {
        match elaborate_source(Path::new("evens.lani"), source.to_string()) {
            Err(CompileError::Diagnostic(diagnostic)) => format!("{diagnostic:?}"),
            other => panic!("expected a generator diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn a_generator_is_a_machine_with_one_state_per_yield() {
        let text = machines_of(EVENS);
        assert!(text.starts_with("import core::option;\nenum EvensResume { Next }\n"), "{text}");
        assert!(text.contains("machine Evens on EvensResume -> core::option::Option<i32> {"), "{text}");
        assert!(text.contains("    limit: i32,\n    start Start;"), "{text}");
        assert!(text.contains("goto Yield0(i) with core::option::Some(i);"), "{text}");
        assert!(text.contains("state Yield0(__lanius_gen_i: i32) {"), "{text}");
        assert!(text.contains("let i: i32 = __lanius_gen_i; { i += 2; } while (i < limit) {"), "{text}");
        assert!(text.contains("fn evens(limit: i32) -> Evens { return evens_start(limit); }"), "{text}");
        assert!(text.contains("fn next(&mut self) -> core::option::Option<i32> { return self.step(EvensResume::Next); }"), "{text}");
        assert!(text.ends_with("Resume::Next); }\n}\n\n"), "{text}");
        // The machine rules accept the result.
        let outcome = machines::expand(&[text.as_str()], &[machines::FILE_GENERATORS]).unwrap();
        assert!(matches!(outcome, Some(machines::Outcome::Expanded(files)) if files[0].is_some()));
    }

    /// Two generators in one file, and one in a second file: each keeps the
    /// text around it, and a yield's state holds the locals of every block
    /// around it.
    #[test]
    fn generators_keep_the_text_around_them() {
        let cells = "import core::option;

fn before() -> i32 { return 1; }

pub gen fn grid_cells(rows: i32, cols: i32) -> i32 {
    let r: i32 = 0;
    while (r < rows) {
        let c: i32 = 0;
        if (r == 3) { return; } else { yield 0 - 1; }
        while (c < cols) {
            yield r * 10 + c;
            c += 1;
        }
        r += 1;
    }
    yield 999;
}

fn between() -> i32 { return 2; }

gen fn once() -> bool {
    yield true;
}

fn after() -> i32 { return 3; }
";
        let outputs = match machines::expand(&[cells, "fn plain() -> i32 { return 0; }\n", EVENS], &[0, 0, 0]).unwrap() {
            Some(machines::Outcome::Generators(files)) => files,
            _ => panic!("the pass found no generator"),
        };
        assert!(outputs[1].is_none());
        assert!(outputs[2].as_ref().is_some_and(|output| output.text.contains("machine Evens on")));
        let text = &outputs[0].as_ref().expect("the first file has generators").text;
        for kept in ["fn before() -> i32 { return 1; }", "fn between() -> i32 { return 2; }", "fn after() -> i32 { return 3; }\n"] {
            assert_eq!(text.matches(kept).count(), 1, "{text}");
        }
        assert!(text.contains("pub enum GridCellsResume { Next }\npub machine GridCells on GridCellsResume"), "{text}");
        assert!(text.contains("pub fn grid_cells(rows: i32, cols: i32) -> GridCells { return grid_cells_start(rows, cols); }"), "{text}");
        assert!(text.contains("pub impl GridCells {\n    pub fn next(&mut self)"), "{text}");
        assert!(text.contains("if (r == 3) { goto Done with core::option::None(); } else { goto Yield0(r, c) with core::option::Some(0 - 1); }"), "{text}");
        assert!(text.contains("state Yield1(__lanius_gen_r: i32, __lanius_gen_c: i32) {"), "{text}");
        assert!(text.contains("let r: i32 = __lanius_gen_r; { let c: i32 = __lanius_gen_c; { c += 1; } while (c < cols) {"), "{text}");
        assert!(text.contains("state Yield2(__lanius_gen_r: i32) {"), "{text}");
        assert!(text.contains("goto Yield2(r) with core::option::Some(999);"), "{text}");
        assert!(text.contains("state Yield0 {\n        OnceResume::Next -> {  goto Done"), "{text}");
        let outcome = machines::expand(&[text.as_str()], &[machines::FILE_GENERATORS]).unwrap();
        assert!(matches!(outcome, Some(machines::Outcome::Expanded(files)) if files[0].is_some()));
    }

    #[test]
    fn generators_stay_in_their_subset() {
        assert!(rejected(&EVENS.replace("i += 2;", "limit = 1;")).contains("parameters are read-only"));
        assert!(rejected(&EVENS.replace("i += 2;", "i += 2; break;")).contains("no `break` or `continue`"));
        assert!(rejected(&EVENS.replace("let i: i32 = 0;", "let i = 0;")).contains("declare their type"));
        assert!(rejected(&EVENS.replace("yield i;", "{ yield i; }")).contains("not inside a `match`, `for` or plain block"));
        assert!(rejected(&EVENS.replace("import core::option;\n", "")).contains("imports `core::option`"));
        assert!(rejected(&EVENS.replace("i += 2;", "let i: i32 = 1;")).contains("`i` is declared again"));
        assert!(rejected(&EVENS.replace("i += 2;", "return 3;")).contains("takes no value"));
        assert!(rejected(&EVENS.replace("-> i32 {", "{")).contains("declares the type it yields"));
        let outside = "fn main() -> i32 {\n    yield 1;\n    return 0;\n}\n";
        let text = rejected(outside);
        assert!(text.contains("write it in a `gen fn`"), "{text}");
        assert!(text.contains("line: 2"), "{text}");
    }
}
