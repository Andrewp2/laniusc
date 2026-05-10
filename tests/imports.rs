mod common;

use std::{fs, io, path::PathBuf};

use laniusc::{
    compiler::{
        CompileError,
        expand_source_imports,
        expand_source_imports_from_path,
        expand_type_aliases_in_source,
    },
    hir::parse_source,
};

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(stem: &str) -> Self {
        let path = common::temp_artifact_path("laniusc_imports", stem, None);
        fs::create_dir_all(&path)
            .unwrap_or_else(|err| panic!("create temporary directory {}: {err}", path.display()));
        Self { path }
    }

    fn write(&self, relative: &str, contents: &str) -> PathBuf {
        let path = self.path.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .unwrap_or_else(|err| panic!("create directory {}: {err}", parent.display()));
        }
        fs::write(&path, contents)
            .unwrap_or_else(|err| panic!("write temporary file {}: {err}", path.display()));
        path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        match fs::remove_dir_all(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(_) => {}
        }
    }
}

#[test]
fn source_only_stdlib_import_expands_and_parses() {
    let src = r#"
import "stdlib/i32.lani";

fn main() {
    return lstd_i32_abs(-7);
}
"#;

    let expanded = expand_source_imports(src).expect("expand stdlib import");
    assert!(expanded.contains("pub fn lstd_i32_abs"));
    assert!(!expanded.contains("import \"stdlib/i32.lani\";"));
    parse_source(&expanded).expect("expanded stdlib import should parse");
}

#[test]
fn module_style_stdlib_imports_expand_and_parse() {
    let src = r#"
import core::i32;
import core::bool;

fn main() {
    let high: i32 = core::i32::MAX;
    let positive: bool = core::i32::between_inclusive(7, 0, high);
    return core::bool::to_i32(positive) + core::i32::saturating_abs(-6);
}
"#;

    let expanded = expand_source_imports(src).expect("expand module-style stdlib imports");
    assert!(expanded.contains("pub fn __lanius_core_i32_abs"));
    assert!(expanded.contains("pub fn __lanius_core_i32_saturating_abs"));
    assert!(expanded.contains("pub const __lanius_core_i32_MAX"));
    assert!(expanded.contains("pub fn __lanius_core_bool_to_i32"));
    assert!(expanded.contains("let high: i32 = __lanius_core_i32_MAX;"));
    assert!(expanded.contains("__lanius_core_i32_between_inclusive(7, 0, high)"));
    assert!(
        expanded
            .contains("__lanius_core_bool_to_i32(positive) + __lanius_core_i32_saturating_abs(-6)")
    );
    assert!(!expanded.contains("import core::i32;"));
    parse_source(&expanded).expect("expanded module-style stdlib imports should parse");
}

#[test]
fn module_style_primitive_seed_imports_expand_and_parse() {
    let src = r#"
import core::u32;
import core::u8;
import core::i64;
import core::f32;
import core::char;

fn main() {
    let unsigned: u32 = core::u32::clamp(7, core::u32::MIN, core::u32::MAX);
    let saturated: u32 = core::u32::saturating_add(unsigned, 1);
    let byte: u8 = core::u8::clamp(65, core::u8::MIN, core::u8::MAX);
    let ascii: bool = core::u8::is_ascii_uppercase(byte);
    let wide: i64 = core::i64::abs(-9);
    let scalar: f32 = core::f32::clamp(1.5, core::f32::ZERO, core::f32::ONE);
    let digit: bool = core::char::is_ascii_digit('7');
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand primitive stdlib imports");
    assert!(expanded.contains("pub fn __lanius_core_u32_clamp"));
    assert!(expanded.contains("pub fn __lanius_core_u32_saturating_add"));
    assert!(expanded.contains("pub const __lanius_core_u32_MIN"));
    assert!(expanded.contains("pub fn __lanius_core_u8_clamp"));
    assert!(expanded.contains("pub fn __lanius_core_u8_is_ascii_uppercase"));
    assert!(expanded.contains("pub fn __lanius_core_i64_abs"));
    assert!(expanded.contains("pub fn __lanius_core_f32_clamp"));
    assert!(expanded.contains("pub fn __lanius_core_char_is_ascii_digit"));
    assert!(expanded.contains("__lanius_core_u32_clamp(7"));
    assert!(expanded.contains("__lanius_core_u32_saturating_add(unsigned, 1)"));
    assert!(expanded.contains("__lanius_core_u8_clamp(65"));
    assert!(expanded.contains("__lanius_core_u8_is_ascii_uppercase(byte)"));
    assert!(expanded.contains("__lanius_core_i64_abs(-9)"));
    assert!(expanded.contains("__lanius_core_f32_clamp(1.5"));
    assert!(expanded.contains("__lanius_core_char_is_ascii_digit('7')"));
    parse_source(&expanded).expect("expanded primitive stdlib imports should parse");
}

#[test]
fn module_style_test_assert_seed_import_expands_and_parse() {
    let src = r#"
import test::assert;

fn main() {
    test::assert::is_true(true);
    test::assert::is_false(false);
    test::assert::eq_i32(1, 1);
    test::assert::ne_i32(1, 2);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand test assertion stdlib import");
    assert!(expanded.contains("pub fn __lanius_test_assert_is_true"));
    assert!(expanded.contains("pub fn __lanius_test_assert_is_false"));
    assert!(expanded.contains("pub fn __lanius_test_assert_eq_i32"));
    assert!(expanded.contains("pub fn __lanius_test_assert_ne_i32"));
    assert!(expanded.contains("__lanius_test_assert_is_true(true);"));
    assert!(expanded.contains("__lanius_test_assert_is_false(false);"));
    assert!(expanded.contains("__lanius_test_assert_eq_i32(1, 1);"));
    assert!(expanded.contains("__lanius_test_assert_ne_i32(1, 2);"));
    parse_source(&expanded).expect("expanded test assertion stdlib import should parse");
}

#[test]
fn module_style_core_panic_seed_import_expands_and_parse() {
    let src = r#"
import core::panic;

fn main() {
    core::panic::unreachable();
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand core panic stdlib import");
    assert!(expanded.contains("pub fn __lanius_core_panic_panic"));
    assert!(expanded.contains("pub fn __lanius_core_panic_unreachable"));
    assert!(expanded.contains("assert(false);"));
    assert!(expanded.contains("__lanius_core_panic_unreachable();"));
    parse_source(&expanded).expect("expanded core panic stdlib import should parse");
}

#[test]
fn module_style_slice_seed_import_expands_and_parse() {
    let src = r#"
import core::slice;

fn main(values: [i32]) {
    let first: i32 = core::slice::first_i32(values);
    let total: i32 = core::slice::sum_i32(values, 4);
    let found: bool = core::slice::contains_i32(values, 4, first);
    let fallback: i32 = core::slice::get_or_i32(values, 4, 2, total);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand core slice stdlib import");
    assert!(expanded.contains("pub fn __lanius_core_slice_first_i32"));
    assert!(expanded.contains("pub fn __lanius_core_slice_sum_i32"));
    assert!(expanded.contains("pub fn __lanius_core_slice_contains_i32"));
    assert!(expanded.contains("pub fn __lanius_core_slice_get_or_i32"));
    assert!(expanded.contains("__lanius_core_slice_first_i32(values)"));
    assert!(expanded.contains("__lanius_core_slice_sum_i32(values, 4)"));
    assert!(expanded.contains("__lanius_core_slice_contains_i32(values, 4, first)"));
    assert!(expanded.contains("__lanius_core_slice_get_or_i32(values, 4, 2, total)"));
    parse_source(&expanded).expect("expanded core slice stdlib import should parse");
}

#[test]
fn module_style_alloc_allocator_seed_import_expands_and_parse() {
    let src = r#"
import alloc::allocator;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    let grown: u32 = alloc::allocator::realloc(ptr, 16, 32, 4);
    alloc::allocator::dealloc(grown, 32, 4);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand alloc allocator stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_alloc" fn __lanius_alloc_allocator_alloc"#));
    assert!(expanded.contains(r#"pub extern "lanius_alloc" fn __lanius_alloc_allocator_realloc"#));
    assert!(expanded.contains(r#"pub extern "lanius_alloc" fn __lanius_alloc_allocator_dealloc"#));
    assert!(expanded.contains("__lanius_alloc_allocator_alloc(16, 4)"));
    assert!(expanded.contains("__lanius_alloc_allocator_realloc(ptr, 16, 32, 4)"));
    assert!(expanded.contains("__lanius_alloc_allocator_dealloc(grown, 32, 4);"));
    parse_source(&expanded).expect("expanded alloc allocator stdlib import should parse");
}

#[test]
fn module_style_std_io_seed_import_expands_and_parse() {
    let src = r#"
import std::io;

fn main() {
    let ptr: u32 = 0;
    let written: i32 = std::io::write_stdout(ptr, 4);
    let warned: i32 = std::io::write_stderr(ptr, 4);
    let read: i32 = std::io::read_stdin(ptr, 4);
    let flushed: i32 = std::io::flush_stdout() + std::io::flush_stderr();
    std::io::print_i32(written + warned + read + flushed);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand std io stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_io_write_stdout"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_io_write_stderr"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_io_read_stdin"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_io_flush_stdout"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_io_flush_stderr"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_io_print_i32"#));
    assert!(expanded.contains("__lanius_std_io_write_stdout(ptr, 4)"));
    assert!(expanded.contains("__lanius_std_io_write_stderr(ptr, 4)"));
    assert!(expanded.contains("__lanius_std_io_read_stdin(ptr, 4)"));
    assert!(expanded.contains("__lanius_std_io_flush_stdout() + __lanius_std_io_flush_stderr()"));
    assert!(expanded.contains("__lanius_std_io_print_i32(written + warned + read + flushed);"));
    parse_source(&expanded).expect("expanded std io stdlib import should parse");
}

#[test]
fn module_style_std_process_seed_import_expands_and_parse() {
    let src = r#"
import std::process;

fn main() {
    let count: i32 = std::process::argc();
    let length: i32 = std::process::arg_len(0);
    let read: i32 = std::process::arg_read(0, 0, 16);
    std::process::set_exit_code(count + length + read);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand std process stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_process_argc"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_process_arg_len"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_process_arg_read"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_process_set_exit_code"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_process_exit"#));
    assert!(expanded.contains("__lanius_std_process_argc()"));
    assert!(expanded.contains("__lanius_std_process_arg_len(0)"));
    assert!(expanded.contains("__lanius_std_process_arg_read(0, 0, 16)"));
    assert!(expanded.contains("__lanius_std_process_set_exit_code(count + length + read);"));
    parse_source(&expanded).expect("expanded std process stdlib import should parse");
}

#[test]
fn module_style_std_env_seed_import_expands_and_parse() {
    let src = r#"
import std::env;

fn main() {
    let value_len: i32 = std::env::var_len(0, 0);
    let read: i32 = std::env::var_read(0, 0, 16, 32);
    let count: i32 = std::env::var_count();
    let key_len: i32 = std::env::var_key_len(0);
    let key_read: i32 = std::env::var_key_read(0, 64, 16);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand std env stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_env_var_len"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_env_var_read"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_env_var_count"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_env_var_key_len"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_env_var_key_read"#));
    assert!(expanded.contains("__lanius_std_env_var_len(0, 0)"));
    assert!(expanded.contains("__lanius_std_env_var_read(0, 0, 16, 32)"));
    assert!(expanded.contains("__lanius_std_env_var_count()"));
    assert!(expanded.contains("__lanius_std_env_var_key_len(0)"));
    assert!(expanded.contains("__lanius_std_env_var_key_read(0, 64, 16)"));
    parse_source(&expanded).expect("expanded std env stdlib import should parse");
}

#[test]
fn module_style_std_time_seed_import_expands_and_parse() {
    let src = r#"
import std::time;

fn main() {
    let monotonic: i64 = std::time::monotonic_now_ns();
    let wall: i64 = std::time::system_now_unix_ms();
    let status: i32 = std::time::sleep_ms(1);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand std time stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_time_monotonic_now_ns"#));
    assert!(
        expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_time_system_now_unix_ms"#)
    );
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_time_sleep_ms"#));
    assert!(expanded.contains("__lanius_std_time_monotonic_now_ns()"));
    assert!(expanded.contains("__lanius_std_time_system_now_unix_ms()"));
    assert!(expanded.contains("__lanius_std_time_sleep_ms(1)"));
    parse_source(&expanded).expect("expanded std time stdlib import should parse");
}

#[test]
fn module_style_std_fs_seed_import_expands_and_parse() {
    let src = r#"
import std::fs;

fn main() {
    let handle: i32 = std::fs::open_read(0, 0);
    let read: i32 = std::fs::read(handle, 16, 32);
    let written: i32 = std::fs::write(handle, 16, 32);
    let moved: i32 = std::fs::rename(0, 0, 16, 16);
    let closed: i32 = std::fs::close(handle);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand std fs stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_open_read"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_open_write"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_open_append"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_close"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_read"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_write"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_remove_file"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_create_dir"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_remove_dir"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_fs_rename"#));
    assert!(expanded.contains("__lanius_std_fs_open_read(0, 0)"));
    assert!(expanded.contains("__lanius_std_fs_read(handle, 16, 32)"));
    assert!(expanded.contains("__lanius_std_fs_write(handle, 16, 32)"));
    assert!(expanded.contains("__lanius_std_fs_rename(0, 0, 16, 16)"));
    assert!(expanded.contains("__lanius_std_fs_close(handle)"));
    parse_source(&expanded).expect("expanded std fs stdlib import should parse");
}

#[test]
fn module_style_std_net_seed_import_expands_and_parse() {
    let src = r#"
import std::net;

fn main() {
    let stream: i32 = std::net::tcp_connect(0, 0, 80);
    let sent: i32 = std::net::tcp_send(stream, 16, 32);
    let received: i32 = std::net::tcp_recv(stream, 16, 32);
    let closed: i32 = std::net::tcp_close(stream);
    let socket: i32 = std::net::udp_bind(0, 0, 53);
    let datagram: i32 = std::net::udp_send_to(socket, 0, 0, 53, 16, 32);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand std net stdlib import");
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_connect"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_bind"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_listen"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_accept"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_close"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_send"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_tcp_recv"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_udp_bind"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_udp_send_to"#));
    assert!(expanded.contains(r#"pub extern "lanius_std" fn __lanius_std_net_udp_recv_from"#));
    assert!(expanded.contains("__lanius_std_net_tcp_connect(0, 0, 80)"));
    assert!(expanded.contains("__lanius_std_net_tcp_send(stream, 16, 32)"));
    assert!(expanded.contains("__lanius_std_net_tcp_recv(stream, 16, 32)"));
    assert!(expanded.contains("__lanius_std_net_tcp_close(stream)"));
    assert!(expanded.contains("__lanius_std_net_udp_bind(0, 0, 53)"));
    assert!(expanded.contains("__lanius_std_net_udp_send_to(socket, 0, 0, 53, 16, 32)"));
    parse_source(&expanded).expect("expanded std net stdlib import should parse");
}

#[test]
fn module_style_ordering_seed_import_expands_and_parse() {
    let src = r#"
import core::ordering;

fn main() {
    let order: core::ordering::Ordering = core::ordering::compare_i32(1, 2);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand core ordering stdlib import");
    assert!(expanded.contains("pub enum __lanius_core_ordering_Ordering"));
    assert!(expanded.contains("pub fn __lanius_core_ordering_compare_i32"));
    assert!(expanded.contains("order: __lanius_core_ordering_Ordering"));
    assert!(expanded.contains("__lanius_core_ordering_compare_i32(1, 2)"));
    parse_source(&expanded).expect("expanded core ordering stdlib import should parse");
}

#[test]
fn module_style_cmp_seed_import_expands_and_parse() {
    let src = r#"
import core::cmp;

fn main() {
    let left: i32 = 3;
    let right: i32 = 5;
    let same: bool = left.eq(right);
    let less: bool = left.lt(right);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand core cmp stdlib import");
    assert!(expanded.contains("pub trait __lanius_core_cmp_Eq<T>"));
    assert!(expanded.contains("pub trait __lanius_core_cmp_Ord<T>"));
    assert!(expanded.contains("pub impl __lanius_core_cmp_Eq<i32> for i32"));
    assert!(expanded.contains("pub impl __lanius_core_cmp_Ord<i32> for i32"));
    assert!(expanded.contains("let same: bool = left.eq(right);"));
    assert!(expanded.contains("let less: bool = left.lt(right);"));
    parse_source(&expanded).expect("expanded core cmp import should parse");
}

#[test]
fn module_style_hash_seed_import_expands_and_parse() {
    let src = r#"
import core::hash;

fn main() {
    let value: i32 = 7;
    let hashed: u32 = value.hash();
    let direct: u32 = core::hash::hash_i32(value);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand core hash stdlib import");
    assert!(expanded.contains("pub trait __lanius_core_hash_Hash<T>"));
    assert!(expanded.contains("pub impl __lanius_core_hash_Hash<i32> for i32"));
    assert!(expanded.contains("pub fn __lanius_core_hash_hash_i32"));
    assert!(expanded.contains("let hashed: u32 = value.hash();"));
    assert!(expanded.contains("__lanius_core_hash_hash_i32(value)"));
    parse_source(&expanded).expect("expanded core hash import should parse");
}

#[test]
fn module_style_target_seed_import_expands_and_parse() {
    let src = r#"
import core::target;

fn main() {
    let native: bool = core::target::IS_NATIVE;
    let fs: bool = core::target::has_filesystem();
    let network: bool = core::target::has_network();
    let clock: bool = core::target::has_clock();
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand core target stdlib import");
    assert!(expanded.contains("pub const __lanius_core_target_IS_NATIVE"));
    assert!(expanded.contains("pub const __lanius_core_target_HAS_FILESYSTEM"));
    assert!(expanded.contains("pub fn __lanius_core_target_has_filesystem"));
    assert!(expanded.contains("let native: bool = __lanius_core_target_IS_NATIVE;"));
    assert!(expanded.contains("__lanius_core_target_has_filesystem()"));
    assert!(expanded.contains("__lanius_core_target_has_network()"));
    assert!(expanded.contains("__lanius_core_target_has_clock()"));
    parse_source(&expanded).expect("expanded core target stdlib import should parse");
}

#[test]
fn imported_module_declaration_exposes_namespaced_calls_in_expanded_source() {
    let dir = TempDir::new("module_namespace");
    dir.write(
        "math.lani",
        r#"
module app::math;

pub fn add_one(value: i32) -> i32 {
    return value + 1;
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "math.lani";

fn main() {
    return app::math::add_one(41);
}
"#,
    );

    let expanded = expand_source_imports_from_path(&main).expect("expand namespaced module import");
    assert!(expanded.contains("pub fn __lanius_app_math_add_one"));
    assert!(expanded.contains("return __lanius_app_math_add_one(41);"));
    assert!(!expanded.contains("module app::math;"));
    assert!(!expanded.contains("app::math::add_one"));
    parse_source(&expanded).expect("expanded namespaced module import should parse");
}

#[test]
fn imported_module_declaration_exposes_namespaced_extern_functions() {
    let dir = TempDir::new("module_extern_namespace");
    dir.write(
        "host.lani",
        r#"
module app::host;

pub extern "wasm" fn alloc(size: usize) -> u32;
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "host.lani";

fn main() {
    let ptr: u32 = app::host::alloc(4);
    return;
}
"#,
    );

    let expanded = expand_source_imports_from_path(&main).expect("expand namespaced extern import");
    assert!(expanded.contains(r#"pub extern "wasm" fn __lanius_app_host_alloc"#));
    assert!(expanded.contains("let ptr: u32 = __lanius_app_host_alloc(4);"));
    assert!(!expanded.contains("app::host::alloc"));
    parse_source(&expanded).expect("expanded extern module import should parse");
}

#[test]
fn imported_module_declaration_exposes_namespaced_type_aliases() {
    let dir = TempDir::new("module_type_alias_namespace");
    dir.write(
        "types.lani",
        r#"
module app::types;

pub type Count = i32;

pub fn add_one(value: Count) -> Count {
    return value + 1;
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "types.lani";

fn main() {
    let value: app::types::Count = app::types::add_one(1);
    return value;
}
"#,
    );

    let expanded =
        expand_source_imports_from_path(&main).expect("expand namespaced type alias import");
    assert!(expanded.contains("pub type __lanius_app_types_Count = i32;"));
    assert!(expanded.contains("value: __lanius_app_types_Count"));
    assert!(expanded.contains("__lanius_app_types_add_one(1)"));
    assert!(!expanded.contains("app::types::Count"));
    parse_source(&expanded).expect("expanded type alias module import should parse");

    let expanded_aliases =
        expand_type_aliases_in_source(&expanded).expect("expand imported type alias uses");
    assert!(expanded_aliases.contains("pub fn __lanius_app_types_add_one(value: i32) -> i32"));
    assert!(expanded_aliases.contains("let value: i32 = __lanius_app_types_add_one(1);"));
    assert!(!expanded_aliases.contains("value: __lanius_app_types_Count"));
}

#[test]
fn type_alias_expansion_rejects_cycles() {
    let src = r#"
type A = B;
type B = A;

fn main() {
    let value: A = 1;
    return value;
}
"#;

    let err = expand_type_aliases_in_source(src).expect_err("type alias cycle should fail");
    assert!(
        err.to_string().contains("type alias cycle detected"),
        "expected type alias cycle error, got {err}"
    );
}

#[test]
fn imported_module_rewrites_private_helpers_for_public_exports() {
    let dir = TempDir::new("module_private_helpers");
    dir.write(
        "math.lani",
        r#"
module app::math;

const OFFSET: i32 = 1;

fn add_one(value: i32) -> i32 {
    return value + OFFSET;
}

pub fn add_two(value: i32) -> i32 {
    return add_one(add_one(value));
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "math.lani";

fn main() {
    return app::math::add_two(40);
}
"#,
    );

    let expanded =
        expand_source_imports_from_path(&main).expect("expand module with private helpers");
    assert!(expanded.contains("const __lanius_app_math_OFFSET"));
    assert!(expanded.contains("fn __lanius_app_math_add_one"));
    assert!(expanded.contains("pub fn __lanius_app_math_add_two"));
    assert!(
        expanded.contains("return __lanius_app_math_add_one(__lanius_app_math_add_one(value));")
    );
    assert!(expanded.contains("return __lanius_app_math_add_two(40);"));
    assert!(!expanded.contains("app::math::add_two"));
    parse_source(&expanded).expect("expanded private-helper module should parse");
}

#[test]
fn imported_module_rejects_external_private_member_access() {
    let dir = TempDir::new("module_private_reject");
    dir.write(
        "math.lani",
        r#"
module app::math;

fn add_one(value: i32) -> i32 {
    return value + 1;
}

pub fn add_two(value: i32) -> i32 {
    return add_one(add_one(value));
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "math.lani";

fn main() {
    return app::math::add_one(41);
}
"#,
    );

    let err = expand_source_imports_from_path(&main)
        .expect_err("private module member should not be externally visible");
    match err {
        CompileError::Import(message) => {
            assert!(
                message.contains("module member `app::math::add_one` is private"),
                "expected private module member error, got {message}"
            );
        }
        other => panic!("expected import error, got {other:?}"),
    }
}

#[test]
fn relative_imports_resolve_from_each_importing_file() {
    let dir = TempDir::new("relative");
    dir.write(
        "constants.lani",
        r#"
pub fn base_value() -> i32 {
    return 41;
}
"#,
    );
    dir.write(
        "helpers/math.lani",
        r#"
import "../constants.lani";

pub fn answer() -> i32 {
    return base_value() + 1;
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "helpers/math.lani";

fn main() {
    return answer();
}
"#,
    );

    let expanded = expand_source_imports_from_path(&main).expect("expand relative imports");
    assert!(expanded.contains("pub fn base_value"));
    assert!(expanded.contains("pub fn answer"));
    parse_source(&expanded).expect("expanded relative imports should parse");
}

#[test]
fn duplicate_canonical_import_expands_once() {
    let dir = TempDir::new("duplicate");
    dir.write(
        "helper.lani",
        r#"
pub fn imported_once() -> i32 {
    return 1;
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "helper.lani";
import "helper.lani";

fn main() {
    return imported_once();
}
"#,
    );

    let expanded = expand_source_imports_from_path(&main).expect("expand duplicate imports");
    assert_eq!(expanded.matches("pub fn imported_once").count(), 1);
    parse_source(&expanded).expect("expanded duplicate import should parse");
}

#[test]
fn path_and_module_import_of_core_file_expands_once() {
    let src = r#"
import "stdlib/core/i32.lani";
import core::i32;

fn main() {
    return core::i32::abs(-1);
}
"#;

    let expanded = expand_source_imports(src).expect("expand duplicate stdlib imports");
    assert_eq!(expanded.matches("pub fn __lanius_core_i32_abs").count(), 1);
    parse_source(&expanded).expect("expanded duplicate stdlib import should parse");
}

#[test]
fn module_style_array_seed_import_expands() {
    let src = r#"
import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    let copied: [i32; 4] = core::array_i32_4::copy(values);
    let reversed: [i32; 4] = core::array_i32_4::reversed(copied);
    let total: i32 = core::array_i32_4::sum(values);
    let first: i32 = core::array_i32_4::first(reversed);
    let found_at: i32 = core::array_i32_4::index_of_or(copied, first, -1);
    return total + found_at + core::array_i32_4::len();
}
"#;

    let expanded = expand_source_imports(src).expect("expand module-style array stdlib import");
    assert!(expanded.contains("pub fn __lanius_core_array_i32_4_len"));
    assert!(expanded.contains("pub fn __lanius_core_array_i32_4_first"));
    assert!(expanded.contains("pub fn __lanius_core_array_i32_4_copy"));
    assert!(expanded.contains("pub fn __lanius_core_array_i32_4_reversed"));
    assert!(expanded.contains("pub fn __lanius_core_array_i32_4_sum"));
    assert!(expanded.contains("pub fn __lanius_core_array_i32_4_index_of_or"));
    assert!(expanded.contains("let copied: [i32; 4] = __lanius_core_array_i32_4_copy(values);"));
    assert!(
        expanded.contains("let reversed: [i32; 4] = __lanius_core_array_i32_4_reversed(copied);")
    );
    assert!(expanded.contains("let total: i32 = __lanius_core_array_i32_4_sum(values);"));
    assert!(expanded.contains("let first: i32 = __lanius_core_array_i32_4_first(reversed);"));
    assert!(expanded.contains("__lanius_core_array_i32_4_index_of_or(copied, first, -1)"));
    assert!(expanded.contains("return total + found_at + __lanius_core_array_i32_4_len();"));
    assert!(!expanded.contains("core::array_i32_4::sum"));
    parse_source(&expanded).expect("expanded module-style array stdlib import should parse");
}

#[test]
fn module_style_const_generic_array_seed_import_expands() {
    let src = r#"
import core::array_i32;

fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    let first: i32 = core::array_i32::first(values);
    let third: i32 = core::array_i32::get_unchecked(values, 2);
    return first + third;
}
"#;

    let expanded = expand_source_imports(src).expect("expand const-generic array stdlib import");
    assert!(expanded.contains("pub fn __lanius_core_array_i32_first"));
    assert!(expanded.contains("pub fn __lanius_core_array_i32_get_unchecked"));
    assert!(expanded.contains("let first: i32 = __lanius_core_array_i32_first(values);"));
    assert!(
        expanded.contains("let third: i32 = __lanius_core_array_i32_get_unchecked(values, 2);")
    );
    assert!(!expanded.contains("core::array_i32::first"));
    parse_source(&expanded).expect("expanded const-generic array stdlib import should parse");
}

#[test]
fn module_style_sum_type_seed_imports_expand() {
    let src = r#"
import core::option;
import core::result;
import core::ordering;

fn main(value: core::option::Option<i32>, result: core::result::Result<i32, i32>, ordering: core::ordering::Ordering) {
    let some: core::option::Option<i32> = core::option::Some(1);
    let none: core::option::Option<i32> = core::option::None;
    let some_flag: bool = core::option::is_some(some);
    let ok_flag: bool = core::result::is_ok(result);
    let value_or_default: i32 = core::option::unwrap_or(none, 0);
    let result_or_default: i32 = core::result::unwrap_or(result, 0);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand module-style sum type imports");
    assert!(expanded.contains("pub enum __lanius_core_option_Option<T>"));
    assert!(expanded.contains("__lanius_core_option_Some(T)"));
    assert!(expanded.contains("__lanius_core_option_None"));
    assert!(expanded.contains("pub enum __lanius_core_result_Result<T, E>"));
    assert!(expanded.contains("__lanius_core_result_Ok(T)"));
    assert!(expanded.contains("__lanius_core_result_Err(E)"));
    assert!(expanded.contains("pub enum __lanius_core_ordering_Ordering"));
    assert!(expanded.contains("__lanius_core_ordering_Less"));
    assert!(expanded.contains("value: __lanius_core_option_Option<i32>"));
    assert!(expanded.contains("result: __lanius_core_result_Result<i32, i32>"));
    assert!(expanded.contains("ordering: __lanius_core_ordering_Ordering"));
    assert!(expanded.contains("__lanius_core_option_Some(1)"));
    assert!(
        expanded
            .contains("let none: __lanius_core_option_Option<i32> = __lanius_core_option_None;")
    );
    assert!(expanded.contains("pub fn __lanius_core_option_is_some"));
    assert!(expanded.contains("pub fn __lanius_core_option_unwrap_or"));
    assert!(expanded.contains("pub fn __lanius_core_result_is_ok"));
    assert!(expanded.contains("pub fn __lanius_core_result_unwrap_or"));
    assert!(expanded.contains("let some_flag: bool = __lanius_core_option_is_some(some);"));
    assert!(expanded.contains("let ok_flag: bool = __lanius_core_result_is_ok(result);"));
    assert!(
        expanded.contains("let value_or_default: i32 = __lanius_core_option_unwrap_or(none, 0);")
    );
    assert!(
        expanded
            .contains("let result_or_default: i32 = __lanius_core_result_unwrap_or(result, 0);")
    );
    parse_source(&expanded).expect("expanded module-style sum type imports should parse");
}

#[test]
fn module_style_range_seed_import_expands() {
    let src = r#"
import core::range;

fn main(
    exclusive: core::range::Range<i32>,
    inclusive: core::range::RangeInclusive<i32>,
    from: core::range::RangeFrom<i32>,
    to: core::range::RangeTo<i32>,
    full: core::range::RangeFull
) {
    let made: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = core::range::start_i32(made);
    let inside: bool = core::range::contains_i32(made, start);
    return;
}
"#;

    let expanded = expand_source_imports(src).expect("expand module-style range import");
    assert!(expanded.contains("pub struct __lanius_core_range_Range<T>"));
    assert!(expanded.contains("pub struct __lanius_core_range_RangeInclusive<T>"));
    assert!(expanded.contains("pub struct __lanius_core_range_RangeFrom<T>"));
    assert!(expanded.contains("pub struct __lanius_core_range_RangeTo<T>"));
    assert!(expanded.contains("pub struct __lanius_core_range_RangeFull"));
    assert!(expanded.contains("exclusive: __lanius_core_range_Range<i32>"));
    assert!(expanded.contains("inclusive: __lanius_core_range_RangeInclusive<i32>"));
    assert!(expanded.contains("from: __lanius_core_range_RangeFrom<i32>"));
    assert!(expanded.contains("to: __lanius_core_range_RangeTo<i32>"));
    assert!(expanded.contains("full: __lanius_core_range_RangeFull"));
    assert!(expanded.contains("pub fn __lanius_core_range_range_i32"));
    assert!(expanded.contains("pub fn __lanius_core_range_start_i32"));
    assert!(expanded.contains("pub fn __lanius_core_range_contains_i32"));
    assert!(expanded.contains("impl __lanius_core_range_Range<i32>"));
    assert!(expanded.contains("pub fn start(receiver: __lanius_core_range_Range<i32>) -> i32"));
    assert!(
        expanded.contains(
            "pub fn contains(receiver: __lanius_core_range_Range<i32>, value: i32) -> bool"
        )
    );
    assert!(expanded.contains(
        "let made: __lanius_core_range_Range<i32> = __lanius_core_range_range_i32(1, 4);"
    ));
    assert!(expanded.contains("let start: i32 = __lanius_core_range_start_i32(made);"));
    assert!(expanded.contains("let inside: bool = __lanius_core_range_contains_i32(made, start);"));
    parse_source(&expanded).expect("expanded module-style range import should parse");
}

#[test]
fn missing_module_import_reports_candidates() {
    let err = expand_source_imports("import core::not_a_module;\n")
        .expect_err("missing module import should fail");
    match err {
        CompileError::Import(message) => {
            assert!(
                message.contains("module import \"core::not_a_module\" not found"),
                "expected module lookup error, got {message}"
            );
            assert!(
                message.contains("stdlib/core/not_a_module.lani"),
                "expected canonical stdlib module candidate, got {message}"
            );
            assert!(
                message.contains("stdlib/not_a_module.lani"),
                "expected core compatibility candidate, got {message}"
            );
        }
        other => panic!("expected import error, got {other:?}"),
    }
}

#[test]
fn import_cycles_return_clear_error() {
    let dir = TempDir::new("cycle");
    let a = dir.write(
        "a.lani",
        r#"
import "b.lani";

pub fn a() -> i32 {
    return 1;
}
"#,
    );
    dir.write(
        "b.lani",
        r#"
import "a.lani";

pub fn b() -> i32 {
    return 2;
}
"#,
    );

    let err = expand_source_imports_from_path(&a).expect_err("cycle should fail import expansion");
    match err {
        CompileError::Import(message) => {
            assert!(
                message.contains("import cycle detected"),
                "expected cycle error, got {message}"
            );
            assert!(
                message.contains("a.lani"),
                "expected cycle path, got {message}"
            );
            assert!(
                message.contains("b.lani"),
                "expected cycle path, got {message}"
            );
        }
        other => panic!("expected import error, got {other:?}"),
    }
}
