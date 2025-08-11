// src/bin/gen_tables.rs
// Build full-grammar lexer tables once and write them to disk.
// Usage:
//   cargo run --bin gen_tables                # writes tables/lexer_tables.bin
//   cargo run --bin gen_tables -- json       # also writes tables/lexer_tables.json
//   cargo run --bin gen_tables -- /path/out.bin

use laniusc::lexer::tables::{INVALID_TOKEN, build_tables, save_tables_bin, save_tables_json};
use std::{env, fs, path::Path};

fn main() {
    let mut args = env::args().skip(1).collect::<Vec<_>>();
    let write_json = args.iter().any(|a| a == "json");

    // pick output
    let out = args
        .iter()
        .find(|a| a.as_str().ends_with(".bin"))
        .cloned()
        .unwrap_or_else(|| "tables/lexer_tables.bin".to_string());
    let out_path = Path::new(&out);

    if let Some(parent) = out_path.parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            eprintln!("error: failed to create {}: {e}", parent.display());
            std::process::exit(1);
        }
    }

    println!("[gen_tables] building full grammar tables…");
    let t = build_tables();

    let m = t.m as u64;
    let merge_bytes_u32 = m * m * 4;
    let token_kinds = t.token_of.iter().filter(|&&k| k != INVALID_TOKEN).count();
    println!(
        "[gen_tables] m = {} funcs, merge (u32) = {} bytes (~{} MiB), token_kinds seen = {}",
        m,
        merge_bytes_u32,
        merge_bytes_u32 / (1024 * 1024),
        token_kinds
    );

    if let Err(e) = save_tables_bin(out_path, &t) {
        eprintln!("error: failed to write {}: {e}", out_path.display());
        std::process::exit(1);
    }
    println!("[gen_tables] wrote {}", out_path.display());

    if write_json {
        let json_path = out_path.with_extension("json");
        if let Err(e) = save_tables_json(&json_path, &t) {
            eprintln!(
                "warning: failed to also write JSON {}: {e}",
                json_path.display()
            );
        } else {
            println!("[gen_tables] also wrote {}", json_path.display());
        }
    }

    println!("tip: commit the .bin and `cargo build` — build.rs will embed it.");
}
