mod common;

use laniusc::compiler::{
    compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen,
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
    CompileError,
};

fn assert_x86_64_elf_entry(bytes: &[u8]) {
    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
}

fn assert_x86_text_contains_direct_call(bytes: &[u8]) {
    assert!(
        bytes[0x78..].contains(&0xe8),
        "direct call lowering should emit a call rel32 opcode in .text"
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn assert_x86_exit_code(context: &str, artifact_stem: &str, bytes: &[u8], expected: i32) {
    let output = common::run_x86_64_elf_output(context, artifact_stem, bytes);
    assert_eq!(output.status.code(), Some(expected));
}

#[test]
fn x86_path_codegen_reports_missing_input_before_codegen() {
    let missing = common::temp_artifact_path("laniusc_missing_x86", "input", Some("lani"));
    if let Err(err) = std::fs::remove_file(&missing) {
        log::warn!(
            "failed to remove stale missing-input artifact {}: {err}",
            missing.display()
        );
    }

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        &missing,
    ))
    .expect_err("missing x86 input should fail while preparing source");

    let message = err.to_string();
    match err {
        CompileError::GpuFrontend(_) => {}
        other => panic!("expected GPU frontend read error, got {other:?}: {message}"),
    }
    assert!(
        message.contains("read") && message.contains(&missing.display().to_string()),
        "missing input error should name the unreadable path: {message}"
    );
    assert!(
        !message.contains("GPU x86_64 codegen is not currently available"),
        "missing input should not be reported as backend codegen failure: {message}"
    );
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
fn x86_sample_programs_execute_expected_stdout() {
    for sample in common::sample_programs::load_sample_programs() {
        let sample_name = sample.name().to_string();
        let sample_source = sample.source().to_string();
        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 sample compile {sample_name}"),
            move || match sample_name.as_str() {
                "option_result_helpers" => {
                    pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&[
                        include_str!("../stdlib/core/option.lani"),
                        include_str!("../stdlib/core/result.lani"),
                        sample_source.as_str(),
                    ]))
                }
                "range_sum" => {
                    pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&[
                        include_str!("../stdlib/core/range.lani"),
                        sample_source.as_str(),
                    ]))
                }
                "slice_helpers" => {
                    pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&[
                        include_str!("../stdlib/core/slice.lani"),
                        sample_source.as_str(),
                    ]))
                }
                _ => pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&sample_source)),
            },
        )
        .unwrap_or_else(|err| {
            panic!(
                "x86 sample {} should compile from {}\nerror: {err}",
                sample.name(),
                sample.path().display()
            )
        });

        let output = common::run_x86_64_elf_output(
            format!("x86 sample {}", sample.name()),
            &format!("sample_{}", sample.name()),
            &bytes,
        );
        common::assert_command_success(format!("x86 sample {}", sample.name()), &output);
        sample.assert_stdout_eq("x86", &String::from_utf8_lossy(&output.stdout));
    }
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_integer_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 7;\n}\n",
    ))
    .expect("x86 codegen should emit an executable ELF for a scalar return");

    assert_x86_64_elf_entry(&bytes);
    assert_eq!(bytes[4], 2, "ELF64 class");
    assert_eq!(bytes[5], 1, "little-endian ELF");
    assert_eq!(u16::from_le_bytes(bytes[18..20].try_into().unwrap()), 62);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 integer literal return",
        "x86_integer_literal_return",
        &bytes,
        7,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_zero_arg_direct_call_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn value() -> i32 {\n    return 7;\n}\nfn main() {\n    return value();\n}\n",
    ))
    .expect("x86 codegen should emit a direct call using backend call ABI records");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert!(
        bytes[0x78..].contains(&0xe8),
        "direct call lowering should emit a call rel32 opcode in .text"
    );

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 zero-arg direct call return",
            "x86_zero_arg_direct_call_return",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(7));
    }
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_one_literal_arg_direct_call_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn value(x: i32) -> i32 {\n    return 9;\n}\nfn main() {\n    return value(7);\n}\n",
    ))
    .expect("x86 codegen should pass a literal SysV integer arg before a direct call");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 one literal arg direct call return",
        "x86_one_literal_arg_direct_call_return",
        &bytes,
        9,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_one_arg_param_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    return id(7);\n}\n",
    ))
    .expect("x86 codegen should lower a direct call whose callee returns its first parameter");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 one param direct call return",
        "x86_one_param_direct_call_return",
        &bytes,
        7,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_local_call_arg_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let value: i32 = 7;\n    return id(value);\n}\n",
    ))
    .expect("x86 codegen should lower a local scalar call argument through call-arg value records");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 local arg direct call return",
        "x86_local_arg_direct_call_return",
        &bytes,
        7,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_binary_call_arg_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    return id(4 + 5);\n}\n",
    ))
    .expect(
        "x86 codegen should lower a scalar binary call argument through call-arg value records",
    );

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 binary arg direct call return",
        "x86_binary_arg_direct_call_return",
        &bytes,
        9,
    );
}

#[test]
fn x86_source_codegen_keeps_param_values_across_fixed_register_arg_eval() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn g(x: i32, y: i32) -> i32 {\n    print(x);\n    print(y);\n    return y;\n}\nfn f(a: i32, b: i32, c: i32, d: i32) -> i32 {\n    return g((11 << 1), d);\n}\nfn main() {\n    print(f(9, 52, 90, 14));\n    return 0;\n}\n",
    ))
    .expect(
        "x86 codegen should snapshot parameter values before fixed-register expression lowering",
    );

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 fixed register call argument parameter",
            "x86_fixed_register_call_arg_param",
            &bytes,
        );
        assert_eq!(stdout, "22\n14\n14\n");
    }
}

#[test]
fn x86_source_codegen_executes_intrinsic_output_for_hir_constant_locals() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let a: i32 = 1 + 2 * 3;\n    let b: i32 = (1 + 2) * 3;\n    print(a);\n    print(b);\n    return 0;\n}\n",
    ))
    .expect("x86 codegen should emit semantic intrinsic output rows from HIR values");

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 intrinsic output for constant locals",
            "x86_intrinsic_output_constant_locals",
            &bytes,
        );
        assert_eq!(stdout, "7\n9\n");
    }
}

#[test]
fn x86_source_codegen_executes_intrinsic_output_for_chained_local_constants() {
    let source = "fn main() {\n    let x: i32 = (6 & 3) | (8 ^ 2);\n    let y: i32 = x << 1 >> 2;\n    print(y);\n    return 0;\n}\n";
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 intrinsic output for chained local constants",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source)),
    )
    .expect("x86 codegen should resolve chained local constants through HIR records");

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 intrinsic output for chained local constants",
            "x86_intrinsic_output_chained_local_constants",
            &bytes,
        );
        assert_eq!(stdout, "5\n");
    }
}

#[test]
fn x86_source_codegen_executes_hir_if_intrinsic_output_once_per_taken_branch() {
    let source = "fn main() {\n    let alpha_value: i32 = 7;\n    let beta_value: i32 = 3;\n    if (alpha_value >= beta_value) {\n        print(10);\n    } else {\n        print(11);\n    }\n    if ((alpha_value == beta_value) || false) {\n        print(20);\n    } else {\n        print(21);\n    }\n    if (beta_value < alpha_value) {\n        print(30);\n    }\n    return 0;\n}\n";
    let bytes = common::run_gpu_codegen_with_timeout("x86 HIR if intrinsic output", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect(
        "x86 codegen should lower HIR if statement intrinsic output without printing both arms",
    );

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf(
            "x86 HIR if intrinsic output",
            "x86_hir_if_intrinsic_output",
            &bytes,
        );
        assert_eq!(stdout, "10\n21\n30\n");
    }
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_one_arg_param_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn inc(x: i32) -> i32 {\n    return x + 1;\n}\nfn main() {\n    return inc(7);\n}\n",
    ))
    .expect("x86 codegen should lower a direct call whose callee returns param plus literal");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 one param add direct call return",
        "x86_one_param_add_direct_call_return",
        &bytes,
        8,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_two_arg_param_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(7, 5);\n}\n",
    ))
    .expect("x86 codegen should lower a direct call whose callee adds two parameters");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 two param add direct call return",
        "x86_two_param_add_direct_call_return",
        &bytes,
        12,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_three_arg_third_param_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn third(x: i32, y: i32, z: i32) -> i32 {\n    return z;\n}\nfn main() {\n    return third(7, 5, 3);\n}\n",
    ))
    .expect("x86 codegen should lower the third SysV integer argument through HIR call records");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 three param third direct call return",
        "x86_three_param_third_direct_call_return",
        &bytes,
        3,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_two_binary_arg_param_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(4 + 5, 6 + 7);\n}\n",
    ))
    .expect("x86 codegen should assign width-based vreg ranges for two binary call args");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 two binary arg param add return",
        "x86_two_binary_arg_param_add_return",
        &bytes,
        22,
    );
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
fn x86_source_pack_codegen_emits_direct_elf_for_module_main_literal_return() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return 5;\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should emit direct ELF bytes for a bounded main return");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_exit_code(
        "x86 source-pack module literal return",
        "x86_source_pack_module_literal_return",
        &bytes,
        5,
    );
}

#[test]
#[cfg(all(unix, target_arch = "x86_64"))]
fn x86_source_pack_codegen_emits_direct_elf_for_qualified_scalar_const_return() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::MAX;\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower a resolver-backed scalar const return");

    assert_x86_64_elf_entry(&bytes);
    assert!(
        bytes
            .windows(4)
            .any(|window| window == 2_147_483_647u32.to_le_bytes()),
        "qualified const return should materialize i32::MAX"
    );
    assert_x86_exit_code(
        "x86 source-pack qualified const return",
        "x86_source_pack_qualified_const_return",
        &bytes,
        255,
    );
}

#[test]
fn x86_source_pack_codegen_emits_direct_elf_for_stdlib_min_helper_branch() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::min(7, 5);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower a resolver-backed terminal-if helper");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code("x86 source-pack core::i32::min", "core_i32_min", &bytes, 5);
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_abs_helper_branch() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::abs(-4);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect(
        "x86 source-pack codegen should lower a resolver-backed param/immediate terminal-if helper",
    );

    assert_eq!(&bytes[0..4], b"\x7fELF");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::i32::abs(-4)",
            "core_i32_abs",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(4));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_saturating_abs_const_call_branch() {
    let cases = [
        ("negative", "-4", 0u32.wrapping_sub(4), Some(4)),
        ("positive", "4", 4u32, Some(4)),
        ("min", "-2147483648", 0x8000_0000u32, Some(255)),
    ];

    for (name, arg_source, _arg_bits, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() {{\n    return core::i32::saturating_abs({arg_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!(
                    "x86 source-pack codegen should lower core::i32::saturating_abs {name}: {err}"
                )
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::saturating_abs {name}"),
                &format!("core_i32_saturating_abs_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_clamp_nested_helper_branch() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::clamp(9, 0, 7);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower a resolver-backed nested terminal-if helper");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::i32::clamp(9, 0, 7)",
            "core_i32_clamp",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(7));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_signum_nested_literal_branch() {
    let cases = [
        ("negative", "-9", 0u32.wrapping_sub(9), Some(255)),
        ("zero", "0", 0u32, Some(0)),
        ("positive", "9", 9u32, Some(1)),
    ];

    for (name, arg_source, _arg_bits, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() {{\n    return core::i32::signum({arg_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::i32::signum {name}: {err}")
            });

        assert_x86_64_elf_entry(&bytes);
        assert_x86_text_contains_direct_call(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::signum {name}"),
                &format!("core_i32_signum_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_compare_as_i32_nested_literal_branch() {
    let cases = [
        ("less", "4", "9", 4u32, 9u32, Some(255)),
        ("greater", "9", "4", 9u32, 4u32, Some(1)),
        ("equal", "4", "4", 4u32, 4u32, Some(0)),
    ];

    for (name, left_source, right_source, _left_bits, _right_bits, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() {{\n    return core::i32::compare_as_i32({left_source}, {right_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!(
                    "x86 source-pack codegen should lower core::i32::compare_as_i32 {name}: {err}"
                )
            });

        assert_x86_64_elf_entry(&bytes);
        assert_x86_text_contains_direct_call(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::compare_as_i32 {name}"),
                &format!("core_i32_compare_as_i32_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_predicate_helpers() {
    let cases = [
        ("is_zero", "core::i32::is_zero(0)", 0u32, 0x94u8),
        (
            "is_negative",
            "core::i32::is_negative(-3)",
            0u32.wrapping_sub(3),
            0x9cu8,
        ),
        ("is_positive", "core::i32::is_positive(5)", 5u32, 0x9fu8),
    ];

    for (name, call, _arg, _setcc_opcode) in cases {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() -> bool {{\n    return {call};\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::i32::{name}: {err}")
            });

        assert_x86_64_elf_entry(&bytes);
        assert_x86_text_contains_direct_call(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::{name}"),
                &format!("core_i32_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), Some(1));
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_i32_between_inclusive_compare_and_compare() {
    let cases = [
        ("true", "5", "1", "9", 5u32, 1u32, 9u32, Some(1)),
        ("low_false", "0", "1", "9", 0u32, 1u32, 9u32, Some(0)),
        ("high_false", "10", "1", "9", 10u32, 1u32, 9u32, Some(0)),
    ];

    for (
        name,
        value_source,
        low_source,
        high_source,
        _value_bits,
        _low_bits,
        _high_bits,
        expected,
    ) in cases
    {
        let user_source = format!(
            "module app::main;\nimport core::i32;\nfn main() -> bool {{\n    return core::i32::between_inclusive({value_source}, {low_source}, {high_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/i32.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!(
                    "x86 source-pack codegen should lower core::i32::between_inclusive {name}: {err}"
                )
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::i32::between_inclusive {name}"),
                &format!("core_i32_between_inclusive_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u32_min_with_unsigned_branch() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> u32 {\n    return core::u32::min(4294967295, 1);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower core::u32::min with unsigned ordering");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u32::min unsigned",
            "core_u32_min_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(1));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u32_max_with_unsigned_branch() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> u32 {\n    return core::u32::max(4294967295, 1);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower core::u32::max with unsigned ordering");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u32::max unsigned",
            "core_u32_max_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(255));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u32_between_inclusive_unsigned_setcc() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::between_inclusive(2147483648, 1, 4294967295);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect(
            "x86 source-pack codegen should lower core::u32::between_inclusive with unsigned comparisons",
        );

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u32::between_inclusive unsigned",
            "core_u32_between_inclusive_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(1));
    }
}

#[test]
fn x86_source_codegen_executes_u32_local_comparison_as_unsigned() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let left: u32 = 4294967295;\n    let right: u32 = 1;\n    return left > right;\n}\n",
    ))
    .expect("x86 codegen should compare local u32 declarations with unsigned ordering");

    assert_x86_64_elf_entry(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 local u32 unsigned comparison",
        "x86_local_u32_unsigned_comparison",
        &bytes,
        1,
    );
}

#[test]
fn x86_source_pack_codegen_executes_core_u8_max_above_signed_boundary() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> u8 {\n    return core::u8::max(255, 128);\n}\n",
    ];
    let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        .expect("x86 source-pack codegen should lower core::u8::max with unsigned ordering");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "x86 source-pack core::u8::max unsigned",
            "core_u8_max_unsigned",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(255));
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_u8_literal_range_predicates() {
    let cases = [
        ("digit_true", "is_ascii_digit", 53u32, 48u32, 57u32, Some(1)),
        (
            "digit_false",
            "is_ascii_digit",
            65u32,
            48u32,
            57u32,
            Some(0),
        ),
        (
            "lowercase_true",
            "is_ascii_lowercase",
            113u32,
            97u32,
            122u32,
            Some(1),
        ),
    ];

    for (name, helper, arg, _lower, _upper, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::u8;\nfn main() -> bool {{\n    return core::u8::{helper}({arg});\n}}\n"
        );
        let sources = [include_str!("../stdlib/core/u8.lani"), user_source.as_str()];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::u8::{helper} {name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::u8::{helper} {name}"),
                &format!("core_u8_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_bool_unary_and_conversion_helpers() {
    let cases = [
        (
            "not_false",
            "fn main() -> bool {\n    return core::bool::not(false);\n}\n",
            0u32,
            0x94u8,
            Some(1),
        ),
        (
            "not_true",
            "fn main() -> bool {\n    return core::bool::not(true);\n}\n",
            1u32,
            0x94u8,
            Some(0),
        ),
        (
            "from_i32_zero",
            "fn main() -> bool {\n    return core::bool::from_i32(0);\n}\n",
            0u32,
            0x95u8,
            Some(0),
        ),
        (
            "from_i32_nonzero",
            "fn main() -> bool {\n    return core::bool::from_i32(9);\n}\n",
            9u32,
            0x95u8,
            Some(1),
        ),
    ];

    for (name, main_body, arg_bits, setcc_opcode, expected_status) in cases {
        let user_source = format!("module app::main;\nimport core::bool;\n{main_body}");
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load unary arg into edi");
        assert_eq!(&bytes[0x79..0x7d], &arg_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x8d..0x92], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x92..0x95], &[0x0f, setcc_opcode, 0xc0]);
        assert_eq!(&bytes[0x95..0x98], &[0x0f, 0xb6, 0xc0]);
        assert_eq!(bytes[0x98], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_bool_binary_helpers() {
    let cases = [
        ("and_true", "core::bool::and(true, true)", Some(1)),
        ("and_false", "core::bool::and(true, false)", Some(0)),
        ("or_true", "core::bool::or(false, true)", Some(1)),
        ("or_false", "core::bool::or(false, false)", Some(0)),
        ("xor_true", "core::bool::xor(true, false)", Some(1)),
        ("xor_false", "core::bool::xor(true, true)", Some(0)),
        ("eq_true", "core::bool::eq(false, false)", Some(1)),
        ("eq_false", "core::bool::eq(true, false)", Some(0)),
    ];

    for (name, call, expected_status) in cases {
        let user_source = format!(
            "module app::main;\nimport core::bool;\nfn main() -> bool {{\n    return {call};\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_source_pack_codegen_executes_core_bool_terminal_param_branches() {
    let to_i32_cases = [
        ("to_i32_true", "true", 1u32, Some(1)),
        ("to_i32_false", "false", 0u32, Some(0)),
    ];

    for (name, arg_source, arg_bits, expected_status) in to_i32_cases {
        let user_source = format!(
            "module app::main;\nimport core::bool;\nfn main() {{\n    return core::bool::to_i32({arg_source});\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load condition into edi");
        assert_eq!(&bytes[0x79..0x7d], &arg_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xe8, "main should call rel32 after arg setup");
        assert_eq!(&bytes[0x7e..0x82], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x8b..0x8d], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x8d..0x92], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x92..0x98], &[0x0f, 0x84, 0x0a, 0, 0, 0]);
        assert_eq!(&bytes[0x98..0x9d], &[0xb8, 1, 0, 0, 0]);
        assert_eq!(&bytes[0x9d..0xa2], &[0xe9, 5, 0, 0, 0]);
        assert_eq!(&bytes[0xa2..0xa7], &[0xb8, 0, 0, 0, 0]);
        assert_eq!(bytes[0xa7], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }

    let select_cases = [
        ("select_true", "true", 1u32, Some(7)),
        ("select_false", "false", 0u32, Some(3)),
    ];

    for (name, condition_source, condition_bits, expected_status) in select_cases {
        let user_source = format!(
            "module app::main;\nimport core::bool;\nfn main() {{\n    return core::bool::select_i32({condition_source}, 7, 3);\n}}\n"
        );
        let sources = [
            include_str!("../stdlib/core/bool.lani"),
            user_source.as_str(),
        ];
        let bytes = pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
            .unwrap_or_else(|err| {
                panic!("x86 source-pack codegen should lower core::bool::{name}: {err}")
            });

        assert_eq!(&bytes[0..4], b"\x7fELF");
        assert_eq!(bytes[0x78], 0xbf, "main should load condition into edi");
        assert_eq!(&bytes[0x79..0x7d], &condition_bits.to_le_bytes());
        assert_eq!(bytes[0x7d], 0xbe, "main should load when_true into esi");
        assert_eq!(&bytes[0x7e..0x82], &7u32.to_le_bytes());
        assert_eq!(bytes[0x82], 0xba, "main should load when_false into edx");
        assert_eq!(&bytes[0x83..0x87], &3u32.to_le_bytes());
        assert_eq!(bytes[0x87], 0xe8, "main should call after three args");
        assert_eq!(&bytes[0x88..0x8c], &9u32.to_le_bytes());
        assert_eq!(&bytes[0x8c..0x8e], &[0x89, 0xc7]);
        assert_eq!(&bytes[0x8e..0x93], &[0xb8, 0x3c, 0, 0, 0]);
        assert_eq!(&bytes[0x93..0x95], &[0x0f, 0x05]);
        assert_eq!(&bytes[0x95..0x97], &[0x89, 0xf8]);
        assert_eq!(&bytes[0x97..0x9c], &[0x3d, 0, 0, 0, 0]);
        assert_eq!(&bytes[0x9c..0xa2], &[0x0f, 0x84, 7, 0, 0, 0]);
        assert_eq!(&bytes[0xa2..0xa4], &[0x89, 0xf0]);
        assert_eq!(&bytes[0xa4..0xa9], &[0xe9, 2, 0, 0, 0]);
        assert_eq!(&bytes[0xa9..0xab], &[0x89, 0xd0]);
        assert_eq!(bytes[0xab], 0xc3);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                &format!("x86 source-pack core::bool::{name}"),
                &format!("core_bool_{name}"),
                &bytes,
            );
            assert_eq!(output.status.code(), expected_status);
        }
    }
}

#[test]
fn x86_explicit_source_pack_paths_emit_direct_elf_for_qualified_scalar_const_return() {
    let stdlib_path =
        common::TempArtifact::new("laniusc_x86_source_pack", "stdlib_core_i32", Some("lani"));
    let user_path = common::TempArtifact::new("laniusc_x86_source_pack", "user_main", Some("lani"));
    stdlib_path.write_str(include_str!("../stdlib/core/i32.lani"));
    user_path.write_str(
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::MAX;\n}\n",
    );
    let stdlib_paths = [stdlib_path.path().to_path_buf()];
    let user_paths = [user_path.path().to_path_buf()];

    let bytes = common::run_gpu_codegen_with_timeout(
        "GPU explicit source-pack path x86 compile",
        move || {
            pollster::block_on(
                compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen(
                    &stdlib_paths,
                    &user_paths,
                ),
            )
        },
    )
    .expect("x86 explicit source-pack path codegen should use the GPU source-pack pipeline");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &2_147_483_647u32.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_true_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return true;\n}\n",
    ))
    .expect("x86 codegen should lower a HIR boolean literal into direct ELF bytes");

    assert_x86_64_elf_entry(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 true literal return",
        "x86_true_literal_return",
        &bytes,
        1,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_false_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return false;\n}\n",
    ))
    .expect("x86 codegen should lower a false HIR literal into direct ELF bytes");

    assert_x86_64_elf_entry(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 false literal return",
        "x86_false_literal_return",
        &bytes,
        0,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_logical_not_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return !false;\n}\n",
    ))
    .expect("x86 codegen should lower HIR logical-not of a boolean literal");

    assert_x86_64_elf_entry(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 logical not return",
        "x86_logical_not_return",
        &bytes,
        1,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_integer_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 1 + 2;\n}\n",
    ))
    .expect("x86 codegen should emit direct ELF bytes for the first binary HIR slice");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 2, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_local_integer_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 7;\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower one scalar local into an executable ELF");

    assert_x86_64_elf_entry(&bytes);

    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 local integer return",
        "x86_local_integer_return",
        &bytes,
        7,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_bool_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: bool = true;\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower scalar locals initialized from HIR boolean literals");

    assert_x86_64_elf_entry(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code("x86 bool local return", "x86_bool_local_return", &bytes, 1);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_logical_not_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: bool = false;\n    return !value;\n}\n",
    ))
    .expect("x86 codegen should lower HIR logical-not of a scalar local");

    assert_x86_64_elf_entry(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 logical not local return",
        "x86_logical_not_local_return",
        &bytes,
        1,
    );
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negative_integer_literal_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return -1;\n}\n",
    ))
    .expect("x86 codegen should lower a HIR unary signed literal into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &u32::MAX.to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negative_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = -3;\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower a scalar local initialized from a HIR unary signed literal");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negated_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 3;\n    return -value;\n}\n",
    ))
    .expect("x86 codegen should lower HIR unary negation of a scalar local");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(bytes[0x7d], 0xbf);
    assert_eq!(&bytes[0x7e..0x82], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x82..0x84], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_local_integer_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 7;\n    return value + 2;\n}\n",
    ))
    .expect("x86 codegen should lower one scalar local binary return into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 7, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 2, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_bool_and_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let left: bool = true;\n    let right: bool = false;\n    return left && right;\n}\n",
    ))
    .expect("x86 codegen should lower bounded boolean and returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x25, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_bool_or_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    return false || true;\n}\n",
    ))
    .expect("x86 codegen should lower bounded boolean or returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x0d, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negated_local_binary_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 3;\n    return -value + 5;\n}\n",
    ))
    .expect("x86 codegen should lower HIR unary local atoms in binary returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8);
    assert_eq!(&bytes[0x79..0x7d], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_two_local_integer_add_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let left: i32 = 7;\n    let right: i32 = 2;\n    return left + right;\n}\n",
    ))
    .expect("x86 codegen should lower two scalar literal locals into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 7, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x05, 2, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x84], &[0x89, 0xc7]);
    assert_eq!(&bytes[0x84..0x89], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x89..0x8b], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_terminal_if_else_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 4;\n    if (value > 3) { return 0; } else { return 1; }\n}\n",
    ))
    .expect("x86 codegen should lower one scalar terminal if/else into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8e, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_terminal_if_else_bool_returns() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: i32 = 4;\n    if (value > 3) { return true; } else { return false; }\n}\n",
    ))
    .expect("x86 codegen should lower HIR boolean literals in terminal branch arms");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8e, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 1, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_terminal_if_else_negative_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = 4;\n    if (value > 3) { return -1; } else { return 0; }\n}\n",
    ))
    .expect("x86 codegen should lower signed scalar atoms in terminal if/else arms");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8e, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 0xff, 0xff, 0xff, 0xff]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_abs_shaped_negated_local_branch() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    let value: i32 = -4;\n    if (value < 0) { return -value; } else { return value; }\n}\n",
    ))
    .expect("x86 codegen should lower an abs-shaped terminal branch over a scalar local");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8);
    assert_eq!(&bytes[0x79..0x7d], &(0u32.wrapping_sub(4)).to_le_bytes());
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x88], &[0x0f, 0x8d, 10, 0, 0, 0]);
    assert_eq!(&bytes[0x88..0x8d], &[0xbf, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x92], &[0xe9, 5, 0, 0, 0]);
    assert_eq!(&bytes[0x92..0x97], &[0xbf, 0xfc, 0xff, 0xff, 0xff]);
    assert_eq!(&bytes[0x97..0x9c], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x9c..0x9e], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_comparison_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: i32 = 4;\n    return value > 3;\n}\n",
    ))
    .expect("x86 codegen should lower one scalar comparison return into direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(
        u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
        0x400078
    );
    assert_eq!(&bytes[0x78..0x7d], &[0xb8, 4, 0, 0, 0]);
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 3, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x85], &[0x0f, 0x9f, 0xc0]);
    assert_eq!(&bytes[0x85..0x88], &[0x0f, 0xb6, 0xf8]);
    assert_eq!(&bytes[0x88..0x8d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x8f], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_emits_direct_elf_for_negated_local_comparison_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() -> bool {\n    let value: i32 = 3;\n    return -value < 0;\n}\n",
    ))
    .expect("x86 codegen should lower HIR unary local atoms in comparison returns");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[0x78], 0xb8);
    assert_eq!(&bytes[0x79..0x7d], &(0u32.wrapping_sub(3)).to_le_bytes());
    assert_eq!(&bytes[0x7d..0x82], &[0x3d, 0, 0, 0, 0]);
    assert_eq!(&bytes[0x82..0x85], &[0x0f, 0x9c, 0xc0]);
    assert_eq!(&bytes[0x85..0x88], &[0x0f, 0xb6, 0xf8]);
    assert_eq!(&bytes[0x88..0x8d], &[0xb8, 0x3c, 0, 0, 0]);
    assert_eq!(&bytes[0x8d..0x8f], &[0x0f, 0x05]);
}

#[test]
fn x86_source_codegen_executes_call_initialized_local_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let value: i32 = id(1);\n    return value;\n}\n",
    ))
    .expect("x86 codegen should lower a call-initialized local through HIR value records");

    assert_x86_64_elf_entry(&bytes);
    assert_x86_text_contains_direct_call(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 call-initialized local return",
        "x86_call_initialized_local_return",
        &bytes,
        1,
    );
}

#[test]
fn x86_source_codegen_executes_nested_hir_expression_return() {
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 1 + 2 + 3;\n}\n",
    ))
    .expect("x86 codegen should lower nested HIR expression returns");

    assert_x86_64_elf_entry(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 nested HIR expression return",
        "x86_nested_hir_expression_return",
        &bytes,
        6,
    );
}

#[test]
fn x86_path_codegen_reads_existing_input_and_emits_elf() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "input", Some("lani"));
    src_path.write_str("fn main() {\n    return 0;\n}\n");

    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        src_path.path(),
    ))
    .expect("x86 path codegen should read source and emit direct ELF bytes");

    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(&bytes[0x7e..0x82], &0u32.to_le_bytes());
}
