//! Size sweep tests for the lexer:
//!  - all target lengths < 32 (0..=31) — runs by default
//!  - powers of two from 32 up to ~10,000,000 — opt-in (ignored by default)
//!
//! We generate using the **shared** generator (same as fuzz_lex/perf_one).
//! It produces at least `target_len` bytes and always appends a safe trailer.

use std::{fs, io::Write, path::Path};

use laniusc::{
    dev::generator::gen_valid_source,
    lexer::{
        cpu::{CpuToken, lex_on_cpu},
        gpu::{Token as GpuToken, lex_on_gpu},
    },
};
use rand::{SeedableRng, rngs::StdRng};

fn env_u64(name: &str, default: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(default)
}

fn env_usize(name: &str, default: usize) -> usize {
    std::env::var(name)
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(default)
}

fn first_divergence_idx(cpu: &[CpuToken], gpu: &[GpuToken]) -> usize {
    let n = cpu.len().min(gpu.len());
    for i in 0..n {
        let ct = &cpu[i];
        let gt = &gpu[i];
        if ct.kind as u32 != gt.kind as u32 || ct.start != gt.start || ct.len != gt.len {
            return i;
        }
    }
    n
}

fn slice_preview(src: &str, start: usize, len: usize) -> String {
    let bytes = src.as_bytes();
    let end = start.saturating_add(len).min(bytes.len());
    let s = &bytes[start..end];
    let head = 10usize.min(s.len());
    let tail = 10usize.min(s.len().saturating_sub(head));
    if s.len() <= head + tail {
        String::from_utf8_lossy(s).into_owned()
    } else {
        format!(
            "{}…(+{})…{}",
            String::from_utf8_lossy(&s[..head]),
            s.len() - head - tail,
            String::from_utf8_lossy(&s[s.len() - tail..])
        )
    }
}

fn dump_near(src: &str, cpu: &[CpuToken], gpu: &[GpuToken], from: usize) {
    let lo = from.saturating_sub(1);
    let hi = (from + 3).min(cpu.len().min(gpu.len()));
    eprintln!("--- context tokens [{lo}..{hi}) ---");
    for i in lo..hi {
        let c = cpu
            .get(i)
            .map(|t| (t.kind, t.start, t.len, slice_preview(src, t.start, t.len)));
        let g = gpu
            .get(i)
            .map(|t| (t.kind, t.start, t.len, slice_preview(src, t.start, t.len)));
        let mark = if c == g { "✅" } else { "❌" };
        eprintln!("{mark} #{i:06} CPU={c:?}  GPU={g:?}");
    }
}

fn save_case(dir: &str, tag: &str, target_len: usize, seed: u64, src: &str) -> String {
    let _ = fs::create_dir_all(dir);
    let base = format!("{tag}_len{target_len}_seed{seed}_n{}.lan", src.len());
    let path = Path::new(dir).join(base);
    let json = path.with_extension("json");
    fs::write(&path, src.as_bytes()).ok();

    // minimal meta
    let meta = serde_json::json!({
        "target_len": target_len,
        "actual_bytes": src.len(),
        "seed": seed,
        "replay": format!("FUZZ_INPUT={} cargo run --bin fuzz_lex", path.display()),
    });
    if let Ok(mut f) = fs::File::create(&json) {
        let _ = writeln!(f, "{}", serde_json::to_string_pretty(&meta).unwrap());
    }
    path.display().to_string()
}

fn assert_tokens_equal_or_dump(
    src: &str,
    cpu: &[CpuToken],
    gpu: &[GpuToken],
    label: &str,
    target: usize,
    seed: u64,
) {
    if cpu.len() != gpu.len() {
        let case_path = save_case("fuzz-cases", "size_sweep_fail", target, seed, src);
        eprintln!(
            "[{label}] target_len={} actual_len={} token-count mismatch: CPU={} GPU={}\n  saved: {}",
            target,
            src.len(),
            cpu.len(),
            gpu.len(),
            case_path
        );
        let i = first_divergence_idx(cpu, gpu);
        dump_near(src, cpu, gpu, i);
        panic!("token-count mismatch");
    }
    for (i, (ct, gt)) in cpu.iter().zip(gpu.iter()).enumerate() {
        if ct.kind as u32 != gt.kind as u32 || ct.start != gt.start || ct.len != gt.len {
            let case_path = save_case("fuzz-cases", "size_sweep_fail", target, seed, src);
            eprintln!(
                "[{label}] target_len={} actual_len={} token {i} mismatch\n  saved: {}",
                target,
                src.len(),
                case_path
            );
            dump_near(src, cpu, gpu, i);
            panic!("token mismatch");
        }
    }
}

async fn run_one(target_len: usize, seed: u64) {
    // Derive a per-length seed for reproducibility across iterations.
    let mut rng =
        StdRng::seed_from_u64(seed ^ (target_len as u64).wrapping_mul(0x9E3779B97F4A7C15));
    let src = gen_valid_source(&mut rng, target_len);

    let cpu = lex_on_cpu(&src).expect("CPU lex failed");
    let gpu = lex_on_gpu(&src).await.expect("GPU lex failed");

    assert_tokens_equal_or_dump(&src, &cpu, &gpu, "size_sweep", target_len, seed);
}

/// Sweep 0..=31 target lengths. (Fast; runs by default.)
#[test]
fn size_sweep_small_targets() {
    pollster::block_on(async {
        let seed = env_u64("SIZE_SWEEP_SEED", 42);
        for len in 0..=31 {
            run_one(len, seed).await;
        }
    });
}

/// Powers of two from 32 up to ~10,000,000 (capped by SIZE_SWEEP_MAX).
/// Ignored by default; opt-in when needed.
#[test]
#[ignore]
fn size_sweep_powers_of_two() {
    pollster::block_on(async {
        let seed = env_u64("SIZE_SWEEP_SEED", 42);
        let max_len = env_usize("SIZE_SWEEP_MAX", 10_000_000);

        let mut n = 32usize;
        while n <= max_len {
            run_one(n, seed).await;
            eprintln!(
                "[size_sweep] ok: target_len={} (actual_len will be >= target)",
                n
            );
            n = n.saturating_mul(2);
            if n == 0 {
                break;
            } // overflow guard
        }
    });
}
