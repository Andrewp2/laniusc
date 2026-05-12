// Developer lexer fuzz tool.
//
// This binary is not part of the compiler pipeline. It may call the explicitly
// named test CPU lexer oracle to compare against GPU lexer output.

use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

use laniusc::{
    dev::generator::gen_valid_source,
    lexer::{
        tables::TokenKind,
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
};
use log::warn;
use rand::{SeedableRng, rngs::StdRng};

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
        "Float" => Float,
        "Char" => Char,
        "White" => White,
        "LParen" => LParen,
        "RParen" => RParen,
        "Plus" => Plus,
        "Inc" => Inc,
        "Star" => Star,
        "Tilde" => Tilde,
        "Assign" => Assign,
        "PlusAssign" => PlusAssign,
        "MinusAssign" => MinusAssign,
        "StarAssign" => StarAssign,
        "SlashAssign" => SlashAssign,
        "PercentAssign" => PercentAssign,
        "CaretAssign" => CaretAssign,
        "ShlAssign" => ShlAssign,
        "ShrAssign" => ShrAssign,
        "AmpAssign" => AmpAssign,
        "PipeAssign" => PipeAssign,
        "Slash" => Slash,
        "LineComment" => LineComment,
        "BlockComment" => BlockComment,
        "Dot" => Dot,
        "Comma" => Comma,
        "Semicolon" => Semicolon,
        "Colon" => Colon,
        "Question" => Question,
        "Lt" => Lt,
        "Gt" => Gt,
        "Le" => Le,
        "Ge" => Ge,
        "EqEq" => EqEq,
        "NotEqual" => NotEqual,
        "Percent" => Percent,
        "Caret" => Caret,
        "Shl" => Shl,
        "Shr" => Shr,
        "AndAnd" => AndAnd,
        "OrOr" => OrOr,
        "Not" => Not,
        "Dec" => Dec,
        "LBracket" => LBracket,
        "RBracket" => RBracket,
        "LBrace" => LBrace,
        "RBrace" => RBrace,
        "String" => String,
        "GroupLParen" => GroupLParen,
        "CallLParen" => CallLParen,
        "ParamLParen" => ParamLParen,
        "IndexLBracket" => IndexLBracket,
        "ArrayLBracket" => ArrayLBracket,
        "AngleGeneric" => AngleGeneric,
        "Ampersand" => Ampersand,
        "Pipe" => Pipe,
        "Minus" => Minus,
        "PrefixPlus" => PrefixPlus,
        "InfixPlus" => InfixPlus,
        "PrefixMinus" => PrefixMinus,
        "InfixMinus" => InfixMinus,
        "GroupRParen" => GroupRParen,
        "CallRParen" => CallRParen,
        "ParamRParen" => ParamRParen,
        "ArrayRBracket" => ArrayRBracket,
        "IndexRBracket" => IndexRBracket,
        "LetIdent" => LetIdent,
        "ParamIdent" => ParamIdent,
        "TypeIdent" => TypeIdent,
        "LetAssign" => LetAssign,
        "ArgComma" => ArgComma,
        "ArrayComma" => ArrayComma,
        "ParamComma" => ParamComma,
        "TypeArrayLBracket" => TypeArrayLBracket,
        "TypeArrayRBracket" => TypeArrayRBracket,
        "TypeSemicolon" => TypeSemicolon,
        "IfLBrace" => IfLBrace,
        "IfRBrace" => IfRBrace,
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
            let s = match fs::read_to_string(&p) {
                Ok(s) => s,
                Err(err) => {
                    warn!("failed to read lex fuzz golden {}: {err}", p.display());
                    return None;
                }
            };
            match serde_json::from_str::<Golden>(&s) {
                Ok(g) => return Some(g),
                Err(e) => {
                    warn!("[golden] failed to parse {}: {e}", p.display());
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
    eprintln!("--- golden context [{from}..{hi}) ---");
    for i in from..hi {
        eprintln!(
            "#{:06} got={:?} want={:?}",
            i,
            got.get(i).map(|(k, t)| (k, t)),
            exp.get(i).map(|e| (&e.kind, &e.text))
        );
    }
}

fn main() {
    match std::env::var("LANIUS_READBACK") {
        Ok(value) => {
            if value == "0" {
                panic!("LANIUS_READBACK=0 not supported (we can't fuzz output that we can't get)");
            }
            if value != "1" && !value.eq_ignore_ascii_case("true") {
                warn!(
                    "LANIUS_READBACK has value '{value}'; expected 0/1/true/false. continuing with default enabled mode"
                );
            }
        }
        Err(_) => {
            warn!("LANIUS_READBACK is unset; using default readback-enabled mode");
        }
    }
    if let Err(err) = pollster::block_on(laniusc::lexer::gpu::lex_on_gpu("warmup")) {
        warn!("GPU warmup lex failed: {err}");
        std::process::exit(1);
    }
    if let Ok(path) = std::env::var("FUZZ_INPUT") {
        eprintln!("[replay] reading {path}");
        let s = fs::read_to_string(&path).expect("failed to read FUZZ_INPUT");
        pollster::block_on(run_once(&s, None, None, None, None));
        return;
    }

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

    let save_cases = env_bool_flag("FUZZ_SAVE", false);
    let out_dir = std::env::var("FUZZ_DIR").unwrap_or_else(|_| {
        warn!("FUZZ_DIR is unset; using default fuzz-cases");
        "fuzz-cases".to_string()
    });
    let len: usize = parse_env_or_default("FUZZ_LEN", 1_000_000usize);
    let iters: usize = parse_env_or_default("FUZZ_ITERS", 3usize);
    let seed: u64 = parse_env_or_default("FUZZ_SEED", 42u64);

    eprintln!("[fuzz] len={len} iters={iters} seed={seed}");
    let mut rng = StdRng::seed_from_u64(seed);

    if save_cases && let Err(e) = fs::create_dir_all(&out_dir) {
        eprintln!("error: failed to create {out_dir}: {e}");
        std::process::exit(1);
    }

    pollster::block_on(async move {
        for i in 0..iters {
            eprintln!("[fuzz] iter {i} ----------------");
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

async fn run_once(
    src: &str,
    seed: Option<u64>,
    iter: Option<usize>,
    len: Option<usize>,
    golden_for: Option<&Path>,
) -> bool {
    let t0 = Instant::now();
    let test_cpu = match lex_on_test_cpu(src) {
        Ok(toks) => toks,
        Err(e) => {
            eprintln!("\n[test CPU oracle] {e}");
            let tail = src.len().saturating_sub(64);
            eprintln!(
                "[tail] {:?}",
                String::from_utf8_lossy(&src.as_bytes()[tail..])
            );
            panic!("test CPU oracle lex failed");
        }
    };
    let t1 = Instant::now();
    let gpu = laniusc::lexer::gpu::lex_on_gpu(src)
        .await
        .expect("GPU lex failed");
    let t2 = Instant::now();

    let eq = compare_streams(src, &test_cpu, &gpu);
    let test_cpu_ms = (t1 - t0).as_millis();
    let gpu_ms = (t2 - t1).as_millis();

    match (seed, iter, len) {
        (Some(_seed), Some(i), Some(_l)) => eprintln!(
            "[fuzz] iter {i}: test CPU oracle/GPU {} ms/{} ms  |  test CPU oracle/GPU tokens kept = {}/{}  -> {}",
            test_cpu_ms,
            gpu_ms,
            test_cpu.len(),
            gpu.len(),
            if eq { "OK" } else { "MISMATCH!" }
        ),
        _ => eprintln!(
            "[replay] test CPU oracle/GPU {} ms/{} ms  |  test CPU oracle/GPU tokens kept = {}/{}  -> {}",
            test_cpu_ms,
            gpu_ms,
            test_cpu.len(),
            gpu.len(),
            if eq { "OK" } else { "MISMATCH!" }
        ),
    }

    let mut ok = eq;

    if let Some(p) = golden_for {
        if let Some(g) = load_golden_for(p) {
            let test_cpu_norm: Vec<(TokenKind, usize, usize)> =
                test_cpu.iter().map(|t| (t.kind, t.start, t.len)).collect();
            let gpu_norm: Vec<(TokenKind, usize, usize)> =
                gpu.iter().map(|t| (t.kind, t.start, t.len)).collect();

            let test_cpu_ok = check_against_golden("test_cpu", src, &test_cpu_norm, &g);
            let gpu_ok = check_against_golden("gpu", src, &gpu_norm, &g);

            if !test_cpu_ok || !gpu_ok {
                ok = false;
            }
        } else {
            eprintln!("[golden] no sidecar found for {}", p.display());
        }
    }
    ok
}

fn collect_examples() -> Vec<PathBuf> {
    if let Ok(list) = std::env::var("FUZZ_EX") {
        let mut out = Vec::new();
        for part in list.split([',', ':']) {
            let p = PathBuf::from(part.trim());
            if !p.as_os_str().is_empty() && p.exists() {
                out.push(p);
            }
        }
        if !out.is_empty() {
            return out;
        }
        warn!("FUZZ_EX is set but did not yield any existing .lani files");
    } else {
        warn!("FUZZ_EX is unset; checking FUZZ_EX_DIR");
    }

    let dir = std::env::var("FUZZ_EX_DIR").unwrap_or_else(|_| {
        warn!("FUZZ_EX_DIR is unset; using default lexer_tests");
        "lexer_tests".into()
    });
    let p = Path::new(&dir);
    if !p.exists() {
        warn!("example directory {dir} does not exist");
        return Vec::new();
    }
    if !p.is_dir() {
        warn!("FUZZ_EX_DIR value {dir} is not a directory");
        return Vec::new();
    }

    let mut out = Vec::new();
    let Ok(rd) = fs::read_dir(p) else {
        warn!("failed to read example directory {}", p.display());
        return Vec::new();
    };
    {
        for ent in rd {
            match ent {
                Ok(ent) => {
                    let path = ent.path();
                    if path
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(|e| e.eq_ignore_ascii_case("lani"))
                        .unwrap_or(false)
                    {
                        out.push(path);
                    }
                }
                Err(err) => warn!("failed to read an example entry from {dir}: {err}"),
            }
        }
    }
    out.sort();
    out
}

fn env_bool_flag(name: &str, default: bool) -> bool {
    let default_label = if default { "true" } else { "false" };
    match std::env::var(name) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" => true,
            "0" | "false" => false,
            _ => {
                warn!("{name} has value '{value}'; using default {default_label}");
                default
            }
        },
        Err(_) => {
            warn!("{name} is unset; using default {default_label}");
            default
        }
    }
}

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
    let ts = match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(elapsed) => elapsed.as_secs(),
        Err(err) => {
            warn!("system time before UNIX_EPOCH: {err}");
            0
        }
    };

    let base = format!("case_s{seed}_i{iter}_n{}.lani", src.len());
    let path = Path::new(dir).join(base);

    if let Err(err) = fs::write(&path, src.as_bytes()) {
        warn!("failed to write fuzz case {}: {err}", path.display());
    }

    let meta = CaseMeta {
        unix_ts: ts,
        seed: Some(seed),
        iter: Some(iter),
        requested_len: None,
        actual_bytes: src.len(),
        note: "Replay with: FUZZ_INPUT=<this file> cargo run --bin lex_fuzz",
    };
    let meta_path = path.with_extension("json");
    match fs::File::create(&meta_path) {
        Ok(mut f) => {
            let meta = serde_json::to_string_pretty(&meta).unwrap_or_else(|err| {
                let msg = format!("failed to serialize meta for {path:?}: {err}");
                warn!("{msg}");
                format!("{{\"error\": \"{}\"}}", msg.replace('"', "\\\""))
            });
            if let Err(err) = writeln!(f, "{}", meta) {
                warn!("failed to write fuzz meta {}: {err}", meta_path.display());
            }
        }
        Err(err) => warn!("failed to create fuzz meta {}: {err}", meta_path.display()),
    }

    path
}

fn parse_env_or_default<T>(name: &str, default: T) -> T
where
    T: std::str::FromStr + Copy + std::fmt::Debug,
    <T as std::str::FromStr>::Err: std::fmt::Display,
{
    match std::env::var(name) {
        Ok(raw) => match raw.parse::<T>() {
            Ok(value) => value,
            Err(err) => {
                warn!("invalid {name} value '{raw}': {err}; using default {default:?}");
                default
            }
        },
        Err(_) => {
            warn!("{name} is unset; using default {default:?}");
            default
        }
    }
}

fn compare_streams(
    src: &str,
    test_cpu: &[TestCpuToken],
    gpu: &[laniusc::lexer::gpu::Token],
) -> bool {
    if test_cpu.len() != gpu.len() {
        let i = first_divergence_idx(test_cpu, gpu);
        eprintln!(
            "[diff] token count mismatch: test_cpu={} gpu={} (first divergence at index {})",
            test_cpu.len(),
            gpu.len(),
            i
        );
        dump_near(src, test_cpu, gpu, i.saturating_sub(1));

        let min_len = test_cpu.len().min(gpu.len());
        if i == min_len {
            if test_cpu.len() > gpu.len() {
                eprintln!("--- extra test CPU oracle tokens starting at {min_len} ---");
                for j in min_len..(min_len + 6).min(test_cpu.len()) {
                    let t = &test_cpu[j];
                    let text = &src.as_bytes()[t.start..t.start + t.len];
                    eprintln!(
                        "#{:06} test CPU oracle extra = {:?} @{}+{} {:?}",
                        j,
                        t.kind,
                        t.start,
                        t.len,
                        String::from_utf8_lossy(text)
                    );
                }
            } else {
                eprintln!("--- extra GPU tokens starting at {min_len} ---");
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

    for (idx, (ct, gt)) in test_cpu.iter().zip(gpu.iter()).enumerate() {
        if ct.kind as u32 != gt.kind as u32 || ct.start != gt.start || ct.len != gt.len {
            eprintln!(
                "[diff] token {} mismatch:\n  test CPU oracle: kind={:?} start={} len={}\n  GPU: kind={:?} start={} len={}",
                idx, ct.kind, ct.start, ct.len, gt.kind, gt.start, gt.len
            );

            dump_src_window(src, ct.start, ct.len, "test CPU oracle", idx);
            dump_src_window(src, gt.start, gt.len, "GPU", idx);

            dump_near(src, test_cpu, gpu, idx.saturating_sub(1));
            return false;
        }
    }
    true
}

fn first_divergence_idx(test_cpu: &[TestCpuToken], gpu: &[laniusc::lexer::gpu::Token]) -> usize {
    let n = test_cpu.len().min(gpu.len());
    for i in 0..n {
        let ct = &test_cpu[i];
        let gt = &gpu[i];
        if ct.kind as u32 != gt.kind as u32 || ct.start != gt.start || ct.len != gt.len {
            return i;
        }
    }
    n
}

fn line_col_at(src: &str, byte_idx: usize) -> (usize, usize) {
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

const MAX_SNIP_WINDOW: usize = 1024;
const TOK_HEAD_BYTES: usize = 10;
const TOK_TAIL_BYTES: usize = 10;

fn preview_lossy(bytes: &[u8], head: usize, tail: usize) -> String {
    if bytes.len() <= head + tail {
        return String::from_utf8_lossy(bytes).into_owned();
    }
    let head_s = String::from_utf8_lossy(&bytes[..head]);
    let tail_s = String::from_utf8_lossy(&bytes[bytes.len() - tail..]);
    format!(
        "{}…(+{} bytes)…{}",
        head_s,
        bytes.len() - head - tail,
        tail_s
    )
}

fn dump_src_window(src: &str, start: usize, len: usize, who: &str, idx: usize) {
    let bytes = src.as_bytes();
    let full_lo = start.saturating_sub(64);
    let full_hi = (start + len + 64).min(src.len());
    let full_len = full_hi.saturating_sub(full_lo);
    let (line, col) = line_col_at(src, start);

    eprintln!(
        "[src:{who} idx={idx}] token @{start}+{len} (line {line}, col {col})  window [{full_lo}..{full_hi}]"
    );

    if full_len <= MAX_SNIP_WINDOW {
        let snippet = String::from_utf8_lossy(&bytes[full_lo..full_hi]);
        eprintln!("    {snippet:?}");
    } else {
        let before = &bytes[full_lo..start];
        let token_end = (start + len).min(src.len());
        let token = &bytes[start..token_end];
        let after_end = (token_end + 64).min(src.len());
        let after = &bytes[token_end..after_end];

        let snippet = format!(
            "{}{}{}",
            String::from_utf8_lossy(&before[..before.len().min(64)]),
            preview_lossy(token, TOK_HEAD_BYTES, TOK_TAIL_BYTES),
            String::from_utf8_lossy(after)
        );
        eprintln!("    {snippet:?}");
    }

    let caret_pos = start.saturating_sub(full_lo);
    let caret_len = len.max(1).min(80);
    let mut underline = String::new();
    underline.push_str(&" ".repeat(caret_pos));
    underline.push_str(&"^".repeat(caret_len));
    eprintln!("    {underline}");
}

fn dump_near(
    src: &str,
    test_cpu: &[TestCpuToken],
    gpu: &[laniusc::lexer::gpu::Token],
    from_idx: usize,
) {
    let lo = from_idx;
    let last_index = test_cpu.len().min(gpu.len());
    let hi = (from_idx + 3).min(last_index);
    eprintln!("gpu len {} test_cpu len {}", gpu.len(), test_cpu.len());
    eprintln!("--- context tokens [{lo}..{hi}) ---");
    let bytes = src.as_bytes();
    for i in lo..hi {
        let test_cpu_dbg = test_cpu.get(i).map(|t| {
            let len = t.len.min(src.len() - t.start);
            let s = &bytes[t.start..t.start + len];
            (t.kind, t.start, len, preview_lossy(s, 10, 10))
        });
        let gpu_dbg = gpu.get(i).map(|t| {
            let len = t.len.min(src.len() - t.start);
            let s = &bytes[t.start..t.start + len];
            (t.kind, t.start, len, preview_lossy(s, 10, 10))
        });
        let same = if test_cpu_dbg == gpu_dbg {
            "\u{2705}"
        } else {
            "\u{274c}"
        };
        eprintln!("{same} #{i:06} test_cpu={test_cpu_dbg:?} GPU={gpu_dbg:?}");
    }
}
