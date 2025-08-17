// src/bin/parse_demo.rs
use std::{env, fs, path::PathBuf, time::Instant};

use laniusc::{
    lexer::gpu::driver::lex_on_gpu,
    parser::{gpu::GpuParser, tables::PrecomputedParseTables},
};

fn ensure_parse_tables_bin() {
    let path = PathBuf::from("tables/parse_tables.bin");
    if path.exists() {
        return;
    }
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let n_kinds = laniusc::lexer::tables::tokens::N_KINDS;
    let tables = laniusc::parser::tables::build_mvp_precomputed_tables(n_kinds, Vec::new());
    tables
        .save_bin(&path)
        .expect("write tables/parse_tables.bin");
    println!("[parse_demo] generated {}", path.display());
}

fn load_or_generate() -> (String, String) {
    if let Some(path) = env::args().nth(1) {
        let p = PathBuf::from(&path);
        let t0 = Instant::now();
        let src = fs::read_to_string(&p).expect("read file");
        let ms = t0.elapsed().as_secs_f64() * 1e3;
        println!(
            "Input: {} ({} bytes) | load {:.3} ms",
            p.display(),
            src.len(),
            ms
        );
        (src, format!("file:{}", p.display()))
    } else {
        use rand::{SeedableRng, rngs::StdRng};
        let target_len = env::var("PARSE_DEMO_LEN")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(5000usize);
        let seed = env::var("PARSE_DEMO_SEED")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(42u64);
        let mut rng = StdRng::seed_from_u64(seed);
        let t0 = Instant::now();
        let s = laniusc::dev::generator::gen_valid_source(&mut rng, target_len);
        let ms = t0.elapsed().as_secs_f64() * 1e3;

        let out_dir = PathBuf::from("fuzz-cases");
        let _ = fs::create_dir_all(&out_dir);
        let filename = format!("parse_demo_seed{}_len{}.lan", seed, s.len());
        let out_path = out_dir.join(filename);
        if let Err(e) = fs::write(&out_path, &s) {
            eprintln!(
                "[parse_demo] warning: failed to write {}: {e}",
                out_path.display()
            );
        } else {
            println!("[parse_demo] saved {}", out_path.display());
        }

        println!(
            "Input: generated (len={} bytes) | gen {:.3} ms [seed={}]",
            s.len(),
            ms,
            seed
        );
        (s, "generated".into())
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    ensure_parse_tables_bin();
    let (text, _desc) = load_or_generate();

    // 1) Lex on GPU
    let tokens = lex_on_gpu(&text)
        .await
        .expect("GPU lex failed; ensure your GPU backend is working");
    assert!(!tokens.is_empty(), "no tokens");
    println!("Lexed: kept={} tokens", tokens.len());

    let kinds_u32: Vec<u32> = tokens.iter().map(|t| t.kind as u32).collect();
    let n_kinds = laniusc::lexer::tables::tokens::N_KINDS;

    // 2) Load offline tables (or MVP) and run the unified parser pipeline.
    let tbl_bytes = fs::read("tables/parse_tables.bin").expect("read tables/parse_tables.bin");
    let tables = PrecomputedParseTables::load_bin_bytes(&tbl_bytes).expect("parse tables .bin");
    assert_eq!(tables.n_kinds, n_kinds, "n_kinds mismatch");

    let parser = GpuParser::new().await.expect("GPU parser init");

    let res = parser.parse(&kinds_u32, &tables).await.expect("parse()");

    let total_pop: u32 = res.headers.iter().map(|h| h.pop_count).sum();
    let total_push: u32 = res.headers.iter().map(|h| h.push_len).sum();
    println!(
        "LLP headers: pairs={} | total_push={} total_pop={} balance={} total_emit={}",
        res.headers.len(),
        total_push,
        total_pop,
        (total_push as i64) - (total_pop as i64),
        res.emit_stream.len()
    );

    println!(
        "Packed: sc_stream_len={} emit_stream_len={}",
        res.sc_stream.len(),
        res.emit_stream.len()
    );

    println!(
        "Bracket validate (GPU): valid={} final_depth={} min_depth={}",
        res.brackets.valid, res.brackets.final_depth, res.brackets.min_depth
    );

    for (i, &m) in res.brackets.match_for_index.iter().take(12).enumerate() {
        println!(
            "[match {:02}] {}",
            i,
            if m == 0xFFFF_FFFF { u32::MAX } else { m }
        );
    }

    for (i, v) in res.sc_stream.iter().take(16).enumerate() {
        println!("[sc {:02}] 0x{:08x}", i, v);
    }
    for (i, v) in res.emit_stream.iter().take(8).enumerate() {
        println!("[emit {:02}] {}", i, v);
    }
}
