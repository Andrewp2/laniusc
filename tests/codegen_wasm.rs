mod common;

use std::{fmt::Write as _, path::PathBuf};

#[test]
fn wasm_executes_scalar_constant_return_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
const BASE: i32 = 7;

fn main() {
    return BASE + 35;
}
"#,
    )
    .expect("scalar constant-return source should compile to WASM");

    let status =
        common::run_wasm_main_return_with_node("scalar WASM main return", "scalar_return", &wasm);
    assert_eq!(status, 42);
}

#[test]
fn wasm_executes_intrinsic_print_stdout_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    print(6 * 7);
    print(-7);
    return 0;
}
"#,
    )
    .expect("intrinsic print source should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM intrinsic print", "intrinsic_print", &wasm);
    assert_eq!(stdout, "42\n-7\n");
}

#[test]
fn wasm_executes_std_io_write_stdout_import_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() -> i32 {
    let written: i32 = std::io::write_stdout(0, 0);
    if (written != 0) {
        return 1;
    }
    return 0;
}
"#,
    ])
    .expect("std::io write_stdout import should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM std::io write_stdout", "stdio_write_stdout", &wasm);
    assert_eq!(stdout, "");
}

#[test]
fn wasm_executes_std_io_write_stdout_bytes_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import core::mem;
import std::io;

fn main() -> i32 {
    let bytes: [i32; 1] = [65];
    let ptr: u32 = core::mem::i32_array_data_ptr(bytes);
    let written: i32 = std::io::write_stdout(ptr, 1);
    if (written != 1) {
        return 1;
    }
    return 0;
}
"#,
    ])
    .expect("std::io write_stdout byte buffer should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM std::io write_stdout bytes",
        "stdio_write_bytes",
        &wasm,
    );
    assert_eq!(stdout, "A");
}

#[test]
fn wasm_executes_std_io_flush_operations_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() -> i32 {
    if (!std::io::stdio_is_available()) {
        return 3;
    }
    if (std::io::stdio_requires_runtime_binding()) {
        return 4;
    }
    if (!std::io::flush_stdout_is_executable()) {
        return 5;
    }
    if (!std::io::flush_stderr_is_executable()) {
        return 6;
    }
    let stdout_result: i32 = std::io::flush_stdout();
    let stderr_result: i32 = std::io::flush_stderr();
    if (stdout_result != std::io::STDIO_OPERATION_OK) {
        return 1;
    }
    if (stderr_result != std::io::STDIO_OPERATION_OK) {
        return 2;
    }
    return 0;
}
"#,
    ])
    .expect("std::io flush operations should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM std::io flush operations",
        "stdio_flush",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_std_process_argc_import_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import std::process;

fn main() -> i32 {
    let count: i32 = std::process::argc();
    if (count != 2) {
        return 7;
    }
    return 0;
}
"#,
    ])
    .expect("std::process argc import should compile to WASM");

    let status =
        common::run_wasm_main_return_with_node("WASM std::process argc", "process_argc", &wasm);
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_std_process_exit_from_nested_helper_with_node() {
    common::require_node();
    let app_source = r#"
module app::main;

import std::process;

fn bump(code: i32) -> i32 {
    return code + 1;
}

fn finish(code: i32) {
    std::process::exit(code);
}

fn main() -> i32 {
    finish(bump(6));
    return 99;
}
"#;
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/process.lani"),
        app_source,
    ])
    .expect("nested std::process exit should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested std::process exit",
        "process_exit_nested",
        &wasm,
    );
    assert_eq!(status, 7);
}

#[test]
fn wasm_executes_host_argument_expression_beyond_legacy_stack_depth() {
    common::require_node();
    let mut expression = "1".to_owned();
    for _ in 0..24 {
        expression = format!("({expression} + 1)");
    }
    let source = format!(
        r#"
module app::main;

import std::process;

fn main() -> i32 {{
    std::process::exit({expression});
    return 99;
}}
"#
    );
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/process.lani"),
        &source,
    ])
    .expect("deep host-call argument expression should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM deep host-call argument",
        "deep_host_call_argument",
        &wasm,
    );
    assert_eq!(status, 25);
}

#[test]
fn wasm_executes_std_process_argument_read_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import core::mem;
import std::io;
import std::process;

fn main() -> i32 {
    let buffer: [i32; 2] = [0, 0];
    let ptr: u32 = core::mem::i32_array_data_ptr(buffer);
    let count: i32 = std::process::argc();
    let len: i32 = std::process::arg_len(0);
    let copied: i32 = std::process::arg_read(0, ptr, len);
    if (count != 2) {
        return 1;
    }
    if (len != 7) {
        return 2;
    }
    if (copied != len) {
        return 3;
    }
    let written: i32 = std::io::write_stdout(ptr, copied);
    if (written != copied) {
        return 4;
    }
    return 0;
}
"#,
    ])
    .expect("std::process argument read imports should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM std::process argument read",
        "process_argument_read",
        &wasm,
    );
    assert_eq!(stdout, "program");
}

#[test]
fn wasm_executes_std_random_and_time_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/random.lani"),
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;

import std::random;
import std::time;

fn main() -> i32 {
    let random_value: u32 = std::random::secure_u32();
    let seconds: i32 = std::time::unix_seconds();
    if (random_value != 1234567) {
        return 1;
    }
    if (seconds != 1234567890) {
        return 2;
    }
    return 0;
}
"#,
    ])
    .expect("std::random and std::time imports should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM std::random and std::time",
        "random_time",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_std_random_fill_secure_bytes_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/random.lani"),
        r#"
module app::main;

import core::mem;
import std::io;
import std::random;

fn main() -> i32 {
    if (!std::random::random_is_available()) {
        return 3;
    }
    if (!std::random::fill_secure_bytes_is_executable()) {
        return 4;
    }
    let values: [i32; 1] = [0];
    let ptr: u32 = core::mem::i32_array_data_ptr(values);
    let filled: i32 = std::random::fill_secure_bytes(ptr, 4);
    if (filled != 4) {
        return 1;
    }
    let written: i32 = std::io::write_stdout(ptr, 4);
    if (written != filled) {
        return 2;
    }
    return 0;
}
"#,
    ])
    .expect("std::random fill_secure_bytes should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM std::random fill_secure_bytes",
        "random_fill_secure_bytes",
        &wasm,
    );
    assert_eq!(stdout.as_bytes(), &[11, 48, 85, 122]);
}

#[test]
fn wasm_executes_std_fs_path_mutations_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/fs.lani"),
        r#"
module app::main;
import alloc::allocator;
import std::process;
import std::fs;
fn main() -> i32 {
    let capacity: usize = 64;
    let path_len: usize = 15;
    let ptr: u32 = alloc::allocator::alloc(capacity, 4);
    let arg_read_result: i32 = std::process::arg_read(1, ptr, capacity);
    if (arg_read_result != 15) {
        return 1;
    }
    let create_result: i32 = std::fs::create_dir(ptr, path_len);
    if (create_result != 0) {
        return 2;
    }
    let rename_dir_result: i32 = std::fs::rename(ptr, path_len, ptr, path_len);
    if (rename_dir_result != 0) {
        return 3;
    }
    let remove_dir_result: i32 = std::fs::remove_dir(ptr, path_len);
    if (remove_dir_result != 0) {
        return 4;
    }
    let handle: i32 = std::fs::open_write(ptr, path_len);
    if (handle < 0) {
        return 5;
    }
    let close_result: i32 = std::fs::close(handle);
    if (close_result != 0) {
        return 6;
    }
    let rename_file_result: i32 = std::fs::rename(ptr, path_len, ptr, path_len);
    if (rename_file_result != 0) {
        return 7;
    }
    let remove_file_result: i32 = std::fs::remove_file(ptr, path_len);
    if (remove_file_result != 0) {
        return 8;
    }
    alloc::allocator::dealloc(ptr, capacity, 4);
    return 0;
}
"#,
    ])
    .expect("std::fs path mutations should compile to WASM");
    let status = common::run_wasm_main_return_with_node(
        "WASM std::fs path mutations",
        "filesystem_path_mutations",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_alloc_allocator_alloc_dealloc_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;

import alloc::allocator;

fn main() -> i32 {
    let ptr: u32 = alloc::allocator::alloc(64, 8);
    if (ptr == 0) {
        return 1;
    }
    alloc::allocator::dealloc(ptr, 64, 8);
    return 0;
}
"#,
    ])
    .expect("alloc::allocator alloc/dealloc imports should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM alloc::allocator alloc/dealloc",
        "alloc_allocator_alloc_dealloc",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_host_runtime_smoke_source_pack_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/env.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/random.lani"),
        include_str!("../stdlib/std/time.lani"),
        include_str!("../sample_programs/host_runtime_smoke.lani"),
    ])
    .expect("host runtime smoke source pack should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM host runtime smoke source pack",
        "host_runtime_smoke_source_pack",
        &wasm,
    );
    assert_eq!(stdout, "99\n");
}

#[test]
fn wasm_executes_std_env_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/env.lani"),
        r#"
module app::main;

import core::mem;
import std::env;

fn main() -> i32 {
    let buffer: [i32; 8] = [0, 0, 0, 0, 0, 0, 0, 0];
    let ptr: u32 = core::mem::i32_array_data_ptr(buffer);
    let reported_cwd_len: i32 = std::env::current_dir_len();
    let cwd_len: i32 = std::env::current_dir_read(ptr, 64);
    if (cwd_len <= 0) {
        return 1;
    }
    if (cwd_len != reported_cwd_len) {
        return 7;
    }

    let count: i32 = std::env::var_count();
    if (count != 1) {
        return 2;
    }

    let key_len: i32 = std::env::var_key_len(0);
    if (key_len <= 0) {
        return 3;
    }
    let key_read: i32 = std::env::var_key_read(0, ptr, 64);
    if (key_read != key_len) {
        return 4;
    }

    let value_len: i32 = std::env::var_len(ptr, key_len);
    if (value_len <= 0) {
        return 5;
    }
    let value_read: i32 = std::env::var_read(ptr, key_len, ptr, 64);
    if (value_read != value_len) {
        return 6;
    }

    return 0;
}
"#,
    ])
    .expect("std::env imports should compile to WASM");

    let status = common::run_wasm_main_return_with_node("WASM std::env", "env_imports", &wasm);
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_std_fs_file_io_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import core::mem;
import std::fs;
import std::io;

fn main() -> i32 {
    let path: [i32; 1] = [102];
    let payload: [i32; 1] = [82];
    let read_buffer: [i32; 1] = [0];
    let path_ptr: u32 = core::mem::i32_array_data_ptr(path);
    let payload_ptr: u32 = core::mem::i32_array_data_ptr(payload);
    let read_ptr: u32 = core::mem::i32_array_data_ptr(read_buffer);

    let output: i32 = std::fs::open_write(path_ptr, 1);
    if (output < 0) {
        return 1;
    }
    let written: i32 = std::fs::write(output, payload_ptr, 1);
    if (written != 1) {
        return 2;
    }
    let output_closed: i32 = std::fs::close(output);
    if (output_closed < 0) {
        return 3;
    }

    let input: i32 = std::fs::open_read(path_ptr, 1);
    if (input < 0) {
        return 4;
    }
    let read_count: i32 = std::fs::read(input, read_ptr, 1);
    if (read_count != 1) {
        return 5;
    }
    let input_closed: i32 = std::fs::close(input);
    if (input_closed < 0) {
        return 6;
    }
    let copied: i32 = std::io::write_stdout(read_ptr, 1);
    if (copied != 1) {
        return 7;
    }
    return 0;
}
"#,
    ])
    .expect("std::fs low-level file imports should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM std::fs file IO", "fs_file_io", &wasm);
    assert_eq!(stdout, "R");
}

#[test]
fn wasm_executes_std_fs_path_text_write_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() -> i32 {
    let file: std::fs::FileHandle = std::fs::open_write_path("wasm_text.txt");
    if (file < 0) {
        return 1;
    }
    let written: i32 = std::io::write_text(file, "saved");
    let closed: i32 = std::fs::close_file(file);
    if (written != 5) {
        return 2;
    }
    if (closed != 0) {
        return 3;
    }
    return 0;
}
"#,
    ])
    .expect("std::fs path text write should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM std::fs path text write",
        "std_fs_path_text_write",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "");
    assert_eq!(
        result.files.get("wasm_text.txt").map(Vec::as_slice),
        Some(b"saved".as_slice())
    );
}

#[test]
fn wasm_executes_lanius_std_string_local_through_user_function_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
extern "lanius_std" fn open_write_path(path: str) -> i32;
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;

fn write_named(path: str) -> i32 {
    let file: i32 = open_write_path(path);
    if (file < 0) {
        return 100;
    }
    return write_text(file, "saved");
}

fn main() -> i32 {
    let path: str = "dynamic_path.txt";
    let written: i32 = write_named(path);
    if (written != 5) {
        return written;
    }
    return 0;
}
"#,
    )
    .expect("string locals and string params should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM lanius_std string local through user function",
        "string_local_user_function",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(
        result.files.get("dynamic_path.txt").map(Vec::as_slice),
        Some(b"saved".as_slice())
    );
}

#[test]
fn wasm_executes_parser_decoded_string_escapes_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
extern "lanius_std" fn open_write_path(path: str) -> i32;
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;
extern "lanius_std" fn close_file(handle: i32) -> i32;

fn main() -> i32 {
    let file: i32 = open_write_path("wasm_escape.txt");
    if (file < 0) {
        return 1;
    }
    let written: i32 = write_text(file, "line\nnext\tend");
    let closed: i32 = close_file(file);
    if (written != 13) {
        return 2;
    }
    if (closed != 0) {
        return 3;
    }
    return 0;
}
"#,
    )
    .expect("parser-decoded string escapes should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM parser-decoded string escapes",
        "parser_decoded_string_escapes",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(
        result.files.get("wasm_escape.txt").map(Vec::as_slice),
        Some(b"line\nnext\tend".as_slice())
    );
}

#[test]
fn wasm_executes_long_parser_decoded_string_across_dfa_chunks_with_node() {
    common::require_node();
    let payload = format!("{}\\n{}", "a".repeat(130), "b".repeat(130));
    let source = format!(
        r#"
extern "lanius_std" fn open_write_path(path: str) -> i32;
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;
extern "lanius_std" fn close_file(handle: i32) -> i32;

fn main() -> i32 {{
    let file: i32 = open_write_path("wasm_long_escape.txt");
    if (file < 0) {{
        return 1;
    }}
    let written: i32 = write_text(file, "{payload}");
    let closed: i32 = close_file(file);
    if (written != 261) {{
        return 2;
    }}
    if (closed != 0) {{
        return 3;
    }}
    return 0;
}}
"#
    );
    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("long parser-decoded string should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM long parser-decoded string",
        "long_parser_decoded_string",
        &wasm,
        &[],
    );
    let expected = format!("{}\n{}", "a".repeat(130), "b".repeat(130));
    assert_eq!(result.exit_code, 0);
    assert_eq!(
        result.files.get("wasm_long_escape.txt").map(Vec::as_slice),
        Some(expected.as_bytes())
    );
}

#[test]
fn wasm_executes_std_fs_path_text_write_decodes_escapes_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() -> i32 {
    let file: std::fs::FileHandle = std::fs::open_write_path("escaped_text.txt");
    if (file < 0) {
        return 1;
    }
    let written: i32 = std::io::write_text(file, "line\nnext");
    let closed: i32 = std::fs::close_file(file);
    if (written != 9) {
        return 2;
    }
    if (closed != 0) {
        return 3;
    }
    return 0;
}
"#,
    ])
    .expect("std::fs path text write with escapes should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM std::fs path text write escape decode",
        "std_fs_path_text_write_escape_decode",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "");
    assert_eq!(
        result.files.get("escaped_text.txt").map(Vec::as_slice),
        Some(b"line\nnext".as_slice())
    );
}

#[test]
fn wasm_executes_std_fs_path_i32_roundtrip_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() -> i32 {
    let output: std::fs::FileHandle = std::fs::open_write_path("wasm_i32.txt");
    if (output < 0) {
        return 1;
    }
    let write_value: i32 = std::io::write_i32(output, 12345);
    let write_line: i32 = std::io::write_newline(output);
    let output_close: i32 = std::fs::close_file(output);
    if (write_value < 0) {
        return 2;
    }
    if (write_line < 0) {
        return 6;
    }
    if (output_close < 0) {
        return 7;
    }

    let input: std::fs::FileHandle = std::fs::open_read_path("wasm_i32.txt");
    if (input < 0) {
        return 3;
    }
    let value: i32 = std::fs::read_i32(input, -1);
    let input_close: i32 = std::fs::close_file(input);
    if (input_close < 0) {
        return 4;
    }
    if (value != 12345) {
        return 5;
    }

    std::io::print_i32(value);
    return 0;
}
"#,
    ])
    .expect("std::fs path i32 roundtrip should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM std::fs path i32 roundtrip",
        "std_fs_path_i32_roundtrip",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "12345\n");
    assert_eq!(
        result.files.get("wasm_i32.txt").map(Vec::as_slice),
        Some(b"12345\n".as_slice())
    );
}

#[test]
fn wasm_executes_scalar_local_assignments_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let x: i32 = 10;
    x += 5;
    x -= 3;
    x *= 4;
    x /= 6;
    x %= 5;
    print(x);
    return 0;
}
"#,
    )
    .expect("scalar local assignments should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM scalar local assignments", "local_assigns", &wasm);
    assert_eq!(stdout, "3\n");
}

#[test]
fn wasm_executes_scalar_let_expression_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() -> i32 {
    let x: i32 = 2;
    let y: i32 = 3;
    let value: i32 = x + y * 2;
    return value;
}
"#,
    )
    .expect("scalar let expression should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM scalar let expression",
        "scalar_let_expression",
        &wasm,
    );
    assert_eq!(status, 8);
}

#[test]
fn wasm_executes_constant_assignment_inside_if_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() -> i32 {
    let ok: bool = false;
    let count: i32 = 0;
    if (true) {
        ok = true;
        count += 1;
    }
    if (ok && count == 1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("constant assignment inside an if should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM constant assignment inside if",
        "constant_assignment_inside_if",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_scalar_local_return_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let x: i32 = 10;
    x += 5;
    return x;
}
"#,
    )
    .expect("scalar local return should compile to WASM");

    let status =
        common::run_wasm_main_return_with_node("WASM scalar local return", "local_return", &wasm);
    assert_eq!(status, 15);
}

#[test]
fn wasm_executes_f32_literal_local_with_node() {
    common::require_node();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wasm/f32_literal_local.lani");
    let wasm = common::compile_path_to_wasm_with_timeout(&source)
        .expect("f32 literal locals should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 literal local",
        "f32_literal_local",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_f32_scalar_function_with_node() {
    common::require_node();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wasm/f32_scalar_function.lani");
    let wasm = common::compile_path_to_wasm_with_timeout(&source)
        .expect("f32 scalar functions should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 scalar function",
        "f32_scalar_function",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_struct_local_member_reads_with_node() {
    common::require_node();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wasm/struct_local_member.lani");
    let wasm = common::compile_path_to_wasm_with_timeout(&source)
        .expect("struct literal locals and member reads should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM struct local member reads",
        "struct_local_member",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_receiver_f32_member_call_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn x_value(self) -> f32 {
        return self.x;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 4.0, y: 1.0, z: 2.0 };
    let x: f32 = value.x_value();
    if (x > 3.5) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate receiver f32 member call should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate receiver f32 member call",
        "aggregate_receiver_f32_member_call",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_f32_aggregate_member_binary_return_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 3.0, z: 4.0 };
    let result: f32 = value.dot(value);
    if (result > 28.9 && result < 29.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("f32 aggregate member binary return should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 aggregate member binary return",
        "f32_aggregate_member_binary_return",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_i32_to_f32_inside_composite_let_expression() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
extern "lanius_std" fn i32_to_f32(value: i32) -> f32;

fn main() -> i32 {
    let divisor: f32 = 2.0;
    let value: f32 = (i32_to_f32(7) + 1.0) / divisor;
    if (value > 3.9 && value < 4.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("i32_to_f32 inside a composite let should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM i32_to_f32 composite let",
        "i32_to_f32_composite_let",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_expression_deeper_than_legacy_emit_stack() {
    common::require_node();
    let mut expression = "1".to_owned();
    for _ in 0..48 {
        expression = format!("-({expression})");
    }
    let source = format!(
        r#"
fn main() -> i32 {{
    let value: i32 = {expression};
    if (value == 1) {{
        return 0;
    }}
    return 1;
}}
"#
    );
    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep expression should compile to WASM without a bounded sizing walk");
    let status =
        common::run_wasm_main_return_with_node("WASM deep expression", "deep_expression", &wasm);
    assert_eq!(status, 0);
}

#[test]
fn wasm_evaluates_deep_expression_from_reassigned_local_at_runtime() {
    common::require_node();
    let mut expression = "value".to_owned();
    for _ in 0..48 {
        expression = format!("1 + ({expression})");
    }
    let source = format!(
        r#"
fn main() {{
    let value: i32 = 1;
    value = 40;
    let result: i32 = {expression};
    print(result);
    return 0;
}}
"#
    );
    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep expressions must read reassigned locals at runtime");
    let stdout = common::run_wasm_main_with_node(
        "WASM deep runtime expression after reassignment",
        "deep_runtime_expression_after_reassignment",
        &wasm,
    );
    assert_eq!(stdout, "88\n");
}

#[test]
fn wasm_executes_ray_coordinate_conversion_formula() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
extern "lanius_std" fn i32_to_f32(value: i32) -> f32;

struct Settings {
    width: i32,
    height: i32,
}

fn coordinate_status(settings: Settings, x: i32, y: i32) -> i32 {
    let x_offset: f32 = (i32_to_f32(0) + 0.5) / 1.0;
    if (!(x_offset > 0.49 && x_offset < 0.51)) {
        return 10;
    }
    let width_minus_one: i32 = settings.width - 1;
    if (width_minus_one != 15) {
        return 14;
    }
    let width_divisor: f32 = i32_to_f32(settings.width - 1);
    if (!(width_divisor > 14.9 && width_divisor < 15.1)) {
        return 15;
    }
    let x_value: f32 = i32_to_f32(x);
    if (!(x_value > 0.9 && x_value < 1.1)) {
        return 16;
    }
    let u: f32 = (i32_to_f32(x) + x_offset) / i32_to_f32(settings.width - 1);
    if (!(u > 0.09 && u < 0.11)) {
        return 11;
    }
    let row_from_top: i32 = settings.height - 1 - y;
    if (row_from_top != 8) {
        return 12;
    }
    let v: f32 = (i32_to_f32(row_from_top) + 0.5) / i32_to_f32(settings.height - 1);
    if (!(v > 1.06 && v < 1.07)) {
        return 13;
    }
    return 0;
}

fn main() -> i32 {
    let settings: Settings = Settings { width: 16, height: 9 };
    return coordinate_status(settings, 1, 0);
}
"#,
    )
    .expect("ray coordinate conversion formula should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM ray coordinate conversion formula",
        "ray_coordinate_conversion_formula",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_camera_ray_with_nonzero_coordinates() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        let result: Vec3 = Vec3 { x: x, y: y, z: z };
        return result;
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

struct Camera {
    origin: Vec3,
    lower_left_corner: Vec3,
    horizontal: Vec3,
    vertical: Vec3,
}

impl Camera {
    fn ray(self, u: f32, v: f32) -> Ray {
        let horizontal: Vec3 = self.horizontal;
        let vertical: Vec3 = self.vertical;
        let lower_left_corner: Vec3 = self.lower_left_corner;
        let origin: Vec3 = self.origin;
        let across: Vec3 = horizontal.mul_scalar(u);
        let up: Vec3 = vertical.mul_scalar(v);
        let corner_across: Vec3 = lower_left_corner.add(across);
        let target: Vec3 = corner_across.add(up);
        let direction: Vec3 = target.sub(origin);
        let result: Ray = Ray { origin: origin, direction: direction };
        return result;
    }
}

fn main() -> i32 {
    let origin: Vec3 = Vec3::new(0.0, 0.0, 0.0);
    let lower_left: Vec3 = Vec3::new(-1.777778, -1.0, -1.0);
    let horizontal: Vec3 = Vec3::new(3.555556, 0.0, 0.0);
    let vertical: Vec3 = Vec3::new(0.0, 2.0, 0.0);
    let camera: Camera = Camera {
        origin: origin,
        lower_left_corner: lower_left,
        horizontal: horizontal,
        vertical: vertical,
    };
    let first_ray: Ray = camera.ray(0.033333, 1.0625);
    let first_direction: Vec3 = first_ray.direction;
    if (!(first_direction.x > -1.67 && first_direction.x < -1.65)) {
        return 9;
    }
    let second_ray: Ray = camera.ray(0.1, 1.0625);
    let direction: Vec3 = second_ray.direction;
    if (!(direction.x > -1.43 && direction.x < -1.41)) {
        return 10;
    }
    if (!(direction.y > 1.12 && direction.y < 1.13)) {
        return 11;
    }
    if (!(direction.z > -1.01 && direction.z < -0.99)) {
        return 12;
    }
    return 0;
}
"#,
    )
    .expect("camera ray with nonzero coordinates should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM camera ray with nonzero coordinates",
        "camera_ray_nonzero_coordinates",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_passes_loop_coordinates_after_aggregate_call_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn observe(first: Pair, second: Pair, x: i32, y: i32) -> i32 {
    return first.left + second.right + x * 10 + y;
}

fn main() -> i32 {
    let first: Pair = Pair { left: 1, right: 2 };
    let second: Pair = Pair { left: 3, right: 4 };
    let sum: i32 = 0;
    let height: i32 = 3;
    let width: i32 = 4;
    for y in 0..height {
        for x in 0..width {
            let observed: i32 = observe(first, second, x, y);
            sum = sum + observed;
        }
    }
    if (sum == 252) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("loop coordinates after aggregate call args should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM loop coordinates after aggregate call args",
        "loop_coordinates_after_aggregate_call_args",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_passes_f32_bounds_after_aggregate_call_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn bounds_ok(first: Pair, second: Pair, lower: f32, upper: f32) -> i32 {
    if (first.left == 1 && second.right == 4 &&
        lower > 0.0009 && lower < 0.0011 &&
        upper > 999999.0) {
        return 0;
    }
    return 1;
}

fn main() -> i32 {
    let first: Pair = Pair { left: 1, right: 2 };
    let second: Pair = Pair { left: 3, right: 4 };
    return bounds_ok(first, second, 0.001, 1000000.0);
}
"#,
    )
    .expect("f32 bounds after aggregate call args should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 bounds after aggregate call args",
        "f32_bounds_after_aggregate_call_args",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_preserves_valid_f32_root_through_or_guard() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn select_root(candidate: f32, lower: f32, upper: f32) -> f32 {
    let root: f32 = candidate;
    if (root < lower || root > upper) {
        root = 100.0;
    }
    return root;
}

fn main() -> i32 {
    let root: f32 = select_root(0.572, 0.001, 1000000.0);
    if (root > 0.57 && root < 0.58) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("valid f32 root OR guard should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM valid f32 root OR guard",
        "valid_f32_root_or_guard",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_computes_near_quadratic_root_expression() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn near_root(half_b: f32, sqrtd: f32, a: f32) -> f32 {
    let root: f32 = (-half_b - sqrtd) / a;
    return root;
}

fn main() -> i32 {
    let root: f32 = near_root(-88.9375, 87.92786, 1.765625);
    if (root > 0.57 && root < 0.58) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("near quadratic root expression should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM near quadratic root expression",
        "near_quadratic_root_expression",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_nested_f32_direct_call_argument_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn x_value(self) -> f32 {
        return self.x;
    }

    fn half_x(self) -> f32 {
        return half(self.x_value());
    }
}

fn half(value: f32) -> f32 {
    return value / 2.0;
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let result: f32 = value.half_x();
    if (result > 0.9 && result < 1.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("nested f32 direct call arguments should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested f32 direct call argument",
        "nested_f32_direct_call_argument",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_method_with_f32_receiver_call_local() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn x_value(self) -> f32 {
        return self.x;
    }

    fn keep_when_x_nonzero(self) -> Vec3 {
        let len: f32 = self.x_value();
        if (len == 0.0) {
            return self;
        }
        return self;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 4.0, y: 1.0, z: 2.0 };
    let result: Vec3 = value.keep_when_x_nonzero();
    if (result.x > 3.5) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate-return method with f32 receiver-call local should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate-return method f32 receiver call local",
        "aggregate_return_method_f32_receiver_call_local",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_nested_f32_return_call_with_aggregate_receiver_arg() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }

    fn length(self) -> f32 {
        return core::f32::sqrt(self.dot(self));
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let result: f32 = value.length();
    if (result > 1.9 && result < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    ])
    .expect("nested f32 return call with aggregate receiver arg should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested f32 return call with aggregate receiver arg",
        "nested_f32_return_call_aggregate_receiver_arg",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_normalized_vector_dot_product() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }

    fn length(self) -> f32 {
        return core::f32::sqrt(self.dot(self));
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

    fn unit(self) -> Vec3 {
        let len: f32 = self.length();
        if (len == 0.0) {
            return self;
        }
        return self.mul_scalar(1.0 / len);
    }
}

fn main() -> i32 {
    let sphere_center: Vec3 = Vec3::new(0.0, -100.5, -1.0);
    let point: Vec3 = Vec3::new(0.0, -0.5009, -0.5724);
    let outward: Vec3 = point.sub(sphere_center);
    let outward_normal: Vec3 = outward.mul_scalar(0.01);
    let normal: Vec3 = outward_normal.unit();
    let light_value: Vec3 = Vec3::new(-0.4, 0.9, -0.6);
    let light: Vec3 = light_value.unit();
    if (!(normal.x > -0.1 && normal.x < 0.1 &&
          normal.y > 0.9 && normal.z > -0.1 && normal.z < 0.1)) {
        return 10;
    }
    if (!(light.x < -0.3 && light.y > 0.7 && light.z < -0.4)) {
        return 11;
    }
    let diffuse: f32 = normal.dot(light);
    if (diffuse > 0.5) {
        return 0;
    }
    return 1;
}
"#,
    ])
    .expect("normalized vector dot product should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM normalized vector dot product",
        "normalized_vector_dot_product",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_binary_member_expression_return_without_control_flow() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 3.0, z: 4.0 };
    let result: f32 = value.dot(value);
    return 0;
}
"#,
    )
    .expect("binary member-expression return should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM binary member-expression return",
        "binary_member_expression_return",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_bool_member_condition_on_aggregate_call_result() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Hit {
    ok: bool,
}

fn make_hit() -> Hit {
    return Hit { ok: true };
}

fn main() -> i32 {
    let hit: Hit = make_hit();
    if (hit.ok) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("bool member condition on aggregate call result should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM bool member condition on aggregate call result",
        "bool_member_condition_aggregate_call_result",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_method_with_f32_expr_arg() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

    fn scaled(self) -> Vec3 {
        let len: f32 = self.x;
        if (len == 0.0) {
            return self;
        }
        return self.mul_scalar(1.0 / len);
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let result: Vec3 = value.scaled();
    if (result.x > 0.9 && result.x < 1.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate return method with f32 expression arg should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate return method with f32 expression arg",
        "aggregate_return_method_f32_expr_arg",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_f32_sqrt_like_loop_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn sqrt_like(value: f32) -> f32 {
    if (value <= 0.0) {
        return 0.0;
    }

    let guess: f32 = value;
    if (guess < 1.0) {
        guess = 1.0;
    }

    let iteration: i32 = 0;
    while (iteration < 4) {
        guess = 0.5 * (guess + value / guess);
        iteration = iteration + 1;
    }
    return guess;
}

fn main() -> i32 {
    let result: f32 = sqrt_like(4.0);
    if (result > 1.9 && result < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("sqrt-like f32 loop should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM sqrt-like f32 loop",
        "sqrt_like_f32_loop",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_imported_core_f32_sqrt_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;

fn main() -> i32 {
    let result: f32 = core::f32::sqrt(4.0);
    if (result > 1.9 && result < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    ])
    .expect("imported core::f32 sqrt should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM imported core f32 sqrt",
        "imported_core_f32_sqrt",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_local_member_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn make_vec(x: f32, y: f32, z: f32) -> Vec3 {
    let result: Vec3 = Vec3 { x: x, y: y, z: z };
    return result;
}

fn main() -> i32 {
    let value: Vec3 = make_vec(1.0, 2.0, 3.0);
    let y: f32 = value.y;
    if (y > 1.9 && y < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate returns should compile to pointer-valued WASM ABI");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate return local member",
        "aggregate_return_local_member",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_member_value_copy_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

struct Hit {
    ok: bool,
    point: Vec3,
}

fn main() -> i32 {
    let point: Vec3 = Vec3 { x: 1.0, y: 2.0, z: 3.0 };
    let hit: Hit = Hit { ok: true, point: point };
    let copied: Vec3 = hit.point;
    if (copied.x < 0.9) {
        return 11;
    }
    if (copied.y < 1.9) {
        return 12;
    }
    if (copied.z < 2.9) {
        return 13;
    }
    return 0;
}
"#,
    )
    .expect("aggregate-valued member lets should compile to WASM value copies");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate member value copy",
        "aggregate_member_value_copy",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_copies_aggregate_local_and_updates_scalar_members() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn bump(pair: Pair) -> Pair {
    let next: Pair = pair;
    next.left += 2;
    next.right = next.left - 1;
    return next;
}

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, right: 5 };
    let next: Pair = bump(pair);
    if (next.left != 9) {
        return 1;
    }
    if (next.right != 8) {
        return 2;
    }
    return 0;
}
"#,
    )
    .expect("aggregate local copies and scalar member assignments should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate local copy and scalar member assignments",
        "aggregate_local_copy_member_assignments",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_copies_nested_aggregate_member_from_returned_aggregate() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

struct Hit {
    ok: bool,
    normal: Vec3,
}

fn make_hit() -> Hit {
    let normal: Vec3 = Vec3::new(0.0, 1.0, 0.0);
    return Hit { ok: true, normal: normal };
}

fn forward_hit() -> Hit {
    let source: Hit = make_hit();
    let source_normal: Vec3 = source.normal;
    let normal_x: f32 = source_normal.x;
    let normal_y: f32 = source_normal.y;
    let normal_z: f32 = source_normal.z;
    let normal: Vec3 = Vec3::new(normal_x, normal_y, normal_z);
    return Hit { ok: source.ok, normal: normal };
}

fn main() -> i32 {
    let hit: Hit = forward_hit();
    let normal: Vec3 = hit.normal;
    let light: Vec3 = Vec3::new(-0.4, 0.9, -0.6);
    let diffuse: f32 = normal.dot(light);
    if (diffuse > 0.8 && diffuse < 1.0) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("nested aggregate member from returned aggregate should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM returned nested aggregate member copy",
        "returned_nested_aggregate_member_copy",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_passes_aggregate_member_as_aggregate_call_argument() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }
}

struct Sphere {
    center: Vec3,
    radius: f32,
}

fn subtract_center(point: Vec3, sphere: Sphere) -> Vec3 {
    return point.sub(sphere.center);
}

fn main() -> i32 {
    let center: Vec3 = Vec3::new(0.0, -100.5, -1.0);
    let sphere: Sphere = Sphere { center: center, radius: 100.0 };
    let point: Vec3 = Vec3::new(0.0, -0.5, -0.57);
    let outward: Vec3 = subtract_center(point, sphere);
    if (outward.y > 99.9 && outward.y < 100.1 &&
        outward.z > 0.4 && outward.z < 0.5) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate member call argument should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate member call argument",
        "aggregate_member_call_argument",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_handles_member_address_chain_deeper_than_legacy_limit() {
    common::require_node();
    const DEPTH: usize = 24;

    let mut source = String::from("struct Leaf { value: i32, }\n");
    for depth in 1..=DEPTH {
        let child_ty = if depth == 1 {
            "Leaf".to_owned()
        } else {
            format!("Wrap{}", depth - 1)
        };
        source.push_str(&format!("struct Wrap{depth} {{ child: {child_ty}, }}\n"));
    }

    let member_chain = format!("value{}", ".child".repeat(DEPTH)) + ".value";
    source.push_str(&format!(
        "fn read(value: Wrap{DEPTH}) -> i32 {{ return {member_chain}; }}\n"
    ));
    source.push_str("fn main() {\nlet leaf: Leaf = Leaf { value: 42 };\n");
    for depth in 1..=DEPTH {
        let child = if depth == 1 {
            "leaf".to_owned()
        } else {
            format!("wrap{}", depth - 1)
        };
        source.push_str(&format!(
            "let wrap{depth}: Wrap{depth} = Wrap{depth} {{ child: {child} }};\n"
        ));
    }
    source.push_str(&format!("print(read(wrap{DEPTH}));\nreturn 0;\n}}\n"));

    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep aggregate member chain should compile to WASM");
    let stdout = common::run_wasm_main_with_node(
        "WASM aggregate member chain beyond legacy depth",
        "deep_aggregate_member_chain",
        &wasm,
    );
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_resolves_member_chain_through_conflicting_field_layouts() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Leaf {
    padding: i32,
    value: i32,
}

struct Inner {
    child: Leaf,
    padding: i32,
}

struct Outer {
    padding: i32,
    child: Inner,
}

fn read(value: Outer) -> i32 {
    return value.child.child.value;
}

fn main() {
    let leaf: Leaf = Leaf { padding: 7, value: 42 };
    let inner: Inner = Inner { child: leaf, padding: 11 };
    let outer: Outer = Outer { padding: 13, child: inner };
    print(read(outer));
    return 0;
}
"#,
    )
    .expect("receiver types should resolve member fields with conflicting ordinals");
    let stdout = common::run_wasm_main_with_node(
        "WASM receiver-typed member chain with conflicting field layouts",
        "conflicting_field_layout_member_chain",
        &wasm,
    );
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_copies_aggregate_member_beyond_legacy_address_depth() {
    common::require_node();
    const DEPTH: usize = 24;

    let mut source = String::from("struct Leaf { value: i32, }\n");
    for depth in 1..=DEPTH {
        let child_ty = if depth == 1 {
            "Leaf".to_owned()
        } else {
            format!("Wrap{}", depth - 1)
        };
        if depth % 2 == 0 {
            source.push_str(&format!(
                "struct Wrap{depth} {{ padding: i32, child: {child_ty}, }}\n"
            ));
        } else {
            source.push_str(&format!(
                "struct Wrap{depth} {{ child: {child_ty}, padding: i32, }}\n"
            ));
        }
    }

    let member_chain = format!("value{}", ".child".repeat(DEPTH));
    source.push_str(&format!(
        "fn copy_leaf(value: Wrap{DEPTH}) -> Leaf {{\n    let copied: Leaf = {member_chain};\n    return copied;\n}}\n"
    ));
    source.push_str("fn main() {\nlet leaf: Leaf = Leaf { value: 42 };\n");
    for depth in 1..=DEPTH {
        let child = if depth == 1 {
            "leaf".to_owned()
        } else {
            format!("wrap{}", depth - 1)
        };
        let fields = if depth % 2 == 0 {
            format!("padding: {depth}, child: {child}")
        } else {
            format!("child: {child}, padding: {depth}")
        };
        source.push_str(&format!(
            "let wrap{depth}: Wrap{depth} = Wrap{depth} {{ {fields} }};\n"
        ));
    }
    source.push_str(&format!(
        "let copied: Leaf = copy_leaf(wrap{DEPTH});\nprint(copied.value);\nreturn 0;\n}}\n"
    ));

    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep aggregate member copies should use expression-span metadata");
    let stdout = common::run_wasm_main_with_node(
        "WASM aggregate copy beyond legacy member-address depth",
        "deep_aggregate_member_copy",
        &wasm,
    );
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_assigns_through_member_chain_beyond_legacy_address_depth() {
    common::require_node();
    const DEPTH: usize = 24;

    let mut source = String::from("struct Leaf { value: i32, }\n");
    for depth in 1..=DEPTH {
        let child_ty = if depth == 1 {
            "Leaf".to_owned()
        } else {
            format!("Wrap{}", depth - 1)
        };
        source.push_str(&format!(
            "struct Wrap{depth} {{ padding: i32, child: {child_ty}, }}\n"
        ));
    }

    source.push_str("fn main() {\nlet leaf: Leaf = Leaf { value: 0 };\n");
    for depth in 1..=DEPTH {
        let child = if depth == 1 {
            "leaf".to_owned()
        } else {
            format!("wrap{}", depth - 1)
        };
        source.push_str(&format!(
            "let wrap{depth}: Wrap{depth} = Wrap{depth} {{ padding: {depth}, child: {child} }};\n"
        ));
    }
    let member_chain = format!("wrap{DEPTH}{}", ".child".repeat(DEPTH));
    source.push_str(&format!(
        "{member_chain}.value = 42;\nprint({member_chain}.value);\nreturn 0;\n}}\n"
    ));

    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep aggregate member assignments should use expression-span metadata");
    let stdout = common::run_wasm_main_with_node(
        "WASM assignment beyond legacy member-address depth",
        "deep_aggregate_member_assignment",
        &wasm,
    );
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_executes_aggregate_return_direct_call_with_member_expr_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        let result: Vec3 = Vec3 { x: x, y: y, z: z };
        return result;
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }
}

fn main() -> i32 {
    let left: Vec3 = Vec3::new(1.0, 2.0, 3.0);
    let right: Vec3 = Vec3::new(4.0, 5.0, 6.0);
    let sum: Vec3 = left.add(right);
    if (sum.y > 6.9 && sum.y < 7.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate-return direct calls should accept scalar expression arguments");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate return direct call with member expr args",
        "aggregate_return_direct_call_member_expr_args",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_let_binary_expr_with_direct_call_operand() {
    common::require_node();
    let source = r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

fn bump(value: i32) -> i32 {
    return value + 1;
}

fn main() -> i32 {
    let left: Vec3 = Vec3 { x: 3.0, y: 0.0, z: 0.0 };
    let right: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let float_left: f32 = left.dot(right) - right.x * right.x;
    let float_right: f32 = right.x * right.x - left.dot(right);
    let int_left: i32 = bump(10) - 4;
    let int_right: i32 = 20 - bump(5);
    if (float_left > 1.9 && float_left < 2.1 &&
        float_right > -2.1 && float_right < -1.9 &&
        int_left == 7 && int_right == 14) {
        return 0;
    }
    return 1;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(source)
        .expect("let binary expression with direct-call operand should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM let binary direct-call operand",
        "let_binary_direct_call_operand",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_compound_assignment_with_direct_call_rhs() {
    common::require_node();
    let source = r#"
fn add(x: i32, y: i32) -> i32 {
    return x + y;
}

fn main() -> i32 {
    let total: i32 = 1;
    total += add(2, 3) + 4;
    total += 20 - add(2, 3);
    return total;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(source)
        .expect("compound assignment with a direct-call RHS should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM compound assignment with direct-call RHS",
        "compound_assign_direct_call_rhs",
        &wasm,
    );
    assert_eq!(status, 25);
}

#[test]
fn wasm_executes_plain_assignment_with_direct_call_rhs() {
    common::require_node();
    let source = r#"
fn add(x: i32, y: i32) -> i32 {
    return x + y;
}

fn main() -> i32 {
    let total: i32 = 0;
    total = add(2, 3) + 4;
    total = 20 - add(2, 3);
    return total;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(source)
        .expect("plain assignment with a direct-call RHS should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM plain assignment with direct-call RHS",
        "plain_assign_direct_call_rhs",
        &wasm,
    );
    assert_eq!(status, 15);
}

#[test]
fn wasm_executes_float_compound_assignment_with_direct_call_rhs() {
    common::require_node();
    let source = r#"
fn adjust(x: f32) -> f32 {
    return x + 1.5;
}

fn main() -> i32 {
    let total: f32 = 2.0;
    let plain: f32 = 0.0;
    total += adjust(3.0) - 1.0;
    total += 10.0 - adjust(3.0);
    plain = adjust(3.0) - 1.0;
    plain = 10.0 - adjust(3.0);
    if (total > 10.9 && total < 11.1 && plain > 5.4 && plain < 5.6) {
        return 0;
    }
    return 1;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(source)
        .expect("float compound assignment with a direct-call RHS should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM float compound assignment with direct-call RHS",
        "float_compound_assign_direct_call_rhs",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_plain_scalar_assignment_expression() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() -> i32 {
    let total: i32 = 0;
    let x: i32 = 2;
    let y: i32 = 3;
    total = x + y * 2;
    return total;
}
"#,
    )
    .expect("plain scalar assignment expression should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM plain scalar assignment expression",
        "plain_scalar_assignment_expression",
        &wasm,
    );
    assert_eq!(status, 8);
}

#[test]
fn wasm_executes_general_scalar_call_expression_forest() {
    common::require_node();
    let source = r#"
fn bump(x: i32) -> i32 {
    return x + 1;
}

fn twice(x: i32) -> i32 {
    return x * 2;
}

fn main() -> i32 {
    let a: i32 = (bump(3) + bump(4)) * (twice(2) + 1);
    let b: i32 = 0;
    b = (bump(1) + twice(3)) * (bump(2) + 1);
    b += (bump(0) + bump(1)) * 2;
    return (a + b) + bump(twice(2));
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(source)
        .expect("general scalar call expression forest should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM general scalar call expression forest",
        "general_scalar_call_expression_forest",
        &wasm,
    );
    assert_eq!(status, 88);
}

#[test]
fn wasm_executes_float_compound_scalar_assignment_expression() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() -> i32 {
    let total: f32 = 1.5;
    let delta: f32 = 2.0;
    total += delta * 2.0;
    if (total > 5.4 && total < 5.6) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("float compound scalar assignment expression should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM float compound scalar assignment expression",
        "float_compound_scalar_assignment_expression",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_array_literal_indexed_accumulation() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
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
"#,
    )
    .expect("array literal indexed accumulation should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM array literal indexed accumulation",
        "array_index_accum",
        &wasm,
    );
    assert_eq!(stdout, "14\n");
}

#[test]
fn wasm_executes_computed_array_literal_elements() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() -> i32 {
    let base: i32 = 3;
    let values: [i32; 2] = [base + 1, base * 2];
    let total: i32 = 0;
    total += values[0];
    total += values[1];
    return total;
}

"#,
    )
    .expect("computed array literal elements should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM computed array literal elements",
        "computed_array_literal_elements",
        &wasm,
    );
    assert_eq!(status, 10);
}

#[test]
fn wasm_executes_deep_computed_array_literal_elements() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn build(x: i32) -> i32 {
    let value: i32 = 7;
    let values: [i32; 4] = [
        value,
        (x + 8) & 31,
        (value + 6) & 31,
        (x * 3 + 7) & 31,
    ];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        total = (total + values[i] * (i + 1)) & 255;
        i += 1;
    }
    return total;
}

fn main() -> i32 {
    return build(5);
}
"#,
    )
    .expect("nested array element expressions should use the parallel expression forest");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested computed array literal elements",
        "deep_computed_array_literal_elements",
        &wasm,
    );
    assert_eq!(status, 160);
}

#[test]
fn wasm_executes_computed_struct_literal_fields() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn main() -> i32 {
    let base: i32 = 4;
    let pair: Pair = Pair { left: base + 2, right: base * 3 };
    return pair.left + pair.right;
}
"#,
    )
    .expect("computed struct literal fields should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM computed struct literal fields",
        "computed_struct_literal_fields",
        &wasm,
    );
    assert_eq!(status, 18);
}

#[test]
fn wasm_executes_struct_field_expression_beyond_legacy_stack_depth() {
    common::require_node();
    let mut expression = "1".to_owned();
    for _ in 0..24 {
        expression = format!("({expression} + 1)");
    }
    let source = format!(
        r#"
struct Pair {{
    left: i32,
    right: i32,
}}

fn main() -> i32 {{
    let pair: Pair = Pair {{ left: {expression}, right: 17 }};
    return pair.left + pair.right;
}}
"#
    );
    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep struct-field expression should compile without a bounded sizing walk");

    let status = common::run_wasm_main_return_with_node(
        "WASM deep struct-field expression",
        "deep_struct_field_expression",
        &wasm,
    );
    assert_eq!(status, 42);
}

#[test]
fn wasm_routes_member_expression_beyond_legacy_feature_stack() {
    common::require_node();
    let mut right = "1".to_owned();
    for _ in 0..24 {
        right = format!("(1 + {right})");
    }
    let source = format!(
        r#"
struct Boxed {{
    value: i32,
}}

fn main() -> i32 {{
    let boxed: Boxed = Boxed {{ value: 17 }};
    let total: i32 = boxed.value + {right};
    return total;
}}
"#
    );
    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("deep member expression should route from scanned subtree features");

    let status = common::run_wasm_main_return_with_node(
        "WASM deep member-expression routing",
        "deep_member_expression_routing",
        &wasm,
    );
    assert_eq!(status, 42);
}

#[test]
fn wasm_executes_scalar_while_loop_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
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

"#,
    )
    .expect("scalar while construct should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM scalar while construct", "while_sum", &wasm);
    assert_eq!(stdout, "55\n");
}

#[test]
fn wasm_reevaluates_member_expression_while_condition_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct State {
    value: i32,
    limit: i32,
}

fn main() {
    let state: State = State { value: 1, limit: 5 };
    let total: i32 = 0;
    while (state.value < state.limit && state.value < 6) {
        total += state.value;
        state.value += 1;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("member-expression while condition should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM reevaluated member-expression while condition",
        "while_member_condition",
        &wasm,
    );
    assert_eq!(stdout, "10\n");
}

#[test]
fn wasm_executes_f32_newton_iteration_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn sqrt(value: f32) -> f32 {
    if (value <= 0.0) {
        return 0.0;
    }
    let guess: f32 = value;
    if (guess < 1.0) {
        guess = 1.0;
    }
    let iteration: i32 = 0;
    while (iteration < 8) {
        guess = 0.5 * (guess + value / guess);
        iteration = iteration + 1;
    }
    return guess;
}

fn main() {
    let root: f32 = sqrt(9.0);
    if (root > 2.99 && root < 3.01) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("f32 Newton iteration should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 Newton iteration",
        "f32_newton_iteration",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_nested_boolean_conditions_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let total: i32 = 0;
    let t_min: i32 = 2;
    let t_max: i32 = 4;
    let root: i32 = 5;
    if (root < t_min || root > t_max) {
        total += 10;
    } else {
        total += 100;
    }

    let root_ok: i32 = 3;
    if (root_ok < t_min || root_ok > t_max) {
        total += 1000;
    } else {
        total += 1;
    }

    let threshold: i32 = 0;
    let scaled: i32 = 5;
    let byte: i32 = 250;
    while (threshold <= scaled && byte < 255) {
        threshold += 2;
        byte += 1;
        total += 1;
    }

    print(total);
    return 0;
}
"#,
    )
    .expect("nested boolean conditions should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM nested boolean conditions",
        "nested_boolean_conditions",
        &wasm,
    );
    assert_eq!(stdout, "14\n");
}

#[test]
fn wasm_executes_runtime_if_else_after_assignment_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let x: i32 = 0;
    x += 1;
    if (x == 1) {
        print(7);
    } else {
        print(9);
    }
    return 0;
}
"#,
    )
    .expect("runtime if/else should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM runtime if/else after assignment",
        "runtime_if_else",
        &wasm,
    );
    assert_eq!(stdout, "7\n");
}

#[test]
fn wasm_executes_while_break_and_continue_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 8) {
        i += 1;
        if (i == 3) {
            continue;
        }
        if (i > 5) {
            break;
        }
        total += i;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("while break/continue should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM while break/continue", "while_break_continue", &wasm);
    assert_eq!(stdout, "12\n");
}

#[test]
fn wasm_executes_numeric_range_for_loop_with_break_continue_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let end: i32 = 8;
    let total: i32 = 0;
    for value in 2..end {
        if (value == 4) {
            continue;
        }
        if (value == 7) {
            break;
        }
        total += value;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("numeric range for construct should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM numeric range for construct",
        "numeric_range_for",
        &wasm,
    );
    assert_eq!(stdout, "16\n");
}

#[test]
fn wasm_executes_array_for_loop_with_break_continue_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() -> i32 {
    let values: [i32; 6] = [1, 2, 3, 4, 5, 6];
    let total: i32 = 0;
    for value in values {
        if (value == 2) {
            continue;
        }
        if (value == 5) {
            break;
        }
        total += value;
    }
    return total;
}
"#,
    )
    .expect("array for-loop with break/continue should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM array for-loop with break/continue",
        "array_for_break_continue",
        &wasm,
    );
    assert_eq!(status, 8);
}

#[test]
fn wasm_executes_simple_range_loop_then_prints_local_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let end: i32 = 6;
    let total: i32 = 0;
    for value in 2..end {
        total += value;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("simple numeric range and trailing local print should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM simple range with trailing local print",
        "simple_range_print_local",
        &wasm,
    );
    assert_eq!(stdout, "14\n");
}

#[test]
fn wasm_resolves_outer_loop_local_beyond_legacy_control_depth() {
    common::require_node();
    const DEPTH: usize = 24;

    let mut source = String::from("fn main() {\nlet end: i32 = 2;\nfor value in 0..end {\n");
    for _ in 0..DEPTH {
        source.push_str("if (value >= 0) {\n");
    }
    source.push_str("print(value);\n");
    for _ in 0..DEPTH {
        source.push_str("}\n");
    }
    source.push_str("}\nreturn 0;\n}\n");

    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("loop locals should resolve from semantic declarations at arbitrary depth");
    let stdout = common::run_wasm_main_with_node(
        "WASM outer loop local beyond legacy control depth",
        "deep_outer_loop_local",
        &wasm,
    );
    assert_eq!(stdout, "0\n1\n");
}

#[test]
fn wasm_branches_through_ifs_beyond_legacy_control_depth() {
    common::require_node();
    const DEPTH: usize = 24;

    let mut source = String::from(
        "fn main() {\n\
         let break_value: i32 = 0;\n\
         if (break_value == 0) {\n\
         while (break_value < 3) {\n\
         break_value += 1;\n",
    );
    for _ in 0..DEPTH {
        source.push_str("if (break_value >= 0) {\n");
    }
    source.push_str("break;\n");
    for _ in 0..DEPTH {
        source.push_str("}\n");
    }
    source.push_str(
        "break_value += 100;\n\
         }\n\
         }\n\
         let continue_value: i32 = 0;\n\
         let skipped: i32 = 0;\n\
         if (continue_value == 0) {\n\
         while (continue_value < 3) {\n\
         continue_value += 1;\n",
    );
    for _ in 0..DEPTH {
        source.push_str("if (continue_value >= 0) {\n");
    }
    source.push_str("continue;\n");
    for _ in 0..DEPTH {
        source.push_str("}\n");
    }
    source.push_str(
        "skipped += 100;\n\
         }\n\
         }\n\
         print(break_value);\n\
         print(continue_value + skipped);\n\
         return 0;\n\
         }\n",
    );

    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("break and continue should use exact parallel control-depth metadata");
    let stdout = common::run_wasm_main_with_node(
        "WASM branches beyond legacy control depth",
        "deep_break_continue",
        &wasm,
    );
    assert_eq!(stdout, "1\n3\n");
}

#[test]
fn wasm_executes_direct_user_function_call_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn add_fee(value: i32) -> i32 {
    return value + 4;
}

fn main() {
    print(add_fee(36));
    return 0;
}
"#,
    )
    .expect("direct scalar function call should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM direct function call", "direct_call", &wasm);
    assert_eq!(stdout, "40\n");
}

#[test]
fn wasm_executes_direct_user_function_call_with_unary_constant_expression_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn mix(left: i32, right: i32) -> i32 {
    return left + right;
}

fn main() {
    print(mix(-17, 23));
    return 0;
}
"#,
    )
    .expect("direct scalar function calls should accept unary constant expression arguments");

    let stdout = common::run_wasm_main_with_node(
        "WASM direct call constant expression args",
        "direct_call_const_expr_args",
        &wasm,
    );
    assert_eq!(stdout, "6\n");
}

#[test]
fn wasm_executes_direct_user_function_call_with_more_than_four_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn sum5(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
    return e;
}

fn main() {
    print(sum5(1, 2, 3, 4, 5));
    return 0;
}
"#,
    )
    .expect("direct scalar function calls should not be capped at four arguments");

    let stdout = common::run_wasm_main_with_node(
        "WASM direct call more than four args",
        "direct_call_more_than_four_args",
        &wasm,
    );
    assert_eq!(stdout, "5\n");
}

#[test]
fn wasm_emits_more_than_one_type_scan_block_of_functions() {
    common::require_node();
    const FUNCTION_COUNT: usize = 257;
    let mut source = String::new();
    for index in 0..FUNCTION_COUNT {
        writeln!(source, "fn value_{index}() -> i32 {{ return {index}; }}")
            .expect("write generated function");
    }
    source.push_str("fn main() {\n");
    for index in 0..FUNCTION_COUNT {
        writeln!(source, "    print(value_{index}());").expect("write generated call");
    }
    source.push_str("    return 0;\n}\n");

    let wasm = common::compile_source_to_wasm_with_timeout(&source)
        .expect("WASM module type-entry scan should cross a 256-lane block boundary");
    let stdout = common::run_wasm_main_with_node(
        "WASM multi-block function type scan",
        "multi_block_function_type_scan",
        &wasm,
    );
    let expected = (0..FUNCTION_COUNT)
        .map(|index| format!("{index}\n"))
        .collect::<String>();
    assert_eq!(stdout, expected);
}

#[test]
fn wasm_executes_mixed_scalar_direct_user_function_call_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn choose(flag: i32, value: f32) -> i32 {
    if (value > 2.0) {
        return flag;
    }
    return 0;
}

fn main() {
    print(choose(37, 2.5));
    return 0;
}
"#,
    )
    .expect("mixed scalar direct function call should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM mixed scalar direct function call",
        "mixed_scalar_direct_call",
        &wasm,
    );
    assert_eq!(stdout, "37\n");
}

#[test]
fn wasm_executes_nested_direct_user_function_calls_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn add(x: i32, y: i32) -> i32 {
    return x + y;
}

fn double(x: i32) -> i32 {
    return add(x, x);
}

fn main() {
    print(double(21));
    return 0;
}
"#,
    )
    .expect("nested direct scalar function calls should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM nested function calls", "nested_direct_calls", &wasm);
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_executes_nested_user_function_calls_as_if_condition() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn write_status() -> i32 {
    return 0;
}

fn operation_failed(result: i32) -> bool {
    return result < 0;
}

fn main() -> i32 {
    if (operation_failed(write_status())) {
        return 1;
    }
    return 42;
}
"#,
    )
    .expect("nested user calls in an if condition should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested user calls in if condition",
        "nested_user_calls_if_condition",
        &wasm,
    );
    assert_eq!(status, 42);
}

#[test]
fn wasm_executes_six_argument_call_with_nested_call_values() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn add(x: i32, y: i32) -> i32 {
    return x + y;
}

fn sum6(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) -> i32 {
    return a + b + c + d + e + f;
}

fn main() {
    print(sum6(add(1, 2), 4, add(5, 6), 7, 8, 9));
    return 0;
}
"#,
    )
    .expect("six-argument call with nested call values should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM six-argument call with nested call values",
        "six_argument_call_nested_values",
        &wasm,
    );
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_executes_recursive_direct_call_with_expression_argument() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn fact(n: i32) -> i32 {
    if (n <= 1) {
        return 1;
    } else {
        return n * fact(n - 1);
    }
}

fn main() {
    print(fact(6));
    return 0;
}
"#,
    )
    .expect("recursive direct call with expression argument should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM recursive direct call expression argument",
        "recursive_direct_call_expr_arg",
        &wasm,
    );
    assert_eq!(stdout, "720\n");
}

#[test]
fn wasm_executes_binary_return_with_direct_call_operand() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn bump(value: i32) -> i32 {
    return value + 1;
}

fn call_on_left(value: i32) -> i32 {
    return bump(value) + 4;
}

fn call_on_right(value: i32) -> i32 {
    return 4 + bump(value);
}

fn bump_float(value: f32) -> f32 {
    return value + 1.0;
}

fn float_call_on_left(value: f32) -> f32 {
    return bump_float(value) - 4.0;
}

fn float_call_on_right(value: f32) -> f32 {
    return 10.0 - bump_float(value);
}

fn main() {
    let left: f32 = float_call_on_left(5.0);
    let right: f32 = float_call_on_right(7.0);
    if (!(left > 1.9 && left < 2.1 && right > 1.9 && right < 2.1)) {
        return 1;
    }
    print(call_on_left(37));
    print(call_on_right(37));
    return 0;
}
"#,
    )
    .expect("binary return expression with direct-call operand should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM binary return direct-call operand",
        "binary_return_direct_call_operand",
        &wasm,
    );
    assert_eq!(stdout, "42\n42\n");
}

#[test]
fn wasm_executes_multiple_explicit_returns_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn abs_i32(value: i32) -> i32 {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}

fn main() {
    let negative: i32 = -17;
    let checked: i32 = abs_i32(negative);
    if (checked == 17) {
        let positive: i32 = abs_i32(23);
        print(positive);
        return 0;
    } else {
        return 1;
    }
}
"#,
    )
    .expect("multiple explicit returns should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM multiple explicit returns",
        "multiple_returns",
        &wasm,
    );
    assert_eq!(stdout, "23\n");
}

#[test]
fn wasm_executes_exact_clock_buffer_api_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;
import alloc::allocator;
import std::time;
fn main() -> i32 {
    let ptr: u32 = alloc::allocator::alloc(16, 8);
    let monotonic_status: i32 = std::time::monotonic_read(ptr, 16);
    if (monotonic_status != 0) {
        return 1;
    }
    let system_status: i32 = std::time::system_read(ptr, 16);
    if (system_status != 0) {
        return 2;
    }
    let short_status: i32 = std::time::monotonic_read(ptr, 15);
    if (short_status != -1) {
        return 3;
    }
    let sleep_status: i32 = std::time::sleep_ms_i32(0);
    if (sleep_status != 0) {
        return 4;
    }
    let negative_status: i32 = std::time::sleep_ms_i32(-1);
    if (negative_status != -1) {
        return 5;
    }
    alloc::allocator::dealloc(ptr, 16, 8);
    return 0;
}
"#,
    ])
    .expect("exact clock buffer API should compile to WASM");
    let status = common::run_wasm_main_return_with_node(
        "WASM exact clock buffer API",
        "exact_clock_buffer",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_returns_scalar_host_call_with_negative_expression_argument() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;
import std::time;
fn main() -> i32 {
    return std::time::sleep_ms_i32(-1);
}
"#,
    ])
    .expect("return-position scalar host calls should compile to WASM");
    let status = common::run_wasm_main_return_with_node(
        "WASM return-position scalar host call",
        "return_scalar_host_call",
        &wasm,
    );
    assert_eq!(status, -1);
}

#[test]
fn wasm_realloc_preserves_existing_bytes_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;
import alloc::allocator;
import std::process;
import std::io;
fn main() -> i32 {
    let ptr: u32 = alloc::allocator::alloc(32, 4);
    let read: i32 = std::process::arg_read(1, ptr, 32);
    if (read != 15) {
        return 1;
    }
    let grown: u32 = alloc::allocator::realloc(ptr, 32, 64, 4);
    if (grown == 0) {
        return 2;
    }
    let written: i32 = std::io::write_stdout(grown, 15);
    if (written != 15) {
        return 3;
    }
    alloc::allocator::dealloc(grown, 64, 4);
    return 0;
}
"#,
    ])
    .expect("realloc preservation should compile to WASM");
    let stdout =
        common::run_wasm_main_with_node("WASM realloc preservation", "realloc_preservation", &wasm);
    assert_eq!(stdout, "LANIUS_TEST_ENV");
}

#[test]
fn wasm_alloc_failed_is_non_returning_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;
import alloc::allocator;
fn main() -> i32 {
    alloc::allocator::alloc_failed(64, 8);
    return 99;
}
"#,
    ])
    .expect("alloc_failed should compile to WASM");
    let status = common::run_wasm_main_return_with_node("WASM alloc_failed", "alloc_failed", &wasm);
    assert_eq!(status, 1);
}
