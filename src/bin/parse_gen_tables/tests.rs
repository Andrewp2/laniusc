use std::sync::OnceLock;

use super::*;

struct CurrentGrammarFixture {
    spec: GrammarSpec,
    analysis: GrammarAnalysis,
    predictions: Vec<Prediction>,
}

struct CurrentProjectedFixture {
    tables: PrecomputedParseTables,
    projection: SummaryProjection,
}

fn current_grammar_fixture() -> &'static CurrentGrammarFixture {
    static FIXTURE: OnceLock<CurrentGrammarFixture> = OnceLock::new();
    FIXTURE.get_or_init(|| {
        let spec = parse_grammar(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/grammar/lanius.bnf"
        )))
        .expect("parse grammar");
        let analysis = analyze_grammar(&spec);
        let predictions = build_ll1_predictions(&spec, &analysis).expect("ll1 predictions");
        CurrentGrammarFixture {
            spec,
            analysis,
            predictions,
        }
    })
}

fn current_projected_fixture() -> &'static CurrentProjectedFixture {
    static FIXTURE: OnceLock<CurrentProjectedFixture> = OnceLock::new();
    FIXTURE.get_or_init(|| {
        let current = current_grammar_fixture();
        let prod_arity = compute_prod_arity(&current.spec.productions);
        let (tables, projection, _) =
            build_projected_precomputed_tables(&current.spec, &current.predictions, prod_arity)
                .expect("project tables");
        CurrentProjectedFixture { tables, projection }
    })
}

fn parse_with_predictions(
    spec: &GrammarSpec,
    predictions: &[Prediction],
    input: &[TokenKind],
) -> Result<Vec<String>> {
    let predict_map = build_predict_map(predictions);

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
    predictions: &[Prediction],
    input: &[TokenKind],
) -> Result<BTreeMap<(u32, u32), Vec<String>>> {
    let predict_map = build_predict_map(predictions);

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
    let current = current_grammar_fixture();

    assert_eq!(current.spec.start, "file");
    assert!(!current.predictions.is_empty());
    assert!(
        !diagnostics_are_fatal(&current.analysis.diagnostics),
        "{}",
        format_diagnostics(&current.analysis.diagnostics)
    );
}

#[test]
fn ll1_predictions_parse_expression_stream() {
    let current = current_grammar_fixture();
    let tags = parse_with_predictions(
        &current.spec,
        &current.predictions,
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
    let current = current_grammar_fixture();
    let projected = current_projected_fixture();

    assert!(!projected.projection.pp.cells.is_empty());
    assert!(!projected.projection.sc.cells.is_empty());

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
        let idx = (pair[0] as usize) * (projected.tables.n_kinds as usize) + (pair[1] as usize);
        let off = projected.tables.pp_off[idx] as usize;
        let len = projected.tables.pp_len[idx] as usize;
        emitted.extend_from_slice(&projected.tables.pp_superseq[off..off + len]);
    }

    let tags = emitted
        .iter()
        .map(|id| current.spec.productions[*id as usize].tag.as_str())
        .collect::<Vec<_>>();

    assert!(tags.contains(&"expr"));
    assert!(tags.contains(&"ident"));
    assert!(tags.contains(&"add_tail"));
    assert!(tags.contains(&"int"));
    assert!(tags.contains(&"assign_end"));
}

#[test]
fn candidate_llp_stack_summaries_are_projected_for_raw_tokens() {
    let projection = &current_projected_fixture().projection;

    assert!(!projection.sc.cells.is_empty());
    assert!(!projection.pp.cells.is_empty());
}

#[test]
fn ll1_predictions_parse_empty_array() {
    let current = current_grammar_fixture();
    let tags = parse_with_predictions(
        &current.spec,
        &current.predictions,
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
    let current = current_grammar_fixture();

    let group = prediction_chunks_by_pair(
        &current.spec,
        &current.predictions,
        &[
            TokenKind::LParen,
            TokenKind::Ident,
            TokenKind::RParen,
            TokenKind::Semicolon,
        ],
    )
    .expect("parse grouped expression");
    let call = prediction_chunks_by_pair(
        &current.spec,
        &current.predictions,
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
