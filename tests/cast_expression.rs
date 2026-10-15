mod common;

use laniusc_compiler::compiler::{CompileError, compile_source_to_x86_64_with_gpu_codegen};

// `expr as T` converts between scalar numeric types, from bool or char to an
// integer, and from u8 to char, with Rust semantics. Cast targets are type
// names, optionally qualified; applications, arrays and references are parse
// errors.

fn expect_type_checks(context: &str, source: &str) {
    if let Err(err) = common::type_check_source_with_timeout(source) {
        panic!("{context}: expected the cast to type-check: {}", err.to_public_diagnostic().render());
    }
}

fn expect_invalid_cast(context: &str, source: &str) {
    let err = common::type_check_source_with_timeout(source)
        .err()
        .unwrap_or_else(|| panic!("{context}: expected an invalid cast"));
    let diagnostic = err.to_public_diagnostic();
    assert_eq!(
        diagnostic.code,
        "LNC0072",
        "{context}: expected the invalid cast diagnostic: {}",
        diagnostic.render()
    );
}

fn expect_parse_error(context: &str, source: &str) {
    let err = common::type_check_source_with_timeout(source)
        .err()
        .unwrap_or_else(|| panic!("{context}: expected a parse error"));
    let diagnostic = err.to_public_diagnostic();
    assert_ne!(
        diagnostic.code,
        "LNC0072",
        "{context}: an unsupported target shape is a parse error: {}",
        diagnostic.render()
    );
    assert!(
        !matches!(err, CompileError::GpuTypeCheck(_)),
        "{context}: an unsupported target shape is a parse error: {}",
        diagnostic.render()
    );
}

#[test]
fn casts_type_check_between_scalar_numeric_types_and_from_bool() {
    expect_type_checks(
        "scalar casts",
        r#"
fn takes_u32(value: u32) -> u32 {
    return value;
}

fn main() -> i32 {
    let minus_one: i32 = -1;
    let a: u32 = minus_one as u32;
    let b: u8 = 300 as u8;
    let c: i64 = minus_one as i64;
    let d: usize = a as usize;
    let e: f32 = minus_one as f32;
    let f: f64 = e as f64;
    let g: i16 = f as i16;
    let h: u64 = true as u64;
    let i: i32 = (3 < 4) as i32;
    let chained: i32 = 300 as u8 as i32;
    let unannotated = minus_one as u16;
    let widened: u32 = unannotated as u32;
    let argument: u32 = takes_u32(minus_one as u32);
    let negated: u32 = -minus_one as u32;
    let product: i32 = minus_one * 2 as i32;
    let compared: bool = a as i32 < minus_one;
    return chained + i + (b as i32) + (g as i32) + (h as i32) + (c as i32) +
        (d as i32) + (widened as i32) + (argument as i32) + (negated as i32) +
        product + (compared as i32);
}
"#,
    );
}

#[test]
fn casts_type_check_from_char_to_integers_and_from_u8_to_char() {
    expect_type_checks(
        "char casts",
        r#"
fn main() -> i32 {
    let letter: char = 'A';
    let code: u32 = letter as u32;
    let low: u8 = 'Ω' as u8;
    let wide: i64 = letter as i64;
    let byte: u8 = 66;
    let from_byte: char = byte as char;
    let round_trip: u32 = byte as char as u32;
    return (code as i32) + (low as i32) + (wide as i32) + (round_trip as i32) +
        (from_byte as i32);
}
"#,
    );
}

#[test]
fn casts_accept_alias_targets() {
    expect_type_checks(
        "alias target",
        r#"
type Length = u32;

fn main() -> i32 {
    let value: i32 = 7;
    let length: Length = value as Length;
    return length as i32;
}
"#,
    );
}

#[test]
fn casts_accept_qualified_alias_targets() {
    common::type_check_source_pack_with_timeout(&[
        r#"
module lib::sizes;

pub type Length = u32;
"#,
        r#"
module app::main;

import lib::sizes;

fn main() -> i32 {
    let value: i32 = 7;
    let length: u32 = value as lib::sizes::Length;
    return length as i32;
}
"#,
    ])
    .unwrap_or_else(|err| {
        panic!(
            "qualified cast target should type-check: {}",
            err.to_public_diagnostic().render()
        )
    });
}

#[test]
fn casts_reject_bool_targets_char_misuse_and_non_numeric_operands() {
    expect_invalid_cast(
        "integer to bool",
        r#"
fn main() -> i32 {
    let value: i32 = 7;
    let flag: bool = value as bool;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "float to bool",
        r#"
fn main() -> i32 {
    let value: f32 = 1.5;
    let flag: bool = value as bool;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "bool to float",
        r#"
fn main() -> i32 {
    let value: f32 = true as f32;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "struct to integer",
        r#"
struct Pair { left: i32, right: i32 }

fn main() -> i32 {
    let pair: Pair = Pair { left: 1, right: 2 };
    return pair as i32;
}
"#,
    );
    expect_invalid_cast(
        "i32 to char",
        r#"
fn main() -> i32 {
    let value: i32 = 65;
    let letter: char = value as char;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "unsuffixed integer literal to char",
        r#"
fn main() -> i32 {
    let letter: char = 97 as char;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "char to float",
        r#"
fn main() -> i32 {
    let value: f32 = 'A' as f32;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "char to bool",
        r#"
fn main() -> i32 {
    let flag: bool = 'A' as bool;
    return 0;
}
"#,
    );
    expect_invalid_cast(
        "integer to struct",
        r#"
struct Pair { left: i32, right: i32 }

fn main() -> i32 {
    let value: i32 = 1;
    let pair: Pair = value as Pair;
    return 0;
}
"#,
    );
}

#[test]
fn cast_targets_reject_applications_arrays_and_references() {
    expect_parse_error(
        "generic target",
        r#"
fn main() -> i32 {
    let value: i32 = 1;
    let other = value as Option<i32>;
    return 0;
}
"#,
    );
    expect_parse_error(
        "array target",
        r#"
fn main() -> i32 {
    let value: i32 = 1;
    let other = value as [i32; 1];
    return 0;
}
"#,
    );
    expect_parse_error(
        "reference target",
        r#"
fn main() -> i32 {
    let value: i32 = 1;
    let other = value as &i32;
    return 0;
}
"#,
    );
    expect_parse_error(
        "missing target",
        r#"
fn main() -> i32 {
    let value: i32 = 1;
    let other = value as;
    return 0;
}
"#,
    );
}

fn compile_source(context: &str, source: &str) -> Vec<u8> {
    let source = source.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .unwrap_or_else(|err| {
        panic!(
            "{context} should compile to x86_64: {}",
            err.to_public_diagnostic().render()
        )
    })
}

// Each program returns the number of its first failing check, or zero.
fn assert_source_exit(name: &str, source: &str, expected: i32) {
    let context = format!("x86 cast {name}");
    let bytes = compile_source(&context, source);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(&context, &format!("x86_cast_{name}"), &bytes);
        assert_eq!(
            output.status.code(),
            Some(expected),
            "{context}: stdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, expected);
}

#[test]
fn x86_integer_casts_truncate_and_extend_by_source_signedness() {
    assert_source_exit(
        "integer_widths",
        r#"
fn widen_i8(value: i8) -> i64 {
    return value as i64;
}

fn widen_u8(value: u8) -> u64 {
    return value as u64;
}

fn takes_u32(value: u32) -> u32 {
    return value;
}

fn main() -> i32 {
    let minus_one: i32 = -1;
    let as_u32: u32 = minus_one as u32;
    if (as_u32 != 4294967295) { return 1; }
    let three_hundred: i32 = 300;
    let truncated: u8 = three_hundred as u8;
    if (truncated != 44) { return 2; }
    let small: i8 = -1;
    let sign_extended: i32 = small as i32;
    if (sign_extended != -1) { return 3; }
    let byte: u8 = 255;
    let reinterpreted: i8 = byte as i8;
    if (reinterpreted != -1) { return 4; }
    let zero_extended: i32 = byte as i32;
    if (zero_extended != 255) { return 5; }
    let all_ones: u32 = 4294967295;
    let wrapped: i32 = all_ones as i32;
    if (wrapped != -1) { return 6; }
    let wide_signed: i64 = minus_one as i64;
    if (wide_signed != -1) { return 7; }
    let wide_unsigned: i64 = all_ones as i64;
    if (wide_unsigned != 4294967295) { return 8; }
    let long: i64 = 4294967596;
    let low: i32 = long as i32;
    if (low != 300) { return 9; }
    let low_byte: u8 = long as u8;
    if (low_byte != 44) { return 10; }
    let forty_thousand: i32 = 40000;
    let as_i16: i16 = forty_thousand as i16;
    if (as_i16 != -25536) { return 11; }
    let as_u16: u16 = forty_thousand as u16;
    if (as_u16 != 40000) { return 12; }
    let yes: bool = true;
    let one: i32 = yes as i32;
    if (one != 1) { return 13; }
    let no: u8 = (3 < 2) as u8;
    if (no != 0) { return 14; }
    let chained: i32 = three_hundred as u8 as i32;
    if (chained != 44) { return 15; }
    if (widen_i8(small) != -1) { return 16; }
    if (widen_u8(byte) != 255) { return 17; }
    let negated: u32 = -minus_one as u32;
    if (negated != 1) { return 18; }
    let product: i32 = three_hundred * 2 as u8 as i32;
    if (product != 600) { return 19; }
    let inferred = three_hundred as u8;
    if (inferred != 44) { return 20; }
    if (takes_u32(minus_one as u32) != 4294967295) { return 21; }
    let max_u64: u64 = wide_signed as u64;
    let back: i64 = max_u64 as i64;
    if (back != -1) { return 22; }
    let size: usize = byte as usize;
    if (size != 255) { return 23; }
    let negative_size: isize = small as isize;
    if (negative_size != -1) { return 24; }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_float_casts_truncate_saturate_and_map_nan_to_zero() {
    assert_source_exit(
        "floats",
        r#"
fn main() -> i32 {
    let positive: f32 = 3.9;
    let truncated: i32 = positive as i32;
    if (truncated != 3) { return 1; }
    let negative: f32 = -3.9;
    let toward_zero: i32 = negative as i32;
    if (toward_zero != -3) { return 2; }
    let thousand: f32 = 1000.0;
    let saturated: u8 = thousand as u8;
    if (saturated != 255) { return 3; }
    let clamped: u8 = negative as u8;
    if (clamped != 0) { return 4; }
    let low: i8 = (0.0 - thousand) as i8;
    if (low != -128) { return 5; }
    let seven: i32 = 7;
    let seven_f32: f32 = seven as f32;
    if (seven_f32 != 7.0) { return 6; }
    let seven_f64: f64 = seven_f32 as f64;
    let seven_i64: i64 = seven_f64 as i64;
    if (seven_i64 != 7) { return 7; }
    let zero: f32 = 0.0;
    let nan: f32 = zero / zero;
    let nan_int: i32 = nan as i32;
    if (nan_int != 0) { return 8; }
    let infinity: f32 = 1.0 / zero;
    let max_i32: i32 = infinity as i32;
    if (max_i32 != 2147483647) { return 9; }
    let min_i32: i32 = (0.0 - infinity) as i32;
    if (min_i32 != 0 - 2147483647 - 1) { return 10; }
    let max_i64: i64 = infinity as i64;
    if (max_i64 != 9223372036854775807) { return 11; }
    let all_ones: u32 = 4294967295;
    let round_trip: u32 = all_ones as f64 as u32;
    if (round_trip != all_ones) { return 12; }
    let minus_one: i64 = -1;
    let max_u64: u64 = minus_one as u64;
    let saturated_u64: u64 = max_u64 as f64 as u64;
    if (saturated_u64 != max_u64) { return 13; }
    let infinite_u64: u64 = infinity as u64;
    if (infinite_u64 != max_u64) { return 14; }
    let half: u64 = 9223372036854775808;
    let half_f64: f64 = half as f64;
    let half_back: u64 = half_f64 as u64;
    if (half_back != half) { return 15; }
    let five: u64 = 5;
    let five_f32: f32 = five as f32;
    if (five_f32 != 5.0) { return 16; }
    let narrowed: f32 = seven_f64 as f32;
    if (narrowed != 7.0) { return 17; }
    let byte: u8 = 200;
    let byte_f32: f32 = byte as f32;
    if (byte_f32 != 200.0) { return 18; }
    let small: i8 = -100;
    let small_f64: f64 = small as f64;
    if ((small_f64 as i32) != -100) { return 19; }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_char_casts_use_the_code_point() {
    assert_source_exit(
        "chars",
        r#"
fn main() -> i32 {
    let letter: char = 'A';
    let code: u32 = letter as u32;
    if (code != 65) { return 1; }
    let omega: char = 'Ω';
    if ((omega as u32) != 937) { return 2; }
    let low: u8 = omega as u8;
    if (low != 169) { return 3; }
    let emoji: char = '😀';
    if ((emoji as i64) != 128512) { return 4; }
    let half: u16 = emoji as u16;
    if (half != 62976) { return 5; }
    let signed_half: i16 = emoji as i16;
    if (signed_half != -2560) { return 6; }
    let byte: u8 = 66;
    let from_byte: char = byte as char;
    if (from_byte != 'B') { return 7; }
    let top: u8 = 255;
    if ((top as char as u32) != 255) { return 8; }
    return 0;
}
"#,
        0,
    );
}
