// src/bin/parse_gen_tables/analysis.rs

use super::*;

pub(super) fn analyze_grammar(spec: &GrammarSpec) -> GrammarAnalysis {
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

pub(super) fn collect_nonterminals(prods: &[Production]) -> BTreeSet<String> {
    prods.iter().map(|prod| prod.lhs.clone()).collect()
}

pub(super) fn nonterminal_ids(nonterminals: &BTreeSet<String>) -> BTreeMap<String, u32> {
    nonterminals
        .iter()
        .enumerate()
        .map(|(id, name)| (name.clone(), id as u32))
        .collect()
}

pub(super) fn find_undefined_nonterminals(
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

pub(super) fn find_unreachable_nonterminals(
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

pub(super) fn compute_nullable(
    prods: &[Production],
    nonterminals: &BTreeSet<String>,
) -> BTreeSet<String> {
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

pub(super) fn compute_first(
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

pub(super) fn compute_follow(
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

pub(super) fn first_of_sequence(
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

pub(super) fn find_left_recursions(
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

pub(super) fn find_left_recursion_from(
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

pub(super) fn find_ll1_conflicts(
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

pub(super) fn intersection(a: &BTreeSet<u32>, b: &BTreeSet<u32>) -> BTreeSet<u32> {
    a.intersection(b).copied().collect()
}

pub(super) fn format_token_set(tokens: &BTreeSet<u32>) -> String {
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

pub(super) fn diagnostics_are_fatal(diagnostics: &GrammarDiagnostics) -> bool {
    !diagnostics.undefined_nonterminals.is_empty()
        || !diagnostics.left_recursions.is_empty()
        || !diagnostics.ll1_conflicts.is_empty()
}

pub(super) fn build_ll1_predictions(
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

pub(super) fn prediction_lookaheads(
    prod: &Production,
    analysis: &GrammarAnalysis,
) -> BTreeSet<u32> {
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

pub(super) fn format_diagnostics(diagnostics: &GrammarDiagnostics) -> String {
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
