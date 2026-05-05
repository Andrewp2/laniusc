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
    parser::tables::{PrecomputedParseTables, build_mvp_precomputed_tables},
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
    pp_projection: PairProjectionMeta,
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

    vec![
        vec![Ident, Semicolon],
        vec![Int, Semicolon],
        vec![Float, Semicolon],
        vec![String, Semicolon],
        vec![Char, Semicolon],
        vec![PrefixPlus, Int, Semicolon],
        vec![PrefixMinus, Int, Semicolon],
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
        vec![Ident, InfixPlus, Int, Semicolon],
        vec![Ident, InfixMinus, Int, Semicolon],
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
        vec![GroupLParen, Ident, GroupRParen, Semicolon],
        vec![ArrayLBracket, ArrayRBracket, Semicolon],
        vec![ArrayLBracket, Ident, ArrayRBracket, Semicolon],
        vec![ArrayLBracket, Ident, Comma, Int, ArrayRBracket, Semicolon],
        vec![Ident, Dot, Ident, Semicolon],
        vec![Ident, CallLParen, CallRParen, Semicolon],
        vec![Ident, CallLParen, Ident, CallRParen, Semicolon],
        vec![Ident, CallLParen, Ident, Comma, Int, CallRParen, Semicolon],
        vec![Ident, IndexLBracket, Int, IndexRBracket, Semicolon],
        vec![
            Ident,
            CallLParen,
            Int,
            CallRParen,
            IndexLBracket,
            Int,
            IndexRBracket,
            Semicolon,
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
            If,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Return,
            Ident,
            Semicolon,
            RBrace,
        ],
        vec![
            If,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Return,
            Ident,
            Semicolon,
            RBrace,
            Else,
            LBrace,
            Return,
            Int,
            Semicolon,
            RBrace,
        ],
        vec![
            While,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Break,
            Semicolon,
            Continue,
            Semicolon,
            RBrace,
        ],
        vec![LBrace, Let, Ident, Assign, Int, Semicolon, RBrace],
        vec![Fn, Ident, CallLParen, CallRParen, LBrace, RBrace],
        vec![
            Fn, Ident, CallLParen, CallRParen, Arrow, Ident, LBrace, Return, Int, Semicolon, RBrace,
        ],
        vec![
            Fn, Ident, CallLParen, Ident, Colon, Ident, CallRParen, Arrow, Ident, LBrace, Return,
            Ident, Semicolon, RBrace,
        ],
        vec![
            Pub,
            Fn,
            Ident,
            CallLParen,
            Ident,
            Colon,
            Ident,
            Comma,
            Ident,
            Colon,
            ArrayLBracket,
            Ident,
            Semicolon,
            Int,
            ArrayRBracket,
            CallRParen,
            Arrow,
            Ident,
            LBrace,
            Let,
            Ident,
            Colon,
            Ident,
            Assign,
            Ident,
            InfixPlus,
            Ident,
            IndexLBracket,
            Ident,
            IndexRBracket,
            Semicolon,
            If,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Return,
            Ident,
            Semicolon,
            RBrace,
            Else,
            LBrace,
            While,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Break,
            Semicolon,
            Continue,
            Semicolon,
            RBrace,
            RBrace,
            RBrace,
        ],
    ]
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

fn ll1_chunks_by_pair_ids(
    spec: &GrammarSpec,
    predict_map: &HashMap<(String, u32), usize>,
    input: &[TokenKind],
) -> Result<BTreeMap<(u32, u32), Vec<u32>>> {
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
                chunks_by_pos[pos].push(prod_id as u32);
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

fn project_pair_chunks(
    spec: &GrammarSpec,
    predictions: &[Prediction],
    witnesses: &[Vec<TokenKind>],
) -> Result<PairProjection> {
    let predict_map = build_predict_map(predictions);
    let mut projection = PairProjection::default();

    for input in witnesses {
        let chunks = ll1_chunks_by_pair_ids(spec, &predict_map, input)
            .with_context(|| format!("project LL(1) chunks for witness {}", format_input(input)))?;
        for (pair, chunk) in chunks {
            match projection.cells.get(&pair) {
                Some(existing) if existing != &chunk => {
                    projection.conflicts.push(format!(
                        "{}: kept [{}], saw [{}] from witness {}",
                        format_pair(pair),
                        format_prod_ids(existing, spec),
                        format_prod_ids(&chunk, spec),
                        format_input(input)
                    ));
                }
                Some(_) => {}
                None => {
                    projection.cells.insert(pair, chunk);
                }
            }
        }
    }

    Ok(projection)
}

fn build_projected_precomputed_tables(
    spec: &GrammarSpec,
    predictions: &[Prediction],
    prod_arity: Vec<u32>,
) -> Result<(PrecomputedParseTables, PairProjection, usize)> {
    let witnesses = default_projection_witnesses();
    let projection = project_pair_chunks(spec, predictions, &witnesses)?;
    let mut tables = build_mvp_precomputed_tables(N_KINDS, prod_arity);

    for (&(prev, this), seq) in &projection.cells {
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

    let (tables, pp_projection, witness_inputs): (PrecomputedParseTables, PairProjection, usize) =
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
        &pp_projection,
        witness_inputs,
    );
    let meta_json = serde_json::to_string_pretty(&meta)?;
    fs::write(&meta_path, meta_json)
        .with_context(|| format!("write parse table metadata to {}", meta_path.display()))?;
    println!(
        "[gen_parse_tables] wrote {} and {} (start={}, productions={}, predictions={}, projected_pp_cells={}, projection_conflicts={}, terminals={}, nonterminals={}, nullable={}, diagnostics=clean)",
        out_path.display(),
        meta_path.display(),
        spec.start,
        spec.productions.len(),
        predictions.len(),
        pp_projection.cells.len(),
        pp_projection.conflicts.len(),
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
    pp_projection: &PairProjection,
    witness_inputs: usize,
) -> ParseTablesMeta {
    ParseTablesMeta {
        grammar: grammar_path.to_string(),
        start: spec.start.clone(),
        lookback: DEFAULT_LOOKBACK,
        lookahead: DEFAULT_LOOKAHEAD,
        diagnostics: analysis.diagnostics.clone(),
        pp_projection: PairProjectionMeta {
            witness_inputs,
            projected_cells: pp_projection.cells.len(),
            conflicts: pp_projection.conflicts.clone(),
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
                TokenKind::InfixPlus,
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

        assert!(!projection.cells.is_empty());

        let input = [
            EOF_TOKEN,
            TokenKind::Ident as u32,
            TokenKind::InfixPlus as u32,
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
    fn ll1_predictions_parse_empty_array() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let tags = parse_with_predictions(
            &spec,
            &analysis,
            &[
                TokenKind::ArrayLBracket,
                TokenKind::ArrayRBracket,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse token stream");

        assert!(tags.iter().any(|tag| tag == "array_lit"));
        assert!(tags.iter().any(|tag| tag == "array_none"));
    }

    #[test]
    fn closing_delimiter_retags_disambiguate_rparen_pairs() {
        let spec = parse_grammar(include_str!("../../grammar/lanius.bnf")).expect("parse grammar");
        let analysis = analyze_grammar(&spec);

        let group = prediction_chunks_by_pair(
            &spec,
            &analysis,
            &[
                TokenKind::GroupLParen,
                TokenKind::Ident,
                TokenKind::GroupRParen,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse grouped expression");
        let call = prediction_chunks_by_pair(
            &spec,
            &analysis,
            &[
                TokenKind::Ident,
                TokenKind::CallLParen,
                TokenKind::Ident,
                TokenKind::CallRParen,
                TokenKind::Semicolon,
            ],
        )
        .expect("parse call expression");

        let group_key = (TokenKind::Ident as u32, TokenKind::GroupRParen as u32);
        let call_key = (TokenKind::Ident as u32, TokenKind::CallRParen as u32);
        assert!(
            !group.contains_key(&call_key),
            "group parse should not project through CallRParen"
        );
        assert!(
            !call.contains_key(&group_key),
            "call parse should not project through GroupRParen"
        );

        let key = (TokenKind::Ident as u32, TokenKind::CallRParen as u32);
        assert!(!group.contains_key(&key));
        let key = (TokenKind::Ident as u32, TokenKind::GroupRParen as u32);
        assert!(!call.contains_key(&key));

        let key = (TokenKind::Ident as u32, TokenKind::GroupRParen as u32);
        let group_chunk = group.get(&key).expect("group Ident/RParen chunk");
        let key = (TokenKind::Ident as u32, TokenKind::CallRParen as u32);
        let call_chunk = call.get(&key).expect("call Ident/RParen chunk");

        assert!(!group_chunk.iter().any(|tag| tag == "args_end"));
        assert!(call_chunk.iter().any(|tag| tag == "args_end"));
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
