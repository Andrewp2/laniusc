mod common;

#[test]
fn actual_option_generic_payload_functions_execute_scalar_and_string_instances() {
    for (fixture, stdout) in [
        (
            "option_generic_scalar_payload_functions.lani",
            b"payload\nfallback\n\npayload\npayload\npayload\n".as_slice(),
        ),
        (
            "repro_option_generic_string_payload.lani",
            b"payload\n".as_slice(),
        ),
        (
            "option_generic_string_methods.lani",
            b"payload\nfallback\n\npayload\npayload\npayload\npayload\npayload\npayload\n\n"
                .as_slice(),
        ),
    ] {
        execute_fixture(fixture, stdout);
    }
}

#[test]
fn option_string_payload_methods_execute_all_state_pairs() {
    let states = [
        ("absent", None),
        ("empty", Some("")),
        ("left", Some("left")),
        ("right", Some("different length")),
    ];
    let mut source = String::from(
        "module app::main;\nimport core::option;\nimport std::io;\nfn main() -> i32 {\n",
    );
    for (name, payload) in states {
        let constructor = payload.map_or_else(
            || "core::option::None()".to_owned(),
            |text| format!("core::option::Some(\"{text}\")"),
        );
        source.push_str(&format!(
            "    let {name}: core::option::Option<str> = {constructor};\n"
        ));
    }
    let mut expected_stdout = String::new();
    let mut failure = 1;
    for (left, left_value) in states {
        for (right, right_value) in states {
            for (method, expected) in [
                ("or", left_value.or(right_value)),
                ("and", left_value.and(right_value)),
                ("xor", left_value.xor(right_value)),
            ] {
                source.push_str(&format!("    let selected_{failure}: core::option::Option<str> = {left}.{method}({right});\n"));
                let tag_check = if expected.is_some() {
                    "is_some"
                } else {
                    "is_none"
                };
                source.push_str(&format!(
                    "    if (!selected_{failure}.{tag_check}()) {{ return {failure}; }}\n"
                ));
                source.push_str(&format!("    let text_{failure}: str = selected_{failure}.unwrap_or(\"absent fallback\");\n"));
                let text = expected.unwrap_or("absent fallback");
                source.push_str(&format!(
                    "    if (std::io::println(text_{failure}) != {}) {{ return {failure}; }}\n",
                    text.len() + 1
                ));
                expected_stdout.push_str(text);
                expected_stdout.push('\n');
                failure += 1;
            }
        }
    }
    // Receiver methods must preserve each input, including an empty string.
    for (name, payload) in states {
        source.push_str(&format!("    let preserved_{name}: str = {name}.unwrap_or(\"absent fallback\");\n    std::io::println(preserved_{name});\n"));
        expected_stdout.push_str(payload.unwrap_or("absent fallback"));
        expected_stdout.push('\n');
    }
    source.push_str("    return 0;\n}\n");
    let entry = common::TempArtifact::new("laniusc_option_string_methods", "entry", Some("lani"));
    entry.write_str(&source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("Option string method state pairs", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&path, &stdlib),
            )
        })
        .expect("compile actual generic Option string methods");
    assert_native_stdout(
        "Option string method state pairs",
        &bytes,
        expected_stdout.as_bytes(),
    );
}

#[test]
fn option_string_payload_methods_reject_inconsistent_arguments() {
    for statement in [
        "let text: str = value.unwrap_or(false);",
        "let selected: core::option::Option<str> = value.or(wrong);",
        "let selected: core::option::Option<str> = value.and(wrong);",
        "let selected: core::option::Option<str> = value.xor(wrong);",
    ] {
        let entry = common::TempArtifact::new("laniusc_option_wrong_string", "entry", Some("lani"));
        entry.write_str(&format!("module app::main;\nimport core::option;\nfn main() -> i32 {{\n    let value: core::option::Option<str> = core::option::Some(\"payload\");\n    let wrong: core::option::Option<bool> = core::option::Some(false);\n    {statement}\n    return 0;\n}}\n"));
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let result =
            common::run_gpu_codegen_with_timeout("Option string wrong argument", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&path, &stdlib),
                )
            });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("receiver's str parameter accepted: {statement}"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{statement}: {error:?}"
        );
    }
}

fn execute_fixture(fixture: &str, stdout: &[u8]) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation").join(fixture);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("Option generic scalar payloads", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("instantiate {fixture}: {error:?}"));
    assert_native_stdout(fixture, &bytes, stdout);
}

fn assert_native_stdout(name: &str, bytes: &[u8], stdout: &[u8]) {
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(name, "option_generic_payloads", bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, stdout, "{name}: {output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (name, bytes, stdout);
}
