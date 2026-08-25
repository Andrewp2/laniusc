mod common;

use std::fmt::Write as _;

use laniusc_compiler::compiler::{GpuCompiler, GpuCompilerBackends};

fn integer_case_expected(left: i32, right: i32, shift: u32) -> i32 {
    let mut total = 0i32;
    total = total.wrapping_add(left.wrapping_add(right));
    total = total.wrapping_add(left.wrapping_sub(right));
    total = total.wrapping_add(left.wrapping_mul(right));
    total = total.wrapping_add(left / right);
    total = total.wrapping_add(left % right);
    total = total.wrapping_add(left & right);
    total = total.wrapping_add(left | right);
    total = total.wrapping_add(left ^ right);
    total = total.wrapping_add(left.wrapping_shl(shift));
    total = total.wrapping_add(left >> shift);
    total = total.wrapping_add(i32::from(left > right));
    total = total.wrapping_add(i32::from(left != 0 && right != 0));
    total
}

fn generated_scalar_program() -> (String, i32) {
    let cases = [(29, 5, 2), (41, 7, 3), (63, 9, 1), (17, 4, 4)];
    let mut source = String::from(
        "fn keep(value: i32) -> i32 { return value; }\n\
         fn keep_f32(value: f32) -> f32 { return value; }\n",
    );
    let mut expected = 0i32;
    for (index, (left, right, shift)) in cases.into_iter().enumerate() {
        expected = expected.wrapping_add(integer_case_expected(left, right, shift));
        writeln!(
            source,
            "fn integer_case_{index}() -> i32 {{\n\
             \x20   let left: i32 = keep({left});\n\
             \x20   let right: i32 = keep({right});\n\
             \x20   let shift: i32 = keep({shift});\n\
             \x20   let total: i32 = 0;\n\
             \x20   total += left + right;\n\
             \x20   total += left - right;\n\
             \x20   total += left * right;\n\
             \x20   total += left / right;\n\
             \x20   total += left % right;\n\
             \x20   total += left & right;\n\
             \x20   total += left | right;\n\
             \x20   total += left ^ right;\n\
             \x20   total += left << shift;\n\
             \x20   total += left >> shift;\n\
             \x20   if (left > right) {{ total += 1; }}\n\
             \x20   if (left != 0 && right != 0) {{ total += 1; }}\n\
             \x20   return total;\n\
             }}"
        )
        .unwrap();
    }

    source.push_str(
        "fn float_case() -> i32 {\n\
         \x20   let left: f32 = keep_f32(1.25);\n\
         \x20   let right: f32 = keep_f32(2.5);\n\
         \x20   let value: f32 = (left + right) * 2.0;\n\
         \x20   if (value == 7.5) { return 17; }\n\
         \x20   return 0;\n\
         }\n\
         fn main() -> i32 {\n\
         \x20   let total: i32 = integer_case_0() + integer_case_1() +\n\
         \x20       integer_case_2() + integer_case_3() + float_case();\n\
         \x20   return total % 251;\n\
         }\n",
    );
    expected = expected.wrapping_add(17).rem_euclid(251);
    (source, expected)
}

#[test]
fn generated_scalar_program_agrees_on_x86_and_wasm() {
    common::require_node();
    let (source, expected) = generated_scalar_program();
    let (x86, wasm) = common::run_gpu_codegen_with_timeout(
        "generated scalar semantic differential compile",
        move || {
            pollster::block_on(async move {
                let compiler = GpuCompiler::new_with_device_and_backends(
                    laniusc_compiler::gpu::device::global(),
                    GpuCompilerBackends::all(),
                )
                .await?;
                let x86 = compiler.compile_source_to_x86_64(&source).await?;
                let wasm = compiler.compile_source_to_wasm(&source).await?;
                Ok::<_, laniusc_compiler::compiler::CompileError>((x86, wasm))
            })
        },
    )
    .expect("generated scalar semantic program should compile for both targets");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "generated scalar semantic x86 execution",
            "optimizer_scalar_semantics",
            &x86,
        );
        assert_eq!(output.status.code(), Some(expected));
    }

    let wasm_result = common::run_wasm_main_return_with_node(
        "generated scalar semantic Wasm execution",
        "optimizer_scalar_semantics",
        &wasm,
    );
    assert_eq!(wasm_result, expected);
}

#[test]
fn structured_control_program_agrees_on_x86_and_wasm() {
    common::require_node();
    let source = r#"
fn accumulate(limit: i32) -> i32 {
    let index: i32 = 0;
    let total: i32 = 1;
    while (index < limit) {
        if (index % 3 == 0) {
            total += index;
        } else {
            total += 2;
        }
        index += 1;
    }
    if (total > 20) {
        return total % 251;
    }
    return 0;
}

fn main() -> i32 {
    return accumulate(12);
}
"#;
    let expected = 35;
    let (x86, wasm) =
        common::run_gpu_codegen_with_timeout("structured optimizer control compile", move || {
            pollster::block_on(async move {
                let compiler = GpuCompiler::new_with_device_and_backends(
                    laniusc_compiler::gpu::device::global(),
                    GpuCompilerBackends::all(),
                )
                .await?;
                let x86 = compiler.compile_source_to_x86_64(source).await?;
                let wasm = compiler.compile_source_to_wasm(source).await?;
                Ok::<_, laniusc_compiler::compiler::CompileError>((x86, wasm))
            })
        })
        .expect("structured control program should compile for both targets");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "structured optimizer control x86 execution",
            "optimizer_structured_control",
            &x86,
        );
        assert_eq!(output.status.code(), Some(expected));
    }

    let wasm_result = common::run_wasm_main_return_with_node(
        "structured optimizer control Wasm execution",
        "optimizer_structured_control",
        &wasm,
    );
    assert_eq!(wasm_result, expected);
}

#[test]
fn structured_loop_exits_agree_on_x86_and_wasm() {
    common::require_node();
    let source = r#"
fn main() -> i32 {
    let index: i32 = 0;
    let total: i32 = 0;
    while (index < 12) {
        index += 1;
        if (index % 2 == 0) {
            continue;
        }
        if (index > 7) {
            break;
        }
        total += index;
    }
    return total;
}
"#;
    let expected = 16;
    let (x86, wasm) =
        common::run_gpu_codegen_with_timeout("optimizer structured loop exits", move || {
            pollster::block_on(async move {
                let compiler = GpuCompiler::new_with_device_and_backends(
                    laniusc_compiler::gpu::device::global(),
                    GpuCompilerBackends::all(),
                )
                .await?;
                let x86 = compiler.compile_source_to_x86_64(source).await?;
                let wasm = compiler.compile_source_to_wasm(source).await?;
                Ok::<_, laniusc_compiler::compiler::CompileError>((x86, wasm))
            })
        })
        .expect("structured break/continue should compile for both targets");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "optimizer structured loop exits x86 execution",
            "optimizer_structured_loop_exits",
            &x86,
        );
        assert_eq!(output.status.code(), Some(expected));
    }

    let wasm_result = common::run_wasm_main_return_with_node(
        "optimizer structured loop exits Wasm execution",
        "optimizer_structured_loop_exits",
        &wasm,
    );
    assert_eq!(wasm_result, expected);
}

#[test]
fn projected_memory_program_agrees_on_x86_and_wasm() {
    common::require_node();
    let source = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn bump(pair: Pair, delta: i32) -> i32 {
    let next: Pair = pair;
    next.left += delta;
    next.right = next.left - 1;
    return next.left * 10 + next.right;
}

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, right: 5 };
    return bump(pair, 2);
}
"#;
    let expected = 98;
    let (x86, wasm) =
        common::run_gpu_codegen_with_timeout("optimizer projected memory compile", move || {
            pollster::block_on(async move {
                let compiler = GpuCompiler::new_with_device_and_backends(
                    laniusc_compiler::gpu::device::global(),
                    GpuCompilerBackends::all(),
                )
                .await?;
                let x86 = compiler.compile_source_to_x86_64(source).await?;
                let wasm = compiler.compile_source_to_wasm(source).await?;
                Ok::<_, laniusc_compiler::compiler::CompileError>((x86, wasm))
            })
        })
        .expect("projected memory program should compile for both targets");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "optimizer projected memory x86 execution",
            "optimizer_projected_memory",
            &x86,
        );
        assert_eq!(output.status.code(), Some(expected));
    }

    let wasm_result = common::run_wasm_main_return_with_node(
        "optimizer projected memory Wasm execution",
        "optimizer_projected_memory",
        &wasm,
    );
    assert_eq!(wasm_result, expected);
}
