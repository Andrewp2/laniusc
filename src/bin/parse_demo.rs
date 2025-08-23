// src/bin/parse_demo.rs
use anyhow::Result;
use laniusc::{
    lexer::{gpu::driver::GpuLexer, tables::tokens},
    parser::{
        gpu::driver::GpuParser,
        tables::{self as parse_tables, PrecomputedParseTables},
    },
};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    // Pick a small sample; allow overriding with CLI arg.
    let args: Vec<String> = std::env::args().collect();
    let input = if args.len() > 1 {
        std::fs::read_to_string(&args[1])?
    } else {
        // Default to a tiny expression touching (), [], and literals
        String::from("foo(1, 2)[0] [1,2,3,] (bar)")
    };

    // 1) GPU lex
    let lexer = GpuLexer::new().await?;
    let tokens = lexer.lex(&input).await?;

    // Build token_kinds (post-retag) from tokens_out; append a sentinel 0.
    if tokens.is_empty() {
        eprintln!(
            "[parse_demo] got 0 tokens. Ensure LANIUS_READBACK=1 (default) and input has tokens."
        );
    }
    let mut token_kinds_u32: Vec<u32> = Vec::with_capacity(tokens.len() + 1);
    for t in &tokens {
        token_kinds_u32.push(t.kind as u32);
    }
    // Add sentinels: START and END, so the first token participates in a pair.
    token_kinds_u32.insert(0, 0);
    token_kinds_u32.push(0);

    // 2) Tables: prefer generated file tables/parse_tables.bin; fallback to MVP tables
    let n_kinds = tokens::N_KINDS;
    let tables = match std::fs::read("tables/parse_tables.bin") {
        Ok(bytes) => match PrecomputedParseTables::load_bin_bytes(&bytes) {
            Ok(t) => {
                println!("[parse_demo] using tables/parse_tables.bin");
                t
            }
            Err(e) => {
                eprintln!("[parse_demo] failed to load parse_tables.bin: {e}; using MVP tables");
                parse_tables::build_mvp_precomputed_tables(n_kinds, vec![])
            }
        },
        Err(_) => {
            eprintln!("[parse_demo] tables/parse_tables.bin not found; using MVP tables");
            parse_tables::build_mvp_precomputed_tables(n_kinds, vec![])
        }
    };

    // 3) GPU parser (pairs → headers → pack → brackets → tree)
    let parser = GpuParser::new().await?;
    let res = parser.parse(&token_kinds_u32, &tables).await?;

    // Sanity checks per milestone
    println!(
        "headers.len = {} (expect n_tokens-1 = {})",
        res.headers.len(),
        token_kinds_u32.len().saturating_sub(1)
    );
    println!(
        "brackets: valid={} final_depth={} min_depth={}",
        res.brackets.valid, res.brackets.final_depth, res.brackets.min_depth
    );

    // Emit stream is the left-most derivation for MVP tables (likely empty)
    let to_show = res.emit_stream.len().min(32);
    print!("emit_stream[0..{}] = [", to_show);
    for i in 0..to_show {
        if i > 0 {
            print!(", ");
        }
        print!("{}", res.emit_stream[i]);
    }
    println!("]");

    // NEW: quick tree summary (now part of ParseResult)
    println!("nodes: {}", res.node_kind.len());
    for i in 0..res.node_kind.len().min(16) {
        println!(
            "  node[{i}] kind={} parent={}",
            res.node_kind[i], res.parent[i]
        );
    }

    Ok(())
}
