//! Recount EMIT/EOF/ALL/KEPT on the host using the compact tables.
//! Usage: cargo run --bin recount_compact -- <path-to-input-file>

use std::{env, fs};

use laniusc::lexer::gpu::debug_host::recount_tables_host;

fn main() {
    let path = env::args().nth(1).expect("pass a file path");
    let data = fs::read(&path).expect("read file");
    let counts = recount_tables_host(&data).expect("host recount");

    let kb = (data.len() as f64) / 1024.0;
    println!(
        "[dbg host] {} bytes ({:.1} KiB): EMIT={} ({:.2}/KiB)  EOF={} ({:.4}/KiB)  ALL={}  KEPT={}  mismatches={}",
        data.len(),
        kb,
        counts.emit,
        (counts.emit as f64) / kb.max(1e-9),
        counts.eof,
        (counts.eof as f64) / kb.max(1e-9),
        counts.all,
        counts.kept,
        counts.emit_kind_mismatch
    );
}
