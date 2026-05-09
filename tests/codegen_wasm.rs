use std::{fs, process::Command};

use laniusc::compiler::compile_source_to_wasm_with_gpu_codegen;

#[test]
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
    let wasm =
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src)).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "7\n9\n");
}

#[test]
fn gpu_codegen_cli_emits_wasm_file() {
    let src_path = std::env::temp_dir().join(format!(
        "laniusc_gpu_wasm_{}_{}.lani",
        std::process::id(),
        unique_suffix()
    ));
    let out_path = src_path.with_extension("wasm");
    fs::write(&src_path, "let x = 1;\n").expect("write temporary source");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let output = Command::new(bin)
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg("--emit")
        .arg("wasm")
        .arg(&src_path)
        .arg("-o")
        .arg(&out_path)
        .output()
        .expect("run laniusc");

    let _ = fs::remove_file(&src_path);
    assert!(
        output.status.success(),
        "laniusc failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let wasm = fs::read(&out_path).expect("read emitted WASM");
    let _ = fs::remove_file(&out_path);
    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
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
    let wasm =
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src)).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "55\n");
}

#[test]
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
    let wasm =
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src)).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "120\n");
}

#[test]
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
    let wasm =
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src)).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "14\n");
}

#[test]
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
    let wasm =
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src)).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "1\n");
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
    if Command::new("node").arg("--version").output().is_err() {
        return;
    }
    let wasm_path = std::env::temp_dir().join(format!(
        "laniusc_exec_wasm_{}_{}.wasm",
        std::process::id(),
        unique_suffix()
    ));
    fs::write(&wasm_path, wasm).expect("write executable WASM");
    let script = format!(
        "(async()=>{{ const fs=require('fs'); let stdout=''; const imports={{env:{{print_i64(value){{ stdout += value.toString() + '\\n'; }}}}}}; const m=await WebAssembly.instantiate(fs.readFileSync({:?}), imports); const got=m.instance.exports.main(); if (got !== 0) {{ console.error('return='+got); process.exit(1); }} if (stdout !== {:?}) {{ console.error(JSON.stringify(stdout)); process.exit(1); }} }})().catch(e=>{{ console.error(e); process.exit(1); }});",
        wasm_path.display().to_string(),
        expected_stdout
    );
    let output = Command::new("node")
        .arg("-e")
        .arg(script)
        .output()
        .expect("run node WASM check");
    let _ = fs::remove_file(&wasm_path);
    assert!(
        output.status.success(),
        "node failed to execute emitted WASM:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}
