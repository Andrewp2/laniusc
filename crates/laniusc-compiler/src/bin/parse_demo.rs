// src/bin/parse_demo.rs
use anyhow::Result;
use laniusc_compiler::{
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
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
    if std::env::var_os("LANIUS_PARSE_DEMO_TOKENS").is_some() {
        for (i, t) in tokens.iter().enumerate() {
            println!(
                "token[{i}] kind={} start={} len={} text={:?}",
                t.kind as u32,
                t.start,
                t.len,
                &input[t.start..t.start + t.len]
            );
        }
    }
    // Add sentinels: START and END, so the first token participates in a pair.
    token_kinds_u32.insert(0, 0);
    token_kinds_u32.push(0);

    // 2) Tables: require the generated GPU parser tables.
    let bytes = std::fs::read("tables/parse_tables.bin")?;
    let tables = PrecomputedParseTables::load_bin_bytes(&bytes)
        .map_err(|err| anyhow::anyhow!("load tables/parse_tables.bin: {err}"))?;
    println!("[parse_demo] using tables/parse_tables.bin");

    // 3) GPU parser (pairs → headers → pack → brackets → tree)
    let parser = GpuParser::new().await?;
    if std::env::var_os("LANIUS_PARSE_DEMO_RESIDENT").is_some() {
        let parsed = lexer
            .with_resident_tokens(&input, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await??;
        println!(
            "resident ll1: accepted={} error_pos={} error_code={} detail={} steps={} emits={}",
            parsed.ll1.accepted,
            parsed.ll1.error_pos,
            parsed.ll1.error_code,
            parsed.ll1.detail,
            parsed.ll1.steps,
            parsed.ll1.emit_len
        );
        println!("resident nodes: {}", parsed.node_kind.len());
        for i in 0..parsed.node_kind.len().min(16) {
            println!(
                "  node[{i}] kind={} parent={}",
                parsed.node_kind[i], parsed.parent[i]
            );
        }
        if std::env::var_os("LANIUS_PARSE_DEMO_FULL").is_some() {
            for (i, &kind) in parsed.node_kind.iter().enumerate() {
                let hir = parsed.hir_kind.get(i).copied().unwrap_or(u32::MAX);
                let pos = parsed.hir_token_pos.get(i).copied().unwrap_or(u32::MAX);
                let end = parsed.hir_token_end.get(i).copied().unwrap_or(u32::MAX);
                let parent = parsed.parent.get(i).copied().unwrap_or(u32::MAX);
                let first_child = parsed.first_child.get(i).copied().unwrap_or(u32::MAX);
                let next_sibling = parsed.next_sibling.get(i).copied().unwrap_or(u32::MAX);
                let subtree_end = parsed.subtree_end.get(i).copied().unwrap_or(u32::MAX);
                let callee = parsed
                    .hir_call_callee_node
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let arg_start = parsed
                    .hir_call_arg_start
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let arg_end = parsed.hir_call_arg_end.get(i).copied().unwrap_or(u32::MAX);
                let arg_count = parsed
                    .hir_call_arg_count
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let array_first = parsed
                    .hir_array_lit_first_element
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let array_count = parsed
                    .hir_array_lit_element_count
                    .get(i)
                    .copied()
                    .unwrap_or(0);
                let array_parent = parsed
                    .hir_array_element_parent_lit
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let array_ordinal = parsed
                    .hir_array_element_ordinal
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let array_next = parsed
                    .hir_array_element_next
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let match_arm_start = parsed
                    .hir_match_arm_start
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let match_arm_count = parsed.hir_match_arm_count.get(i).copied().unwrap_or(0);
                let match_pattern = parsed
                    .hir_match_arm_pattern_node
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let match_payload_start = parsed
                    .hir_match_arm_payload_start
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let match_payload_count = parsed
                    .hir_match_arm_payload_count
                    .get(i)
                    .copied()
                    .unwrap_or(0);
                let match_result = parsed
                    .hir_match_arm_result_node
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let match_next = parsed
                    .hir_match_arm_next
                    .get(i)
                    .copied()
                    .unwrap_or(u32::MAX);
                let token_text = tokens
                    .get(pos as usize)
                    .map(|t| &input[t.start..t.start + t.len])
                    .unwrap_or("");
                println!(
                    "  node[{i}] prod={kind} hir={hir} pos={pos} end={end} parent={parent} child={first_child} next={next_sibling} subtree_end={subtree_end} callee={callee} args=({arg_start},{arg_end},{arg_count}) array=({array_first},{array_count},{array_parent},{array_ordinal},{array_next}) match=({match_arm_start},{match_arm_count}) arm=({match_pattern},{match_payload_start},{match_payload_count},{match_result},{match_next}) token={token_text:?}"
                );
            }
        }
        return Ok(());
    }

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
    if std::env::var_os("LANIUS_PARSE_DEMO_FULL").is_some() {
        for (i, &kind) in res.node_kind.iter().enumerate() {
            let hir = res.hir_kind.get(i).copied().unwrap_or(u32::MAX);
            let pos = res.hir_token_pos.get(i).copied().unwrap_or(u32::MAX);
            let end = res.hir_token_end.get(i).copied().unwrap_or(u32::MAX);
            let parent = res.parent.get(i).copied().unwrap_or(u32::MAX);
            let first_child = res.first_child.get(i).copied().unwrap_or(u32::MAX);
            let next_sibling = res.next_sibling.get(i).copied().unwrap_or(u32::MAX);
            let subtree_end = res.subtree_end.get(i).copied().unwrap_or(u32::MAX);
            let token_text = tokens
                .get(pos as usize)
                .map(|t| &input[t.start..t.start + t.len])
                .unwrap_or("");
            println!(
                "  node[{i}] prod={kind} hir={hir} pos={pos} end={end} parent={parent} child={first_child} next={next_sibling} subtree_end={subtree_end} token={token_text:?}"
            );
        }
    }

    Ok(())
}
