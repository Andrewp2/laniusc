use std::{fs, process::Command};

mod common;

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_binary_module() {
    let src = r#"
fn main() {
    let a = 1 + 2 * 3;
    let b = (1 + 2) * 3;
    print(a);
    print(b);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "7\n9\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_cli_emits_wasm_file() {
    let src_path = common::TempArtifact::new("laniusc_gpu_wasm", "cli_source", Some("lani"));
    let out_path = common::TempArtifact::new("laniusc_gpu_wasm", "cli_output", Some("wasm"));
    src_path.write_str("let x = 1;\n");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let mut command = Command::new(bin);
    command
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg("--emit")
        .arg("wasm")
        .arg(src_path.path())
        .arg("-o")
        .arg(out_path.path());
    let output = common::command_output_with_timeout("laniusc --emit wasm", &mut command);

    common::assert_command_success("laniusc --emit wasm", &output);
    let wasm = fs::read(out_path.path()).expect("read emitted WASM");
    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_while_and_compound_assignments() {
    let src = r#"
fn main() {
    let i: i32 = 1;
    let total: i32 = 0;
    while (i <= 10) {
        total += i;
        i += 1;
    }
    print(total);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "55\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_extern_wasm_import_calls() {
    let src = r#"
extern "host" fn log_i64(value: i64);
extern "host" fn double_i64(value: i64) -> i64;
extern "host" fn answer_i32() -> i32;
extern "host" fn plus_one_i32(value: i32) -> i32;

fn main() {
    log_i64(5);
    print(double_i64(21));
    print(answer_i32());
    print(plus_one_i32(6));
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    assert!(contains_bytes(&wasm, b"\x04host\x07log_i64"));
    assert!(contains_bytes(&wasm, b"\x04host\x0adouble_i64"));
    assert!(contains_bytes(&wasm, b"\x04host\x0aanswer_i32"));
    assert!(contains_bytes(&wasm, b"\x04host\x0cplus_one_i32"));
    run_wasm_extern_imports_if_node_available(&wasm);
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_loop_multiply_and_subtract() {
    let src = r#"
fn main() {
    let n: i32 = 5;
    let acc: i32 = 1;
    while (n > 0) {
        acc *= n;
        n -= 1;
    }
    print(acc);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "120\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_integer_array_sum_loop() {
    let src = r#"
fn main() {
    let values: [i32; 5] = [3, 1, 4, 1, 5];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 5) {
        total += values[i];
        i += 1;
    }
    print(total);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "14\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_bool_branch() {
    let src = r#"
fn main() {
    let ok: bool = (3 < 4) && !(5 == 6);
    if (ok || (1 > 2)) {
        print(1);
    } else {
        print(0);
    }
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "1\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_bool_literals() {
    let src = r#"
fn main() {
    let flag: bool = false;
    if (true) {
        print(1);
    } else {
        print(0);
    }
    if (flag) {
        print(0);
    } else {
        print(2);
    }
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "1\n2\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_assert_builtin_success() {
    let src = r#"
fn main() {
    let ok: bool = true;
    assert(ok);
    assert(3 < 4);
    print(1);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "1\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_traps_failed_assert_builtin() {
    let src = r#"
fn main() {
    assert(false);
    print(1);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    if common::node_available() {
        let output = common::run_wasm_main_with_node_output("assert trap", "assert_trap", &wasm);
        assert!(
            !output.status.success(),
            "failed assertion should make node exit nonzero\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_lowers_top_level_constants() {
    let src = r#"
const LIMIT: i32 = 7;
const ENABLED: bool = true;

fn main() {
    if (ENABLED) {
        print(LIMIT + 5);
    } else {
        print(0);
    }
    return LIMIT;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "12\n");
}

#[test]
#[ignore = "GPU codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_ignores_enum_declarations() {
    let src = r#"
pub enum ResultI32 {
    Ok(i32),
    Err(i32),
}

enum Ordering {
    Less,
    Equal,
    Greater,
}

fn main() {
    print(3);
    return 0;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "3\n");
}

fn assert_lanius_wasm(bytes: &[u8]) {
    assert!(
        bytes.len() >= 37,
        "WASM output too small: {} bytes",
        bytes.len()
    );
    assert_eq!(
        &bytes[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
    assert!(contains_bytes(bytes, b"\x03env\x09print_i64"));
    assert!(contains_bytes(bytes, b"\x04main\x00"));
}

fn run_wasm_main_if_node_available(wasm: &[u8], expected_stdout: &str) {
    if !common::node_available() {
        return;
    }
    let stdout = common::run_wasm_main_with_node("codegen WASM check", "codegen_wasm", wasm);
    assert_eq!(
        stdout, expected_stdout,
        "codegen WASM stdout mismatch\nexpected:\n{expected_stdout:?}\nactual:\n{stdout:?}"
    );
}

fn run_wasm_extern_imports_if_node_available(wasm: &[u8]) {
    if !common::node_available() {
        return;
    }

    let wasm_path =
        common::TempArtifact::new("laniusc_codegen_wasm", "extern_imports", Some("wasm"));
    wasm_path.write_bytes(wasm);
    let script = r#"
const fs = require('fs');
(async () => {
  let stdout = '';
  const imports = {
    env: {
      print_i64(value) {
        stdout += value.toString() + '\n';
      }
    },
    host: {
      log_i64(value) {
        stdout += `log:${value.toString()}\n`;
      },
      double_i64(value) {
        return value * 2n;
      },
      answer_i32() {
        return 7;
      },
      plus_one_i32(value) {
        return value + 1;
      }
    }
  };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  const status = module.instance.exports.main();
  if (status !== 0) {
    console.error(`main returned ${String(status)}`);
    process.exit(1);
  }
  process.stdout.write(stdout);
})().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
"#;
    let mut command = Command::new("node");
    command.arg("-e").arg(script).arg(wasm_path.path());
    let output =
        common::short_process_output_with_timeout("node extern WASM imports", &mut command);
    common::assert_command_success("node extern WASM imports", &output);
    assert_eq!(
        common::stdout_utf8("extern WASM imports stdout", output.stdout),
        "log:5\n42\n7\n7\n"
    );
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}
