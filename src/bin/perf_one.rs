// src/bin/perf_one.rs
use std::{env, fs, path::PathBuf, time::Instant};

use laniusc::lexer::{cpu::lex_on_cpu, gpu::GpuLexer};
use rand::{Rng, SeedableRng, rngs::StdRng};

// ---------------- in-memory generator (borrowed from fuzz_lex style) ----------------

fn gen_valid_source<R: Rng>(rng: &mut R, target_len: usize) -> String {
    let mut out = String::with_capacity(target_len + target_len / 8);

    while out.len() < target_len {
        let roll = rng.random_range(0u32..100);

        match roll {
            0..=24 => push_ident(rng, &mut out),
            25..=39 => push_int(rng, &mut out),
            40..=54 => push_ws(rng, &mut out),
            55..=61 => push_line_comment(rng, &mut out),
            62..=70 => push_block_comment(rng, &mut out),
            71..=99 => push_operator(rng, &mut out),
            _ => unreachable!(),
        }
    }

    // Trailer keeps the last block-comment sane and ensures an EOF tokenization edge.
    out.push('*');
    out.push('/');
    out.push(' ');
    out.push('0');
    out.push('\n');

    out
}

fn push_ident<R: Rng>(rng: &mut R, out: &mut String) {
    let len = rng.random_range(1..=12);
    let mut s = String::new();
    s.push(random_alpha(rng));
    for _ in 1..len {
        if rng.random_bool(0.6) {
            s.push(random_alpha(rng));
        } else {
            s.push(random_digit(rng));
        }
    }
    out.push_str(&s);
}

fn push_int<R: Rng>(rng: &mut R, out: &mut String) {
    let len = rng.random_range(1..=8);
    for _ in 0..len {
        out.push(random_digit(rng));
    }
}

fn push_ws<R: Rng>(rng: &mut R, out: &mut String) {
    let opts: [char; 4] = [' ', '\t', '\r', '\n'];
    let len = rng.random_range(1..=8);
    for _ in 0..len {
        let i = rng.random_range(0..opts.len());
        out.push(opts[i]);
    }
}

fn push_line_comment<R: Rng>(rng: &mut R, out: &mut String) {
    out.push_str("//");
    let len = rng.random_range(0..=40);
    const ALPH: &str =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 +-*/&|![]{}()<>=*&";
    let bytes = ALPH.as_bytes();
    for _ in 0..len {
        let i = rng.random_range(0..bytes.len());
        out.push(bytes[i] as char);
    }
    out.push('\n');
}

fn push_block_comment<R: Rng>(rng: &mut R, out: &mut String) {
    out.push_str("/*");
    let chunks = rng.random_range(0..=15);
    const BODY: &str =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 +-![]{}()<>=&|";
    let bytes = BODY.as_bytes();
    for _ in 0..chunks {
        let k = rng.random_range(1..=8);
        for _ in 0..k {
            let i = rng.random_range(0..bytes.len());
            out.push(bytes[i] as char);
        }
        if rng.random_bool(0.2) {
            out.push('*');
        }
        if rng.random_bool(0.2) {
            out.push('\n');
        }
    }
    out.push_str("*/");
}

fn push_operator<R: Rng>(rng: &mut R, out: &mut String) {
    let ops = [
        "(", ")", "+", "*", "=", "/", "!", "[", "]", "{", "}", "<", "<=", ">", ">=", "==", "&",
        "&&", "|", "||",
    ];
    let i = rng.random_range(0..ops.len());
    out.push_str(ops[i]);
    if rng.random_bool(0.25) {
        out.push(' ');
    }
}

fn random_alpha<R: Rng>(rng: &mut R) -> char {
    let set = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
    let i = rng.random_range(0..set.len());
    set[i] as char
}
fn random_digit<R: Rng>(rng: &mut R) -> char {
    let set = b"0123456789";
    let i = rng.random_range(0..set.len());
    set[i] as char
}

fn fmt_mib(bytes: u64) -> String {
    let mib = (bytes as f64) / (1024.0 * 1024.0);
    format!("{mib:.2} MiB")
}

fn throughput_mibs(bytes: u64, ms: f64) -> f64 {
    if ms <= 0.0 {
        return 0.0;
    }
    (bytes as f64) / (1024.0 * 1024.0) / (ms / 1_000.0)
}

// ---------------- in-memory generator (borrowed from fuzz_lex style) ----------------

fn parse_target_len() -> usize {
    // Default: 10,000,000 characters
    env::var("PERF_ONE_LEN")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(10_000_000)
}

fn parse_seed() -> u64 {
    env::var("PERF_ONE_SEED")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(42)
}

fn parse_warmup() -> usize {
    env::var("PERF_ONE_WARMUP")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1)
}

fn parse_reps() -> usize {
    env::var("PERF_ONE_REPS")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(10)
}

fn percentile(sorted_ms: &[f64], p: f64) -> f64 {
    if sorted_ms.is_empty() {
        return 0.0;
    }
    let idx = ((p.clamp(0.0, 1.0)) * (sorted_ms.len() as f64 - 1.0)).round() as usize;
    sorted_ms[idx]
}

fn print_stats(label: &str, ms_list: &[f64], bytes: u64) {
    if ms_list.is_empty() {
        println!("{label}: no samples");
        return;
    }
    let mut s = ms_list.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let best = s[0];
    let p50 = percentile(&s, 0.50);
    let p95 = percentile(&s, 0.95);
    println!(
        "{label}: best={:.3} ms | p50={:.3} ms | p95={:.3} ms | throughput(best)={:.1} MiB/s",
        best,
        p50,
        p95,
        throughput_mibs(bytes, best)
    );
}

// ------------------------------------------------------------------------------------

fn main() {
    pollster::block_on(async {
        // If a path is supplied, we’ll use it; otherwise we **generate** input in memory.
        let maybe_path = env::args().nth(1);

        let (text, src_desc) = if let Some(path) = maybe_path {
            let p = PathBuf::from(path);
            let load_t0 = Instant::now();
            let src = match fs::read_to_string(&p) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to read {}: {e}", p.display());
                    std::process::exit(2);
                }
            };
            let load_ms = load_t0.elapsed().as_secs_f64() * 1e3;
            let bytes = src.len() as u64;
            println!(
                "Input: file={}  ({} | {} bytes)",
                p.display(),
                fmt_mib(bytes),
                bytes
            );
            println!("Load:  {load_ms:.3} ms");
            (src, "file".to_string())
        } else {
            let target_len = parse_target_len();
            let seed = parse_seed();
            let gen_t0 = Instant::now();
            let mut rng = StdRng::seed_from_u64(seed);
            let src = gen_valid_source(&mut rng, target_len);
            let gen_ms = gen_t0.elapsed().as_secs_f64() * 1e3;
            let bytes = src.len() as u64;
            println!(
                "Input: generated in-memory (len={} | {}) [seed={}]",
                bytes,
                fmt_mib(bytes),
                seed
            );
            println!("Gen:   {gen_ms:.3} ms");
            (src, "generated".to_string())
        };

        let bytes = text.len() as u64;
        let warmup = parse_warmup();
        let reps = parse_reps();

        // ---------------- CPU ----------------
        let mut cpu_runs = Vec::with_capacity(reps);
        for i in 0..(warmup + reps) {
            let t0 = Instant::now();
            let cpu_tokens = match lex_on_cpu(&text) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("CPU lex failed: {e}");
                    std::process::exit(1);
                }
            };
            let ms = t0.elapsed().as_secs_f64() * 1e3;
            if i >= warmup {
                cpu_runs.push(ms);
            }
            if i == warmup {
                println!("CPU:  first={:.3} ms | tokens={}", ms, cpu_tokens.len());
            }
        }
        print_stats("CPU", &cpu_runs, bytes);

        // ---------------- GPU (init separated) ----------------
        let gpu_init_t0 = Instant::now();
        let gpu = match GpuLexer::new().await {
            Ok(g) => g,
            Err(e) => {
                eprintln!("GPU init failed: {e:?}");
                std::process::exit(1);
            }
        };
        let gpu_init_ms = gpu_init_t0.elapsed().as_secs_f64() * 1e3;
        println!("GPU:  init={gpu_init_ms:.3} ms");

        let mut gpu_runs = Vec::with_capacity(reps);
        let mut first_tokens_len: Option<usize> = None;
        for i in 0..(warmup + reps) {
            let t0 = Instant::now();
            let gpu_tokens = match gpu.lex(&text).await {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("GPU lex failed: {e:?}");
                    std::process::exit(1);
                }
            };
            let ms = t0.elapsed().as_secs_f64() * 1e3;
            if i == warmup {
                first_tokens_len = Some(gpu_tokens.len());
                println!("GPU:  first-lex={:.3} ms | tokens={}", ms, gpu_tokens.len());
            }
            if i >= warmup {
                gpu_runs.push(ms);
            }
        }
        print_stats("GPU-lex", &gpu_runs, bytes);

        // Reference-only total (not used for speedup)
        if let Some(&best_gpu) = gpu_runs.iter().min_by(|a, b| a.partial_cmp(b).unwrap()) {
            let best_total = gpu_init_ms + best_gpu;
            println!(
                "GPU:  total(best)={:.3} ms | throughput(total)={:.1} MiB/s",
                best_total,
                throughput_mibs(bytes, best_total)
            );
        }

        // Optional quick sanity: token counts match?
        // (Just compare the CPU's first run with GPU's first post-warmup run.)
        if let Some(gpu_len) = first_tokens_len {
            let cpu_first = {
                // rerun a quick CPU pass to get its token count without timing noise
                lex_on_cpu(&text).map(|v| v.len()).unwrap_or_default()
            };
            if cpu_first != gpu_len {
                eprintln!(
                    "PANIC!!!: token count mismatch (cpu={cpu_first} vs gpu={gpu_len}) [{src_desc}]"
                );
            }
        }

        // Show a simple speedup using medians (more stable than single-shot)
        if !cpu_runs.is_empty() && !gpu_runs.is_empty() {
            let mut c = cpu_runs.clone();
            c.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let mut g = gpu_runs.clone();
            g.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let speedup = c[c.len() / 2] / g[g.len() / 2];
            println!("Speedup (median CPU / median GPU_lex): {speedup:.2}×");
        }
    });
}
