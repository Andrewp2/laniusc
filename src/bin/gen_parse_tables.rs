// src/bin/gen_parse_tables.rs
// Offline generator for the LLP "3 data structures / 7 arrays".
// Reads a very simple grammar file and writes tables/parse_tables.bin.
//
// MVP behavior:
//   * Parses production lines and collects production tags + arities.
//   * Emits bracket-only stack-change sequences (so you can already test file I/O).
//   * Leaves partial-parse sequences empty (to be filled when we wire real LLP generation).
//
// Grammar line examples (subset):
//   expr                -> atom sum;
//   sum [sum_add]       -> 'plus' atom sum;
//   sum [sum_end]       -> ;
//   atom [atom_paren]   -> 'lparen' expr 'rparen';
//
// Notes:
//   - Terminals appear as single-quoted names. For MVP we don’t resolve them to TokenKind;
//     bracket tokens are injected directly, and other token pairs get empty sequences.
//   - Nonterminals are bare identifiers.
//   - Tag is optional; defaults to the LHS nonterminal name.

use std::{env, fs, path::PathBuf};

use laniusc::{
    lexer::tables::tokens::N_KINDS,
    parser::tables::{PrecomputedParseTables, build_mvp_precomputed_tables},
};

#[derive(Debug)]
struct Production {
    _lhs: String,
    tag: String,
    rhs_syms: Vec<Sym>,
}
#[derive(Debug)]
enum Sym {
    Terminal(String),
    NonTerminal(String),
}

fn parse_grammar(src: &str) -> Vec<Production> {
    let mut prods = Vec::new();
    for (line_number, raw_line) in src.lines().enumerate() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        // naive split on "->" and trailing ';'
        let Some((lhs_part, rhs_part0)) = line.split_once("->") else {
            continue;
        };
        let rhs_part = rhs_part0.trim_end_matches(';').trim();

        // lhs may have optional [tag]
        let lhs_part = lhs_part.trim();
        let (lhs_name, tag_opt) = if let Some((lhs, tag_part0)) = lhs_part.split_once('[') {
            let tag = tag_part0.trim_end_matches(']').trim();
            (lhs.trim().to_string(), Some(tag.to_string()))
        } else {
            (lhs_part.to_string(), None)
        };

        let mut rhs_syms = Vec::new();
        for tok in rhs_part.split_whitespace() {
            if tok.starts_with('\'') && tok.ends_with('\'') && tok.len() >= 2 {
                rhs_syms.push(Sym::Terminal(tok.trim_matches('\'').to_string()));
            } else {
                rhs_syms.push(Sym::NonTerminal(tok.to_string()));
            }
        }

        let tag = tag_opt.unwrap_or_else(|| lhs_name.clone());
        prods.push(Production {
            _lhs: lhs_name,
            tag,
            rhs_syms,
        });
        if !line.ends_with(';') {
            eprintln!(
                "[gen_parse_tables] warning: missing ';' at line {}",
                line_number + 1
            );
        }
    }
    prods
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

fn main() -> std::io::Result<()> {
    let grammar_path = env::args()
        .nth(1)
        .unwrap_or_else(|| "grammar/lanius.bnf".to_string());
    let out_path = PathBuf::from("tables/parse_tables.bin");

    let src = fs::read_to_string(&grammar_path)
        .unwrap_or_else(|e| panic!("failed to read grammar at {}: {e}", grammar_path));

    let prods = parse_grammar(&src);
    if prods.is_empty() {
        eprintln!(
            "[gen_parse_tables] warning: parsed zero productions from {}",
            grammar_path
        );
    }

    let prod_arity = compute_prod_arity(&prods);

    // MVP: build a correctly-shaped set of tables (brackets only, empty partial parses),
    // using the number of token kinds currently defined in the lexer.
    let tables: PrecomputedParseTables = build_mvp_precomputed_tables(N_KINDS, prod_arity);

    // Save to disk.
    if let Some(parent) = out_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    tables.save_bin(&out_path)?;
    println!("[gen_parse_tables] wrote {}", out_path.display());
    Ok(())
}
