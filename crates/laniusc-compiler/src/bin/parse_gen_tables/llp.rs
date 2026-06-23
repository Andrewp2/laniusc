// src/bin/parse_gen_tables/llp.rs

use super::*;

pub(super) fn item_set_key(set: &LlpItemSet) -> Vec<LlpItem> {
    let mut keys = set.items.clone();
    keys.sort();
    keys
}

pub(super) fn insert_item_unique(
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

pub(super) fn insert_term_set_omit_empty(
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

pub(super) fn compute_base_first_or_last_terms(
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

pub(super) fn compute_first_or_last_terms_for_sequence(
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

pub(super) fn compute_before_sets(
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

pub(super) fn compute_first_for_symbol_then_term(
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

pub(super) fn compute_gamma(
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

pub(super) fn llp_syms_before_dot(set: &LlpItemSet, spec: &GrammarSpec) -> Vec<Sym> {
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

pub(super) fn llp_predecessor(
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

pub(super) fn llp_closure(
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

pub(super) fn compute_llp_item_sets(
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

pub(super) fn build_psls_table(spec: &GrammarSpec, item_sets: &[LlpItemSet]) -> PslsTable {
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

pub(super) fn format_psls_conflicts(
    spec: &GrammarSpec,
    conflicts: &[PslsConflict],
    limit: usize,
) -> String {
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

pub(super) fn format_pair_samples(pairs: &[(u32, u32)], limit: usize) -> String {
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

pub(super) fn format_production_ref(id: usize, prod: &Production) -> String {
    format!(
        "#{id} {} [{}] line {} -> {}",
        prod.lhs,
        prod.tag,
        prod.line,
        format_symbol_sequence(&prod.rhs_syms)
    )
}

pub(super) fn format_symbol_sequence(syms: &[Sym]) -> String {
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

pub(super) fn stack_symbol_id(sym: &Sym, nt_symbol_ids: &BTreeMap<String, u32>) -> Result<u32> {
    match sym {
        Sym::Terminal(token) => Ok(*token),
        Sym::NonTerminal(name) => nt_symbol_ids
            .get(name)
            .copied()
            .ok_or_else(|| anyhow!("unknown nonterminal '{name}'")),
    }
}

pub(super) fn ll_partial_parse(
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

pub(super) fn build_llp_parse_entries(
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

pub(super) fn llp_augmented_spec(spec: &GrammarSpec) -> GrammarSpec {
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

pub(super) fn compute_prod_arity(prods: &[Production]) -> Vec<u32> {
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

pub(super) fn build_predict_map(predictions: &[Prediction]) -> HashMap<(String, u32), usize> {
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

pub(super) fn symbol_ids(spec: &GrammarSpec) -> BTreeMap<String, u32> {
    let nonterminals = collect_nonterminals(&spec.productions);
    nonterminal_ids(&nonterminals)
        .into_iter()
        .map(|(name, id)| (name, N_KINDS + id))
        .collect()
}

pub(super) fn install_ll1_runtime_tables(
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

pub(super) fn build_llp_precomputed_tables(
    spec: &GrammarSpec,
    predictions: &[Prediction],
    prod_arity: Vec<u32>,
) -> Result<(PrecomputedParseTables, GeneratedPairTables, usize)> {
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

    let mut pair_tables = GeneratedPairTables::default();

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

        pair_tables
            .stack_change
            .cells
            .insert((prev, this), sc.clone());
        pair_tables
            .partial_parse
            .cells
            .insert((prev, this), pp.clone());
        tables.set_sc_for_pair(prev, this, &sc);
        tables.set_pp_for_pair(prev, this, &pp);
    }

    let max_symbol_id = N_KINDS
        .saturating_add(nt_symbol_ids.len() as u32)
        .saturating_sub(1);
    tables.finalize_bit_widths(max_symbol_id);

    Ok((tables, pair_tables, 0))
}

pub(super) fn format_pair(pair: (u32, u32)) -> String {
    format!("({}, {})", format_token(pair.0), format_token(pair.1))
}
