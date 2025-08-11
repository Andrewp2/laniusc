// src/bin/gen_tables.rs
// Build full-grammar lexer tables once and write them to JSON.
// Usage:
//   cargo run --bin gen_tables                # writes tables/lexer_tables.json
//   cargo run --bin gen_tables -- /path/out.json

use laniusc::lexer::tables::{INVALID_TOKEN, build_tables, save_tables_json};
use std::{env, fs, path::Path};

fn main() {
    // Resolve output path
    let out = env::args()
        .nth(1)
        .unwrap_or_else(|| "tables/lexer_tables.json".to_string());
    let out_path = Path::new(&out);

    // Ensure parent dir exists
    if let Some(parent) = out_path.parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            eprintln!("error: failed to create {}: {e}", parent.display());
            std::process::exit(1);
        }
    }

    // Build full-grammar tables (covers all 256 byte generators)
    println!("[gen_tables] building full grammar tables…");
    let t = build_tables();

    // Some stats
    let m = t.m as u64;
    let merge_bytes = m * m * 4;
    let token_kinds = t.token_of.iter().filter(|&&k| k != INVALID_TOKEN).count();
    println!(
        "[gen_tables] m = {} funcs, merge = {} bytes (~{} KiB, ~{} MiB), token_kinds seen = {}",
        m,
        merge_bytes,
        merge_bytes / 1024,
        merge_bytes / (1024 * 1024),
        token_kinds
    );

    // Write
    if let Err(e) = save_tables_json(out_path, &t) {
        eprintln!("error: failed to write {}: {e}", out_path.display());
        std::process::exit(1);
    }
    println!("[gen_tables] wrote {}", out_path.display());
    println!("         tip: commit this file and then `cargo build` — build.rs will embed it.");
}
