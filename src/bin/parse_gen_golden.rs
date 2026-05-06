// src/bin/parse_gen_golden.rs
//
// Generate CPU goldens for files in parser_tests/ (or given paths).
// Now emits the FULL CPU AST (from src/parser/cpu.rs) in addition to the existing
// bracket truth used by parse_fuzz. The JSON looks like:
//
// {
//   "brackets": {...},
//   "sc_canon": [...],
//   "match_for_index": [...],
//   "tree": { "node_kind": [...], "parent": [...] },   // back-compat shape-only
//   "ast":  { "root": N, "nodes": [ { "tag": "...", "children": [...] }, ... ] },
//   "hir":  { "items": [...] },
//   "token_kinds": ["Ident","CallLParen", ...]         // optional, for debugging
// }
//
// Usage:
//   cargo run --bin parse_gen_golden
//   cargo run --bin parse_gen_golden -- parser_tests/tricky_combo.lani

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use laniusc::{
    hir::{HirFile, parse_source},
    lexer::{gpu::driver::GpuLexer, tables::tokens},
    parser::cpu::{Ast, parse_from_token_kinds},
};
use serde::{Deserialize, Serialize};

// ------------------- legacy structs kept for back-compat -------------------

#[derive(Serialize, Deserialize, Clone, Copy)]
struct Brackets {
    valid: bool,
    final_depth: i32,
    min_depth: i32,
}

#[derive(Serialize, Deserialize)]
struct CpuTree {
    node_kind: Vec<u32>, // 0 = paren '()', 1 = bracket '[]'
    parent: Vec<u32>,    // 0xFFFF_FFFF for root
}

#[derive(Serialize)]
struct CpuOnlyGolden {
    cpu_only: bool,
    brackets: Brackets,
    sc_canon: Vec<u32>,
    match_for_index: Vec<u32>,
    tree: CpuTree,

    // Full CPU AST and lowered HIR.
    ast: Ast,
    hir: HirFile,

    // Optional: human-friendly token names for debugging diffs
    token_kinds: Vec<String>,
}

// ------------------- input collection -------------------

fn collect_inputs_from_dir(dir: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(rd) = std::fs::read_dir(dir) {
        for ent in rd.flatten() {
            let p = ent.path();
            if p.extension().and_then(|e| e.to_str()) == Some("lani") {
                out.push(p);
            }
        }
        out.sort();
    }
    out
}

fn sidecar_path_for(p: &Path) -> PathBuf {
    let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("case");
    let dir = p.parent().unwrap_or_else(|| Path::new("."));
    dir.join(format!("{stem}.parse.json"))
}

// ------------------- bracket-only canonical truth from raw text -------------------
//
// This keeps compatibility with parse_fuzz’s CPU-only checks.

fn cpu_reference_brackets_from_src(src: &str) -> (Brackets, Vec<u32>, Vec<u32>, CpuTree) {
    // Canonical codes: '(' / ')' => type 0, '[' / ']' => type 1
    // code = (type << 1) | is_push, with push=1, pop=0
    let mut sc_canon: Vec<u32> = Vec::with_capacity(src.len());
    let mut match_for_index: Vec<u32> = Vec::with_capacity(src.len());
    let mut stack_idx: Vec<(char, usize)> = Vec::new();

    let mut depth: i32 = 0;
    let mut min_depth: i32 = 0;
    let mut valid = true;

    let ty = |ch: char| -> u32 { if ch == '(' || ch == ')' { 0 } else { 1 } };

    for ch in src.chars() {
        match ch {
            '(' | '[' => {
                sc_canon.push((ty(ch) << 1) | 1);
                match_for_index.push(0xFFFF_FFFF);
                stack_idx.push((ch, sc_canon.len() - 1));
                depth += 1;
                if depth < min_depth {
                    min_depth = depth;
                }
            }
            ')' | ']' => {
                sc_canon.push((ty(ch) << 1) | 0);
                match_for_index.push(0xFFFF_FFFF);
                if depth <= 0 || stack_idx.is_empty() {
                    valid = false;
                    depth -= 1;
                    if depth < min_depth {
                        min_depth = depth;
                    }
                } else {
                    let (open_ch, open_i) = stack_idx.pop().unwrap();
                    depth -= 1;
                    if depth < min_depth {
                        min_depth = depth;
                    }
                    let matched = (open_ch == '(' && ch == ')') || (open_ch == '[' && ch == ']');
                    if !matched {
                        valid = false;
                    }
                    let close_i = sc_canon.len() - 1;
                    match_for_index[open_i] = close_i as u32;
                    match_for_index[close_i] = open_i as u32;
                }
            }
            _ => {}
        }
    }
    if !stack_idx.is_empty() {
        valid = false;
    }

    // Build “one node per open” shape tree (for compatibility checks).
    let mut node_kind: Vec<u32> = Vec::new();
    let mut parent: Vec<u32> = Vec::new();
    let mut node_stack: Vec<usize> = Vec::new();

    for &code in &sc_canon {
        let is_push = (code & 1) == 1;
        let kind = code >> 1; // 0 paren, 1 bracket
        if is_push {
            let this = node_kind.len();
            node_kind.push(kind);
            let p = if let Some(&up) = node_stack.last() {
                up as u32
            } else {
                0xFFFF_FFFF
            };
            parent.push(p);
            node_stack.push(this);
        } else {
            let _ = node_stack.pop();
        }
    }

    (
        Brackets {
            valid,
            final_depth: depth,
            min_depth,
        },
        sc_canon,
        match_for_index,
        CpuTree { node_kind, parent },
    )
}

// ------------------- run one file -------------------

async fn run_one(lexer: &GpuLexer, path: &Path) -> Result<()> {
    let src = std::fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;

    // Legacy bracket truth (by raw text)
    let (brackets, sc_canon, match_for_index, tree) = cpu_reference_brackets_from_src(&src);

    // Tokens via existing GPU lexer → TokenKind stream for CPU parser
    let toks = lexer.lex(&src).await.context("lex GPU")?;
    let kinds: Vec<tokens::TokenKind> = toks.iter().map(|t| t.kind).collect();
    let token_kinds: Vec<String> = kinds.iter().map(|k| format!("{:?}", k)).collect();

    // Full CPU parse and lowered HIR.
    let ast: Ast =
        parse_from_token_kinds(&kinds).map_err(|e| anyhow::anyhow!("CPU parse failed: {}", e))?;
    let hir: HirFile =
        parse_source(&src).map_err(|e| anyhow::anyhow!("HIR parse failed: {}", e))?;

    // Serialize
    let golden = CpuOnlyGolden {
        cpu_only: true,
        brackets,
        sc_canon,
        match_for_index,
        tree,
        ast,
        hir,
        token_kinds,
    };

    let out_path = sidecar_path_for(path);
    let s = serde_json::to_string_pretty(&golden)?;
    std::fs::write(&out_path, s)?;
    println!("[golden] wrote {}", out_path.display());
    Ok(())
}

// ------------------- main -------------------

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();

    let inputs: Vec<PathBuf> = if args.is_empty() {
        collect_inputs_from_dir("parser_tests")
    } else {
        args.into_iter().map(PathBuf::from).collect()
    };
    if inputs.is_empty() {
        anyhow::bail!("no inputs found");
    }

    // One GPU lexer, reused for all files.
    let lexer = pollster::block_on(GpuLexer::new()).context("init GpuLexer")?;

    let mut ok = 0usize;
    for p in inputs {
        match pollster::block_on(run_one(&lexer, &p)) {
            Ok(()) => ok += 1,
            Err(e) => eprintln!("[golden] skip {}: {}", p.display(), e),
        }
    }
    println!("[golden] finished: wrote {} files", ok);
    Ok(())
}
