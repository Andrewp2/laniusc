// src/bin/parse_gen_tables/main.rs
// Offline generator for the LLP "3 data structures / 7 arrays".
// Reads a simple grammar file and writes tables/parse_tables.bin plus metadata.
//
// Current behavior:
//   * Parses production lines and a `%start NonTerminal;` directive.
//   * Resolves quoted terminal names to lexer TokenKind discriminants.
//   * Validates the grammar boundary before table generation.
//   * Emits Pareas-style LLP(1, 1) stack-change and partial-parse tables.
//   * Emits LL(1) runtime tables while the GPU replay path remains available for
//     cross-checking and diagnostics.
//
// Grammar line examples:
//   %start expr;
//   expr                -> atom sum;
//   sum [sum_add]       -> 'InfixPlus' atom sum;
//   sum [sum_end]       -> ;
//   atom [atom_paren]   -> 'GroupLParen' expr 'GroupRParen';
//
// Notes:
//   - Terminals appear as single-quoted TokenKind names.
//   - Nonterminals are bare identifiers.
//   - Tags are accepted in the grammar syntax and define stable production IDs.

use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque},
    env,
    fs,
    path::PathBuf,
};

use anyhow::{Context, Result, anyhow, bail};
use laniusc_compiler::{
    lexer::tables::tokens::{N_KINDS, TokenKind},
    parser::tables::{
        INVALID_TABLE_ENTRY,
        PrecomputedParseTables,
        build_mvp_precomputed_tables,
        encode_pop,
        encode_push,
    },
};
use serde::Serialize;

mod analysis;
mod grammar;
mod llp;
mod output;

use analysis::*;
use grammar::*;
use llp::*;
use output::*;

const DEFAULT_LOOKBACK: u32 = 1;
const DEFAULT_LOOKAHEAD: u32 = 1;
const EOF_TOKEN: u32 = 0;

#[derive(Debug, Clone)]
struct GrammarSpec {
    start: String,
    productions: Vec<Production>,
}

#[derive(Debug, Clone)]
struct Production {
    line: usize,
    lhs: String,
    tag: String,
    rhs_syms: Vec<Sym>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
enum Sym {
    Terminal(u32),
    NonTerminal(String),
}

#[derive(Debug, Default)]
struct GrammarAnalysis {
    nullable: BTreeSet<String>,
    first: BTreeMap<String, BTreeSet<u32>>,
    follow: BTreeMap<String, BTreeSet<u32>>,
    diagnostics: GrammarDiagnostics,
}

#[derive(Debug, Clone, Default, Serialize)]
struct GrammarDiagnostics {
    undefined_nonterminals: Vec<String>,
    unreachable_nonterminals: Vec<String>,
    left_recursions: Vec<String>,
    ll1_conflicts: Vec<String>,
}

#[derive(Serialize)]
struct ParseTablesMeta {
    grammar: String,
    start: String,
    lookback: u32,
    lookahead: u32,
    diagnostics: GrammarDiagnostics,
    stack_change_table: PairTableMeta,
    partial_parse_table: PairTableMeta,
    ll1_runtime: Ll1RuntimeMeta,
    ll1_predictions: Vec<PredictionMeta>,
    productions: Vec<ProductionMeta>,
}

#[derive(Serialize)]
struct PredictionMeta {
    nonterminal: String,
    lookahead: String,
    lookahead_id: u32,
    production: u32,
}

#[derive(Debug, Clone)]
struct Prediction {
    nonterminal: String,
    lookahead: u32,
    production: u32,
}

#[derive(Serialize)]
struct ProductionMeta {
    id: u32,
    line: usize,
    lhs: String,
    tag: String,
    arity: u32,
    rhs: Vec<String>,
}

#[derive(Serialize)]
struct Ll1RuntimeMeta {
    nonterminals: usize,
    start_nonterminal: String,
    predict_cells: usize,
    rhs_symbols: usize,
}

#[derive(Debug, Default, Serialize)]
struct PairTableMeta {
    witness_inputs: usize,
    cells: usize,
    conflicts: Vec<String>,
}

#[derive(Debug, Default)]
struct PairTableData {
    cells: BTreeMap<(u32, u32), Vec<u32>>,
    conflicts: Vec<String>,
}

#[derive(Debug, Default)]
struct GeneratedPairTables {
    stack_change: PairTableData,
    partial_parse: PairTableData,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
enum TerminalRef {
    Empty,
    Token(u32),
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct LlpItem {
    prod: usize,
    dot: usize,
    lookback: TerminalRef,
    lookahead: TerminalRef,
    gamma: Vec<Sym>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LlpItemSet {
    items: Vec<LlpItem>,
}

#[derive(Debug, Clone)]
struct PslsEntry {
    gamma: Vec<Sym>,
    prod: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct PslsConflict {
    pair: (u32, u32),
    existing_prod: usize,
    prod: usize,
    existing_gamma: Vec<Sym>,
    gamma: Vec<Sym>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct PslsConflictGroupKey {
    existing_prod: usize,
    prod: usize,
    existing_gamma: Vec<Sym>,
    gamma: Vec<Sym>,
}

#[derive(Debug, Default)]
struct PslsTable {
    cells: BTreeMap<(u32, u32), PslsEntry>,
    conflicts: Vec<PslsConflict>,
}

#[derive(Debug, Clone)]
struct LlpParseEntry {
    initial_stack: Vec<Sym>,
    final_stack: Vec<Sym>,
    productions: Vec<usize>,
}

fn format_token(token: u32) -> String {
    if token == EOF_TOKEN {
        "$".to_string()
    } else {
        TokenKind::from_u32(token)
            .map(|kind| format!("{kind:?}"))
            .unwrap_or_else(|| format!("#{token}"))
    }
}

fn main() -> Result<()> {
    let grammar_path = env::args()
        .nth(1)
        .unwrap_or_else(|| "grammar/lanius.bnf".to_string());
    let out_path = PathBuf::from("tables/parse_tables.bin");
    let meta_path = PathBuf::from("tables/parse_tables.meta.json");
    let production_ids_path = PathBuf::from("shaders/parser/generated_parse_production_ids.slang");

    let src = fs::read_to_string(&grammar_path)
        .with_context(|| format!("failed to read grammar at {grammar_path}"))?;

    let spec = parse_grammar(&src).context("parse grammar")?;
    let analysis = analyze_grammar(&spec);
    if diagnostics_are_fatal(&analysis.diagnostics) {
        bail!(
            "grammar validation failed:\n{}",
            format_diagnostics(&analysis.diagnostics)
        );
    }

    for unreachable in &analysis.diagnostics.unreachable_nonterminals {
        eprintln!("[gen_parse_tables] warning: unreachable nonterminal '{unreachable}'");
    }

    let predictions = build_ll1_predictions(&spec, &analysis)?;
    let prod_arity = compute_prod_arity(&spec.productions);

    let (tables, pair_tables, witness_inputs): (
        PrecomputedParseTables,
        GeneratedPairTables,
        usize,
    ) = build_llp_precomputed_tables(&spec, &predictions, prod_arity.clone())?;

    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent)?;
    }
    tables.save_bin(&out_path)?;
    let meta = build_meta(
        &grammar_path,
        &spec,
        &analysis,
        &predictions,
        &prod_arity,
        &pair_tables,
        witness_inputs,
    );
    let meta_json = serde_json::to_string_pretty(&meta)?;
    fs::write(&meta_path, meta_json)
        .with_context(|| format!("write parse table metadata to {}", meta_path.display()))?;
    write_production_id_slang(&production_ids_path, &meta.productions).with_context(|| {
        format!(
            "write generated production-id Slang constants to {}",
            production_ids_path.display()
        )
    })?;
    println!(
        "[gen_parse_tables] wrote {}, {}, and {} (start={}, productions={}, predictions={}, stack_change_cells={}, stack_change_conflicts={}, partial_parse_cells={}, partial_parse_conflicts={}, terminals={}, nonterminals={}, nullable={}, diagnostics=clean)",
        out_path.display(),
        meta_path.display(),
        production_ids_path.display(),
        spec.start,
        spec.productions.len(),
        predictions.len(),
        pair_tables.stack_change.cells.len(),
        pair_tables.stack_change.conflicts.len(),
        pair_tables.partial_parse.cells.len(),
        pair_tables.partial_parse.conflicts.len(),
        count_terminal_refs(&spec.productions),
        count_nonterminal_refs(&spec.productions),
        analysis.nullable.len()
    );
    Ok(())
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
