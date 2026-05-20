// src/bin/parse_gen_tables.rs
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

use anyhow::{anyhow, bail, Context, Result};
use laniusc::{
    lexer::tables::tokens::{TokenKind, N_KINDS},
    parser::tables::{
        build_mvp_precomputed_tables,
        encode_pop,
        encode_push,
        PrecomputedParseTables,
        INVALID_TABLE_ENTRY,
    },
};
use serde::Serialize;

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
    sc_projection: PairProjectionMeta,
    pp_projection: PairProjectionMeta,
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
struct PairProjectionMeta {
    witness_inputs: usize,
    projected_cells: usize,
    conflicts: Vec<String>,
}

#[derive(Debug, Default)]
struct PairProjection {
    cells: BTreeMap<(u32, u32), Vec<u32>>,
    conflicts: Vec<String>,
}

#[derive(Debug, Default)]
struct SummaryProjection {
    sc: PairProjection,
    pp: PairProjection,
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

fn parse_grammar(src: &str) -> Result<GrammarSpec> {
    let mut prods = Vec::new();
    let mut tag_counts: HashMap<String, usize> = HashMap::new();
    let mut start: Option<String> = None;

    for (line_number, raw_line) in src.lines().enumerate() {
        let line_number = line_number + 1;
        let line = strip_comment(raw_line).trim();
        if line.is_empty() {
            continue;
        }

        if let Some(rest) = line.strip_prefix("%start") {
            if start.is_some() {
                bail!("line {line_number}: duplicate %start directive");
            }
            let rest = rest.trim();
            if !rest.ends_with(';') {
                bail!("line {line_number}: %start directive must end with ';'");
            }
            let name = rest.trim_end_matches(';').trim();
            if !is_ident(name) {
                bail!("line {line_number}: invalid start nonterminal '{name}'");
            }
            start = Some(name.to_string());
            continue;
        }

        if !line.ends_with(';') {
            bail!("line {line_number}: production must end with ';'");
        }

        let Some((lhs_part, rhs_part0)) = line.split_once("->") else {
            bail!("line {line_number}: expected production with '->'");
        };
        let rhs_part = rhs_part0.trim_end_matches(';').trim();

        let lhs_part = lhs_part.trim();
        let (lhs_name, tag_base) = parse_lhs(lhs_part, line_number)?;

        let next_count = tag_counts.entry(tag_base.clone()).or_default();
        *next_count += 1;
        let tag = if *next_count == 1 {
            tag_base
        } else {
            format!("{tag_base}#{}", *next_count)
        };

        let mut rhs_syms = Vec::new();
        for tok in rhs_part.split_whitespace() {
            if tok.starts_with('\'') && tok.ends_with('\'') && tok.len() >= 2 {
                let terminal_name = tok.trim_matches('\'');
                let token = TokenKind::from_name(terminal_name).ok_or_else(|| {
                    anyhow!("line {line_number}: unknown terminal token kind '{terminal_name}'")
                })?;
                rhs_syms.push(Sym::Terminal(token as u32));
            } else if is_ident(tok) {
                rhs_syms.push(Sym::NonTerminal(tok.to_string()));
            } else {
                bail!("line {line_number}: invalid grammar symbol '{tok}'");
            }
        }

        prods.push(Production {
            line: line_number,
            lhs: lhs_name,
            tag,
            rhs_syms,
        });
    }

    let start = start
        .or_else(|| prods.first().map(|prod| prod.lhs.clone()))
        .ok_or_else(|| anyhow!("grammar contains no productions"))?;

    Ok(GrammarSpec {
        start,
        productions: prods,
    })
}

fn strip_comment(line: &str) -> &str {
    line.split_once('#').map_or(line, |(before, _)| before)
}

fn parse_lhs(lhs_part: &str, line_number: usize) -> Result<(String, String)> {
    let (lhs_name, tag_base) = if let Some((lhs, tag_part0)) = lhs_part.split_once('[') {
        let tag_part = tag_part0.trim();
        let Some(tag) = tag_part.strip_suffix(']') else {
            bail!("line {line_number}: production tag must end with ']'");
        };
        (lhs.trim(), tag.trim())
    } else {
        (lhs_part, lhs_part)
    };

    if !is_ident(lhs_name) {
        bail!("line {line_number}: invalid production lhs '{lhs_name}'");
    }
    if !is_ident(tag_base) {
        bail!("line {line_number}: invalid production tag '{tag_base}'");
    }

    Ok((lhs_name.to_string(), tag_base.to_string()))
}

fn is_ident(s: &str) -> bool {
    let mut chars = s.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first == '_' || first.is_ascii_alphabetic())
        && chars.all(|c| c == '_' || c.is_ascii_alphanumeric())
}

fn analyze_grammar(spec: &GrammarSpec) -> GrammarAnalysis {
    let nonterminals = collect_nonterminals(&spec.productions);
    let undefined_nonterminals = find_undefined_nonterminals(&spec.productions, &nonterminals);
    let nullable = compute_nullable(&spec.productions, &nonterminals);
    let first = compute_first(&spec.productions, &nonterminals, &nullable);
    let follow = compute_follow(
        &spec.productions,
        &nonterminals,
        &nullable,
        &first,
        &spec.start,
    );

    let mut diagnostics = GrammarDiagnostics {
        undefined_nonterminals,
        unreachable_nonterminals: find_unreachable_nonterminals(
            &spec.productions,
            &nonterminals,
            &spec.start,
        ),
        left_recursions: find_left_recursions(&spec.productions, &nonterminals, &nullable),
        ll1_conflicts: Vec::new(),
    };

    if !nonterminals.contains(&spec.start) {
        diagnostics.undefined_nonterminals.push(format!(
            "start nonterminal '{}' has no productions",
            spec.start
        ));
    }

    diagnostics.ll1_conflicts = find_ll1_conflicts(spec, &nullable, &first, &follow);

    GrammarAnalysis {
        nullable,
        first,
        follow,
        diagnostics,
    }
}

fn collect_nonterminals(prods: &[Production]) -> BTreeSet<String> {
    prods.iter().map(|prod| prod.lhs.clone()).collect()
}

fn nonterminal_ids(nonterminals: &BTreeSet<String>) -> BTreeMap<String, u32> {
    nonterminals
        .iter()
        .enumerate()
        .map(|(id, name)| (name.clone(), id as u32))
        .collect()
}

fn find_undefined_nonterminals(
    prods: &[Production],
    nonterminals: &BTreeSet<String>,
) -> Vec<String> {
    let mut missing = BTreeSet::new();
    for prod in prods {
        for sym in &prod.rhs_syms {
            if let Sym::NonTerminal(name) = sym
                && !nonterminals.contains(name)
            {
                missing.insert(format!(
                    "line {}: '{}' referenced by '{}' has no productions",
                    prod.line, name, prod.lhs
                ));
            }
        }
    }
    missing.into_iter().collect()
}

fn find_unreachable_nonterminals(
    prods: &[Production],
    nonterminals: &BTreeSet<String>,
    start: &str,
) -> Vec<String> {
    if !nonterminals.contains(start) {
        return nonterminals.iter().cloned().collect();
    }

    let mut by_lhs: BTreeMap<&str, Vec<&Production>> = BTreeMap::new();
    for prod in prods {
        by_lhs.entry(&prod.lhs).or_default().push(prod);
    }

    let mut reachable = BTreeSet::new();
    let mut queue = VecDeque::new();
    reachable.insert(start.to_string());
    queue.push_back(start.to_string());

    while let Some(nt) = queue.pop_front() {
        if let Some(nt_prods) = by_lhs.get(nt.as_str()) {
            for prod in nt_prods {
                for sym in &prod.rhs_syms {
                    if let Sym::NonTerminal(child) = sym
                        && reachable.insert(child.clone())
                    {
                        queue.push_back(child.clone());
                    }
                }
            }
        }
    }

    nonterminals
        .difference(&reachable)
        .cloned()
        .collect::<Vec<_>>()
}

fn compute_nullable(prods: &[Production], nonterminals: &BTreeSet<String>) -> BTreeSet<String> {
    let mut nullable = BTreeSet::new();
    loop {
        let mut changed = false;
        for prod in prods {
            let rhs_nullable = prod.rhs_syms.iter().all(|sym| match sym {
                Sym::Terminal(_) => false,
                Sym::NonTerminal(name) => nullable.contains(name),
            });
            if rhs_nullable && nonterminals.contains(&prod.lhs) && nullable.insert(prod.lhs.clone())
            {
                changed = true;
            }
        }
        if !changed {
            return nullable;
        }
    }
}

fn compute_first(
    prods: &[Production],
    nonterminals: &BTreeSet<String>,
    nullable: &BTreeSet<String>,
) -> BTreeMap<String, BTreeSet<u32>> {
    let mut first = nonterminals
        .iter()
        .map(|nt| (nt.clone(), BTreeSet::new()))
        .collect::<BTreeMap<_, _>>();

    loop {
        let mut changed = false;
        for prod in prods {
            let seq_first = first_of_sequence(&prod.rhs_syms, nullable, &first).0;
            let lhs_first = first.entry(prod.lhs.clone()).or_default();
            for token in seq_first {
                if lhs_first.insert(token) {
                    changed = true;
                }
            }
        }
        if !changed {
            return first;
        }
    }
}

fn compute_follow(
    prods: &[Production],
    nonterminals: &BTreeSet<String>,
    nullable: &BTreeSet<String>,
    first: &BTreeMap<String, BTreeSet<u32>>,
    start: &str,
) -> BTreeMap<String, BTreeSet<u32>> {
    let mut follow = nonterminals
        .iter()
        .map(|nt| (nt.clone(), BTreeSet::new()))
        .collect::<BTreeMap<_, _>>();
    follow
        .entry(start.to_string())
        .or_default()
        .insert(EOF_TOKEN);

    loop {
        let mut changed = false;
        for prod in prods {
            for (idx, sym) in prod.rhs_syms.iter().enumerate() {
                let Sym::NonTerminal(name) = sym else {
                    continue;
                };
                let suffix = &prod.rhs_syms[idx + 1..];
                let (suffix_first, suffix_nullable) = first_of_sequence(suffix, nullable, first);

                let lhs_follow = if suffix_nullable {
                    follow.get(&prod.lhs).cloned().unwrap_or_default()
                } else {
                    BTreeSet::new()
                };

                let target = follow.entry(name.clone()).or_default();
                for token in suffix_first.into_iter().chain(lhs_follow) {
                    if target.insert(token) {
                        changed = true;
                    }
                }
            }
        }
        if !changed {
            return follow;
        }
    }
}

fn first_of_sequence(
    seq: &[Sym],
    nullable: &BTreeSet<String>,
    first: &BTreeMap<String, BTreeSet<u32>>,
) -> (BTreeSet<u32>, bool) {
    let mut out = BTreeSet::new();
    for sym in seq {
        match sym {
            Sym::Terminal(token) => {
                out.insert(*token);
                return (out, false);
            }
            Sym::NonTerminal(name) => {
                if let Some(nt_first) = first.get(name) {
                    out.extend(nt_first.iter().copied());
                }
                if !nullable.contains(name) {
                    return (out, false);
                }
            }
        }
    }
    (out, true)
}

fn find_left_recursions(
    prods: &[Production],
    nonterminals: &BTreeSet<String>,
    nullable: &BTreeSet<String>,
) -> Vec<String> {
    let mut edges: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for prod in prods {
        for sym in &prod.rhs_syms {
            match sym {
                Sym::Terminal(_) => break,
                Sym::NonTerminal(name) => {
                    edges
                        .entry(prod.lhs.clone())
                        .or_default()
                        .insert(name.clone());
                    if !nullable.contains(name) {
                        break;
                    }
                }
            }
        }
    }

    let mut cycles = BTreeSet::new();
    for start in nonterminals {
        let mut path = vec![start.clone()];
        find_left_recursion_from(start, start, &edges, &mut path, &mut cycles);
    }
    cycles.into_iter().collect()
}

fn find_left_recursion_from(
    start: &str,
    current: &str,
    edges: &BTreeMap<String, BTreeSet<String>>,
    path: &mut Vec<String>,
    cycles: &mut BTreeSet<String>,
) {
    let Some(nexts) = edges.get(current) else {
        return;
    };
    for next in nexts {
        if next == start {
            let mut cycle = path.clone();
            cycle.push(start.to_string());
            cycles.insert(cycle.join(" -> "));
        } else if !path.iter().any(|seen| seen == next) {
            path.push(next.clone());
            find_left_recursion_from(start, next, edges, path, cycles);
            path.pop();
        }
    }
}

fn find_ll1_conflicts(
    spec: &GrammarSpec,
    nullable: &BTreeSet<String>,
    first: &BTreeMap<String, BTreeSet<u32>>,
    follow: &BTreeMap<String, BTreeSet<u32>>,
) -> Vec<String> {
    let mut by_lhs: BTreeMap<&str, Vec<(usize, &Production)>> = BTreeMap::new();
    for (idx, prod) in spec.productions.iter().enumerate() {
        by_lhs.entry(&prod.lhs).or_default().push((idx, prod));
    }

    let mut conflicts = Vec::new();
    for (lhs, alternatives) in by_lhs {
        for i in 0..alternatives.len() {
            for j in i + 1..alternatives.len() {
                let (prod_a_id, prod_a) = alternatives[i];
                let (prod_b_id, prod_b) = alternatives[j];
                let (first_a, nullable_a) = first_of_sequence(&prod_a.rhs_syms, nullable, first);
                let (first_b, nullable_b) = first_of_sequence(&prod_b.rhs_syms, nullable, first);

                let first_overlap = intersection(&first_a, &first_b);
                if !first_overlap.is_empty() {
                    conflicts.push(format!(
                        "{lhs}: productions {} ('{}', line {}) and {} ('{}', line {}) share FIRST {}",
                        prod_a_id,
                        prod_a.tag,
                        prod_a.line,
                        prod_b_id,
                        prod_b.tag,
                        prod_b.line,
                        format_token_set(&first_overlap)
                    ));
                }

                let lhs_follow = follow.get(lhs).cloned().unwrap_or_default();
                if nullable_a {
                    let overlap = intersection(&first_b, &lhs_follow);
                    if !overlap.is_empty() {
                        conflicts.push(format!(
                            "{lhs}: nullable production {} ('{}', line {}) conflicts with production {} ('{}', line {}) through FOLLOW {}",
                            prod_a_id,
                            prod_a.tag,
                            prod_a.line,
                            prod_b_id,
                            prod_b.tag,
                            prod_b.line,
                            format_token_set(&overlap)
                        ));
                    }
                }
                if nullable_b {
                    let overlap = intersection(&first_a, &lhs_follow);
                    if !overlap.is_empty() {
                        conflicts.push(format!(
                            "{lhs}: nullable production {} ('{}', line {}) conflicts with production {} ('{}', line {}) through FOLLOW {}",
                            prod_b_id,
                            prod_b.tag,
                            prod_b.line,
                            prod_a_id,
                            prod_a.tag,
                            prod_a.line,
                            format_token_set(&overlap)
                        ));
                    }
                }
                if nullable_a && nullable_b {
                    conflicts.push(format!(
                        "{lhs}: productions {} ('{}', line {}) and {} ('{}', line {}) are both nullable",
                        prod_a_id, prod_a.tag, prod_a.line, prod_b_id, prod_b.tag, prod_b.line
                    ));
                }
            }
        }
    }
    conflicts
}

fn intersection(a: &BTreeSet<u32>, b: &BTreeSet<u32>) -> BTreeSet<u32> {
    a.intersection(b).copied().collect()
}

fn format_token_set(tokens: &BTreeSet<u32>) -> String {
    let names = tokens
        .iter()
        .map(|token| {
            if *token == EOF_TOKEN {
                "$".to_string()
            } else {
                TokenKind::from_u32(*token)
                    .map(|kind| format!("{kind:?}"))
                    .unwrap_or_else(|| format!("#{token}"))
            }
        })
        .collect::<Vec<_>>();
    format!("{{{}}}", names.join(", "))
}

fn diagnostics_are_fatal(diagnostics: &GrammarDiagnostics) -> bool {
    !diagnostics.undefined_nonterminals.is_empty()
        || !diagnostics.left_recursions.is_empty()
        || !diagnostics.ll1_conflicts.is_empty()
}

fn build_ll1_predictions(
    spec: &GrammarSpec,
    analysis: &GrammarAnalysis,
) -> Result<Vec<Prediction>> {
    let mut entries: BTreeMap<(String, u32), u32> = BTreeMap::new();

    for (prod_id, prod) in spec.productions.iter().enumerate() {
        let mut lookaheads = prediction_lookaheads(prod, analysis);
        for lookahead in std::mem::take(&mut lookaheads) {
            let key = (prod.lhs.clone(), lookahead);
            if let Some(prev) = entries.insert(key.clone(), prod_id as u32) {
                bail!(
                    "LL(1) prediction conflict for {} on {} between productions {} and {}",
                    key.0,
                    format_token(lookahead),
                    prev,
                    prod_id
                );
            }
        }
    }

    Ok(entries
        .into_iter()
        .map(|((nonterminal, lookahead), production)| Prediction {
            nonterminal,
            lookahead,
            production,
        })
        .collect())
}

fn prediction_lookaheads(prod: &Production, analysis: &GrammarAnalysis) -> BTreeSet<u32> {
    let (first, nullable) = first_of_sequence(&prod.rhs_syms, &analysis.nullable, &analysis.first);
    let mut out = first;
    if nullable {
        out.extend(
            analysis
                .follow
                .get(&prod.lhs)
                .into_iter()
                .flat_map(|tokens| tokens.iter().copied()),
        );
    }
    out
}

fn item_set_key(set: &LlpItemSet) -> Vec<LlpItem> {
    let mut keys = set.items.clone();
    keys.sort();
    keys
}

fn insert_item_unique(
    items: &mut Vec<LlpItem>,
    seen: &mut HashSet<LlpItem>,
    item: LlpItem,
) -> bool {
    if !seen.insert(item.clone()) {
        return false;
    }
    items.push(item);
    true
}

fn insert_term_set_omit_empty(
    dst: &mut BTreeSet<TerminalRef>,
    src: &BTreeSet<TerminalRef>,
) -> bool {
    let mut changed = false;
    for term in src {
        if *term != TerminalRef::Empty && dst.insert(*term) {
            changed = true;
        }
    }
    changed
}

fn compute_base_first_or_last_terms(
    spec: &GrammarSpec,
    first: bool,
) -> BTreeMap<String, BTreeSet<TerminalRef>> {
    let nonterminals = collect_nonterminals(&spec.productions);
    let mut sets = nonterminals
        .iter()
        .map(|name| (name.clone(), BTreeSet::new()))
        .collect::<BTreeMap<_, _>>();

    loop {
        let mut changed = false;
        for prod in &spec.productions {
            let mut nullable_prefix = true;
            let len = prod.rhs_syms.len();
            for i in 0..len {
                let sym = if first {
                    &prod.rhs_syms[i]
                } else {
                    &prod.rhs_syms[len - i - 1]
                };
                match sym {
                    Sym::Terminal(token) => {
                        changed |= sets
                            .entry(prod.lhs.clone())
                            .or_default()
                            .insert(TerminalRef::Token(*token));
                        nullable_prefix = false;
                        break;
                    }
                    Sym::NonTerminal(name) => {
                        let sym_set = sets.get(name).cloned().unwrap_or_default();
                        let has_empty = sym_set.contains(&TerminalRef::Empty);
                        changed |= insert_term_set_omit_empty(
                            sets.entry(prod.lhs.clone()).or_default(),
                            &sym_set,
                        );
                        if !has_empty {
                            nullable_prefix = false;
                            break;
                        }
                    }
                }
            }

            if nullable_prefix {
                changed |= sets
                    .entry(prod.lhs.clone())
                    .or_default()
                    .insert(TerminalRef::Empty);
            }
        }

        if !changed {
            return sets;
        }
    }
}

fn compute_first_or_last_terms_for_sequence(
    seq: &[Sym],
    first: bool,
    base_sets: &BTreeMap<String, BTreeSet<TerminalRef>>,
) -> BTreeSet<TerminalRef> {
    let mut out = BTreeSet::new();
    let len = seq.len();
    for i in 0..len {
        let sym = if first { &seq[i] } else { &seq[len - i - 1] };
        match sym {
            Sym::Terminal(token) => {
                out.insert(TerminalRef::Token(*token));
                return out;
            }
            Sym::NonTerminal(name) => {
                let Some(sym_set) = base_sets.get(name) else {
                    return out;
                };
                insert_term_set_omit_empty(&mut out, sym_set);
                if !sym_set.contains(&TerminalRef::Empty) {
                    return out;
                }
            }
        }
    }
    out.insert(TerminalRef::Empty);
    out
}

fn compute_before_sets(
    spec: &GrammarSpec,
    base_last: &BTreeMap<String, BTreeSet<TerminalRef>>,
) -> BTreeMap<String, BTreeSet<TerminalRef>> {
    let nonterminals = collect_nonterminals(&spec.productions);
    let mut before = nonterminals
        .iter()
        .map(|name| (name.clone(), BTreeSet::new()))
        .collect::<BTreeMap<_, _>>();
    before
        .entry(spec.start.clone())
        .or_default()
        .insert(TerminalRef::Token(EOF_TOKEN));

    loop {
        let mut changed = false;
        for prod in &spec.productions {
            for (i, sym) in prod.rhs_syms.iter().enumerate() {
                let Sym::NonTerminal(name) = sym else {
                    continue;
                };

                let prefix = &prod.rhs_syms[..i];
                let prefix_last =
                    compute_first_or_last_terms_for_sequence(prefix, false, base_last);
                changed |= insert_term_set_omit_empty(
                    before.entry(name.clone()).or_default(),
                    &prefix_last,
                );
                if prefix_last.contains(&TerminalRef::Empty) {
                    let lhs_before = before.get(&prod.lhs).cloned().unwrap_or_default();
                    changed |= insert_term_set_omit_empty(
                        before.entry(name.clone()).or_default(),
                        &lhs_before,
                    );
                }
            }
        }

        if !changed {
            return before;
        }
    }
}

fn compute_first_for_symbol_then_term(
    sym: &Sym,
    lookahead: TerminalRef,
    base_first: &BTreeMap<String, BTreeSet<TerminalRef>>,
) -> BTreeSet<TerminalRef> {
    let mut out = BTreeSet::new();
    match sym {
        Sym::Terminal(token) => {
            out.insert(TerminalRef::Token(*token));
        }
        Sym::NonTerminal(name) => {
            if let Some(first) = base_first.get(name) {
                insert_term_set_omit_empty(&mut out, first);
                if first.contains(&TerminalRef::Empty) {
                    out.insert(lookahead);
                }
            }
        }
    }
    out
}

fn compute_gamma(
    target: TerminalRef,
    x: &Sym,
    delta: &[Sym],
    base_first: &BTreeMap<String, BTreeSet<TerminalRef>>,
) -> Result<Vec<Sym>> {
    let TerminalRef::Token(target_token) = target else {
        bail!("LLP gamma target must be a concrete terminal");
    };

    let mut gamma = Vec::new();
    for sym in std::iter::once(x).chain(delta.iter()) {
        gamma.push(sym.clone());
        match sym {
            Sym::Terminal(token) => {
                if *token != target_token {
                    bail!(
                        "LLP gamma terminal mismatch: wanted {}, found {:?}",
                        format_token(target_token),
                        token
                    );
                }
                return Ok(gamma);
            }
            Sym::NonTerminal(name) => {
                let first = base_first
                    .get(name)
                    .ok_or_else(|| anyhow!("missing FIRST set for '{name}'"))?;
                if first.contains(&TerminalRef::Token(target_token)) {
                    return Ok(gamma);
                }
                if !first.contains(&TerminalRef::Empty) {
                    bail!(
                        "LLP gamma cannot pass non-nullable nonterminal '{}' toward {}",
                        name,
                        format_token(target_token)
                    );
                }
            }
        }
    }

    bail!(
        "LLP gamma exhausted symbols before {}",
        format_token(target_token)
    )
}

fn llp_syms_before_dot(set: &LlpItemSet, spec: &GrammarSpec) -> Vec<Sym> {
    let mut out = Vec::new();
    for item in &set.items {
        if item.dot == 0 {
            continue;
        }
        let sym = spec.productions[item.prod].rhs_syms[item.dot - 1].clone();
        if !out.iter().any(|existing| existing == &sym) {
            out.push(sym);
        }
    }
    out
}

fn llp_predecessor(
    set: &LlpItemSet,
    sym: &Sym,
    spec: &GrammarSpec,
    base_first: &BTreeMap<String, BTreeSet<TerminalRef>>,
    base_last: &BTreeMap<String, BTreeSet<TerminalRef>>,
    before: &BTreeMap<String, BTreeSet<TerminalRef>>,
) -> Result<LlpItemSet> {
    let mut new_set = LlpItemSet { items: Vec::new() };
    let mut seen = HashSet::new();

    for item in &set.items {
        if item.dot == 0 || &spec.productions[item.prod].rhs_syms[item.dot - 1] != sym {
            continue;
        }

        let prod = &spec.productions[item.prod];
        let alpha = &prod.rhs_syms[..item.dot - 1];
        let mut us = compute_first_or_last_terms_for_sequence(alpha, false, base_last);
        if us.contains(&TerminalRef::Empty) {
            let before_lhs = before.get(&prod.lhs).cloned().unwrap_or_default();
            if !before_lhs.is_empty() {
                us.remove(&TerminalRef::Empty);
            }
            insert_term_set_omit_empty(&mut us, &before_lhs);
        }

        let vs = compute_first_for_symbol_then_term(sym, item.lookahead, base_first);
        for u in &us {
            for v in &vs {
                if *v == TerminalRef::Empty {
                    continue;
                }
                let gamma = compute_gamma(*v, sym, &item.gamma, base_first)?;
                insert_item_unique(
                    &mut new_set.items,
                    &mut seen,
                    LlpItem {
                        prod: item.prod,
                        dot: item.dot - 1,
                        lookback: *u,
                        lookahead: *v,
                        gamma,
                    },
                );
            }
        }
    }

    Ok(new_set)
}

fn llp_closure(
    set: &mut LlpItemSet,
    spec: &GrammarSpec,
    base_last: &BTreeMap<String, BTreeSet<TerminalRef>>,
    before: &BTreeMap<String, BTreeSet<TerminalRef>>,
) {
    let mut queue = VecDeque::new();
    let mut seen = set.items.iter().cloned().collect::<HashSet<_>>();
    for item in &set.items {
        if item.dot > 0
            && matches!(
                spec.productions[item.prod].rhs_syms[item.dot - 1],
                Sym::NonTerminal(_)
            )
        {
            queue.push_back(item.clone());
        }
    }

    while let Some(item) = queue.pop_front() {
        let Sym::NonTerminal(nt) = &spec.productions[item.prod].rhs_syms[item.dot - 1] else {
            continue;
        };

        for (prod_id, prod) in spec.productions.iter().enumerate() {
            if &prod.lhs != nt {
                continue;
            }

            let mut us = compute_first_or_last_terms_for_sequence(&prod.rhs_syms, false, base_last);
            if us.contains(&TerminalRef::Empty) {
                us.remove(&TerminalRef::Empty);
                let before_lhs = before.get(&prod.lhs).cloned().unwrap_or_default();
                insert_term_set_omit_empty(&mut us, &before_lhs);
            }

            for u in us {
                let new_item = LlpItem {
                    prod: prod_id,
                    dot: prod.rhs_syms.len(),
                    lookback: u,
                    lookahead: item.lookahead,
                    gamma: item.gamma.clone(),
                };
                if insert_item_unique(&mut set.items, &mut seen, new_item.clone())
                    && new_item.dot > 0
                    && matches!(
                        spec.productions[new_item.prod].rhs_syms[new_item.dot - 1],
                        Sym::NonTerminal(_)
                    )
                {
                    queue.push_back(new_item);
                }
            }
        }
    }
}

fn compute_llp_item_sets(
    spec: &GrammarSpec,
    base_first: &BTreeMap<String, BTreeSet<TerminalRef>>,
    base_last: &BTreeMap<String, BTreeSet<TerminalRef>>,
    before: &BTreeMap<String, BTreeSet<TerminalRef>>,
) -> Result<Vec<LlpItemSet>> {
    let start_prod = spec
        .productions
        .iter()
        .position(|prod| prod.lhs == spec.start)
        .ok_or_else(|| anyhow!("start nonterminal '{}' has no production", spec.start))?;

    let initial = LlpItemSet {
        items: vec![LlpItem {
            prod: start_prod,
            dot: spec.productions[start_prod].rhs_syms.len(),
            lookback: TerminalRef::Token(EOF_TOKEN),
            lookahead: TerminalRef::Empty,
            gamma: Vec::new(),
        }],
    };

    let mut sets = Vec::new();
    let mut seen = BTreeSet::new();
    let mut queue = VecDeque::new();
    seen.insert(item_set_key(&initial));
    queue.push_back(initial.clone());
    sets.push(initial);

    while let Some(set) = queue.pop_front() {
        for sym in llp_syms_before_dot(&set, spec) {
            let mut new_set = llp_predecessor(&set, &sym, spec, base_first, base_last, before)?;
            llp_closure(&mut new_set, spec, base_last, before);
            let key = item_set_key(&new_set);
            if seen.insert(key) {
                queue.push_back(new_set.clone());
                sets.push(new_set);
            }
        }
    }

    Ok(sets)
}

fn build_psls_table(spec: &GrammarSpec, item_sets: &[LlpItemSet]) -> PslsTable {
    let mut psls = PslsTable::default();
    let mut seen_conflicts = BTreeSet::new();
    for set in item_sets {
        for item in &set.items {
            if item.dot == 0 {
                continue;
            }
            let Sym::Terminal(_) = spec.productions[item.prod].rhs_syms[item.dot - 1] else {
                continue;
            };
            let (TerminalRef::Token(x), TerminalRef::Token(y)) = (item.lookback, item.lookahead)
            else {
                continue;
            };
            let pair = (x, y);
            match psls.cells.get(&pair) {
                Some(existing) if existing.gamma != item.gamma => {
                    let conflict = PslsConflict {
                        pair,
                        existing_prod: existing.prod,
                        prod: item.prod,
                        existing_gamma: existing.gamma.clone(),
                        gamma: item.gamma.clone(),
                    };
                    if seen_conflicts.insert(conflict.clone()) {
                        psls.conflicts.push(conflict);
                    }
                }
                Some(_) => {}
                None => {
                    psls.cells.insert(
                        pair,
                        PslsEntry {
                            gamma: item.gamma.clone(),
                            prod: item.prod,
                        },
                    );
                }
            }
        }
    }
    psls
}

fn format_psls_conflicts(spec: &GrammarSpec, conflicts: &[PslsConflict], limit: usize) -> String {
    let mut grouped: BTreeMap<PslsConflictGroupKey, Vec<(u32, u32)>> = BTreeMap::new();
    for conflict in conflicts {
        grouped
            .entry(PslsConflictGroupKey {
                existing_prod: conflict.existing_prod,
                prod: conflict.prod,
                existing_gamma: conflict.existing_gamma.clone(),
                gamma: conflict.gamma.clone(),
            })
            .or_default()
            .push(conflict.pair);
    }

    let mut groups = grouped.into_iter().collect::<Vec<_>>();
    groups.sort_by(|(key_a, pairs_a), (key_b, pairs_b)| {
        pairs_b
            .len()
            .cmp(&pairs_a.len())
            .then_with(|| key_a.existing_prod.cmp(&key_b.existing_prod))
            .then_with(|| key_a.prod.cmp(&key_b.prod))
    });

    let mut lines = Vec::new();
    for (key, pairs) in groups.iter().take(limit) {
        let existing = &spec.productions[key.existing_prod];
        let incoming = &spec.productions[key.prod];
        lines.push(format!(
            "  {} pair(s), samples {}: {} vs {}",
            pairs.len(),
            format_pair_samples(pairs, 8),
            format_production_ref(key.existing_prod, existing),
            format_production_ref(key.prod, incoming)
        ));
        lines.push(format!(
            "    existing gamma: {}",
            format_symbol_sequence(&key.existing_gamma)
        ));
        lines.push(format!(
            "    incoming gamma: {}",
            format_symbol_sequence(&key.gamma)
        ));
    }
    lines.join("\n")
}

fn format_pair_samples(pairs: &[(u32, u32)], limit: usize) -> String {
    let samples = pairs
        .iter()
        .take(limit)
        .map(|pair| format_pair(*pair))
        .collect::<Vec<_>>();
    if pairs.len() > limit {
        format!("{} ...", samples.join(", "))
    } else {
        samples.join(", ")
    }
}

fn format_production_ref(id: usize, prod: &Production) -> String {
    format!(
        "#{id} {} [{}] line {} -> {}",
        prod.lhs,
        prod.tag,
        prod.line,
        format_symbol_sequence(&prod.rhs_syms)
    )
}

fn format_symbol_sequence(syms: &[Sym]) -> String {
    if syms.is_empty() {
        return "<empty>".to_string();
    }
    syms.iter()
        .map(|sym| match sym {
            Sym::Terminal(token) => format!("'{}'", format_token(*token)),
            Sym::NonTerminal(name) => name.clone(),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn stack_symbol_id(sym: &Sym, nt_symbol_ids: &BTreeMap<String, u32>) -> Result<u32> {
    match sym {
        Sym::Terminal(token) => Ok(*token),
        Sym::NonTerminal(name) => nt_symbol_ids
            .get(name)
            .copied()
            .ok_or_else(|| anyhow!("unknown nonterminal '{name}'")),
    }
}

fn ll_partial_parse(
    spec: &GrammarSpec,
    predict_map: &HashMap<(String, u32), usize>,
    y: u32,
    stack: &mut Vec<Sym>,
) -> Result<Vec<usize>> {
    let mut productions = Vec::new();
    loop {
        let Some(top) = stack.pop() else {
            bail!("LL partial parse stack emptied before {}", format_token(y));
        };
        match top {
            Sym::Terminal(token) => {
                if token != y {
                    bail!(
                        "LL partial parse terminal mismatch: expected {:?}, found {}",
                        format_token(token),
                        format_token(y)
                    );
                }
                break;
            }
            Sym::NonTerminal(name) => {
                let Some(&prod_id) = predict_map.get(&(name.clone(), y)) else {
                    bail!("no LL prediction for {name} on {}", format_token(y));
                };
                productions.push(prod_id);
                stack.extend(spec.productions[prod_id].rhs_syms.iter().rev().cloned());
            }
        }
    }
    Ok(productions)
}

fn build_llp_parse_entries(
    spec: &GrammarSpec,
    real_start: &str,
    predictions: &[Prediction],
    psls: &PslsTable,
) -> Result<BTreeMap<(u32, u32), LlpParseEntry>> {
    let predict_map = build_predict_map(predictions);
    let start_prod = spec
        .productions
        .iter()
        .position(|prod| prod.lhs == spec.start)
        .ok_or_else(|| anyhow!("start nonterminal '{}' has no production", spec.start))?;
    let mut entries = BTreeMap::new();

    for (&pair, entry) in &psls.cells {
        let (x, y) = pair;
        let (initial_stack, mut stack) = if entry.prod == start_prod && x == EOF_TOKEN {
            (
                Vec::new(),
                vec![
                    Sym::Terminal(EOF_TOKEN),
                    Sym::NonTerminal(real_start.to_string()),
                    Sym::Terminal(EOF_TOKEN),
                ],
            )
        } else {
            let initial = entry.gamma.iter().rev().cloned().collect::<Vec<_>>();
            (initial.clone(), initial)
        };

        if entry.prod == start_prod && x == EOF_TOKEN {
            ll_partial_parse(spec, &predict_map, x, &mut stack)
                .with_context(|| format!("consume start marker for {}", format_pair(pair)))?;
        }

        let productions = ll_partial_parse(spec, &predict_map, y, &mut stack)
            .with_context(|| format!("build LLP parse entry for {}", format_pair(pair)))?;
        entries.insert(
            pair,
            LlpParseEntry {
                initial_stack,
                final_stack: stack,
                productions,
            },
        );
    }

    Ok(entries)
}

fn llp_augmented_spec(spec: &GrammarSpec) -> GrammarSpec {
    let start = "__llp_start".to_string();
    let mut productions = spec.productions.clone();
    productions.push(Production {
        line: 0,
        lhs: start.clone(),
        tag: "__llp_start".to_string(),
        rhs_syms: vec![
            Sym::Terminal(EOF_TOKEN),
            Sym::NonTerminal(spec.start.clone()),
            Sym::Terminal(EOF_TOKEN),
        ],
    });
    GrammarSpec { start, productions }
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

fn format_diagnostics(diagnostics: &GrammarDiagnostics) -> String {
    let mut lines = Vec::new();
    for msg in &diagnostics.undefined_nonterminals {
        lines.push(format!("undefined: {msg}"));
    }
    for msg in &diagnostics.left_recursions {
        lines.push(format!("left-recursive: {msg}"));
    }
    for msg in &diagnostics.ll1_conflicts {
        lines.push(format!("ll1-conflict: {msg}"));
    }
    for msg in &diagnostics.unreachable_nonterminals {
        lines.push(format!("unreachable: {msg}"));
    }
    lines.join("\n")
}

fn compute_prod_arity(prods: &[Production]) -> Vec<u32> {
    prods
        .iter()
        .map(|p| {
            p.rhs_syms
                .iter()
                .filter(|s| matches!(s, Sym::NonTerminal(_)))
                .count() as u32
        })
        .collect()
}

fn build_predict_map(predictions: &[Prediction]) -> HashMap<(String, u32), usize> {
    predictions
        .iter()
        .map(|entry| {
            (
                (entry.nonterminal.clone(), entry.lookahead),
                entry.production as usize,
            )
        })
        .collect()
}

fn symbol_ids(spec: &GrammarSpec) -> BTreeMap<String, u32> {
    let nonterminals = collect_nonterminals(&spec.productions);
    nonterminal_ids(&nonterminals)
        .into_iter()
        .map(|(name, id)| (name, N_KINDS + id))
        .collect()
}

fn install_ll1_runtime_tables(
    tables: &mut PrecomputedParseTables,
    spec: &GrammarSpec,
    predictions: &[Prediction],
) -> Result<()> {
    let nonterminals = collect_nonterminals(&spec.productions);
    let nt_ids = nonterminal_ids(&nonterminals);
    let n_nonterminals = nt_ids.len() as u32;

    tables.n_nonterminals = n_nonterminals;
    tables.start_nonterminal = *nt_ids
        .get(&spec.start)
        .ok_or_else(|| anyhow!("start nonterminal '{}' is not defined", spec.start))?;

    let predict_cells = (n_nonterminals as usize) * (N_KINDS as usize);
    tables.ll1_predict = vec![INVALID_TABLE_ENTRY; predict_cells];
    for entry in predictions {
        let nt = *nt_ids.get(&entry.nonterminal).ok_or_else(|| {
            anyhow!(
                "prediction references unknown nonterminal '{}'",
                entry.nonterminal
            )
        })?;
        let idx = (nt as usize) * (N_KINDS as usize) + entry.lookahead as usize;
        tables.ll1_predict[idx] = entry.production;
    }

    tables.prod_rhs_off.clear();
    tables.prod_rhs_len.clear();
    tables.prod_rhs.clear();
    for prod in &spec.productions {
        tables.prod_rhs_off.push(tables.prod_rhs.len() as u32);
        tables.prod_rhs_len.push(prod.rhs_syms.len() as u32);
        for sym in &prod.rhs_syms {
            let encoded = match sym {
                Sym::Terminal(token) => *token,
                Sym::NonTerminal(name) => {
                    let id = *nt_ids
                        .get(name)
                        .ok_or_else(|| anyhow!("production references undefined '{name}'"))?;
                    N_KINDS + id
                }
            };
            tables.prod_rhs.push(encoded);
        }
    }

    Ok(())
}

fn build_projected_precomputed_tables(
    spec: &GrammarSpec,
    predictions: &[Prediction],
    prod_arity: Vec<u32>,
) -> Result<(PrecomputedParseTables, SummaryProjection, usize)> {
    let llp_spec = llp_augmented_spec(spec);
    let base_first = compute_base_first_or_last_terms(&llp_spec, true);
    let base_last = compute_base_first_or_last_terms(&llp_spec, false);
    let before = compute_before_sets(&llp_spec, &base_last);
    let item_sets = compute_llp_item_sets(&llp_spec, &base_first, &base_last, &before)?;
    let psls = build_psls_table(&llp_spec, &item_sets);
    if !psls.conflicts.is_empty() {
        let sample = format_psls_conflicts(&llp_spec, &psls.conflicts, 20);
        bail!(
            "grammar is not LLP(1, 1): {} PSLS conflicts\n{sample}",
            psls.conflicts.len()
        );
    }
    let entries = build_llp_parse_entries(&llp_spec, &spec.start, predictions, &psls)?;

    let mut projection = SummaryProjection::default();

    let mut tables = build_mvp_precomputed_tables(N_KINDS, prod_arity);
    install_ll1_runtime_tables(&mut tables, spec, predictions)?;

    tables.sc_superseq.clear();
    tables.sc_off.fill(0);
    tables.sc_len.fill(0);
    tables.pp_superseq.clear();
    tables.pp_off.fill(0);
    tables.pp_len.fill(0);

    let nt_symbol_ids = symbol_ids(&llp_spec);
    for (&(prev, this), entry) in &entries {
        let mut sc = Vec::new();
        for sym in entry.initial_stack.iter().rev() {
            sc.push(encode_pop(stack_symbol_id(sym, &nt_symbol_ids)?));
        }
        for sym in &entry.final_stack {
            sc.push(encode_push(stack_symbol_id(sym, &nt_symbol_ids)?));
        }
        let pp = entry
            .productions
            .iter()
            .map(|prod| *prod as u32)
            .collect::<Vec<_>>();

        projection.sc.cells.insert((prev, this), sc.clone());
        projection.pp.cells.insert((prev, this), pp.clone());
        tables.set_sc_for_pair(prev, this, &sc);
        tables.set_pp_for_pair(prev, this, &pp);
    }

    let max_symbol_id = N_KINDS
        .saturating_add(nt_symbol_ids.len() as u32)
        .saturating_sub(1);
    tables.finalize_bit_widths(max_symbol_id);

    Ok((tables, projection, 0))
}

fn format_pair(pair: (u32, u32)) -> String {
    format!("({}, {})", format_token(pair.0), format_token(pair.1))
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

    let (tables, projection, witness_inputs): (PrecomputedParseTables, SummaryProjection, usize) =
        build_projected_precomputed_tables(&spec, &predictions, prod_arity.clone())?;

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
        &projection,
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
        "[gen_parse_tables] wrote {}, {}, and {} (start={}, productions={}, predictions={}, candidate_llp_sc_cells={}, candidate_llp_sc_conflicts={}, projected_pp_cells={}, pp_conflicts={}, terminals={}, nonterminals={}, nullable={}, diagnostics=clean)",
        out_path.display(),
        meta_path.display(),
        production_ids_path.display(),
        spec.start,
        spec.productions.len(),
        predictions.len(),
        projection.sc.cells.len(),
        projection.sc.conflicts.len(),
        projection.pp.cells.len(),
        projection.pp.conflicts.len(),
        count_terminal_refs(&spec.productions),
        count_nonterminal_refs(&spec.productions),
        analysis.nullable.len()
    );
    Ok(())
}

fn write_production_id_slang(path: &PathBuf, productions: &[ProductionMeta]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let mut seen = HashSet::new();
    let mut source = String::from(
        "// Generated by src/bin/parse_gen_tables.rs from grammar/lanius.bnf.\n\
         // Do not edit by hand; regenerate parse tables instead.\n\n",
    );
    for prod in productions {
        let name = production_const_name(&prod.tag);
        if !seen.insert(name.clone()) {
            bail!("duplicate generated production constant name: {name}");
        }
        source.push_str(&format!("static const uint {name} = {}u;\n", prod.id));
    }
    fs::write(path, source)?;
    Ok(())
}

fn production_const_name(tag: &str) -> String {
    let mut out = String::from("PROD_");
    let mut last_was_underscore = false;
    for ch in tag.chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch.to_ascii_uppercase());
            last_was_underscore = false;
        } else if !last_was_underscore {
            out.push('_');
            last_was_underscore = true;
        }
    }
    if out.ends_with('_') {
        out.pop();
    }
    out
}

fn count_terminal_refs(prods: &[Production]) -> usize {
    prods
        .iter()
        .flat_map(|prod| prod.rhs_syms.iter())
        .filter_map(|sym| match sym {
            Sym::Terminal(token) => Some(*token),
            Sym::NonTerminal(_) => None,
        })
        .count()
}

fn count_nonterminal_refs(prods: &[Production]) -> usize {
    prods
        .iter()
        .flat_map(|prod| prod.rhs_syms.iter())
        .filter_map(|sym| match sym {
            Sym::Terminal(_) => None,
            Sym::NonTerminal(name) => Some(name.as_str()),
        })
        .count()
}

fn build_meta(
    grammar_path: &str,
    spec: &GrammarSpec,
    analysis: &GrammarAnalysis,
    predictions: &[Prediction],
    prod_arity: &[u32],
    projection: &SummaryProjection,
    witness_inputs: usize,
) -> ParseTablesMeta {
    ParseTablesMeta {
        grammar: grammar_path.to_string(),
        start: spec.start.clone(),
        lookback: DEFAULT_LOOKBACK,
        lookahead: DEFAULT_LOOKAHEAD,
        diagnostics: analysis.diagnostics.clone(),
        sc_projection: PairProjectionMeta {
            witness_inputs,
            projected_cells: projection.sc.cells.len(),
            conflicts: projection.sc.conflicts.clone(),
        },
        pp_projection: PairProjectionMeta {
            witness_inputs,
            projected_cells: projection.pp.cells.len(),
            conflicts: projection.pp.conflicts.clone(),
        },
        ll1_runtime: {
            let nonterminals = collect_nonterminals(&spec.productions);
            let rhs_symbols = spec
                .productions
                .iter()
                .map(|prod| prod.rhs_syms.len())
                .sum();
            Ll1RuntimeMeta {
                nonterminals: nonterminals.len(),
                start_nonterminal: spec.start.clone(),
                predict_cells: nonterminals.len() * N_KINDS as usize,
                rhs_symbols,
            }
        },
        ll1_predictions: predictions
            .iter()
            .map(|entry| PredictionMeta {
                nonterminal: entry.nonterminal.clone(),
                lookahead: format_token(entry.lookahead),
                lookahead_id: entry.lookahead,
                production: entry.production,
            })
            .collect(),
        productions: spec
            .productions
            .iter()
            .enumerate()
            .map(|(id, prod)| ProductionMeta {
                id: id as u32,
                line: prod.line,
                lhs: prod.lhs.clone(),
                tag: prod.tag.clone(),
                arity: prod_arity[id],
                rhs: prod
                    .rhs_syms
                    .iter()
                    .map(|sym| match sym {
                        Sym::Terminal(token) => format!("'{}'", format_token(*token)),
                        Sym::NonTerminal(name) => name.clone(),
                    })
                    .collect(),
            })
            .collect(),
    }
}

#[cfg(test)]
#[path = "parse_gen_tables/tests.rs"]
mod tests;
