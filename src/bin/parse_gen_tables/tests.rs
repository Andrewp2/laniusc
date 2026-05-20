use std::sync::OnceLock;

use super::*;

struct CurrentGrammarFixture {
    spec: GrammarSpec,
    analysis: GrammarAnalysis,
    predictions: Vec<Prediction>,
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
                if input.get(pos).map(|kind| *kind as u32) != Some(token) {
                    bail!(
                        "terminal mismatch at pos {}: expected {:?}, found {:?}",
                        pos,
                        format_token(token),
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
                if input.get(pos).map(|kind| *kind as u32) != Some(token) {
                    bail!(
                        "terminal mismatch at pos {}: expected {:?}, found {:?}",
                        pos,
                        format_token(token),
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
            TokenKind::Fn,
            TokenKind::Ident,
            TokenKind::ParamLParen,
            TokenKind::ParamRParen,
            TokenKind::FnBlockLBrace,
            TokenKind::Return,
            TokenKind::Ident,
            TokenKind::InfixPlus,
            TokenKind::Int,
            TokenKind::ReturnSemicolon,
            TokenKind::FnBlockRBrace,
        ],
    )
    .expect("parse function token stream");

    assert_eq!(tags.first().map(String::as_str), Some("file"));
    assert!(tags.iter().any(|tag| tag == "fn"));
    assert!(tags.iter().any(|tag| tag == "expr"));
    assert!(tags.iter().any(|tag| tag == "ident"));
    assert!(tags.iter().any(|tag| tag == "add_tail"));
    assert!(tags.iter().any(|tag| tag == "int"));
    assert!(tags.iter().any(|tag| tag == "assign_end"));
}

#[test]
fn ll1_predictions_parse_empty_array() {
    let current = current_grammar_fixture();
    let tags = parse_with_predictions(
        &current.spec,
        &current.predictions,
        &[
            TokenKind::Fn,
            TokenKind::Ident,
            TokenKind::ParamLParen,
            TokenKind::ParamRParen,
            TokenKind::FnBlockLBrace,
            TokenKind::Return,
            TokenKind::ArrayLBracket,
            TokenKind::ArrayRBracket,
            TokenKind::ReturnSemicolon,
            TokenKind::FnBlockRBrace,
        ],
    )
    .expect("parse function token stream");

    assert!(tags.iter().any(|tag| tag == "array_lit"));
    assert!(tags.iter().any(|tag| tag == "array_none"));
}

#[test]
fn simple_llp_grammar_builds_paper_style_pair_tables() {
    let spec = parse_grammar(
        "
        %start file;
        file [file_ident] -> 'Ident' 'Semicolon';
        ",
    )
    .expect("parse grammar");
    let analysis = analyze_grammar(&spec);
    assert!(
        !diagnostics_are_fatal(&analysis.diagnostics),
        "{}",
        format_diagnostics(&analysis.diagnostics)
    );
    let predictions = build_ll1_predictions(&spec, &analysis).expect("ll1 predictions");
    let prod_arity = compute_prod_arity(&spec.productions);

    let (tables, projection, witness_inputs) =
        build_projected_precomputed_tables(&spec, &predictions, prod_arity)
            .expect("build paper-style LLP tables");

    assert_eq!(witness_inputs, 0);
    assert!(!projection.sc.cells.is_empty());
    assert!(!projection.pp.cells.is_empty());
    assert!(!tables.sc_superseq.is_empty());
    assert!(!tables.pp_superseq.is_empty());
}

#[test]
fn psls_conflict_report_names_productions_and_gammas() {
    let spec = parse_grammar(
        "
        %start file;
        file [file_item] -> item;
        item [item_impl] -> 'Impl' block;
        block [block] -> 'LBrace' 'RBrace';
        ",
    )
    .expect("parse grammar");
    let conflicts = vec![PslsConflict {
        pair: (TokenKind::RBrace as u32, EOF_TOKEN),
        existing_prod: 1,
        prod: 2,
        existing_gamma: vec![Sym::Terminal(TokenKind::RBrace as u32)],
        gamma: vec![
            Sym::NonTerminal("block".to_string()),
            Sym::Terminal(TokenKind::RBrace as u32),
        ],
    }];

    let report = format_psls_conflicts(&spec, &conflicts, 20);

    assert!(report.contains("(RBrace, $)"), "{report}");
    assert!(report.contains("#1 item [item_impl] line"), "{report}");
    assert!(report.contains("#2 block [block] line"), "{report}");
    assert!(report.contains("existing gamma: 'RBrace'"), "{report}");
    assert!(
        report.contains("incoming gamma: block 'RBrace'"),
        "{report}"
    );
}

#[test]
fn semantic_closing_delimiters_use_distinct_projection_pairs() {
    let current = current_grammar_fixture();

    let group = prediction_chunks_by_pair(
        &current.spec,
        &current.predictions,
        &[
            TokenKind::Fn,
            TokenKind::Ident,
            TokenKind::ParamLParen,
            TokenKind::ParamRParen,
            TokenKind::FnBlockLBrace,
            TokenKind::Return,
            TokenKind::GroupLParen,
            TokenKind::Ident,
            TokenKind::GroupRParen,
            TokenKind::ReturnSemicolon,
            TokenKind::FnBlockRBrace,
        ],
    )
    .expect("parse grouped expression");
    let call = prediction_chunks_by_pair(
        &current.spec,
        &current.predictions,
        &[
            TokenKind::Fn,
            TokenKind::Ident,
            TokenKind::ParamLParen,
            TokenKind::ParamRParen,
            TokenKind::FnBlockLBrace,
            TokenKind::Return,
            TokenKind::Ident,
            TokenKind::CallLParen,
            TokenKind::Ident,
            TokenKind::CallRParen,
            TokenKind::ReturnSemicolon,
            TokenKind::FnBlockRBrace,
        ],
    )
    .expect("parse call expression");

    let group_key = (TokenKind::Ident as u32, TokenKind::GroupRParen as u32);
    let call_key = (TokenKind::Ident as u32, TokenKind::CallRParen as u32);
    let group_chunk = group
        .get(&group_key)
        .expect("group Ident/GroupRParen chunk");
    let call_chunk = call.get(&call_key).expect("call Ident/CallRParen chunk");

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
