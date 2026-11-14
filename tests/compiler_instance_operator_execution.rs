//! Operators inside generic bodies that one job instantiates at several types.
//!
//! Each instance's operator rows take their types from its own environment,
//! so `add<f64>` adds floats while `add<i32>` adds integers in the same
//! program. Operand rules (arithmetic, negation, conditions, logical
//! operands, string equality, indexing) apply to each instance's types and
//! report LNC0006 at the generic body's operand, as a single-instance program
//! does. An unsuffixed literal whose context is a type parameter takes each
//! instance's scalar, with that scalar's range and float rounding. Each
//! fixture calls its instances in both orders, so no instance's types can
//! stand in for another's.

use crate::common;

use laniusc_compiler::compiler::{CompileError, compile_source_to_x86_64_with_gpu_codegen};

fn compile(context: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let owned = source.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&owned))
    })
}

fn assert_exit(context: &str, artifact: &str, source: &str, expected: i32) {
    let bytes = compile(context, source)
        .unwrap_or_else(|error| panic!("{context}: valid generic program rejected: {error:?}"));
    let output = common::run_x86_64_elf_output(context, artifact, &bytes);
    assert_eq!(output.status.code(), Some(expected), "{context}: {output:?}");
}

/// Rejects with LNC0006 whose primary label covers the first occurrence of
/// `anchor`'s first `length` bytes.
fn assert_operand_rejected(context: &str, source: &str, anchor: &str, length: usize) {
    assert_rejected(context, "LNC0006", source, anchor, length);
}

/// Rejects with `code` whose primary label covers the first occurrence of
/// `anchor`'s first `length` bytes.
fn assert_rejected(context: &str, code: &str, source: &str, anchor: &str, length: usize) {
    let error = compile(context, source).expect_err("invalid program must not produce an executable");
    let CompileError::Diagnostic(diagnostic) = error else {
        panic!("{context}: expected {code}, got {error:?}");
    };
    assert_eq!(diagnostic.code, code, "{context}: {}", diagnostic.render());
    let start = source.find(anchor).expect("fixture anchor");
    let end = start + length;
    let primary = diagnostic.primary_label.as_ref().expect("source label");
    let label_start = primary.byte_start.expect("label byte start");
    let label_end = primary.byte_end.expect("label byte end");
    assert!(
        label_start < end && label_end > start,
        "{context}: the label must cover {anchor:?} at {start}..{end}: {}",
        diagnostic.render()
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn generic_arithmetic_uses_each_instance_type() {
    assert_exit(
        "add at f64 and i32",
        "instance_operator_add_numeric",
        "fn add<T>(a:T,b:T)->T { return a+b; } fn main()->i32 { if (add<f64>(1.25,2.25)!=3.5) { return 1; } return add<i32>(40,2); }",
        42,
    );
    assert_exit(
        "arithmetic at float and integer widths",
        "instance_operator_widths",
        "fn add<T>(a:T,b:T)->T { return a+b; } \
         fn scale<T>(a:T,b:T)->T { return (a-b)*b/b; } \
         fn neg<T>(a:T)->T { return -a; } \
         fn main()->i32 { \
           if (add<f32>(1.5,2.0)!=3.5) { return 1; } \
           if (add<f64>(0.5,0.25)!=0.75) { return 2; } \
           if (add<i64>(4000000000,2)!=4000000002) { return 3; } \
           if (add<u8>(200,50)!=250) { return 4; } \
           if (scale<f32>(7.5,2.5)!=5.0) { return 5; } \
           if (scale<i32>(9,3)!=6) { return 6; } \
           if (neg<f64>(2.5)!=-2.5) { return 7; } \
           if (neg<i16>(7)!=-7) { return 8; } \
           return add<i32>(40,2); }",
        42,
    );
    assert_exit(
        "comparisons and conditions at bool, integer and float",
        "instance_operator_valid_mixed",
        "fn same<T>(a:T,b:T)->bool { return a==b; } \
         fn pick<T>(c:bool,a:T,b:T)->T { if (c && a==a) { return a; } return b; } \
         fn main()->i32 { \
           if (!same<bool>(true,true) || same<i32>(1,2) || !same<f64>(0.5,0.5)) { return 1; } \
           if (pick<f32>(true,1.5,2.5)!=1.5) { return 2; } \
           return pick<i32>(false,1,42); }",
        42,
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn generic_operand_rules_apply_to_each_instance() {
    assert_operand_rejected(
        "bool addition beside an integer instance",
        "fn add<T>(a:T,b:T)->T { return a+b; } fn main()->i32 { let x:i32=add<i32>(40,2); if (add<bool>(false,true)) { return x; } return 1; }",
        "a+b",
        1,
    );
    assert_operand_rejected(
        "integer condition beside a bool instance",
        "fn pick<T>(c:T)->i32 { if (c) { return 1; } return 0; } fn main()->i32 { return pick<bool>(true)+pick<i32>(1); }",
        "c) {",
        1,
    );
    assert_operand_rejected(
        "integer loop condition beside a bool instance",
        "fn spin<T>(c:T)->i32 { while (c) { return 1; } return 0; } fn main()->i32 { return spin<bool>(false)+spin<i32>(0); }",
        "c) {",
        1,
    );
    assert_operand_rejected(
        "logical not of an integer beside a bool instance",
        "fn neg<T>(c:T)->bool { return !c; } fn main()->i32 { if (!neg<bool>(false)) { return 1; } if (neg<i32>(0)) { return 42; } return 2; }",
        "c; }",
        1,
    );
    assert_operand_rejected(
        "string equality beside an integer instance",
        "fn same<T>(a:T,b:T)->bool { return a==b; } fn main()->i32 { if (!same<i32>(1,1)) { return 1; } if (same<str>(\"yes\",\"yes\")) { return 42; } return 2; }",
        "a==b",
        1,
    );
    assert_operand_rejected(
        "indexing an integer beside an array instance",
        "fn first<T>(a:T)->i32 { return a[0]; } fn main()->i32 { let a:[i32;1]=[42]; return first<[i32;1]>(a)+first<i32>(42); }",
        "a[0]",
        4,
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn generic_literals_take_each_instance_scalar() {
    // The program that rejected at the literal when its row kept i32.
    assert_exit(
        "integer literal at i64, u8 and i32",
        "instance_literal_integer_widths",
        "fn bump<T>(a:T)->T { return a+1; } fn main()->i32 { if (bump<i64>(4000000000)!=4000000001) { return 1; } if (bump<u8>(200)!=201) { return 2; } return bump<i32>(41); }",
        42,
    );
    assert_exit(
        "integer literal, instances called in the other order",
        "instance_literal_integer_widths_reversed",
        "fn bump<T>(a:T)->T { return a+1; } fn main()->i32 { if (bump<u8>(200)!=201) { return 2; } let r:i32 = bump<i32>(41); if (bump<i64>(4000000000)!=4000000001) { return 1; } return r; }",
        42,
    );
    // 0.1 rounds differently in f32 and f64: each copy lowers its own width.
    assert_exit(
        "float literal at f64 and f32",
        "instance_literal_float_widths",
        "fn bump<T>(a:T)->T { return a + 0.1; } fn main()->i32 { if (bump<f32>(0.2) != 0.3) { return 1; } if (bump<f64>(0.2) != 0.30000000000000004) { return 2; } return 42; }",
        42,
    );
    assert_exit(
        "float literal, instances called in the other order",
        "instance_literal_float_widths_reversed",
        "fn bump<T>(a:T)->T { return a+1.5; } fn main()->i32 { if (bump<f64>(1.5)!=3.0) { return 1; } if (bump<f32>(1.5)!=3.0) { return 2; } if (bump<f64>(0.2)!=1.7) { return 3; } return 42; }",
        42,
    );
    // Literal on the left, parentheses, nested operators, unary minus,
    // a signed minimum, comparisons, shifts, let and assignment contexts,
    // a generic call result and a returned literal.
    assert_exit(
        "integer literal contexts",
        "instance_literal_integer_contexts",
        "fn id<T>(a:T)->T { return a; } \
         fn f<T>(a:T)->T { return (2 * (a + 1)) - -3; } \
         fn g<T>(a:T)->T { let x:T = 5; return id<T>(a) * 2 + x; } \
         fn h<T>(a:T)->bool { return 1 < a && (a + 0) != 7; } \
         fn k<T>(a:T)->T { return 1 + 2 * a; } \
         fn m<T>(a:T)->T { let y:T = a; y = 3; return y; } \
         fn n<T>(a:T)->T { return -(1) + a; } \
         fn low<T>(a:T)->T { return a + -128; } \
         fn s<T>(a:T)->T { return (a << 2) >> 1; } \
         fn one<T>()->T { return 1; } \
         fn main()->i32 { \
           if (f<i32>(4) != 13 || f<i64>(4000000000) != 8000000005 || f<i16>(100) != 205) { return 1; } \
           if (g<i16>(3) != 11 || g<u64>(3) != 11) { return 2; } \
           if (!h<u8>(200) || h<i64>(0) || h<i32>(7)) { return 3; } \
           if (k<u16>(1000) != 2001 || k<i8>(3) != 7) { return 4; } \
           if (m<u64>(9) != 3 || m<i8>(9) != 3) { return 5; } \
           if (n<i8>(-127) != -128 || n<i64>(0) != -1) { return 6; } \
           if (low<i8>(127) != -1 || low<i32>(128) != 0) { return 7; } \
           if (s<u8>(100) != 72 || s<i64>(3000000000) != 6000000000) { return 8; } \
           if (one<i64>() != 1 || one<u8>() != 1) { return 9; } \
           return 42; }",
        42,
    );
    assert_exit(
        "float literal contexts",
        "instance_literal_float_contexts",
        "fn id<T>(a:T)->T { return a; } \
         fn f<T>(a:T)->T { return (2.0 * (a + 1.0)) - -3.0; } \
         fn g<T>(a:T)->T { let x:T = 0.5; return id<T>(a) * 2.0 + x; } \
         fn h<T>(a:T)->bool { return 1.5 < a && (a + 0.0) != 7.0; } \
         fn m<T>(a:T)->T { let y:T = a; y = 0.1; return y; } \
         fn half<T>()->T { return 0.5; } \
         fn main()->i32 { \
           if (f<f64>(0.5) != 6.0 || f<f32>(0.25) != 5.5) { return 1; } \
           if (g<f32>(1.5) != 3.5 || g<f64>(1.5) != 3.5) { return 2; } \
           if (!h<f32>(2.0) || h<f64>(1.0)) { return 3; } \
           if (m<f64>(0.0) + 0.2 != 0.30000000000000004) { return 4; } \
           if (m<f32>(0.0) + 0.2 != 0.3) { return 5; } \
           if (half<f32>() + half<f32>() != 1.0 || half<f64>() != 0.5) { return 6; } \
           return 42; }",
        42,
    );
    // One instance is bound in place rather than copied; its literal takes
    // the bound width too.
    assert_exit(
        "float literal of a single instance",
        "instance_literal_float_in_place",
        "fn big<T>(a:T)->T { return a + 1e39; } fn main()->i32 { let x:f64 = big<f64>(1.0); if (x != 1e39) { return 1; } return 42; }",
        42,
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn generic_literals_are_checked_against_each_instance_scalar() {
    // No implicit conversion: an integer literal does not take a float
    // context, as with `x + 1` for `x: f64`.
    assert_operand_rejected(
        "integer literal beside an f64 instance",
        "fn bump<T>(a:T)->T { return a+1; } fn main()->i32 { if (bump<f64>(1.5)!=2.5) { return 1; } return bump<i32>(41); }",
        "1; }",
        1,
    );
    assert_operand_rejected(
        "integer literal on the left beside an f64 instance",
        "fn tw<T>(a:T)->T { return 2*a; } fn main()->i32 { let r:i32 = tw<i32>(21); if (tw<f64>(1.5)!=3.0) { return 1; } return r; }",
        "2*a",
        1,
    );
    assert_operand_rejected(
        "float literal beside an integer instance",
        "fn bump<T>(a:T)->T { return a+0.5; } fn main()->i32 { let x:i32 = bump<i32>(1); if (bump<f64>(1.0)!=1.5) { return 1; } return x; }",
        "0.5",
        3,
    );
    assert_rejected(
        "integer literal outside u8",
        "LNC0069",
        "fn bump<T>(a:T)->T { return a+300; } fn main()->i32 { let x:i32 = bump<i32>(1); let y:u8 = bump<u8>(1); return x; }",
        "300",
        3,
    );
    assert_rejected(
        "integer literal outside u8, instances in the other order",
        "LNC0069",
        "fn bump<T>(a:T)->T { return a+300; } fn main()->i32 { let y:u8 = bump<u8>(1); let x:i32 = bump<i32>(1); return x; }",
        "300",
        3,
    );
    assert_rejected(
        "negative literal below i8",
        "LNC0069",
        "fn low<T>(a:T)->T { return a + -129; } fn main()->i32 { let x:i32 = low<i32>(1); let y:i8 = low<i8>(1); return x; }",
        "129",
        3,
    );
    assert_rejected(
        "float literal outside f32",
        "LNC0070",
        "fn big<T>(a:T)->T { return a + 1e39; } fn main()->i32 { let x:f64 = big<f64>(1.0); let y:f32 = big<f32>(1.0); return 42; }",
        "1e39",
        4,
    );
    // A returned value has its function's instance result type.
    assert_operand_rejected(
        "f64 product returned as i32",
        "fn sq<T>(a:T)->i32 { return a*a; } fn main()->i32 { let x:i32 = sq<f64>(1.5); return sq<i32>(6)+6; }",
        "a*a",
        1,
    );
    assert_operand_rejected(
        "f64 value returned as i32",
        "fn id<T>(a:T)->i32 { return a; } fn main()->i32 { let x:i32 = id<i32>(42); return id<f64>(1.5)+x; }",
        "a; }",
        1,
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn known_aggregate_and_bool_operands_are_rejected() {
    assert_operand_rejected(
        "negation of bool beside an integer instance",
        "fn neg<T>(a:T)->T { return -a; } fn main()->i32 { if (neg<bool>(true)) { return neg<i32>(-42); } return 1; }",
        "a; }",
        1,
    );
    assert_operand_rejected(
        "negation of bool, instances in the other order",
        "fn neg<T>(a:T)->T { return -a; } fn main()->i32 { if (neg<i32>(-42) != 42) { return 1; } if (neg<bool>(true)) { return 2; } return 42; }",
        "a; }",
        1,
    );
    assert_operand_rejected(
        "struct addition beside an integer instance",
        "fn add<T>(a:T,b:T)->T { return a+b; } struct S { v:i32 } fn main()->i32 { let s:S=S{v:1}; let t:S=add<S>(s,s); return add<i32>(t.v,41); }",
        "a+b",
        1,
    );
    assert_operand_rejected(
        "struct addition, instances in the other order",
        "struct S { v:i32 } fn add<T>(a:T,b:T)->T { return a+b; } fn main()->i32 { let r:i32 = add<i32>(40,2); let s:S=S{v:1}; let t:S=add<S>(s,s); return r; }",
        "a+b",
        1,
    );
    // The same rules outside generic bodies.
    for (context, source, anchor, length) in [
        ("negation of bool", "fn main()->i32 { let x:bool=true; if (-x) { return 1; } return 42; }", "x) {", 1),
        ("negation of a pointer", "fn main()->i32 { let p:ptr = 0; if (-p == p) { return 42; } return 1; }", "p ==", 1),
        ("struct addition", "struct S { v:i32 } fn main()->i32 { let s:S=S{v:1}; let t:S=s+s; return t.v; }", "s+s", 1),
        ("struct negation", "struct S { v:i32 } fn main()->i32 { let s:S=S{v:1}; let t:S=-s; return t.v; }", "s; r", 1),
        ("array addition", "fn main()->i32 { let a:[i32;2]=[1,2]; let b:[i32;2]=a+a; return b[0]; }", "a+a", 1),
        ("array equality", "fn main()->i32 { let a:[i32;2]=[1,2]; if (a == a) { return 42; } return 1; }", "a == a", 1),
        ("struct condition", "struct S { v:i32 } fn main()->i32 { let s:S=S{v:1}; if (s) { return 1; } return 42; }", "s) {", 1),
        ("logical not of a struct", "struct S { v:i32 } fn main()->i32 { let s:S=S{v:1}; if (!s) { return 1; } return 42; }", "s) {", 1),
        ("indexing a struct", "struct S { v:i32 } fn main()->i32 { let s:S=S{v:1}; return s[0]; }", "s[0]", 4),
        ("struct index", "struct S { v:i32 } fn main()->i32 { let a:[i32;2]=[1,2]; let s:S=S{v:1}; return a[s]; }", "s]", 1),
    ] {
        assert_operand_rejected(context, source, anchor, length);
    }
    // Supported forms stay accepted: enum and struct equality, enum and
    // char ordering, pointer offsets and null comparisons, unsigned
    // negation and distinct-type arithmetic.
    assert_exit(
        "supported compound and pointer operators",
        "instance_operator_supported_forms",
        "enum C { R, G } struct S { v:i32 } type M = distinct i64; \
         fn main()->i32 { \
           let c:C=C::R; let s:S=S{v:1}; let p:ptr = 0; let q:ptr = p + 8; \
           let m:M = 40; let n:M = -m; let u:u32 = 1; \
           if (c == C::G || !(c < C::G) || !(s == s)) { return 1; } \
           if ('a' >= 'b' || q == p || p != 0) { return 2; } \
           if (n >= m || -u == u) { return 3; } \
           return 42; }",
        42,
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn symbolic_literals_preserve_pointer_nulls_and_integer_offsets() {
    let declarations = "fn zero<T>()->T { return 0; } \
        fn is_zero<T>(p:T)->bool { return p == 0; } \
        fn next<T>(p:T)->T { return p + 8; } \
        fn assign<T>(p:T)->T { p += 8; return p; } \
        fn nested<T>(p:T)->T { return p - -(4 * 2); } \
        fn wrap<T>(p:T)->T { return p + (2147483647 + 1); }";
    let pointer = "let p:ptr = zero<ptr>(); let q:ptr = p + 8; \
        if (!is_zero<ptr>(p) || next<ptr>(p) != q || assign<ptr>(p) != q || nested<ptr>(p) != q) { return 1; } \
        let wrapped:ptr = p + -2147483648; if (wrap<ptr>(p) != wrapped) { return 2; }";
    let integer = "if (zero<i64>() != 0 || !is_zero<i64>(0) || next<i64>(0) != 8 || \
        assign<i64>(0) != 8 || nested<i64>(0) != 8 || wrap<i64>(0) != 2147483648) { return 3; }";
    for (index, (first, second)) in [(pointer, integer), (integer, pointer)].into_iter().enumerate() {
        assert_exit("pointer literal contexts", &format!("instance_literal_pointers_{index}"),
            &format!("{declarations} fn main()->i32 {{ {first} {second} return 42; }}"), 42);
    }
    assert_exit("pointer offset assignment bound in place", "instance_literal_pointer_in_place",
        "fn move<T>(p:T)->T { p += 8; p -= 4; return p; } fn main()->i32 { let p:ptr=0; let q:ptr=p; q += 8; q -= 4; if (move<ptr>(p)!=q) { return 1; } return 42; }", 42);
    assert_operand_rejected("nonzero integer is not a null pointer",
        "fn value<T>()->T { return 8; } fn main()->i32 { let p:ptr=value<ptr>(); return value<i32>(); }",
        "8;", 1);
    assert_operand_rejected("pointer comparison requires a null constant",
        "fn is_one<T>(p:T)->bool { return p == 1; } fn main()->i32 { let p:ptr=0; if (is_one<ptr>(p) || is_one<i32>(1)) { return 1; } return 42; }",
        "1;", 1);
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn symbolic_literal_contexts_stay_in_the_enclosing_binder() {
    assert_exit("inferred struct parameters do not escape into main", "instance_literal_inferred_fields",
        "struct P<T>{x:T} fn main()->i32 { let p=P{x:41}; let q=P{x:2.5}; if (q.x != 2.5) { return 1; } return p.x+1; }", 42);
    assert_exit("inferred enum payload literal", "instance_literal_inferred_payload",
        "enum Maybe<T>{Some(T),None} fn main()->i32 { let a=Some(41); return match (a) { Some(v) -> v+1, None -> 0 }; }", 42);
    assert_exit("generic field and inherited impl parameter", "instance_literal_field_and_impl",
        "struct P<T>{x:T} impl<T> P<T> { fn bump(&self)->T { return self.x+1; } } \
         fn bump<T>(p:P<T>)->T { return p.x+1; } \
         fn main()->i32 { let p:P<i64> = P{x:4000000000}; let q:P<u8> = P{x:41}; \
           if (p.bump()!=4000000001 || q.bump()!=42 || bump<i64>(p)!=4000000001 || bump<u8>(q)!=42) { return 1; } return 42; }", 42);
    assert_exit("single integer instance", "instance_literal_integer_in_place",
        "fn bump<T>(a:T)->T { return a+1; } fn main()->i32 { if (bump<i64>(4000000000)!=4000000001) { return 1; } return 42; }", 42);
    assert_rejected("single instance still checks literal range", "LNC0069",
        "fn bump<T>(a:T)->T { return a+300; } fn main()->i32 { let y:u8=bump<u8>(1); return 42; }", "300", 3);
}
