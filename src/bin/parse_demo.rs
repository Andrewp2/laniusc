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
        String::from("fn main() { let x = 1 + 2; return x; }")
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
    println!(
        "ll1: accepted={} error_pos={} error_code={} detail={} steps={} emits={}",
        res.ll1.accepted,
        res.ll1.error_pos,
        res.ll1.error_code,
        res.ll1.detail,
        res.ll1.steps,
        res.ll1.emit_len
    );
    println!(
        "ll1_seeded_blocks: n={} block_size={} emit_stride={}",
        res.ll1_seeded_blocks.len(),
        res.ll1_block_size,
        res.ll1_block_emit_stride
    );
    println!(
        "ll1_seed_plan: accepted={} pos={} error_code={} detail={} steps={} seeds={} max_depth={} emits={}",
        res.ll1_seed_plan.accepted,
        res.ll1_seed_plan.pos,
        res.ll1_seed_plan.error_code,
        res.ll1_seed_plan.detail,
        res.ll1_seed_plan.steps,
        res.ll1_seed_plan.seed_count,
        res.ll1_seed_plan.max_depth,
        res.ll1_seed_plan.emit_len
    );
    for (i, block) in res.ll1_seeded_blocks.iter().take(4).enumerate() {
        println!(
            "  seeded_block[{i}] status={} begin={} end={} pos={} steps={} emits={} stack={} err={} first_prod={}",
            block.status,
            block.begin,
            block.end,
            block.pos,
            block.steps,
            block.emit_len,
            block.stack_depth,
            block.error_code,
            block.first_production
        );
    }
    let ll1_to_show = res.ll1_emit_stream.len().min(32);
    print!("ll1_emit_stream[0..{}] = [", ll1_to_show);
    for i in 0..ll1_to_show {
        if i > 0 {
            print!(", ");
        }
        print!("{}", res.ll1_emit_stream[i]);
    }
    println!("]");

    if res.ll1.accepted {
        println!(
            "llp_matches_ll1 = {}",
            res.emit_stream == res.ll1_emit_stream
        );
    }

    // LLP projected emit stream; for covered valid inputs this should match LL(1).
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
