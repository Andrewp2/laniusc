use std::time::Instant;

use laniusc::{
    compiler::{GpuCompiler, compile_source_to_wasm_with_gpu_codegen_using},
    gpu::device,
};

fn main() {
    if let Err(err) = pollster::block_on(run()) {
        eprintln!("gpu_compile_bench: {err}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let mut lines = 100_000usize;
    let mut target_bytes: Option<usize> = None;
    let mut iters = 3usize;
    let mut warmups = 1usize;
    let mut validate_output = false;
    let mut source_mode = SourceMode::SimpleLets;
    let mut seed = 0xc0de_5eed_u64;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--lines" => {
                lines = parse_usize("--lines", args.next())?;
            }
            "--target-bytes" => {
                target_bytes = Some(parse_usize("--target-bytes", args.next())?);
            }
            "--iters" => {
                iters = parse_usize("--iters", args.next())?;
            }
            "--warmups" => {
                warmups = parse_usize("--warmups", args.next())?;
            }
            "--source" | "--mode" => {
                source_mode = parse_source_mode(args.next())?;
            }
            flag if flag.starts_with("--source=") => {
                source_mode =
                    parse_source_mode(Some(flag.trim_start_matches("--source=").to_string()))?
            }
            flag if flag.starts_with("--mode=") => {
                source_mode =
                    parse_source_mode(Some(flag.trim_start_matches("--mode=").to_string()))?
            }
            "--seed" => {
                seed = parse_u64("--seed", args.next())?;
            }
            "--validate-output" => {
                validate_output = true;
            }
            "--emit" => require_wasm_emit(args.next())?,
            flag if flag.starts_with("--emit=") => {
                require_wasm_emit(Some(flag.trim_start_matches("--emit=").to_string()))?
            }
            "-h" | "--help" => {
                print_help();
                return Ok(());
            }
            flag => return Err(format!("unknown flag {flag}")),
        }
    }

    let src = make_source(source_mode, lines, target_bytes, seed);
    let source_lines = src.lines().count();
    let compiler = GpuCompiler::new_with_device(device::global())
        .await
        .map_err(|err| err.to_string())?;

    for _ in 0..warmups {
        let wasm = compile_source_to_wasm_with_gpu_codegen_using(&src, &compiler)
            .await
            .map_err(|err| err.to_string())?;
        validate_wasm_output(validate_output, &wasm, "warmup")?;
    }

    let mut best_ms = f64::INFINITY;
    let mut total_ms = 0.0f64;
    let mut output_bytes = 0usize;
    for _ in 0..iters {
        let start = Instant::now();
        let emitted = compile_source_to_wasm_with_gpu_codegen_using(&src, &compiler)
            .await
            .map_err(|err| err.to_string())?;
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
        best_ms = best_ms.min(elapsed_ms);
        total_ms += elapsed_ms;
        output_bytes = emitted.len();
        validate_wasm_output(validate_output, &emitted, "measured")?;
    }

    let avg_ms = if iters == 0 {
        0.0
    } else {
        total_ms / iters as f64
    };
    println!(
        "emit={} source={} lines={source_lines} bytes={} output_bytes={output_bytes} warmups={warmups} iters={iters} best_ms={best_ms:.3} avg_ms={avg_ms:.3}",
        "wasm",
        source_mode.name(),
        src.len()
    );
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SourceMode {
    SimpleLets,
    Mixed,
}

impl SourceMode {
    fn name(self) -> &'static str {
        match self {
            SourceMode::SimpleLets => "simple-lets",
            SourceMode::Mixed => "mixed",
        }
    }
}

fn require_wasm_emit(value: Option<String>) -> Result<(), String> {
    match value
        .ok_or_else(|| "--emit requires a value".to_string())?
        .as_str()
    {
        "wasm" => Ok(()),
        other => Err(format!("unsupported --emit {other:?}; expected wasm")),
    }
}

fn validate_wasm_output(enabled: bool, wasm: &[u8], phase: &str) -> Result<(), String> {
    if !enabled {
        return Ok(());
    }
    if !is_lanius_wasm_module(wasm) {
        return Err(format!("{phase} output is not the expected WASM module"));
    }
    Ok(())
}

fn is_lanius_wasm_module(bytes: &[u8]) -> bool {
    bytes.len() >= 60
        && bytes[0..8] == [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
        && contains_bytes(bytes, b"\x03env\x09print_i64")
        && contains_bytes(bytes, b"\x04main\x00")
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

fn parse_usize(flag: &str, value: Option<String>) -> Result<usize, String> {
    value
        .ok_or_else(|| format!("{flag} requires a value"))?
        .parse::<usize>()
        .map_err(|err| format!("parse {flag}: {err}"))
}

fn parse_u64(flag: &str, value: Option<String>) -> Result<u64, String> {
    value
        .ok_or_else(|| format!("{flag} requires a value"))?
        .parse::<u64>()
        .map_err(|err| format!("parse {flag}: {err}"))
}

fn parse_source_mode(value: Option<String>) -> Result<SourceMode, String> {
    match value
        .ok_or_else(|| "--source requires a value".to_string())?
        .as_str()
    {
        "simple" | "simple-let" | "simple-lets" | "lets" => Ok(SourceMode::SimpleLets),
        "mixed" => Ok(SourceMode::Mixed),
        other => Err(format!(
            "unsupported --source {other:?}; expected simple-lets or mixed"
        )),
    }
}

fn make_source(
    source_mode: SourceMode,
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> String {
    match source_mode {
        SourceMode::SimpleLets => make_simple_let_source(lines, target_bytes),
        SourceMode::Mixed => make_mixed_source(lines, target_bytes, seed),
    }
}

fn make_simple_let_source(lines: usize, target_bytes: Option<usize>) -> String {
    if let Some(target_bytes) = target_bytes {
        let mut src = String::with_capacity(target_bytes.saturating_add(128));
        let mut i = 0usize;
        while src.len() < target_bytes {
            push_simple_let_line(&mut src, i);
            i += 1;
        }
        return src;
    }

    let mut src = String::with_capacity(lines.saturating_mul(18).saturating_add(64));
    for i in 0..lines {
        push_simple_let_line(&mut src, i);
    }
    src
}

fn push_simple_let_line(src: &mut String, i: usize) {
    src.push_str("let x");
    src.push_str(&i.to_string());
    src.push_str(" = ");
    src.push_str(&(i % 1024).to_string());
    src.push_str(";\n");
}

fn make_mixed_source(lines: usize, target_bytes: Option<usize>, seed: u64) -> String {
    let mut src = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(48)));
    let mut rng = DeterministicRng::new(seed);
    let mut line_count = 0usize;
    let mut chunk = 0usize;
    loop {
        if target_bytes.is_some_and(|target| src.len() >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }
        line_count += push_mixed_chunk(&mut src, chunk, &mut rng);
        chunk += 1;
    }
    src
}

fn push_mixed_chunk(src: &mut String, chunk: usize, rng: &mut DeterministicRng) -> usize {
    match chunk % 4 {
        0 => push_bool_let_chunk(src, chunk, rng),
        1 => push_if_else_chunk(src, chunk, rng),
        2 => push_compare_print_chunk(src, chunk, rng),
        _ => push_logic_chunk(src, chunk, rng),
    }
}

fn push_bool_let_chunk(src: &mut String, chunk: usize, rng: &mut DeterministicRng) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    if chunk % 32 != 0 {
        src.push_str(&format!(
            "if (({a} < {b}) && !({} == {})) {{\n",
            rng.small_int(),
            rng.small_int()
        ));
        src.push_str(&format!("    print({a});\n"));
        src.push_str("} else {\n");
        src.push_str(&format!("    print({b});\n"));
        src.push_str("}\n");
        return 5;
    }

    src.push_str(&format!(
        "let flag{chunk}: bool = ({a} < {b}) && !({} == {});\n",
        rng.small_int(),
        rng.small_int()
    ));
    src.push_str(&format!("if (flag{chunk}) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({b});\n"));
    src.push_str("}\n");
    6
}

fn push_if_else_chunk(src: &mut String, chunk: usize, rng: &mut DeterministicRng) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    src.push_str(&format!("if (({a} <= {b}) || !({b} != {a})) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({b});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

fn push_compare_print_chunk(src: &mut String, chunk: usize, rng: &mut DeterministicRng) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    src.push_str(&format!("if (({a} >= {b}) || ({a} == {c})) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({c});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

fn push_logic_chunk(src: &mut String, chunk: usize, rng: &mut DeterministicRng) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    src.push_str(&format!("if (!(({a} > {b}) && ({b} <= {c}))) {{\n"));
    src.push_str(&format!("    print({b});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({c});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

struct DeterministicRng {
    state: u64,
}

impl DeterministicRng {
    fn new(seed: u64) -> Self {
        Self { state: seed | 1 }
    }

    fn next_u32(&mut self) -> u32 {
        self.state = self
            .state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1);
        (self.state >> 32) as u32
    }

    fn small_int(&mut self) -> u32 {
        self.next_u32() % 64
    }
}

fn print_help() {
    eprintln!(
        "Usage: gpu_compile_bench [--emit wasm] [--source simple-lets|mixed] [--lines N] [--target-bytes N] [--seed N] [--warmups N] [--iters N] [--validate-output]\n\
         Measures reused GpuCompiler runtime after construction."
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixed_source_is_deterministic_and_diverse() {
        let a = make_source(SourceMode::Mixed, 80, None, 123);
        let b = make_source(SourceMode::Mixed, 80, None, 123);
        assert_eq!(a, b);
        assert!(a.contains("if ("));
        assert!(a.contains("&&"));
        assert!(a.contains("||"));
        assert!(a.contains("!("));
        assert!(a.contains(": bool"));
        assert!(a.contains("print("));
    }

    #[test]
    fn target_bytes_generates_at_least_requested_size() {
        let src = make_source(SourceMode::Mixed, 0, Some(10_000), 123);
        assert!(src.len() >= 10_000);
    }
}
