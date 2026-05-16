use std::path::Path;

#[test]
fn cli_x86_availability_claims_are_explicitly_narrow_gpu_slice() {
    let main = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs"));
    assert!(
        main.contains("x86_64 currently supports only the direct GPU HIR main-return")
            && main.contains("resolver-backed scalar-const source-pack slices")
    );
    assert!(main.contains("compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen"));
    assert!(!main.contains("x86_64 source-pack compilation is unavailable"));
    assert!(!main.contains("supported targets: wasm, x86_64"));
    assert!(!main.contains("Emits x86_64 ELF or WASM"));
}

#[test]
fn gpu_device_does_not_request_wgpu_fallback_adapter() {
    let device = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/gpu/device.rs"));
    assert!(device.contains("force_fallback_adapter: false"));
    assert!(device.contains("does not allow a CPU compiler fallback"));
}

#[test]
fn cpu_codegen_backends_are_deleted() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for rel in [
        "src/codegen/c.rs",
        "src/codegen/cpu_wasm.rs",
        "src/codegen/cpu_native.rs",
        "src/codegen/gpu_wasm.rs",
        "src/codegen/gpu_x86.rs",
        "src/codegen/gpu_c.rs",
        "shaders/codegen/x86_from_wasm.slang",
        "tests/codegen_c.rs",
        "tests/sample_programs.rs",
    ] {
        assert!(!root.join(rel).exists(), "{rel} should not exist");
    }

    let x86_regalloc = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/shaders/codegen/x86_regalloc.slang"
    ));
    assert!(
        x86_regalloc.contains("StructuredBuffer<uint> x86_live_start")
            && x86_regalloc.contains("RWStructuredBuffer<uint> x86_phys_reg"),
        "x86 regalloc must consume GPU liveness records and write GPU register records"
    );
    assert!(
        !x86_regalloc.contains("visible_decl") && !x86_regalloc.contains("token-index"),
        "x86 regalloc must not restore the deleted fixed token-index visible_decl map"
    );

    let codegen_mod = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/codegen/mod.rs"));
    assert!(codegen_mod.contains("pub mod wasm;"));
    assert!(codegen_mod.contains("pub mod x86;"));
    assert!(!codegen_mod.contains("pub mod gpu_wasm;"));
    assert!(!codegen_mod.contains("pub mod gpu_x86;"));
    assert!(!codegen_mod.contains("pub mod cpu_wasm;"));
    assert!(!codegen_mod.contains("pub mod cpu_native;"));
    assert!(!codegen_mod.contains("pub mod c;"));
    assert!(!codegen_mod.contains("pub mod gpu_c;"));
}

#[test]
fn cpu_parser_and_rust_hir_frontend_are_deleted() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for rel in [
        "src/parser/cpu.rs",
        "src/hir.rs",
        "tests/hir.rs",
        "tests/imports.rs",
        "tests/stdlib.rs",
        "src/bin/parse_gen_golden.rs",
    ] {
        assert!(!root.join(rel).exists(), "{rel} should not exist");
    }

    let lib_mod = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/lib.rs"));
    let parser_mod = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/parser/mod.rs"));
    assert!(!lib_mod.contains("pub mod hir;"));
    assert!(!parser_mod.contains("pub mod cpu;"));
}

#[test]
fn parser_cpu_oracles_are_explicitly_test_only() {
    let tables = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/parser/tables.rs"));
    let parse_fuzz = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/bin/parse_fuzz.rs"
    ));
    assert!(tables.contains("Test-only host LL(1) oracle for parser tests and fuzz tooling"));
    assert!(tables.contains("The compiler must not call this"));
    assert!(tables.contains("test_cpu_ll1_production_stream"));
    assert!(tables.contains("test_cpu_ll1_production_stream_with_positions"));
    assert!(tables.contains("test_cpu_projected_production_stream"));
    assert!(tables.contains("not as a\n/// runtime parser fallback"));
    assert!(parse_fuzz.contains("test_cpu_oracle_only"));
    assert!(!parse_fuzz.contains("cpu_only"));
    assert!(parse_fuzz.contains("not part of the compiler pipeline"));
    assert!(parse_fuzz.contains("test CPU oracles exist only to validate GPU parser passes"));

    for source in [
        include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/compiler.rs")),
        include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs")),
    ] {
        assert!(!source.contains("test_cpu_ll1_production_stream"));
        assert!(!source.contains("test_cpu_projected_production_stream"));
    }

    for golden in [
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/parser_tests/control.parse.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/parser_tests/file.parse.json"
        )),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/parser_tests/function.parse.json"
        )),
    ] {
        assert!(golden.contains("\"test_cpu_oracle_only\": true"));
        assert!(!golden.contains("\"cpu_only\""));
    }
}

#[test]
fn cpu_lexer_oracle_is_explicitly_test_only() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    assert!(!root.join("src/lexer/cpu.rs").exists());
    assert!(!root.join("src/lexer/debug_checks.rs").exists());
    assert!(!root.join("src/lexer/debug_host.rs").exists());

    let lexer_mod = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/lexer/mod.rs"));
    let test_cpu = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/lexer/test_cpu.rs"
    ));
    let lex_fuzz = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/bin/lex_fuzz.rs"));
    assert!(lexer_mod.contains("pub mod test_cpu;"));
    assert!(!lexer_mod.contains("pub mod cpu;"));
    assert!(lexer_mod.contains("TEST-ONLY CPU lexer oracle"));
    assert!(lexer_mod.contains("must not call it or use it as a fallback"));
    assert!(test_cpu.contains("TEST-ONLY CPU lexer oracle"));
    assert!(test_cpu.contains("must not be used as a"));
    assert!(test_cpu.contains("lex_on_test_cpu"));
    assert!(lex_fuzz.contains("not part of the compiler pipeline"));
    assert!(lex_fuzz.contains("test CPU lexer oracle"));

    for source in [
        include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/compiler.rs")),
        include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs")),
        include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/lexer/driver.rs")),
    ] {
        assert!(!source.contains("lex_on_test_cpu"));
        assert!(!source.contains("lexer::test_cpu"));
    }
}

#[test]
fn developer_compile_benchmark_stays_on_wasm_until_x86_is_wired() {
    let bench = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/bin/gpu_compile_bench.rs"
    ));
    assert!(bench.contains("compile_source_to_wasm_with_gpu_codegen_using"));
    assert!(bench.contains("unsupported --emit {other:?}; expected wasm"));
    assert!(!bench.contains("compile_source_to_x86_64_with_gpu_codegen"));
    assert!(!bench.contains("x86_64"));
}

#[test]
fn stdlib_docs_do_not_claim_removed_source_prepasses() {
    for (name, source) in [
        (
            "TODO.md",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/TODO.md")),
        ),
        (
            "stdlib/README.md",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/stdlib/README.md")),
        ),
        (
            "stdlib/PLAN.md",
            include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/stdlib/PLAN.md")),
        ),
        (
            "stdlib/LANGUAGE_REQUIREMENTS.md",
            include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/stdlib/LANGUAGE_REQUIREMENTS.md"
            )),
        ),
        (
            "stdlib/STANDARD_LIBRARY_SPEC.md",
            include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/stdlib/STANDARD_LIBRARY_SPEC.md"
            )),
        ),
    ] {
        for forbidden in [
            "imports are source-level includes expanded before lexing",
            "included explicitly before user code",
            "source expansion rewrites module declarations",
            "namespace bridge",
            "codegen-only scalar lowering",
            "conformance precheck",
            "type-check-only erasure path",
            "These exercise generic struct literals",
            "self receiver method calls",
            "for traversal over range-like seed structs",
            "These can lower as direct WASM imports",
            "lower as direct WASM imports",
            "It parses and imports",
            "Top-level primitive constants are available for source stdlib modules",
            "Generic function-call substitution or monomorphization",
            "type-argument inference/substitution or monomorphization exists",
            "the CPU parser accepts that surface",
            "`src/hir.rs` now provides",
            "GPU x86_64 ELF emission for the current sample-program subset",
            "the default x86_64 CLI path compile directly",
        ] {
            assert!(
                !source.contains(forbidden),
                "{name} still claims removed prepass behavior: {forbidden}"
            );
        }
    }
}
