// src/bin/perf_one.rs
use std::{
    env,
    fs,
    path::{Path, PathBuf},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

use laniusc::lexer::{cpu::lex_on_cpu, gpu::GpuLexer};

fn pick_random_large_lan(dir: &Path) -> anyhow::Result<PathBuf> {
    let mut files: Vec<(PathBuf, u64)> = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("lan") {
            if let Ok(meta) = entry.metadata() {
                files.push((path, meta.len()));
            }
        }
    }

    if files.is_empty() {
        anyhow::bail!("no .lan files found under {}", dir.display());
    }

    // Prefer larger files; keep the largest ~1/3, then pick a pseudo-random one from that set.
    files.sort_by_key(|(_, sz)| *sz);
    let keep_from = files.len().saturating_sub((files.len().max(3)) / 3);
    let big_slice = &files[keep_from..];

    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64;
    let idx = (seed as usize) % big_slice.len();
    Ok(big_slice[idx].0.clone())
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

fn main() {
    pollster::block_on(async {
        // Determine input file: CLI arg or pick from fuzz-cases/
        let input_path = if let Some(arg) = env::args().nth(1) {
            PathBuf::from(arg)
        } else {
            let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
            let fuzz_dir = repo_root.join("fuzz-cases");
            match pick_random_large_lan(&fuzz_dir) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("Failed to pick a .lan file: {e}");
                    std::process::exit(2);
                }
            }
        };

        // Load file (as UTF-8; .lan is ASCII-compatible)
        let load_t0 = Instant::now();
        let src = match fs::read_to_string(&input_path) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("Failed to read {}: {e}", input_path.display());
                std::process::exit(2);
            }
        };
        let load_ms = load_t0.elapsed().as_secs_f64() * 1e3;
        let bytes = src.len() as u64;

        println!(
            "File: {}  ({} | {} bytes)",
            input_path.display(),
            fmt_mib(bytes),
            bytes
        );
        println!("Load: {:.3} ms", load_ms);

        // ---------------- CPU ----------------
        let cpu_t0 = Instant::now();
        let cpu_tokens = match lex_on_cpu(&src) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("CPU lex failed: {e}");
                std::process::exit(1);
            }
        };
        let cpu_ms = cpu_t0.elapsed().as_secs_f64() * 1e3;
        println!(
            "CPU:  {:.3} ms | tokens={} | throughput={:.1} MiB/s",
            cpu_ms,
            cpu_tokens.len(),
            throughput_mibs(bytes, cpu_ms)
        );

        // ---------------- GPU (include init) ----------------
        // GPU init time (adapter/device + pipelines)
        let gpu_init_t0 = Instant::now();
        let gpu = match GpuLexer::new().await {
            Ok(g) => g,
            Err(e) => {
                eprintln!("GPU init failed: {e:?}");
                std::process::exit(1);
            }
        };
        let gpu_init_ms = gpu_init_t0.elapsed().as_secs_f64() * 1e3;

        // GPU lex time (buffers, dispatch, wait, readback, decode)
        let gpu_lex_t0 = Instant::now();
        let gpu_tokens = match gpu.lex(&src).await {
            Ok(v) => v,
            Err(e) => {
                eprintln!("GPU lex failed: {e:?}");
                std::process::exit(1);
            }
        };
        let gpu_lex_ms = gpu_lex_t0.elapsed().as_secs_f64() * 1e3;
        let gpu_total_ms = gpu_init_ms + gpu_lex_ms;

        println!(
            "GPU:  init={:.3} ms | lex={:.3} ms | total={:.3} ms | tokens={} | throughput={:.1} MiB/s",
            gpu_init_ms,
            gpu_lex_ms,
            gpu_total_ms,
            gpu_tokens.len(),
            throughput_mibs(bytes, gpu_total_ms)
        );

        // Optional quick sanity: token counts match?
        if cpu_tokens.len() != gpu_tokens.len() {
            eprintln!(
                "NOTE: token count mismatch (cpu={} vs gpu={})",
                cpu_tokens.len(),
                gpu_tokens.len()
            );
        }

        // Summary
        if gpu_total_ms > 0.0 {
            println!(
                "Speedup (CPU_time / GPU_total_time): {:.2}×",
                cpu_ms / gpu_total_ms
            );
        }
    });
}
