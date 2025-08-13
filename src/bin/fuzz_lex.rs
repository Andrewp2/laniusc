// src/bin/fuzz_lex.rs
// Generate big random-but-valid inputs, run CPU & GPU lexers, compare.
// Extras:
//   - FUZZ_SAVE=1 and FUZZ_DIR=... save generated fuzz cases
//   - FUZZ_INPUT=path         replay a saved case
//   - FUZZ_EX=<files>         comma/colon-separated list of handcrafted .lan files
//   - FUZZ_EX_DIR=<dir>       directory of .lan files (default: "lexer_tests")
//
// New:
//   - Sidecar golden files: <case>.tokens.json with {"tokens":[{"kind":"...", "text":"..."}...]}
//   - For handcrafted cases, if a golden exists, verify CPU and GPU match it.

use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

use laniusc::lexer::{
    cpu::{CpuToken, lex_on_cpu},
    tables::TokenKind,
};
use rand::{Rng, SeedableRng, rngs::StdRng};

// ------------------ goldens ------------------

#[derive(serde::Deserialize)]
struct Golden {
    tokens: Vec<GoldenTok>,
}
#[derive(serde::Deserialize)]
struct GoldenTok {
    kind: String,
    text: String,
}

fn kind_from_str(s: &str) -> Option<TokenKind> {
    use TokenKind::*;
    Some(match s {
        "Ident" => Ident,
        "Int" => Int,
        "White" => White,
        "LParen" => LParen,
        "RParen" => RParen,
        "Plus" => Plus,
        "Star" => Star,
        "Assign" => Assign,
        "Slash" => Slash,
        "LineComment" => LineComment,
        "BlockComment" => BlockComment,
        "Lt" => Lt,
        "Gt" => Gt,
        "Le" => Le,
        "Ge" => Ge,
        "EqEq" => EqEq,
        "AndAnd" => AndAnd,
        "OrOr" => OrOr,
        "Not" => Not,
        "LBracket" => LBracket,
        "RBracket" => RBracket,
        "LBrace" => LBrace,
        "RBrace" => RBrace,
        "GroupLParen" => GroupLParen,     // <- no extra Some()
        "CallLParen" => CallLParen,       // <- no extra Some()
        "IndexLBracket" => IndexLBracket, // <- no extra Some()
        "ArrayLBracket" => ArrayLBracket, // <- no extra Some()
        "AngleGeneric" => AngleGeneric,
        "Ampersand" => Ampersand,
        "Pipe" => Pipe,
        "Minus" => Minus,
        _ => return None,
    })
}

fn load_golden_for(base_lan: &Path) -> Option<Golden> {
    let candidates = [
        base_lan.with_extension("tokens.json"),
        base_lan.with_extension("golden.json"),
        base_lan.with_extension("json"),
    ];
    for p in candidates {
        if p.exists() {
            let s = fs::read_to_string(&p).ok()?;
            match serde_json::from_str::<Golden>(&s) {
                Ok(g) => return Some(g),
                Err(e) => {
                    eprintln!("[golden] failed to parse {}: {e}", p.display());
                    return None;
                }
            }
        }
    }
    None
}

fn tokens_as_kind_text<'a, T>(src: &'a str, toks: T) -> Vec<(TokenKind, String)>
where
    T: IntoIterator<Item = &'a (TokenKind, usize, usize)>,
{
    toks.into_iter()
        .map(|(k, start, len)| {
            let text = String::from_utf8_lossy(&src.as_bytes()[*start..start + len]).into_owned();
            (*k, text)
        })
        .collect()
}

fn check_against_golden(
    label: &str,
    src: &str,
    toks: &[(TokenKind, usize, usize)],
    golden: &Golden,
) -> bool {
    let got = tokens_as_kind_text(src, toks.iter());
    if got.len() != golden.tokens.len() {
        eprintln!(
            "[golden:{label}] count mismatch: got={} expected={}",
            got.len(),
            golden.tokens.len()
        );
        dump_kind_text_diff(&got, &golden.tokens, 0);
        return false;
    }
    for (i, ((gk, gtxt), exp)) in got.iter().zip(golden.tokens.iter()).enumerate() {
        let Some(ek) = kind_from_str(&exp.kind) else {
            eprintln!(
                "[golden:{label}] unknown kind '{}' at index {}",
                exp.kind, i
            );
            return false;
        };
        if *gk as u32 != ek as u32 || gtxt != &exp.text {
            eprintln!(
                "[golden:{label}] mismatch at {}:\n  got:  kind={:?} text={:?}\n  want: kind={}   text={:?}",
                i, gk, gtxt, exp.kind, exp.text
            );
            dump_kind_text_diff(&got, &golden.tokens, i.saturating_sub(2));
            return false;
        }
    }
    true
}

fn dump_kind_text_diff(got: &[(TokenKind, String)], exp: &[GoldenTok], from: usize) {
    let hi = (from + 8).min(got.len().max(exp.len()));
    eprintln!("--- golden context [{}..{}) ---", from, hi);
    for i in from..hi {
        eprintln!(
            "#{:06} got={:?} want={:?}",
            i,
            got.get(i).map(|(k, t)| (k, t)),
            exp.get(i).map(|e| (&e.kind, &e.text))
        );
    }
}

// ------------------ main ------------------

fn main() {
    // --- REPLAY A SINGLE CASE ---
    if let Ok(path) = std::env::var("FUZZ_INPUT") {
        eprintln!("[replay] reading {}", path);
        let s = fs::read_to_string(&path).expect("failed to read FUZZ_INPUT");
        pollster::block_on(run_once(&s, None, None, None, None));
        return;
    }

    // --- HANDCRAFTED EXAMPLES (run before fuzzing) ---
    let examples = collect_examples();
    if !examples.is_empty() {
        eprintln!("[ex] running {} handcrafted example(s)…", examples.len());
        for (j, p) in examples.iter().enumerate() {
            match fs::read_to_string(p) {
                Ok(s) => {
                    eprintln!("[ex {j}] {}", p.display());
                    if !pollster::block_on(run_once(&s, None, None, None, Some(p.as_path()))) {
                        std::process::exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("[ex {j}] failed to read {}: {e}", p.display());
                    std::process::exit(1);
                }
            }
        }
    }

    // --- FUZZ MODE ---
    let save_cases = std::env::var("FUZZ_SAVE").ok().as_deref() == Some("1");
    let out_dir = std::env::var("FUZZ_DIR").unwrap_or_else(|_| "fuzz-cases".to_string());
    let len: usize = std::env::var("FUZZ_LEN")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(1_000_000);
    let iters: usize = std::env::var("FUZZ_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3);
    let seed: u64 = std::env::var("FUZZ_SEED")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(42);

    eprintln!("[fuzz] len={len} iters={iters} seed={seed}");
    let mut rng = StdRng::seed_from_u64(seed);

    if save_cases {
        if let Err(e) = fs::create_dir_all(&out_dir) {
            eprintln!("error: failed to create {}: {e}", out_dir);
            std::process::exit(1);
        }
    }

    pollster::block_on(async move {
        for i in 0..iters {
            let s = gen_valid_source(&mut rng, len);
            eprintln!("[fuzz] iter {i}: generated {} bytes", s.len());

            if save_cases {
                let path = save_case(&out_dir, seed, i, &s);
                eprintln!("[save] wrote {}", path.display());
            }

            let ok = run_once(&s, Some(seed), Some(i), Some(len), None).await;
            if !ok {
                std::process::exit(1);
            }
        }
        eprintln!("[fuzz] all iterations matched ✅");
    });
}

// ---------- run one (CPU vs GPU [+ optional golden]) ----------

async fn run_once(
    src: &str,
    seed: Option<u64>,
    iter: Option<usize>,
    len: Option<usize>,
    golden_for: Option<&Path>,
) -> bool {
    let t0 = Instant::now();
    let cpu = match lex_on_cpu(src) {
        Ok(toks) => toks,
        Err(e) => {
            eprintln!("\n[CPU] {}", e);
            let tail = src.as_bytes().len().saturating_sub(64);
            eprintln!(
                "[tail] {:?}",
                String::from_utf8_lossy(&src.as_bytes()[tail..])
            );
            panic!("CPU lex failed");
        }
    };
    let t1 = Instant::now();
    let t2 = Instant::now();
    let gpu = laniusc::lexer::gpu::lex_on_gpu(src)
        .await
        .expect("GPU lex failed");
    let t3 = Instant::now();

    let eq = compare_streams(src, &cpu, &gpu);
    let cpu_ms = (t1 - t0).as_millis();
    let gpu_init_ms = (t2 - t1).as_millis();
    let gpu_ms = (t3 - t2).as_millis();

    match (seed, iter, len) {
        (Some(_seed), Some(i), Some(_l)) => eprintln!(
            "[fuzz] iter {i}: CPU {} ms  |  GPU init {} ms  |  GPU lex {} ms  |  tokens kept = {}  -> {}",
            cpu_ms,
            gpu_init_ms,
            gpu_ms,
            gpu.len(),
            if eq { "OK" } else { "MISMATCH!" }
        ),
        _ => eprintln!(
            "[replay] CPU {} ms  |  GPU init {} ms  |  GPU lex {} ms  |  tokens kept = {}  -> {}",
            cpu_ms,
            gpu_init_ms,
            gpu_ms,
            gpu.len(),
            if eq { "OK" } else { "MISMATCH!" }
        ),
    }

    let mut ok = eq;

    if let Some(p) = golden_for {
        if let Some(g) = load_golden_for(p) {
            // Normalize into (kind, start, len) triplets for both streams.
            let cpu_norm: Vec<(TokenKind, usize, usize)> =
                cpu.iter().map(|t| (t.kind, t.start, t.len)).collect();
            let gpu_norm: Vec<(TokenKind, usize, usize)> =
                gpu.iter().map(|t| (t.kind, t.start, t.len)).collect();

            let cpu_ok = check_against_golden("cpu", src, &cpu_norm, &g);
            let gpu_ok = check_against_golden("gpu", src, &gpu_norm, &g);

            if !cpu_ok || !gpu_ok {
                ok = false;
            }
        } else {
            eprintln!("[golden] no sidecar found for {}", p.display());
        }
    }

    if !ok {
        dump_near(src, &cpu, &gpu, 0);
    }
    ok
}

// ---------- handcrafted examples discovery ----------

fn collect_examples() -> Vec<PathBuf> {
    // FUZZ_EX takes precedence; split on ',' or ':'
    if let Ok(list) = std::env::var("FUZZ_EX") {
        let mut out = Vec::new();
        for part in list.split(|c| c == ',' || c == ':') {
            let p = PathBuf::from(part.trim());
            if !p.as_os_str().is_empty() && p.exists() {
                out.push(p);
            }
        }
        if !out.is_empty() {
            return out;
        }
    }

    // Else look for a directory (default "lexer_tests")
    let dir = std::env::var("FUZZ_EX_DIR").unwrap_or_else(|_| "lexer_tests".into());
    let p = Path::new(&dir);
    if !p.exists() || !p.is_dir() {
        return Vec::new();
    }

    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(p) {
        for ent in rd.flatten() {
            let path = ent.path();
            if path
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| e.eq_ignore_ascii_case("lan"))
                .unwrap_or(false)
            {
                out.push(path);
            }
        }
    }
    out.sort();
    out
}

// ---------- save / replay helpers ----------

#[derive(serde::Serialize)]
struct CaseMeta<'a> {
    unix_ts: u64,
    seed: Option<u64>,
    iter: Option<usize>,
    requested_len: Option<usize>,
    actual_bytes: usize,
    note: &'a str,
}

fn save_case(dir: &str, seed: u64, iter: usize, src: &str) -> PathBuf {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let base = format!("case_s{seed}_i{iter}_n{}.lan", src.len());
    let path = Path::new(dir).join(base);

    fs::write(&path, src.as_bytes()).expect("failed to write case file");

    let meta = CaseMeta {
        unix_ts: ts,
        seed: Some(seed),
        iter: Some(iter),
        requested_len: None,
        actual_bytes: src.len(),
        note: "Replay with: FUZZ_INPUT=<this file> cargo run --bin fuzz_lex",
    };
    let meta_path = path.with_extension("json");
    let mut f = fs::File::create(&meta_path).expect("failed to write meta");
    let _ = writeln!(f, "{}", serde_json::to_string_pretty(&meta).unwrap());

    path
}

// ---------- generator (valid wrt current grammar) ----------

fn gen_valid_source<R: Rng>(rng: &mut R, target_len: usize) -> String {
    let mut out = String::with_capacity(target_len + target_len / 8);

    while out.len() < target_len {
        let roll = rng.random_range(0u32..100);

        match roll {
            0..=24 => push_ident(rng, &mut out),          // ~25%
            25..=39 => push_int(rng, &mut out),           // ~15%
            40..=54 => push_ws(rng, &mut out),            // ~15%
            55..=61 => push_line_comment(rng, &mut out),  // ~7%
            62..=70 => push_block_comment(rng, &mut out), // ~9%
            71..=99 => push_operator(rng, &mut out),      // ~29%
            _ => unreachable!(),
        }
    }

    // Safety trailer — ensure accepting end state and newline.
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
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 +-*/&|![]{}()<>=*";
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

// ---------- comparison (CPU vs GPU) ----------

// ---------- comparison (CPU vs GPU) ----------

fn compare_streams(src: &str, cpu: &[CpuToken], gpu: &[laniusc::lexer::gpu::Token]) -> bool {
    if cpu.len() != gpu.len() {
        // NEW: find the first divergence even when only the lengths differ
        let i = first_divergence_idx(cpu, gpu);
        eprintln!(
            "[diff] token count mismatch: cpu={} gpu={} (first divergence at index {})",
            cpu.len(),
            gpu.len(),
            i
        );
        dump_near(src, cpu, gpu, i.saturating_sub(3));

        // If everything matched up to min len, show the first few trailing tokens from the longer side.
        let min_len = cpu.len().min(gpu.len());
        if i == min_len {
            if cpu.len() > gpu.len() {
                eprintln!("--- extra CPU tokens starting at {} ---", min_len);
                for j in min_len..(min_len + 6).min(cpu.len()) {
                    let t = &cpu[j];
                    let text = &src.as_bytes()[t.start..t.start + t.len];
                    eprintln!(
                        "#{:06} CPU extra = {:?} @{}+{} {:?}",
                        j,
                        t.kind,
                        t.start,
                        t.len,
                        String::from_utf8_lossy(text)
                    );
                }
            } else {
                eprintln!("--- extra GPU tokens starting at {} ---", min_len);
                for j in min_len..(min_len + 6).min(gpu.len()) {
                    let t = &gpu[j];
                    let text = &src.as_bytes()[t.start..t.start + t.len];
                    eprintln!(
                        "#{:06} GPU extra = {:?} @{}+{} {:?}",
                        j,
                        t.kind,
                        t.start,
                        t.len,
                        String::from_utf8_lossy(text)
                    );
                }
            }
        }
        return false;
    }

    for (idx, (ct, gt)) in cpu.iter().zip(gpu.iter()).enumerate() {
        if ct.kind as u32 != gt.kind as u32 || ct.start != gt.start || ct.len != gt.len {
            eprintln!(
                "[diff] token {} mismatch:\n  CPU: kind={:?} start={} len={}\n  GPU: kind={:?} start={} len={}",
                idx, ct.kind, ct.start, ct.len, gt.kind, gt.start, gt.len
            );

            // NEW: show a little source window around both tokens
            dump_src_window(src, ct.start, ct.len, "CPU", idx);
            dump_src_window(src, gt.start, gt.len, "GPU", idx);

            dump_near(src, cpu, gpu, idx.saturating_sub(3));
            return false;
        }
    }
    true
}

// (keep dump_near as-is; it now gets called with a better starting index)

// ---------- helpers (NEW) ----------

fn first_divergence_idx(cpu: &[CpuToken], gpu: &[laniusc::lexer::gpu::Token]) -> usize {
    let n = cpu.len().min(gpu.len());
    for i in 0..n {
        let ct = &cpu[i];
        let gt = &gpu[i];
        if ct.kind as u32 != gt.kind as u32 || ct.start != gt.start || ct.len != gt.len {
            return i;
        }
    }
    n // lengths differ or streams are identical
}

fn line_col_at(src: &str, byte_idx: usize) -> (usize, usize) {
    // 1-based line/col
    let mut line = 1usize;
    let mut col = 1usize;
    for (i, b) in src.as_bytes().iter().enumerate() {
        if i == byte_idx {
            break;
        }
        if *b == b'\n' {
            line += 1;
            col = 1;
        } else {
            col += 1;
        }
    }
    (line, col)
}

fn dump_src_window(src: &str, start: usize, len: usize, who: &str, idx: usize) {
    let lo = start.saturating_sub(64);
    let hi = (start + len + 64).min(src.len());
    let (line, col) = line_col_at(src, start);
    let snippet = String::from_utf8_lossy(&src.as_bytes()[lo..hi]);

    eprintln!(
        "[src:{who} idx={idx}] token @{}+{} (line {}, col {})  window [{}..{}]",
        start, len, line, col, lo, hi
    );
    eprintln!("    {:?}", snippet);

    // underline the token within the window (best-effort; ignores tabs)
    let caret_pos = start.saturating_sub(lo);
    let caret_len = len.max(1).min(80);
    let mut underline = String::new();
    underline.push_str(&" ".repeat(caret_pos));
    underline.push_str(&"^".repeat(caret_len));
    eprintln!("    {}", underline);
}

fn dump_near(src: &str, cpu: &[CpuToken], gpu: &[laniusc::lexer::gpu::Token], from_idx: usize) {
    let lo = from_idx;
    let hi = (from_idx + 6).min(cpu.len().max(gpu.len()));
    eprintln!("--- context tokens [{}..{}) ---", lo, hi);
    for i in lo..hi {
        let cpu_s = cpu
            .get(i)
            .map(|t| &src.as_bytes()[t.start..t.start + t.len]);
        let gpu_s = gpu
            .get(i)
            .map(|t| &src.as_bytes()[t.start..t.start + t.len]);
        eprintln!(
            "#{:06} CPU={:?} GPU={:?}",
            i,
            cpu.get(i).map(|t| (
                t.kind,
                t.start,
                t.len,
                String::from_utf8_lossy(cpu_s.unwrap_or_default())
            )),
            gpu.get(i).map(|t| (
                t.kind,
                t.start,
                t.len,
                String::from_utf8_lossy(gpu_s.unwrap_or_default())
            )),
        );
    }
}
