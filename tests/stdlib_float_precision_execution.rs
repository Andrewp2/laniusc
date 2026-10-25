#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

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
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_float_precision", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("tests/fixtures/stdlib_foundation/float_precision_model.lani"))
}
fn invoke(
    single: bool,
    style: char,
    precision: usize,
    alternate: bool,
    uppercase: bool,
    bits: &[u64],
) -> Vec<String> {
    let mut output = vec![];
    for chunk in bits.chunks(128) {
        let result = common::process_output_with_timeout(
            "float precision model",
            Command::new(model().path())
                .args([
                    if single { "f32" } else { "f64" },
                    &style.to_string(),
                    &precision.to_string(),
                    if alternate { "1" } else { "0" },
                    if uppercase { "1" } else { "0" },
                ])
                .args(chunk.iter().map(u64::to_string)),
            Duration::from_secs(15),
        );
        assert_eq!(result.status.code(), Some(0), "{result:?}");
        assert!(result.stderr.is_empty(), "{result:?}");
        let rows: Vec<_> = String::from_utf8(result.stdout)
            .unwrap()
            .lines()
            .map(str::to_owned)
            .collect();
        assert_eq!(rows.len(), chunk.len());
        output.extend(rows);
    }
    output
}
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

#[test]
fn precision_contracts_views_atomic_errors_limits_and_no_allocation_execute() {
    let exe = executable("tests/fixtures/stdlib_foundation/float_precision_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_float_precision", "trace", None);
    let result = common::process_output_with_timeout(
        "float precision contracts",
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

#[test]
fn exact_ties_and_decimal_not_shortest_text_rounding_match_known_values() {
    let bits: Vec<_> = [
        0.5f64, 1.5, 2.5, 3.5, -0.5, -2.5, 1.25, 1.75, 2.675, 0.15, 9.999, 99.95,
    ]
    .iter()
    .map(|v| v.to_bits())
    .collect();
    assert_eq!(
        invoke(false, 'f', 0, false, false, &bits[..6]),
        ["0", "2", "2", "4", "-0", "-2"]
    );
    assert_eq!(
        invoke(false, 'f', 1, false, false, &bits[6..10]),
        ["1.2", "1.8", "2.7", "0.1"]
    );
    assert_eq!(invoke(false, 'f', 2, false, false, &bits[8..9]), ["2.67"]);
    assert_eq!(
        invoke(false, 'g', 3, true, false, &bits[10..]),
        ["10.0", "100."]
    );
    assert_eq!(
        invoke(
            false,
            'e',
            0,
            true,
            true,
            &[0, 1f64.to_bits(), 0x8000000000000000]
        ),
        ["0.E+00", "1.E+00", "-0.E+00"]
    );
}

// Python's format is one independent oracle; Fraction quantization below also
// checks exact nearest-even rounding without going through decimal float text.
fn check_oracle(single: bool, bits: &[u64], options: &[(char, usize, bool, bool)]) {
    let mut rows = vec![];
    for &(style, precision, alternate, uppercase) in options {
        let actual = invoke(single, style, precision, alternate, uppercase, bits);
        for (&bits, actual) in bits.iter().zip(actual) {
            rows.push(format!(
                "{} {bits} {style} {precision} {} {} {actual}",
                if single { 32 } else { 64 },
                u8::from(alternate),
                u8::from(uppercase)
            ));
        }
    }
    let cases = common::TempArtifact::new("laniusc_float_precision", "oracle", None);
    cases.write_bytes(rows.join("\n"));
    let script = r#"import sys,struct,math,decimal,fractions
for line in sys.stdin:
    width,bits,style,p,alt,upper,actual=line.split(); width=int(width); bits=int(bits); p=int(p); alt=int(alt); upper=int(upper)
    x=struct.unpack('>f' if width==32 else '>d',bits.to_bytes(width//8,'big'))[0]
    spec=('#' if alt else '')+'.'+str(p)+(style.upper() if upper else style)
    expected=format(x,spec)
    assert actual==expected,(width,hex(bits),spec,actual,expected)
    if not math.isfinite(x): continue
    r=fractions.Fraction.from_float(abs(x)); pp=max(1,p) if style=='g' else p
    order=decimal.Decimal.from_float(abs(x)).adjusted() if x else 0
    q=-pp if style=='f' else order-pp+(1 if style=='g' else 0)
    quantum=fractions.Fraction(10**q) if q>=0 else fractions.Fraction(1,10**-q)
    n,d=(r/quantum).as_integer_ratio(); k,rem=divmod(n,d)
    if 2*rem>d or (2*rem==d and k%2): k+=1
    rounded=fractions.Fraction(decimal.Decimal(actual)); target=k*quantum
    assert abs(rounded)==target,(width,hex(bits),spec,actual,target)
"#;
    let result = common::process_output_with_timeout(
        "Python builtin and Fraction exact precision oracle",
        Command::new("python3")
            .args(["-c", script])
            .stdin(std::fs::File::open(cases.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}

#[test]
fn all_binary_exponents_transition_neighbors_and_random_encodings_match_python_and_exact_fraction()
{
    let mut state = 0xdead_3aca_f193_c842;
    for single in [true, false] {
        let fraction_bits = if single { 23 } else { 52 };
        let max_exponent = if single { 255 } else { 2047 };
        let sign = 1u64 << if single { 31 } else { 63 };
        let mask = (1u64 << fraction_bits) - 1;
        let mut bits = vec![];
        for exponent in 0..=max_exponent {
            for fraction in [0, 1, mask] {
                let value = (exponent << fraction_bits) | fraction;
                bits.push(value);
                bits.push(value | sign);
            }
        }
        bits.extend((0..1024).map(|_| {
            let value = next(&mut state);
            if single {
                value as u32 as u64
            } else {
                value
            }
        }));
        check_oracle(
            single,
            &bits,
            &[
                ('f', 0, false, false),
                ('f', 6, false, false),
                ('e', 0, false, false),
                ('e', 16, true, true),
                ('g', 0, false, false),
                ('g', 6, false, false),
                ('g', 17, true, true),
            ],
        );
    }
}

#[test]
fn precision_endpoints_ties_decimal_powers_and_extrema_match_independent_oracles() {
    for single in [true, false] {
        let mut bits = if single {
            vec![
                0, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0x80000000, 0xff7fffff, 0x7f800000,
                0xff800000, 0x7f800001, 0xffc12345,
            ]
        } else {
            vec![
                0,
                1,
                0xfffffffffffff,
                0x10000000000000,
                0x7fefffffffffffff,
                0x8000000000000000,
                0xffefffffffffffff,
                0x7ff0000000000000,
                0xfff0000000000000,
                0x7ff0000000000001,
                0xfff8000000001234,
            ]
        };
        for value in [
            0.5f64,
            1.5,
            2.5,
            1.25,
            1.75,
            0.15,
            2.675,
            9.999,
            99.95,
            0.00009999999,
            0.00001,
            1e-4,
            1e6,
            1e20,
        ] {
            let middle = if single {
                (value as f32).to_bits() as u64
            } else {
                value.to_bits()
            };
            bits.extend([middle - 1, middle, middle + 1]);
        }
        check_oracle(
            single,
            &bits,
            &[
                ('f', 1, false, false),
                ('f', 2, true, true),
                ('f', 767, false, false),
                ('f', 768, true, false),
                ('e', 768, true, true),
                ('g', 1, true, false),
                ('g', 767, false, false),
                ('g', 768, true, true),
            ],
        );
    }
}
