use std::{
    fs,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};

use laniusc::{
    compiler::{
        GpuCompiler,
        compile_simple_source_to_c_with_gpu_codegen,
        compile_source_to_c,
        compile_source_to_c_with_gpu_codegen,
        compile_source_to_c_with_gpu_codegen_using,
        compile_source_to_c_with_gpu_frontend,
    },
    gpu::device,
};

#[test]
fn emits_c_for_function_fixture() {
    let c = compile_source_to_c(include_str!("../parser_tests/function.lani")).expect("compile C");

    assert!(c.contains("int main(void)"));
    assert!(c.contains("int64_t x = (1 + 2);"));
    assert!(c.contains("return x;"));
}

#[test]
fn emitted_parser_fixtures_are_c_syntax() {
    for (name, src) in [
        ("control", include_str!("../parser_tests/control.lani")),
        ("file", include_str!("../parser_tests/file.lani")),
        ("function", include_str!("../parser_tests/function.lani")),
    ] {
        let c = compile_source_to_c(src).unwrap_or_else(|err| panic!("{name}: {err}"));
        assert_c_syntax(name, &c);
    }
}

#[test]
fn emitted_function_fixture_runs() {
    let c = compile_source_to_c(include_str!("../parser_tests/function.lani")).expect("compile C");
    let Some(exe) = compile_c_executable("function_fixture", &c) else {
        return;
    };

    let status = Command::new(&exe).status().expect("run emitted executable");
    let _ = fs::remove_file(&exe);
    assert_eq!(status.code(), Some(3));
}

#[test]
fn gpu_frontend_emits_runnable_function_fixture() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_frontend(include_str!(
        "../parser_tests/function.lani"
    )))
    .expect("GPU frontend compile C");
    let Some(exe) = compile_c_executable("gpu_function_fixture", &c) else {
        return;
    };

    let status = Command::new(&exe).status().expect("run emitted executable");
    let _ = fs::remove_file(&exe);
    assert_eq!(status.code(), Some(3));
}

#[test]
fn gpu_codegen_emits_runnable_function_fixture() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(include_str!(
        "../parser_tests/function.lani"
    )))
    .expect("GPU codegen compile C");
    assert!(c.contains("int main(void)"));
    assert!(c.contains("int64_t x=1+2;"));

    let Some(exe) = compile_c_executable("gpu_codegen_function_fixture", &c) else {
        return;
    };

    let status = Command::new(&exe).status().expect("run emitted executable");
    let _ = fs::remove_file(&exe);
    assert_eq!(status.code(), Some(3));
}

#[test]
fn gpu_codegen_emits_parser_fixtures_as_c_syntax() {
    for (name, src) in [
        ("control", include_str!("../parser_tests/control.lani")),
        ("file", include_str!("../parser_tests/file.lani")),
        ("function", include_str!("../parser_tests/function.lani")),
    ] {
        let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(src))
            .unwrap_or_else(|err| panic!("{name}: GPU codegen failed: {err}"));
        assert_c_syntax(&format!("gpu_codegen_{name}"), &c);
        match name {
            "control" => {
                assert!(c.contains("while(y!=0){"));
                assert!(c.contains("y-=1;"));
                assert!(c.contains("break;"));
                assert!(c.contains("continue;"));
            }
            "file" => {
                assert!(c.contains("uint32_t my_arr[10]"));
                assert!(c.contains("lanius_print_i64(z);"));
            }
            _ => {}
        }
    }
}

#[test]
fn gpu_codegen_keeps_simple_fixture_compat_entrypoint() {
    let c = pollster::block_on(compile_simple_source_to_c_with_gpu_codegen(include_str!(
        "../parser_tests/function.lani"
    )))
    .expect("GPU codegen compile C");

    assert!(c.contains("int main(void)"));
    assert!(c.contains("return x;"));
}

#[test]
fn gpu_compiler_reuses_device_across_codegen_runs() {
    let compiler = pollster::block_on(GpuCompiler::new_with_device(device::global()))
        .expect("initialize reusable GPU compiler");

    let first = pollster::block_on(compile_source_to_c_with_gpu_codegen_using(
        "fn main() { let x: i32 = 1; return x; }\n",
        &compiler,
    ))
    .expect("first compile on reusable GPU compiler");
    let second = pollster::block_on(compile_source_to_c_with_gpu_codegen_using(
        "fn main() { let y: i32 = 2; return y; }\n",
        &compiler,
    ))
    .expect("second compile on reusable GPU compiler");

    assert!(first.contains("int32_t x=1;"));
    assert!(second.contains("int32_t y=2;"));
    assert_c_syntax("gpu_compiler_reuse_first", &first);
    assert_c_syntax("gpu_compiler_reuse_second", &second);
}

#[test]
fn gpu_codegen_wraps_top_level_statements() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "let x = 1 + 2;\nprint(x);\n",
    ))
    .expect("GPU codegen top-level C");

    assert!(c.contains("int main(void){"));
    assert!(c.contains("int64_t x=1+2;"));
    assert!(c.contains("lanius_print_i64(x);"));
    assert!(c.contains("return 0;"));
    assert_c_syntax("gpu_codegen_top_level", &c);
}

#[test]
fn gpu_codegen_wraps_top_level_statements_around_functions() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "let x = 1;\nfn f() { return; }\nlet y = x + 1;\nprint(y);\n",
    ))
    .expect("GPU codegen mixed item-order C");

    let fn_pos = c.find("void f(void){").expect("function emitted");
    let main_pos = c.find("int main(void){").expect("generated main emitted");
    assert!(
        fn_pos < main_pos,
        "function should be emitted before generated main:\n{c}"
    );
    assert!(c.contains("int64_t x=1;"));
    assert!(c.contains("int64_t y=x+1;"));
    assert!(c.contains("lanius_print_i64(y);"));
    assert!(c.contains("return 0;\n}\n"));
    assert_c_syntax("gpu_codegen_mixed_item_order", &c);
}

#[test]
fn gpu_codegen_checks_top_level_return_after_function_as_generated_main() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn f() { return; }\nreturn 1;\n",
    ))
    .expect("GPU type checker should treat top-level return as generated main");

    assert!(c.contains("void f(void){"));
    assert!(c.contains("int main(void){"));
    assert!(c.contains("return 1;"));
    assert_c_syntax("gpu_codegen_top_level_return_after_function", &c);
}

#[test]
fn gpu_codegen_scans_multiple_token_blocks() {
    let mut src = String::new();
    for i in 0..80 {
        src.push_str(&format!("let x{i} = {i};\n"));
    }

    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(&src))
        .expect("GPU codegen multi-block source");

    assert!(c.contains("int main(void){"));
    assert!(c.contains("int64_t x79=79;"));
    assert!(c.contains("return 0;"));
    assert_c_syntax("gpu_codegen_multi_block", &c);
}

#[test]
fn gpu_codegen_resolves_names_across_large_scope() {
    let mut src = String::from("fn main() { let x: i32 = 7;\n");
    for i in 0..180 {
        src.push_str(&format!("let y{i}: i32 = {i};\n"));
    }
    src.push_str("return x; }\n");

    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(&src))
        .expect("GPU codegen should resolve names across large scopes");

    assert!(c.contains("int32_t x=7;"));
    assert!(c.contains("int32_t y179=179;"));
    assert!(c.contains("return x;"));
    assert_c_syntax("gpu_codegen_large_scope_resolution", &c);
}

#[test]
fn gpu_codegen_infers_top_level_let_types() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "let a = 1.5;\nlet b = 'x';\nlet c = \"hi\";\nlet d = 1 < 2;\n",
    ))
    .expect("GPU codegen inferred let C");

    assert!(c.contains("double a=1.5;"));
    assert!(c.contains("char b='x';"));
    assert!(c.contains("const char * c=\"hi\";"));
    assert!(c.contains("bool d=1<2;"));
    assert_c_syntax("gpu_codegen_inferred_lets", &c);
}

#[test]
fn gpu_codegen_infers_let_types_from_identifiers_and_calls() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn value() -> f64 { return 2.5; }\n\
         fn main() { let s = \"hi\"; let t = s; let u = t; let v = u; let f = value(); let g = f; return 0; }\n",
    ))
    .expect("GPU codegen inferred identifier and call let C");

    assert!(c.contains("double value(void){"));
    assert!(c.contains("const char * s=\"hi\";"));
    assert!(c.contains("const char * t=s;"));
    assert!(c.contains("const char * u=t;"));
    assert!(c.contains("const char * v=u;"));
    assert!(c.contains("double f=value();"));
    assert!(c.contains("double g=f;"));
    assert_c_syntax("gpu_codegen_inferred_idents_calls", &c);
}

#[test]
fn gpu_codegen_respects_block_scoped_names() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn main() { let x: i32 = 1; { let x = \"inner\"; let s = x; } let z = x; let y: i32 = z; return y; }\n",
    ))
    .expect("GPU codegen block-scoped C");

    assert!(c.contains("int32_t x=1;"));
    assert!(c.contains("const char * x=\"inner\";"));
    assert!(c.contains("const char * s=x;"));
    assert!(c.contains("int32_t z=x;"));
    assert!(c.contains("int32_t y=z;"));
    assert!(c.contains("return y;"));
    assert_c_syntax("gpu_codegen_block_scope", &c);
}

#[test]
fn gpu_codegen_rejects_type_errors_on_gpu() {
    for (name, src, want) in [
        (
            "unknown type",
            "fn main() { let x: bogus = 1; return x; }\n",
            "UnknownType",
        ),
        (
            "unresolved ident",
            "fn main() { return missing; }\n",
            "UnresolvedIdent",
        ),
        (
            "function scope leak",
            "fn f() { let x: i32 = 1; return; }\nfn main() { return x; }\n",
            "UnresolvedIdent",
        ),
        (
            "block scope leak",
            "fn main() { if (1 < 2) { let x: i32 = 1; } return x; }\n",
            "UnresolvedIdent",
        ),
        (
            "raw block scope leak",
            "fn main() { { let x: i32 = 1; } return x; }\n",
            "UnresolvedIdent",
        ),
        (
            "literal mismatch",
            "fn main() { let x: i32 = \"no\"; return x; }\n",
            "AssignMismatch",
        ),
        (
            "float arithmetic mismatch",
            "fn main() { let x: i32 = 1 + 2.5; return x; }\n",
            "AssignMismatch",
        ),
        (
            "inferred identifier mismatch",
            "fn main() { let s = \"hi\"; let t = s; let x: i32 = t; return x; }\n",
            "AssignMismatch",
        ),
        (
            "block shadow inferred identifier mismatch",
            "fn main() { let x: i32 = 1; { let x = \"inner\"; let y: i32 = x; } return x; }\n",
            "AssignMismatch",
        ),
        (
            "assignment mismatch",
            "fn main() { let x: i32 = 1; x = \"bad\"; return x; }\n",
            "AssignMismatch",
        ),
    ] {
        let err = match pollster::block_on(compile_source_to_c_with_gpu_codegen(src)) {
            Ok(c) => panic!("{name}: expected GPU type error, got C:\n{c}"),
            Err(err) => err,
        };
        let msg = err.to_string();
        assert!(msg.contains(want), "{name}: {msg}");
    }
}

#[test]
fn gpu_codegen_rejects_invalid_c_edge_cases_on_gpu() {
    for (name, src, want) in [
        (
            "invalid member access",
            "fn main() { let x: i32 = 1; let y = x.foo; return y; }\n",
            "InvalidMemberAccess",
        ),
        (
            "typed array whole assignment",
            "fn main() { let a: [i32; 2] = [1, 2]; a = [3, 4]; return a[0]; }\n",
            "AssignMismatch",
        ),
        (
            "inferred array whole assignment",
            "fn main() { let a = [1, 2]; a = [3, 4]; return a[0]; }\n",
            "AssignMismatch",
        ),
        (
            "indexing non-array",
            "fn main() { let x: i32 = 1; return x[0]; }\n",
            "AssignMismatch",
        ),
        (
            "indexing grouped non-array",
            "fn main() { let x: i32 = 1; return (x)[0]; }\n",
            "AssignMismatch",
        ),
        (
            "index with non-integer",
            "fn main() { let a: [i32; 2] = [1, 2]; return a[\"bad\"]; }\n",
            "AssignMismatch",
        ),
        (
            "sibling block scope leak",
            "fn main() { if (1 < 2) { let x: i32 = 1; } if (2 < 3) { return x; } return 0; }\n",
            "UnresolvedIdent",
        ),
        (
            "inferred call mismatch",
            "fn value() -> f64 { return 2.5; }\nfn main() { let f = value(); let x: i32 = f; return x; }\n",
            "AssignMismatch",
        ),
        (
            "array equality",
            "fn main() { let ok = [1] == [1]; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "indexed assignment mismatch",
            "fn main() { let a: [i32; 2] = [1, 2]; a[0] = \"bad\"; return a[0]; }\n",
            "AssignMismatch",
        ),
        (
            "typed array element mismatch",
            "fn main() { let a: [i32; 2] = [1, \"bad\"]; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "inferred array element mismatch",
            "fn main() { let a = [1, \"bad\"]; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "typed array too short",
            "fn main() { let a: [i32; 2] = [1]; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "typed array too long",
            "fn main() { let a: [i32; 2] = [1, 2, 3]; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "array return type",
            "fn f() -> [i32; 2] { return [1, 2]; }\nfn main() { return 0; }\n",
            "InvalidArrayReturn",
        ),
        (
            "break outside loop",
            "fn main() { break; return 0; }\n",
            "LoopControl",
        ),
        (
            "continue outside loop",
            "fn main() { if (1 < 2) { continue; } return 0; }\n",
            "LoopControl",
        ),
        (
            "assignment non-lvalue",
            "fn main() { 1 = 2; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "prefix increment non-lvalue",
            "fn main() { ++1; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "postfix increment non-lvalue",
            "fn main() { 1++; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "call increment non-lvalue",
            "fn value() -> i32 { return 1; }\nfn main() { value()++; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "function argument mismatch",
            "fn id(x: i32) -> i32 { return x; }\nfn main() { return id(\"bad\"); }\n",
            "AssignMismatch",
        ),
        (
            "function arity mismatch",
            "fn id(x: i32) -> i32 { return x; }\nfn main() { return id(1, 2); }\n",
            "AssignMismatch",
        ),
        (
            "print argument mismatch",
            "fn main() { print(\"bad\"); return 0; }\n",
            "AssignMismatch",
        ),
        (
            "not string operand",
            "fn main() { let ok: bool = !\"bad\"; return 0; }\n",
            "ConditionType",
        ),
        (
            "bitwise not float operand",
            "fn main() { let x = ~2.5; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "bitwise not string operand",
            "fn main() { let x = ~\"bad\"; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "string arithmetic lhs",
            "fn main() { let x = \"bad\" + 1; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "string arithmetic rhs",
            "fn main() { let x = 1 * \"bad\"; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "float bit shift",
            "fn main() { let x = 2.5 << 1; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "string equality",
            "fn main() { let ok = \"a\" == \"b\"; return 0; }\n",
            "AssignMismatch",
        ),
        (
            "string logical and",
            "fn main() { let ok = \"a\" && 1; return 0; }\n",
            "AssignMismatch",
        ),
    ] {
        let err = match pollster::block_on(compile_source_to_c_with_gpu_codegen(src)) {
            Ok(c) => panic!("{name}: expected GPU type error, got C:\n{c}"),
            Err(err) => err,
        };
        let msg = err.to_string();
        assert!(msg.contains(want), "{name}: {msg}");
    }
}

#[test]
fn gpu_codegen_accepts_gpu_checked_bool_expression() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn main() { let ok: bool = !(1 > 2); let bits = ~1; return 0; }\n",
    ))
    .expect("GPU type checker should accept bool comparison");

    assert!(c.contains("bool ok=!(1>2);"));
    assert!(c.contains("int64_t bits=~1;"));
    assert_c_syntax("gpu_codegen_bool_typecheck", &c);
}

#[test]
fn gpu_codegen_emits_checked_function_calls_and_arrays() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn add(x: i32, y: i32) -> i32 { return x + y; }\n\
         fn main() { let a: [i32; 3] = [1, 2, 3]; return add(a[0], a[1]); }\n",
    ))
    .expect("GPU codegen function call and array C");

    assert!(c.contains("int32_t add(int32_t x,int32_t y){"));
    assert!(c.contains("int32_t a[3]={1,2,3};"));
    assert!(c.contains("return add(a[0],a[1]);"));
    assert_c_syntax("gpu_codegen_calls_arrays", &c);
}

#[test]
fn gpu_codegen_infers_array_literal_declarations() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn main() { let a = [1, 2, 3]; return a[1]; }\n",
    ))
    .expect("GPU codegen inferred array literal C");

    assert!(c.contains("int64_t a[3]={1,2,3};"));
    assert!(c.contains("return a[1];"));
    assert_c_syntax("gpu_codegen_inferred_array_literal", &c);
}

#[test]
fn gpu_codegen_emits_array_literal_compound_expressions() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn main() { [1, 2]; let a: [i32; 2] = [1, 2]; return ([a[0], a[1]])[1]; }\n",
    ))
    .expect("GPU codegen array literal expression C");

    assert!(c.contains("(int64_t[]){1,2};"));
    assert!(c.contains("return ((int64_t[]){a[0],a[1]})[1];"));
    assert_c_syntax("gpu_codegen_array_literal_compound_expr", &c);
}

#[test]
fn gpu_codegen_checks_increment_decrement_lvalues() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn main() { let x: i32 = 1; ++x; x--; return x; }\n",
    ))
    .expect("GPU codegen inc/dec lvalues");

    assert!(c.contains("++x;"));
    assert!(c.contains("x--;"));
    assert_c_syntax("gpu_codegen_inc_dec_lvalues", &c);
}

#[test]
fn gpu_codegen_emits_compound_bitwise_and_shift_ops() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn main() { let x: i32 = 1; x += 2; x -= 1; x *= 3; x /= 2; x %= 2; let y: i32 = (x & 3) | (4 ^ 2); return y << 1 >> 1; }\n",
    ))
    .expect("GPU codegen compound and bitwise ops");

    assert!(c.contains("x+=2;"));
    assert!(c.contains("x-=1;"));
    assert!(c.contains("x*=3;"));
    assert!(c.contains("x/=2;"));
    assert!(c.contains("x%=2;"));
    assert!(c.contains("int32_t y=(x&3)|(4^2);"));
    assert!(c.contains("return y<<1>>1;"));
    assert_c_syntax("gpu_codegen_compound_bitwise_shift", &c);
}

#[test]
fn gpu_codegen_emits_unary_no_init_lets_and_nested_calls() {
    let c = pollster::block_on(compile_source_to_c_with_gpu_codegen(
        "fn id(x: i32) -> i32 { return x; }\n\
         fn main() { let scratch: i32; scratch = id(id(1)); ++scratch; scratch--; let y: i32 = -scratch; let z = ~y; return z; }\n",
    ))
    .expect("GPU codegen unary, no-init let, and nested calls");

    assert!(c.contains("int32_t id(int32_t x){"));
    assert!(c.contains("int32_t scratch;"));
    assert!(c.contains("scratch=id(id(1));"));
    assert!(c.contains("++scratch;"));
    assert!(c.contains("scratch--;"));
    assert!(c.contains("int32_t y=-scratch;"));
    assert!(c.contains("int64_t z=~y;"));
    assert_c_syntax("gpu_codegen_unary_no_init_nested_calls", &c);
}

#[test]
fn gpu_codegen_cli_does_not_need_frontend_readbacks() {
    let src_path = std::env::temp_dir().join(format!(
        "laniusc_gpu_no_readback_{}_{}.lani",
        std::process::id(),
        unique_suffix()
    ));
    let out_path = src_path.with_extension("c");
    fs::write(
        &src_path,
        "fn main() { let x: i32 = 1; let y: i32 = x + 2; return y; }\n",
    )
    .expect("write temporary source");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let output = Command::new(bin)
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .args(["--gpu-codegen"])
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
    let c = fs::read_to_string(&out_path).expect("read emitted C");
    let _ = fs::remove_file(&out_path);
    assert!(c.contains("int32_t x=1;"));
    assert!(c.contains("int32_t y=x+2;"));
    assert!(c.contains("return y;"));
    assert_c_syntax("gpu_codegen_no_frontend_readbacks", &c);
}

#[test]
fn gpu_codegen_rejects_syntax_errors_on_gpu() {
    for (name, src, want) in [
        (
            "missing semicolon",
            "fn main() { let x = 1 return x; }\n",
            "MissingSemicolon",
        ),
        (
            "unbalanced delimiter",
            "fn main() { let x = 1; return x; \n",
            "UnbalancedDelimiter",
        ),
        ("early close delimiter", "} {\n", "UnbalancedDelimiter"),
        (
            "bad if block",
            "fn main() { if (1) return 1; return 0; }\n",
            "ExpectedToken",
        ),
        (
            "empty let initializer",
            "fn main() { let x = ; return 0; }\n",
            "ExpectedToken",
        ),
        (
            "orphan else",
            "fn main() { else { return 0; } return 0; }\n",
            "ExpectedToken",
        ),
        (
            "empty assignment",
            "fn main() { let x = 1; x = ; return x; }\n",
            "ExpectedToken",
        ),
        (
            "empty call argument",
            "fn id(x: i32) -> i32 { return x; }\nfn main() { return id(,); }\n",
            "ExpectedToken",
        ),
        (
            "missing binary rhs",
            "fn main() { let x = 1 + ; return 0; }\n",
            "ExpectedToken",
        ),
        (
            "missing binary lhs",
            "fn main() { let x = * 1; return 0; }\n",
            "ExpectedToken",
        ),
        (
            "adjacent expression atoms",
            "fn main() { return 1 2; }\n",
            "ExpectedToken",
        ),
        (
            "empty group expression",
            "fn main() { let x = (); return 0; }\n",
            "ExpectedToken",
        ),
        (
            "empty index expression",
            "fn main() { let a: [i32; 2] = [1, 2]; return a[]; }\n",
            "ExpectedToken",
        ),
        (
            "trailing array element comma",
            "fn main() { let a: [i32; 2] = [1, 2,]; return 0; }\n",
            "ExpectedToken",
        ),
        (
            "missing typed let type",
            "fn main() { let x: = 1; return 0; }\n",
            "LL(1) parser",
        ),
    ] {
        let err = match pollster::block_on(compile_source_to_c_with_gpu_codegen(src)) {
            Ok(c) => panic!("{name}: expected GPU syntax error, got C:\n{c}"),
            Err(err) => err,
        };
        let msg = err.to_string();
        assert!(msg.contains("GPU syntax error"), "{name}: {msg}");
        assert!(
            msg.contains(want) || msg.contains("LL(1) parser"),
            "{name}: {msg}"
        );
    }
}

fn assert_c_syntax(name: &str, c: &str) {
    let mut child = match Command::new("cc")
        .args(["-std=c11", "-fsyntax-only", "-x", "c", "-"])
        .stdin(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return,
        Err(err) => panic!("{name}: failed to spawn cc: {err}"),
    };

    child
        .stdin
        .as_mut()
        .expect("cc stdin")
        .write_all(c.as_bytes())
        .expect("write C to cc");

    let output = child.wait_with_output().expect("wait for cc");
    assert!(
        output.status.success(),
        "{name}: emitted C failed syntax check:\n{}\n--- C ---\n{}",
        String::from_utf8_lossy(&output.stderr),
        c
    );
}

fn compile_c_executable(name: &str, c: &str) -> Option<PathBuf> {
    let path = std::env::temp_dir().join(format!(
        "laniusc_{}_{}_{}",
        name,
        std::process::id(),
        unique_suffix()
    ));
    let mut child = match Command::new("cc")
        .args(["-std=c11", "-x", "c", "-", "-o"])
        .arg(&path)
        .stdin(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return None,
        Err(err) => panic!("{name}: failed to spawn cc: {err}"),
    };

    child
        .stdin
        .as_mut()
        .expect("cc stdin")
        .write_all(c.as_bytes())
        .expect("write C to cc");
    let output = child.wait_with_output().expect("wait for cc");
    assert!(
        output.status.success(),
        "{name}: emitted C failed executable build:\n{}\n--- C ---\n{}",
        String::from_utf8_lossy(&output.stderr),
        c
    );
    Some(path)
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}
