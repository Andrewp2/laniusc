// src/bin/parse_gen_tables.rs
// Offline generator for the LLP "3 data structures / 7 arrays".
// Reads a simple grammar file and writes tables/parse_tables.bin plus metadata.
//
// Current behavior:
//   * Parses production lines and a `%start NonTerminal;` directive.
//   * Resolves quoted terminal names to lexer TokenKind discriminants.
//   * Validates the grammar boundary before table generation.
//   * Emits bracket stack-change sequences for the current runtime.
//   * Emits a first LL(1) witness-projected partial-parse table so the GPU parser
//     produces real production IDs for common expression inputs.
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
    collections::{BTreeMap, BTreeSet, HashMap, VecDeque},
    env,
    fs,
    path::PathBuf,
};

use anyhow::{Context, Result, anyhow, bail};
use laniusc::{
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

const DEFAULT_LOOKBACK: u32 = 1;
const DEFAULT_LOOKAHEAD: u32 = 1;
const EOF_TOKEN: u32 = 0;

#[derive(Debug)]
struct GrammarSpec {
    start: String,
    productions: Vec<Production>,
}

#[derive(Debug)]
struct Production {
    line: usize,
    lhs: String,
    tag: String,
    rhs_syms: Vec<Sym>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Sym {
    Terminal(TokenKind),
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
                rhs_syms.push(Sym::Terminal(token));
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
                out.insert(*token as u32);
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

fn default_projection_witnesses() -> Vec<Vec<TokenKind>> {
    use TokenKind::*;

    let mut witnesses = vec![
        vec![Ident, Semicolon],
        vec![Int, Semicolon],
        vec![Float, Semicolon],
        vec![String, Semicolon],
        vec![Char, Semicolon],
        vec![Plus, Int, Semicolon],
        vec![Minus, Int, Semicolon],
        vec![Not, Ident, Semicolon],
        vec![Tilde, Ident, Semicolon],
        vec![Inc, Ident, Semicolon],
        vec![Dec, Ident, Semicolon],
        vec![Ident, Inc, Semicolon],
        vec![Ident, Dec, Semicolon],
        vec![Ident, Assign, Int, Semicolon],
        vec![Ident, PlusAssign, Int, Semicolon],
        vec![Ident, MinusAssign, Int, Semicolon],
        vec![Ident, StarAssign, Int, Semicolon],
        vec![Ident, SlashAssign, Int, Semicolon],
        vec![Ident, PercentAssign, Int, Semicolon],
        vec![Ident, CaretAssign, Int, Semicolon],
        vec![Ident, ShlAssign, Int, Semicolon],
        vec![Ident, ShrAssign, Int, Semicolon],
        vec![Ident, AmpAssign, Int, Semicolon],
        vec![Ident, PipeAssign, Int, Semicolon],
        vec![Ident, Plus, Int, Semicolon],
        vec![Ident, Minus, Int, Semicolon],
        vec![Ident, Star, Int, Semicolon],
        vec![Ident, Slash, Int, Semicolon],
        vec![Ident, Percent, Int, Semicolon],
        vec![Ident, Shl, Int, Semicolon],
        vec![Ident, Shr, Int, Semicolon],
        vec![Ident, Lt, Int, Semicolon],
        vec![Ident, Gt, Int, Semicolon],
        vec![Ident, Le, Int, Semicolon],
        vec![Ident, Ge, Int, Semicolon],
        vec![Ident, EqEq, Int, Semicolon],
        vec![Ident, NotEqual, Int, Semicolon],
        vec![Ident, Ampersand, Ident, Semicolon],
        vec![Ident, Caret, Ident, Semicolon],
        vec![Ident, Pipe, Ident, Semicolon],
        vec![Ident, AndAnd, Ident, Semicolon],
        vec![Ident, OrOr, Ident, Semicolon],
        vec![LParen, Ident, RParen, Semicolon],
        vec![LBracket, RBracket, Semicolon],
        vec![LBracket, Ident, RBracket, Semicolon],
        vec![LBracket, Ident, Comma, Int, RBracket, Semicolon],
        vec![Ident, Dot, Ident, Semicolon],
        vec![Ident, LParen, RParen, Semicolon],
        vec![Ident, LParen, Ident, RParen, Semicolon],
        vec![Ident, LParen, Ident, Comma, Int, RParen, Semicolon],
        vec![Ident, LBracket, Int, RBracket, Semicolon],
        vec![
            Ident, LParen, Int, RParen, LBracket, Int, RBracket, Semicolon,
        ],
        vec![Let, Ident, Semicolon],
        vec![Let, Ident, Colon, Ident, Semicolon],
        vec![Let, Ident, Assign, Int, Semicolon],
        vec![Let, Ident, Colon, Ident, Assign, Int, Semicolon],
        vec![Return, Semicolon],
        vec![Return, Ident, Semicolon],
        vec![Break, Semicolon],
        vec![Continue, Semicolon],
        vec![
            If, LParen, Ident, RParen, LBrace, Return, Ident, Semicolon, RBrace,
        ],
        vec![
            If, LParen, Ident, RParen, LBrace, Return, Ident, Semicolon, RBrace, Else, LBrace,
            Return, Int, Semicolon, RBrace,
        ],
        vec![
            While, LParen, Ident, RParen, LBrace, Break, Semicolon, Continue, Semicolon, RBrace,
        ],
        vec![LBrace, Let, Ident, Assign, Int, Semicolon, RBrace],
        vec![Fn, Ident, LParen, RParen, LBrace, RBrace],
        vec![
            Fn, Ident, LParen, RParen, Arrow, Ident, LBrace, Return, Int, Semicolon, RBrace,
        ],
        vec![
            Fn, Ident, LParen, Ident, Colon, Ident, RParen, Arrow, Ident, LBrace, Return, Ident,
            Semicolon, RBrace,
        ],
        vec![
            Pub, Fn, Ident, LParen, Ident, Colon, Ident, Comma, Ident, Colon, LBracket, Ident,
            Semicolon, Int, RBracket, RParen, Arrow, Ident, LBrace, Let, Ident, Colon, Ident,
            Assign, Ident, Plus, Ident, LBracket, Ident, RBracket, Semicolon, If, LParen, Ident,
            RParen, LBrace, Return, Ident, Semicolon, RBrace, Else, LBrace, While, LParen, Ident,
            RParen, LBrace, Break, Semicolon, Continue, Semicolon, RBrace, RBrace, RBrace,
        ],
    ];

    let exprs = vec![
        vec![Ident],
        vec![Int],
        vec![Float],
        vec![String],
        vec![Char],
        vec![Plus, Int],
        vec![Minus, Int],
        vec![Not, Ident],
        vec![Tilde, Ident],
        vec![Inc, Ident],
        vec![Dec, Ident],
        vec![Ident, Inc],
        vec![Ident, Dec],
        vec![Ident, Assign, Int],
        vec![Ident, PlusAssign, Int],
        vec![Ident, MinusAssign, Int],
        vec![Ident, StarAssign, Int],
        vec![Ident, SlashAssign, Int],
        vec![Ident, PercentAssign, Int],
        vec![Ident, CaretAssign, Int],
        vec![Ident, ShlAssign, Int],
        vec![Ident, ShrAssign, Int],
        vec![Ident, AmpAssign, Int],
        vec![Ident, PipeAssign, Int],
        vec![Ident, Plus, Int],
        vec![Ident, Minus, Int],
        vec![Ident, Star, Int],
        vec![Ident, Slash, Int],
        vec![Ident, Percent, Int],
        vec![Ident, Shl, Int],
        vec![Ident, Shr, Int],
        vec![Ident, Lt, Int],
        vec![Ident, Gt, Int],
        vec![Ident, Le, Int],
        vec![Ident, Ge, Int],
        vec![Ident, EqEq, Int],
        vec![Ident, NotEqual, Int],
        vec![Ident, Ampersand, Ident],
        vec![Ident, Caret, Ident],
        vec![Ident, Pipe, Ident],
        vec![Ident, AndAnd, Ident],
        vec![Ident, OrOr, Ident],
        vec![Int, Plus, Int],
        vec![Int, Minus, Int],
        vec![Int, Star, Int],
        vec![Int, Slash, Int],
        vec![Int, Percent, Int],
        vec![Int, Shl, Int],
        vec![Int, Shr, Int],
        vec![Int, Lt, Int],
        vec![Int, Gt, Int],
        vec![Int, Le, Int],
        vec![Int, Ge, Int],
        vec![Int, EqEq, Int],
        vec![Int, NotEqual, Int],
        vec![Int, Ampersand, Int],
        vec![Int, Caret, Int],
        vec![Int, Pipe, Int],
        vec![Int, AndAnd, Int],
        vec![Int, OrOr, Int],
        vec![LParen, Ident, RParen],
        vec![LBracket, RBracket],
        vec![LBracket, Ident, RBracket],
        vec![LBracket, Ident, Comma, Int, RBracket],
        vec![Ident, Dot, Ident],
        vec![Ident, LParen, RParen],
        vec![Ident, LParen, Ident, RParen],
        vec![Ident, LParen, Ident, Comma, Int, RParen],
        vec![Ident, LBracket, Int, RBracket],
    ];

    for expr in &exprs {
        let mut stmt = expr.clone();
        stmt.push(Semicolon);
        witnesses.push(stmt);

        let mut ret = vec![Return];
        ret.extend_from_slice(expr);
        ret.push(Semicolon);
        witnesses.push(ret);

        let mut let_init = vec![Let, Ident, Assign];
        let_init.extend_from_slice(expr);
        let_init.push(Semicolon);
        witnesses.push(let_init);

        let mut let_typed_init = vec![Let, Ident, Colon, Ident, Assign];
        let_typed_init.extend_from_slice(expr);
        let_typed_init.push(Semicolon);
        witnesses.push(let_typed_init);

        let mut call = vec![Ident, LParen];
        call.extend_from_slice(expr);
        call.extend_from_slice(&[RParen, Semicolon]);
        witnesses.push(call);

        let mut call_more = vec![Ident, LParen, Ident, Comma];
        call_more.extend_from_slice(expr);
        call_more.extend_from_slice(&[RParen, Semicolon]);
        witnesses.push(call_more);

        let mut array = vec![LBracket];
        array.extend_from_slice(expr);
        array.extend_from_slice(&[RBracket, Semicolon]);
        witnesses.push(array);

        let mut array_more = vec![LBracket, Ident, Comma];
        array_more.extend_from_slice(expr);
        array_more.extend_from_slice(&[RBracket, Semicolon]);
        witnesses.push(array_more);

        let mut index = vec![Ident, LBracket];
        index.extend_from_slice(expr);
        index.extend_from_slice(&[RBracket, Semicolon]);
        witnesses.push(index);

        let mut block_expr = vec![LBrace];
        block_expr.extend_from_slice(expr);
        block_expr.extend_from_slice(&[Semicolon, RBrace]);
        witnesses.push(block_expr);

        let mut if_stmt = vec![If, LParen];
        if_stmt.extend_from_slice(expr);
        if_stmt.extend_from_slice(&[RParen, LBrace, Return, Int, Semicolon, RBrace]);
        witnesses.push(if_stmt);

        let mut while_stmt = vec![While, LParen];
        while_stmt.extend_from_slice(expr);
        while_stmt.extend_from_slice(&[RParen, LBrace, Break, Semicolon, RBrace]);
        witnesses.push(while_stmt);
    }

    let type_exprs = vec![vec![Ident], vec![LBracket, Ident, Semicolon, Int, RBracket]];
    for ty in &type_exprs {
        let mut param = vec![Fn, Ident, LParen, Ident, Colon];
        param.extend_from_slice(ty);
        param.extend_from_slice(&[RParen, LBrace, RBrace]);
        witnesses.push(param);

        let mut params_more = vec![Fn, Ident, LParen, Ident, Colon, Ident, Comma, Ident, Colon];
        params_more.extend_from_slice(ty);
        params_more.extend_from_slice(&[RParen, LBrace, RBrace]);
        witnesses.push(params_more);

        let mut let_type = vec![Let, Ident, Colon];
        let_type.extend_from_slice(ty);
        let_type.push(Semicolon);
        witnesses.push(let_type);

        let mut let_type_init = vec![Let, Ident, Colon];
        let_type_init.extend_from_slice(ty);
        let_type_init.extend_from_slice(&[Assign, Int, Semicolon]);
        witnesses.push(let_type_init);

        let mut ret_type = vec![Fn, Ident, LParen, RParen, Arrow];
        ret_type.extend_from_slice(ty);
        ret_type.extend_from_slice(&[LBrace, RBrace]);
        witnesses.push(ret_type);
    }

    witnesses.extend([
        vec![
            LBrace, Int, Semicolon, Break, Semicolon, Continue, Semicolon, Return, Int, Semicolon,
            RBrace,
        ],
        vec![LBrace, LBrace, RBrace, Return, Int, Semicolon, RBrace],
        vec![
            LBrace, While, LParen, Ident, RParen, LBrace, Break, Semicolon, Continue, Semicolon,
            RBrace, Return, Int, Semicolon, RBrace,
        ],
        vec![
            LBrace, Int, Semicolon, Ident, LParen, Ident, RParen, Semicolon, RBrace,
        ],
    ]);

    witnesses
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

fn encode_stack_sym(sym: &Sym, nt_symbol_ids: &BTreeMap<String, u32>) -> Result<u32> {
    match sym {
        Sym::Terminal(token) => Ok(*token as u32),
        Sym::NonTerminal(name) => nt_symbol_ids
            .get(name)
            .copied()
            .ok_or_else(|| anyhow!("unknown nonterminal '{name}'")),
    }
}

fn ll1_trace_by_pair_ids(
    spec: &GrammarSpec,
    predict_map: &HashMap<(String, u32), usize>,
    input: &[TokenKind],
) -> Result<(
    BTreeMap<(u32, u32), Vec<u32>>,
    BTreeMap<(u32, u32), Vec<u32>>,
)> {
    let nt_symbol_ids = symbol_ids(spec);
    let mut chunks_by_pos = vec![Vec::new(); input.len() + 1];
    let mut sc_by_pos = vec![Vec::new(); input.len() + 1];
    let mut stack = vec![Sym::NonTerminal(spec.start.clone())];
    let mut pos = 0usize;

    sc_by_pos[0].push(encode_push(*nt_symbol_ids.get(&spec.start).ok_or_else(
        || anyhow!("start nonterminal '{}' is not defined", spec.start),
    )?));

    while let Some(top) = stack.pop() {
        match top {
            Sym::Terminal(token) => {
                if input.get(pos).copied() != Some(token) {
                    bail!(
                        "terminal mismatch at pos {}: expected {:?}, found {:?}",
                        pos,
                        token,
                        input.get(pos)
                    );
                }
                sc_by_pos[pos].push(encode_pop(token as u32));
                pos += 1;
            }
            Sym::NonTerminal(name) => {
                let lookahead = input
                    .get(pos)
                    .map(|token| *token as u32)
                    .unwrap_or(EOF_TOKEN);
                let Some(&prod_id) = predict_map.get(&(name.clone(), lookahead)) else {
                    bail!(
                        "no prediction for {} on {} at pos {}",
                        name,
                        format_token(lookahead),
                        pos
                    );
                };
                let prod = &spec.productions[prod_id];
                chunks_by_pos[pos].push(prod_id as u32);
                sc_by_pos[pos].push(encode_pop(
                    *nt_symbol_ids
                        .get(&name)
                        .ok_or_else(|| anyhow!("unknown nonterminal '{name}'"))?,
                ));
                for sym in prod.rhs_syms.iter().rev() {
                    sc_by_pos[pos].push(encode_push(encode_stack_sym(sym, &nt_symbol_ids)?));
                }
                stack.extend(prod.rhs_syms.iter().rev().cloned());
            }
        }
    }

    if pos != input.len() {
        bail!("parser stopped at token {} of {}", pos, input.len());
    }

    let mut pp_out = BTreeMap::new();
    let mut sc_out = BTreeMap::new();
    for pos in 0..=input.len() {
        let prev = if pos == 0 {
            EOF_TOKEN
        } else {
            input[pos - 1] as u32
        };
        let current = input
            .get(pos)
            .map(|token| *token as u32)
            .unwrap_or(EOF_TOKEN);
        pp_out.insert((prev, current), chunks_by_pos[pos].clone());
        sc_out.insert((prev, current), sc_by_pos[pos].clone());
    }

    Ok((sc_out, pp_out))
}

fn install_projection_cell(
    projection: &mut PairProjection,
    pair: (u32, u32),
    seq: Vec<u32>,
    spec: &GrammarSpec,
    witness: &[TokenKind],
    kind: &str,
) {
    let fmt_seq = |seq: &[u32]| {
        if kind == "sc" {
            format_sc_ops(seq, spec)
        } else {
            format_prod_ids(seq, spec)
        }
    };
    match projection.cells.get(&pair) {
        Some(existing) if existing != &seq => {
            projection.conflicts.push(format!(
                "{kind} {}: kept [{}], saw [{}] from witness {}",
                format_pair(pair),
                fmt_seq(existing),
                fmt_seq(&seq),
                format_input(witness)
            ));
        }
        Some(_) => {}
        None => {
            projection.cells.insert(pair, seq);
        }
    }
}

fn project_pair_summaries(
    spec: &GrammarSpec,
    predictions: &[Prediction],
    witnesses: &[Vec<TokenKind>],
) -> Result<SummaryProjection> {
    let predict_map = build_predict_map(predictions);
    let mut projection = SummaryProjection::default();

    for input in witnesses {
        let (sc_chunks, pp_chunks) = ll1_trace_by_pair_ids(spec, &predict_map, input)
            .with_context(|| {
                format!(
                    "project LL(1) summaries for witness {}",
                    format_input(input)
                )
            })?;
        for (pair, chunk) in sc_chunks {
            install_projection_cell(&mut projection.sc, pair, chunk, spec, input, "sc");
        }
        for (pair, chunk) in pp_chunks {
            install_projection_cell(&mut projection.pp, pair, chunk, spec, input, "pp");
        }
    }

    Ok(projection)
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
                Sym::Terminal(token) => *token as u32,
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
    let witnesses = default_projection_witnesses();
    let projection = project_pair_summaries(spec, predictions, &witnesses)?;
    let mut tables = build_mvp_precomputed_tables(N_KINDS, prod_arity);
    install_ll1_runtime_tables(&mut tables, spec, predictions)?;

    tables.pp_superseq.clear();
    tables.pp_off.fill(0);
    tables.pp_len.fill(0);

    for (&(prev, this), seq) in &projection.pp.cells {
        tables.set_pp_for_pair(prev, this, seq);
    }
    tables.finalize_bit_widths(1);

    Ok((tables, projection, witnesses.len()))
}

fn format_input(input: &[TokenKind]) -> String {
    let names = input
        .iter()
        .map(|token| format!("{token:?}"))
        .collect::<Vec<_>>();
    format!("[{}]", names.join(", "))
}

fn format_pair(pair: (u32, u32)) -> String {
    format!("({}, {})", format_token(pair.0), format_token(pair.1))
}

fn format_prod_ids(ids: &[u32], spec: &GrammarSpec) -> String {
    ids.iter()
        .map(|id| {
            spec.productions
                .get(*id as usize)
                .map(|prod| format!("{}:{id}", prod.tag))
                .unwrap_or_else(|| format!("#{id}"))
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn format_sc_ops(ops: &[u32], spec: &GrammarSpec) -> String {
    ops.iter()
        .map(|op| {
            let verb = if op & 1 == 1 { "push" } else { "pop" };
            let sym = format_stack_symbol(op / 2, spec);
            format!("{verb}({sym})")
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn format_stack_symbol(symbol_id: u32, spec: &GrammarSpec) -> String {
    if symbol_id < N_KINDS {
        return format_token(symbol_id);
    }

    let nt_id = symbol_id - N_KINDS;
    let nonterminals = collect_nonterminals(&spec.productions);
    for (name, id) in nonterminal_ids(&nonterminals) {
        if id == nt_id {
            return name;
        }
    }
    format!("#{symbol_id}")
}

fn main() -> Result<()> {
    let grammar_path = env::args()
        .nth(1)
        .unwrap_or_else(|| "grammar/lanius.bnf".to_string());
    let out_path = PathBuf::from("tables/parse_tables.bin");
    let meta_path = PathBuf::from("tables/parse_tables.meta.json");

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
    println!(
        "[gen_parse_tables] wrote {} and {} (start={}, productions={}, predictions={}, candidate_llp_sc_cells={}, candidate_llp_sc_conflicts={}, projected_pp_cells={}, pp_conflicts={}, terminals={}, nonterminals={}, nullable={}, diagnostics=clean)",
        out_path.display(),
        meta_path.display(),
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

fn count_terminal_refs(prods: &[Production]) -> usize {
    prods
        .iter()
        .flat_map(|prod| prod.rhs_syms.iter())
        .filter_map(|sym| match sym {
            Sym::Terminal(token) => Some(*token as u32),
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
                        Sym::Terminal(token) => format!("'{token:?}'"),
                        Sym::NonTerminal(name) => name.clone(),
                    })
                    .collect(),
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_with_predictions(
        spec: &GrammarSpec,
        analysis: &GrammarAnalysis,
        input: &[TokenKind],
    ) -> Result<Vec<String>> {
        let predictions = build_ll1_predictions(spec, analysis)?;
        let predict_map = predictions
            .into_iter()
            .map(|entry| {
                (
                    (entry.nonterminal, entry.lookahead),
                    entry.production as usize,
                )
            })
            .collect::<HashMap<_, _>>();

        let mut stack = vec![Sym::NonTerminal(spec.start.clone())];
        let mut pos = 0usize;
        let mut emitted = Vec::new();

        while let Some(top) = stack.pop() {
            match top {
                Sym::Terminal(token) => {
                    if input.get(pos).copied() != Some(token) {
                        bail!(
                            "terminal mismatch at pos {}: expected {:?}, found {:?}",
                            pos,
                            token,
                            input.get(pos)
                        );
                    }
                    pos += 1;
                }
                Sym::NonTerminal(name) => {
                    let lookahead = input
                        .get(pos)
                        .map(|token| *token as u32)
                        .unwrap_or(EOF_TOKEN);
                    let Some(&prod_id) = predict_map.get(&(name.clone(), lookahead)) else {
                        bail!(
                            "no prediction for {} on {} at pos {}",
                            name,
                            format_token(lookahead),
                            pos
                        );
                    };
                    let prod = &spec.productions[prod_id];
                    emitted.push(prod.tag.clone());
                    stack.extend(prod.rhs_syms.iter().rev().cloned());
                }
            }
        }

        if pos != input.len() {
            bail!("parser stopped at token {} of {}", pos, input.len());
        }

        Ok(emitted)
    }

    fn prediction_chunks_by_pair(
        spec: &GrammarSpec,
        analysis: &GrammarAnalysis,
        input: &[TokenKind],
    ) -> Result<BTreeMap<(u32, u32), Vec<String>>> {
        let predictions = build_ll1_predictions(spec, analysis)?;
        let predict_map = predictions
            .into_iter()
            .map(|entry| {
                (
                    (entry.nonterminal, entry.lookahead),
                    entry.production as usize,
                )
            })
            .collect::<HashMap<_, _>>();

        let mut chunks_by_pos = vec![Vec::new(); input.len() + 1];
        let mut stack = vec![Sym::NonTerminal(spec.start.clone())];
        let mut pos = 0usize;

        while let Some(top) = stack.pop() {
            match top {
                Sym::Terminal(token) => {
                    if input.get(pos).copied() != Some(token) {
                        bail!(
                            "terminal mismatch at pos {}: expected {:?}, found {:?}",
                            pos,
                            token,
                            input.get(pos)
                        );
                    }
                    pos += 1;
                }
                Sym::NonTerminal(name) => {
                    let lookahead = input
                        .get(pos)
                        .map(|token| *token as u32)
                        .unwrap_or(EOF_TOKEN);
                    let Some(&prod_id) = predict_map.get(&(name.clone(), lookahead)) else {
                        bail!(
                            "no prediction for {} on {} at pos {}",
                            name,
                            format_token(lookahead),
                            pos
                        );
                    };
                    let prod = &spec.productions[prod_id];
                    chunks_by_pos[pos].push(prod.tag.clone());
                    stack.extend(prod.rhs_syms.iter().rev().cloned());
                }
            }
        }

        if pos != input.len() {
            bail!("parser stopped at token {} of {}", pos, input.len());
        }

        let mut out = BTreeMap::new();
        for (pos, chunk) in chunks_by_pos.into_iter().enumerate() {
            let prev = if pos == 0 {
                EOF_TOKEN
            } else {
                input[pos - 1] as u32
            };
            let current = input
                .get(pos)
                .map(|token| *token as u32)
                .unwrap_or(EOF_TOKEN);
            out.insert((prev, current), chunk);
        }
        Ok(out)
    }

    #[test]
    fn parses_explicit_start_directive() {
        let spec = parse_grammar(
            "
            %start expr;
            expr -> 'Ident';
            ",
        )
        .expect("parse grammar");

        assert_eq!(spec.start, "expr");
        assert_eq!(spec.productions.len(), 1);
    }

    #[test]
    fn current_grammar_is_clean_at_generator_boundary() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let predictions = build_ll1_predictions(&spec, &analysis).expect("ll1 predictions");

        assert_eq!(spec.start, "file");
        assert!(!predictions.is_empty());
        assert!(
            !diagnostics_are_fatal(&analysis.diagnostics),
            "{}",
            format_diagnostics(&analysis.diagnostics)
        );
    }

    #[test]
    fn ll1_predictions_parse_expression_stream() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let tags = parse_with_predictions(
            &spec,
            &analysis,
            &[
                TokenKind::Ident,
                TokenKind::Plus,
                TokenKind::Int,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse token stream");

        assert_eq!(tags.first().map(String::as_str), Some("file"));
        assert!(tags.iter().any(|tag| tag == "expr"));
        assert!(tags.iter().any(|tag| tag == "ident"));
        assert!(tags.iter().any(|tag| tag == "add_tail"));
        assert!(tags.iter().any(|tag| tag == "int"));
        assert!(tags.iter().any(|tag| tag == "assign_end"));
    }

    #[test]
    fn projected_tables_emit_expression_pairs() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let predictions = build_ll1_predictions(&spec, &analysis).expect("ll1 predictions");
        let prod_arity = compute_prod_arity(&spec.productions);
        let (tables, projection, _) =
            build_projected_precomputed_tables(&spec, &predictions, prod_arity)
                .expect("project tables");

        assert!(!projection.pp.cells.is_empty());
        assert!(!projection.sc.cells.is_empty());

        let input = [
            EOF_TOKEN,
            TokenKind::Ident as u32,
            TokenKind::Plus as u32,
            TokenKind::Int as u32,
            TokenKind::Semicolon as u32,
            EOF_TOKEN,
        ];
        let mut emitted = Vec::new();
        for pair in input.windows(2) {
            let idx = (pair[0] as usize) * (tables.n_kinds as usize) + (pair[1] as usize);
            let off = tables.pp_off[idx] as usize;
            let len = tables.pp_len[idx] as usize;
            emitted.extend_from_slice(&tables.pp_superseq[off..off + len]);
        }

        let tags = emitted
            .iter()
            .map(|id| spec.productions[*id as usize].tag.as_str())
            .collect::<Vec<_>>();

        assert!(tags.contains(&"expr"));
        assert!(tags.contains(&"ident"));
        assert!(tags.contains(&"add_tail"));
        assert!(tags.contains(&"int"));
        assert!(tags.contains(&"assign_end"));
    }

    #[test]
    fn candidate_llp_stack_summaries_are_projected_for_raw_tokens() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let predictions = build_ll1_predictions(&spec, &analysis).expect("ll1 predictions");
        let witnesses = default_projection_witnesses();
        let projection =
            project_pair_summaries(&spec, &predictions, &witnesses).expect("project summaries");

        assert!(!projection.sc.cells.is_empty());
        assert!(!projection.pp.cells.is_empty());
    }

    #[test]
    fn ll1_predictions_parse_empty_array() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let tags = parse_with_predictions(
            &spec,
            &analysis,
            &[
                TokenKind::LBracket,
                TokenKind::RBracket,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse token stream");

        assert!(tags.iter().any(|tag| tag == "array_lit"));
        assert!(tags.iter().any(|tag| tag == "array_none"));
    }

    #[test]
    fn raw_closing_delimiters_share_rparen_projection_pairs() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);

        let group = prediction_chunks_by_pair(
            &spec,
            &analysis,
            &[
                TokenKind::LParen,
                TokenKind::Ident,
                TokenKind::RParen,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse grouped expression");
        let call = prediction_chunks_by_pair(
            &spec,
            &analysis,
            &[
                TokenKind::Ident,
                TokenKind::LParen,
                TokenKind::Ident,
                TokenKind::RParen,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse call expression");

        let key = (TokenKind::Ident as u32, TokenKind::RParen as u32);
        let group_chunk = group.get(&key).expect("group Ident/RParen chunk");
        let call_chunk = call.get(&key).expect("call Ident/RParen chunk");

        assert!(!group_chunk.is_empty());
        assert!(!call_chunk.is_empty());
    }

    #[test]
    fn detects_direct_left_recursion() {
        let spec = parse_grammar(
            "
            %start expr;
            expr -> expr 'InfixPlus' atom;
            expr -> atom;
            atom -> 'Ident';
            ",
        )
        .expect("parse grammar");
        let analysis = analyze_grammar(&spec);

        assert!(
            analysis
                .diagnostics
                .left_recursions
                .iter()
                .any(|cycle| cycle == "expr -> expr")
        );
    }

    #[test]
    fn detects_ll1_first_conflict() {
        let spec = parse_grammar(
            "
            %start expr;
            expr [a] -> 'Ident';
            expr [b] -> 'Ident';
            ",
        )
        .expect("parse grammar");
        let analysis = analyze_grammar(&spec);

        assert!(
            analysis
                .diagnostics
                .ll1_conflicts
                .iter()
                .any(|conflict| conflict.contains("share FIRST {Ident}"))
        );
    }

    #[test]
    fn detects_undefined_nonterminals() {
        let spec = parse_grammar(
            "
            %start expr;
            expr -> atom;
            ",
        )
        .expect("parse grammar");
        let analysis = analyze_grammar(&spec);

        assert!(
            analysis
                .diagnostics
                .undefined_nonterminals
                .iter()
                .any(|missing| missing.contains("'atom'"))
        );
    }
}
