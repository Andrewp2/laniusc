use std::{collections::HashMap, fmt::Write};

use anyhow::{Context, Result, anyhow, bail, ensure};
use laniusc_compiler::{
    lexer::tables::tokens::TokenKind,
    parser::tables::{INVALID_TABLE_ENTRY, PrecomputedParseTables},
};

use crate::artifact::{ParseChild, ParseNode, Token};

const PARSE_TABLES: &[u8] = include_bytes!("../../../tables/parse_tables.bin");
const PACKED_GENERIC_CLOSE: u32 = 0x8000_0000;
const PACKED_KIND_MASK: u32 = 0x7fff;

#[derive(Debug)]
pub struct ParseExtraction {
    pub semantic_token_kinds: Vec<u32>,
    pub nodes: Vec<ParseNode>,
    pub root: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct StateKey {
    production: u32,
    dot: u32,
    origin: usize,
}

#[derive(Debug, Clone)]
enum InternalChild {
    Token { id: u32, semantic_kind: u32 },
    Node(u32),
}

#[derive(Debug, Clone)]
struct State {
    key: StateKey,
    children: Vec<InternalChild>,
    completed_node: Option<u32>,
}

#[derive(Debug, Default)]
struct Chart {
    states: Vec<State>,
    by_key: HashMap<StateKey, usize>,
}

impl Chart {
    fn insert(&mut self, key: StateKey, children: Vec<InternalChild>) -> bool {
        if self.by_key.contains_key(&key) {
            return false;
        }
        let index = self.states.len();
        self.states.push(State {
            key,
            children,
            completed_node: None,
        });
        self.by_key.insert(key, index);
        true
    }
}

#[derive(Debug, Clone)]
struct InternalNode {
    production: u32,
    nonterminal: u32,
    position_start: u32,
    position_end: u32,
    children: Vec<InternalChild>,
}

fn production_lhs(tables: &PrecomputedParseTables) -> Result<Vec<u32>> {
    let mut lhs = vec![None; tables.n_productions as usize];
    for nonterminal in 0..tables.n_nonterminals {
        let row = nonterminal as usize * tables.n_kinds as usize;
        for &production in &tables.ll1_predict[row..row + tables.n_kinds as usize] {
            if production == INVALID_TABLE_ENTRY {
                continue;
            }
            let slot = lhs
                .get_mut(production as usize)
                .context("prediction references an out-of-range production")?;
            match *slot {
                None => *slot = Some(nonterminal),
                Some(previous) => ensure!(
                    previous == nonterminal,
                    "production {production} is predicted for nonterminals {previous} and {nonterminal}"
                ),
            }
        }
    }
    lhs.into_iter()
        .enumerate()
        .map(|(production, nonterminal)| {
            nonterminal.ok_or_else(|| anyhow!("production {production} has no prediction row"))
        })
        .collect()
}

fn productions_by_lhs(tables: &PrecomputedParseTables, lhs: &[u32]) -> Vec<Vec<u32>> {
    let mut productions = vec![Vec::new(); tables.n_nonterminals as usize];
    for (production, &nonterminal) in lhs.iter().enumerate() {
        productions[nonterminal as usize].push(production as u32);
    }
    productions
}

fn production_rhs<'a>(tables: &'a PrecomputedParseTables, production: u32) -> Result<&'a [u32]> {
    let offset = *tables
        .prod_rhs_off
        .get(production as usize)
        .context("production offset is missing")? as usize;
    let length = *tables
        .prod_rhs_len
        .get(production as usize)
        .context("production length is missing")? as usize;
    tables
        .prod_rhs
        .get(offset..offset + length)
        .context("production RHS is out of bounds")
}

/// Advances through the physical-token lattice. Even positions are ordinary
/// token boundaries. An odd position is the boundary between the two virtual
/// generic closes represented by one physical `>>` token.
fn scan_terminal(tokens: &[Token], position: usize, semantic_kind: u32) -> Option<usize> {
    let kind = TokenKind::from_u32(semantic_kind)?;
    let canonical = kind.canonical_lexer_kind() as u32;
    let token_index = position / 2;
    let token = tokens.get(token_index)?;

    if position % 2 == 1 {
        return (token.kind == TokenKind::Shr as u32 && canonical == TokenKind::Gt as u32)
            .then_some(position + 1);
    }
    if token.kind == canonical {
        return Some(position + 2);
    }
    (token.kind == TokenKind::Shr as u32 && canonical == TokenKind::Gt as u32)
        .then_some(position + 1)
}

fn materialize_node(
    internal_id: u32,
    internal: &[InternalNode],
    output: &mut Vec<ParseNode>,
    semantic_by_token: &mut [Vec<u32>],
) -> Result<u32> {
    let node = internal
        .get(internal_id as usize)
        .context("internal parse node is missing")?;
    let mut children = Vec::with_capacity(node.children.len());
    for child in &node.children {
        match *child {
            InternalChild::Token { id, semantic_kind } => {
                semantic_by_token
                    .get_mut(id as usize)
                    .context("parse node references an out-of-range token")?
                    .push(semantic_kind);
                children.push(ParseChild::Token(id));
            }
            InternalChild::Node(child_id) => {
                children.push(ParseChild::Node(materialize_node(
                    child_id,
                    internal,
                    output,
                    semantic_by_token,
                )?));
            }
        }
    }
    let output_id = u32::try_from(output.len()).context("parse tree exceeds u32 node IDs")?;
    output.push(ParseNode {
        production: node.production,
        nonterminal: node.nonterminal,
        position_start: node.position_start,
        position_end: node.position_end,
        children,
    });
    Ok(output_id)
}

fn encode_semantic_kinds(tokens: &[Token], assignments: Vec<Vec<u32>>) -> Result<Vec<u32>> {
    tokens
        .iter()
        .zip(assignments)
        .enumerate()
        .map(|(index, (token, kinds))| match kinds.as_slice() {
            [kind] => Ok(*kind),
            [inner, outer]
                if token.kind == TokenKind::Shr as u32
                    && TokenKind::from_u32(*inner)
                        .is_some_and(|kind| kind.canonical_lexer_kind() == TokenKind::Gt)
                    && TokenKind::from_u32(*outer)
                        .is_some_and(|kind| kind.canonical_lexer_kind() == TokenKind::Gt) =>
            {
                Ok(PACKED_GENERIC_CLOSE
                    | (*inner & PACKED_KIND_MASK)
                    | ((*outer & PACKED_KIND_MASK) << 15))
            }
            [] => bail!("token {index} was not consumed by the parse"),
            _ => bail!("token {index} has an invalid semantic expansion {kinds:?}"),
        })
        .collect()
}

fn parse_with_tables(tokens: &[Token], tables: &PrecomputedParseTables) -> Result<ParseExtraction> {
    ensure!(
        tables.n_nonterminals > 0,
        "parse tables have no nonterminals"
    );
    let lhs = production_lhs(tables)?;
    let by_lhs = productions_by_lhs(tables, &lhs);
    let final_position = tokens
        .len()
        .checked_mul(2)
        .context("token lattice overflow")?;
    let mut charts: Vec<Chart> = (0..=final_position).map(|_| Chart::default()).collect();
    let mut internal_nodes = Vec::<InternalNode>::new();

    for &production in &by_lhs[tables.start_nonterminal as usize] {
        charts[0].insert(
            StateKey {
                production,
                dot: 0,
                origin: 0,
            },
            Vec::new(),
        );
    }

    for position in 0..=final_position {
        let mut index = 0;
        while index < charts[position].states.len() {
            let state = charts[position].states[index].clone();
            let rhs = production_rhs(tables, state.key.production)?;
            if (state.key.dot as usize) < rhs.len() {
                let symbol = rhs[state.key.dot as usize];
                if symbol < tables.n_kinds {
                    if let Some(next_position) = scan_terminal(tokens, position, symbol) {
                        let mut children = state.children.clone();
                        children.push(InternalChild::Token {
                            id: u32::try_from(position / 2).context("token ID exceeds u32")?,
                            semantic_kind: symbol,
                        });
                        charts[next_position].insert(
                            StateKey {
                                dot: state.key.dot + 1,
                                ..state.key
                            },
                            children,
                        );
                    }
                } else {
                    let nonterminal = symbol - tables.n_kinds;
                    let productions = by_lhs
                        .get(nonterminal as usize)
                        .context("RHS references an out-of-range nonterminal")?;
                    for &production in productions {
                        charts[position].insert(
                            StateKey {
                                production,
                                dot: 0,
                                origin: position,
                            },
                            Vec::new(),
                        );
                    }

                    let completed: Vec<u32> = charts[position]
                        .states
                        .iter()
                        .filter_map(|candidate| {
                            let candidate_lhs = lhs[candidate.key.production as usize];
                            let candidate_rhs =
                                production_rhs(tables, candidate.key.production).ok()?;
                            (candidate_lhs == nonterminal
                                && candidate.key.origin == position
                                && candidate.key.dot as usize == candidate_rhs.len())
                            .then_some(candidate.completed_node)
                            .flatten()
                        })
                        .collect();
                    for child_id in completed {
                        let mut children = state.children.clone();
                        children.push(InternalChild::Node(child_id));
                        charts[position].insert(
                            StateKey {
                                dot: state.key.dot + 1,
                                ..state.key
                            },
                            children,
                        );
                    }
                }
            } else {
                let node_id = match state.completed_node {
                    Some(node_id) => node_id,
                    None => {
                        let node_id = u32::try_from(internal_nodes.len())
                            .context("internal parse tree exceeds u32 node IDs")?;
                        internal_nodes.push(InternalNode {
                            production: state.key.production,
                            nonterminal: lhs[state.key.production as usize],
                            position_start: u32::try_from(state.key.origin)
                                .context("parse position start exceeds u32")?,
                            position_end: u32::try_from(position)
                                .context("parse position end exceeds u32")?,
                            children: state.children.clone(),
                        });
                        charts[position].states[index].completed_node = Some(node_id);
                        node_id
                    }
                };
                let completed_lhs = lhs[state.key.production as usize];
                let parents = charts[state.key.origin].states.clone();
                for parent in parents {
                    let parent_rhs = production_rhs(tables, parent.key.production)?;
                    let Some(&expected) = parent_rhs.get(parent.key.dot as usize) else {
                        continue;
                    };
                    if expected != tables.n_kinds + completed_lhs {
                        continue;
                    }
                    let mut children = parent.children;
                    children.push(InternalChild::Node(node_id));
                    charts[position].insert(
                        StateKey {
                            dot: parent.key.dot + 1,
                            ..parent.key
                        },
                        children,
                    );
                }
            }
            index += 1;
        }
    }

    let root_internal = charts[final_position]
        .states
        .iter()
        .find_map(|state| {
            let production = state.key.production as usize;
            let complete = production_rhs(tables, state.key.production)
                .is_ok_and(|rhs| state.key.dot as usize == rhs.len());
            (state.key.origin == 0
                && lhs[production] == tables.start_nonterminal
                && complete)
                .then_some(state.completed_node)
                .flatten()
        })
        .ok_or_else(|| {
            let furthest = charts
                .iter()
                .rposition(|chart| !chart.states.is_empty())
                .unwrap_or(0);
            let token_index = furthest / 2;
            let raw_kind = tokens.get(token_index).map(|token| token.kind);
            anyhow!(
                "source does not match the Lanius grammar at token lattice position {furthest} (token {token_index}, raw kind {raw_kind:?}, {} states)",
                charts[furthest].states.len()
            )
        })?;

    let mut nodes = Vec::new();
    let mut semantic_by_token = vec![Vec::new(); tokens.len()];
    let root = materialize_node(
        root_internal,
        &internal_nodes,
        &mut nodes,
        &mut semantic_by_token,
    )?;
    let semantic_token_kinds = encode_semantic_kinds(tokens, semantic_by_token)?;
    Ok(ParseExtraction {
        semantic_token_kinds,
        nodes,
        root,
    })
}

pub fn parse_tokens(tokens: &[Token]) -> Result<ParseExtraction> {
    let tables =
        PrecomputedParseTables::load_bin_bytes(PARSE_TABLES).map_err(|message| anyhow!(message))?;
    parse_with_tables(tokens, &tables)
}

/// Renders the immutable production table as reviewed Lean source. The
/// generated file is part of the formal language definition; this untrusted
/// generator is only a convenience for producing a diff when the grammar
/// intentionally changes.
pub fn render_lean_grammar() -> Result<String> {
    let tables =
        PrecomputedParseTables::load_bin_bytes(PARSE_TABLES).map_err(|message| anyhow!(message))?;
    let lhs = production_lhs(&tables)?;
    let mut output = String::new();
    writeln!(
        output,
        "-- This file is generated by `cargo run -p laniusc-formal-export --bin generate-lean-grammar`."
    )?;
    writeln!(
        output,
        "-- Its checked-in contents are part of the trusted formal grammar."
    )?;
    writeln!(output, "import Lanius.Extraction.Grammar\n")?;
    writeln!(output, "namespace Lanius.Extraction\n")?;
    writeln!(output, "def laniusGrammar : Grammar := {{")?;
    writeln!(output, "  n_kinds := {}", tables.n_kinds)?;
    writeln!(output, "  n_nonterminals := {}", tables.n_nonterminals)?;
    writeln!(
        output,
        "  start_nonterminal := {}",
        tables.start_nonterminal
    )?;
    writeln!(output, "  split_token_kind := {}", TokenKind::Shr as u32)?;
    writeln!(output, "  split_component_kind := {}", TokenKind::Gt as u32)?;
    let canonical_kinds = std::iter::once(0)
        .chain(
            TokenKind::ALL
                .iter()
                .map(|kind| kind.canonical_lexer_kind() as u32),
        )
        .map(|kind| kind.to_string())
        .collect::<Vec<_>>()
        .join(", ");
    writeln!(output, "  canonical_kinds := [{canonical_kinds}]")?;
    writeln!(output, "  productions := [")?;
    for production in 0..tables.n_productions {
        let rhs = production_rhs(&tables, production)?;
        let symbols = rhs
            .iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(", ");
        writeln!(
            output,
            "    ⟨{}, [{}]⟩, -- production {}",
            lhs[production as usize], symbols, production
        )?;
    }
    writeln!(output, "  ]")?;
    writeln!(output, "}}\n")?;
    writeln!(output, "end Lanius.Extraction")?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::extract_tokens;

    #[test]
    fn parses_real_verified_lexer_source_without_context_special_cases() {
        let source = include_bytes!("../../../verified_compiler/src/verified/digits.lani").to_vec();
        let (_, _, tokens) = extract_tokens("digits.lani".into(), source).unwrap();
        let parsed = parse_tokens(&tokens).unwrap();

        assert_eq!(parsed.semantic_token_kinds.len(), tokens.len());
        assert_eq!(parsed.root as usize + 1, parsed.nodes.len());
        let root = &parsed.nodes[parsed.root as usize];
        assert_eq!(root.position_start, 0);
        assert_eq!(root.position_end as usize, tokens.len() * 2);
    }

    #[test]
    fn checked_in_formal_grammar_matches_the_parser_table() {
        assert_eq!(
            render_lean_grammar().unwrap(),
            include_str!("../../../formal/Lanius/Extraction/GeneratedGrammar.lean")
        );
    }
}
