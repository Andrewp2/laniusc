#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::Command,
    sync::OnceLock,
    time::{Duration, Instant},
};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_float_decimal", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("tests/fixtures/stdlib_foundation/float_decimal_model.lani"))
}
fn invoke(mode: &str, inputs: &[String]) -> Vec<String> {
    let mut rows = Vec::new();
    for chunk in inputs.chunks(128) {
        let result = common::process_output_with_timeout(
            "native float-decimal model",
            Command::new(model().path()).arg(mode).args(chunk),
            Duration::from_secs(15),
        );
        assert_eq!(result.status.code(), Some(0), "mode={mode} {result:?}");
        assert!(result.stderr.is_empty(), "{result:?}");
        let values: Vec<_> = std::str::from_utf8(&result.stdout)
            .unwrap()
            .lines()
            .map(str::to_owned)
            .collect();
        assert_eq!(values.len(), chunk.len());
        rows.extend(values);
    }
    rows
}
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}
fn parts(text: &str) -> (bool, u64, i32) {
    let negative = text.starts_with('-');
    let text = text.trim_start_matches(['-', '+']);
    let (mantissa, exponent) = text
        .split_once(['e', 'E'])
        .map_or((text, 0), |(m, e)| (m, e.parse::<i32>().unwrap()));
    let fraction = mantissa.split_once('.').map_or(0, |(_, f)| f.len() as i32);
    let joined = mantissa.replace('.', "");
    let joined = joined.trim_start_matches('0');
    if joined.is_empty() {
        return (negative, 0, 0);
    }
    let trimmed = joined.trim_end_matches('0');
    let exponent = exponent - fraction + (joined.len() - trimmed.len()) as i32;
    (negative, trimmed.parse().unwrap(), exponent)
}
#[test]
fn bounds_strides_capacity_atomicity_resources_and_no_allocation_execute() {
    let exe = executable("tests/fixtures/stdlib_foundation/float_decimal_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_float_decimal", "trace", None);
    let result = common::process_output_with_timeout(
        "float decimal contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,brk,open,openat,socket,connect",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
fn check_formats(single: bool, bits: &[u64]) {
    let mode = if single { "f32" } else { "f64" };
    let inputs: Vec<_> = bits.iter().map(u64::to_string).collect();
    let outputs = invoke(mode, &inputs);
    let mut ties = Vec::new();
    for (&bits, text) in bits.iter().zip(outputs) {
        if single {
            let value = f32::from_bits(bits as u32);
            if value.is_nan() {
                assert_eq!(text, "NaN");
                continue;
            }
            if value.is_infinite() {
                assert_eq!(
                    text,
                    if value.is_sign_negative() {
                        "-inf"
                    } else {
                        "inf"
                    }
                );
                continue;
            }
            assert_eq!(
                text.parse::<f32>().unwrap().to_bits(),
                bits as u32,
                "bits{bits:08x} {text}"
            );
            check_shortest(single, bits, &text, &value.to_string(), &mut ties);
        } else {
            let value = f64::from_bits(bits);
            if value.is_nan() {
                assert_eq!(text, "NaN");
                continue;
            }
            if value.is_infinite() {
                assert_eq!(
                    text,
                    if value.is_sign_negative() {
                        "-inf"
                    } else {
                        "inf"
                    }
                );
                continue;
            }
            assert_eq!(
                text.parse::<f64>().unwrap().to_bits(),
                bits,
                "bits{bits:016x} {text}"
            );
            check_shortest(single, bits, &text, &value.to_string(), &mut ties);
        }
        assert!(!text.contains('E') && !text.contains('+'));
        if let Some((_, exponent)) = text.split_once('e') {
            assert!(!exponent.trim_start_matches('-').starts_with('0') || exponent == "0");
        }
    }
    if !ties.is_empty() {
        // Rust's Display chooses the away decimal candidate at some exact
        // halfway cases. Our specified decimal tie policy chooses even. Prove
        // those differences using standard-library exact rationals, rather
        // than accepting an arbitrary last-digit disagreement.
        let file = common::TempArtifact::new("laniusc_float_decimal", "ties", None);
        file.write_bytes(ties.join("\n"));
        let script = "import sys,struct,decimal,fractions\nfor line in sys.stdin:\n width,bits,a,b,coefficient=line.split();x=struct.unpack('>f' if width=='32' else '>d',int(bits).to_bytes(int(width)//8,'big'))[0];x=fractions.Fraction.from_float(x);a=fractions.Fraction(decimal.Decimal(a));b=fractions.Fraction(decimal.Decimal(b));assert abs(x-a)==abs(x-b),(line,x,a,b);assert int(coefficient)%2==0,line\n";
        let result = common::process_output_with_timeout(
            "exact decimal formatting tie oracle",
            Command::new("python3")
                .args(["-c", script])
                .stdin(std::fs::File::open(file.path()).unwrap()),
            Duration::from_secs(10),
        );
        assert_eq!(result.status.code(), Some(0), "{result:?}");
        assert!(
            result.stdout.is_empty() && result.stderr.is_empty(),
            "{result:?}"
        );
    }
}
fn check_shortest(single: bool, bits: u64, text: &str, reference: &str, ties: &mut Vec<String>) {
    let actual = parts(text);
    let expected = parts(reference);
    assert_eq!(
        (actual.0, actual.1.to_string().len(), actual.2),
        (expected.0, expected.1.to_string().len(), expected.2),
        "shortest significant digits: {bits:016x} {text} vs {reference}"
    );
    if actual != expected {
        assert_eq!(
            actual.1.abs_diff(expected.1),
            1,
            "{bits:016x} {text} vs {reference}"
        );
        assert_eq!(actual.1 % 2, 0, "{bits:016x} {text} vs {reference}");
        ties.push(format!(
            "{} {bits} {text} {reference} {}",
            if single { 32 } else { 64 },
            actual.1
        ));
    }
}
#[test]
fn binary32_shortest_formats_match_independent_rust_across_exponents_edges_and_random_bits() {
    let mut bits = Vec::new();
    for exponent in 0..=255u64 {
        for fraction in [0, 1, 0x3fffff, 0x7fffff] {
            for sign in [0, 1u64 << 31] {
                bits.push(sign | (exponent << 23) | fraction);
            }
        }
    }
    let mut state = 0xcafe_dead_beef_1234;
    bits.extend((0..4096).map(|_| next(&mut state) as u32 as u64));
    check_formats(true, &bits);
}
#[test]
fn binary64_shortest_formats_match_independent_rust_across_exponents_asymmetric_bounds_and_random_bits()
 {
    let mut bits = Vec::new();
    for exponent in 0..=2047u64 {
        for fraction in [0, 1, 0x7ffffffffffff, 0xfffffffffffff] {
            for sign in [0, 1u64 << 63] {
                bits.push(sign | (exponent << 52) | fraction);
            }
        }
    }
    let mut state = 0x1234_beef_dead_cafe;
    bits.extend((0..4096).map(|_| next(&mut state)));
    check_formats(false, &bits);
}
#[test]
fn parses_explicit_grammar_specials_random_decimals_and_extreme_exponents_like_rust() {
    let mut inputs: Vec<String> = [
        "0",
        "-0",
        "+0",
        ".5",
        "1.",
        "+00001.2500e+2",
        "1e309",
        "1e-325",
        "1e999999999999999999999999",
        "-1e-9999999999999999999999",
        "0e99999999999999999999999",
        "1.7976931348623157e308",
        "2.2250738585072014e-308",
        "4.9406564584124654e-324",
        "1.1754943508222875e-38",
        "1.401298464324817e-45",
        "3.4028234663852886e38",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    let mut state = 0xdeaf_beef_cafe_8765;
    for index in 0..4096 {
        let count = 1 + (next(&mut state) % 80) as usize;
        let mut text = if next(&mut state) & 1 == 0 {
            String::new()
        } else {
            "-".to_owned()
        };
        for digit in 0..count {
            text.push((b'0' + (next(&mut state) % 10) as u8) as char);
            if digit == count / 2 {
                text.push('.')
            }
        }
        text.push('e');
        text.push_str(&((next(&mut state) % 900) as i32 - 450).to_string());
        if index % 3 == 0 {
            text.insert(0, '+');
            if text.starts_with("+-") {
                text.remove(1);
            }
        }
        inputs.push(text);
    }
    for single in [false, true] {
        let output = invoke(if single { "p32" } else { "p64" }, &inputs);
        for (text, result) in inputs.iter().zip(output) {
            let expected = if single {
                text.parse::<f32>().unwrap().to_bits() as u64
            } else {
                text.parse::<f64>().unwrap().to_bits()
            };
            assert_eq!(result, expected.to_string(), "{single} {text}");
        }
    }
    for single in [false, true] {
        let width = if single { 32 } else { 64 };
        let specials: Vec<_> = [
            "inf",
            "INF",
            "Infinity",
            "+inFINITY",
            "-INF",
            "nan",
            "NaN",
            "-nAn",
        ]
        .into_iter()
        .map(str::to_owned)
        .collect();
        for (text, result) in specials
            .iter()
            .zip(invoke(if single { "p32" } else { "p64" }, &specials))
        {
            let bits: u64 = result.parse().unwrap();
            let negative = text.starts_with('-');
            let nan = text.to_ascii_lowercase().contains("nan");
            let sign = if negative { 1u64 << (width - 1) } else { 0 };
            let base = if single {
                if nan { 0x7fc00000 } else { 0x7f800000 }
            } else {
                if nan {
                    0x7ff8000000000000
                } else {
                    0x7ff0000000000000
                }
            };
            assert_eq!(bits, sign | base, "{text}");
        }
    }
}
#[test]
fn exact_halfway_and_decisive_long_digits_round_ties_to_even_including_subnormal_boundaries() {
    let script = r#"import sys
def decimal(n,e):
 if e>=0:m=n<<e;q=0
 else:m=n*5**(-e);q=e
 while m and m%10==0:m//=10;q+=1
 return m,q
for width in (32,64):
 f,bias,maxexp=(23,127,254) if width==32 else (52,1023,2046)
 seeds=[0,1,2,3,(1<<f)-1,1<<f,(1<<f)+1,((maxexp<<f)|((1<<f)-1))]
 for exponent in [1,2,10,bias-1,bias,bias+1,maxexp-1,maxexp]:
  for fraction in [0,1,(1<<f)-2,(1<<f)-1]:seeds.append((exponent<<f)|fraction)
 for bits in seeds:
  frac=bits&((1<<f)-1);biased=bits>>f;m=frac if not biased else (1<<f)|frac;e=(1-bias-f) if not biased else (biased-bias-f)
  coef,q=decimal(4*m+2,e-2)
  for delta in (-1,0,1):
   text=str(coef+delta)+'e'+str(q)
   if len(str(coef+delta))<=768:
    print(width,text);print(width,'-'+text)
"#;
    let result = common::process_output_with_timeout(
        "exact decimal midpoint reference",
        Command::new("python3").args(["-c", script]),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(result.stderr.is_empty());
    let text = std::str::from_utf8(&result.stdout).unwrap();
    for single in [false, true] {
        let prefix = if single { "32 " } else { "64 " };
        let inputs: Vec<_> = text
            .lines()
            .filter_map(|line| line.strip_prefix(prefix).map(str::to_owned))
            .collect();
        assert!(inputs.iter().any(|s| s.len() > 700) || single);
        let outputs = invoke(if single { "p32" } else { "p64" }, &inputs);
        for (text, result) in inputs.iter().zip(outputs) {
            let expected = if single {
                text.parse::<f32>().unwrap().to_bits() as u64
            } else {
                text.parse::<f64>().unwrap().to_bits()
            };
            assert_eq!(result, expected.to_string(), "width{single} halfway {text}");
        }
    }
}
#[test]
fn rejects_malformed_overlong_and_excess_digit_inputs_with_explicit_offsets() {
    let invalid = [
        ("", 100),
        ("+", 101),
        ("-", 101),
        (".", 101),
        (".e1", 101),
        ("1e", 102),
        ("1e+", 103),
        ("1e-", 103),
        ("1e1x", 103),
        ("1..", 102),
        ("1_0", 101),
        (" 1", 100),
        ("1 ", 101),
        ("0x1p0", 101),
        ("NaN(payload)", 100),
        ("infi", 100),
        ("∞", 100),
    ];
    let mut inputs: Vec<_> = invalid.iter().map(|(text, _)| text.to_string()).collect();
    inputs.push("0".repeat(769));
    inputs.push("0".repeat(1025));
    for mode in ["p32", "p64"] {
        let outputs = invoke(mode, &inputs);
        for ((text, code), result) in invalid.iter().zip(&outputs) {
            assert_eq!(result, &format!("E{code}"), "{mode} {text:?}");
        }
        assert_eq!(outputs[invalid.len()], "E4");
        assert_eq!(outputs[invalid.len() + 1], "E3");
    }
}
#[test]
fn representative_native_batch_handles_extreme_exponents_with_a_bounded_scratch_and_work_budget() {
    let mut state = 0x9876_abcd_dead_beef;
    let bits: Vec<_> = (0..2048).map(|_| next(&mut state)).collect();
    model();
    let start = Instant::now();
    check_formats(false, &bits);
    eprintln!(
        "2048 native binary64 shortest formats including process/model transport: {:.3}ms",
        start.elapsed().as_secs_f64() * 1000.0
    );
}
