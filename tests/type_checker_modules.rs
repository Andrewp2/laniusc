mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking:\n{src}"),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_accepts(src: &str) {
    common::type_check_source_with_timeout(src)
        .unwrap_or_else(|err| panic!("source should pass GPU type checking: {err:?}"));
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!(
            "source pack should fail GPU type checking:\n{}",
            sources.join("\n--- source split ---\n")
        ),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_accepts(sources: &[&str]) {
    common::type_check_source_pack_with_timeout(sources)
        .unwrap_or_else(|err| panic!("source pack should pass GPU type checking: {err:?}"));
}

fn assert_source_pack_case_accepts(sources: &'static [&'static str], app_source: &'static str) {
    let mut sources = sources.to_vec();
    if !app_source.is_empty() {
        sources.push(app_source);
    }
    assert_gpu_type_check_pack_accepts(&sources);
}

#[test]
fn type_checker_accepts_leading_module_metadata() {
    assert_gpu_type_check_accepts("module app::main;");
    assert_gpu_type_check_accepts("module app::main; fn main() { return 0; }");
}

#[test]
fn type_checker_source_pack_accepts_module_metadata_and_resolved_path_imports() {
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; pub fn one() -> i32 { return 1; } ",
        "module app::main; import core::math; fn main() { return one(); }",
    ]);
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; pub const VALUE: i32 = 1;",
        r#"
module app::main;

import core::math;
import core::math;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import core::math; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import \"stdlib/core/math.lani\"; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import app::main; fn main() { return 0; }",
    ]);
}

#[test]
fn type_checker_source_pack_resolves_public_type_aliases_on_gpu() {
    assert_gpu_type_check_pack_accepts(&[
        "module core::count; pub type Count = i32;",
        r#"
module app::main;

import core::count;

fn keep(value: Count) -> Count {
    return value;
}

fn main() {
    let imported: Count = keep(1);
    let qualified: core::count::Count = imported;
    return qualified;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_duplicate_declarations_in_same_module_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

fn duplicate() -> i32 { return 1; }
fn duplicate() -> i32 { return 2; }

fn main() { return duplicate(); }
"#]);

    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

type Duplicate = i32;
type Duplicate = bool;

fn main() { return 0; }
"#]);
}

#[test]
fn type_checker_enforces_stdlib_trait_where_obligations_from_source_pack() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/cmp.lani"),
        include_str!("../stdlib/core/hash.lani"),
        r#"
module app::main;

import core::cmp;
import core::hash;

fn keep_cmp<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn keep_hash<T>(value: T) -> T where T: core::hash::Hash<T> {
    return value;
}

fn keep_both<T>(value: T) -> T where T: core::cmp::Eq<T> + core::hash::Hash<T> {
    return value;
}

fn main() {
    let left: i32 = keep_cmp(7);
    let middle: i32 = keep_hash(left);
    let right: i32 = keep_both(middle);
    return right;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/cmp.lani"),
        include_str!("../stdlib/core/hash.lani"),
        r#"
module app::main;

import core::cmp;
import core::hash;

fn keep_both<T>(value: T) -> T where T: core::cmp::Eq<T> + core::hash::Hash<T> {
    return value;
}

fn main() {
    let value: bool = keep_both(true);
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_stdlib_module_calls() {
    let cases = [
        (
            &[include_str!("../stdlib/core/bool.lani")][..],
            r#"
module app::main;

import core::bool;

fn main() {
    let inverted: bool = core::bool::not(false);
    let both: bool = core::bool::and(inverted, true);
    let either: bool = core::bool::or(false, both);
    let changed: bool = core::bool::xor(either, false);
    let same: bool = core::bool::eq(changed, true);
    let numeric: bool = core::bool::from_i32(1);
    if (same && numeric) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/i32.lani")][..],
            r#"
module app::main;

import core::i32;

fn main() {
    let magnitude: i32 = core::i32::saturating_abs(-7);
    let lower: i32 = core::i32::min(magnitude, core::i32::MAX);
    let signed: i32 = core::i32::signum(-3);
    let powered: bool = core::i32::is_power_of_two(8);
    if (powered && signed == -1 && lower == 7) {
        return core::i32::clamp(lower, 0, 7);
    }
    return 1;
}
"#,
        ),
        (
            &[
                include_str!("../stdlib/core/char.lani"),
                include_str!("../stdlib/core/u32.lani"),
            ][..],
            r#"
module app::main;

import core::char;
import core::u32;

fn main() {
    let digit: bool = core::char::is_ascii_digit('7');
    let alpha: bool = core::char::is_ascii_alphabetic('Q');
    let clamped: u32 = core::u32::clamp(9, core::u32::MIN, 7);
    let wrapped: u32 = core::u32::wrapping_add(core::u32::MAX, 1);
    if (digit && alpha && clamped == 7 && wrapped == 0) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            &[
                include_str!("../stdlib/core/u8.lani"),
                include_str!("../stdlib/core/i64.lani"),
            ][..],
            r#"
module app::main;

import core::u8;
import core::i64;

fn main() {
    let ascii: bool = core::u8::is_ascii_digit(57);
    let low: u8 = core::u8::min(9, 4);
    let magnitude: i64 = core::i64::abs(-7);
    let bounded: i64 = core::i64::clamp(magnitude, 0, 5);
    if (ascii && low == 4 && bounded == 5) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/f32.lani")][..],
            r#"
module app::main;

import core::f32;

fn choose(value: f32) -> f32 {
    let magnitude: f32 = core::f32::abs(value);
    let low: f32 = core::f32::min(magnitude, core::f32::ONE);
    let bounded: f32 = core::f32::clamp(low, core::f32::ZERO, 1.0);
    if (bounded > 0.5) {
        return bounded;
    }
    return core::f32::max(bounded, 0.5);
}

fn main() {
    let value: f32 = choose(-2.0);
    if (value > 0.5) {
        return 0;
    }
    return 1;
}
"#,
        ),
    ];

    for (sources, app_source) in cases {
        assert_source_pack_case_accepts(sources, app_source);
    }
}

#[test]
fn type_checker_accepts_core_range_module_calls() {
    let cases = [
        (
            &[include_str!("../stdlib/core/range.lani")][..],
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = core::range::start_i32(range);
    let end: i32 = core::range::end_i32(range);
    if (core::range::contains_i32(range, 2)) {
        return start;
    }
    return end;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/range.lani")][..],
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = range.start();
    let end: i32 = range.end();
    let direct_start: i32 = core::range::range_i32(1, 4).start();
    let direct_contains: bool = core::range::range_i32(1, 4).contains(2);
    if (range.contains(2) && direct_contains) {
        return start + direct_start;
    }
    return end;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/range.lani")][..],
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::RangeInclusive<i32> = core::range::range_inclusive_i32(1, 4);
    let start: i32 = range.start();
    let end: i32 = range.end();
    let empty: bool = range.is_empty();
    let direct_end: i32 = core::range::range_inclusive_i32(1, 4).end();
    let direct_contains: bool = core::range::range_inclusive_i32(1, 4).contains(4);
    let direct_empty: bool = core::range::range_inclusive_i32(5, 4).is_empty();
    if (range.contains(4) && !empty && !direct_empty) {
        return direct_end;
    }
    return start + end;
}
"#,
        ),
    ];

    for (sources, app_source) in cases {
        assert_source_pack_case_accepts(sources, app_source);
    }
}

#[test]
fn type_checker_rejects_private_cross_module_method_call() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::private_methods;

pub struct Thing {
    value: i32,
}

pub fn make(value: i32) -> Thing {
    return Thing { value: value };
}

impl Thing {
    fn hidden(self) -> i32 {
        return self.value;
    }
}
"#,
        r#"
module app::main;

import core::private_methods;

fn main() {
    let thing: core::private_methods::Thing = core::private_methods::make(1);
    return thing.hidden();
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_duplicate_inherent_methods_in_same_module_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

struct Thing {
    value: i32,
}

impl Thing {
    fn read(self) -> i32 {
        return self.value;
    }

    fn read(self) -> i32 {
        return 0;
    }
}

fn main() {
    let thing: Thing = Thing { value: 1 };
    return thing.read();
}
"#]);
}

#[test]
fn type_checker_accepts_core_ordering_module_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/ordering.lani"),
        r#"
module app::main;

import core::ordering;

fn main() {
    let ordering: core::ordering::Ordering = core::ordering::compare_i32(1, 2);
    let less: core::ordering::Ordering = core::ordering::Less;
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_generic_option_and_result_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/option.lani"),
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::option;
import core::result;

fn option_value() -> i32 {
    let value: core::option::Option<i32> = core::option::Some(1);
    let fallback: i32 = 2;
    let is_some: bool = core::option::is_some(value);
    if (is_some) {
        return core::option::unwrap_or(value, fallback);
    }
    return fallback;
}

fn result_value() -> i32 {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    let is_ok: bool = core::result::is_ok(value);
    if (is_ok) {
        return core::result::unwrap_or(value, 3);
    }
    return 3;
}

fn main() {
    let left: i32 = option_value();
    let right: i32 = result_value();
    return left + right;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_generic_enum_instance_returns() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let none: core::option::Option<i32> = core::option::None;
    let replaced: core::option::Option<i32> = core::option::replace(none, 11);
    return core::option::unwrap_or(replaced, 0);
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_qualified_generic_option_and_result_call_mismatches() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::Some(1);
    return core::option::unwrap_or(value, true);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::result;

fn main() {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    return core::result::unwrap_or(value, false);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::None;
    let wrong: core::option::Option<bool> = core::option::replace(value, 11);
    return 0;
}
"#,
    ]);
}

#[test]
fn accepts_bounded_generic_callees_rejects_conflicts() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::keep(1);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::id;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    let flag: bool = core::id::keep(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::choose(1, 2);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::id;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::choose(1, true);
}
"#,
    ]);
}

#[test]
fn rejects_non_constructor_symbolic_enum_returns() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn wrong<T>(value: T) -> core::option::Option<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_same_module_qualified_type_paths() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

enum Choice {
    Yes,
    No,
}

fn take(point: app::main::Point, choice: app::main::Choice) {
    return;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn x_of(point: app::main::Point) -> i32 {
    return point.x;
}

fn copy(point: app::main::Point) -> app::main::Point {
    return point;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn copy(point: app::main::Point) -> app::main::Point {
    let local: app::main::Point = point;
    return local;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn copy(point: app::main::Point) -> app::main::Point {
    let local: app::other::Point = point;
    return local;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
fn take(value: core::option::Option<i32>) {
    return;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_resolves_qualified_function_calls() {
    assert_gpu_type_check_accepts(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let value: i32 = app::helper();
    return value;
}
"#,
    );
    assert_gpu_type_check_accepts(
        r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::main::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let flag: bool = app::helper();
    return 0;
}
"#,
    );
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::math;

pub fn one() -> i32 {
    return 1;
}
"#,
        r#"
module app::main;

fn main() {
    return core::math::one();
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() {
    let code: i32 = std::io::flush_stdout();
    std::io::print_i32(code);
    return code;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;

import alloc::allocator;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    alloc::allocator::dealloc(ptr, 16, 4);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_rejects(
        r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::other::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return other::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn main() {
    return app::missing();
}
"#,
    );
}

#[test]
fn type_checker_accepts_stdlib_host_module_calls() {
    let cases = [
        (
            &[
                include_str!("../stdlib/std/env.lani"),
                include_str!("../stdlib/std/fs.lani"),
                include_str!("../stdlib/std/net.lani"),
                include_str!("../stdlib/std/process.lani"),
                include_str!("../stdlib/std/time.lani"),
            ][..],
            r#"
module app::main;

import std::env;
import std::fs;
import std::net;
import std::process;
import std::time;

fn main() {
    let args: i32 = std::process::argc();
    let first_arg_len: i32 = std::process::arg_len(0);
    let vars: i32 = std::env::var_count();
    let first_var_len: i32 = std::env::var_key_len(0);
    let file: i32 = std::fs::open_read(0, 0);
    let bytes: i32 = std::fs::read(file, 0, 0);
    let now: i64 = std::time::monotonic_now_ns();
    let slept: i32 = std::time::sleep_ms(0);
    let tcp: i32 = std::net::tcp_connect(0, 0, 80);
    let udp: i32 = std::net::udp_bind(0, 0, 53);
    std::process::set_exit_code(0);
    return args + first_arg_len + vars + first_var_len + file + bytes + slept + tcp + udp;
}
"#,
        ),
        (
            &[
                include_str!("../stdlib/alloc/allocator.lani"),
                include_str!("../stdlib/std/io.lani"),
            ][..],
            r#"
module app::main;

import alloc::allocator;
import std::io;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    let grown: u32 = alloc::allocator::realloc(ptr, 16, 32, 4);
    let stdin_count: i32 = std::io::read_stdin(grown, 32);
    let stdout_count: i32 = std::io::write_stdout(grown, 32);
    let stderr_count: i32 = std::io::write_stderr(grown, 32);
    let flushed: i32 = std::io::flush_stderr();
    std::io::print_i32(stdin_count + stdout_count + stderr_count + flushed);
    alloc::allocator::dealloc(grown, 32, 4);
    alloc::allocator::alloc_failed(64, 8);
    return std::io::flush_stdout();
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/target.lani")][..],
            r#"
module app::main;

import core::target;

fn main() {
    let native: bool = core::target::is_native();
    let has_stdio: bool = core::target::HAS_STDIO;
    let threaded: bool = core::target::has_threads();
    if (native && has_stdio && !threaded) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/panic.lani")][..],
            r#"
module app::main;

import core::panic;

fn main() {
    core::panic::unreachable();
    return 0;
}
"#,
        ),
        (
            &[include_str!("../stdlib/test/assert.lani")][..],
            r#"
module app::main;

import test::assert;

fn main() {
    let value: i32 = 7;
    test::assert::eq_i32(value, 7);
    test::assert::is_true(value == 7);
    return value;
}
"#,
        ),
    ];

    for (sources, app_source) in cases {
        assert_source_pack_case_accepts(sources, app_source);
    }
}

#[test]
fn type_checker_accepts_direct_host_abi_extern_calls() {
    let cases = [
        (
            "lanius_std",
            r#"
extern "lanius_std" fn argc() -> i32;
extern "lanius_std" fn var_count() -> i32;
extern "lanius_std" fn open_read(path_ptr: u32, path_len: usize) -> i32;
extern "lanius_std" fn monotonic_now_ns() -> i64;
extern "lanius_std" fn tcp_connect(addr_ptr: u32, addr_len: usize, port: i32) -> i32;
extern "lanius_std" fn print_i32(value: i32);

fn main() {
    let args: i32 = argc();
    let vars: i32 = var_count();
    let file: i32 = open_read(0, 0);
    let sock: i32 = tcp_connect(0, 0, 80);
    let now: i64 = monotonic_now_ns();
    print_i32(args + vars + file + sock);
    return 0;
}
"#,
        ),
        (
            "lanius_alloc",
            r#"
extern "lanius_alloc" fn alloc(size: usize, align: usize) -> u32;
extern "lanius_alloc" fn realloc(ptr: u32, old_size: usize, new_size: usize, align: usize) -> u32;
extern "lanius_alloc" fn dealloc(ptr: u32, size: usize, align: usize);
extern "lanius_alloc" fn alloc_failed(size: usize, align: usize);

fn main() {
    let ptr: u32 = alloc(16, 4);
    let grown: u32 = realloc(ptr, 16, 32, 4);
    dealloc(grown, 32, 4);
    alloc_failed(64, 8);
    return 0;
}
"#,
        ),
    ];

    for (label, source) in cases {
        common::type_check_source_with_timeout(source).unwrap_or_else(|err| {
            panic!("{label} extern declarations should pass GPU type checking: {err:?}")
        });
    }
}

#[test]
fn type_checker_resolves_qualified_trait_bounds() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}

pub impl Eq<i32> for i32 {
    pub fn check(value: i32) -> bool {
        return value > 0;
    }
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::missing::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub struct Eq<T> {
    value: T,
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_qualified_constants() {
    assert_gpu_type_check_accepts(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    let value: i32 = app::LIMIT;
    return value;
}
"#,
    );
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::i32;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

import core::i32;

fn main() {
    let value: i32 = core::i32::MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

fn main() {
    let value: i32 = MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_rejects(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    let flag: bool = app::LIMIT;
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    return app::MISSING;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let value: i32 = app::helper;
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_private_cross_module_constants() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

const SECRET: i32 = 7;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = core::limits::SECRET;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

const SECRET: i32 = 7;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = SECRET;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_same_module_private_qualified_values() {
    assert_gpu_type_check_accepts(
        r#"
module app;

const SECRET: i32 = 7;

fn helper() -> i32 {
    return app::SECRET;
}

fn main() {
    return app::helper();
}
"#,
    );
}

#[test]
fn type_checker_rejects_private_cross_module_qualified_paths() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

fn hidden() -> i32 {
    return 7;
}
"#,
        r#"
module app::main;

fn main() {
    return core::secret::hidden();
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

struct Hidden {
    value: i32,
}
"#,
        r#"
module app::main;

fn accept(value: core::secret::Hidden) -> i32 {
    return 0;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_ambiguous_imported_names() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub const VALUE: i32 = 1;
"#,
        r#"
module core::right;

pub const VALUE: i32 = 2;
"#,
        r#"
module app::main;

import core::left;
import core::right;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub struct Item {
    value: i32,
}
"#,
        r#"
module core::right;

pub struct Item {
    value: i32,
}
"#,
        r#"
module app::main;

import core::left;
import core::right;

fn accept(value: Item) -> i32 {
    return 0;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_qualified_unit_enum_variants() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::ordering;

pub enum Ordering {
    Less,
    Equal,
    Greater,
}
"#,
        r#"
module app::main;

import core::ordering;

fn accept(value: core::ordering::Ordering) -> i32 {
    return 0;
}

fn main() {
    let value: core::ordering::Ordering = core::ordering::Less;
    return accept(value);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::ordering;

pub enum Ordering {
    Less,
    Equal,
    Greater,
}
"#,
        r#"
module app::main;

import core::ordering;

fn main() {
    let value: bool = core::ordering::Less;
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum MaybeI32 {
    Some(i32),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::MaybeI32 = core::maybe::Some;
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_generic_enum_constructors() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn accept(value: core::maybe::Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some(1);
    return accept(value);
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn accept(value: core::maybe::Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: core::maybe::Maybe<i32> = Some(1);
    return accept(value);
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}

fn accept(value: Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: Maybe<i32> = Some(1);
    return accept(value);
}
"#]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some(true);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some();
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::None(1);
    return 0;
}
"#,
    ]);
}
