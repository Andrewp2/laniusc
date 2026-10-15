mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

// Reuse the real I/O module inside the fixture's source root. Imports enforce
// canonical path containment, so a symlink to the repository stdlib is invalid.
struct ReceiverTestStdlib(common::TempArtifact);

impl ReceiverTestStdlib {
    fn new() -> Self {
        let root = common::TempArtifact::new("generated_receivers", "stdlib", None);
        std::fs::create_dir_all(root.path().join("core")).expect("temporary core directory");
        std::fs::create_dir_all(root.path().join("std")).expect("temporary std directory");
        std::fs::write(
            root.path().join("core/five.lani"),
            include_str!("fixtures/stdlib_foundation/repro_generated_receiver_root/core/five.lani"),
        )
        .expect("fixture record module");
        std::fs::write(
            root.path().join("core/relay.lani"),
            include_str!("fixtures/stdlib_foundation/generic_relay.lani"),
        )
        .expect("fixture generic relay module");
        std::fs::write(
            root.path().join("std/io.lani"),
            include_str!("../stdlib/std/io.lani"),
        )
        .expect("real I/O module");
        Self(root)
    }
}

impl Drop for ReceiverTestStdlib {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(self.0.path());
    }
}

#[test]
fn native_compilation_preserves_generic_and_plain_programs_in_one_workspace() {
    common::run_gpu_codegen_with_timeout("native compilation workspace transitions", || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
            .expect("GPU compiler");
        for _ in 0..2 {
            for (label, source, expected) in [
                (
                    "generated five argument types across workspace jobs",
                    include_str!(
                        "fixtures/stdlib_foundation/repro_generic_generated_five_arguments.lani"
                    ),
                    0,
                ),
                (
                    "nested generic constructors before plain jobs",
                    "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> } fn wrap<T>(value: T) -> Holder<T> { return Holder { child: Cell { value: value } }; } fn main() -> i32 { let number: Holder<i32> = wrap(46); let flag: Holder<bool> = wrap(false); if (flag.child.value) { return 1; } return number.child.value; }",
                    46,
                ),
                (
                    "generic scalar operators after compound jobs",
                    "fn choose<T>(left: T, right: T, first: bool) -> T { if (first) { return left; } return right; } fn main() -> i32 { if (choose(-2147483648, 2147483647, true) != -2147483648 || choose(false, true, true)) { return 1; } return 42; }",
                    42,
                ),
                (
                    "constant environments before plain jobs",
                    "fn keep<const N: usize>(v: [i32; N]) -> [i32; N] { return v; } fn main() -> i32 { let a: [i32; 2] = [40, 2]; let b: [i32; 3] = [41, 3, 1]; let x: [i32; 2] = keep(a); let y: [i32; 3] = keep(b); return x[0] + x[1] + y[2] - 1; }",
                    42,
                ),
                (
                    "explicit symbolic constants across workspace transitions",
                    "fn length<const N: usize>() -> usize { return N; } fn relay<const N: usize>() -> usize { return length<N>(); } fn main() -> i32 { if (relay<0>() != 0 || relay<3>() != 3) { return 1; } return 42; }",
                    42,
                ),
                (
                    "result-only constants before plain jobs",
                    "enum Length<T> { Known(usize), Values(T) } fn length<const N: usize>() -> Length<[i32; N]> { return Known(N); } fn main() -> i32 { let v: Length<[i32; 4]> = length(); let n: usize = match (v) { Known(n) => n, Values(v) => 99 }; if (n != 4) { return 1; } return 42; }",
                    42,
                ),
                (
                    "normalized mixed aliases before plain jobs",
                    include_str!("fixtures/stdlib_compiler_state/alias-type-probes/mixed-composition-alias.lani"),
                    0,
                ),
                (
                    "constant-only aliases across workspace transitions",
                    include_str!("fixtures/stdlib_compiler_state/alias-type-probes/constant-only-alias.lani"),
                    0,
                ),
                (
                    "normalized constructor bindings across workspace transitions",
                    include_str!("fixtures/stdlib_compiler_state/alias-member-probes/reordered.lani"),
                    0,
                ),
                (
                    "concrete alias unit bindings across workspace transitions",
                    include_str!("fixtures/stdlib_compiler_state/alias-member-probes/called-unit.lani"),
                    0,
                ),
                (
                    "plain comparisons",
                    "fn main() -> i32 { let n: i32 = 4; if (n < 5) { return 41; } return 1; }",
                    41,
                ),
                (
                    "plain inferred scalar calls after generic jobs",
                    "fn next(v: i32) -> i32 { return v + 1; } fn flag(v: bool) -> bool { return v; } fn amount() -> f32 { return 2.5; } fn main() -> i32 { let first = next(-7); let second = next(first); let stopped = flag(false); let value = amount(); if (stopped || value != 2.5) { return 1; } return second + 47; }",
                    42,
                ),
                (
                    "generic value",
                    "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { return keep(42); }",
                    42,
                ),
                (
                    "plain array return",
                    "fn pair(v: i32) -> [i32; 2] { return [v, v + 1]; } fn main() -> i32 { let p: [i32; 2] = pair(4); return p[0] * 10 + p[1]; }",
                    45,
                ),
            ] {
                let bytes = pollster::block_on(compiler.compile_source_to_x86_64(source))
                    .unwrap_or_else(|error| {
                        panic!("{label}: compile in reused workspace: {error:?}")
                    });
                let output = common::run_x86_64_elf_output(label, "generic_workspace", &bytes);
                assert_eq!(output.status.code(), Some(expected), "{label}: {output:?}");
                assert!(
                    output.stdout.is_empty() && output.stderr.is_empty(),
                    "{label}: {output:?}"
                );
            }
        }
    });
}

#[test]
fn generic_impl_sibling_replay_preserves_local_helpers_across_workspace_reuse() {
    common::run_gpu_codegen_with_timeout("generic impl sibling replay workspace", || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
            .expect("GPU compiler");
        for (label, source, expected) in [
            (
                "selected generic method with an uncalled generic sibling",
                include_str!("fixtures/stdlib_foundation/sibling_publication/minimal.lani"),
                0,
            ),
            (
                "generic siblings retain ordinary local helper code and generic calls",
                include_str!("fixtures/stdlib_foundation/sibling_publication/local-helper.lani"),
                0,
            ),
            (
                "ordinary native compilation after generic method replay",
                "fn next(value: i32) -> i32 { return value + 1; } fn main() -> i32 { let value = next(40); if (next(value) != 42) { return 1; } return 42; }",
                42,
            ),
        ] {
            let bytes = pollster::block_on(compiler.compile_source_to_x86_64(source))
                .unwrap_or_else(|error| panic!("{label}: compile in reused workspace: {error:?}"));
            let output = common::run_x86_64_elf_output(label, "sibling_workspace", &bytes);
            assert_eq!(output.status.code(), Some(expected), "{label}: {output:?}");
            assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{label}: {output:?}");
        }
    });
}

#[test]
fn generic_impl_sibling_replay_preserves_ordinary_imported_helpers() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/sibling_publication/imported/stdlib");
    execute_with_stdlib(
        "ordinary imported helper from selected generic methods",
        include_str!("fixtures/stdlib_foundation/sibling_publication/imported/main.lani"),
        &root,
        b"",
        0,
    );
}

#[test]
fn generic_impl_sibling_replay_preserves_method_and_impl_constants() {
    execute(
        "sibling methods with independent type and constant environments",
        include_str!("fixtures/stdlib_foundation/sibling_publication/method-and-impl-constants.lani"),
    );
}

#[test]
fn structural_inherent_reference_cells_preserve_place_identity() {
    common::run_gpu_codegen_with_timeout("structural reference cells and workspace reuse", || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
            .expect("GPU compiler");
        for (label, source, expected) in [
            (
                "structural method reference cells and generic forwarding",
                include_str!("fixtures/stdlib_foundation/structural_inherent/reference-cells.lani"),
                0,
            ),
            (
                "ordinary scalar compilation after address-bearing generic replay",
                "fn next(value:i32)->i32{return value+1;} fn main()->i32{return next(next(40));}",
                42,
            ),
        ] {
            let bytes = pollster::block_on(compiler.compile_source_to_x86_64(source))
                .unwrap_or_else(|error| panic!("{label}: compile in reused workspace: {error:?}"));
            let output = common::run_x86_64_elf_output(label, "structural_receiver_workspace", &bytes);
            assert_eq!(output.status.code(), Some(expected), "{label}: {output:?}");
            assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{label}: {output:?}");
        }
    });
}

#[test]
fn structural_inherent_adjusted_values_preserve_copy_and_argument_order() {
    execute(
        "structural method adjusted values and argument capture",
        include_str!("fixtures/stdlib_foundation/structural_inherent/owned-receivers-and-borrowed-payloads.lani"),
    );
}

#[test]
fn structural_inherent_loop_values_keep_array_and_slice_shapes() {
    execute(
        "literal, generic fixed-array and slice loops retain value shapes",
        include_str!("fixtures/stdlib_foundation/structural_inherent/loop-value-shapes.lani"),
    );
}

#[test]
fn structural_inherent_unused_receivers_preserve_following_arguments() {
    execute(
        "unused implicit and explicit receivers preserve following arguments",
        include_str!("fixtures/stdlib_foundation/structural_inherent/unused-receiver-arity.lani"),
    );
}

#[test]
fn structural_inherent_deep_receivers_preserve_capture_order() {
    execute(
        "deep receiver adjustment before later argument effects",
        include_str!("fixtures/stdlib_foundation/structural_inherent/deep-receiver-order.lani"),
    );
}

#[test]
fn structural_inherent_array_parameters_copy_into_stable_places() {
    execute(
        "packed array parameters initialize canonical borrowed locals",
        include_str!("fixtures/stdlib_foundation/structural_inherent/array-parameter-place-copy.lani"),
    );
}

#[test]
fn structural_inherent_reference_indexes_preserve_aliases_and_stride() {
    execute(
        "one and two reference array and slice indexing",
        include_str!("fixtures/stdlib_foundation/structural_inherent/reference-index-aliases.lani"),
    );
}

#[test]
fn structural_inherent_reference_array_indexes_reject_negative_bounds() {
    execute_with_status("reference array negative bound", r#"
impl [i32; 3] { fn borrow(&self) -> &[i32; 3] { return self; } }
fn read(values: &[i32; 3], index: i32) -> i32 { return values[index]; }
fn main() -> i32 {
    let values: [i32; 3] = [11, 13, 17];
    let reference: &[i32; 3] = values.borrow();
    return read(reference, -1);
}
"#, b"", 101);
}

#[test]
fn structural_inherent_reference_slice_indexes_reject_upper_bounds() {
    execute_with_status("double reference slice upper bound", r#"
impl [i32] { fn borrow(&self) -> &[i32] { return self; } }
impl &[i32] { fn outer(&self) -> & &[i32] { return self; } }
fn view(values: [i32]) -> [i32] { return values; }
fn read(values: & &[i32], index: i32) -> i32 { return values[index]; }
fn main() -> i32 {
    let backing: [i32; 3] = [19, 23, 29];
    let values: [i32] = view(backing);
    let reference: &[i32] = values.borrow();
    let outer: & &[i32] = reference.outer();
    return read(outer, 3);
}
"#, b"", 101);
}

#[test]
fn structural_inherent_imported_methods_rank_by_reference_depth() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/structural_inherent/imported/stdlib");
    execute_with_stdlib(
        "structural methods rank local and imported reference levels together",
        include_str!("fixtures/stdlib_foundation/structural_inherent/imported/main.lani"),
        &root,
        b"",
        0,
    );
}

#[test]
fn structural_inherent_imported_scalar_methods_execute_without_local_methods() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/structural_inherent/imported_scalar/stdlib");
    // The source-pack scheduler checks the provider's local impl before the
    // caller, whose local method inventory is empty.
    execute_with_stdlib(
        "imported scalar receiver and following argument with no local methods",
        include_str!("fixtures/stdlib_foundation/structural_inherent/imported_scalar/main.lani"),
        &root,
        b"",
        75,
    );
}

fn execute(label: &str, source: &str) {
    execute_with_stdout(label, source, b"");
}

fn execute_with_stdout(label: &str, source: &str, expected: &[u8]) {
    execute_with_status(label, source, expected, 0);
}

fn execute_with_status(label: &str, source: &str, expected: &[u8], status: i32) {
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    execute_with_stdlib(label, source, &stdlib, expected, status);
}

fn execute_with_stdlib(
    label: &str,
    source: &str,
    stdlib: &std::path::Path,
    expected: &[u8],
    status: i32,
) {
    let entry = common::TempArtifact::new("generic_types", label, Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let stdlib = stdlib.to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
    .unwrap_or_else(|error| panic!("{label}: compile: {error:?}"));
    let output = common::run_x86_64_elf_output(label, "generic_types", &bytes);
    assert_eq!(output.status.code(), Some(status), "{label}: {output:?}");
    assert_eq!(output.stdout, expected, "{label}: {output:?}");
    assert!(output.stderr.is_empty(), "{label}: {output:?}");
}

#[test]
fn imported_trait_contract_records_preserve_ordinary_generic_execution() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_compiler_state/imported-trait-contract/stdlib");
    execute_with_stdlib("generic values alongside imported trait contracts",
        include_str!("fixtures/stdlib_compiler_state/imported-trait-contract/portable-values.lani"),
        &root, b"", 0);
}

fn imported_trait_root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_compiler_state/imported-trait-resolution/stdlib")
}

fn reject_imported_trait_program(label: &str, source: &str, code: &str) {
    let entry = common::TempArtifact::new("imported_trait", label, Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let root = imported_trait_root();
    let error = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    }).err().unwrap_or_else(|| panic!("{label}: invalid imported contract emitted an executable"));
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, code, "{label}: {error:?}");
    assert!(diagnostic.primary_label.is_some(), "{label}: {error:?}");
}

#[test]
fn imported_trait_contracts_execute_caller_owned_compound_methods() {
    execute_with_stdlib("imported trait compound method contracts",
        include_str!("fixtures/stdlib_compiler_state/imported-trait-resolution/compound-methods-bound-argument.lani"),
        &imported_trait_root(), b"", 0);
    execute_with_stdlib("imported trait direct compound method arguments",
        include_str!("fixtures/stdlib_compiler_state/imported-trait-resolution/compound-methods.lani"),
        &imported_trait_root(), b"", 0);
}

#[test]
fn imported_trait_keys_normalize_paths_and_preserve_defining_unit_identity() {
    let source = r#"import core::trait_api;
pub impl Rel<core::trait_api::Cell<[i32; 0]>> for bool {}
fn keep<T>(value:T)->T where T:core::trait_api::Rel<core::trait_api::Cell<[i32;0]>> {return value;}
fn main()->i32 {if(keep(false)){return 1;}return 0;}
"#;
    execute_with_stdlib("normalized imported trait paths", source, &imported_trait_root(), b"", 0);
    reject_imported_trait_program("duplicate imported trait paths", &source.replace(
        "fn keep<T>", "pub impl core::trait_api::Rel<core::trait_api::Cell<[i32;0]>> for bool {}\nfn keep<T>"), "LNC0021");
    reject_imported_trait_program("different imported trait unit", &source.replace(
        "import core::trait_api;", "import core::trait_api; import core::trait_peer;").replace(
        "impl Rel<", "impl core::trait_api::Rel<").replace(
        "T:core::trait_api::Rel", "T:core::trait_peer::Rel"), "LNC0008");
    reject_imported_trait_program("empty element identity in imported trait", &source.replace(
        "T:core::trait_api::Rel<core::trait_api::Cell<[i32;0]>>",
        "T:core::trait_api::Rel<core::trait_api::Cell<[bool;0]>>"), "LNC0008");
}

#[test]
fn imported_trait_methods_reject_incomplete_and_incompatible_contracts() {
    for (label, argument, methods) in [
        ("missing method", "i32", ""),
        ("extra method", "i32", "pub fn echo(self,value:i32)->i32{return value;} pub fn extra(self){}"),
        ("duplicate method", "i32", "pub fn echo(self,value:i32)->i32{return value;} pub fn echo(self,value:i32)->i32{return value;}"),
        ("wrong receiver", "i32", "pub fn echo(&self,value:i32)->i32{return value;}"),
        ("wrong visibility", "i32", "fn echo(self,value:i32)->i32{return value;}"),
        ("wrong arity", "i32", "pub fn echo(self,value:i32,extra:bool)->i32{return value;}"),
        ("wrong return", "i32", "pub fn echo(self,value:i32)->bool{return false;}"),
        ("wrong nested element", "core::trait_api::Cell<[i32;2]>", "pub fn echo(self,value:core::trait_api::Cell<[bool;2]>)->core::trait_api::Cell<[bool;2]>{return value;}"),
        ("wrong nested length", "core::trait_api::Cell<[i32;2]>", "pub fn echo(self,value:core::trait_api::Cell<[i32;3]>)->core::trait_api::Cell<[i32;3]>{return value;}"),
        ("wrong empty element", "[i32;0]", "pub fn echo(self,value:[bool;0])->[bool;0]{return value;}"),
    ] {
        let source = format!("import core::trait_api; pub impl core::trait_api::Echo<{argument}> for bool {{{methods}}} fn main()->i32{{return 0;}}");
        reject_imported_trait_program(label, &source, "LNC0021");
    }
    reject_imported_trait_program("type in imported constant slot",
        include_str!("fixtures/stdlib_compiler_state/imported-trait-resolution/type-in-constant-slot.lani"), "LNC0021");
}

#[test]
fn imported_trait_bounds_preserve_all_thirty_two_ordered_graphs() {
    let source = include_str!("fixtures/stdlib_compiler_state/imported-trait-resolution/thirty-two-arguments.lani");
    execute_with_stdlib("32 imported trait operands", source, &imported_trait_root(), b"", 0);
    reject_imported_trait_program("last imported trait operand",
        &source.replace("[bool;0]> {return value;}", "[i32;0]> {return value;}"), "LNC0008");
}

#[test]
fn local_generic_value_functions_execute_distinct_scalar_types() {
    execute(
        "local scalar environments",
        r#"
module app::main;
fn keep<T>(value: T) -> T { return value; }
pub fn choose<T>(left: T, right: T, use_left: bool) -> T {
    if (use_left) { return left; }
    return right;
}

fn main() -> i32 {
    if (keep(-7) != -7 || keep(false)) { return 1; }
    if (choose(-2147483648, 2147483647, true) != -2147483648) { return 2; }
    if (choose(false, true, true) || !choose(false, true, false)) { return 3; }
    if (keep(2.5) != 2.5 || keep('Ω') != 'Ω') { return 4; }
    return 0;
}
"#,
    );
}

#[test]
fn transparent_aliases_preserve_scalar_and_array_values() {
    for (label, source) in [
        ("direct scalar", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/scalar-direct.lani")),
        ("aliased scalar", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/scalar-alias.lani")),
        ("direct array", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/array-direct.lani")),
        ("aliased array", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/array-alias.lani")),
    ] {
        execute(label, source);
    }
}

#[test]
fn generic_aliases_preserve_nominal_forwarding() {
    execute("direct nominal forwarding", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/nominal-direct.lani"));
    execute("aliased nominal forwarding", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/nominal-alias.lani"));
}

#[test]
fn generic_aliases_preserve_slice_arguments_and_results() {
    execute("direct slice forwarding", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/slice-direct.lani"));
    execute("aliased slice forwarding", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/slice-alias.lani"));
}

#[test]
fn generic_aliases_substitute_reordered_record_parameters() {
    execute("direct reordered record", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/reordered-direct.lani"));
    execute("aliased reordered record", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/reordered-alias.lani"));
}

#[test]
fn alias_qualified_enum_constructors_preserve_parent_arguments() {
    execute("direct enum qualifier", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/qualifier-direct.lani"));
    execute("aliased enum qualifier", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/qualifier-alias.lani"));
}

fn execute_imported_alias_probe(case: &str) {
    let fixture = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_compiler_state/alias-import-probes").join(case);
    for form in ["direct", "alias"] {
        let source = std::fs::read_to_string(fixture.join(format!("{form}.lani")))
            .expect("retained imported alias probe");
        execute_with_stdlib(&format!("imported {case} {form}"), &source,
            &fixture.join("stdlib"), b"", 0);
    }
}

#[test]
fn imported_transparent_aliases_preserve_scalar_values() {
    execute_imported_alias_probe("scalar");
}

#[test]
fn imported_generic_aliases_substitute_identity_targets() {
    execute_imported_alias_probe("identity");
}

#[test]
fn imported_generic_aliases_substitute_array_targets() {
    execute_imported_alias_probe("array");
}

#[test]
fn imported_generic_aliases_substitute_reordered_record_targets() {
    execute_imported_alias_probe("reordered");
}

#[test]
fn imported_generic_aliases_substitute_slice_targets() {
    execute_imported_alias_probe("slice");
}

#[test]
fn imported_alias_qualified_constructors_preserve_parent_arguments() {
    execute_imported_alias_probe("qualifier");
}

fn imported_alias_member_stdlib() -> ReceiverTestStdlib {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/members.lani"),
        include_str!("fixtures/stdlib_compiler_state/alias-import-members/members.lani"))
        .expect("imported alias member declarations");
    std::fs::write(stdlib.0.path().join("core/reexport.lani"), r#"
module core::reexport;
import core::members;
pub type Numbers<const N: usize> = core::members::Numbers<N>;
pub type Items<T, const N: usize> = core::members::Items<T, N>;
pub fn total(value: Numbers<2>) -> i32 { return core::members::total(value); }
pub fn missing(value: Numbers<0>) -> bool { return core::members::missing(value); }
"#).expect("member alias reexports");
    stdlib
}

#[test]
fn imported_alias_constructors_preserve_reordered_compound_and_constant_arguments() {
    let stdlib = imported_alias_member_stdlib();
    execute_with_stdlib("imported normalized constructor arguments", r#"
import core::members;
type Local<T, const N: usize> = core::members::Swap<bool, T, N>;
fn make<T, const N: usize>(values: [T; N]) -> core::members::Packet<T, N, bool> {
    return Local<T, N>::Data(values, false);
}
fn main() -> i32 {
    let pair = core::members::Flip<bool, [i32; 2]>::Both([19, 23], false);
    let first = match (pair) { core::members::Pair::Both(values, flag) -> values[0] + values[1], _ -> 0 };
    let flag = match (pair) { core::members::Pair::Both(values, flag) -> flag, _ -> true };
    let packet = core::members::Numbers<2>::Data([20, 22], false);
    let symbolic = make<i32, 2>([18, 24]);
    if (flag || first != 42 || core::members::total(packet) != 42 ||
        core::members::total(symbolic) != 42) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
}

#[test]
fn imported_alias_constructors_preserve_concrete_and_empty_unit_parents() {
    let stdlib = imported_alias_member_stdlib();
    execute_with_stdlib("imported concrete alias without written type operands", r#"
import core::members;
fn main() -> i32 {
    let value = core::members::Number::Both(42, false);
    let number = match (value) { core::members::Pair::Both(number, flag) -> number, _ -> 0 };
    let flag = match (value) { core::members::Pair::Both(number, flag) -> flag, _ -> true };
    if (flag || number != 42) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
    execute_with_stdlib("imported alias bare and called units", r#"
import core::members;
type Local = core::members::Numbers<0>;
fn main() -> i32 {
    let bare = core::members::Number::Empty;
    let called = core::members::Number::Empty();
    let local = Local::Missing;
    let generic = core::members::Numbers<0>::Missing();
    if (!(match (bare) { core::members::Pair::Empty -> true, _ -> false }) ||
        !(match (called) { core::members::Pair::Empty -> true, _ -> false }) ||
        !core::members::missing(local) || !core::members::missing(generic)) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
}

#[test]
fn reexported_alias_constructors_resolve_members_without_importing_the_target_module() {
    let stdlib = imported_alias_member_stdlib();
    execute_with_stdlib("reexported member target identity", r#"
import core::reexport;
fn main() -> i32 {
    let value = core::reexport::Numbers<2>::Data([19, 23], false);
    let empty = core::reexport::Numbers<0>::Missing;
    if (core::reexport::total(value) != 42 || !core::reexport::missing(empty)) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
}

#[test]
fn imported_alias_associated_methods_preserve_complete_receiver_and_own_arguments() {
    let stdlib = imported_alias_member_stdlib();
    execute_with_stdlib("imported alias associated methods", r#"
import core::members;
import core::reexport;
type Local = core::members::Items<i32, 2>;
fn main() -> i32 {
    let direct = core::members::Cell<[i32; 2]>::make([19, 23]);
    let aliased = core::members::Items<i32, 2>::make([20, 22]);
    let local = Local::make([18, 24]);
    let reexported = core::reexport::Items<i32, 2>::make([21, 21]);
    let truth = core::members::Truth::make(false);
    let values = aliased.read();
    let chosen = core::members::Items<i32, 2>::choose<bool>([1, 2], false);
    if (truth.read() || chosen || direct.value[0] + direct.value[1] != 42 ||
        values[0] + values[1] != 42 || local.value[0] + local.value[1] != 42 ||
        reexported.value[0] + reexported.value[1] != 42) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
}

#[test]
fn imported_alias_constructors_preserve_thirty_two_injected_operands() {
    let stdlib = ReceiverTestStdlib::new();
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let mut operands = vec!["[[str; 0]; 0]"; 32];
    operands[0] = "[i32; 2]";
    operands[31] = "bool";
    std::fs::write(stdlib.0.path().join("core/wide.lani"), format!(
        "module core::wide; pub enum Wide<{parameters}> {{ Data(T0, T31), Missing }} pub type Concrete = Wide<{}>;",
        operands.join(", "))).expect("wide imported concrete alias");
    execute_with_stdlib("thirty two injected imported parent operands", r#"
import core::wide;
fn main() -> i32 {
    let value = core::wide::Concrete::Data([19, 23], false);
    let copy = value;
    value = core::wide::Concrete::Missing();
    let total = match (copy) { core::wide::Wide::Data(values, flag) -> values[0] + values[1], _ -> 0 };
    let flag = match (copy) { core::wide::Wide::Data(values, flag) -> flag, _ -> true };
    if (total != 42 || flag || !(match (value) { core::wide::Wide::Missing -> true, _ -> false })) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
}

#[test]
fn imported_alias_associated_methods_reject_receiver_and_own_argument_conflicts() {
    let stdlib = imported_alias_member_stdlib();
    for expression in [
        "core::members::Truth::make(42)",
        "core::members::Items<i32, 2>::make([false, true])",
        "core::members::Items<i32, 2>::make([1, 2, 3])",
        "core::members::Items<i32, 2>::choose<bool>([1, 2], 42)",
        "core::members::Items<i32, 2>::choose<bool, i32>([1, 2], false)",
    ] {
        let entry = common::TempArtifact::new("imported_alias_method_reject", "entry", Some("lani"));
        entry.write_str(&format!("import core::members; fn main() -> i32 {{ let v = {expression}; return 0; }}"));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("invalid imported alias associated method", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        }).err().unwrap_or_else(|| panic!("{expression} emitted an ELF"));
        let diagnostic = error.to_public_diagnostic();
        assert!(matches!(diagnostic.code.as_str(), "LNC0006" | "LNC0027"),
            "{expression}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{expression}: {error:?}");
    }
}

#[test]
fn imported_alias_constructors_reject_conflicting_and_invalid_applications() {
    let stdlib = imported_alias_member_stdlib();
    let mut accepted = Vec::new();
    for expression in [
        "let v = core::members::Number::Both(false, 42);",
        "let v: core::members::Pair<bool, i32> = core::members::Number::Empty;",
        "let v: core::members::Pair<bool, i32> = core::members::Number::Empty();",
        "let v = core::members::Flip<bool, i32>::Both(false, 42);",
        "let v = core::members::Flip<bool>::Empty();",
        "let v = core::members::Flip<bool, i32>::Empty<bool, i32>();",
        "let v = core::members::Numbers<2>::Data([1, 2, 3], false);",
        "let v = core::members::Numbers<bool>::Missing();",
    ] {
        let entry = common::TempArtifact::new("imported_member_reject", "entry", Some("lani"));
        entry.write_str(&format!("import core::members; fn main() -> i32 {{ {expression} return 0; }}"));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let result = common::run_gpu_codegen_with_timeout("invalid imported alias member", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        });
        let error = match result {
            Ok(_) => { accepted.push(expression); continue; }
            Err(error) => error,
        };
        let diagnostic = error.to_public_diagnostic();
        assert!(matches!(diagnostic.code.as_str(), "LNC0005" | "LNC0006" | "LNC0027"),
            "{expression}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{expression}: {error:?}");
    }
    assert!(accepted.is_empty(), "invalid alias member applications were accepted: {accepted:?}");
}

fn imported_alias_composition_stdlib() -> ReceiverTestStdlib {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/aliases.lani"),
        include_str!("fixtures/stdlib_compiler_state/alias-import-composition/aliases.lani"))
        .expect("complete imported alias templates");
    stdlib
}

#[test]
fn explicit_slice_arguments_preserve_local_imported_alias_and_method_borrows() {
    let stdlib = imported_alias_composition_stdlib();
    for (name, source) in [
        ("ordinary", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/ordinary.lani")),
        ("structural", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/structural.lani")),
        ("local", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/local.lani")),
        ("imported", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/imported.lani")),
        ("alias", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/alias.lani")),
        ("method", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/method.lani")),
    ] {
        execute_with_stdlib(name, source, stdlib.0.path(), b"", 0);
    }
}

#[test]
fn explicit_slice_arguments_preserve_compound_storage_and_symbolic_elements() {
    let stdlib = imported_alias_composition_stdlib();
    execute_with_stdlib("compound explicit slice arguments",
        include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/compositions.lani"),
        stdlib.0.path(), "Ω\nC\n".as_bytes(), 0);
}

#[test]
fn imported_alias_constructors_preserve_behavior_after_workspace_growth() {
    // The larger imported program enables additional scratch families. The
    // following smaller job must have the same logical table bounds as a cold
    // compilation, even when coloring reuses a larger physical slot.
    execute("workspace growth before alias constructor", include_str!(
        "fixtures/stdlib_compiler_state/method-result-contract/alias-workspace-warmup.lani"));
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/views.lani"),
        "module core::views; pub enum View<T> { Present(T, i32) } pub type Numbers = View<[i32]>;")
        .expect("imported enum and concrete alias");
    for _ in 0..2 {
        execute_with_stdlib("alias constructor after workspace growth", include_str!(
            "fixtures/stdlib_compiler_state/method-result-contract/alias-workspace-entry.lani"),
            stdlib.0.path(), b"", 0);
    }
}

#[test]
fn slice_enum_payloads_borrow_arrays_and_preserve_following_fields() {
    for (name, source) in [
        ("ordinary enum slice", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/enum-ordinary.lani")),
        ("structural enum slice", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/enum-structural.lani")),
        ("bound enum slice", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/enum_constructor.lani")),
    ] {
        execute(name, source);
    }
    let stdlib = imported_alias_composition_stdlib();
    std::fs::write(stdlib.0.path().join("core/views.lani"),
        "module core::views; pub enum View<T> { Present(T, i32) } pub type Numbers = View<[i32]>;")
        .expect("imported slice payload and concrete alias");
    for qualifier in ["core::views::View<[i32]>", "core::views::Numbers"] {
        execute_with_stdlib("imported enum slice payload", &format!(r#"
import core::views;
fn main() -> i32 {{
    let data: [i32; 2] = [19, 23];
    let wrapped = {qualifier}::Present(data, 7);
    let view = match (wrapped) {{ core::views::View::Present(values, tail) -> values }};
    let tail = match (wrapped) {{ core::views::View::Present(values, tail) -> tail }};
    view[0] = 20;
    data[1] = 22;
    if (tail != 7 || view[0] + view[1] != 42 || data[0] != 20) {{ return 1; }}
    return 0;
}}
"#), stdlib.0.path(), b"", 0);
    }
}

#[test]
fn explicit_slice_arguments_borrow_temporary_arrays() {
    execute("temporary array borrow", include_str!("fixtures/stdlib_compiler_state/explicit-slice-borrow/literal.lani"));
}

#[test]
fn explicit_slice_arguments_reject_element_nested_and_result_conversions() {
    let stdlib = imported_alias_composition_stdlib();
    for expression in [
        "let data: [i32; 2] = [19, 23]; let view = keep<[bool]>(data);",
        "let data: [i32; 2] = [19, 23]; let view = core::aliases::keep<[bool]>(data);",
        "let data: [i32; 2] = [19, 23]; let view: [i32; 2] = core::aliases::keep<[i32]>(data);",
        "let data: Cell<[i32; 2]> = Cell { value: [19, 23] }; let view = keep<Cell<[i32]>>(data);",
        "let data: [A; 1] = [A { value: 42 }]; let view = keep<[B]>(data);",
        "let data: [i32; 2] = [19, 23]; let view = View<[bool]>::Present(data);",
    ] {
        let entry = common::TempArtifact::new("explicit_slice_reject", "entry", Some("lani"));
        entry.write_str(&format!(r#"
import core::aliases;
struct Cell<T> {{ value: T }}
struct A {{ value: i32 }}
struct B {{ value: i32 }}
enum View<T> {{ Present(T) }}
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{ {expression} return 0; }}
"#));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("invalid slice argument conversion", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        }).err().unwrap_or_else(|| panic!("invalid conversion emitted an executable: {expression}"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{expression}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{expression}: {error:?}");
    }
}

#[test]
fn imported_identity_aliases_specialize_complete_values_in_generic_bodies() {
    let stdlib = imported_alias_composition_stdlib();
    execute_with_stdlib("qualified identity alias replay",
        include_str!("fixtures/stdlib_compiler_state/alias-import-composition/symbolic-identity.lani"),
        stdlib.0.path(), "Ω\n".as_bytes(), 0);
}

#[test]
fn imported_identity_aliases_reject_conflicting_body_and_call_types() {
    let stdlib = imported_alias_composition_stdlib();
    for (signature, body, call) in [
        ("fn keep<A, B>(v: core::aliases::Id<A>) -> core::aliases::Id<B>",
            "return v;", "let v = keep<i32, bool>(42);"),
        ("fn keep<T>(v: core::aliases::Id<T>) -> core::aliases::Id<T>",
            "return v;", "let v: bool = keep<i32>(42);"),
        ("fn keep<T>(v: core::aliases::Id<T>) -> core::aliases::Id<T>",
            "return v;", "let v = keep<[i32; 2]>([19, 23, 7]);"),
        ("fn keep<T>(v: core::aliases::Id<T>) -> core::aliases::Id<T>",
            "return v;", "let v = keep<bool>(42);"),
    ] {
        let entry = common::TempArtifact::new("imported_alias_replay_reject", "entry", Some("lani"));
        entry.write_str(&format!("import core::aliases; {signature} {{ {body} }} fn main() -> i32 {{ {call} return 0; }}"));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("qualified alias replay rejection", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        }).err().unwrap_or_else(|| panic!("conflicting alias types emitted an executable: {signature}; {call}"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{signature}; {call}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{signature}; {call}: {error:?}");
    }
}

#[test]
fn imported_generic_aliases_preserve_nested_local_and_imported_compositions() {
    let stdlib = imported_alias_composition_stdlib();
    execute_with_stdlib("nested imported alias compositions", r#"
import core::aliases;
import std::io;
type Local<T> = core::aliases::Id<core::aliases::Fixed<T, 2>>;
struct Cell<T> { value: T }
impl<T> Cell<T> { fn borrow(&self) -> &Cell<T> { return self; } }
fn view<T>(value: core::aliases::View<T>) -> core::aliases::Id<core::aliases::View<T>> { return value; }
fn main() -> i32 {
    let data: Local<i32> = [19, 23];
    let original: core::aliases::Id<core::aliases::Nested<i32, str>> =
        core::aliases::Pair { first: "Ω", second: data };
    let saved = core::aliases::keep(original);
    original.second[0] = -9;
    let injected: core::aliases::Inject<Local<i32>> =
        core::aliases::Pair { first: false, second: saved.second };
    if (saved.second[0] != 19 || injected.first || injected.second[1] != 23) { return 1; }
    let borrowed: core::aliases::Id<core::aliases::View<i32>> = view(data);
    borrowed[0] = 20;
    let cell: Cell<i32> = Cell { value: 19 };
    let pointer: core::aliases::Ref<Cell<i32>> = cell.borrow();
    cell.value = 22;
    data[1] = pointer.value;
    if (data[0] + data[1] != 42) { return 2; }
    let empty: core::aliases::Id<core::aliases::Empty<bool>> = [];
    let flag: core::aliases::Flag<Local<str>> = false;
    if (flag) { return 3; }
    if (std::io::println(saved.first) != 3) { return 4; }
    return 0;
}
"#, stdlib.0.path(), "Ω\n".as_bytes(), 0);
}

#[test]
fn imported_generic_aliases_preserve_symbolic_type_and_constant_environments() {
    let stdlib = imported_alias_composition_stdlib();
    execute_with_stdlib("imported aliases in generic bodies", r#"
import core::aliases;
type Local<T, const N: usize> = core::aliases::Id<core::aliases::Fixed<T, N>>;
fn relay<T, const N: usize>(value: Local<T, N>) -> core::aliases::Fixed<T, N> {
    let saved: core::aliases::Id<Local<T, N>> = core::aliases::keep(value);
    return saved;
}
fn main() -> i32 {
    let data: core::aliases::Constant<2> = relay<i32, 2>([19, 23]);
    let flags: Local<bool, 2> = relay<bool, 2>([false, true]);
    let empty: Local<i32, 0> = relay<i32, 0>([]);
    if (data[0] + data[1] != 42 || flags[0] || !flags[1]) { return 1; }
    return 0;
}
"#, stdlib.0.path(), b"", 0);
}

#[test]
fn imported_generic_aliases_reject_type_length_and_header_conflicts() {
    let stdlib = imported_alias_composition_stdlib();
    for (declaration, expected_code) in [
        ("let value: core::aliases::Id<bool> = 42;", "LNC0006"),
        ("let value: core::aliases::Fixed<i32, 2> = [19, 23, 7];", "LNC0006"),
        ("let value: core::aliases::Fixed<bool, 2> = [19, 23];", "LNC0006"),
        ("let value: core::aliases::Swap<bool, i32> = core::aliases::Pair { first: false, second: 42 };", "LNC0006"),
        ("let value: core::aliases::Id<i32, bool> = 42;", "LNC0006"),
        ("let value: core::aliases::Fixed<i32, bool> = [19, 23];", "LNC0006"),
        ("let value: core::aliases::Fixed<2, i32> = [19, 23];", "LNC0006"),
        ("let value: core::aliases::Id<Unknown> = 42;", "LNC0007"),
        ("let value: core::aliases::Flag<Unknown> = false;", "LNC0007"),
    ] {
        let entry = common::TempArtifact::new("imported_alias_reject", "entry", Some("lani"));
        entry.write_str(&format!("import core::aliases; fn main() -> i32 {{ {declaration} return 0; }}"));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("imported alias rejection", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        }).expect_err("invalid alias operands must reject before executable publication");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, expected_code, "{declaration}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{declaration}: {error:?}");
    }
}

fn execute_reexported_alias(definition: &str, body: &str) {
    let stdlib = imported_alias_composition_stdlib();
    std::fs::write(stdlib.0.path().join("core/reexport.lani"),
        format!("module core::reexport; import core::aliases; {definition}"))
        .expect("alias reexport module");
    execute_with_stdlib("reexported alias", &format!(
        "import core::aliases; import core::reexport; fn main() -> i32 {{ {body} }}"),
        stdlib.0.path(), b"", 0);
}

#[test]
fn reexported_generic_aliases_preserve_identity_targets() {
    execute_reexported_alias("pub type Id<T> = core::aliases::Id<T>;",
        "let value: core::reexport::Id<i32> = 42; return value - 42;");
}

#[test]
fn reexported_generic_aliases_preserve_constant_array_targets() {
    execute_reexported_alias("pub type Numbers<const N: usize> = core::aliases::Fixed<i32, N>;",
        "let values: core::reexport::Numbers<2> = [19, 23]; return values[0] + values[1] - 42;");
}

#[test]
fn reexported_generic_aliases_preserve_reordered_nominal_targets() {
    execute_reexported_alias("pub type Swap<A, B> = core::aliases::Swap<A, B>;",
        "let value: core::reexport::Swap<bool, i32> = core::aliases::Pair { first: 42, second: false }; if (value.second) { return 1; } return value.first - 42;");
}

#[test]
fn alias_qualified_constructors_preserve_reordered_target_arguments() {
    execute("alias qualifier reordered", include_str!("fixtures/stdlib_compiler_state/alias-member-probes/reordered.lani"));
}

#[test]
fn alias_qualified_constructors_preserve_injected_and_constant_arguments() {
    execute("alias qualifier injected", include_str!("fixtures/stdlib_compiler_state/alias-member-probes/injected.lani"));
    execute("alias qualifier constant", include_str!("fixtures/stdlib_compiler_state/alias-member-probes/constant.lani"));
}

#[test]
fn alias_qualified_constructors_preserve_normalized_concrete_unit_parents() {
    execute("alias qualifier bare-unit", include_str!("fixtures/stdlib_compiler_state/alias-member-probes/bare-unit.lani"));
    execute("alias qualifier called-unit", include_str!("fixtures/stdlib_compiler_state/alias-member-probes/called-unit.lani"));
}

#[test]
fn alias_qualified_constructors_preserve_symbolic_and_constant_domains() {
    execute("normalized alias constructor body environments", r#"
enum Packet<T, const N: usize, F> { Missing, Data([T; N], F) }
type Swap<F, T, const N: usize> = Packet<T, N, F>;
type Numbers<const N: usize> = Swap<bool, i32, N>;
fn make<T, const N: usize>(values: [T; N]) -> Packet<T, N, bool> {
    return Swap<bool, T, N>::Data(values, false);
}
fn empty<T, const N: usize>() -> Packet<T, N, bool> {
    return Swap<bool, T, N>::Missing();
}
fn main() -> i32 {
    let value = make<i32, 2>([19, 23]);
    let direct = Numbers<2>::Data([20, 22], false);
    let zero = Numbers<0>::Missing;
    let other = empty<i32, 0>();
    if (!(match (zero) { Packet::Missing -> true, _ -> false }) ||
        !(match (other) { Packet::Missing -> true, _ -> false })) { return 1; }
    let first = match (value) { Packet::Data(values, flag) -> values[0] + values[1], _ -> 0 };
    let second = match (direct) { Packet::Data(values, flag) -> values[0] + values[1], _ -> 0 };
    let flag = match (value) { Packet::Data(values, flag) -> flag, _ -> true };
    if (flag || first != 42 || second != 42) { return 2; }
    return 0;
}
"#);
}

#[test]
fn alias_qualified_constructors_preserve_thirty_two_injected_operands() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let mut operands = vec!["[[i32; 0]; 0]"; 32];
    operands[0] = "[i32; 2]";
    operands[31] = "bool";
    execute("bare alias with thirty two target operands", &format!(r#"
enum Wide<{parameters}> {{ Data(T0, T31), Missing }}
type Concrete = Wide<{}>;
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{
    let value = Concrete::Data([19, 23], false);
    let copy = keep(value);
    value = Concrete::Missing();
    let total = match (copy) {{ Wide::Data(values, flag) -> values[0] + values[1], _ -> 0 }};
    let flag = match (copy) {{ Wide::Data(values, flag) -> flag, _ -> true }};
    if (total != 42 || flag || !(match (value) {{ Wide::Missing -> true, _ -> false }})) {{ return 1; }}
    return 0;
}}
"#, operands.join(", ")));
}

#[test]
fn alias_qualified_constructors_reject_conflicting_and_invalid_applications() {
    for expression in [
        "let v = Number::Some(false);",
        "let v: Choice<bool> = Number::None;",
        "let v: Choice<bool> = Number::None();",
        "let v = Flip<bool, i32>::Both(false, 42);",
        "let v = Flip<bool>::Empty();",
        "let v = Flip<bool, i32>::Empty<bool, i32>();",
        "let v = Window<i32, 2>::Some([1, 2, 3]);",
        "let v = Window<i32, bool>::None();",
    ] {
        let source = format!(r#"
enum Choice<T> {{ Some(T), None }}
enum Pair<A, B> {{ Both(A, B), Empty }}
type Number = Choice<i32>;
type Flip<A, B> = Pair<B, A>;
type Window<T, const N: usize> = Choice<[T; N]>;
fn main() -> i32 {{ {expression} return 0; }}
"#);
        let error = common::run_gpu_codegen_with_timeout("invalid normalized constructor", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        }).expect_err("alias constructor constraints must reject before emission");
        let diagnostic = error.to_public_diagnostic();
        assert!(matches!(diagnostic.code.as_str(), "LNC0005" | "LNC0006" | "LNC0027"),
            "{expression}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{expression}: {error:?}");
    }
}

#[test]
fn generic_alias_chains_preserve_ordered_environments_at_runtime() {
    execute("deep reordered alias", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/deep-reordered-alias.lani"));
    execute("deep selected alias", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/deep-selection-alias.lani"));
}

#[test]
fn generic_aliases_preserve_mixed_compositions_and_empty_values() {
    execute("constant only alias", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/constant-only-alias.lani"));
    execute("mixed composed aliases", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/mixed-composition-alias.lani"));
}

#[test]
fn generic_aliases_preserve_thirty_two_parameter_environments() {
    execute("thirty two alias arguments", include_str!("fixtures/stdlib_compiler_state/alias-type-probes/thirty-two-parameter-alias.lani"));
}

#[test]
fn late_method_results_preserve_types_without_receiver_or_result_annotations() {
    for (name, source) in [
        ("trait result", include_str!("fixtures/stdlib_compiler_state/method-result-contract/method-signature.lani")),
        ("inherent result", include_str!("fixtures/stdlib_compiler_state/method-result-contract/method-signature-inherent-control.lani")),
        ("annotated receiver control", include_str!("fixtures/stdlib_compiler_state/method-result-contract/receiver-annotated.lani")),
        ("annotated result control", include_str!("fixtures/stdlib_compiler_state/method-result-contract/method-signature-annotated.lani")),
        ("ordinary function control", include_str!("fixtures/stdlib_compiler_state/method-result-contract/ordinary-function.lani")),
        ("arrays without a generic arena", include_str!("fixtures/stdlib_compiler_state/method-result-contract/ordinary-array.lani")),
    ] {
        execute(name, source);
    }
}

#[test]
fn late_method_results_compose_through_local_and_imported_generic_calls() {
    let source = include_str!("fixtures/stdlib_compiler_state/method-result-contract/compositions.lani");
    let expected = include_bytes!("fixtures/stdlib_compiler_state/method-result-contract/compositions.expected.txt");
    execute_with_stdout("complete late method results", source, expected);
    let stdlib = ReceiverTestStdlib::new();
    let imported = source
        .replace("import std::io;", "import std::io;\nimport core::relay;")
        .replace("fn keep<T>(value: T) -> T { return value; }", "")
        .replace("keep(", "core::relay::keep(");
    execute_with_stdlib("imported late method result arguments", &imported, stdlib.0.path(), expected, 0);
}

#[test]
fn late_method_results_preserve_all_thirty_two_compound_arguments() {
    execute("32 late method result arguments", include_str!("fixtures/stdlib_compiler_state/method-result-contract/thirty-two.lani"));
}

#[test]
fn late_method_results_reject_conflicting_complete_types() {
    for (label, declarations, actual, expected, value) in [
        ("element", "", "[i32; 2]", "[bool; 2]", "[19, 23]"),
        ("length", "", "[i32; 2]", "[i32; 3]", "[19, 23]"),
        ("empty element", "", "[i32; 0]", "[bool; 0]", "[]"),
        ("nominal identity", "struct Left { value: i32 } struct Right { value: i32 }", "Left", "Right", "Left { value: 42 }"),
    ] {
        let source = format!(r#"
struct Cell<T> {{ value: T }}
{declarations}
impl i32 {{ fn copy(self: i32, value: Cell<{actual}>) -> Cell<{actual}> {{ return value; }} }}
fn require(value: Cell<{expected}>) -> i32 {{ return 0; }}
fn main() -> i32 {{
    let n = 0;
    let input: Cell<{actual}> = Cell {{ value: {value} }};
    let result = n.copy(input);
    return require(result);
}}
"#);
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        }).expect_err("a late method result must retain its actual type");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{label}: {error:?}");
    }
}

#[test]
fn normalized_alias_trait_arguments_execute() {
    execute("normalized nominal and scalar trait arguments", r#"
struct Key { value: i32 }
type KeyAlias = Key;
type OtherAlias = KeyAlias;
type Count = i32;
trait Rel<Value> {}
impl Rel<Key> for i32 {}
impl Rel<Count> for bool {}
fn keep<T>(value: T) -> T where T: Rel<OtherAlias> { return value; }
fn flag<T>(value: T) -> T where T: Rel<Count> { return value; }
fn main() -> i32 {
    if (keep(42) != 42 || flag(false)) { return 1; }
    return 0;
}

"#);
}

#[test]
fn trait_bounds_preserve_complete_argument_graphs_and_symbolic_bindings() {
    for (name, source) in [
        ("nested", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/nested-argument.lani")),
        ("array", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/array-argument.lani")),
        ("compound", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/compound-arguments.lani")),
        ("symbolic", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/symbolic-arguments.lani")),
        ("forwarded", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/symbolic-forwarding.lani")),
    ] {
        execute(name, source);
    }
}

#[test]
fn nested_symbolic_nominal_constants_in_trait_bounds_execute() {
    execute("nested symbolic constant bound", include_str!(
        "fixtures/stdlib_compiler_state/caller-contract-snapshots/nested-symbolic-constant-bound-runtime.lani"
    ));
}

#[test]
fn nested_symbolic_nominal_constants_in_trait_bounds_reject_wrong_bindings() {
    let source = include_str!(
        "fixtures/stdlib_compiler_state/caller-contract-snapshots/nested-symbolic-constant-bound-runtime.lani"
    );
    let cases = [
        ("different constant parameter", source.replace("Cell<[U;N],M>", "Cell<[U;N],N>")),
        ("wrong concrete constant", source.replace("let markers:[i32;3]=[5,7,11];", "let markers:[i32;2]=[5,7];")),
        ("wrong nested type", source.replace("Cell<[U;N],M>", "Cell<[bool;N],M>")),
        ("unknown constant name", source.replace("Cell<[U;N],M>", "Cell<[U;N],Missing>")),
        ("type parameter in constant slot", source.replace("Cell<[U;N],M>", "Cell<[U;N],U>")),
        ("constant parameter in type slot", source.replace("Cell<[U;N],M>", "Cell<N,M>")),
        ("constant supplied directly to type trait operand", source.replace("Rel<Cell<[U;N],M>>", "Rel<M>")),
        ("direct constant trait operand remains unsupported", r#"
trait Sized<const N:usize> {}
impl Sized<2> for bool {}
fn keep<T>(value:T)->T where T:Sized<2> { return value; }
fn main()->i32 { if (keep(false)) { return 1; } return 0; }
"#.to_owned()),
    ];
    common::run_gpu_codegen_with_timeout("invalid nested constant bounds", move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
            .expect("GPU compiler");
        for (label, source) in cases {
            let error = pollster::block_on(compiler.compile_source_to_x86_64(&source))
                .expect_err(&format!("{label}: invalid bound must reject before executable output"));
            let diagnostic = error.to_public_diagnostic();
            if label == "direct constant trait operand remains unsupported" {
                assert_eq!(diagnostic.code, "LNC0016", "{label}: {error:?}");
            } else {
                assert!(matches!(diagnostic.code.as_str(), "LNC0007" | "LNC0008" | "LNC0021"),
                    "{label}: expected a source contract rejection: {error:?}");
            }
            assert!(diagnostic.primary_label.is_some(), "{label}: {error:?}");
        }
    });
}

#[test]
fn trait_bound_subjects_preserve_value_copies_borrows_and_empty_values() {
    execute("compound trait subjects", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/compound-subjects.lani"));
}

#[test]
fn trait_bounds_preserve_all_thirty_two_ordered_argument_graphs() {
    execute("32 complete trait arguments", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/thirty-two-mixed.lani"));
}

#[test]
fn trait_bounds_execute_thirty_two_independent_compound_operand_graphs() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(",");
    let operands = (0..32).map(|i| format!("Cell<[i32;{i}]>")).collect::<Vec<_>>();
    let source = |bound: &[String]| format!(r#"
struct Cell<T> {{ value: T }}
trait Wide<{parameters}> {{}}
impl Wide<{}> for bool {{}}
fn keep<T>(v:T)->T where T:Wide<{}> {{return v;}}
fn main()->i32 {{if (keep(false) || !keep(true)) {{return 1;}} return 0;}}
"#, operands.join(","), bound.join(","));
    execute("32 independent compound trait operands", &source(&operands));
    let mut wrong_last = operands.clone();
    wrong_last[31] = "Cell<[i32;32]>".to_owned();
    reject_trait_program("32 compound operands with wrong final length", &source(&wrong_last), "LNC0008");
}

#[test]
fn trait_method_contracts_compare_substituted_types_independently_of_syntax_shape() {
    execute("normalized trait method signature", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/method-signature-annotated.lani"));
}

fn reject_trait_program(label: &str, source: &str, code: &str) {
    let source = source.to_owned();
    let error = common::run_gpu_codegen_with_timeout(label, move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
        pollster::block_on(compiler.compile_source_to_x86_64(&source))
    }).err().unwrap_or_else(|| panic!("{label}: invalid trait contract emitted an executable"));
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, code, "{label}: {error:?}");
    assert!(diagnostic.primary_label.is_some(), "{label}: {error:?}");
}

#[test]
fn trait_bounds_reject_inner_identity_length_order_and_unproved_assumptions() {
    for (label, source) in [
        ("slot 31", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/thirty-two-last-mismatch.lani").to_owned()),
        ("array length", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/symbolic-arguments.lani").replace("keep(false,[19,23])", "keep(false,[19,23,24])")),
        ("element identity", "trait Rel<T>{} impl Rel<[i32;0]> for bool{} fn keep<T>(v:T)->T where T:Rel<[bool;0]>{return v;} fn main()->i32{keep(false);return 0;}".to_owned()),
        ("nominal identity", "struct A{v:i32} struct B{v:i32} struct Cell<T>{v:T} trait Rel<T>{} impl Rel<Cell<A>> for bool{} fn keep<T>(v:T)->T where T:Rel<Cell<B>>{return v;} fn main()->i32{keep(false);return 0;}".to_owned()),
        ("argument order", "trait Rel<A,B>{} impl Rel<[i32;2],[bool;2]> for bool{} fn keep<T>(v:T)->T where T:Rel<[bool;2],[i32;2]>{return v;} fn main()->i32{keep(false);return 0;}".to_owned()),
        ("unproved caller bound", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/symbolic-forwarding.lani").replace("fn relay<T>(v:T)->T where T:Mark", "fn relay<T>(v:T)->T")),
    ] {
        reject_trait_program(label, &source, "LNC0008");
    }
}

#[test]
fn trait_impls_reject_duplicate_complete_keys_and_inner_method_mismatches() {
    reject_trait_program("incomplete nested nominal argument", "struct Cell<T>{v:T} trait Rel<T>{} impl Rel<[Cell;0]> for i32{} fn main()->i32{return 0;}", "LNC0021");
    reject_trait_program("unused generic impl parameter", "trait Rel<U>{} impl<T> Rel<i32> for i32{} fn main()->i32{return 0;}", "LNC0021");
    reject_trait_program("equivalent alias impl keys", "type Pair=[i32;2]; trait Mark{} impl Mark for Pair{} impl Mark for [i32;2]{} fn main()->i32{return 0;}", "LNC0021");
    reject_trait_program("method inner element", "struct Cell<T>{v:T} trait Echo<T>{fn echo(v:Cell<T>)->Cell<T>;} impl Echo<[i32;2]> for i32{fn echo(v:Cell<[bool;2]>)->Cell<[bool;2]>{return v;}} fn main()->i32{return 0;}", "LNC0021");
    reject_trait_program("method reference referent", "struct A{v:i32} struct B{v:i32} trait Echo<T>{fn echo(v:T)->T;} impl Echo<&A> for i32{fn echo(v:&B)->&B{return v;}} fn main()->i32{return 0;}", "LNC0021");
}

#[test]
fn imported_generic_bodies_execute_with_caller_selected_implementations() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_compiler_state/trait-type-graphs/stdlib");
    execute_with_stdlib(
        "caller implementation reaches imported body",
        include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/imported-caller-impl.lani"),
        &root, b"", 0,
    );
}

#[test]
fn caller_selected_bounds_forward_through_nested_bodies_and_existing_bodies() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_compiler_state/program-replay/stdlib");
    execute_with_stdlib("caller evidence through nested replay", r#"
import core::contracts;
pub impl core::contracts::Rel<core::contracts::Cell<[i32;3]>> for bool {}
pub impl core::contracts::Rel<core::contracts::Cell<[i32;2]>> for i32 {}
fn main()->i32 {
    if (core::contracts::relay(false,[19,23,24])) { return 1; }
    if (core::contracts::relay(42,[19,23]) != 42) { return 2; }
    if (core::contracts::tag<bool,i32,3>() != 42) { return 3; }
    if (core::contracts::relay(false,[1,2,3])) { return 4; }
    return 0;
}
"#, &root, b"", 0);
}

#[test]
fn reused_native_bodies_still_reject_missing_bounds_at_the_actual_call() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_compiler_state/program-replay/stdlib");
    // This body can already be emitted without concrete bindings. Every call
    // must still satisfy its bound, including after other programs have run.
    let valid = "import core::contracts; pub impl core::contracts::Rel<core::contracts::Cell<[i32;3]>> for bool {} fn main()->i32 {return core::contracts::tag<bool,i32,3>()-42;}";
    execute_with_stdlib("valid existing body before missing bound", valid, &root, b"", 0);
    let source = "import core::contracts;\nfn main()->i32 {\n    return core::contracts::tag<bool,i32,3>();\n}\n";
    let entry = common::TempArtifact::new("trait_contract", "missing_existing_body_bound", Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let expected_path = path.clone();
    let compile_root = root.clone();
    let error = common::run_gpu_codegen_with_timeout("missing existing body bound", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &compile_root))
    }).expect_err("an existing generic body still requires its call's implementation");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{error:?}");
    let label = diagnostic.primary_label.as_ref().expect("retained source call diagnostic");
    assert_eq!(label.path, expected_path, "{error:?}");
    assert_eq!(label.line, 3, "{error:?}");
    assert!(label.source_line.as_deref().is_some_and(|line| line.contains("core::contracts::tag<bool,i32,3>()")), "{error:?}");
    execute_with_stdlib("valid existing body after missing bound", valid, &root, b"", 0);
}

#[test]
fn imported_generic_bodies_enforce_their_concrete_trait_contracts() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_compiler_state/trait-type-graphs/stdlib");
    execute_with_stdlib("imported bound", include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/imported.lani"), &root, b"", 0);
    let entry = common::TempArtifact::new("trait_contract", "invalid_imported", Some("lani"));
    entry.write_str(include_str!("fixtures/stdlib_compiler_state/trait-type-graphs/imported-mismatch.lani"));
    let path = entry.path().to_path_buf();
    let error = common::run_gpu_codegen_with_timeout("invalid imported bound", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    }).err().expect("an unsatisfied imported bound must reject before emission");
    assert_eq!(error.to_public_diagnostic().code, "LNC0008", "{error:?}");
    assert!(error.to_public_diagnostic().primary_label.is_some());
}

#[test]
fn generic_aliases_reject_incompatible_checked_graphs() {
    for (label, definitions, parameter, result) in [
        ("alias element identity", "", "Packed<i32, 2>", "Packed<bool, 2>"),
        ("alias array length", "", "Packed<i32, 2>", "Packed<i32, 3>"),
        ("alias empty array identity", "", "Packed<i32, 0>", "Packed<bool, 0>"),
        ("alias nominal identity", "struct Left { value: i32 } struct Right { value: i32 }", "Packed<Left, 2>", "Packed<Right, 2>"),
        ("alias symbolic type identity", "", "Packed<T, N>", "Packed<U, N>"),
        ("alias symbolic length identity", "", "Packed<T, N>", "Packed<T, M>"),
    ] {
        let source = format!(
            "struct Cell<V> {{ value: V }} type Packed<T, const N: usize> = Cell<[T; N]>; {definitions} fn wrong<T, U, const N: usize, const M: usize>(value: {parameter}) -> {result} {{ return value; }} fn main() -> i32 {{ return 0; }}"
        );
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        })
        .expect_err("incompatible checked alias graphs must reject");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{label}: {error:?}");
    }
}

#[test]
fn ordinary_pointer_values_preserve_addresses_and_aliases() {
    execute(
        "ordinary pointer forwarding",
        include_str!("fixtures/stdlib_foundation/repro_ordinary_pointer_forwarding.lani"),
    );
}

#[test]
fn direct_record_literal_arguments_execute_through_ordinary_and_generic_calls() {
    for (label, definitions, empty, pair, text, nested) in [
        (
            "ordinary literal arguments",
            "fn empty(v: Empty) -> Empty { return v; } fn pair(v: Pair) -> Pair { return v; } fn text(v: Text) -> Text { return v; } fn nested(v: Nested) -> Nested { return v; }",
            "empty",
            "pair",
            "text",
            "nested",
        ),
        (
            "local generic literal arguments",
            "fn keep<T>(v: T) -> T { return v; }",
            "keep",
            "keep",
            "keep",
            "keep",
        ),
        (
            "imported generic literal arguments",
            "",
            "core::mem::identity",
            "core::mem::identity",
            "core::mem::identity",
            "core::mem::identity",
        ),
    ] {
        execute_with_stdout(
            label,
            &format!(
                r#"
module app::main;
import std::io;
import core::mem;
struct Empty {{}}
struct Pair {{ head: i32, tail: i32 }}
struct Text {{ text: str, sentinel: i32 }}
struct Nested {{ child: Text, tail: i32 }}
{definitions}
fn main() -> i32 {{
    let nothing = {empty}(Empty {{}});
    let numbers = {pair}(Pair {{ head: -7, tail: 99 }});
    let words = {text}(Text {{ text: "Ω", sentinel: -91 }});
    let composite = {nested}(Nested {{ child: Text {{ text: "backup", sentinel: 42 }}, tail: -31 }});
    if (numbers.head != -7 || numbers.tail != 99 || words.sentinel != -91 ||
        composite.child.sentinel != 42 || composite.tail != -31) {{ return 1; }}
    if (std::io::println(words.text) != 3 || std::io::println(composite.child.text) != 7) {{ return 2; }}
    return 0;
}}
"#
            ),
            "Ω\nbackup\n".as_bytes(),
        );
    }
}

#[test]
fn direct_record_literal_generic_arguments_reject_type_and_field_conflicts() {
    for (label, declarations, expression) in [
        (
            "distinct literal record identities",
            "struct Left { value: i32 } struct Right { value: i32 }",
            "agree(Left { value: -7 }, Right { value: -7 })",
        ),
        (
            "distinct empty literal identities",
            "struct Left {} struct Right {}",
            "agree(Left {}, Right {})",
        ),
        (
            "wrong literal field type",
            "struct Left { value: i32 }",
            "keep(Left { value: false })",
        ),
    ] {
        let source = format!(
            "{declarations}\nfn keep<T>(value: T) -> T {{ return value; }}\nfn agree<T>(left: T, right: T) -> T {{ return left; }}\nfn main() -> i32 {{ let result = {expression}; return 0; }}"
        );
        let entry = common::TempArtifact::new("generic_types", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("literal arguments must retain nominal and field constraints");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn direct_record_literal_arguments_preserve_generic_body_failure() {
    let source =
        include_str!("fixtures/stdlib_foundation/repro_generic_zero_literal_argument.lani");
    let entry = common::TempArtifact::new("generic_types", "literal_argument_assert", Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("literal argument assertion", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
    .expect("direct empty literals must supply a complete generic binding");
    let output =
        common::run_x86_64_elf_output("literal argument assertion", "generic_types", &bytes);
    assert!(
        !output.status.success(),
        "the empty result cannot erase the body: {output:?}"
    );
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        assert_eq!(
            output.status.signal(),
            Some(4),
            "native assert uses SIGILL: {output:?}"
        );
    }
}

#[test]
fn direct_record_literal_arguments_preserve_contextual_generic_compositions() {
    execute_with_stdout(
        "contextual generic literal arguments",
        r#"
module app::main;
import core::mem;
import std::io;
struct Empty {}
struct Phantom<A, B> {}
struct Cell<T> { value: T, sentinel: i32 }
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let words: Cell<str> = keep(Cell { value: "Ω", sentinel: -91 });
    let nested: Cell<Cell<str>> = core::mem::identity(Cell { value: Cell { value: "backup", sentinel: 42 }, sentinel: -31 });
    let arrays: Cell<[str; 2]> = keep(Cell { value: ["", "Ω"], sentinel: 99 });
    let marker: Phantom<[str; 0], Empty> = keep(Phantom {});
    let copied = core::mem::identity(nested);
    copied.value.sentinel = -7;
    if (words.sentinel != -91 || nested.value.sentinel != 42 || copied.value.sentinel != -7 ||
        nested.sentinel != -31 || copied.sentinel != -31 || arrays.sentinel != 99) { return 1; }
    if (std::io::println(words.value) != 3 || std::io::println(copied.value.value) != 7 ||
        std::io::println(arrays.value[0]) != 1 || std::io::println(arrays.value[1]) != 3) { return 2; }
    return 0;
}
"#,
        "Ω\nbackup\n\nΩ\n".as_bytes(),
    );
}

#[test]
fn direct_record_literal_arguments_preserve_imported_generic_record_fields() {
    let stdlib = ReceiverTestStdlib::new();
    let entry =
        common::TempArtifact::new("generic_types", "imported_literal_arguments", Some("lani"));
    entry.write_str(r#"
module app::main;
import core::five;
import core::relay;
import std::io;
struct Text { message: str, sentinel: i32 }
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let local: core::five::Five<i32, bool, str, Text, [str; 2]> = keep(core::five::Five {
        fifth: ["", "Ω"], third: "Ω", first: -7, second: false,
        fourth: Text { message: "backup", sentinel: 42 }
    });
    let imported: core::five::Five<i32, bool, str, Text, [str; 2]> = core::relay::forward(core::five::Five {
        first: -91, second: true, third: "", fifth: ["Ω", "backup"],
        fourth: Text { message: "Ω", sentinel: 99 }
    });
    let copied = core::relay::keep(local);
    copied.fourth.sentinel = -31;
    if (local.first != -7 || local.second || imported.first != -91 || !imported.second ||
        local.fourth.sentinel != 42 || copied.fourth.sentinel != -31 || imported.fourth.sentinel != 99) { return 1; }
    if (std::io::println(copied.third) != 3 || std::io::println(copied.fourth.message) != 7 ||
        std::io::println(copied.fifth[0]) != 1 || std::io::println(copied.fifth[1]) != 3 ||
        std::io::println(imported.third) != 1 || std::io::println(imported.fifth[1]) != 7) { return 2; }
    return 0;
}

"#);
    let path = entry.path().to_path_buf();
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout(
        "imported generic record literal arguments",
        move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root)),
    )
    .expect("imported record contexts must remain complete through generic calls");
    let output =
        common::run_x86_64_elf_output("imported record literal arguments", "generic_types", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "Ω\nbackup\n\nΩ\n\nbackup\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn direct_record_literal_arguments_inside_generic_bodies_preserve_complete_types() {
    execute_with_stdout(
        "literal arguments inside generic bodies",
        r#"
module app::main;
import core::mem;
import std::io;
struct Empty {}
struct Pair { head: i32, tail: i32 }
struct Cell<T> { value: T, sentinel: i32 }
struct Holder<T> { child: Cell<T>, tail: i32 }
fn keep<T>(value: T) -> T { return value; }
fn local<T>(value: T) -> Holder<T> {
    return keep(Holder { child: Cell { value: value, sentinel: 42 }, tail: -91 });
}
fn imported<T>(value: T) -> Holder<T> {
    return core::mem::identity(Holder { child: Cell { value: value, sentinel: 42 }, tail: -91 });
}
fn main() -> i32 {
    let number = local(-7);
    let flag = imported(false);
    let text = local("Ω");
    let pair = imported(Pair { head: -33, tail: 99 });
    let items: [str; 2] = ["", "backup"];
    let array = imported(items);
    let empty = local(Empty {});
    let copied = core::mem::identity(pair);
    copied.child.value.tail = -17;
    if (number.child.value != -7 || flag.child.value || text.child.sentinel != 42 ||
        pair.child.value.head != -33 || pair.child.value.tail != 99 || copied.child.value.tail != -17 ||
        copied.tail != -91 || array.child.sentinel != 42 || empty.child.sentinel != 42 || empty.tail != -91) { return 1; }
    if (std::io::println(text.child.value) != 3 || std::io::println(array.child.value[0]) != 1 ||
        std::io::println(array.child.value[1]) != 7) { return 2; }
    return 0;
}
"#,
        "Ω\n\nbackup\n".as_bytes(),
    );
}

#[test]
fn local_generic_pointer_values_preserve_addresses_and_aliases() {
    execute(
        "local generic pointer forwarding",
        include_str!("fixtures/stdlib_foundation/repro_generic_local_pointer_forwarding.lani"),
    );
}

#[test]
fn imported_generic_pointer_values_preserve_addresses_and_aliases() {
    execute(
        "imported generic pointer forwarding",
        include_str!("fixtures/stdlib_foundation/repro_generic_imported_pointer_forwarding.lani"),
    );
}

#[test]
fn zero_sized_values_forward_through_ordinary_and_generic_functions() {
    for (label, source) in [
        (
            "ordinary empty record",
            include_str!("fixtures/stdlib_foundation/repro_ordinary_empty_forwarding.lani"),
        ),
        (
            "local generic empty record",
            include_str!("fixtures/stdlib_foundation/repro_generic_local_empty_forwarding.lani"),
        ),
        (
            "imported generic empty record",
            include_str!("fixtures/stdlib_foundation/repro_generic_imported_empty_forwarding.lani"),
        ),
        (
            "ordinary empty array",
            include_str!("fixtures/stdlib_foundation/repro_ordinary_empty_array_forwarding.lani"),
        ),
        (
            "local generic empty array",
            include_str!(
                "fixtures/stdlib_foundation/repro_generic_local_empty_array_forwarding.lani"
            ),
        ),
        (
            "imported generic empty array",
            include_str!(
                "fixtures/stdlib_foundation/repro_generic_imported_empty_array_forwarding.lani"
            ),
        ),
    ] {
        execute(label, source);
    }
}

#[test]
fn zero_sized_generic_calls_preserve_body_effects() {
    execute(
        "zero-sized generic body effects",
        r#"
module app::main;
import core::mem;
struct Empty {}
struct Phantom<T> {}
fn visit<T>(value: T, seen: [i32], sentinel: i32) -> T {
    assert(sentinel == 42);
    seen[0] = seen[0] + 1;
    return value;
}
fn view(values: [i32]) -> [i32] { return values; }
fn main() -> i32 {
    let count: [i32; 1] = [0];
    let seen: [i32] = view(count);
    let seed: Empty = Empty {};
    let empty: Empty = visit(core::mem::identity(seed), seen, 42);
    let nothing: [str; 0] = [];
    let array: [str; 0] = core::mem::identity(visit(nothing, seen, 42));
    let marker: Phantom<[str; 2]> = Phantom {};
    let copied: Phantom<[str; 2]> = visit(core::mem::identity(marker), seen, 42);
    if (count[0] != 3) { return 1; }
    return 0;
}
"#,
    );
    let mut failures = Vec::new();
    for function in [
        "fn fail(value: Empty, safe: bool) -> Empty { assert(safe); return value; }",
        "fn fail<T>(value: T, safe: bool) -> T { assert(safe); return value; }",
    ] {
        let source = format!(
            "struct Empty {{}}\n{function}\nfn main() -> i32 {{ let seed: Empty = Empty {{}}; let value: Empty = fail(seed, false); return 0; }}"
        );
        let entry =
            common::TempArtifact::new("generic_types", "empty_assert_failure", Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("empty assertion failure", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect("compile ordinary and generic failing bodies");
        let output =
            common::run_x86_64_elf_output("empty assertion failure", "generic_types", &bytes);
        assert!(
            !output.status.success(),
            "the empty result cannot skip assert: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        #[cfg(unix)]
        {
            use std::os::unix::process::ExitStatusExt;
            assert_eq!(
                output.status.signal(),
                Some(4),
                "native assert traps with SIGILL: {output:?}"
            );
        }
        failures.push(output.status);
    }
    assert_eq!(
        failures[0], failures[1],
        "generic failure must preserve ordinary failure behavior"
    );
}

#[test]
fn zero_sized_compositions_preserve_neighbors_and_array_bounds() {
    execute_with_stdout(
        "zero-sized compositions",
        include_str!("fixtures/stdlib_foundation/generic_zero_sized_compositions.lani"),
        "Ω\nbackup\n".as_bytes(),
    );
    for (operation, index) in [("read", -1), ("read", 3), ("store", -1), ("store", 3)] {
        let operation = if operation == "read" {
            "let copied: Empty = values[index];"
        } else {
            "values[index] = seed;"
        };
        execute_with_status(
            "zero-sized element bounds",
            &format!(
                r#"
struct Empty {{}}
fn runtime_index(value: i32) -> i32 {{ if (value == -99) {{ return 0; }} return value; }}
fn main() -> i32 {{
    let seed: Empty = Empty {{}};
    let values: [Empty; 3] = [seed, seed, seed];
    let index: i32 = runtime_index({index});
    {operation}
    return 0;
}}
"#
            ),
            b"",
            101,
        );
    }
}

#[test]
fn zero_sized_generic_calls_retain_distinct_complete_type_identities() {
    for (label, declarations, setup) in [
        (
            "empty nominal identity",
            "struct Left {} struct Right {}",
            "let left: Left = Left {}; let right: Right = Right {};",
        ),
        (
            "phantom ordered arguments",
            "struct Phantom<T> {}",
            "let left: Phantom<i32> = Phantom {}; let right: Phantom<bool> = Phantom {};",
        ),
        (
            "zero-sized array lengths",
            "struct Empty {}",
            "let seed: Empty = Empty {}; let left: [Empty; 2] = [seed, seed]; let right: [Empty; 3] = [seed, seed, seed];",
        ),
    ] {
        let source = format!(
            "{declarations}\nfn agree<T>(left: T, right: T) -> T {{ return left; }}\nfn main() -> i32 {{ {setup} let value = agree(left, right); return 0; }}"
        );
        let entry = common::TempArtifact::new("generic_types", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("equal zero layouts must not erase type constraints");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains("agree(left, right)")),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn imported_zero_sized_generic_bodies_preserve_effects_and_argument_placement() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/generic_zero_sized_imported_effects.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_zero_sized_effects_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported zero-sized body effects", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile imported generic bodies with zero-sized arguments");
    let output =
        common::run_x86_64_elf_output("imported zero-sized body effects", "generic_types", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn generic_pointer_compositions_preserve_values_copies_and_aliases() {
    execute(
        "generic pointer compositions",
        include_str!("fixtures/stdlib_foundation/generic_pointer_compositions.lani"),
    );
}

#[test]
fn ordinary_pointer_field_and_array_stores_preserve_full_addresses() {
    execute(
        "ordinary pointer field and array stores",
        include_str!("fixtures/stdlib_foundation/repro_ordinary_pointer_stores.lani"),
    );
}

#[test]
fn ordinary_trait_methods_execute_alongside_generic_value_calls() {
    execute(
        "plain trait method with generic calls",
        r#"
module app::main;
trait Hash<T> { fn hash(value: T) -> u32; }
impl Hash<i32> for i32 { fn hash(value: i32) -> u32 { return value; } }
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    if (i32::hash(keep(-1)) != 4294967295) { return 1; }
    if (keep(false)) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn nested_generic_declaration_fields_substitute_in_the_enclosing_scope() {
    execute(
        "nested generic declaration field",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_field_substitution.lani"),
    );
    execute_with_stdout(
        "nested generic declaration environments",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_field_environments.lani"),
        "\nΩ\nbackup\nΩ\n\nΩ\nΩ\n".as_bytes(),
    );
    execute_with_stdout(
        "nested generic declaration descriptor fields",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_field_descriptors.lani"),
        "Ω\n\nΩ\nbackup\n".as_bytes(),
    );
}

#[test]
fn nested_generic_applications_are_created_without_source_annotations() {
    execute(
        "minimal implied nested application",
        include_str!("fixtures/stdlib_foundation/repro_generic_missing_nested_application.lani"),
    );
    execute_with_stdout(
        "compiler generated nested applications",
        include_str!("fixtures/stdlib_foundation/generic_generated_nested_applications.lani"),
        "Ω\n\nΩ\nΩ\n\nbackup\nΩ\nΩ\n\n\n".as_bytes(),
    );
}

#[test]
fn generic_bodies_construct_nested_applications() {
    execute(
        "generic nested constructor body",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_constructor_body.lani"),
    );
    execute_with_stdout(
        "nested generic constructor body environments",
        include_str!("fixtures/stdlib_foundation/generic_nested_constructor_bodies.lani"),
        "Ω\n\nΩ\n\nΩ\nbackup\nΩ\nΩ\nbackup\n".as_bytes(),
    );
}

#[test]
fn local_generic_enums_substitute_nested_payload_types() {
    execute(
        "nested generic enum array payload",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_enum_payload.lani"),
    );
    execute_with_stdout(
        "nested generic enum payload environments",
        include_str!("fixtures/stdlib_foundation/generic_nested_enum_payloads.lani"),
        "\nbackup\nΩ\nbackup\nΩ\n\nbackup\nΩ\n\nbackup\nbackup\n".as_bytes(),
    );
    for index in [-1, 2] {
        execute_with_status(
            "generic enum array payload bounds",
            &format!(
                r#"
module app::main;
enum Batch<T> {{ Items([T; 2]), Empty }}
fn read<T>(value: Batch<T>, index: i32, fallback: T) -> T {{
    return match (value) {{ Items(items) -> items[index], Empty -> fallback }};
}}
fn main() -> i32 {{
    let words: [str; 2] = ["Ω", ""];
    let value: Batch<str> = Items(words);
    let selected: str = read(value, {index}, "backup");
    return 0;
}}
"#
            ),
            b"",
            101,
        );
    }
}

#[test]
fn generated_imported_receivers_preserve_more_than_four_type_arguments() {
    execute(
        "local generated five arguments",
        include_str!("fixtures/stdlib_foundation/repro_generic_generated_five_arguments.lani"),
    );
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_generic_generated_receiver_arguments.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout("generated receiver arguments", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile generated receiver applications with more than four arguments");
    let output =
        common::run_x86_64_elf_output("generated receiver arguments", "generic_types", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let receiver_stdlib = ReceiverTestStdlib::new();
    for (label, argument, expression, checks, stdout) in [
        (
            "generated bool receiver",
            "bool",
            "false",
            "if (value.child.last()) { return 3; }",
            "",
        ),
        (
            "generated unsigned receiver",
            "u32",
            "4294967295",
            "if (value.child.last() != 4294967295) { return 3; }",
            "",
        ),
        (
            "generated float receiver",
            "f32",
            "2.5",
            "if (value.child.last() != 2.5) { return 3; }",
            "",
        ),
        (
            "generated character receiver",
            "char",
            "'Ω'",
            "if (value.child.last() != 'Ω') { return 3; }",
            "",
        ),
        (
            "generated array receiver",
            "[i32; 2]",
            "[-7, 42]",
            "let copy: [i32; 2] = value.child.last(); if (copy[0] != -7 || copy[1] != 42) { return 3; } copy[0] = 9; let original: [i32; 2] = value.child.last(); if (original[0] != -7 || value.sentinel != 99) { return 4; }",
            "",
        ),
        (
            "generated string receiver",
            "str",
            "\"Ω\"",
            "if (std::io::println(value.child.last()) != 3) { return 3; }",
            "Ω\n",
        ),
        (
            "generated empty string receiver",
            "str",
            "\"\"",
            "if (std::io::println(value.child.last()) != 1) { return 3; }",
            "\n",
        ),
        (
            "generated string array receiver",
            "[str; 2]",
            "[\"Ω\", \"\"]",
            "let copy: [str; 2] = value.child.last(); if (std::io::println(copy[0]) != 3 || std::io::println(copy[1]) != 1) { return 3; } copy[0] = \"changed\"; let original: [str; 2] = value.child.last(); if (std::io::println(original[0]) != 3 || value.sentinel != 99) { return 4; }",
            "Ω\n\nΩ\n",
        ),
        (
            "generated record receiver",
            "Pair",
            "Pair { number: -7, text: \"Ω\" }",
            "let copy: Pair = value.child.last(); if (copy.number != -7 || std::io::println(copy.text) != 3) { return 3; } copy.number = 9; copy.text = \"changed\"; let original: Pair = value.child.last(); if (original.number != -7 || std::io::println(original.text) != 3 || value.sentinel != 99) { return 4; }",
            "Ω\nΩ\n",
        ),
        (
            "generated borrowed slice receiver",
            "[i32]",
            "view(data)",
            "let selected: [i32] = value.child.last(); if (selected[0] != -7 || selected[1] != 42) { return 3; } selected[0] = 9; if (data[0] != 9 || value.sentinel != 99) { return 4; }",
            "",
        ),
    ] {
        let source = format!(
            r#"
module app::main;
import core::five;
import std::io;
struct Pair {{ number: i32, text: str }}
fn view(values: [i32]) -> [i32] {{ return values; }}
struct Holder<T> {{ child: core::five::Five<i32, bool, char, u32, T>, sentinel: i32 }}
fn main() -> i32 {{
    let data: [i32; 2] = [-7, 42];
    let value: Holder<{argument}> = Holder {{
        child: core::five::Five {{ fifth: {expression}, third: 'Ω', second: false, first: 11, fourth: 4294967295 }},
        sentinel: 99,
    }};
    if (value.child.first_value() != 11 || value.child.second_value() ||
        value.child.third_value() != 'Ω' || value.child.fourth_value() != 4294967295 || value.sentinel != 99) {{ return 2; }}
    {checks}
    return 0;
}}
"#
        );
        let entry = common::TempArtifact::new("generated_receivers", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = receiver_stdlib.0.path().to_path_buf();
        let bytes = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .unwrap_or_else(|error| panic!("{label}: {error:?}"));
        let output = common::run_x86_64_elf_output(label, "generated_receivers", &bytes);
        assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
        assert_eq!(output.stdout, stdout.as_bytes(), "{label}: {output:?}");
        assert!(output.stderr.is_empty(), "{label}: {output:?}");
    }
}

#[test]
fn imported_generic_record_constructors_check_declaration_and_fields() {
    let original =
        include_str!("fixtures/stdlib_foundation/repro_generic_generated_receiver_arguments.lani");
    for (label, needle, replacement, code) in [
        (
            "foreign fifth argument mismatch",
            "fifth: -7",
            "fifth: false",
            "LNC0006",
        ),
        (
            "foreign second argument mismatch",
            "second: false",
            "second: 11",
            "LNC0006",
        ),
        (
            "foreign wrong declaration",
            "        child: core::five::Five",
            "        child: core::five::Other",
            "LNC0006",
        ),
        ("foreign missing field", ", fifth: -7", "", "LNC0042"),
        (
            "foreign missing all fields",
            "core::five::Five { first: 11, second: false, third: 'Ω', fourth: 4294967295, fifth: -7 }",
            "core::five::Five {}",
            "LNC0042",
        ),
        (
            "foreign duplicate field",
            "fifth: -7",
            "fifth: -7, fifth: 11",
            "LNC0042",
        ),
        (
            "foreign unknown field",
            "fifth: -7",
            "fifth: -7, unknown: 11",
            "LNC0042",
        ),
    ] {
        let source = original.replace(needle, replacement);
        assert_ne!(source, original, "{label}: reproduction must change source");
        let entry = common::TempArtifact::new("generated_receivers", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("invalid imported record constructors must not emit executable code");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, code, "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains(replacement) || line.contains("child:")),
            "{label}: {error:?}"
        );
    }
    for (label, expression) in [
        ("foreign array field length mismatch", "[\"Ω\"]"),
        ("foreign array field element mismatch", "[false, false]"),
    ] {
        let source = format!(
            r#"
module app::main;
import core::five;
struct Holder<T> {{ child: core::five::Five<i32, bool, char, u32, T>, sentinel: i32 }}
fn main() -> i32 {{
    let value: Holder<[str; 2]> = Holder {{
        child: core::five::Five {{ first: 11, second: false, third: 'Ω', fourth: 4294967295, fifth: {expression} }}, sentinel: 99,
    }};
    return 0;
}}
"#
        );
        let entry = common::TempArtifact::new("generated_receivers", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("invalid contextual array literals must not emit executable code");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains("fifth:")),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn explicit_record_constructor_imported_five_arguments_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    execute_with_stdlib(
        "explicit imported five-argument record constructor",
        include_str!(
            "fixtures/stdlib_foundation/repro_imported_explicit_generic_record_constructor.lani"
        ),
        &root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root"),
        b"",
        0,
    );
}

#[test]
fn imported_compound_field_generic_reader_executes() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_compound_field_generic_reader.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported compound field generic reader", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile imported compound field generic reader");
    let output = common::run_x86_64_elf_output(
        "imported compound field generic reader",
        "compound_generic_reader",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let receiver_stdlib = ReceiverTestStdlib::new();
    let entry = root.join(
        "tests/fixtures/stdlib_foundation/repro_imported_compound_field_generic_reader_string.lani",
    );
    let stdlib = receiver_stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout(
        "imported compound string field generic reader",
        move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib)),
    )
    .expect("compile imported compound string field generic reader");
    let output = common::run_x86_64_elf_output(
        "imported compound string field generic reader",
        "compound_generic_reader_string",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, "Ω\n\n".as_bytes(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let entry = root.join(
        "tests/fixtures/stdlib_foundation/repro_imported_compound_field_generic_reader_float.lani",
    );
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported compound float field reader", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile imported compound float field reader");
    let output = common::run_x86_64_elf_output(
        "imported compound float field reader",
        "compound_generic_reader_float",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn generic_compound_returns_use_complete_call_environments() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_generic_compound_return_environment.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout(
        "complete generic compound return environment",
        move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib)),
    )
    .expect("compile complete generic compound return environment");
    let output = common::run_x86_64_elf_output(
        "complete generic compound return environment",
        "compound_return_environment",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let receiver_stdlib = ReceiverTestStdlib::new();
    let entry =
        root.join("tests/fixtures/stdlib_foundation/generic_compound_return_environments.lani");
    let stdlib = receiver_stdlib.0.path().to_path_buf();
    let bytes =
        common::run_gpu_codegen_with_timeout("mixed compound return environments", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile mixed compound return environments");
    let output = common::run_x86_64_elf_output(
        "mixed compound return environments",
        "mixed_compound_returns",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "Ω\n\nΩ\nΩ\nΩ\nΩ\nΩ\n\nΩ\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn generic_applications_compose_six_sixteen_and_thirty_two_parameters() {
    for (count, source, prefix_lines) in [
        (
            6,
            include_str!("fixtures/stdlib_foundation/generic_many_parameter_composition_6.lani"),
            2,
        ),
        (
            16,
            include_str!("fixtures/stdlib_foundation/generic_many_parameter_composition_16.lani"),
            5,
        ),
        (
            32,
            include_str!("fixtures/stdlib_foundation/generic_many_parameter_composition_32.lani"),
            11,
        ),
    ] {
        let expected = format!("{}Ω\n\nΩ\nΩ\n", "Ω\n".repeat(prefix_lines));
        execute_with_stdout(
            &format!("{count} generic parameters with mixed compound fields"),
            source,
            expected.as_bytes(),
        );
    }
}

#[test]
fn generic_inferred_compound_returns_execute() {
    execute(
        "inferred compound generic return",
        include_str!("fixtures/stdlib_foundation/repro_generic_inferred_compound_return.lani"),
    );
}

#[test]
fn nested_generic_parameter_constraints_infer_complete_types() {
    execute(
        "nested generic parameter constraint",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_parameter_constraint.lani"),
    );
    execute_with_stdout(
        "nested parameter values copies and aliases",
        include_str!("fixtures/stdlib_foundation/generic_nested_parameters.lani"),
        "Ω\nΩ\nΩ\nreplacement\n\nΩ\nsecond\n".as_bytes(),
    );
}

#[test]
fn inferred_field_results_supply_complete_generic_arguments() {
    execute_with_stdout(
        "inferred field generic argument",
        include_str!("fixtures/stdlib_foundation/repro_generic_expression_field.lani"),
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn inferred_index_results_supply_complete_generic_arguments() {
    execute_with_stdout(
        "inferred index generic argument",
        include_str!("fixtures/stdlib_foundation/repro_generic_expression_index.lani"),
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn inferred_match_results_supply_complete_generic_arguments() {
    execute_with_stdout(
        "inferred match generic argument",
        include_str!("fixtures/stdlib_foundation/repro_generic_expression_match.lani"),
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn specialized_body_packed_array_arguments_preserve_values() {
    let source =
        include_str!("fixtures/stdlib_foundation/repro_generic_body_expression_closure.lani");
    for result in ["field", "element", "joined"] {
        execute(
            &format!("specialized body expression closure at {result}"),
            &source.replace("return keep(joined);", &format!("return keep({result});")),
        );
    }
}

#[test]
fn specialized_body_expression_chains_preserve_records_descriptors_and_aliases() {
    let definitions =
        include_str!("fixtures/stdlib_foundation/repro_generic_body_expression_closure.lani")
            .split("fn main()")
            .next()
            .expect("generic expression-chain definitions");
    for result in ["field", "element", "joined"] {
        for present in [true, false] {
            let definitions =
                definitions.replace("return keep(joined);", &format!("return keep({result});"));
            let definitions = if present {
                definitions
            } else {
                definitions.replace("return Some(value);", "return None();")
            };
            let source = format!(
                r#"
module app::main;
import std::io;
import core::mem;
{definitions}
struct Text {{ number: i32, text: str, last: i32 }}
struct Empty {{}}
fn borrow(values: [i32]) -> [i32] {{ return values; }}
fn main() -> i32 {{
    let original: Text = Text {{ number: -7, text: "Ω", last: 42 }};
    let copied = roundtrip(original);
    copied.last = 91;
    if (copied.number != -7 || copied.last != 91 || original.last != 42) {{ return 1; }}
    std::io::println(copied.text);
    std::io::println(original.text);
    if (roundtrip(false) || roundtrip(-7) != -7 || roundtrip(2.5) != 2.5 || roundtrip('Ω') != 'Ω') {{ return 2; }}
    let words: [str; 2] = ["Ω", ""];
    let copied_words = roundtrip(words);
    copied_words[0] = "replacement";
    std::io::println(copied_words[0]);
    std::io::println(copied_words[1]);
    std::io::println(words[0]);
    let storage: [i32; 2] = [11, 22];
    let view: [i32] = borrow(storage);
    let restored = roundtrip(view);
    restored[0] = -7;
    if (storage[0] != -7 || restored[1] != 22) {{ return 3; }}
    let pointer: ptr = core::mem::i32_array_data_ptr(storage);
    if (roundtrip(pointer) != pointer) {{ return 4; }}
    let empty: Empty = Empty {{}};
    let copied_empty = roundtrip(empty);
    return 0;
}}
"#
            );
            execute_with_stdout(
                &format!("specialized {result} types, present={present}"),
                &source,
                "Ω\nΩ\nreplacement\n\nΩ\n".as_bytes(),
            );
        }
    }
}

#[test]
fn dependent_expression_chains_preserve_values_and_copy_boundaries() {
    let mut source = String::from(
        r#"
module app::main;
import std::io;
struct Cell<T> { value: T }
struct Pair { first: i32, text: str, last: i32 }
enum Maybe<T> { None, Some(T) }
fn wrap<T>(value: T) -> Cell<T> { return Cell { value: value }; }
fn duplicate<T>(value: T) -> [T; 2] { return [value, value]; }
fn maybe<T>(value: T, present: bool) -> Maybe<T> {
    if (present) { return Some(value); } return None();
}
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let original: Pair = Pair { first: -7, text: "Ω", last: 42 };
    let stage0 = keep(original);
"#,
    );
    for index in 0..12 {
        let next = index + 1;
        let present = if index % 2 == 0 { "true" } else { "false" };
        source.push_str(&format!(
            r#"
    let cell{index} = wrap(stage{index});
    let field{index} = keep(cell{index}.value);
    let elements{index} = duplicate(field{index});
    let element{index} = keep(elements{index}[{element}]);
    let optional{index} = maybe(element{index}, {present});
    let joined{index} = match (optional{index}) {{
        None -> element{index}, Some(value{index}) -> value{index}
    }};
    let stage{next} = keep(joined{index});
    stage{next}.last = stage{next}.last + 1;
    if (stage{next}.first != -7 || stage{next}.last != {expected} ||
        stage{index}.last != {previous} || cell{index}.value.last != {previous} ||
        elements{index}[0].last != {previous}) {{ return 1; }}
"#,
            element = index % 2,
            expected = 42 + next,
            previous = 42 + index,
        ));
    }
    source.push_str(
        r#"
    if (original.last != 42) { return 2; }
    std::io::println(stage12.text);
    std::io::println(original.text);
    return 0;
}
"#,
    );
    execute_with_stdout(
        "dependent field index match chain",
        &source,
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn dependent_expression_results_preserve_slice_aliases() {
    execute(
        "dependent expression slice aliases",
        r#"
module app::main;
struct Cell<T> { value: T }
enum Maybe<T> { None, Some(T) }
fn wrap<T>(value: T) -> Cell<T> { return Cell { value: value }; }
fn duplicate<T>(value: T) -> [T; 2] { return [value, value]; }
fn maybe<T>(value: T) -> Maybe<T> { return Some(value); }
fn keep<T>(value: T) -> T { return value; }
fn exercise(values: [i32], fallback: [i32]) -> i32 {
    let cell = wrap(values);
    let field = keep(cell.value);
    let indexed = keep(duplicate(field)[1]);
    let optional = maybe(indexed);
    let chosen = match (optional) { None -> fallback, Some(value) -> value };
    let result = keep(chosen);
    result[0] = -7;
    result[1] = 42;
    if (values[0] != -7 || values[1] != 42 || cell.value[1] != 42 ||
        fallback[0] != 71) { return 1; }
    return 0;
}
fn main() -> i32 {
    let values: [i32; 2] = [19, 20];
    let fallback: [i32; 2] = [71, 72];
    if (exercise(values, fallback) != 0 || values[0] != -7 || values[1] != 42 ||
        fallback[1] != 72) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn nested_parameter_inference_preserves_thirty_two_bindings() {
    let parameters = (0..32).map(|index| format!("T{index}")).collect::<Vec<_>>();
    let types = (0..32)
        .map(|index| ["i32", "str", "[str; 2]", "[i32]"][index % 4])
        .collect::<Vec<_>>();
    let fields = (0..32)
        .map(|index| format!("v{index}: T{index}"))
        .collect::<Vec<_>>();
    let values = (0..32)
        .map(|index| {
            format!(
                "v{index}: {}",
                ["42", "\"Ω\"", "strings", "borrowed"][index % 4]
            )
        })
        .collect::<Vec<_>>();
    let checks = (0..32)
        .filter(|index| index % 4 == 0)
        .map(|index| format!("if (wrapped.value.v{index} != 42) {{ return 1; }}"))
        .collect::<Vec<_>>()
        .join("\n");
    let source = format!(
        r#"
module app::main;
import std::io;
struct Cell<T> {{ value: T }}
struct Many<{}> {{ {} }}
fn last<{}>(value: Cell<Many<{}>>) -> T31 {{
    return value.value.v31;
}}
fn view(values: [i32]) -> [i32] {{ return values; }}
fn main() -> i32 {{
    let strings: [str; 2] = ["Ω", ""];
    let numbers: [i32; 2] = [-7, 42];
    let borrowed: [i32] = view(numbers);
    let wrapped: Cell<Many<{}>> = Cell {{ value: Many {{ {} }} }};
    {checks}
    std::io::println(wrapped.value.v29);
    std::io::println(wrapped.value.v30[0]);
    let result = last(wrapped);
    if (result[0] != -7 || result[1] != 42) {{ return 2; }}
    result[1] = 91;
    if (numbers[1] != 91) {{ return 3; }}
    return 0;
}}
"#,
        parameters.join(", "),
        fields.join(", "),
        parameters.join(", "),
        parameters.join(", "),
        types.join(", "),
        values.join(", "),
    );
    execute_with_stdout(
        "nested thirty-two parameter inference",
        &source,
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn imported_nested_parameter_inference_preserves_copies_and_aliases() {
    let stdlib = ReceiverTestStdlib::new();
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/generic_imported_nested_parameters.lani");
    let root = stdlib.0.path().to_path_buf();
    let bytes =
        common::run_gpu_codegen_with_timeout("imported nested parameter inference", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &root))
        })
        .expect("compile complete imported nested parameter constraints");
    let output = common::run_x86_64_elf_output(
        "imported nested parameter inference",
        "nested_parameters",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "Ω\nΩ\nreplacement\n\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn nested_parameter_constraints_reject_conflicts_and_missing_bindings() {
    for (label, declarations, function, preparation, call) in [
        (
            "repeated nested scalars",
            "",
            "fn first<T>(value: Cell<Duo<T, T>>) -> T { return value.value.left; }",
            "let value: Cell<Duo<i32, bool>> = Cell { value: Duo { left: 42, right: false } };",
            "first(value)",
        ),
        (
            "repeated nested array lengths",
            "",
            "fn first<T>(value: Cell<Duo<T, T>>) -> T { return value.value.left; }",
            "let a: [i32; 2] = [1, 2]; let b: [i32; 3] = [1, 2, 3]; let value: Cell<Duo<[i32; 2], [i32; 3]>> = Cell { value: Duo { left: a, right: b } };",
            "first(value)",
        ),
        (
            "repeated nested nominal identities",
            "struct Left { n: i32 } struct Right { n: i32 }",
            "fn first<T>(value: Cell<Duo<T, T>>) -> T { return value.value.left; }",
            "let value: Cell<Duo<Left, Right>> = Cell { value: Duo { left: Left { n: 1 }, right: Right { n: 2 } } };",
            "first(value)",
        ),
        (
            "nested arguments disagree",
            "",
            "fn first<T>(left: Cell<Cell<T>>, right: Cell<Cell<T>>) -> T { return left.value.value; }",
            "let left: Cell<Cell<i32>> = Cell { value: Cell { value: 42 } }; let right: Cell<Cell<bool>> = Cell { value: Cell { value: false } };",
            "first(left, right)",
        ),
        (
            "unused parameter remains required",
            "",
            "fn first<T, U>(value: Cell<Cell<T>>) -> T { return value.value.value; }",
            "let value: Cell<Cell<i32>> = Cell { value: Cell { value: 42 } };",
            "first(value)",
        ),
    ] {
        let source = format!(
            "struct Cell<T> {{ value: T }} struct Duo<A, B> {{ left: A, right: B }}\n{declarations}\n{function}\nfn main() -> i32 {{\n{preparation}\nlet result = {call};\nreturn 0;\n}}"
        );
        let entry = common::TempArtifact::new("nested_parameters", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("conflicting or absent complete bindings must reject");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains(call)),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn inferred_returns_inside_generic_bodies_preserve_compound_values() {
    execute(
        "inferred return chain inside generic body",
        include_str!("fixtures/stdlib_foundation/repro_generic_body_inferred_return_chain.lani"),
    );
    let stdlib = ReceiverTestStdlib::new();
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/generic_body_inferred_returns.lani");
    let root = stdlib.0.path().to_path_buf();
    let bytes =
        common::run_gpu_codegen_with_timeout("generic body inferred compound values", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &root))
        })
        .expect("compile local and imported inferred calls inside concrete generic bodies");
    let output = common::run_x86_64_elf_output(
        "generic body inferred compound values",
        "body_inferred_returns",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "\nΩ\n\nΩ\nΩ\nΩ\n\nΩ\n\n\nΩ\n\nΩ\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn imported_generic_inferred_array_return_executes() {
    let stdlib = ReceiverTestStdlib::new();
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_inferred_array_return.lani");
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("imported inferred array return", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &root))
    })
    .expect("compile imported generic array return without a result annotation");
    let output = common::run_x86_64_elf_output(
        "imported inferred array return",
        "imported_inferred_array",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn local_result_context_infers_complete_bindings_through_thirty_two_parameters() {
    execute(
        "five complete result-only bindings",
        include_str!("fixtures/stdlib_foundation/repro_generic_local_result_only_bindings.lani"),
    );
    let parameters = (0..32).map(|index| format!("T{index}")).collect::<Vec<_>>();
    let arguments = (0..32)
        .map(|index| ["i32", "str", "[str; 2]", "[i32]"][index % 4])
        .collect::<Vec<_>>();
    let payloads = (0..32).map(|index| format!("v{index}")).collect::<Vec<_>>();
    let parameters = parameters.join(", ");
    let source = format!(
        "enum Many<{parameters}> {{ Empty, Values({parameters}) }}\n\
         fn absent<{parameters}>() -> Many<{parameters}> {{ return Empty(); }}\n\
         fn main() -> i32 {{\n\
         let value: Many<{}> = absent();\n\
         return match (value) {{ Empty -> 0, Values({}) -> 1 }};\n}}",
        arguments.join(", "),
        payloads.join(", "),
    );
    execute("thirty-two complete result-only bindings", &source);
    execute(
        "nested complete result-only bindings",
        r#"
struct Cell<T> { value: T }
enum Equal<A, B> { Empty, Pair(A, B) }
fn absent<A, B>() -> Equal<[A; 2], Cell<B>> { return Empty(); }
fn main() -> i32 {
    let value: Equal<[str; 2], Cell<[i32]>> = absent();
    return match (value) { Empty -> 0, Pair(a, b) -> 1 };
}
"#,
    );
}

#[test]
fn local_result_context_rejects_repeated_or_argument_constraint_conflicts() {
    for (label, declarations, function, annotation, call) in [
        (
            "repeated array lengths",
            "",
            "fn absent<T>() -> Equal<T, T> { return Empty(); }",
            "Equal<[str; 2], [str; 3]>",
            "absent()",
        ),
        (
            "repeated nominal identities",
            "struct Left { number: i32 } struct Right { number: i32 }",
            "fn absent<T>() -> Equal<T, T> { return Empty(); }",
            "Equal<Left, Right>",
            "absent()",
        ),
        (
            "accepted argument contradicts context",
            "",
            "fn build<T>(value: T) -> Equal<T, T> { return Pair(value, value); }",
            "Equal<bool, bool>",
            "build(42)",
        ),
    ] {
        let source = format!(
            "{declarations}\nenum Equal<A, B> {{ Empty, Pair(A, B) }}\n{function}\nfn main() -> i32 {{\nlet value: {annotation} = {call};\nreturn 0;\n}}",
        );
        let entry = common::TempArtifact::new("local_result_context", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("complete conflicting result constraints must reject before emission");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains(call)),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn imported_generic_inferred_compound_returns_preserve_values_copies_and_aliases() {
    let stdlib = ReceiverTestStdlib::new();
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/generic_imported_inferred_returns.lani");
    let root = stdlib.0.path().to_path_buf();
    let bytes =
        common::run_gpu_codegen_with_timeout("mixed imported inferred returns", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &root))
        })
        .expect("compile complete imported returns without result annotations");
    let output = common::run_x86_64_elf_output(
        "mixed imported inferred returns",
        "mixed_imported_inferred",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "Ω\nΩ\n\nΩ\n\nΩ\n\nΩ\nΩ\n\n\n\nΩ\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn imported_generic_inferred_return_arguments_execute() {
    let stdlib = ReceiverTestStdlib::new();
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "tests/fixtures/stdlib_foundation/repro_imported_generic_inferred_return_argument.lani",
    );
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("inferred return argument", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &root))
    })
    .expect("compile a generic call receiving an inferred complete return type");
    let output = common::run_x86_64_elf_output(
        "inferred return argument",
        "inferred_return_argument",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn imported_generic_inference_closes_long_chains_and_compound_arguments() {
    let stdlib = ReceiverTestStdlib::new();
    let mut source = String::from(
        r#"
module app::main;
import core::relay;
import std::io;
struct Pair { number: i32, text: str }
fn borrow(values: [i32]) -> [i32] { return values; }
fn length(values: [i32]) -> i32 {
    let count: i32 = 0;
    for value in values { count += 1; }
    return count;
}
fn main() -> i32 {
    let original: Pair = Pair { number: -7, text: "Ω" };
    let chain0 = core::relay::duplicate(original);
"#,
    );
    for index in 1..32 {
        let function = if index % 2 == 0 {
            "keep"
        } else {
            "forward_array"
        };
        source.push_str(&format!(
            "    let chain{index} = core::relay::{function}(chain{});\n",
            index - 1,
        ));
    }
    source.push_str(
        r#"
    chain31[0].number = 123;
    if (original.number != -7 || chain0[0].number != -7 || chain31[1].number != -7) { return 1; }
    std::io::println(chain31[0].text);
    std::io::println(chain31[1].text);
    let words = core::relay::duplicate("Ω");
    let wrapped = core::relay::wrap(words);
    let wrappers = core::relay::duplicate(wrapped);
    let copied_wrappers = core::relay::forward_array(wrappers);
    if (copied_wrappers[0].sentinel != 1234 || copied_wrappers[1].sentinel != 1234) { return 2; }
    copied_wrappers[0].value[0] = "";
    std::io::println(copied_wrappers[0].value[0]);
    std::io::println(copied_wrappers[1].value[0]);
    std::io::println(wrapped.value[0]);
    let storage: [i32; 3] = [11, 22, 33];
    let view: [i32] = borrow(storage);
    let vacant: [i32; 0] = [];
    let empty: [i32] = borrow(vacant);
    let views = core::relay::duplicate(view);
    let copied_views = core::relay::forward_array(views);
    copied_views[0][1] = 77;
    if (storage[1] != 77 || copied_views[1][1] != 77 || views[0][1] != 77) { return 3; }
    copied_views[0] = empty;
    if (length(copied_views[0]) != 0 || length(copied_views[1]) != 3 || length(views[0]) != 3) { return 4; }
    return 0;
}
"#,
    );
    let entry = common::TempArtifact::new("inference_chain", "compound_arguments", Some("lani"));
    entry.write_str(&source);
    let path = entry.path().to_path_buf();
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("long compound inference chains", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    })
    .expect("compile complete types across thirty-two dependent calls");
    let output =
        common::run_x86_64_elf_output("long compound inference chains", "inference_chain", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, "Ω\nΩ\n\nΩ\nΩ\n".as_bytes(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn generic_nominal_results_reject_conflicting_contextual_constraints() {
    let stdlib = ReceiverTestStdlib::new();
    for (label, preparation, result, call) in [
        (
            "repeated scalar constraint",
            "",
            "core::relay::Equal<i32, bool>",
            "core::relay::absent()",
        ),
        (
            "repeated equal-width descriptor constraint",
            "",
            "core::relay::Equal<str, [i32]>",
            "core::relay::absent()",
        ),
        (
            "accepted argument contradicts result constraint",
            "let numbers: [i32; 2] = [-7, 42];",
            "[bool; 2]",
            "core::relay::forward_array(numbers)",
        ),
        (
            "inferred argument contradicts result constraint",
            "let numbers = core::relay::duplicate(42);",
            "[bool; 2]",
            "core::relay::forward_array(numbers)",
        ),
        (
            "inferred result length contradicts context",
            "let numbers = core::relay::duplicate(42);",
            "[i32; 3]",
            "core::relay::forward_array(numbers)",
        ),
    ] {
        let source = format!(
            "module app::main; import core::relay; fn main() -> i32 {{ {preparation} let wrong: {result} = {call}; return 0; }}"
        );
        let entry = common::TempArtifact::new("nominal_context_constraint", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        })
        .expect_err("conflicting complete contextual constraints must reject");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains(call)),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn imported_result_only_generic_bindings_reach_body_specialization() {
    let stdlib = ReceiverTestStdlib::new();
    let source = r#"
module app::main;
import core::relay;
fn main() -> i32 {
    let number: core::relay::Equal<i32, i32> = core::relay::absent();
    let text: core::relay::Equal<str, str> = core::relay::absent();
    let array: core::relay::Equal<[str; 2], [str; 2]> = core::relay::absent();
    if (!core::relay::is_empty(number)) { return 1; }
    if (!core::relay::is_empty(text)) { return 2; }
    if (!core::relay::is_empty(array)) { return 3; }
    return 0;
}
"#;
    let entry =
        common::TempArtifact::new("result_only_generic", "body_specialization", Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("result-only body bindings", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    })
    .expect("compile all contextual bindings through specialization");
    let output =
        common::run_x86_64_elf_output("result-only body bindings", "result_only_bindings", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn generic_nominal_arguments_survive_imported_and_forwarded_body_replay() {
    let stdlib = ReceiverTestStdlib::new();
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/generic_nominal_graph_replay.lani");
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("complete nominal graph replay", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &root))
    })
    .expect("compile imported and forwarded complete nominal graphs");
    let output = common::run_x86_64_elf_output(
        "complete nominal graph replay",
        "nominal_graph_replay",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, "Ω\n\nΩ\nΩ\nΩ\nΩ\n".as_bytes(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn generic_compound_returns_reject_wrong_elements_lengths_and_nominal_identities() {
    for (label, declarations, preparation, element, values, result) in [
        (
            "wrong return element",
            "",
            "",
            "i32",
            "[-7, 42]",
            "[str; 2]",
        ),
        ("wrong return length", "", "", "i32", "[-7, 42]", "[i32; 3]"),
        (
            "wrong return nominal identity",
            "struct Pair { value: i32 } struct Other { value: i32 }",
            "let first: Pair = Pair { value: -7 }; let second: Pair = Pair { value: 42 };",
            "Pair",
            "[first, second]",
            "[Other; 2]",
        ),
    ] {
        let source = format!(
            r#"
module app::main;
import core::five;
{declarations}
fn fixed<A, B>(value: core::five::ReorderedFields<A, B>) -> [B; 2] {{ return value.fixed; }}
fn view(value: [str]) -> [str] {{ return value; }}
fn main() -> i32 {{
    let words: [str; 1] = ["x"];
    {preparation}
    let value: core::five::ReorderedFields<str, {element}> = core::five::ReorderedFields {{ fixed: {values}, borrowed: view(words), sentinel: 99 }};
    let result: {result} = fixed(value);
    return 0;
}}
"#
        );
        let entry = common::TempArtifact::new("compound_return_wrong_type", label, Some("lani"));
        std::fs::write(entry.path(), source).expect("wrong compound return source");
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect_err("wrong complete compound return type must be rejected");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains("fixed(value)")),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn imported_generic_compound_record_fields_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_record_array_field.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported compound array field", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile imported compound array field");
    let output = common::run_x86_64_elf_output(
        "imported compound array field",
        "imported_compound_fields",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let receiver_stdlib = ReceiverTestStdlib::new();
    let entry = root.join("tests/fixtures/stdlib_foundation/generic_imported_compound_fields.lani");
    let stdlib = receiver_stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("mixed imported compound fields", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile mixed imported compound field types");
    let output = common::run_x86_64_elf_output(
        "mixed imported compound fields",
        "imported_compound_fields",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "Ω\n\n\nchanged\nΩ\nΩ\nΩ\nΩ\nΩ\n\nΩ\nΩ\nΩ\nchanged\nΩ\nΩ\nchanged\nΩ\nchanged\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn imported_generic_record_fields_execute_in_the_importing_module() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_record_field_read.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic record field", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile direct imported generic record field read");
    let output =
        common::run_x86_64_elf_output("imported generic record field", "imported_fields", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let receiver_stdlib = ReceiverTestStdlib::new();
    let entry = root.join("tests/fixtures/stdlib_foundation/generic_imported_record_fields.lani");
    let prefix = root.join(
        "tests/fixtures/stdlib_foundation/repro_imported_generic_record_multiword_prefix.lani",
    );
    let prefix_stdlib = receiver_stdlib.0.path().to_path_buf();
    let prefix_bytes =
        common::run_gpu_codegen_with_timeout("imported multiword field prefix", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&prefix, &prefix_stdlib))
        })
        .expect("compile minimal imported multiword field prefix");
    let prefix_output = common::run_x86_64_elf_output(
        "imported multiword field prefix",
        "imported_fields",
        &prefix_bytes,
    );
    assert_eq!(prefix_output.status.code(), Some(0), "{prefix_output:?}");
    let stdlib = receiver_stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("imported record field layouts", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile imported field reads, writes, and generic bodies");
    let output =
        common::run_x86_64_elf_output("imported record field layouts", "imported_fields", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        output.stdout,
        "head\nΩ\nΩ\n\nΩ\nΩ\nΩ\n\nΩ\nΩ\nΩ\n\n\nchanged\n\nΩ\nΩ\nΩ\nΩ\n\n".as_bytes(),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn imported_generic_record_fields_reject_wrong_types_and_names() {
    for (label, statement, code) in [
        ("unknown imported field", "return value.unknown;", "LNC0042"),
        (
            "wrong imported field annotation",
            "let bad: bool = value.fifth;",
            "LNC0006",
        ),
        (
            "wrong imported field argument",
            "accept_bool(value.fifth);",
            "LNC0006",
        ),
        (
            "wrong imported scalar field store",
            "value.fifth = false;",
            "LNC0006",
        ),
        (
            "wrong imported record field store",
            "value.second = Other { number: -7, text: \"Ω\" };",
            "LNC0006",
        ),
        (
            "wrong imported array field store length",
            "value.third = [\"Ω\"];",
            "LNC0006",
        ),
        (
            "wrong imported array field store elements",
            "value.third = [false, false];",
            "LNC0006",
        ),
        (
            "wrong imported nested field store",
            "value.second.text = false;",
            "LNC0006",
        ),
    ] {
        let source = format!(
            r#"
module app::main;
import core::five;
struct Pair {{ number: i32, text: str }}
struct Other {{ number: i32, text: str }}
fn view(values: [i32]) -> [i32] {{ return values; }}
fn accept_bool(value: bool) -> i32 {{ return 0; }}
fn main() -> i32 {{
    let data: [i32; 2] = [-7, 42];
    let value: core::five::Five<str, Pair, [str; 2], [i32], i32> = core::five::Five {{
        fifth: 99, fourth: view(data), third: ["Ω", ""], second: Pair {{ number: -7, text: "Ω" }}, first: "Ω",
    }};
    {statement}
    return 0;
}}
"#
        );
        let entry = common::TempArtifact::new("imported_fields", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| {
            panic!("{label}: invalid imported field operation emitted executable code")
        });
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, code, "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains(statement)),
            "{label}: {error:?}"
        );
    }
    let source = include_str!(
        "fixtures/stdlib_foundation/repro_imported_generic_record_multiword_prefix.lani"
    )
    .replace(
        "struct Pair { number: i32, text: str }",
        "struct Pair { number: i32, text: str }\nstruct Other { number: i32, text: str }",
    )
    .replace("second: Pair", "second: Other");
    let entry =
        common::TempArtifact::new("imported_fields", "wrong nested constructor", Some("lani"));
    entry.write_str(&source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
    let error =
        common::run_gpu_codegen_with_timeout("wrong nested imported record field", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .expect("wrong nominal nested constructor must be rejected");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0006", "{error:?}");
    assert!(
        diagnostic
            .primary_label
            .as_ref()
            .and_then(|label| label.source_line.as_ref())
            .is_some_and(|line| line.contains("second: Other")),
        "{error:?}"
    );
}

#[test]
fn imported_generic_record_fields_preserve_native_slice_bounds() {
    for (label, length, initial, replacement, index) in [
        ("negative imported slice field index", 2, "[-7, 42]", "", -1),
        ("upper imported slice field index", 2, "[-7, 42]", "", 2),
        ("empty imported slice field index", 0, "[]", "", 0),
        (
            "replaced imported slice field length",
            2,
            "[-7, 42]",
            "let empty: [i32; 0] = []; value.fifth = view(empty);",
            0,
        ),
    ] {
        let source = format!(
            r#"
module app::main;
import core::five;
fn view(values: [i32]) -> [i32] {{ return values; }}
fn main() -> i32 {{
    let data: [i32; {length}] = {initial};
    let value: core::five::Five<str, bool, char, u32, [i32]> = core::five::Five {{
        first: "Ω", second: false, third: 'Ω', fourth: 4294967295, fifth: view(data),
    }};
    {replacement}
    return value.fifth[{index}];
}}
"#
        );
        let entry = common::TempArtifact::new("imported_fields", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
        let bytes = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .unwrap_or_else(|error| panic!("{label}: {error:?}"));
        let output = common::run_x86_64_elf_output(label, "imported_fields", &bytes);
        assert_eq!(output.status.code(), Some(101), "{label}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{label}: {output:?}"
        );
    }
    for index in [-1, 2] {
        let source = format!(
            r#"
module app::main;
import core::five;
fn at(index: i32) -> i32 {{
    let value: core::five::Five<str, bool, char, u32, [str; 2]> = core::five::Five {{
        first: "Ω", second: false, third: 'Ω', fourth: 4294967295, fifth: ["Ω", ""],
    }};
    let invalid: str = value.fifth[index];
    return 0;
}}
fn main() -> i32 {{ return at({index}); }}
"#
        );
        let entry =
            common::TempArtifact::new("imported_fields", "fixed-array bounds", Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generated_receiver_root");
        let bytes =
            common::run_gpu_codegen_with_timeout("imported fixed-array field bounds", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            })
            .expect("compile imported fixed-array field bounds");
        let output = common::run_x86_64_elf_output(
            "imported fixed-array field bounds",
            "imported_fields",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(101), "{index}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{index}: {output:?}"
        );
    }
}

#[test]
fn unbounded_generic_application_expansion_reports_an_explicit_boundary() {
    let source = "struct Spiral<T> { next: Spiral<[T]> }\nfn require(value: Spiral<i32>) -> i32 { return 0; }\nfn main() -> i32 { return 0; }\n";
    let error =
        common::run_gpu_codegen_with_timeout("generic application expansion boundary", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(source))
        })
        .expect_err("unbounded expansion must not produce an executable");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0047", "{error:?}");
    assert!(
        diagnostic.primary_label.as_ref().is_some_and(|label| label
            .message
            .contains("generic type instantiation")
            && label
                .source_line
                .as_ref()
                .is_some_and(|line| line.contains("Spiral"))),
        "{error:?}"
    );
    assert!(diagnostic.notes.iter().any(|note|
        note.contains("arena is exhausted") || note.contains("64 traversal levels")),
        "{error:?}");
}

#[test]
fn local_generic_records_preserve_concrete_field_layouts() {
    execute(
        "generic record scalar layout",
        include_str!("fixtures/stdlib_foundation/repro_generic_record_scalar_layout.lani"),
    );
    execute_with_stdout(
        "generic record compound layouts",
        include_str!("fixtures/stdlib_foundation/repro_generic_record_compound_layouts.lani"),
        "Ω\n\n".as_bytes(),
    );
    execute(
        "generic record array field",
        include_str!("fixtures/stdlib_foundation/repro_generic_record_array_field.lani"),
    );
}

#[test]
fn generic_value_functions_preserve_compound_array_elements() {
    execute_with_stdout(
        "compound array values",
        include_str!("fixtures/stdlib_foundation/repro_generic_compound_array_values.lani"),
        "Ω\n\nbackup\nΩ\nΩ\n".as_bytes(),
    );
}

#[test]
fn generic_value_functions_preserve_compound_slice_elements() {
    execute(
        "compound slice values",
        include_str!("fixtures/stdlib_foundation/repro_generic_compound_slice_value.lani"),
    );
    execute_with_stdout(
        "compound slice descriptors",
        include_str!("fixtures/stdlib_foundation/repro_generic_compound_slice_descriptors.lani"),
        "Ω\n\nbackup\nx\n\nbackup\nΩ\nx\n".as_bytes(),
    );
    execute(
        "nested array slice values",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_array_slice_values.lani"),
    );
    execute(
        "nested plane slice values",
        include_str!("fixtures/stdlib_foundation/repro_nested_array_type_syntax.lani"),
    );
    execute(
        "compound slice Option and Result payloads",
        include_str!("fixtures/stdlib_foundation/repro_generic_compound_slice_option_result.lani"),
    );
}

#[test]
fn generic_value_functions_preserve_compound_slice_bounds() {
    for (label, definitions, preparation, index) in [
        (
            "compound slice upper bound",
            "",
            "let forwarded: [Pair] = keep(values);",
            2,
        ),
        (
            "compound slice negative bound",
            "",
            "let forwarded: [Pair] = keep(values);",
            -1,
        ),
        (
            "empty compound slice bound",
            "",
            "let empty: [Pair] = core::mem::typed_slice_from_raw_parts(core::mem::i32_slice_data_ptr(values), 0); let forwarded: [Pair] = keep(empty);",
            0,
        ),
        (
            "optional compound slice upper bound",
            "import core::option;",
            "let some: core::option::Option<[Pair]> = core::option::Some(values); let forwarded: [Pair] = core::option::unwrap_or(keep(some), values);",
            2,
        ),
        (
            "empty Result compound slice bound",
            "import core::result;",
            "let empty: [Pair] = core::mem::typed_slice_from_raw_parts(core::mem::i32_slice_data_ptr(values), 0); let success: core::result::Result<[Pair], [Pair]> = core::result::Ok(empty); let forwarded: [Pair] = core::result::unwrap_or(keep(success), values);",
            0,
        ),
    ] {
        execute_with_status(
            label,
            &format!(
                r#"
module app::main;
import core::mem;
{definitions}
struct Pair {{ left: i32, right: i32 }}
fn keep<T>(value: T) -> T {{ return core::mem::identity(value); }}
fn inspect(values: [Pair]) -> i32 {{
    {preparation}
    return forwarded[{index}].right;
}}
fn main() -> i32 {{
    let pair: Pair = Pair {{ left: -7, right: 42 }};
    let rows: [Pair; 2] = [pair, pair];
    return inspect(rows);
}}
"#
            ),
            b"",
            101,
        );
    }
    for (label, outer, inner) in [
        ("nested slice outer bound", 2, 0),
        ("nested slice inner bound", 0, 2),
    ] {
        execute_with_status(
            label,
            &format!(
                r#"
module app::main;
import core::mem;
fn keep<T>(value: T) -> T {{ return core::mem::identity(value); }}
fn inspect(values: [[i32; 2]], outer: i32, inner: i32) -> i32 {{
    let forwarded: [[i32; 2]] = keep(values);
    return forwarded[outer][inner];
}}
fn main() -> i32 {{
    let row: [i32; 2] = [-7, 42];
    let rows: [[i32; 2]; 2] = [row, row];
    return inspect(rows, {outer}, {inner});
}}
"#
            ),
            b"",
            101,
        );
    }
}

#[test]
fn generic_value_functions_preserve_slice_of_slice_descriptors() {
    execute(
        "nested borrowed slice descriptors",
        include_str!("fixtures/stdlib_foundation/repro_generic_slice_of_slices.lani"),
    );
    execute(
        "generic slice element return",
        include_str!("fixtures/stdlib_foundation/repro_generic_slice_element_return.lani"),
    );
    execute(
        "generic slice element swap",
        include_str!("fixtures/stdlib_foundation/repro_generic_slice_element_swap.lani"),
    );
    execute_with_stdout(
        "slice of slice generic payloads and elements",
        include_str!("fixtures/stdlib_foundation/generic_slice_of_slice_descriptors.lani"),
        "-7\n11\n123\n321\nΩ\n\nΩ\nbackup\nchanged\nchanged\n".as_bytes(),
    );
    for (outer, inner) in [(-1, 0), (2, 0), (0, -1), (0, 2), (1, 0)] {
        execute_with_status(
            "slice of slice forwarded bounds",
            &format!(
                r#"
module app::main;
import core::mem;
fn keep<T>(value: T) -> T {{ return core::mem::identity(value); }}
fn view(values: [i32]) -> [i32] {{ return values; }}
fn inspect(rows: [[i32]]) -> i32 {{
    let forwarded: [[i32]] = keep(rows);
    return forwarded[{outer}][{inner}];
}}
fn main() -> i32 {{
    let values: [i32; 2] = [-7, 42];
    let no_values: [i32; 0] = [];
    let populated: [i32] = view(values);
    let empty: [i32] = view(no_values);
    let rows: [[i32]; 2] = [populated, empty];
    return inspect(rows);
}}
"#
            ),
            b"",
            101,
        );
    }
}

#[test]
fn imported_scalar_calls_accept_projected_array_elements() {
    execute_with_stdout(
        "generic array element argument",
        include_str!("fixtures/stdlib_foundation/repro_generic_array_index_argument.lani"),
        b"-7\n0\n42\n",
    );
}

#[test]
fn local_generic_match_results_preserve_float_and_string_representations() {
    execute_with_stdout(
        "local string constructor",
        include_str!("fixtures/stdlib_foundation/repro_local_generic_string_constructor.lani"),
        b"payload\n",
    );
    execute_with_stdout(
        "local match representations",
        r#"
module app::main;
import std::io;
enum Maybe<T> { Some(T), None }
fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}
fn main() -> i32 {
    let number: Maybe<f32> = Some(-2.5);
    let absent_number: Maybe<f32> = None();
    if (unwrap_or(number, 99.0) != -2.5) { return 1; }
    if (unwrap_or(absent_number, -7.5) != -7.5) { return 2; }
    let zero: Maybe<f32> = Some(-0.0);
    let selected_zero: f32 = unwrap_or(zero, 99.0);
    if (selected_zero != 0.0 || 1.0 / selected_zero >= 0.0) { return 3; }
    let text: Maybe<str> = Some("Ω");
    let absent_text: Maybe<str> = None();
    let character: Maybe<char> = Some('Ω');
    let absent_character: Maybe<char> = None();
    if (unwrap_or(character, '\0') != 'Ω' || unwrap_or(absent_character, '\0') != '\0') { return 4; }
    let present: str = unwrap_or(text, "missing");
    let fallback: str = unwrap_or(absent_text, "fallback");
    std::io::println(present);
    std::io::println(fallback);
    return 0;
}
"#,
        "Ω\nfallback\n".as_bytes(),
    );
}

#[test]
fn option_and_result_fixed_array_payloads_preserve_values_and_independent_copies() {
    execute(
        "optional and result array payloads",
        include_str!("fixtures/stdlib_foundation/repro_option_result_array_payloads.lani"),
    );
    execute_with_stdout(
        "optional and result array element representations",
        include_str!("fixtures/stdlib_foundation/repro_option_result_array_representations.lani"),
        "Ω\n\nbackup\nΩ\n\n".as_bytes(),
    );
}

#[test]
fn local_generic_payload_functions_execute_records() {
    execute(
        "local record payload",
        r#"
module app::main;
struct Pair { left: i32, right: i32 }
struct Wrapped { pair: Pair, tail: i32 }
enum Maybe<T> { Some(T), None }
fn keep<T>(value: T) -> T { return value; }
fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}

fn main() -> i32 {
    let original: Pair = Pair { left: -7, right: 42 };
    let backup: Pair = Pair { left: 99, right: -11 };
    let forwarded: Pair = keep(original);
    if (forwarded.left != -7 || forwarded.right != 42) { return 1; }
    let present: Maybe<Pair> = Some(original);
    let absent: Maybe<Pair> = None();
    let selected: Pair = unwrap_or(present, backup);
    let missing: Pair = unwrap_or(absent, backup);
    if (selected.left != -7 || selected.right != 42) { return 2; }
    if (missing.left != 99 || missing.right != -11) { return 3; }
    let wrapper: Wrapped = Wrapped { pair: original, tail: 123 };
    let copied: Wrapped = keep(wrapper);
    if (copied.pair.left != -7 || copied.pair.right != 42 || copied.tail != 123) { return 4; }
    if (original.left != -7 || original.right != 42) { return 5; }
    return 0;
}
"#,
    );
}

#[test]
fn local_generic_value_functions_preserve_borrowed_slices() {
    execute(
        "local borrowed descriptor",
        r#"
module app::main;
fn keep<T>(value: T) -> T { return value; }
fn choose<T>(left: T, right: T, first: bool) -> T {
    if (first) { return left; }
    return right;
}

fn exercise(values: [i32], other: [i32]) -> i32 {
    let selected: [i32] = choose(values, other, true);
    let recovered: [i32] = keep(selected);
    let count: i32 = 0;
    for value in recovered { count += 1; }
    if (count != 3 || recovered[0] != -7 || recovered[2] != 42) { return 1; }
    recovered[1] = 99;
    if (values[1] != 99) { return 2; }
    let empty: [i32] = choose(values, other, false);
    let empty_copy: [i32] = keep(empty);
    let empty_count: i32 = 0;
    for value in empty_copy { empty_count += 1; }
    if (empty_count != 0) { return 3; }
    return 0;
}
fn main() -> i32 {
    let data: [i32; 3] = [-7, 0, 42];
    let none: [i32; 0] = [];
    return exercise(data, none);
}
"#,
    );
}

#[test]
fn generic_calls_forward_concrete_record_and_slice_types() {
    execute(
        "generic forwarding",
        r#"
module app::main;
struct Pair { left: i32, right: i32 }
fn keep<T>(value: T) -> T { return value; }
fn forward<T>(value: T) -> T { return keep(value); }
fn exercise(values: [i32]) -> i32 {
    let copied: [i32] = forward(values);
    if (copied[0] != -7 || copied[1] != 42) { return 1; }
    copied[0] = 99;
    if (values[0] != 99) { return 2; }
    return 0;
}
fn main() -> i32 {
    let input: Pair = Pair { left: -7, right: 42 };
    let output: Pair = forward(input);
    if (output.left != -7 || output.right != 42) { return 3; }
    if (forward(false)) { return 4; }
    let values: [i32; 2] = [-7, 42];
    return exercise(values);
}
"#,
    );
}

#[test]
fn imported_option_generic_functions_preserve_borrowed_slice_payloads() {
    execute(
        "imported optional descriptor",
        r#"
module app::main;
import core::option;
fn exercise(values: [i32], backup: [i32]) -> i32 {
    let some: core::option::Option<[i32]> = core::option::Some(values);
    let none: core::option::Option<[i32]> = core::option::None();
    let present: [i32] = core::option::unwrap_or(some, backup);
    let absent: [i32] = core::option::unwrap_or(none, backup);
    if (present[0] != -7 || present[2] != 42 || absent[0] != 99) { return 1; }
    present[1] = -11;
    if (values[1] != -11) { return 2; }
    let count: i32 = 0;
    for value in present { count += 1; }
    if (count != 3) { return 3; }
    return 0;
}
fn main() -> i32 {
    let values: [i32; 3] = [-7, 0, 42];
    let backup: [i32; 1] = [99];
    return exercise(values, backup);
}
"#,
    );
}

#[test]
fn imported_generic_functions_preserve_private_record_values() {
    execute(
        "imported private records",
        r#"
module app::main;
import core::mem;
import core::option;
struct Pair { left: i32, right: i32 }
struct Wrapped { pair: Pair, tail: i32 }
fn main() -> i32 {
    let input: Pair = Pair { left: -7, right: 42 };
    let backup: Pair = Pair { left: 99, right: -11 };
    let copied: Pair = core::mem::identity(input);
    let selected: Pair = core::mem::select(false, input, backup);
    if (copied.left != -7 || copied.right != 42 || selected.left != 99 || selected.right != -11) { return 1; }
    let some: core::option::Option<Pair> = core::option::Some(input);
    let none: core::option::Option<Pair> = core::option::None();
    let present: Pair = core::option::unwrap_or(some, backup);
    let absent: Pair = core::option::unwrap_or(none, backup);
    if (present.left != -7 || present.right != 42 || absent.left != 99 || absent.right != -11) { return 2; }
    let wrapper: Wrapped = Wrapped { pair: input, tail: 123 };
    let output: Wrapped = core::mem::identity(wrapper);
    if (output.pair.left != -7 || output.pair.right != 42 || output.tail != 123) { return 3; }
    if (input.left != -7 || input.right != 42) { return 4; }
    return 0;
}
"#,
    );
}

#[test]
fn direct_record_descriptor_fields_have_exact_types() {
    execute_with_stdout(
        "direct descriptor record",
        r#"
module app::main;
import std::io;
struct Window { values: [i32], label: str, marker: i32 }
fn exercise(values: [i32]) -> i32 {
    let input: Window = Window { values: values, label: "hello", marker: -7 };
    if (std::io::println(input.label) != 6 || input.marker != -7 || input.values[1] != 42) { return 1; }
    input.values[0] = 99;
    if (values[0] != 99) { return 2; }
    return 0;
}
fn main() -> i32 {
    let values: [i32; 2] = [-7, 42];
    return exercise(values);
}
"#,
        b"hello\n",
    );
}

#[test]
fn imported_generic_functions_preserve_descriptor_record_fields() {
    execute_with_stdout(
        "imported descriptor record",
        r#"
module app::main;
import core::mem;
import std::io;
struct Window { values: [i32], label: str, marker: i32 }
fn exercise(values: [i32]) -> i32 {
    let input: Window = Window { values: values, label: "hello", marker: -7 };
    let output: Window = core::mem::identity(input);
    if (std::io::println(output.label) != 6 || output.marker != -7 || output.values[1] != 42) { return 1; }
    let recovered: [i32] = output.values;
    let count: i32 = 0;
    for value in recovered { count += 1; }
    if (count != 2) { return 3; }
    output.values[0] = 99;
    if (values[0] != 99) { return 2; }
    return 0;
}
fn main() -> i32 {
    let values: [i32; 2] = [-7, 42];
    return exercise(values);
}
"#,
        b"hello\n",
    );
}

#[test]
fn imported_generic_functions_preserve_enum_values_and_nested_options() {
    execute(
        "imported nested enums",
        r#"
module app::main;
import core::mem;
import core::option;
struct Pair { left: i32, right: i32 }
fn main() -> i32 {
    let input: Pair = Pair { left: -7, right: 42 };
    let some: core::option::Option<Pair> = core::option::Some(input);
    let none: core::option::Option<Pair> = core::option::None();
    let copied: core::option::Option<Pair> = core::mem::identity(some);
    let selected: core::option::Option<Pair> = core::mem::select(false, some, none);
    let present: Pair = core::option::unwrap_or(copied, input);
    if (present.left != -7 || present.right != 42 || core::option::is_some(selected)) { return 1; }
    let outer: core::option::Option<core::option::Option<Pair>> = core::option::Some(some);
    let absent: core::option::Option<core::option::Option<Pair>> = core::option::None();
    let nested: core::option::Option<core::option::Option<Pair>> = core::mem::identity(outer);
    let recovered: core::option::Option<Pair> = core::option::unwrap_or(nested, none);
    let fallback: core::option::Option<Pair> = core::option::unwrap_or(absent, some);
    let left: Pair = core::option::unwrap_or(recovered, input);
    let right: Pair = core::option::unwrap_or(fallback, input);
    if (left.left != -7 || left.right != 42 || right.left != -7 || right.right != 42) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn local_generic_functions_preserve_nested_enum_values() {
    execute(
        "local nested enums",
        r#"
module app::main;
struct Pair { left: i32, right: i32 }
enum Maybe<T> { Some(T), None }
fn keep<T>(value: T) -> T { return value; }
fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}
fn main() -> i32 {
    let input: Pair = Pair { left: -7, right: 42 };
    let backup: Pair = Pair { left: 99, right: -11 };
    let some: Maybe<Pair> = Some(input);
    let none: Maybe<Pair> = None();
    let outer: Maybe<Maybe<Pair>> = Some(some);
    let absent: Maybe<Maybe<Pair>> = None();
    let copied: Maybe<Maybe<Pair>> = keep(outer);
    let present: Maybe<Pair> = unwrap_or(copied, none);
    let fallback: Maybe<Pair> = unwrap_or(absent, some);
    let left: Pair = unwrap_or(present, backup);
    let right: Pair = unwrap_or(fallback, backup);
    if (left.left != -7 || left.right != 42 || right.left != -7 || right.right != 42) { return 1; }
    return 0;
}
"#,
    );
}

#[test]
fn imported_generic_methods_and_results_preserve_compound_payloads() {
    execute(
        "compound methods and Result",
        r#"
module app::main;
import core::option;
import core::result;
struct Pair { left: i32, right: i32 }
fn exercise(values: [i32], backup_values: [i32]) -> i32 {
    let input: Pair = Pair { left: -7, right: 42 };
    let backup: Pair = Pair { left: 99, right: -11 };
    let some: core::option::Option<Pair> = core::option::Some(input);
    let none: core::option::Option<Pair> = core::option::None();
    let left: Pair = some.unwrap_or(backup);
    let right: Pair = none.unwrap_or(backup);
    if (left.left != -7 || left.right != 42 || right.left != 99 || right.right != -11) { return 1; }
    let ok: core::result::Result<Pair, [i32]> = core::result::Ok(input);
    let err: core::result::Result<Pair, [i32]> = core::result::Err(values);
    let successful: Pair = core::result::unwrap_or(ok, backup);
    let failed: Pair = err.unwrap_or(backup);
    if (successful.left != -7 || successful.right != 42 || failed.left != 99 || failed.right != -11) { return 2; }
    let errors: [i32] = core::result::unwrap_err_or(err, backup_values);
    let fallback: [i32] = ok.unwrap_err_or(backup_values);
    if (errors[0] != -7 || errors[1] != 42 || fallback[0] != 99) { return 3; }
    errors[0] = 123;
    if (values[0] != 123) { return 4; }
    let count: i32 = 0;
    for value in errors { count += 1; }
    if (count != 2) { return 5; }
    return 0;
}
fn main() -> i32 {
    let values: [i32; 2] = [-7, 42];
    let backup: [i32; 1] = [99];
    return exercise(values, backup);
}
"#,
    );
}

#[test]
fn generic_inference_preserves_nested_nominal_identity_and_array_lengths() {
    for (label, definitions, values, call) in [
        (
            "local nested nominal mismatch",
            "enum Maybe<T> { Some(T), None } fn choose<T>(left: T, right: T) -> T { return left; }",
            "let left: Maybe<Pair> = Some(pair); let right: Maybe<Other> = Some(other);",
            "choose(left, right)",
        ),
        (
            "imported nested nominal mismatch",
            "import core::mem; import core::option;",
            "let a: core::option::Option<Pair> = core::option::Some(pair); let b: core::option::Option<Other> = core::option::Some(other); let left: core::option::Option<core::option::Option<Pair>> = core::option::Some(a); let right: core::option::Option<core::option::Option<Other>> = core::option::Some(b);",
            "core::mem::select(true, left, right)",
        ),
        (
            "fixed array length mismatch",
            "fn choose<T>(left: T, right: T) -> T { return left; }",
            "let left: [i32; 2] = [-7, 42]; let right: [i32; 3] = [-7, 42, 99];",
            "choose(left, right)",
        ),
        (
            "generic record argument mismatch",
            "import core::mem; struct Cell<T> { value: T, sentinel: i32 }",
            "let left: Cell<i32> = Cell { value: -7, sentinel: 99 }; let right: Cell<bool> = Cell { value: false, sentinel: 99 };",
            "core::mem::select(true, left, right)",
        ),
        (
            "generic record return mismatch",
            "import core::mem; struct Cell<T> { value: T, sentinel: i32 }",
            "let source: Cell<i32> = Cell { value: -7, sentinel: 99 };",
            "let wrong: Cell<bool> = core::mem::identity(source)",
        ),
        (
            "generic nested constructor array length mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> } fn wrap<T>(value: T) -> Holder<T> { return Holder { child: Cell { value: value } }; }",
            "let words: [str; 2] = [\"\", \"Ω\"];",
            "let wrong: Holder<[str; 3]> = wrap(words)",
        ),
        (
            "generic nested constructor array element mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> } fn wrap<T>(value: T) -> Holder<T> { return Holder { child: Cell { value: value } }; }",
            "let values: [i32; 2] = [-7, 42];",
            "let wrong: Holder<[bool; 2]> = wrap(values)",
        ),
        (
            "generic nested constructor nominal result mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> } fn wrap<T>(value: T) -> Holder<T> { return Holder { child: Cell { value: value } }; }",
            "",
            "let wrong: Holder<Other> = wrap(pair)",
        ),
        (
            "generic enum nested array length mismatch",
            "enum Batch<T> { Items([T; 2]), Empty }",
            "let values: [i32; 3] = [-7, 42, 99];",
            "let wrong: Batch<i32> = Items(values)",
        ),
        (
            "generic enum nested array element mismatch",
            "enum Batch<T> { Items([T; 2]), Empty }",
            "let values: [bool; 2] = [false, true];",
            "let wrong: Batch<i32> = Items(values)",
        ),
        (
            "generic enum nested array nominal mismatch",
            "enum Batch<T> { Items([T; 2]), Empty }",
            "let values: [Other; 2] = [other, other];",
            "let wrong: Batch<Pair> = Items(values)",
        ),
        (
            "compound slice nominal mismatch",
            "import core::mem; fn left_view(values: [Pair]) -> [Pair] { return values; } fn right_view(values: [Other]) -> [Other] { return values; }",
            "let left_values: [Pair; 1] = [pair]; let right_values: [Other; 1] = [other]; let left: [Pair] = left_view(left_values); let right: [Other] = right_view(right_values);",
            "core::mem::select(true, left, right)",
        ),
        (
            "compound slice return mismatch",
            "import core::mem; fn view(values: [Pair]) -> [Pair] { return values; }",
            "let values: [Pair; 1] = [pair]; let source: [Pair] = view(values);",
            "let wrong: [Other] = core::mem::identity(source)",
        ),
        (
            "nested slice element nominal mismatch",
            "import core::slice; fn left_row(values: [Pair]) -> [Pair] { return values; } fn right_row(values: [Other]) -> [Other] { return values; } fn view(values: [[Pair]]) -> [[Pair]] { return values; }",
            "let pair_values: [Pair; 1] = [pair]; let other_values: [Other; 1] = [other]; let first: [Pair] = left_row(pair_values); let wrong: [Other] = right_row(other_values); let rows: [[Pair]; 1] = [first]; let left: [[Pair]] = view(rows);",
            "core::slice::set(left, 1, 0, wrong)",
        ),
        (
            "forwarded compound slice nominal mismatch",
            "import core::mem; fn keep<T>(value: T) -> T { return value; } fn left_view(values: [Pair]) -> [Pair] { return values; } fn right_view(values: [Other]) -> [Other] { return values; }",
            "let left_values: [Pair; 1] = [pair]; let right_values: [Other; 1] = [other]; let left: [Pair] = left_view(left_values); let right: [Other] = right_view(right_values);",
            "core::mem::select(true, keep(left), right)",
        ),
        (
            "forwarded optional compound slice mismatch",
            "import core::option; fn keep<T>(value: T) -> T { return value; } fn left_view(values: [Pair]) -> [Pair] { return values; } fn right_view(values: [Other]) -> [Other] { return values; }",
            "let left_values: [Pair; 1] = [pair]; let right_values: [Other; 1] = [other]; let left: [Pair] = left_view(left_values); let right: [Other] = right_view(right_values); let some: core::option::Option<[Pair]> = core::option::Some(left);",
            "core::option::unwrap_or(keep(some), right)",
        ),
        (
            "nested array slice length mismatch",
            "import core::mem; fn short_view(values: [[i32; 2]]) -> [[i32; 2]] { return values; } fn long_view(values: [[i32; 3]]) -> [[i32; 3]] { return values; }",
            "let short_row: [i32; 2] = [-7, 42]; let long_row: [i32; 3] = [-7, 42, 99]; let shorts: [[i32; 2]; 1] = [short_row]; let longs: [[i32; 3]; 1] = [long_row]; let left: [[i32; 2]] = short_view(shorts); let right: [[i32; 3]] = long_view(longs);",
            "core::mem::select(true, left, right)",
        ),
        (
            "match array length mismatch",
            "",
            "let left: [i32; 2] = [-7, 42]; let right: [i32; 3] = [-7, 42, 99];",
            "match (true) { true -> left, false -> right }",
        ),
        (
            "nested declaration field parameter order mismatch",
            "struct Cell<T> { value: T } struct Holder<A, B> { marker: A, child: Cell<B> }",
            "let number: Cell<i32> = Cell { value: -7 }; let flag: Cell<bool> = Cell { value: false };",
            "let wrong: Holder<i32, bool> = Holder { marker: 99, child: number }",
        ),
        (
            "generated nested scalar mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> }",
            "",
            "let wrong: Holder<i32> = Holder { child: Cell { value: false } }",
        ),
        (
            "generated nested record payload mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> }",
            "",
            "let wrong: Holder<Pair> = Holder { child: Cell { value: Other { left: -7, right: 42 } } }",
        ),
        (
            "generated nested nominal mismatch",
            "struct Cell<T> { value: T } struct OtherCell<T> { value: T } struct Holder<T> { child: Cell<T> }",
            "",
            "let wrong: Holder<i32> = Holder { child: OtherCell { value: -7 } }",
        ),
        (
            "nested declaration field nominal mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<T> }",
            "let left: Cell<Pair> = Cell { value: pair }; let right: Cell<Other> = Cell { value: other };",
            "let wrong: Holder<Other> = Holder { child: left }",
        ),
        (
            "nested declaration field array length mismatch",
            "struct Cell<T> { value: T } struct Holder<T> { child: Cell<[T; 3]> }",
            "let short_values: [i32; 2] = [-7, 42]; let long_values: [i32; 3] = [-7, 42, 99]; let short: Cell<[i32; 2]> = Cell { value: short_values }; let long: Cell<[i32; 3]> = Cell { value: long_values };",
            "let wrong: Holder<i32> = Holder { child: short }",
        ),
        (
            "match generic record identity mismatch",
            "struct Cell<T> { value: T, sentinel: i32 }",
            "let left: Cell<i32> = Cell { value: -7, sentinel: 99 }; let right: Cell<bool> = Cell { value: false, sentinel: 99 };",
            "match (true) { true -> left, false -> right }",
        ),
        (
            "scalar array element argument mismatch",
            "import std::io;",
            "let flags: [bool; 2] = [false, true];",
            "std::io::print_i32(flags[0])",
        ),
    ] {
        let source = format!(
            r#"
module app::main;
{definitions}
struct Pair {{ left: i32, right: i32 }}
struct Other {{ left: i32, right: i32 }}
fn main() -> i32 {{
    let pair: Pair = Pair {{ left: -7, right: 42 }};
    let other: Other = Other {{ left: -7, right: 42 }};
    {values}
    {call};
    return 0;
}}
"#
        );
        let entry = common::TempArtifact::new("generic_types", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| panic!("{label}: incompatible checked types were accepted"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic
                .primary_label
                .as_ref()
                .and_then(|label| label.source_line.as_ref())
                .is_some_and(|line| line.contains(call)),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn generic_slice_operations_preserve_record_element_layouts() {
    execute(
        "generic record slice elements",
        r#"
module app::main;
import core::slice;
struct Pair { left: i32, right: i32 }
fn exercise(values: [Pair], empty: [Pair], destination: [Pair]) -> i32 {
    let backup: Pair = Pair { left: 99, right: -11 };
    let first: Pair = core::slice::first(values);
    let absent: Pair = core::slice::first_or(empty, 0, backup);
    let last: Pair = core::slice::get_or(values, 3, 2, backup);
    let invalid: Pair = core::slice::get_or(values, 3, -1, backup);
    if (first.left != -7 || first.right != 42 || absent.left != 99 || absent.right != -11) { return 1; }
    if (last.left != 123 || last.right != -9 || invalid.left != 99 || invalid.right != -11) { return 2; }
    if (!core::slice::set(values, 3, 1, first) || core::slice::set(values, 3, 3, backup)) { return 3; }
    if (!core::slice::swap(values, 3, 0, 2) || core::slice::swap(values, 3, -1, 1)) { return 4; }
    if (core::slice::reverse_in_place(values, 3) != 1) { return 5; }
    let restored: Pair = values[0];
    if (restored.left != -7 || restored.right != 42) { return 6; }
    if (core::slice::fill(destination, 3, backup) != 3) { return 7; }
    if (!core::slice::copy_nonoverlapping_prefix(destination, 3, values, 3)) { return 8; }
    let copied: Pair = destination[2];
    if (copied.left != 123 || copied.right != -9) { return 9; }
    if (!core::slice::copy_within(values, 3, 0, 2, 1)) { return 10; }
    let moved: Pair = values[2];
    if (moved.left != -7 || moved.right != 42) { return 11; }
    return 0;
}
fn main() -> i32 {
    let a: Pair = Pair { left: -7, right: 42 };
    let b: Pair = Pair { left: 99, right: -11 };
    let c: Pair = Pair { left: 123, right: -9 };
    let values: [Pair; 3] = [a, b, c];
    let destination: [Pair; 3] = [b, b, b];
    let empty: [Pair; 0] = [];
    return exercise(values, empty, destination);
}
"#,
    );
}

#[test]
fn direct_string_slice_access_preserves_descriptors() {
    execute_with_stdout(
        "direct string slice elements",
        r#"
module app::main;
import std::io;
fn exercise(values: [str]) -> i32 {
    let first: str = values[0];
    let last: str = values[2];
    if (std::io::println(first) != 6 || std::io::println(last) != 1) { return 1; }
    return 0;
}
fn main() -> i32 {
    let values: [str; 3] = ["hello", "world", ""];
    return exercise(values);
}
"#,
        b"hello\n\n",
    );
}

#[test]
fn generic_slice_operations_preserve_string_element_descriptors() {
    execute_with_stdout(
        "generic string slice elements",
        r#"
module app::main;
import core::slice;
import std::io;
fn exercise(values: [str]) -> i32 {
    let first: str = core::slice::first(values);
    let last: str = core::slice::get_or(values, 3, 2, "fallback");
    if (std::io::println(first) != 6 || std::io::println(last) != 1) { return 1; }
    if (!core::slice::swap(values, 3, 0, 2)) { return 2; }
    let changed: str = values[2];
    if (std::io::println(changed) != 6) { return 3; }
    if (core::slice::fill(values, 3, "Ω") != 3) { return 4; }
    let filled: str = values[1];
    if (std::io::println(filled) != 3) { return 5; }
    return 0;
}
fn main() -> i32 {
    let values: [str; 3] = ["hello", "world", ""];
    return exercise(values);
}
"#,
        "hello\n\nhello\nΩ\n".as_bytes(),
    );
}

#[test]
fn local_generic_functions_preserve_fixed_array_values() {
    execute(
        "local fixed array values",
        r#"
module app::main;
fn keep<T>(value: T) -> T { return value; }
fn forward<T>(value: T) -> T { return keep(value); }
fn main() -> i32 {
    let original: [i32; 3] = [-7, 0, 42];
    let output: [i32; 3] = keep(original);
    if (output[0] != -7 || output[1] != 0 || output[2] != 42) { return 1; }
    let count: i32 = 0;
    for value in output { count += 1; }
    if (count != 3) { return 2; }
    output[1] = 99;
    if (original[1] != 0 || output[1] != 99) { return 3; }
    let one: [i32; 1] = [-2147483648];
    let one_copy: [i32; 1] = forward(one);
    if (one_copy[0] != -2147483648) { return 4; }
    let two: [i32; 2] = [-7, 2147483647];
    let two_copy: [i32; 2] = forward(two);
    if (two_copy[0] != -7 || two_copy[1] != 2147483647) { return 5; }
    let five: [i32; 5] = [-7, 0, 42, -2147483648, 2147483647];
    let five_copy: [i32; 5] = forward(five);
    let index: i32 = 0;
    for value in five_copy {
        if (value != five[index]) { return 6; }
        index += 1;
    }
    if (index != 5) { return 7; }
    return 0;
}
"#,
    );
}

#[test]
fn imported_generic_functions_preserve_fixed_array_element_representations() {
    execute_with_stdout(
        "fixed array element representations",
        r#"
module app::main;
import core::mem;
import std::io;
fn main() -> i32 {
    let flags: [bool; 2] = [false, true];
    let flags_copy: [bool; 2] = core::mem::identity(flags);
    if (flags_copy[0] || !flags_copy[1]) { return 1; }
    flags_copy[0] = true;
    if (flags[0]) { return 2; }
    let high: u32 = 4294967295;
    let zero: u32 = 0;
    let unsigned: [u32; 2] = [high, zero];
    let unsigned_copy: [u32; 2] = core::mem::identity(unsigned);
    if (unsigned_copy[0] != high || unsigned_copy[1] != 0) { return 3; }
    let floats: [f32; 3] = [-2.5, -0.0, 7.5];
    let floats_copy: [f32; 3] = core::mem::identity(floats);
    if (floats_copy[0] != -2.5 || floats_copy[2] != 7.5) { return 4; }
    if (floats_copy[1] != 0.0 || 1.0 / floats_copy[1] >= 0.0) { return 5; }
    let chars: [char; 1] = ['Ω'];
    let chars_copy: [char; 1] = core::mem::identity(chars);
    if (chars_copy[0] != 'Ω') { return 6; }
    let strings: [str; 3] = ["first", "", "Ω"];
    let strings_copy: [str; 3] = core::mem::identity(strings);
    let first: str = strings_copy[0];
    let empty: str = strings_copy[1];
    let last: str = strings_copy[2];
    if (std::io::println(first) != 6 || std::io::println(empty) != 1 || std::io::println(last) != 3) { return 7; }
    strings_copy[0] = "changed";
    let original: str = strings[0];
    let changed: str = strings_copy[0];
    if (std::io::println(original) != 6 || std::io::println(changed) != 8) { return 8; }
    return 0;
}
"#,
        "first\n\nΩ\nfirst\nchanged\n".as_bytes(),
    );
}

#[test]
fn imported_generic_functions_preserve_fixed_array_values() {
    execute(
        "imported fixed array values",
        r#"
module app::main;
import core::mem;
fn main() -> i32 {
    let original: [i32; 3] = [-7, 0, 42];
    let output: [i32; 3] = core::mem::identity(original);
    if (output[0] != -7 || output[1] != 0 || output[2] != 42) { return 1; }
    let count: i32 = 0;
    for value in output { count += 1; }
    if (count != 3) { return 2; }
    output[1] = 99;
    if (original[1] != 0 || output[1] != 99) { return 3; }
    let one: [i32; 1] = [-2147483648];
    let one_copy: [i32; 1] = core::mem::identity(one);
    if (one_copy[0] != -2147483648) { return 4; }
    let left: [i32; 2] = [-7, 2147483647];
    let right: [i32; 2] = [42, -2147483648];
    let left_copy: [i32; 2] = core::mem::select(true, left, right);
    let right_copy: [i32; 2] = core::mem::select(false, left, right);
    if (left_copy[0] != -7 || left_copy[1] != 2147483647) { return 5; }
    if (right_copy[0] != 42 || right_copy[1] != -2147483648) { return 6; }
    let five: [i32; 5] = [-7, 0, 42, -2147483648, 2147483647];
    let five_copy: [i32; 5] = core::mem::identity(five);
    let index: i32 = 0;
    for value in five_copy {
        if (value != five[index]) { return 7; }
        index += 1;
    }
    if (index != 5) { return 8; }
    return 0;
}
"#,
    );
}

#[test]
fn inline_fixed_array_call_arguments_preserve_values() {
    for (name, ty, values, checks, stdout) in [
        (
            "strings",
            "str",
            "[\"Ω\", \"end\"]",
            "std::io::println(copied[0]); std::io::println(copied[1]); copied[0] = \"replacement\"; std::io::println(container.values[0]);",
            "Ω\nend\nΩ\n",
        ),
        (
            "bools",
            "bool",
            "[false, true]",
            "if (copied[0] || !copied[1]) { return 1; } copied[0] = true; if (container.values[0]) { return 2; }",
            "",
        ),
        (
            "records",
            "Pair",
            "[Pair { first: -7, last: 42 }, Pair { first: 13, last: 91 }]",
            "if (copied[0].first != -7 || copied[0].last != 42 || copied[1].first != 13 || copied[1].last != 91) { return 1; } copied[0].last = 8; if (container.values[0].last != 42) { return 2; }",
            "",
        ),
    ] {
        for generic in [false, true] {
            let function = if generic {
                "fn copy<T>(values: T) -> T { return values; }".to_owned()
            } else {
                format!("fn copy(values: [{ty}; 2]) -> [{ty}; 2] {{ return values; }}")
            };
            let source = format!(
                "module app::main; import std::io; struct Pair {{ first: i32, last: i32 }} struct Container {{ values: [{ty}; 2] }} {function} fn main() -> i32 {{ let container: Container = Container {{ values: {values} }}; let copied: [{ty}; 2] = copy(container.values); {checks} return 0; }}"
            );
            execute_with_stdout(
                &format!("inline array {name}, generic={generic}"),
                &source,
                stdout.as_bytes(),
            );
        }
    }
}

#[test]
fn ordinary_inline_packed_array_arguments_preserve_values() {
    execute(
        "ordinary inline packed array argument",
        include_str!("fixtures/stdlib_foundation/repro_ordinary_inline_i32_array_call.lani"),
    );
}

fn check_aggregate_value_parameter(generic: bool) {
    let (label, declarations, ty) = if generic {
        (
            "generic",
            "struct Cell<T> { value: T, sentinel: i32 } fn replace<T>(cell: Cell<T>, replacement: T) -> i32 { cell.value = replacement; return cell.sentinel; }",
            "Cell<i32>",
        )
    } else {
        (
            "ordinary",
            "struct Cell { value: i32, sentinel: i32 } fn replace(cell: Cell, replacement: i32) -> i32 { cell.value = replacement; return cell.sentinel; }",
            "Cell",
        )
    };
    execute(
        &format!("{label} parameter value copies"),
        &format!(
            r#"
{declarations}
fn main() -> i32 {{
    let original: {ty} = Cell {{ value: 11, sentinel: 42 }};
    if (replace(original, 22) != 42) {{ return 1; }}
    if (original.value != 11 || original.sentinel != 42) {{ return 2; }}
    return 0;
}}
"#
        ),
    );
}

#[test]
fn ordinary_aggregate_value_parameters_preserve_caller_storage() {
    check_aggregate_value_parameter(false);
}

#[test]
fn generic_aggregate_value_parameters_preserve_caller_storage() {
    check_aggregate_value_parameter(true);
}

#[test]
fn fixed_array_value_parameters_copy_before_mutation() {
    execute_with_stdout(
        "fixed array parameter copies",
        r#"
module app::main;
import std::io;
fn replace<T>(values: [T; 3], replacement: T) -> T {
    let previous: T = values[1];
    values[1] = replacement;
    return previous;
}
fn replace_five(values: [i32; 5]) -> i32 {
    values[0] = 91;
    values[4] = 92;
    return values[0] + values[4];
}
fn main() -> i32 {
    let numbers: [i32; 3] = [-7, -2147483648, 2147483647];
    if (replace(numbers, 42) != -2147483648) { return 1; }
    if (numbers[0] != -7 || numbers[1] != -2147483648 || numbers[2] != 2147483647) { return 2; }
    let odd: [i32; 5] = [1, 2, 3, 4, 5];
    if (replace_five(odd) != 183 || odd[0] != 1 || odd[4] != 5) { return 3; }
    let flags: [bool; 3] = [false, true, false];
    if (!replace(flags, false) || !flags[1]) { return 4; }
    let strings: [str; 3] = ["first", "Ω", "last"];
    std::io::println(replace(strings, "changed"));
    std::io::println(strings[1]);
    return 0;
}
"#,
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn aggregate_parameter_copies_preserve_nested_borrows() {
    execute_with_stdout(
        "record copies preserve borrowed backing",
        r#"
module app::main;
import std::io;
struct Cell<T> { value: T }
struct Bundle<T> { owned: T, view: [i32], label: str }
fn view(values: [i32]) -> [i32] { return values; }
fn replace<T>(bundle: Bundle<T>, replacement: T) -> i32 {
    bundle.owned = replacement;
    bundle.view[1] = 77;
    std::io::println(bundle.label);
    bundle.label = "changed";
    return bundle.view[0];
}
fn main() -> i32 {
    let backing: [i32; 2] = [11, 22];
    let original: Bundle<Cell<i32>> = Bundle {
        owned: Cell { value: -7 }, view: view(backing), label: "Ω"
    };
    let replacement: Cell<i32> = Cell { value: 42 };
    if (replace(original, replacement) != 11) { return 1; }
    if (original.owned.value != -7 || replacement.value != 42) { return 2; }
    if (backing[1] != 77 || original.view[1] != 77) { return 3; }
    std::io::println(original.label);
    return 0;
}
"#,
        "Ω\nΩ\n".as_bytes(),
    );
}

#[test]
fn aggregate_parameter_copies_preserve_stack_and_register_arguments() {
    execute(
        "multiple value parameters across argument registers",
        r#"
struct Cell<T> { value: T, sentinel: i32 }
fn change<T>(a: i32, left: Cell<T>, b: i32, right: Cell<T>, c: i32,
             replacement: T, d: i32, e: i32, f: i32) -> i32 {
    left.value = replacement;
    right.value = replacement;
    return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + left.sentinel + right.sentinel;
}
fn main() -> i32 {
    let left: Cell<i32> = Cell { value: 11, sentinel: 42 };
    let right: Cell<i32> = Cell { value: 22, sentinel: 91 };
    if (change(1, left, 2, right, 3, 99, 4, 5, 6) != 224) { return 1; }
    if (left.value != 11 || left.sentinel != 42 || right.value != 22 || right.sentinel != 91) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn concrete_nominal_parameters_retain_complete_return_types() {
    execute(
        "concrete nominal parameter return",
        "struct Cell<T> { value: T, sentinel: i32 } fn keep(cell: Cell<i32>) -> Cell<i32> { return cell; } fn main() -> i32 { let original: Cell<i32> = Cell { value: 11, sentinel: 42 }; let copied: Cell<i32> = keep(original); if (copied.value != 11 || copied.sentinel != 42) { return 1; } return 0; }",
    );
    execute(
        "concrete nominal parameter return after field assignment",
        include_str!(
            "fixtures/stdlib_foundation/repro_nominal_parameter_after_field_assignment.lani"
        ),
    );
}

#[test]
fn concrete_nominal_parameters_reject_incompatible_returns() {
    for result in ["i32", "Cell<bool>"] {
        let source = format!(
            "struct Cell<T> {{ value: T, sentinel: i32 }} fn wrong(cell: Cell<i32>) -> {result} {{ cell.value = 22; return cell; }} fn main() -> i32 {{ let cell: Cell<i32> = Cell {{ value: 11, sentinel: 42 }}; let output: {result} = wrong(cell); return 0; }}"
        );
        let entry =
            common::TempArtifact::new("generic_types", "nominal_return_mismatch", Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error =
            common::run_gpu_codegen_with_timeout("incompatible nominal return", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            })
            .expect_err("a complete nominal parameter type must constrain its return");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{result}: {error:?}"
        );
    }
}

#[test]
fn concrete_nominal_parameters_reject_incompatible_arguments() {
    for value in ["42", "Cell { value: false, sentinel: 42 }"] {
        let source = format!(
            "struct Cell<T> {{ value: T, sentinel: i32 }} fn replace(cell: Cell<i32>) -> Cell<i32> {{ cell.value = 22; return cell; }} fn main() -> i32 {{ let result: Cell<i32> = replace({value}); return 0; }}"
        );
        let entry =
            common::TempArtifact::new("generic_types", "nominal_argument_mismatch", Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error =
            common::run_gpu_codegen_with_timeout("incompatible nominal argument", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            })
            .expect_err("complete nominal argument constraints must reject mismatches");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{value}: {error:?}"
        );
    }
}

fn check_argument_value_before_later_effect(generic: bool) {
    let function = if generic {
        "fn first<T>(value: T, effect: i32) -> T { return value; }"
    } else {
        "fn first(value: [i32; 3], effect: i32) -> [i32; 3] { return value; }"
    };
    execute(
        &format!("argument value before later effect, generic={generic}"),
        &format!(
            r#"
{function}
fn change(values: [i32]) -> i32 {{ values[0] = 99; return 0; }}
fn main() -> i32 {{
    let values: [i32; 3] = [11, 22, 33];
    let before: [i32; 3] = first(values, change(values));
    if (before[0] != 11 || before[1] != 22 || before[2] != 33) {{ return 1; }}
    if (values[0] != 99 || values[1] != 22 || values[2] != 33) {{ return 2; }}
    return 0;
}}
"#,
        ),
    );
}

#[test]
fn ordinary_value_arguments_are_captured_before_later_argument_effects() {
    check_argument_value_before_later_effect(false);
}

#[test]
fn generic_value_arguments_are_captured_before_later_argument_effects() {
    check_argument_value_before_later_effect(true);
}

fn many_concrete_nominal_parameter_source(arity: usize, mismatch: bool) -> String {
    let parameters = (0..arity)
        .map(|i| format!("T{i}"))
        .collect::<Vec<_>>()
        .join(", ");
    let fields = (0..arity)
        .map(|i| format!("field{i}: T{i}"))
        .collect::<Vec<_>>()
        .join(", ");
    let expected = vec!["Cell<i32>"; arity].join(", ");
    let actual = (0..arity)
        .map(|i| {
            if mismatch && i + 1 == arity {
                "Cell<bool>"
            } else {
                "Cell<i32>"
            }
        })
        .collect::<Vec<_>>()
        .join(", ");
    let values = (0..arity)
        .map(|i| {
            let value = if mismatch && i + 1 == arity {
                "false".to_owned()
            } else {
                i.to_string()
            };
            format!("field{i}: Cell {{ value: {value} }}")
        })
        .collect::<Vec<_>>()
        .join(", ");
    format!(
        "struct Cell<T> {{ value: T }} struct Many<{parameters}> {{ {fields} }} fn consume(value: Many<{expected}>) -> i32 {{ return value.field{}.value; }} fn main() -> i32 {{ let value: Many<{actual}> = Many {{ {values} }}; if (consume(value) != {}) {{ return 1; }} return 0; }}",
        arity - 1,
        arity - 1,
    )
}

#[test]
fn concrete_nominal_parameters_preserve_all_nested_type_arguments() {
    for arity in [6, 32] {
        execute(
            &format!("concrete nested nominal parameter with {arity} arguments"),
            &many_concrete_nominal_parameter_source(arity, false),
        );
    }
}

#[test]
fn concrete_nominal_parameters_reject_late_nested_type_argument_mismatches() {
    for arity in [6, 32] {
        let entry = common::TempArtifact::new(
            "generic_types",
            "concrete_nested_nominal_mismatch",
            Some("lani"),
        );
        entry.write_str(&many_concrete_nominal_parameter_source(arity, true));
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(
            "late nested nominal argument mismatch",
            move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib)),
        )
        .err()
        .expect("every ordered nested argument must be checked");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "arity {arity}: {error:?}"
        );
    }
}

#[test]
fn argument_capture_preserves_record_values_and_nested_slice_aliases() {
    for generic in [false, true] {
        let first = if generic {
            "fn first<T>(value: T, effect: i32) -> T { return value; }"
        } else {
            "fn first(value: Item, effect: i32) -> Item { return value; }"
        };
        execute_with_stdout(
            &format!("record argument capture, generic={generic}"),
            &format!(
                r#"
module app::main;
import std::io;
struct Item {{ number: i32, text: str, values: [i32] }}
{first}
fn borrow(values: [i32]) -> [i32] {{ return values; }}
fn change(items: [Item]) -> i32 {{
    items[0].number = 99;
    items[0].text = "new";
    items[0].values[0] = 88;
    return 0;
}}
fn main() -> i32 {{
    let values: [i32; 3] = [11, 22, 33];
    let items: [Item; 1] = [Item {{ number: -7, text: "Ω", values: borrow(values) }}];
    let before: Item = first(items[0], change(items));
    if (before.number != -7 || items[0].number != 99) {{ return 1; }}
    std::io::println(before.text);
    std::io::println(items[0].text);
    if (before.values[0] != 88 || values[0] != 88) {{ return 2; }}
    before.values[2] = 44;
    if (values[2] != 44 || items[0].values[2] != 44) {{ return 3; }}
    return 0;
}}
"#
            ),
            "Ω\nnew\n".as_bytes(),
        );
    }
}

#[test]
fn argument_capture_preserves_slice_descriptor_values() {
    for generic in [false, true] {
        let first = if generic {
            "fn first<T>(value: T, effect: i32) -> T { return value; }"
        } else {
            "fn first(value: [i32], effect: i32) -> [i32] { return value; }"
        };
        execute(
            &format!("slice descriptor argument capture, generic={generic}"),
            &format!(
                r#"
struct View {{ values: [i32] }}
{first}
fn borrow(values: [i32]) -> [i32] {{ return values; }}
fn replace(items: [View], replacement: [i32]) -> i32 {{
    items[0].values = replacement;
    return 0;
}}
fn main() -> i32 {{
    let original: [i32; 3] = [11, 22, 33];
    let replacement: [i32; 2] = [88, 99];
    let items: [View; 1] = [View {{ values: borrow(original) }}];
    let before: [i32] = first(items[0].values, replace(items, replacement));
    if (before[0] != 11 || before[2] != 33 || items[0].values[0] != 88) {{ return 1; }}
    before[1] = 44;
    if (original[1] != 44 || replacement[1] != 99) {{ return 2; }}
    return 0;
}}
"#
            ),
        );
    }
}

#[test]
fn imported_argument_values_are_captured_before_later_effects() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/capture.lani"),
        r#"
module core::capture;
pub fn first<T>(value: T, effect: i32) -> T { return value; }
pub fn array(value: [i32; 3], effect: i32) -> [i32; 3] { return value; }
pub fn view(value: [i32], effect: i32) -> [i32] { return value; }
"#,
    )
    .expect("argument capture module");
    let entry =
        common::TempArtifact::new("generic_types", "imported_argument_capture", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::capture;
struct Container { values: [i32; 3] }
fn change(values: [i32]) -> i32 { values[0] = 99; return 0; }
fn main() -> i32 {
    let values: [i32; 3] = [11, 22, 33];
    let first: [i32; 3] = core::capture::first(values, change(values));
    if (first[0] != 11 || first[1] != 22 || first[2] != 33 || values[0] != 99) { return 1; }
    values[0] = 11;
    let second: [i32; 3] = core::capture::array(values, change(values));
    if (second[0] != 11 || second[2] != 33 || values[0] != 99) { return 2; }
    values[0] = 11;
    let shared: [i32] = core::capture::view(values, change(values));
    if (shared[0] != 99 || shared[2] != 33) { return 3; }
    shared[1] = 44;
    if (values[1] != 44) { return 4; }
    let container: Container = Container { values: [7, 8, 9] };
    let inline: [i32; 3] = core::capture::first(container.values, 0);
    if (inline[0] != 7 || inline[1] != 8 || inline[2] != 9) { return 5; }
    return 0;
}
"#,
    );
    let path = entry.path().to_path_buf();
    let root = stdlib.0.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("imported argument capture", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    })
    .expect("compile imported value and borrowed arguments");
    let output =
        common::run_x86_64_elf_output("imported argument capture", "generic_types", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn generic_array_argument_capture_preserves_following_slice_arguments() {
    execute(
        "native array capture before borrowed slice",
        r#"
fn second<T>(value: T, values: [i32]) -> [i32] { return values; }
fn main() -> i32 {
    let words: [str; 2] = ["Ω", ""];
    let numbers: [i32; 3] = [11, 22, 33];
    let shared: [i32] = second(words, numbers);
    if (shared[0] != 11 || shared[2] != 33) { return 1; }
    shared[1] = 44;
    if (numbers[1] != 44) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn indexed_array_arguments_preserve_inner_length_and_value() {
    for (label, declaration, forward) in [
        (
            "ordinary",
            "fn keep(value: [str; 3]) -> [str; 3] { return value; }",
            "keep",
        ),
        (
            "local generic",
            "fn keep<T>(value: T) -> T { return value; }",
            "keep",
        ),
        ("imported generic", "", "core::mem::identity"),
    ] {
        execute_with_stdout(
            &format!("indexed array argument, {label}"),
            &format!(
                r#"
module app::main;
import core::mem;
import std::io;
{declaration}
fn count(values: [str]) -> i32 {{
    let size: i32 = 0;
    for value in values {{ size += 1; }}
    return size;
}}
fn main() -> i32 {{
    let first: [str; 3] = ["one", "two", "three"];
    let second: [str; 3] = ["Ω", "", "last"];
    let rows: [[str; 3]; 2] = [first, second];
    let copied: [str; 3] = {forward}(rows[1]);
    if (count(copied) != 3) {{ return 1; }}
    std::io::println(copied[0]);
    std::io::println(copied[1]);
    std::io::println(copied[2]);
    copied[2] = "changed";
    std::io::println(rows[1][2]);
    return 0;
}}
"#
            ),
            "Ω\n\nlast\nlast\n".as_bytes(),
        );
    }
}

#[test]
fn indexed_array_borrows_preserve_inner_length_and_aliases() {
    execute_with_stdout(
        "indexed array borrowed length",
        r#"
module app::main;
import core::mem;
import std::io;
fn view(values: [str]) -> [str] { return values; }
fn keep<T>(value: T) -> T { return core::mem::identity(value); }
fn count(values: [str]) -> i32 {
    let size: i32 = 0;
    for value in values { size += 1; }
    return size;
}
fn main() -> i32 {
    let first: [str; 3] = ["one", "two", "three"];
    let second: [str; 3] = ["Ω", "", "last"];
    let rows: [[str; 3]; 2] = [first, second];
    let borrowed: [str] = view(rows[1]);
    let shared: [str] = keep(borrowed);
    if (count(shared) != 3) { return 1; }
    std::io::println(shared[0]);
    std::io::println(shared[2]);
    shared[2] = "changed";
    std::io::println(rows[1][2]);
    std::io::println(second[2]);
    return 0;
}
"#,
        "Ω\nlast\nchanged\nlast\n".as_bytes(),
    );
}

#[test]
fn inline_array_borrows_preserve_elements_and_aliases() {
    execute(
        "inline array borrowed storage",
        r#"
module app::main;
import core::mem;
struct Container { before: i32, values: [i32; 3], after: i32 }
fn view(values: [i32]) -> [i32] { return values; }
fn keep<T>(value: T) -> T { return core::mem::identity(value); }
fn main() -> i32 {
    let item: Container = Container { before: -7, values: [11, 22, 33], after: 99 };
    let borrowed: [i32] = view(item.values);
    let shared: [i32] = keep(borrowed);
    if (shared[0] != 11 || shared[1] != 22 || shared[2] != 33) { return 1; }
    shared[1] = 44;
    if (item.values[1] != 44 || item.before != -7 || item.after != 99) { return 2; }
    item.values[2] = 55;
    if (shared[2] != 55 || item.values[0] != 11) { return 3; }
    return 0;
}
"#,
    );
}

#[test]
fn nested_ordinary_slice_returns_supply_generic_arguments() {
    execute(
        "ordinary slice call as generic argument",
        r#"
module app::main;
import core::mem;
fn view(values: [i32]) -> [i32] { return values; }
fn keep<T>(value: T) -> T { return core::mem::identity(value); }
fn main() -> i32 {
    let values: [i32; 3] = [11, 22, 33];
    let shared: [i32] = keep(view(values));
    if (shared[0] != 11 || shared[2] != 33) { return 1; }
    shared[1] = 44;
    if (values[1] != 44) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn nested_concrete_returns_preserve_complete_types_through_generic_calls() {
    for (label, forward) in [("local", "keep"), ("imported", "core::mem::identity")] {
        execute_with_stdout(
            &format!("nested concrete returns through {label} generics"),
            &format!(
                r#"
module app::main;
import core::mem;
import std::io;
struct Empty {{}}
struct Cell<T> {{ value: T, sentinel: i32 }}
fn keep<T>(value: T) -> T {{ return value; }}
fn view(values: [str]) -> [str] {{ return values; }}
fn array(values: [str; 3]) -> [str; 3] {{ return values; }}
fn cell(values: [str; 3]) -> Cell<[str; 3]> {{
    return Cell {{ value: values, sentinel: -91 }};
}}
fn empty() -> [Empty; 0] {{ return []; }}
fn main() -> i32 {{
    let values: [str; 3] = ["Ω", "", "last"];
    let shared = {forward}(view(values));
    let copied = {forward}(array(values));
    let wrapped = {forward}(cell(values));
    let nothing = {forward}(empty());
    let total: i32 = 0;
    for item in nothing {{ total += 1; }}
    if (total != 0 || wrapped.sentinel != -91) {{ return 1; }}
    shared[2] = "changed";
    std::io::println(values[2]);
    std::io::println(copied[2]);
    std::io::println(wrapped.value[2]);
    copied[0] = "copy";
    std::io::println(values[0]);
    std::io::println(copied[0]);
    return 0;
}}
"#
            ),
            "changed\nlast\nlast\nΩ\ncopy\n".as_bytes(),
        );
    }
}

#[test]
fn nested_concrete_return_arguments_reject_conflicting_generic_constraints() {
    for second in ["false", "numbers", "view(numbers)"] {
        let entry =
            common::TempArtifact::new("generic_types", "nested_return_conflict", Some("lani"));
        entry.write_str(&format!(
            r#"
fn same<T>(left: T, right: T) -> T {{ return left; }}
fn view(values: [i32]) -> [i32] {{ return values; }}
fn strings(values: [str]) -> [str] {{ return values; }}
fn main() -> i32 {{
    let words: [str; 2] = ["Ω", ""];
    let numbers: [i32; 2] = [11, 22];
    let result = same(strings(words), {second});
    return 0;
}}
"#
        ));
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error =
            common::run_gpu_codegen_with_timeout("nested concrete return conflict", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            })
            .expect_err("nested complete return types must constrain every generic argument");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{second}: {error:?}"
        );
    }
}

#[test]
fn ordinary_inline_array_borrows_preserve_elements_and_aliases() {
    execute(
        "ordinary inline array borrowed storage",
        include_str!("fixtures/stdlib_foundation/repro_ordinary_inline_array_borrow.lani"),
    );
}

#[test]
fn slice_strides_preserve_mixed_backing_across_calls_and_value_copies() {
    execute_with_stdout("mixed slice backing and descriptor copies", include_str!(
        "fixtures/stdlib_foundation/slice_stride_compositions.lani"), b"native\npacked\n");
}

#[test]
fn native_backed_slices_enforce_logical_bounds() {
    for index in [-1, 3] {
        execute_with_status("native slice logical bounds", &format!(r#"
struct Container {{ values: [i32; 3] }}
fn view(values: [i32]) -> [i32] {{ return values; }}
fn read(values: [i32], index: i32) -> i32 {{ return values[index]; }}
fn main() -> i32 {{
    let owner: Container = Container {{ values: [11, 22, 33] }};
    return read(view(owner.values), {index});
}}
"#), b"", 101);
    }
}

#[test]
fn zero_sized_slices_preserve_effects_and_neighbors() {
    execute(
        "zero-sized slice values and raw views",
        include_str!("fixtures/stdlib_foundation/zero_sized_slice_views.lani"),
    );
}

#[test]
fn zero_sized_slices_enforce_logical_bounds() {
    for (length, elements, index) in [(3, "seed, seed, seed", -1), (3, "seed, seed, seed", 3), (0, "", 0)] {
        for operation in ["return values[index];", "values[index] = seed; return seed;"] {
            execute_with_status(
                "zero-sized slice logical bounds",
                &format!(r#"
struct Empty {{}}
fn access<T>(values: [T], index: i32, seed: T) -> T {{ {operation} }}
fn main() -> i32 {{
    let seed: Empty = Empty {{}};
    let values: [Empty; {length}] = [{elements}];
    let value: Empty = access(values, {index}, seed);
    return 0;
}}
"#),
                b"",
                101,
            );
        }
    }
}

#[test]
fn generic_slice_forwarders_close_transitive_body_environments() {
    for relay in ["keep", "core::mem::identity"] {
        execute("generic slice forwarder body closure", &format!(r#"
import core::mem;
fn keep<T>(value: T) -> T {{ return value; }}
fn view<T>(values: [T]) -> [T] {{ return {relay}(values); }}
fn main() -> i32 {{
    let values: [i32; 3] = [11, 22, 33];
    let result: [i32] = view(values);
    result[2] = 44;
    if (result[0] != 11 || result[1] != 22 || values[2] != 44) {{ return 1; }}
    return 0;
}}
"#));
    }
}

#[test]
fn generic_assignment_destinations_supply_complete_result_contexts() {
    execute(
        "composed local and imported constructor assignments",
        include_str!("fixtures/stdlib_foundation/generic_assignment_contexts.lani"),
    );
    execute(
        "imported enum constructors assigned to fields",
        include_str!("fixtures/stdlib_foundation/repro_option_field_constructor_assignment.lani"),
    );
    for source in [
        r#"
import core::option;
struct Holder { value: core::option::Option<i32> }
fn empty<T>() -> core::option::Option<T> { return core::option::None(); }
fn main() -> i32 {
    let holder: Holder = Holder { value: core::option::Some(11) };
    holder.value = empty();
    if (!core::option::is_none(holder.value)) { return 1; }
    holder.value = match (true) { true -> core::option::Some(42), false -> core::option::None() };
    return core::option::unwrap_or(holder.value, 0) - 42;
}
"#,
        r#"
import core::mem;
struct Cell<T> { value: T }
fn make<T>(value: T) -> Cell<T> { return Cell { value: value }; }
fn main() -> i32 {
    let values: [Cell<u32>; 2] = [Cell { value: 1 }, Cell { value: 2 }];
    values[0] = make(4294967295);
    values[1] = core::mem::identity(Cell { value: 2147483648 });
    if (values[0].value != 4294967295 || values[1].value != 2147483648) { return 1; }
    values[0] = Cell { value: 3 };
    if (values[0].value != 3 || values[1].value != 2147483648) { return 2; }
    return 0;
}
"#,
        r#"
struct Holder { value: [u32; 2], sentinel: i32 }
fn main() -> i32 {
    let owner: Holder = Holder { value: [1, 2], sentinel: 79 };
    let rows: [[u32; 2]; 2] = [[3, 4], [5, 6]];
    owner.value = [4294967295, 2147483648];
    rows[0] = [2147483648, 4294967295];
    if (owner.value[0] != 4294967295 || owner.value[1] != 2147483648 || owner.sentinel != 79 ||
        rows[0][0] != 2147483648 || rows[0][1] != 4294967295 || rows[1][0] != 5) { return 1; }
    return 0;
}
"#,
    ] {
        execute("assignment receiving contexts", source);
    }
}

#[test]
fn qualified_generic_array_elements_preserve_owned_and_borrowed_storage() {
    execute(
        "qualified generic elements in arrays and slices",
        include_str!("fixtures/stdlib_foundation/generic_qualified_array_elements.lani"),
    );
}

#[test]
fn generic_assignment_destinations_reject_conflicting_payloads() {
    for source in [
        "import core::option; struct Holder { value: core::option::Option<i32> } fn main() -> i32 { let holder: Holder = Holder { value: core::option::None() }; holder.value = core::option::Some(true); return 0; }",
        "struct Cell<T> { value: T } fn make<T>(value: T) -> Cell<T> { return Cell { value: value }; } fn main() -> i32 { let cells: [Cell<i32>; 1] = [Cell { value: 11 }]; let flag: bool = true; cells[0] = make(flag); return 0; }",
        "struct Holder { value: [i32; 2] } fn main() -> i32 { let holder: Holder = Holder { value: [1, 2] }; holder.value = [true, false]; return 0; }",
    ] {
        let entry = common::TempArtifact::new("generic_assignment_conflict", "payload", Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout("assignment payload conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        }).expect_err("a receiving context cannot replace a known incompatible payload type");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
    }
}

#[test]
fn generic_assignment_contexts_preserve_slice_descriptors_and_aliases() {
    execute("slice descriptor fields in imported enum constructors", r#"
import core::option;
import core::mem;
struct Owner { values: [i32; 2], sentinel: i32 }
struct Holder { value: core::option::Option<[i32]>, sentinel: i32 }
fn view(values: [i32]) -> [i32] { return values; }
fn main() -> i32 {
    let packed: [i32; 2] = [11, 22];
    let native: Owner = Owner { values: [31, 41], sentinel: 97 };
    let holder: Holder = Holder { value: core::option::None(), sentinel: 89 };
    holder.value = core::option::Some(core::mem::identity(view(native.values)));
    holder.value = core::mem::identity(holder.value);
    let first: [i32] = core::option::unwrap_or(holder.value, view(packed));
    first[1] = 51;
    if (native.values[1] != 51 || native.sentinel != 97 || holder.sentinel != 89) { return 1; }
    holder.value = core::option::Some(view(packed));
    let second: [i32] = core::option::unwrap_or(holder.value, first);
    second[0] = 61;
    if (packed[0] != 61 || first[0] != 31 || holder.sentinel != 89) { return 2; }
    holder.value = core::option::None();
    if (!core::option::is_none(holder.value) || first[1] != 51) { return 3; }
    return 0;
}
"#);
}

#[test]
fn imported_enum_constructor_wrappers_preserve_symbolic_payloads() {
    execute(
        "imported enum constructors through symbolic wrappers",
        include_str!("fixtures/stdlib_foundation/generic_imported_constructor_wrappers.lani"),
    );
}

#[test]
fn imported_enum_constructor_wrappers_reject_unrelated_parameters() {
    for source in [
        "import core::option; fn wrong<T, U>(value: T) -> core::option::Option<U> { return core::option::Some(value); } fn main() -> i32 { let value: core::option::Option<bool> = wrong(42); return 0; }",
        "import core::result; fn wrong<T, E>(value: E) -> core::result::Result<T, E> { return core::result::Ok(value); } fn main() -> i32 { let value: core::result::Result<i32, bool> = wrong(false); return 0; }",
    ] {
        let entry = common::TempArtifact::new("symbolic_constructor_conflict", "payload", Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout("symbolic constructor parameter conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        }).expect_err("distinct generic parameters cannot substitute for each other");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
    }
}

#[test]
fn generic_borrowed_method_arguments_retain_complete_referents() {
    execute(
        "recursive generic reference passed directly from method",
        include_str!("fixtures/stdlib_foundation/generic_recursive_reference_context.lani"),
    );
    execute("nested borrowed method arguments", r#"
struct Cell<T> { value: T, sentinel: i32 }
impl<T> Cell<T> { fn borrow(&self) -> &Cell<T> { return self; } }
fn relay<T>(value: &Cell<T>) -> &Cell<T> { return value; }
fn main() -> i32 {
    let number: Cell<i32> = Cell { value: 11, sentinel: 97 };
    let flag: Cell<bool> = Cell { value: false, sentinel: 89 };
    let pair: Cell<[u32; 2]> = Cell { value: [31, 41], sentinel: 83 };
    let n: &Cell<i32> = relay(relay(number.borrow()));
    let f: &Cell<bool> = relay(flag.borrow());
    let p: &Cell<[u32; 2]> = relay(relay(pair.borrow()));
    number.value = 42;
    flag.value = true;
    pair.value[1] = 4294967295;
    if (n.value != 42 || !f.value || p.value[0] != 31 || p.value[1] != 4294967295 ||
        n.sentinel != 97 || f.sentinel != 89 || p.sentinel != 83) { return 1; }
    return 0;
}
"#);
}

#[test]
fn generic_borrowed_method_arguments_reject_conflicting_referents() {
    for source in [
        "struct Cell<T> { value: T } impl<T> Cell<T> { fn borrow(&self) -> &Cell<T> { return self; } } fn use_cell<T>(value: &Cell<T>, fallback: T) -> T { return fallback; } fn main() -> i32 { let cell: Cell<i32> = Cell { value: 42 }; let wrong: bool = use_cell(cell.borrow(), false); return 0; }",
        "struct Cell<T> { value: T } struct Other<T> { value: T } impl<T> Other<T> { fn borrow(&self) -> &Other<T> { return self; } } fn use_cell<T>(value: &Cell<T>) -> &Cell<T> { return value; } fn main() -> i32 { let cell: Other<i32> = Other { value: 42 }; let wrong: &Cell<i32> = use_cell(cell.borrow()); return 0; }",
    ] {
        let entry = common::TempArtifact::new("borrowed_method_conflict", "referent", Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout("borrowed method referent conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        }).expect_err("checked references retain their nominal and parameter identities");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
    }
}

#[test]
fn local_enum_constructors_receive_nested_expression_types() {
    execute(
        "local enum constructor receiving contexts",
        include_str!("fixtures/stdlib_foundation/generic_local_enum_contexts.lani"),
    );
}

#[test]
fn local_enum_constructor_contexts_preserve_thirty_two_bindings() {
    let parameters = (0..32).map(|i| format!("A{i}")).collect::<Vec<_>>().join(", ");
    let mut arguments = (0..32).map(|i| match i % 4 {
        0 => "i32", 1 => "bool", 2 => "str", _ => "[i32; 2]",
    }).collect::<Vec<_>>();
    arguments[31] = "[i32; 2]";
    let owned = arguments.join(", ");
    arguments[31] = "[i32]";
    let borrowed = arguments.join(", ");
    execute("32-slot local constructor receiving contexts", &format!(r#"
struct Holder<T> {{ value: T, sentinel: i32 }}
enum Wide<{parameters}> {{ First(A0), Last(A31), Absent }}
fn empty<{parameters}>() -> Holder<Wide<{parameters}>> {{
    return Holder {{ value: Absent(), sentinel: 97 }};
}}
fn view(values: [i32]) -> [i32] {{ return values; }}
fn main() -> i32 {{
    let direct: Holder<Wide<{owned}>> = Holder {{ value: Last([11, 22]), sentinel: 89 }};
    let missing: Holder<Wide<{owned}>> = empty();
    let absent: bool = match (missing.value) {{ Absent -> true, _ -> false }};
    let value: [i32; 2] = match (direct.value) {{ Last(v) -> v, _ -> [0, 0] }};
    value[0] = 33;
    let original: [i32; 2] = match (direct.value) {{ Last(v) -> v, _ -> [0, 0] }};
    if (!absent || missing.sentinel != 97 || direct.sentinel != 89 || original[0] != 11 || original[1] != 22) {{ return 1; }}
    direct.value = First(41);
    let first: i32 = match (direct.value) {{ First(v) -> v, _ -> 0 }};
    if (first != 41 || direct.sentinel != 89) {{ return 2; }}
    let data: [i32; 2] = [51, 61];
    let alias: Holder<Wide<{borrowed}>> = Holder {{ value: Last(view(data)), sentinel: 83 }};
    let slice: [i32] = match (alias.value) {{ Last(v) -> v, _ -> view(data) }};
    slice[1] = 71;
    if (data[0] != 51 || data[1] != 71 || alias.sentinel != 83) {{ return 3; }}
    return 0;
}}
"#));
}

#[test]
fn local_enum_constructor_contexts_preserve_nongeneric_nominal_identity() {
    execute("bare nominal constructor receiving contexts", r#"
struct Slot<T> { value: T, sentinel: i32 }
enum Decision { Accept(bool), Reject }
fn reject() -> Decision { return Reject(); }
fn main() -> i32 {
    let plain: Decision = reject();
    let slot: Slot<Decision> = Slot { value: Reject(), sentinel: 97 };
    slot.value = Accept(true);
    let flag: bool = match (slot.value) { Accept(v) -> v, Reject -> false };
    let other: bool = match (plain) { Accept(v) -> v, Reject -> false };
    if (!flag || other || slot.sentinel != 97) { return 1; }
    return 0;
}
"#);
}

#[test]
fn local_enum_constructor_contexts_reject_conflicting_payloads() {
    for source in [
        "struct Slot<T> { value: T } enum Maybe<T> { Value(T), Missing } fn main() -> i32 { let slot: Slot<Maybe<i32>> = Slot { value: Value(true) }; return 0; }",
        "enum Maybe<T> { Value(T), Missing } fn main() -> i32 { let values: [Maybe<i32>; 1] = [Missing()]; values[0] = Value(false); return 0; }",
        "struct Slot<T> { value: T } enum Maybe<T> { Value(T), Missing } enum Other<T> { Present(T), Absent } fn main() -> i32 { let slot: Slot<Other<i32>> = Slot { value: Missing() }; return 0; }",
        "struct Slot<T> { value: T } enum Maybe<T> { Value(T), Missing } fn wrong<T, U>(value: T) -> Slot<Maybe<U>> { return Slot { value: Value(value) }; } fn main() -> i32 { let slot: Slot<Maybe<bool>> = wrong(42); return 0; }",
        "struct Slot<T> { value: T } enum Decision { Accept(bool), Reject } enum Other { Absent } fn main() -> i32 { let slot: Slot<Other> = Slot { value: Reject() }; return 0; }",
        "enum Decision { Borrow([i32]) } fn main() -> i32 { let value: Decision = Borrow(true); return 0; }",
    ] {
        let entry = common::TempArtifact::new("local_constructor_conflict", "payload", Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout("local constructor context conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        }).expect_err("constructor receiving types must preserve payload and nominal identity");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
    }
}

#[test]
fn bare_nominal_compositions_preserve_copies_and_aliases() {
    execute(
        "bare nominal records and enums in generic values",
        include_str!("fixtures/stdlib_foundation/generic_bare_nominal_compositions.lani"),
    );
    execute(
        "bare nominal payloads through imported calls and inferred body applications",
        include_str!("fixtures/stdlib_foundation/generic_bare_nominal_body_closure.lani"),
    );
}

#[test]
fn nominal_declaration_identity_is_independent_of_source_positions() {
    // These declaration anchors differ by the old struct/enum cache-code gap.
    // The adjacent-position control must have identical language behavior.
    let padding = (0..182)
        .map(|i| format!("fn padding{i} ( ) -> i32 {{ return 0 ; }}\n"))
        .chain((0..9).map(|i| format!("struct Empty{i} {{ }}\n")))
        .collect::<String>();
    for shifted in [false, true] {
        let padding = if shifted {
            padding.replacen("return 0 ;", "return - 0 ;", 1)
        } else {
            padding.clone()
        };
        for (kind, definitions, decision_call, record_call) in [
            ("ordinary", "fn decision(v: Decision) -> Decision { return v; } fn record(v: Record) -> Record { return v; }", "decision", "record"),
            ("generic", "fn keep<T>(v: T) -> T { return v; }", "keep", "keep"),
        ] {
            execute(
                &format!("nominal declaration positions, {kind}, shifted={shifted}"),
                &format!(r#"
enum Decision {{ Owned ( i32 ) , Vacant }}
{padding}
struct Record {{ value: i32, sentinel: i32 }}
{definitions}
fn main() -> i32 {{
    let original: Decision = Owned(42);
    let copied: Decision = {decision_call}(original);
    let original_record: Record = Record {{ value: 13, sentinel: 97 }};
    let copied_record: Record = {record_call}(original_record);
    let got: i32 = match (copied) {{ Owned(value) -> value, _ -> 0 }};
    if (got != 42 || copied_record.value != 13 || copied_record.sentinel != 97) {{ return 1; }}
    let absent = {decision_call}(Vacant);
    let missing: bool = match (absent) {{ Vacant -> true, _ -> false }};
    if (!missing) {{ return 2; }}
    return 0;
}}
"#),
            );
            let entry = common::TempArtifact::new("generic_types", "nominal_position_mismatch", Some("lani"));
            entry.write_str(&format!(r#"
enum Decision {{ Owned ( i32 ) , Vacant }}
{padding}
struct Record {{ value: i32, sentinel: i32 }}
{definitions}
fn main() -> i32 {{
    let value: Decision = Owned(42);
    let wrong: Record = {decision_call}(value);
    return 0;
}}
"#));
            let path = entry.path().to_path_buf();
            let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
            let error = common::run_gpu_codegen_with_timeout("nominal declaration position mismatch", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            }).err().expect("distinct nominal declarations must reject despite equal legacy codes");
            assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{kind}, shifted={shifted}: {error:?}");
        }
    }
}

fn check_reference_forwarding(generic: bool) {
    let returned = if generic { "keep(self)" } else { "self" };
    execute(
        &format!("reference forwarding, generic={generic}"),
        &format!(
            r#"
struct Item {{ head: i32, tail: i32 }}
fn keep<T>(value: T) -> T {{ return value; }}
impl Item {{
    fn borrow(&self) -> &Item {{ return {returned}; }}
}}
fn read(value: &Item) -> i32 {{ return value.head + value.tail; }}
fn main() -> i32 {{
    let item: Item = Item {{ head: 11, tail: 22 }};
    let borrowed: &Item = item.borrow();
    if (read(borrowed) != 33) {{ return 1; }}
    item.head = 44;
    if (read(borrowed) != 66 || borrowed.tail != 22) {{ return 2; }}
    return 0;
}}
"#
        ),
    );
}

#[test]
fn ordinary_reference_results_preserve_referent_identity() {
    check_reference_forwarding(false);
}

#[test]
fn generic_reference_results_preserve_referent_identity() {
    check_reference_forwarding(true);
}

#[test]
fn generic_reference_compositions_preserve_aliases_inside_owned_values() {
    for relay in ["keep", "core::relay::forward"] {
        let stdlib = ReceiverTestStdlib::new();
        execute_with_stdlib(
            &format!("reference compositions through {relay}"),
            &format!(
                r#"
module app::main;
import core::relay;
struct Item {{ head: i32, tail: i32 }}
struct Cell<T> {{ value: T, sentinel: i32 }}
enum Maybe<T> {{ Some(T), None }}
impl Item {{ fn borrow(&self) -> &Item {{ return self; }} }}
fn keep<T>(value: T) -> T {{ return value; }}
fn unwrap<T>(value: Maybe<T>, fallback: T) -> T {{
    return match (value) {{ Some(inner) -> inner, None -> fallback }};
}}
fn main() -> i32 {{
    let item: Item = Item {{ head: 11, tail: 22 }};
    let second: Item = Item {{ head: 33, tail: 44 }};
    let borrowed: &Item = item.borrow();
    let other: &Item = second.borrow();
    let original: Cell<&Item> = Cell {{ value: borrowed, sentinel: 1234 }};
    let copied: Cell<&Item> = {relay}(original);
    let pointers: [&Item; 2] = [borrowed, other];
    let array: [&Item; 2] = {relay}(pointers);
    let present: Maybe<&Item> = Some(borrowed);
    let absent: Maybe<&Item> = None();
    let selected: &Item = unwrap({relay}(present), other);
    let fallback: &Item = unwrap({relay}(absent), other);
    item.head = 55;
    second.tail = 66;
    if (copied.value.head != 55 || copied.value.tail != 22 || copied.sentinel != 1234) {{ return 1; }}
    if (array[0].head != 55 || array[1].tail != 66) {{ return 2; }}
    if (selected.head != 55 || fallback.tail != 66) {{ return 3; }}
    original.value = other;
    pointers[0] = other;
    if (copied.value.head != 55 || array[0].head != 55) {{ return 4; }}
    return 0;
}}
"#
            ),
            stdlib.0.path(),
            b"",
            0,
        );
    }
}

#[test]
fn generic_reference_parameter_patterns_preserve_complete_referents() {
    execute(
        "reference parameter pattern",
        r#"
struct Item { head: i32, tail: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn relay<T>(value: &T) -> &T { return value; }
fn main() -> i32 {
    let item: Item = Item { head: 11, tail: 22 };
    let borrowed: &Item = relay(item.borrow());
    item.head = 33;
    if (borrowed.head != 33 || borrowed.tail != 22) { return 1; }
    return 0;
}
"#,
    );
}

#[test]
fn generic_reference_types_reject_incompatible_referents_and_owned_values() {
    for operation in [
        "let wrong: &Other = keep(left.borrow());",
        "accept(right.borrow());",
        "let wrong = same(left.borrow(), right.borrow());",
        "let wrong: &Item = keep(left);",
        "let wrong: Item = keep(left.borrow());",
        "let wrong: &Item = 0;",
    ] {
        let entry = common::TempArtifact::new("generic_types", "reference_mismatch", Some("lani"));
        entry.write_str(&format!(
            r#"
struct Item {{ value: i32 }}
struct Other {{ value: i32 }}
impl Item {{ fn borrow(&self) -> &Item {{ return self; }} }}
impl Other {{ fn borrow(&self) -> &Other {{ return self; }} }}
fn keep<T>(value: T) -> T {{ return value; }}
fn same<T>(left: T, right: T) -> T {{ return left; }}
fn accept(value: &Item) -> i32 {{ return value.value; }}
fn main() -> i32 {{
    let left: Item = Item {{ value: 11 }};
    let right: Other = Other {{ value: 22 }};
    {operation}
    return 0;
}}
"#
        ));
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout("reference type conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| panic!("incompatible reference was accepted: {operation}"));
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{operation}: {error:?}"
        );
    }
}

#[test]
fn imported_reference_signatures_preserve_aliases_and_infer_referents() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "imported reference signatures",
        r#"
module app::main;
import core::relay;
struct Item { head: i32, tail: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn local<T>(value: &T) -> &T { return value; }
fn main() -> i32 {
    let item: Item = Item { head: 11, tail: 22 };
    let other: Item = Item { head: 33, tail: 44 };
    let local_ref = local(item.borrow());
    let imported_ref = core::relay::keep_ref(item.borrow());
    let annotated: &Item = core::relay::same_ref(imported_ref, other.borrow());
    item.head = 55;
    if (local_ref.head != 55 || imported_ref.head != 55 || annotated.head != 55) { return 1; }
    if (annotated.tail != 22) { return 2; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn imported_reference_fields_preserve_pointer_layout_and_aliases() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "imported reference fields",
        r#"
module app::main;
import core::relay;
struct Item { head: i32, tail: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn main() -> i32 {
    let item: Item = Item { head: 11, tail: 22 };
    let other: Item = Item { head: 33, tail: 44 };
    let original = core::relay::wrap_ref(item.borrow());
    let copied = core::relay::keep(original);
    let recovered = core::relay::read_ref(copied);
    original.value = other.borrow();
    item.head = 55;
    if (copied.sentinel != 1234 || copied.value.head != 55 || recovered.tail != 22) { return 1; }
    if (original.value.head != 33 || recovered.head != 55) { return 2; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn imported_reference_signatures_reject_incompatible_referents() {
    for operation in [
        "let wrong: &Other = core::relay::keep_ref(left.borrow());",
        "let wrong = core::relay::same_ref(left.borrow(), right.borrow());",
        "let wrong = core::relay::keep_ref(left);",
        "let wrong: Item = core::relay::keep_ref(left.borrow());",
        "let wrong: core::relay::View<Other> = core::relay::wrap_ref(left.borrow());",
        "let view = core::relay::wrap_ref(left.borrow()); view.value = right.borrow();",
        "let view = core::relay::wrap_ref(left.borrow()); view.value = left;",
    ] {
        let stdlib = ReceiverTestStdlib::new();
        let entry =
            common::TempArtifact::new("generic_types", "imported_reference_mismatch", Some("lani"));
        entry.write_str(&format!(
            r#"
module app::main;
import core::relay;
struct Item {{ value: i32 }}
struct Other {{ value: i32 }}
impl Item {{ fn borrow(&self) -> &Item {{ return self; }} }}
impl Other {{ fn borrow(&self) -> &Other {{ return self; }} }}
fn main() -> i32 {{
    let left: Item = Item {{ value: 11 }};
    let right: Other = Other {{ value: 22 }};
    {operation}
    return 0;
}}
"#
        ));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error =
            common::run_gpu_codegen_with_timeout("imported reference conflict", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
            })
            .err()
            .unwrap_or_else(|| panic!("incompatible imported reference was accepted: {operation}"));
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{operation}: {error:?}"
        );
    }
}

#[test]
fn reference_receivers_preserve_identity_through_method_calls() {
    execute(
        "reference method receivers",
        r#"
struct Item { head: i32, tail: i32 }
impl Item {
    fn borrow(&self) -> &Item { return self; }
    fn sum(&self) -> i32 { return self.head + self.tail; }
}
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let item: Item = Item { head: 11, tail: 22 };
    let borrowed: &Item = keep(item.borrow());
    let again: &Item = borrowed.borrow();
    if (borrowed.sum() != 33 || again.sum() != 33) { return 1; }
    item.head = 44;
    if (borrowed.sum() != 66 || again.head != 44) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn generic_reference_receivers_substitute_complete_method_return_types() {
    execute(
        "generic reference method returns",
        r#"
struct Cell<T> { value: T, sentinel: i32 }
impl<T> Cell<T> {
    fn borrow(&self) -> &Cell<T> { return self; }
    fn get(&self) -> T { return self.value; }
}
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let cell: Cell<i32> = Cell { value: 11, sentinel: 1234 };
    let borrowed: &Cell<i32> = keep(cell.borrow());
    let again: &Cell<i32> = borrowed.borrow();
    cell.value = 44;
    if (borrowed.get() != 44 || again.value != 44 || again.sentinel != 1234) { return 1; }
    return 0;
}
"#,
    );
}

#[test]
fn local_generic_methods_preserve_compound_values_and_nested_calls() {
    execute_with_stdout(
        "local generic compound method bodies",
        r#"
module app::main;
import std::io;
struct Cell<T> { value: T, sentinel: i32 }
impl<T> Cell<T> {
    fn borrow(&self) -> &Cell<T> { return self; }
    fn get(&self) -> T { return self.value; }
    fn relay(&self) -> T { return self.get(); }
}
struct Item { label: str, count: i32 }
fn main() -> i32 {
    let text: Cell<str> = Cell { value: "alpha λ", sentinel: 1234 };
    let text_ref: &Cell<str> = text.borrow();
    let text_copy: str = text_ref.relay();
    text.value = "";
    if (std::io::println(text_copy) != 9 || std::io::println(text_ref.get()) != 1 || text_ref.sentinel != 1234) { return 1; }
    let words: Cell<[str; 2]> = Cell { value: ["first", "last λ"], sentinel: 5678 };
    let words_ref: &Cell<[str; 2]> = words.borrow();
    let words_copy: [str; 2] = words_ref.relay();
    words.value = ["changed", ""];
    if (std::io::println(words_copy[0]) != 6 || std::io::println(words_copy[1]) != 8 || words_ref.sentinel != 5678) { return 2; }
    let original: Item = Item { label: "record λ", count: 11 };
    let record: Cell<Item> = Cell { value: original, sentinel: 2468 };
    let record_ref: &Cell<Item> = record.borrow();
    let record_copy: Item = record_ref.relay();
    record.value = Item { label: "replacement", count: 22 };
    if (std::io::println(record_copy.label) != 10 || record_copy.count != 11 || record_ref.value.count != 22) { return 3; }
    return 0;
}
"#,
        "alpha λ\n\nfirst\nlast λ\nrecord λ\n".as_bytes(),
    );
}

#[test]
fn local_generic_methods_use_lexical_impl_parameter_order() {
    execute_with_stdout(
        "reordered impl parameter methods",
        r#"
module app::main;
import std::io;
struct Pair<A, B> { left: A, right: B, sentinel: i32 }
impl<Y, X> Pair<X, Y> {
    pub fn borrow(&self) -> &Pair<X, Y> { return self; }
    pub fn first(&self) -> X { return self.left; }
    pub fn second(&self) -> Y { return self.right; }
}

fn main() -> i32 {
    let pair: Pair<str, i32> = Pair { left: "left λ", right: 42, sentinel: 1234 };
    let view: &Pair<str, i32> = pair.borrow();
    let copied: str = view.first();
    pair.left = "changed";
    pair.right = -7;
    if (std::io::println(copied) != 8 || std::io::println(view.first()) != 8 || view.second() != -7 || view.sentinel != 1234) { return 1; }
    let other: Pair<[str; 2], bool> = Pair { left: ["a", "b λ"], right: false, sentinel: 5678 };
    let other_view: &Pair<[str; 2], bool> = other.borrow();
    let words: [str; 2] = other_view.first();
    if (other_view.second() || std::io::println(words[0]) != 2 || std::io::println(words[1]) != 5 || other_view.sentinel != 5678) { return 2; }
    return 0;
}
"#,
        "left λ\nchanged\na\nb λ\n".as_bytes(),
    );
}

#[test]
fn structural_impl_receivers_execute_ordinary_array_patterns() {
    execute(
        "ordinary structural impl receiver",
        include_str!("fixtures/stdlib_foundation/repro_ordinary_structural_impl_receiver.lani"),
    );
}

#[test]
fn structural_impl_receivers_execute_nested_generic_array_patterns() {
    execute(
        "nested structural impl receiver",
        include_str!("fixtures/stdlib_foundation/repro_nested_structural_impl_receiver.lani"),
    );
}

fn structural_receiver_shapes(imported: bool) {
    let definitions =
        include_str!("fixtures/stdlib_foundation/structural_receiver_definitions.lani");
    let exercise = include_str!("fixtures/stdlib_foundation/structural_receiver_exercise.lani");
    if !imported {
        execute_with_stdout(
            "local structural receiver shapes",
            &format!("module app::main;\nimport std::io;\n{definitions}\n{exercise}"),
            "Ω\nΩ\nλ\nΩ\n".as_bytes(),
        );
        return;
    }
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/shapes.lani"),
        format!("module core::shapes;\n{definitions}"),
    )
    .expect("structural receiver library");
    let exercise = exercise
        .replace("Wrap", "core::shapes::Wrap")
        .replace("Cell", "core::shapes::Cell");
    execute_with_stdlib(
        "imported structural receiver shapes",
        &format!("module app::main;\nimport std::io;\nimport core::shapes;\n{exercise}"),
        stdlib.0.path(),
        "Ω\nΩ\nλ\nΩ\n".as_bytes(),
        0,
    );
}

#[test]
fn structural_impl_receivers_execute_local_compositions() {
    structural_receiver_shapes(false);
}

#[test]
fn structural_impl_receivers_execute_imported_compositions() {
    structural_receiver_shapes(true);
}

fn structural_receiver_wide(imported: bool) {
    let definitions =
        include_str!("fixtures/stdlib_foundation/structural_receiver_wide_definitions.lani");
    let exercise =
        include_str!("fixtures/stdlib_foundation/structural_receiver_wide_exercise.lani");
    let expected = "Ω\nλ\nΩ\nλ\nΩ\nΩ\nΩ\nΩ\n".as_bytes();
    if !imported {
        execute_with_stdout(
            "local thirty-two-parameter structural receiver",
            &format!("module app::main;\nimport std::io;\n{definitions}\n{exercise}"),
            expected,
        );
        return;
    }
    let root = ReceiverTestStdlib::new();
    std::fs::write(
        root.0.path().join("core/receiver_wide.lani"),
        format!("module core::receiver_wide;\n{definitions}"),
    )
    .expect("wide receiver library");
    let exercise = exercise
        .replace("Mine", "core::receiver_wide::Mine")
        .replace("Cell", "core::receiver_wide::Cell");
    execute_with_stdlib(
        "imported thirty-two-parameter structural receiver",
        &format!("module app::main;\nimport std::io;\nimport core::receiver_wide;\n{exercise}"),
        root.0.path(),
        expected,
        0,
    );
}

#[test]
fn structural_impl_receivers_execute_thirty_two_parameters_locally() {
    structural_receiver_wide(false);
}

#[test]
fn structural_impl_receivers_execute_thirty_two_parameters_imported() {
    structural_receiver_wide(true);
}

#[test]
fn structural_impl_receivers_reject_conflicts_and_ambiguous_patterns() {
    for (label, source) in [
        (
            "wrong nested nominal argument",
            r#"
struct Wrap<A> { value: A }
struct Cell<T> { value: T }
impl Wrap<Cell<i32>> { fn number(&self) -> i32 { return self.value.value; } }
fn main() -> i32 {
    let wrong: Wrap<Cell<bool>> = Wrap<Cell<bool>> { value: Cell<bool> { value: false } };
    return wrong.number();
}"#,
        ),
        (
            "repeated structural type parameter",
            r#"
struct Pair<A, B> { left: A, right: B }
struct Cell<T> { value: T }
impl<T> Pair<Cell<T>, Cell<T>> { fn number(&self) -> T { return self.left.value; } }
fn main() -> i32 {
    let wrong: Pair<Cell<i32>, Cell<bool>> = Pair<Cell<i32>, Cell<bool>> {
        left: Cell<i32> { value: 7 }, right: Cell<bool> { value: false }
    };
    return wrong.number();
}"#,
        ),
        (
            "repeated structural constant parameter",
            r#"
struct Pair<A, B> { left: A, right: B }
impl<T, const N: usize> Pair<[T; N], [T; N]> { fn length(&self) -> usize { return N; } }
fn main() -> i32 {
    let wrong: Pair<[i32; 2], [i32; 3]> = Pair<[i32; 2], [i32; 3]> { left: [1, 2], right: [1, 2, 3] };
    return wrong.length();
}"#,
        ),
        (
            "overlapping structural methods",
            r#"
struct Wrap<A> { value: A }
impl<T> Wrap<T> { fn marker(&self) -> i32 { return 1; } }
impl Wrap<[i32; 2]> { fn marker(&self) -> i32 { return 2; } }
fn main() -> i32 {
    let ambiguous: Wrap<[i32; 2]> = Wrap<[i32; 2]> { value: [7, 9] };
    return ambiguous.marker();
}"#,
        ),
        (
            "alpha equivalent structural methods",
            r#"
struct Wrap<A> { value: A }
impl<T> Wrap<[T; 2]> { fn marker(&self) -> i32 { return 1; } }
impl<U> Wrap<[U; 2]> { fn marker(&self) -> i32 { return 2; } }
fn main() -> i32 {
    let ambiguous: Wrap<[i32; 2]> = Wrap<[i32; 2]> { value: [7, 9] };
    return ambiguous.marker();
}"#,
        ),
    ] {
        let entry = common::TempArtifact::new("generic_types", label, Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        })
        .expect_err("a conflicting or ambiguous receiver must not emit an ELF");
        let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
            panic!("{label}: expected a source diagnostic, got {error:?}");
        };
        assert!(
            diagnostic.primary_label.is_some(),
            "{label}: {diagnostic:?}"
        );
        assert_eq!(diagnostic.code, "LNC0027", "{label}: {diagnostic:?}");
        eprintln!("{label}: {} {}", diagnostic.code, diagnostic.message);
    }
}

#[test]
fn imported_generic_reference_methods_preserve_all_receiver_arguments() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "imported generic reference methods",
        r#"
module app::main;
import core::five;
import core::relay;
import std::io;
struct Item { head: i32, tail: i32 }
fn exercise(values: [i32]) -> i32 {
    let packet: core::five::Five<str, Item, [str; 2], [i32], i32> = core::five::Five {
        first: "left λ", second: Item { head: 11, tail: 22 },
        third: ["one", "last λ"], fourth: values, fifth: 1234
    };
    let view = core::relay::keep_ref(packet.borrow());
    let again = view.borrow();
    let copied_text = view.first_value();
    let copied_record = view.second_value();
    let copied_words = view.third_value();
    let shared = again.fourth_value();
    packet.first = "changed";
    packet.second.head = 44;
    packet.third = ["replacement", ""];
    shared[0] = -7;
    let current_record = again.second_value();
    if (copied_record.head != 11 || copied_record.tail != 22 || current_record.head != 44 || values[0] != -7 || again.last() != 1234) { return 1; }
    std::io::println(copied_text);
    std::io::println(again.first_value());
    std::io::println(copied_words[0]);
    std::io::println(copied_words[1]);
    return 0;
}
fn main() -> i32 { let values: [i32; 2] = [99, 42]; return exercise(values); }
"#,
        stdlib.0.path(),
        "left λ\nchanged\none\nlast λ\n".as_bytes(),
        0,
    );
}

#[test]
fn generic_method_lookup_uses_complete_inferred_call_results() {
    execute_with_stdout(
        "generic call result method receivers",
        r#"
module app::main;
import std::io;
struct Cell<T> { value: T, sentinel: i32 }
impl<T> Cell<T> {
    fn borrow(&self) -> &Cell<T> { return self; }
    fn get(&self) -> T { return self.value; }
}
fn keep<T>(value: T) -> T { return value; }
fn make<T>(value: T) -> Cell<T> { return Cell { value: value, sentinel: 1234 }; }
fn main() -> i32 {
    let original: Cell<str> = Cell { value: "before λ", sentinel: 1234 };
    let view = keep(original.borrow());
    let first = keep(view).get();
    let second = keep(original.borrow()).borrow().get();
    let input: [str; 2] = ["one", "two λ"];
    let words = make(input).get();
    original.value = "after";
    std::io::println(first);
    std::io::println(second);
    std::io::println(view.get());
    std::io::println(words[0]);
    std::io::println(words[1]);
    return 0;
}
"#,
        "before λ\nbefore λ\nafter\none\ntwo λ\n".as_bytes(),
    );
}

#[test]
fn generic_array_literal_arguments_supply_complete_element_types() {
    execute_with_stdout(
        "generic array literal inference",
        r#"
module app::main;
import std::io;
struct Cell<T> { value: T }
fn make<T>(value: T) -> Cell<T> { return Cell { value: value }; }
fn main() -> i32 {
    let cell = make(["one", "two λ"]);
    std::io::println(cell.value[0]);
    std::io::println(cell.value[1]);
    return 0;
}
"#,
        "one\ntwo λ\n".as_bytes(),
    );
}

#[test]
fn inferred_array_literals_preserve_nested_values_and_generic_body_types() {
    execute_with_stdout(
        "inferred nested array literals",
        r#"
module app::main;
import std::io;
import core::mem;
struct Item { text: str, n: i32 }
fn keep<T>(value: T) -> T { return value; }
fn duplicate<T>(value: T) -> [T; 2] { return keep([value, value]); }
fn main() -> i32 {
    let words = core::mem::identity([["a", ""], ["λ", "tail"]]);
    let copy = keep(words);
    words[1][1] = "changed";
    std::io::println(copy[0][0]);
    std::io::println(copy[0][1]);
    std::io::println(copy[1][0]);
    std::io::println(copy[1][1]);
    let first: Item = Item { text: "record", n: 11 };
    let second: Item = Item { text: "last", n: 22 };
    let items = keep([first, second]);
    first.n = 99;
    if (items[0].n != 11 || items[1].n != 22) { return 1; }
    let repeated = duplicate(copy[1]);
    copy[1][1] = "new";
    std::io::println(repeated[0][1]);
    std::io::println(repeated[1][0]);
    let numbers = keep([1, -7, 42]);
    let flags = keep([true, false]);
    if (numbers[1] != -7 || numbers[2] != 42 || !flags[0] || flags[1]) { return 2; }
    let empty: [str; 0] = [];
    let empties = keep([empty, empty]);
    return 0;
}
"#,
        "a\n\nλ\ntail\ntail\nλ\n".as_bytes(),
    );
}

#[test]
fn inferred_array_literals_preserve_reference_and_slice_aliases() {
    execute(
        "inferred array literal aliases",
        r#"
struct Item { value: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn view(values: [i32]) -> [i32] { return values; }
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let first: Item = Item { value: 11 };
    let second: Item = Item { value: 22 };
    let refs = keep([first.borrow(), second.borrow()]);
    let copied = keep(refs);
    first.value = 33;
    if (copied[0].value != 33 || copied[1].value != 22) { return 1; }
    refs[0] = second.borrow();
    if (copied[0].value != 33 || refs[0].value != 22) { return 2; }
    let values: [i32; 3] = [10, 20, 30];
    let slices = keep([view(values), view(values)]);
    let slice_copy = keep(slices);
    values[1] = 44;
    if (slice_copy[0][1] != 44 || slice_copy[1][2] != 30) { return 3; }
    slice_copy[1][0] = 55;
    if (values[0] != 55 || slices[0][0] != 55) { return 4; }
    return 0;
}
"#,
    );
}

#[test]
fn inferred_array_literals_reject_incompatible_elements_and_missing_empty_types() {
    for (label, expression) in [
        ("mixed scalar elements", "keep([1, true])"),
        ("mixed descriptor elements", "keep([\"text\", 1])"),
        ("mixed nested lengths", "keep([[1, 2], [3]])"),
        ("mixed nominal elements", "keep([left, right])"),
        ("mixed nominal arguments", "keep([numbers, flags])"),
        ("empty without context", "keep([])"),
    ] {
        let source = format!(
            r#"
struct Left {{ n: i32 }}
struct Right {{ n: i32 }}
struct Cell<T> {{ value: T }}
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{
    let left: Left = Left {{ n: 1 }};
    let right: Right = Right {{ n: 2 }};
    let numbers: Cell<i32> = Cell {{ value: 3 }};
    let flags: Cell<bool> = Cell {{ value: true }};
    let result = {expression};
    return 0;
}}
"#
        );
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        })
        .expect_err("a heterogeneous or untyped empty literal must reject before emission");
        let diagnostic = error.to_public_diagnostic();
        if label == "empty without context" && diagnostic.code == "LNC0047" {
            assert_eq!(
                diagnostic
                    .primary_label
                    .as_ref()
                    .map(|label| label.message.as_str()),
                Some("generic type instantiation reached a compiler boundary"),
                "{label}: {error:?}"
            );
        } else {
            assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        }
    }
}

#[test]
fn ordinary_inferred_array_literals_and_contextual_empty_literals_execute() {
    execute(
        "ordinary inferred and empty array literals",
        r#"
fn main() -> i32 {
    let values = [4, 5, 6];
    let copy = values;
    values[0] = 99;
    if (copy[0] != 4 || copy[2] != 6 || values[0] != 99) { return 1; }
    let empty: [str; 0] = [];
    let nested: [[str; 0]; 2] = [[], []];
    return 0;
}

"#,
    );
}

#[test]
fn call_contract_nested_method_arguments_preserve_values_and_copies() {
    execute(
        "nested method parameter contract",
        r#"
struct Wrapped<T> { value: T }
struct Five<A, B, C, D, E> { a: A, b: B, c: C, d: D, e: E }
impl<A, B, C, D, E> Five<A, B, C, D, E> {
    fn copy(self, value: Wrapped<[E; 2]>) -> Wrapped<[E; 2]> { return value; }
}
fn copy<T>(value: Wrapped<[T; 2]>) -> Wrapped<[T; 2]> { return value; }
fn main() -> i32 {
    let owner: Five<bool, i32, bool, i32, i32> = Five { a: false, b: 11, c: true, d: 22, e: 33 };
    let value: Wrapped<[i32; 2]> = Wrapped { value: [42, -7] };
    let direct = copy(value);
    let method = owner.copy(value);
    value.value = [99, 100];
    if (direct.value[0] != 42 || direct.value[1] != -7 || method.value[0] != 42 || method.value[1] != -7) { return 1; }
    return 0;
}
"#,
    );
}

#[test]
fn call_contract_nested_method_arguments_reject_receiver_conflicts() {
    for (label, ty, value) in [
        (
            "wrong element",
            "Wrapped<[bool; 2]>",
            "Wrapped { value: [true, false] }",
        ),
        (
            "wrong length",
            "Wrapped<[i32; 3]>",
            "Wrapped { value: [1, 2, 3] }",
        ),
        (
            "wrong nominal",
            "Other<[i32; 2]>",
            "Other { value: [1, 2] }",
        ),
    ] {
        let source = format!(
            r#"
struct Wrapped<T> {{ value: T }}
struct Other<T> {{ value: T }}
struct Five<A, B, C, D, E> {{ a: A, b: B, c: C, d: D, e: E }}
impl<A, B, C, D, E> Five<A, B, C, D, E> {{
    fn consume(self, value: Wrapped<[E; 2]>) -> i32 {{ return 0; }}
}}
fn main() -> i32 {{
    let owner: Five<bool, i32, bool, i32, i32> = Five {{ a: false, b: 11, c: true, d: 22, e: 33 }};
    let value: {ty} = {value};
    return owner.consume(value);
}}
"#
        );
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        })
        .err()
        .expect("a method argument must agree with the complete receiver environment");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn call_contract_constant_parameter_identity_is_declaration_scoped() {
    execute(
        "constant parameter declaration identity",
        include_str!("fixtures/stdlib_foundation/repro_unused_const_array_return.lani"),
    );
    let source = "fn wrong<const N: usize, const M: usize>(values: [i32; N]) -> [i32; M] { return values; } fn main() -> i32 { return 0; }";
    let error = common::run_gpu_codegen_with_timeout("distinct constant parameters", move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
            .expect("GPU compiler");
        pollster::block_on(compiler.compile_source_to_x86_64(source))
    })
    .err()
    .expect("different constant declarations must not compare equal");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn constant_environment_array_results_execute_distinct_lengths_and_types() {
    execute(
        "constant environments preserve array results",
        r#"
struct Wrapped<T> { value: T }
fn wrap<T, const N: usize>(values: [T; N]) -> Wrapped<[T; N]> { return Wrapped { value: values }; }
fn keep<T, const N: usize>(values: [T; N]) -> [T; N] { return values; }
fn main() -> i32 {
    let small: [i32; 2] = [11, -7];
    let large: [i32; 3] = [21, 22, 23];
    let flags: [bool; 2] = [false, true];
    let first: [i32; 2] = keep(small);
    let second = keep(large);
    let third = keep(flags);
    let nested = wrap(large);
    small[0] = 99;
    if (first[0] != 11 || first[1] != -7) { return 1; }
    if (second[0] != 21 || second[2] != 23) { return 2; }
    if (third[0] || !third[1]) { return 3; }
    if (nested.value[0] != 21 || nested.value[2] != 23) { return 4; }
    return 0;
}

"#,
    );
}

#[test]
fn constant_environment_zero_and_fifth_lengths_execute() {
    execute_with_stdout(
        "zero and fifth constant slots",
        r#"
import std::io;
fn keep<const N: usize>(values: [i32; N]) -> [i32; N] { return values; }
fn fifth<T, const A: usize, const B: usize, const C: usize, const D: usize, const E: usize>(
    a: [i32; A], b: [i32; B], c: [i32; C], d: [i32; D], e: [T; E]) -> [T; E] { return e; }
fn main() -> i32 {
    let empty: [i32; 0] = [];
    let copied: [i32; 0] = keep(empty);
    let one: [i32; 1] = [1];
    let two: [i32; 2] = [2, 3];
    let three: [i32; 3] = [4, 5, 6];
    let text: [str; 2] = ["first", "second"];
    let result: [str; 2] = fifth(empty, one, two, three, text);
    text[0] = "changed";
    std::io::println(result[0]);
    std::io::println(result[1]);
    let again: [i32; 1] = keep(one);
    if (again[0] != 1) { return 2; }
    return 0;
}
"#,
        b"first\nsecond\n",
    );
}

#[test]
fn constant_environment_rejects_conflicting_arguments_and_result_lengths() {
    for (label, expression, result) in [
        (
            "conflicting constant arguments",
            "same(short, long)",
            "[i32; 2]",
        ),
        (
            "conflicting result length",
            "same(short, short)",
            "[i32; 3]",
        ),
    ] {
        let source = format!(
            r#"
fn same<T, const N: usize>(a: [T; N], b: [T; N]) -> [T; N] {{ return a; }}
fn main() -> i32 {{
    let short: [i32; 2] = [1, 2];
    let long: [i32; 3] = [1, 2, 3];
    let value: {result} = {expression};
    return 0;
}}
"#
        );
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        })
        .err()
        .expect("incompatible constant bindings must reject before emission");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn constant_environment_imported_array_results_execute() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/constant.lani"),
        r#"
module core::constant;
pub fn before<U>(value: U) -> U { return value; }
pub fn keep<T, const N: usize>(values: [T; N]) -> [T; N] { return values; }
"#,
    )
    .expect("constant template module");
    execute_with_stdlib(
        "imported constant array environment",
        r#"
import core::relay;
import core::constant;
fn main() -> i32 {
    let short: [i32; 2] = [7, -3];
    let long: [i32; 3] = [11, 12, 13];
    let left: [i32; 2] = core::constant::keep(short);
    let right = core::constant::keep(long);
    if (core::relay::keep(42) != 42) { return 2; }
    if (left[0] != 7 || left[1] != -3 || right[2] != 13) { return 1; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn lexical_method_environment_keeps_impl_and_method_arguments_distinct() {
    execute(
        "impl and method lexical type environments",
        r#"
struct Boxed<T> { value: T }
struct Pair<A, B> { first: A, second: B }
impl<T> Boxed<T> {
    fn pair<U>(self, value: U) -> Pair<T, U> {
        return Pair { first: self.value, second: value };
    }
}
fn main() -> i32 {
    let numbers: Boxed<i32> = Boxed { value: 41 };
    let flags: Boxed<bool> = Boxed { value: false };
    let first = numbers.pair(true);
    let second = flags.pair(73);
    let array: [i32; 2] = [5, -8];
    let nested = flags.pair(array);
    array[0] = 99;
    if (first.first != 41 || !first.second) { return 1; }
    if (second.first || second.second != 73) { return 2; }
    if (nested.first || nested.second[0] != 5 || nested.second[1] != -8) { return 3; }
    return 0;
}
"#,
    );
}

#[test]
fn lexical_method_environment_supports_ordinary_owners_and_constant_results() {
    execute(
        "method type and constant environments",
        r#"
struct Plain { value: i32 }
struct Boxed<T> { value: T }
impl Plain {
    fn make<U>(value: U) -> U { return value; }
    fn keep<U>(self, value: U) -> U { return value; }
    fn copy<const N: usize>(self, value: [i32; N]) -> [i32; N] { return value; }
}
impl<T> Boxed<T> {
    fn copy<U, const N: usize>(self, value: [U; N]) -> [U; N] { return value; }
}
fn main() -> i32 {
    let plain: Plain = Plain { value: 9 };
    if (Plain::make(31) != 31 || !Plain::make(true)) { return 4; }
    if (!plain.keep(true) || plain.keep(17) != 17) { return 1; }
    let numbers: [i32; 2] = [23, -4];
    let empty: [i32; 0] = [];
    let empty_copy: [i32; 0] = plain.copy(empty);
    let kept = plain.copy(numbers);
    let boxed: Boxed<i32> = Boxed { value: 4 };
    let flags: [bool; 3] = [false, true, false];
    let copied = boxed.copy(flags);
    numbers[0] = 90;
    flags[1] = false;
    if (kept[0] != 23 || kept[1] != -4) { return 2; }
    if (copied[0] || !copied[1] || copied[2]) { return 3; }
    return 0;
}
"#,
    );
}

#[test]
fn lexical_method_environment_handles_reordered_impls_borrows_and_nested_calls() {
    execute(
        "reordered impl and nested method environments",
        r#"
struct Pair<A, B> { first: A, second: B }
impl<Y, X> Pair<X, Y> {
    fn take<U>(&self, value: U, first: X, second: Y) -> U { return value; }
    fn relay<V>(&self, value: V) -> V { return self.take(value, self.first, self.second); }
}
fn main() -> i32 {
    let pair: Pair<i32, bool> = Pair { first: 8, second: true };
    let value: Pair<[i32; 2], bool> = Pair { first: [7, -3], second: false };
    let result = pair.relay(value);
    value.first = [99, 100];
    if (result.first[0] != 7 || result.first[1] != -3 || result.second) { return 1; }
    if (pair.relay(11) != 11 || !pair.relay(true)) { return 2; }
    return 0;
}
"#,
    );
}

#[test]
fn lexical_method_environment_rejects_conflicts_and_missing_bindings() {
    for (label, method, call) in [
        (
            "repeated method parameter",
            "fn same<U>(self, a: U, b: U) -> i32 { return 0; }",
            "box.same(1, true)",
        ),
        (
            "inherited parameter conflict",
            "fn same<U>(self, a: U, b: T) -> i32 { return 0; }",
            "box.same(true, false)",
        ),
        (
            "missing method binding",
            "fn same<U>(self) -> i32 { return 0; }",
            "box.same()",
        ),
        (
            "method constant conflict",
            "fn same<const N: usize>(self, a: [i32; N], b: [i32; N]) -> i32 { return 0; }",
            "box.same(short, long)",
        ),
    ] {
        let source = format!(
            r#"
struct Boxed<T> {{ value: T }}
impl<T> Boxed<T> {{ {method} }}
fn main() -> i32 {{
    let box: Boxed<i32> = Boxed {{ value: 9 }};
    let short: [i32; 2] = [1, 2];
    let long: [i32; 3] = [1, 2, 3];
    return {call};
}}
"#
        );
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        })
        .err()
        .expect("incomplete or conflicting method environments must reject");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn lexical_method_environment_imported_parameters_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/repro_method_local_import_root");
    execute_with_stdlib(
        "imported method-local generic environment",
        include_str!("fixtures/stdlib_foundation/repro_method_local_import_root/main.lani"),
        &root,
        b"",
        0,
    );
}

#[test]
fn lexical_method_environment_imported_compounds_and_constants_execute() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/methods.lani"),
        r#"
module core::methods;
pub struct Boxed<T> { value: T }
pub struct Plain { value: i32 }
impl<T> Boxed<T> {
    pub fn keep<U>(&self, value: U) -> U { return value; }
    pub fn copy<U, const N: usize>(self, value: [U; N]) -> [U; N] { return value; }
}
impl Plain {
    pub fn make<U>(value: U) -> U { return value; }
}
"#,
    )
    .expect("imported method module");
    execute_with_stdlib(
        "imported compound lexical environments",
        r#"
import core::methods;
struct Pair<A, B> { first: A, second: B }
fn main() -> i32 {
    let owner: core::methods::Boxed<i32> = core::methods::Boxed { value: 9 };
    let value: Pair<[i32; 2], bool> = Pair { first: [7, -3], second: true };
    let result = owner.keep(value);
    value.first = [99, 100];
    if (result.first[0] != 7 || result.first[1] != -3 || !result.second) { return 1; }
    let flags: [bool; 3] = [false, true, false];
    let copied: [bool; 3] = owner.copy(flags);
    flags[1] = false;
    if (copied[0] || !copied[1] || copied[2]) { return 2; }
    let empty: [i32; 0] = [];
    let empty_copy: [i32; 0] = owner.copy(empty);
    if (!core::methods::Plain::make(true)) { return 3; }
    if (core::methods::Plain::make(42) != 42) { return 4; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn lexical_method_environment_imported_rejects_missing_and_conflicting_bindings() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/methods.lani"),
        r#"
module core::methods;
pub struct Boxed<T> { value: T }
impl<T> Boxed<T> {
    pub fn missing<U>(self) -> i32 { return 7; }
    pub fn missing_constant<const N: usize>(self) -> i32 { return 7; }
    pub fn same<U>(self, a: U, b: U) -> i32 { return 7; }
    pub fn inherited<U>(self, a: U, b: T) -> i32 { return 7; }
    pub fn lengths<const N: usize>(self, a: [i32; N], b: [i32; N]) -> i32 { return 7; }
}

"#,
    )
    .expect("imported requirement module");
    for (label, call, expected_code) in [
        (
            "imported missing unused type parameter",
            "owner.missing()",
            "LNC0006",
        ),
        (
            "imported missing unused constant parameter",
            "owner.missing_constant()",
            "LNC0006",
        ),
        (
            "imported repeated type conflict",
            "owner.same(1, true)",
            "LNC0006",
        ),
        (
            "imported inherited type conflict",
            "owner.inherited(true, false)",
            "LNC0006",
        ),
        (
            "imported constant conflict",
            "owner.lengths(short, long)",
            "LNC0006",
        ),
    ] {
        let entry = common::TempArtifact::new("imported_requirements", label, Some("lani"));
        entry.write_str(&format!(
            r#"
import core::methods;
fn main() -> i32 {{
    let owner: core::methods::Boxed<i32> = core::methods::Boxed {{ value: 9 }};
    let short: [i32; 2] = [1, 2];
    let long: [i32; 3] = [1, 2, 3];
    return {call};
}}
"#
        ));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout(label, move ||
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root)))
            .err().unwrap_or_else(|| panic!("{label}: incomplete or conflicting imported environments must reject before ELF publication"));
        assert_eq!(
            error.to_public_diagnostic().code,
            expected_code,
            "{label}: {error:?}"
        );
        assert!(
            error.to_public_diagnostic().primary_label.is_some(),
            "imported requirement diagnostics must label the caller: {label}: {error:?}"
        );
    }
}

#[test]
fn checked_window_program_executes_generic_values_and_portable_utilities() {
    execute_with_stdout(
        "checked packet window program",
        include_str!("../sample_programs/checked_window_checksum.lani"),
        b"96\n",
    );
}

#[test]
fn enum_constructor_literal_local_payload_executes() {
    execute(
        "local enum literal payload",
        include_str!("fixtures/stdlib_foundation/repro_local_enum_literal_payload.lani"),
    );
}

#[test]
fn enum_constructor_literal_imported_payload_executes() {
    execute(
        "imported enum literal payload",
        include_str!("fixtures/stdlib_foundation/repro_imported_enum_literal_payload.lani"),
    );
}

#[test]
fn enum_constructor_literal_compound_payloads_preserve_values_and_copies() {
    execute_with_stdout(
        "compound constructor literal payloads",
        r#"
import core::option;
import std::io;
struct Item { text: str, value: i32 }
enum Packet<T> { Data(T), Missing }
fn pack<T>(value: T) -> Packet<[T; 2]> { return Data([value, value]); }
fn main() -> i32 {
    let words: core::option::Option<[str; 2]> = core::option::Some(["first λ", "last"]);
    let backup: [str; 2] = ["", ""];
    let copied: [str; 2] = words.unwrap_or(backup);
    copied[0] = "changed";
    let original: [str; 2] = words.unwrap_or(backup);
    std::io::println(original[0]);
    std::io::println(original[1]);
    let matrix: Packet<[[i32; 2]; 2]> = Data([[11, 12], [21, 22]]);
    let empty_matrix: [[i32; 2]; 2] = [[0, 0], [0, 0]];
    let rows: [[i32; 2]; 2] = match (matrix) { Data(value) -> value, Missing -> empty_matrix };
    if (rows[0][1] != 12 || rows[1][0] != 21) { return 1; }
    let record: Packet<Item> = Data(Item { text: "record λ", value: 42 });
    let missing: Item = Item { text: "", value: 0 };
    let item: Item = match (record) { Data(value) -> value, Missing -> missing };
    if (item.value != 42) { return 2; }
    std::io::println(item.text);
    let items: core::option::Option<[Item; 2]> = core::option::Some([
        Item { text: "left", value: 31 }, Item { text: "right λ", value: 32 }]);
    let fallbacks: [Item; 2] = [missing, missing];
    let values: [Item; 2] = items.unwrap_or(fallbacks);
    values[1].value = 99;
    let preserved: [Item; 2] = items.unwrap_or(fallbacks);
    if (preserved[0].value != 31 || preserved[1].value != 32) { return 3; }
    std::io::println(preserved[1].text);
    let duplicated: Packet<[str; 2]> = pack("generic λ");
    let generic_words: [str; 2] = match (duplicated) { Data(value) -> value, Missing -> backup };
    std::io::println(generic_words[0]);
    std::io::println(generic_words[1]);
    return 0;
}
"#,
        "first λ\nlast\nrecord λ\nright λ\ngeneric λ\ngeneric λ\n".as_bytes(),
    );
}

#[test]
fn enum_constructor_literal_conflicting_payloads_reject_after_inference() {
    for (label, declaration, constructor) in [
        ("local array length", "Packet<[i32; 3]>", "Data([1, 2])"),
        ("local array element", "Packet<[bool; 2]>", "Data([1, 2])"),
        (
            "local nominal identity",
            "Packet<Item>",
            "Data(Other { value: 3 })",
        ),
        (
            "imported array length",
            "core::option::Option<[i32; 3]>",
            "core::option::Some([1, 2])",
        ),
        (
            "imported array element",
            "core::option::Option<[bool; 2]>",
            "core::option::Some([1, 2])",
        ),
        (
            "imported mixed elements",
            "core::option::Option<[i32; 2]>",
            "core::option::Some([1, true])",
        ),
        (
            "imported nominal identity",
            "core::option::Option<Item>",
            "core::option::Some(Other { value: 3 })",
        ),
    ] {
        let entry = common::TempArtifact::new("enum_literal_rejection", label, Some("lani"));
        entry.write_str(&format!(
            r#"
import core::option;
struct Item {{ value: i32 }}
struct Other {{ value: i32 }}
enum Packet<T> {{ Data(T), Missing }}
fn main() -> i32 {{ let packet: {declaration} = {constructor}; return 0; }}
"#
        ));
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| {
            panic!("{label}: conflicting constructor payload must reject before ELF publication")
        });
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn enum_constructor_expected_empty_payloads_execute() {
    execute(
        "constructor empty payload context",
        include_str!("fixtures/stdlib_foundation/repro_enum_expected_empty_payload.lani"),
    );
}

#[test]
fn enum_constructor_expected_unsigned_payloads_execute() {
    execute(
        "constructor unsigned payload context",
        include_str!("fixtures/stdlib_foundation/repro_enum_expected_unsigned_payload.lani"),
    );
}

#[test]
fn expected_argument_contexts_execute_nested_empty_and_unsigned_arrays() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "expected argument array contexts",
        r#"
import core::relay;
enum Packet<T> { Data(T), Missing }
fn take_empty(values: [str; 0]) -> bool { return true; }
fn keep_unsigned(values: [u32; 2]) -> [u32; 2] { return values; }
fn keep_array<T>(values: [T; 2]) -> [T; 2] { return values; }
fn main() -> i32 {
    if (!take_empty([])) { return 1; }
    let nested: Packet<[[str; 0]; 2]> = Data([[], []]);
    let local: [[str; 0]; 2] = keep_array([[], []]);
    let imported: [[str; 0]; 2] = core::relay::forward_array([[], []]);
    let direct: [u32; 2] = keep_unsigned([11, 42]);
    let generic: [u32; 2] = keep_array([2147483648, 4294967295]);
    let imported_unsigned: [u32; 2] = core::relay::forward_array([2147483648, 4294967295]);
    let present: bool = match (nested) { Data(value) -> true, Missing -> false };
    if (!present) { return 10; }
    if (direct[0] != 11 || direct[1] != 42) { return 11; }
    if (generic[0] != 2147483648 || generic[1] != 4294967295) { return 12; }
    if (imported_unsigned[0] != 2147483648 || imported_unsigned[1] != 4294967295) { return 13; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn expected_argument_contexts_reject_conflicting_known_values() {
    for (label, annotation, value, setup) in [
        ("wrong empty length", "[str; 1]", "[]", ""),
        ("mixed unsigned elements", "[u32; 2]", "[1, false]", ""),
        (
            "named signed value",
            "[u32; 2]",
            "[value, 42]",
            "let value: i32 = 11;",
        ),
        ("nested wrong length", "[[str; 0]; 2]", "[[], [], []]", ""),
        ("nested wrong element", "[[str; 0]; 2]", "[[], [false]]", ""),
    ] {
        for (imported, declaration, constructor) in [
            (false, format!("Packet<{annotation}>"), "Data"),
            (
                true,
                format!("core::option::Option<{annotation}>"),
                "core::option::Some",
            ),
        ] {
            let entry =
                common::TempArtifact::new("expected_argument_conflict", label, Some("lani"));
            entry.write_str(&format!(
                "{} enum Packet<T> {{ Data(T), Missing }} fn main() -> i32 {{ {setup} let wrong: {declaration} = {constructor}({value}); return 0; }}",
                if imported { "import core::option;" } else { "" }
            ));
            let path = entry.path().to_path_buf();
            let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
            let error = common::run_gpu_codegen_with_timeout(label, move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            })
            .expect_err("conflicting expected argument must reject before executable publication");
            assert_eq!(
                error.to_public_diagnostic().code,
                "LNC0006",
                "{label}, imported={imported}: {error:?}"
            );
        }
    }
}

#[test]
fn imported_constructor_contexts_preserve_compound_payload_patterns() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/packets.lani"),
        include_str!(
            "fixtures/stdlib_foundation/repro_expected_constructor_root/core/packets.lani"
        ),
    )
    .expect("compound constructor module");
    execute_with_stdlib(
        "imported compound constructor contexts",
        r#"
import core::packets;
import std::io;
fn main() -> i32 {
    let batch: core::packets::Batch<u32, str> = core::packets::Data([2147483648, 4294967295], "compound λ");
    let fallback: [u32; 2] = [0, 0];
    let values: [u32; 2] = match (batch) { Data(numbers, label) -> numbers, Missing -> fallback };
    let label: str = match (batch) { Data(numbers, label) -> label, Missing -> "missing" };
    std::io::println(label);
    if (values[0] != 2147483648 || values[1] != 4294967295) { return 1; }
    let zero: core::packets::Batch<[str; 0], str> = core::packets::Data([[], []], "zero");
    let zero_label: str = match (zero) { Data(numbers, label) -> label, Missing -> "missing" };
    std::io::println(zero_label);
    return 0;
}

"#,
        stdlib.0.path(),
        "compound λ\nzero\n".as_bytes(),
        0,
    );

    for (label, values, payload) in [
        ("compound payload length", "[11]", "\"label\""),
        ("compound payload element", "[11, false]", "\"label\""),
        ("second type binding", "[11, 42]", "false"),
    ] {
        let entry = common::TempArtifact::new("imported_compound_context", label, Some("lani"));
        entry.write_str(&format!(
            "import core::packets; fn main() -> i32 {{ let batch: core::packets::Batch<u32, str> = core::packets::Data({values}, {payload}); return 0; }}"
        ));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        })
        .expect_err("compound pattern must agree with every argument");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn enum_layouts_include_unconstructed_compound_variants() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/layouts.lani"),
        include_str!(
            "fixtures/stdlib_foundation/repro_expected_constructor_root/core/layouts.lani"
        ),
    )
    .expect("enum layout module");
    for imported in [false, true] {
        let (declaration, owner, present, absent) = if imported {
            (
                "import core::layouts;",
                "core::layouts::Envelope",
                "core::layouts::Present",
                "core::layouts::Absent",
            )
        } else {
            (
                "enum Envelope<A, B> { Present(A, B), Reserved([B; 3]), Nested([[B; 0]; 2]), Absent }",
                "Envelope",
                "Present",
                "Absent",
            )
        };
        execute_with_stdlib(
            if imported {
                "imported unconstructed enum layouts"
            } else {
                "local unconstructed enum layouts"
            },
            &format!(
                r#"
import std::io;
{declaration}
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{
    let seed: u32 = 4294967295;
    let original: {owner}<u32, str> = {present}(seed, "unused variants λ");
    let copied: {owner}<u32, str> = keep(original);
    let label: str = match (copied) {{ Present(number, text) -> text, _ -> "wrong" }};
    let fallback: u32 = 0;
    let number: u32 = match (original) {{ Present(number, text) -> number, _ -> fallback }};
    if (number != 4294967295) {{ return 1; }}
    std::io::println(label);
    let empty: {owner}<bool, [str; 0]> = {present}(true, []);
    let empty_copy: {owner}<bool, [str; 0]> = keep(empty);
    let flag: bool = match (empty_copy) {{ Present(flag, value) -> flag, _ -> false }};
    if (!flag) {{ return 2; }}
    let missing: {owner}<u32, str> = {absent}();
    let missing_copy: {owner}<u32, str> = keep(missing);
    let is_absent: bool = match (missing_copy) {{ Absent -> true, _ -> false }};
    if (!is_absent) {{ return 3; }}
    return 0;
}}
"#
            ),
            stdlib.0.path(),
            "unused variants λ\n".as_bytes(),
            0,
        );
    }
}

#[test]
fn scalar_literal_contexts_execute_imported_unsigned_constructors() {
    execute(
        "imported unsigned scalar constructor context",
        include_str!(
            "fixtures/stdlib_foundation/repro_imported_unsigned_scalar_literal_context.lani"
        ),
    );
}

#[test]
fn scalar_literal_contexts_execute_unsigned_match_arms() {
    execute(
        "unsigned scalar match context",
        include_str!("fixtures/stdlib_foundation/repro_unsigned_match_literal_context.lani"),
    );
    execute(
        "unsigned literal absent branch",
        r#"
enum Maybe<T> { Present(T), Absent }
fn main() -> i32 {
    let wrapped: Maybe<u32> = Absent();
    let value: u32 = match (wrapped) { Present(number) -> number, Absent -> 2147483648 };
    if (value / 2 != 1073741824) { return 1; }
    return 0;
}
"#,
    );
}

#[test]
fn scalar_literal_contexts_execute_local_imported_and_ordinary_calls() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "scalar call contexts",
        r#"
import core::relay;
enum Packet<T> { Data(T), Missing }
fn keep<T>(value: T) -> T { return value; }
fn unsigned(value: u32) -> u32 { return value; }
fn main() -> i32 {
    let ordinary: u32 = unsigned(4294967295);
    let local: u32 = keep(4294967295);
    let imported: u32 = core::relay::forward(2147483648);
    let packet: Packet<u32> = Data(4294967295);
    let fallback: u32 = 0;
    let extracted: u32 = match (packet) { Data(v) -> v, Missing -> fallback };
    if (extracted / 2 != 2147483647) { return 5; }
    if (ordinary / 2 != 2147483647) { return 1; }
    if (local / 2 != 2147483647) { return 2; }
    if (imported / 2 != 1073741824) { return 3; }
    let default = keep(42);
    if (default != 42) { return 4; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn scalar_literal_contexts_reject_named_values_and_noninteger_literals() {
    let stdlib = ReceiverTestStdlib::new();
    for (label, source) in [
        (
            "local generic named signed",
            "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { let signed: i32 = 42; let v: u32 = keep(signed); return 0; }",
        ),
        (
            "imported generic named signed",
            "import core::relay; fn main() -> i32 { let signed: i32 = 42; let v: u32 = core::relay::forward(signed); return 0; }",
        ),
        (
            "imported constructor named signed",
            "import core::option; fn main() -> i32 { let signed: i32 = 42; let v: core::option::Option<u32> = core::option::Some(signed); return 0; }",
        ),
        (
            "local constructor named signed",
            "enum Maybe<T> { Present(T), Absent } fn main() -> i32 { let signed: i32 = 42; let v: Maybe<u32> = Present(signed); return 0; }",
        ),
        (
            "local generic float",
            "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { let v: u32 = keep(1.5); return 0; }",
        ),
        (
            "imported generic float",
            "import core::relay; fn main() -> i32 { let v: u32 = core::relay::forward(1.5); return 0; }",
        ),
        (
            "imported constructor bool",
            "import core::option; fn main() -> i32 { let v: core::option::Option<u32> = core::option::Some(false); return 0; }",
        ),
        (
            "unsigned match named signed",
            "enum Maybe<T> { Present(T), Absent } fn main() -> i32 { let signed: i32 = 42; let seed: u32 = 7; let v: Maybe<u32> = Present(seed); let n: u32 = match (v) { Present(n) -> n, Absent -> signed }; return 0; }",
        ),
        (
            "unsigned match float",
            "enum Maybe<T> { Present(T), Absent } fn main() -> i32 { let seed: u32 = 7; let v: Maybe<u32> = Present(seed); let n: u32 = match (v) { Present(n) -> n, Absent -> 1.5 }; return 0; }",
        ),
        (
            "two conflicting named arguments",
            "fn same<T>(a: T, b: T) -> T { return a; } fn main() -> i32 { let a: i32 = 1; let b: u32 = 2; let n: u32 = same(a, b); return 0; }",
        ),
    ] {
        let entry = common::TempArtifact::new("scalar_context_reject", label, Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let root = if source.contains("core::option") {
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib")
        } else {
            stdlib.0.path().to_path_buf()
        };
        let compiled = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        });
        let error = match compiled {
            Err(error) => error,
            Ok(_) => panic!("{label}: expected context must not change a known value type"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn literal_argument_inference_uses_known_types_in_either_order() {
    execute(
        "literal argument inference",
        include_str!("fixtures/stdlib_foundation/repro_generic_literal_argument_inference.lani"),
    );
    execute(
        "known numeric inference inside a generic body",
        include_str!(
            "fixtures/stdlib_foundation/repro_generic_literal_argument_inference_body.lani"
        ),
    );
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "imported literal argument inference",
        r#"
import core::relay;
fn main() -> i32 {
    let number: u32 = 4294967295;
    let last = core::relay::choose(1, number, false);
    let first = core::relay::choose(number, 1, true);
    let literal = core::relay::choose(number, 2147483648, false);
    if (last / 2 != 2147483647 || first / 2 != 2147483647) { return 1; }
    if (literal / 2 != 1073741824) { return 2; }
    let default = core::relay::choose(41, 42, false);
    if (default != 42) { return 3; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn literal_argument_inference_rejects_conflicting_known_types() {
    let stdlib = ReceiverTestStdlib::new();
    for (label, call) in [
        (
            "local known signed and unsigned",
            "choose(signed, unsigned, false)",
        ),
        (
            "local known unsigned and signed",
            "choose(unsigned, signed, true)",
        ),
        (
            "imported known signed and unsigned",
            "core::relay::choose(signed, unsigned, false)",
        ),
        (
            "imported known unsigned and signed",
            "core::relay::choose(unsigned, signed, true)",
        ),
        ("local literal and Boolean", "choose(1, false, true)"),
        ("local Boolean and literal", "choose(false, 1, false)"),
        (
            "imported literal and floating",
            "core::relay::choose(1, 1.5, true)",
        ),
        (
            "imported floating and literal",
            "core::relay::choose(1.5, 1, false)",
        ),
        ("local literal array length", "choose([1, 2], longer, true)"),
        (
            "imported literal array length",
            "core::relay::choose([1, 2], longer, true)",
        ),
        (
            "local named array elements",
            "choose(signed_array, unsigned_array, false)",
        ),
        (
            "imported named array elements",
            "core::relay::choose(signed_array, unsigned_array, false)",
        ),
    ] {
        let entry = common::TempArtifact::new("literal_argument_conflict", label, Some("lani"));
        entry.write_str(&format!(
            r#"
import core::relay;
fn choose<T>(left: T, right: T, first: bool) -> T {{ if (first) {{ return left; }} return right; }}
fn main() -> i32 {{
    let signed: i32 = 1; let unsigned: u32 = 2;
    let longer: [u32; 3] = [1, 2, 3];
    let signed_array: [i32; 2] = [1, 2];
    let unsigned_array: [u32; 2] = [1, 2];
    let result = {call}; return 0;
}}
"#
        ));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let compiled = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        });
        let error = compiled
            .err()
            .unwrap_or_else(|| panic!("{label}: inference must reject incompatible known types"));
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn literal_argument_inference_preserves_array_and_nested_types() {
    execute(
        "array element inference from a later argument",
        include_str!(
            "fixtures/stdlib_foundation/repro_generic_array_literal_argument_inference.lani"
        ),
    );
    execute(
        "nested argument literal inference",
        include_str!(
            "fixtures/stdlib_foundation/repro_generic_nested_literal_argument_inference.lani"
        ),
    );
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "imported array argument literal inference",
        r#"
import core::relay;
fn main() -> i32 {
    let typed: [u32; 2] = [4294967295, 7];
    let later = core::relay::choose([2147483648, 1], typed, true);
    let earlier = core::relay::choose(typed, [2147483648, 1], true);
    if (later[0] / 2 != 1073741824 || earlier[0] / 2 != 2147483647) { return 1; }
    earlier[0] = 0;
    if (typed[0] / 2 != 2147483647) { return 2; }
    let matrix: [[u32; 2]; 2] = [[4294967295, 7], [8, 9]];
    let nested = core::relay::choose([[2147483648, 1], [2, 3]], matrix, true);
    if (nested[0][0] / 2 != 1073741824 || nested[1][1] != 3) { return 3; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn constant_length_inference_preserves_symbolic_forwarding() {
    execute_with_stdout(
        "symbolic caller length forwarding",
        include_str!("fixtures/stdlib_foundation/repro_generic_symbolic_length_forwarding.lani"),
        "first λ\nchanged\nlast\n".as_bytes(),
    );
}

#[test]
fn constant_length_inference_preserves_nested_patterns() {
    execute_with_stdout(
        "nested constant length and element pattern",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_length_inference.lani"),
        "a\nchanged\nb λ\nf\n".as_bytes(),
    );
}

#[test]
fn constant_length_inference_collects_all_dimensions_locally_and_imported() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib(
        "complete matrix constant environments",
        r#"
import core::relay;
import std::io;
fn keep<T, const N: usize, const M: usize>(value: [[T; N]; M]) -> [[T; N]; M] { return value; }
fn forward<T, const K: usize, const L: usize>(value: [[T; K]; L]) -> [[T; K]; L] {
    return keep(value);
}
fn main() -> i32 {
    let words: [[str; 3]; 2] = [["a", "b λ", "c"], ["d", "e", "f"]];
    let local: [[str; 3]; 2] = forward(words);
    let imported: [[str; 3]; 2] = core::relay::keep_matrix(words);
    local[0][1] = "changed"; imported[1][2] = "changed too";
    std::io::println(words[0][1]);
    std::io::println(words[1][2]);
    std::io::println(local[1][2]);
    std::io::println(imported[0][1]);
    std::io::println(local[0][1]);
    std::io::println(imported[1][2]);
    let empty: [[bool; 0]; 2] = [[], []];
    let zero: [[bool; 0]; 2] = keep(empty);
    let imported_zero: [[bool; 0]; 2] = core::relay::keep_matrix(empty);
    let flags: [bool; 2] = [false, true];
    let copied: [bool; 2] = core::relay::forward_length(flags);
    copied[0] = true;
    if (flags[0] || !flags[1] || !copied[0] || !copied[1]) { return 2; }
    return 0;
}
"#,
        stdlib.0.path(),
        "b λ\nf\nf\nb λ\nchanged\nchanged too\n".as_bytes(),
        0,
    );
}

#[test]
fn constant_length_inference_rejects_fixed_and_repeated_dimension_conflicts() {
    let stdlib = ReceiverTestStdlib::new();
    for (label, call) in [
        ("local repeated nested length", "square(rectangle)"),
        (
            "imported repeated nested length",
            "core::relay::square(rectangle)",
        ),
        ("fixed outer length", "fixed(three_rows)"),
        ("repeated length across arguments", "same(short, long)"),
        ("same length different element type", "same(short, flags)"),
        ("nested expected result inner length", "keep(rectangle)"),
        (
            "imported expected result inner length",
            "core::relay::keep_matrix(rectangle)",
        ),
    ] {
        let entry = common::TempArtifact::new("constant_length_conflict", label, Some("lani"));
        let annotation = if label.contains("expected result") {
            ": [[i32; 2]; 2]"
        } else {
            ""
        };
        entry.write_str(&format!(
            r#"
import core::relay;
fn square<const N: usize>(value: [[i32; N]; N]) -> [[i32; N]; N] {{ return value; }}
fn fixed<T, const N: usize>(value: [[T; N]; 2]) -> [[T; N]; 2] {{ return value; }}
fn same<T, const N: usize>(left: [T; N], right: [T; N]) -> [T; N] {{ return left; }}
fn keep<T, const N: usize, const M: usize>(value: [[T; N]; M]) -> [[T; N]; M] {{ return value; }}
fn main() -> i32 {{
    let rectangle: [[i32; 3]; 2] = [[1, 2, 3], [4, 5, 6]];
    let three_rows: [[i32; 2]; 3] = [[1, 2], [3, 4], [5, 6]];
    let short: [i32; 2] = [1, 2]; let long: [i32; 3] = [1, 2, 3];
    let flags: [bool; 2] = [false, true];
    let wrong{annotation} = {call}; return 0;
}}
"#
        ));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let compiled = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        });
        let error = compiled
            .err()
            .unwrap_or_else(|| panic!("{label}: incompatible dimensions must reject"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic.primary_label.as_ref().is_some_and(|label| label
                .source_line
                .as_deref()
                .is_some_and(|line| line.contains("let wrong"))),
            "{label}: rejection must identify the conflicting call: {diagnostic:?}"
        );
    }
}

fn nested_constant_type(element: &str, lengths: impl IntoIterator<Item = String>) -> String {
    lengths
        .into_iter()
        .fold(element.to_owned(), |child, length| {
            format!("[{child}; {length}]")
        })
}

#[test]
fn constant_length_inference_executes_all_32_slots_locally_and_imported() {
    let stdlib = ReceiverTestStdlib::new();
    let parameters = (0..32)
        .map(|slot| format!("const N{slot}: usize"))
        .collect::<Vec<_>>()
        .join(", ");
    let pattern = nested_constant_type("T", (0..32).map(|slot| format!("N{slot}")));
    let declarations = format!(
        "pub fn keep<T, {parameters}>(value: {pattern}) -> {pattern} {{ return value; }} \
         pub fn forward<T, {parameters}>(value: {pattern}) -> {pattern} {{ return keep(value); }} \
         pub fn measure<T, {parameters}>(value: {pattern}) -> usize {{ return N0 + N4 * 10 + N15 * 100 + N31 * 1000; }} \
         pub fn forward_measure<T, {parameters}>(value: {pattern}) -> usize {{ return measure(value) + N31; }}"
    );
    std::fs::write(
        stdlib.0.path().join("core/many_lengths.lani"),
        format!("module core::many_lengths;\n{declarations}"),
    )
    .expect("32-constant module");
    let lengths = (0..32)
        .map(|slot| match slot {
            0 | 15 | 31 => 2,
            4 => 3,
            _ => 1,
        })
        .collect::<Vec<_>>();
    let concrete = nested_constant_type("str", lengths.iter().map(u32::to_string));
    let literal = lengths
        .iter()
        .skip(1)
        .fold("[\"left\", \"right λ\"]".to_owned(), |child, &length| {
            format!("[{}]", vec![child; length as usize].join(", "))
        });
    let path = lengths
        .iter()
        .skip(1)
        .rev()
        .map(|length| format!("[{}]", length - 1))
        .collect::<String>();
    let source = format!(
        r#"
import std::io;
import core::many_lengths;
{declarations}
fn main() -> i32 {{
    let original: {concrete} = {literal};
    let local: {concrete} = forward(original);
    let imported: {concrete} = core::many_lengths::forward(original);
    if (measure(original) != 2232 || forward_measure(original) != 2234) {{ return 1; }}
    if (core::many_lengths::measure(original) != 2232 ||
        core::many_lengths::forward_measure(original) != 2234) {{ return 2; }}
    local{path}[0] = "changed local";
    imported{path}[1] = "changed imported";
    std::io::println(original{path}[0]); std::io::println(original{path}[1]);
    std::io::println(local{path}[0]); std::io::println(local{path}[1]);
    std::io::println(imported{path}[0]); std::io::println(imported{path}[1]);
    return 0;
}}
"#
    );
    execute_with_stdlib(
        "all 32 constant slots",
        &source,
        stdlib.0.path(),
        "left\nright λ\nchanged local\nright λ\nleft\nchanged imported\n".as_bytes(),
        0,
    );
}

#[test]
fn constant_length_inference_rejects_a_33rd_slot_explicitly() {
    let parameters = (0..33)
        .map(|slot| format!("const N{slot}: usize"))
        .collect::<Vec<_>>()
        .join(", ");
    let pattern = nested_constant_type("i32", (0..33).map(|slot| format!("N{slot}")));
    let concrete = nested_constant_type("i32", (0..33).map(|_| "1".to_owned()));
    let literal = (0..33).fold("42".to_owned(), |child, _| format!("[{child}]"));
    let source = format!(
        "fn keep<{parameters}>(value: {pattern}) -> {pattern} {{ return value; }} fn main() -> i32 {{ let value: {concrete} = {literal}; let rejected = keep(value); return 0; }}"
    );
    let error = common::run_gpu_codegen_with_timeout("33rd constant parameter", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(&source),
        )
    })
    .err()
    .expect("a 33rd constant slot must reject before emitting an ELF");
    assert_eq!(error.to_public_diagnostic().code, "LNC0047", "{error:?}");
    for kind in ["type", "constant"] {
        let parameters = (0..33)
            .map(|slot| {
                if kind == "type" {
                    format!("T{slot}")
                } else {
                    format!("const N{slot}: usize")
                }
            })
            .collect::<Vec<_>>()
            .join(", ");
        let source = format!(
            "fn unused<{parameters}>() -> i32 {{ return 1; }} fn main() -> i32 {{ return 0; }}"
        );
        let boundary_column = source
            .find(if kind == "type" { "T32" } else { "N32" })
            .unwrap()
            + 1;
        let error = common::run_gpu_codegen_with_timeout("unused 33rd generic slot", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(&source),
            )
        })
        .err()
        .expect("an unused 33rd slot must reject at declaration publication");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0047", "{kind}: {error:?}");
        let label = diagnostic
            .primary_label
            .expect("parameter boundary location");
        assert_eq!(label.column as usize, boundary_column, "{kind}: {label:?}");
    }
}

#[test]
fn generic_constant_values_execute_in_expressions() {
    execute(
        "constant values in generic bodies",
        include_str!("fixtures/stdlib_foundation/repro_generic_constant_value_expression.lani"),
    );
}

#[test]
fn generic_constant_values_execute_with_declared_types_and_lexical_scope() {
    let stdlib = ReceiverTestStdlib::new();
    let declarations = r#"
pub fn sum<const N: usize>(values: [i32; N]) -> i32 {
    let total: i32 = 0;
    let index: usize = 0;
    while (index < N) { total = total + values[index]; index = index + 1; }
    return total;
}
pub fn forward<const M: usize>(values: [i32; M]) -> i32 { return sum(values); }
pub fn dimensions<const N: usize, const M: u32>(rows: [[i32; N]; M]) -> usize {
    return N * 10 + M;
}
pub fn signed_length<const N: i32>(values: [i32; N]) -> i32 { return N; }
pub fn shadow_local<const N: usize>(values: [i32; N]) -> i32 {
    let N: i32 = 7;
    N += 2;
    return N;
}
pub fn shadow_parameter<const N: usize>(N: i32, values: [i32; N]) -> i32 {
    return N;
}
"#;
    std::fs::write(
        stdlib.0.path().join("core/constant_values.lani"),
        format!("module core::constant_values;\n{declarations}"),
    )
    .expect("constant expression module");
    let source = format!(
        r#"
import core::constant_values;
{declarations}
fn main() -> i32 {{
    let empty: [i32; 0] = [];
    let single: [i32; 1] = [-7];
    let values: [i32; 3] = [11, 22, 33];
    let rows: [[i32; 3]; 2] = [[1, 2, 3], [4, 5, 6]];
    if (sum(empty) != 0 || sum(single) != -7 || sum(values) != 66) {{ return 1; }}
    if (forward(empty) != 0 || forward(values) != 66) {{ return 2; }}
    if (dimensions(rows) != 32 || signed_length(values) != 3) {{ return 3; }}
    if (shadow_local(values) != 9 || shadow_parameter(9, values) != 9) {{ return 4; }}
    if (core::constant_values::forward(empty) != 0 ||
        core::constant_values::forward(values) != 66) {{ return 5; }}
    if (core::constant_values::dimensions(rows) != 32 ||
        core::constant_values::signed_length(values) != 3) {{ return 6; }}
    if (core::constant_values::shadow_local(values) != 9 ||
        core::constant_values::shadow_parameter(9, values) != 9) {{ return 7; }}
    return 0;
}}
"#
    );
    execute_with_stdlib(
        "constant types and scopes",
        &source,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_constant_values_reject_invalid_value_uses() {
    for (label, source, expected_code) in [
        (
            "outside owner",
            "fn length<const N: usize>(v: [i32; N]) -> usize { return N; } fn main() -> i32 { return N; }",
            "LNC0005",
        ),
        (
            "type parameter as value",
            "fn bad<T>(v: T) -> i32 { return T; } fn main() -> i32 { return bad(1); }",
            "LNC0005",
        ),
        (
            "constant condition",
            "fn bad<const N: usize>(v: [i32; N]) -> i32 { if (N) { return 1; } return 0; } fn main() -> i32 { return bad([1]); }",
            "LNC0006",
        ),
        (
            "constant boolean arithmetic",
            "fn bad<const N: usize>(v: [i32; N]) -> usize { return N + false; } fn main() -> i32 { let v = bad([1]); return 0; }",
            "LNC0006",
        ),
        (
            "constant wrong result",
            "fn bad<const N: usize>(v: [i32; N]) -> bool { return N; } fn main() -> i32 { if (bad([1])) { return 1; } return 0; }",
            "LNC0006",
        ),
    ] {
        let source = source.to_owned();
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(&source),
            )
        })
        .err()
        .unwrap_or_else(|| panic!("{label}: invalid constant use emitted an ELF"));
        assert_eq!(
            error.to_public_diagnostic().code,
            expected_code,
            "{label}: {error:?}"
        );
    }
}

#[test]
fn generic_constant_values_defer_unused_symbolic_bodies() {
    execute(
        "unused symbolic constant value",
        "fn length<const N: usize>() -> usize { return N; } fn main() -> i32 { return 0; }",
    );
}

#[test]
fn generic_constant_values_execute_through_method_environments() {
    let stdlib = ReceiverTestStdlib::new();
    let declarations = r#"
pub struct Boxed<T> { value: T }
pub struct Plain { value: i32 }
impl<T> Boxed<T> {
    pub fn length<U, const N: usize>(&self, values: [U; N]) -> usize { return N; }
    pub fn forward<V, const M: usize>(&self, values: [V; M]) -> usize {
        return self.length(values) + M;
    }
    pub fn dimensions<const N: usize, const M: u32>(&self, values: [[i32; N]; M]) -> usize {
        return N * 10 + M;
    }
}
impl Plain {
    pub fn length<const N: usize>(values: [i32; N]) -> usize { return N; }
    pub fn dimensions<const N: usize, const M: usize>(values: [[i32; N]; M]) -> usize { return N + 10 * M; }
}
"#;
    std::fs::write(
        stdlib.0.path().join("core/constant_methods.lani"),
        format!("module core::constant_methods;\n{declarations}"),
    )
    .expect("constant method module");
    let source = format!(
        r#"
import core::constant_methods;
{declarations}
fn main() -> i32 {{
    let local: Boxed<bool> = Boxed {{ value: false }};
    let imported: core::constant_methods::Boxed<i32> = core::constant_methods::Boxed {{ value: 42 }};
    let empty: [bool; 0] = [];
    let texts: [str; 2] = ["left", "right λ"];
    let rows: [[i32; 3]; 2] = [[1, 2, 3], [4, 5, 6]];
    let static_values: [i32; 2] = [4, 5];
    if (local.length(empty) != 0 || local.length(texts) != 2 || local.forward(texts) != 4) {{ return 1; }}
    if (imported.length(empty) != 0 || imported.length(texts) != 2 || imported.forward(texts) != 4) {{ return 2; }}
    if (local.dimensions(rows) != 32 || imported.dimensions(rows) != 32) {{ return 3; }}
    if (Plain::length([1, 2, 3]) != 3 || core::constant_methods::Plain::length(static_values) != 2) {{ return 4; }}
    return 0;
}}
"#
    );
    execute_with_stdlib("method constant values", &source, stdlib.0.path(), b"", 0);
}

#[test]
fn generic_constant_values_execute_in_imported_associated_array_literals() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/constant_factory.lani"),
        r#"
module core::constant_factory;
pub struct Plain { value: i32 }
impl Plain {
    pub fn length<const N: usize>(values: [i32; N]) -> usize { return N; }
    pub fn dimensions<const N: usize, const M: usize>(values: [[i32; N]; M]) -> usize { return N + 10 * M; }
}
"#,
    )
    .expect("associated constant fixture");
    execute_with_stdlib(
        "associated constant array literals",
        r#"
import core::constant_factory;
fn main() -> i32 {
    if (core::constant_factory::Plain::length([4, 5]) != 2) { return 1; }
    if (core::constant_factory::Plain::length([]) != 0) { return 2; }
    if (core::constant_factory::Plain::dimensions([[], []]) != 20) { return 3; }
    if (core::constant_factory::Plain::dimensions([[1, 2], [3, 4]]) != 22) { return 4; }
    return 0;
}

"#,
        stdlib.0.path(),
        b"",
        0,
    );
    for argument in ["[true, false]", "[1, 2.5]"] {
        let entry =
            common::TempArtifact::new("constant_static_type_conflict", "entry", Some("lani"));
        entry.write_str(&format!("import core::constant_factory; fn main() -> i32 {{ let value = core::constant_factory::Plain::length({argument}); return 0; }}"));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout(
            "associated constant argument mismatch",
            move || pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root)),
        )
        .err()
        .unwrap_or_else(|| panic!("{argument}: incompatible associated argument emitted an ELF"));
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{argument}: {error:?}"
        );
    }
}

#[test]
fn generic_constant_values_execute_nested_array_shape_contexts() {
    execute(
        "nested shape context before length inference",
        r#"
fn length<const N: usize>(values: [i32; N]) -> usize { return N; }
fn dimensions<const N: usize, const M: usize, const K: usize>(values: [[[i32; N]; M]; K]) -> usize {
    return N + 10 * M + 100 * K;
}
fn main() -> i32 {
    if (length([]) != 0 || length([7, 8]) != 2) { return 1; }
    if (dimensions([[[], []], [[], []]]) != 220) { return 2; }
    if (dimensions([[[1, 2, 3]], [[4, 5, 6]]]) != 213) { return 3; }
    return 0;
}
"#,
    );
    for source in [
        "fn square<const N: usize>(v: [[i32; N]; N]) -> usize { return N; } fn main() -> i32 { let v = square([[], []]); return 0; }",
        "fn exact(v: [[i32; 2]; 2]) -> i32 { return 0; } fn main() -> i32 { return exact([[1], [2]]); }",
        "fn length<T, const N: usize>(v: [T; N]) -> usize { return N; } fn main() -> i32 { let v = length([]); return 0; }",
        "fn dimensions<const N: usize, const M: usize>(v: [[i32; N]; M]) -> usize { return N + M; } fn main() -> i32 { let v = dimensions([]); return 0; }",
    ] {
        let error = common::run_gpu_codegen_with_timeout(
            "shape context preserves declaration constraints",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(source),
                )
            },
        )
        .err()
        .expect("literal shape cannot authorize a contradictory or unbound declaration");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
    }
}

#[test]
fn generic_constant_values_reject_missing_bindings() {
    for source in [
        "fn length<const N: usize>() -> usize { return N; } fn main() -> i32 { let value = length(); return 0; }",
        "struct Plain { value: i32 } impl Plain { fn length<const N: usize>(&self) -> usize { return N; } } fn main() -> i32 { let value: Plain = Plain { value: 1 }; let length = value.length(); return 0; }",
        "fn unused<const N: usize>() -> i32 { return 7; } fn main() -> i32 { return unused(); }",
        "struct Plain { value: i32 } impl Plain { fn unused<const N: usize>(&self) -> i32 { return 7; } } fn main() -> i32 { let value: Plain = Plain { value: 1 }; return value.unused(); }",
    ] {
        let error =
            common::run_gpu_codegen_with_timeout("missing constant value binding", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(source),
                )
            })
            .err()
            .expect("a used constant parameter without a binding must not emit an ELF");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{error:?}");
        assert!(diagnostic.primary_label.is_some(), "{diagnostic:?}");
    }
}

#[test]
fn generic_constant_values_reject_mutation() {
    for (parameter, assignment) in [
        ("N", "N = 7"),
        ("N", "N += 7"),
        ("n", "n = 7"),
        ("n", "n += 7"),
        ("N", "(N) += 7"),
    ] {
        let source = format!(
            "fn bad<const {parameter}: usize>(values: [i32; {parameter}]) -> usize {{ {assignment}; return {parameter}; }} fn main() -> i32 {{ let result = bad([1, 2, 3]); return 0; }}"
        );
        let error =
            common::run_gpu_codegen_with_timeout("constant parameter mutation", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(&source),
                )
            })
            .err()
            .unwrap_or_else(|| {
                panic!("{assignment}: assignment to a constant parameter emitted an ELF")
            });
        let diagnostic = error.to_public_diagnostic();
        assert!(
            ["LNC0016", "LNC0068"].contains(&diagnostic.code.as_str()),
            "{assignment}: {error:?}"
        );
    }
}

#[test]
fn generic_constant_values_reject_noninteger_array_lengths() {
    for annotation in ["bool", "f32", "str"] {
        let source = format!(
            "fn bad<const N: {annotation}>(values: [i32; N]) -> i32 {{ return 0; }} fn main() -> i32 {{ return bad([1, 2, 3]); }}"
        );
        let error = common::run_gpu_codegen_with_timeout("constant array length type", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(&source),
            )
        })
        .err()
        .unwrap_or_else(|| panic!("{annotation} constant array length emitted an ELF"));
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{annotation}: {error:?}"
        );
    }
}

#[test]
fn generic_result_only_constants_execute_local_calls() {
    execute(
        "result-only constant bindings",
        include_str!("fixtures/stdlib_foundation/repro_generic_result_only_constant.lani"),
    );
}

#[test]
fn generic_result_only_constants_execute_imported_calls() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/result_constants.lani"),
        r#"
module core::result_constants;
pub enum Length<T> { Known(usize), Values(T) }
pub fn length<T, const N: usize>() -> Length<[T; N]> { return Known(N); }
pub fn dimensions<const N: usize, const M: usize>() -> Length<[[str; N]; M]> {
    return Known(N + 10 * M);
}
"#,
    )
    .expect("result constant module");
    execute_with_stdlib(
        "imported result-only constants",
        r#"
import core::result_constants;
fn main() -> i32 {
    let empty: core::result_constants::Length<[bool; 0]> = core::result_constants::length();
    let texts: core::result_constants::Length<[str; 3]> = core::result_constants::length();
    let rows: core::result_constants::Length<[[str; 3]; 2]> = core::result_constants::dimensions();
    let a: usize = match (empty) { core::result_constants::Known(n) => n, core::result_constants::Values(v) => 99 };
    let b: usize = match (texts) { core::result_constants::Known(n) => n, core::result_constants::Values(v) => 99 };
    let c: usize = match (rows) { core::result_constants::Known(n) => n, core::result_constants::Values(v) => 99 };
    if (a != 0 || b != 3 || c != 23) { return 1; }
    return 0;
}
"#,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_result_only_constants_reject_conflicting_constraints() {
    for source in [
        "fn keep<const N: usize>(v: [i32; N]) -> [i32; N] { return v; } fn main() -> i32 { let v: [i32; 2] = keep([1, 2, 3]); return 0; }",
        "enum Length<T> { Known(usize), Values(T) } fn square<const N: usize>() -> Length<[[i32; N]; N]> { return Known(N); } fn main() -> i32 { let v: Length<[[i32; 2]; 3]> = square(); return 0; }",
    ] {
        let error =
            common::run_gpu_codegen_with_timeout("conflicting result constant", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_source_to_x86_64_with_gpu_codegen(source),
                )
            })
            .err()
            .expect("contradictory result constants must not emit an ELF");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{error:?}");
        assert!(diagnostic.primary_label.is_some(), "{diagnostic:?}");
    }
}

#[test]
fn generic_result_only_constants_execute_symbolic_forwarding() {
    let stdlib = ReceiverTestStdlib::new();
    let declarations = r#"
pub enum Length<T> { Known(usize), Values(T) }
pub fn length<T, const N: usize>() -> Length<[T; N]> { return Known(N); }
pub fn forward<T, const M: usize>() -> Length<[T; M]> { return length(); }
"#;
    std::fs::write(
        stdlib.0.path().join("core/result_forward.lani"),
        format!("module core::result_forward;\n{declarations}"),
    )
    .expect("constant result forwarding module");
    let source = format!(
        r#"
import core::result_forward;
{declarations}
fn main() -> i32 {{
    let local: Length<[str; 3]> = forward();
    let imported: core::result_forward::Length<[[str; 0]; 2]> = core::result_forward::forward();
    let zero: core::result_forward::Length<[bool; 0]> = core::result_forward::forward();
    let a: usize = match (local) {{ Known(n) => n, Values(v) => 99 }};
    let b: usize = match (imported) {{ core::result_forward::Known(n) => n, core::result_forward::Values(v) => 99 }};
    let c: usize = match (zero) {{ core::result_forward::Known(n) => n, core::result_forward::Values(v) => 99 }};
    if (a != 3 || b != 2 || c != 0) {{ return 1; }}
    return 0;
}}
"#
    );
    execute_with_stdlib(
        "symbolic result constant replay",
        &source,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_result_only_constants_execute_method_environments() {
    let stdlib = ReceiverTestStdlib::new();
    let declarations = r#"
pub enum Length<T> { Known(usize), Values(T) }
pub struct Boxed<T> { value: T }
pub struct Plain { value: i32 }
impl<T> Boxed<T> {
    pub fn length<U, const N: usize>(&self) -> Length<[U; N]> { return Known(N); }
    pub fn forward<V, const M: usize>(&self) -> Length<[V; M]> { return self.length(); }
}
impl Plain {
    pub fn length<const N: usize>() -> Length<[i32; N]> { return Known(N); }
}
"#;
    std::fs::write(
        stdlib.0.path().join("core/result_methods.lani"),
        format!("module core::result_methods;\n{declarations}"),
    )
    .expect("constant result method module");
    let source = format!(
        r#"
import core::result_methods;
import std::io;
{declarations}
fn main() -> i32 {{
    let local: Boxed<bool> = Boxed {{ value: true }};
    let imported: core::result_methods::Boxed<str> = core::result_methods::Boxed {{ value: "receiver λ" }};
    let a: Length<[str; 3]> = local.length();
    let b: Length<[bool; 0]> = local.forward();
    let c: core::result_methods::Length<[[str; 0]; 2]> = imported.forward();
    let d: Length<[i32; 4]> = Plain::length();
    let e: core::result_methods::Length<[i32; 5]> = core::result_methods::Plain::length();
    let na: usize = match (a) {{ Known(n) => n, Values(v) => 99 }};
    let nb: usize = match (b) {{ Known(n) => n, Values(v) => 99 }};
    let nc: usize = match (c) {{ core::result_methods::Known(n) => n, core::result_methods::Values(v) => 99 }};
    let nd: usize = match (d) {{ Known(n) => n, Values(v) => 99 }};
    let ne: usize = match (e) {{ core::result_methods::Known(n) => n, core::result_methods::Values(v) => 99 }};
    if (na != 3 || nb != 0 || nc != 2 || nd != 4 || ne != 5) {{ return 1; }}
    if (!local.value) {{ return 2; }}
    if (std::io::println(imported.value) != 12) {{ return 3; }}
    return 0;
}}
"#
    );
    execute_with_stdlib(
        "method result constant replay",
        &source,
        stdlib.0.path(),
        "receiver λ\n".as_bytes(),
        0,
    );
}

#[test]
fn generic_result_only_constants_preserve_thirty_two_bindings_and_replay() {
    let stdlib = ReceiverTestStdlib::new();
    let parameters = (0..32)
        .map(|i| format!("const N{i}: usize"))
        .collect::<Vec<_>>()
        .join(", ");
    let pattern = (0..32)
        .rev()
        .fold("i32".to_owned(), |inner, i| format!("[{inner}; N{i}]"));
    let dimensions: Vec<usize> = (0..32)
        .map(|i| match i {
            0 => 0,
            4 => 4,
            15 => 15,
            31 => 31,
            _ => 1,
        })
        .collect();
    let concrete = (0..32).rev().fold("i32".to_owned(), |inner, i| {
        format!("[{inner}; {}]", dimensions[i])
    });
    let declarations = format!(
        r#"
pub enum Length<T> {{ Known(usize), Values(T) }}
pub fn length<{parameters}>() -> Length<{pattern}> {{ return Known(N0 + N4 * 10 + N15 * 100 + N31 * 1000); }}
pub fn forward<{parameters}>() -> Length<{pattern}> {{ return length(); }}
"#
    );
    std::fs::write(
        stdlib.0.path().join("core/result_wide.lani"),
        format!("module core::result_wide;\n{declarations}"),
    )
    .expect("wide constant result module");
    let expected =
        dimensions[0] + dimensions[4] * 10 + dimensions[15] * 100 + dimensions[31] * 1000;
    let source = format!(
        r#"
import core::result_wide;
{declarations}
fn main() -> i32 {{
    let local: Length<{concrete}> = forward();
    let imported: core::result_wide::Length<{concrete}> = core::result_wide::forward();
    let a: usize = match (local) {{ Known(n) => n, Values(v) => 99 }};
    let b: usize = match (imported) {{ core::result_wide::Known(n) => n, core::result_wide::Values(v) => 99 }};
    if (a != {expected} || b != {expected}) {{ return 1; }}
    return 0;
}}
"#
    );
    execute_with_stdlib(
        "thirty-two result constants",
        &source,
        stdlib.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_result_only_constants_reject_imported_conflicts() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(
        stdlib.0.path().join("core/result_conflicts.lani"),
        r#"
module core::result_conflicts;
pub enum Length<T> { Known(usize), Values(T) }
pub fn keep<const N: usize>(v: [i32; N]) -> [i32; N] { return v; }
pub fn square<const N: usize>() -> Length<[[i32; N]; N]> { return Known(N); }
"#,
    )
    .expect("constant result conflicts module");
    for body in [
        "let v: [i32; 2] = core::result_conflicts::keep([1, 2, 3]);",
        "let v: core::result_conflicts::Length<[[i32; 2]; 3]> = core::result_conflicts::square();",
    ] {
        let entry = common::TempArtifact::new("result_constant_conflict", "entry", Some("lani"));
        entry.write_str(&format!(
            "import core::result_conflicts; fn main() -> i32 {{ {body} return 0; }}"
        ));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error =
            common::run_gpu_codegen_with_timeout("imported result constant conflict", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
            })
            .err()
            .expect("conflicting imported result constants must not emit an ELF");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{body}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{diagnostic:?}");
    }
}

#[test]
fn generic_nested_result_arguments_execute() {
    execute(
        "nested argument result context",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_result_argument.lani"),
    );
}

#[test]
fn generic_nested_result_fields_execute() {
    execute(
        "nested field result context",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_result_field.lani"),
    );
}

#[test]
fn ordinary_match_call_arguments_execute() {
    execute(
        "ordinary scalar match argument completion",
        include_str!("fixtures/stdlib_foundation/repro_call_match_scalar_schedule.lani"),
    );
}

#[test]
fn generic_match_arguments_preserve_completion_and_effect_order() {
    execute_with_stdout(
        "nested match argument completion and sibling effects",
        include_str!("fixtures/stdlib_foundation/repro_match_argument_effect_order.lani"),
        b"1\n3\n4\n5\n",
    );
}

#[test]
fn generic_void_function_preserves_final_imported_call() {
    execute_with_stdout(
        "void helper final imported call after generic matches",
        include_str!("fixtures/stdlib_foundation/repro_mixed_record_nested_strings_void_show.lani"),
        "keep\na\nc\nγ\n".as_bytes(),
    );
}

#[test]
fn generic_nested_result_monomorphic_fields_preserve_widths_and_copies() {
    execute_with_stdout(
        "monomorphic record concrete generic fields",
        include_str!(
            "fixtures/stdlib_foundation/repro_monomorphic_record_generic_field_layout.lani"
        ),
        "keep\nchanged\nc\nedited\nkeep\na\nc\nγ\n".as_bytes(),
    );
}

#[test]
fn generic_nested_result_array_elements_execute() {
    execute(
        "nested array result context",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_result_array.lani"),
    );
}

#[test]
fn generic_nested_result_match_arms_execute() {
    execute(
        "nested match result context",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_result_match.lani"),
    );
}

fn nested_result_stdlib() -> ReceiverTestStdlib {
    let root = ReceiverTestStdlib::new();
    std::fs::write(
        root.0.path().join("core/nested_result.lani"),
        include_str!("fixtures/stdlib_foundation/repro_nested_result_root/core/nested_result.lani"),
    )
    .expect("nested result module");
    root
}

#[test]
fn generic_nested_result_imported_contexts_and_methods_execute() {
    let root = nested_result_stdlib();
    execute_with_stdlib(
        "imported nested result contexts",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_result_imported.lani"),
        root.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_nested_result_symbolic_contexts_and_call_chains_execute() {
    let root = nested_result_stdlib();
    execute_with_stdlib(
        "symbolic nested result context",
        r#"
import core::nested_result;
enum Length<T> { Known(usize), Values(T) }
struct Boxed<T> { value: T }
fn length<T, const N: usize>() -> Length<[T; N]> { return Known(N); }
fn keep<T>(value: T) -> T { return value; }
fn local<T, const N: usize>() -> Length<[T; N]> {
    let item: Boxed<Length<[T; N]> > = Boxed { value: keep(keep(length())) };
    let values: [[Length<[T; N]>; 2]; 1] = [[length(), keep(length())]];
    return match (true) { true -> item.value, false -> values[0][1] };
}
fn imported<T, const N: usize>() -> core::nested_result::BoundLength<[T; N]> {
    let item: Boxed<BoundLength<[T; N]> > = Boxed {
        value: core::nested_result::keep(core::nested_result::keep(core::nested_result::length()))
    };
    let values: [[BoundLength<[T; N]>; 2]; 1] = [[
        core::nested_result::length(), core::nested_result::keep(core::nested_result::length())
    ]];
    return match (false) { true -> item.value, false -> values[0][1] };
}
fn main() -> i32 {
    let a: Length<[str; 3]> = keep(keep(local()));
    let b: Length<[bool; 0]> = local();
    let c: core::nested_result::BoundLength<[[str; 0]; 2]> = core::nested_result::keep(imported());
    let na: usize = match (a) { Known(n) => n, Values(v) => 99 };
    let nb: usize = match (b) { Known(n) => n, Values(v) => 99 };
    let nc: usize = match (c) { core::nested_result::Known(n) => n, core::nested_result::Values(v) => 99 };
    if (na != 3 || nb != 0 || nc != 2) { return 1; }
    return 0;
}
"#,
        root.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_nested_result_field_contexts_preserve_independent_parameter_domains() {
    let stdlib = ReceiverTestStdlib::new();
    let declarations = r#"
pub enum ScopeLength<T> { Known(usize), Values(T) }
pub struct ScopePair<const UNUSED: usize, V, M> { value: V, marker: M }
pub fn length<T, const N: usize>() -> ScopeLength<[T; N]> { return Known(N); }
pub fn keep<U>(value: U) -> U { return value; }
pub fn wrap<M, T, const N: usize>(marker: M) -> ScopePair<5, ScopeLength<[T; N]>, M> {
    let result: ScopePair<5, ScopeLength<[T; N]>, M> = ScopePair {
        value: keep(keep(length())), marker: marker
    };
    return result;
}
"#;
    std::fs::write(
        stdlib.0.path().join("core/field_scopes.lani"),
        format!("module core::field_scopes;\n{declarations}"),
    )
    .expect("independent receiving scope module");
    for imported in [false, true] {
        let prefix = if imported { "core::field_scopes::" } else { "" };
        let header = if imported {
            "import core::field_scopes;"
        } else {
            declarations
        };
        // The record's V is type slot 0, the caller's T is slot 1, and
        // keep's U is slot 0. Its constant 5 must never replace caller N.
        let source = format!(
            r#"
import std::io;
{header}
fn main() -> i32 {{
    let a: {prefix}ScopePair<5, {prefix}ScopeLength<[str; 3]>, bool> = {prefix}wrap(false);
    let b: {prefix}ScopePair<5, {prefix}ScopeLength<[[bool; 2]; 0]>, str> = {prefix}wrap("scope");
    let c: {prefix}ScopePair<5, {prefix}ScopeLength<[&i32; 2]>, i32> = {prefix}wrap(17);
    let na: usize = match (a.value) {{ {prefix}Known(n) => n, {prefix}Values(v) => 99 }};
    let nb: usize = match (b.value) {{ {prefix}Known(n) => n, {prefix}Values(v) => 99 }};
    let nc: usize = match (c.value) {{ {prefix}Known(n) => n, {prefix}Values(v) => 99 }};
    if (a.marker || c.marker != 17 || na != 3 || nb != 0 || nc != 2) {{ return 1; }}
    std::io::println(b.marker);
    return 0;
}}
"#,
        );
        execute_with_stdlib(
            if imported { "imported receiving scope domains" } else { "local receiving scope domains" },
            &source,
            stdlib.0.path(),
            b"scope\n",
            0,
        );
    }
}

#[test]
fn generic_nested_result_conflicts_and_missing_context_reject() {
    let root = nested_result_stdlib();
    let declarations = "enum Length<T> { Known(usize), Values(T) } fn square<const N: usize>() -> Length<[[i32; N]; N]> { return Known(N); } fn length<T, const N: usize>() -> Length<[T; N]> { return Known(N); }";
    for (label, source) in [
        ("argument", format!("{declarations} fn read(v: Length<[[i32; 2]; 3]>) -> i32 {{ return 0; }} fn main() -> i32 {{ return read(square()); }}")),
        ("field", format!("{declarations} struct Field {{ value: Length<[[i32; 2]; 3]> }} fn main() -> i32 {{ let v: Field = Field {{ value: square() }}; return 0; }}")),
        ("array", format!("{declarations} fn main() -> i32 {{ let v: [Length<[[i32; 2]; 3]>; 1] = [square()]; return 0; }}")),
        ("match", format!("{declarations} fn main() -> i32 {{ let v: Length<[[i32; 2]; 3]> = match (true) {{ true -> square(), false -> square() }}; return 0; }}")),
        ("missing", format!("{declarations} fn main() -> i32 {{ let v = length(); return 0; }}")),
        ("scrutinee", format!("{declarations} fn main() -> i32 {{ let v: usize = match (length()) {{ Known(n) => n, Values(v) => 0 }}; return 0; }}")),
        ("imported argument", "import core::nested_result; fn read(v: core::nested_result::BoundLength<[[i32; 2]; 3]>) -> i32 { return 0; } fn main() -> i32 { return read(core::nested_result::square()); }".into()),
        ("imported field", "import core::nested_result; struct Field { value: core::nested_result::BoundLength<[[i32; 2]; 3]> } fn main() -> i32 { let v: Field = Field { value: core::nested_result::square() }; return 0; }".into()),
        ("imported array", "import core::nested_result; fn main() -> i32 { let v: [BoundLength<[[i32; 2]; 3]>; 1] = [core::nested_result::square()]; return 0; }".into()),
        ("imported match", "import core::nested_result; fn main() -> i32 { let v: core::nested_result::BoundLength<[[i32; 2]; 3]> = match (true) { true -> core::nested_result::square(), false -> core::nested_result::square() }; return 0; }".into()),
        ("known call argument in generic field", "struct Boxed<T> { value: T } fn keep<T>(value: T) -> T { return value; } fn main() -> i32 { let v: Boxed<i32> = Boxed { value: keep(false) }; return 0; }".into()),
        ("imported known call argument in generic field", "import core::nested_result; struct Boxed<T> { value: T } fn main() -> i32 { let v: Boxed<i32> = Boxed { value: core::nested_result::keep(false) }; return 0; }".into()),
    ] {
        let entry = common::TempArtifact::new("nested_result_conflict", label, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = root.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("nested result conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| panic!("{label}: conflicting or missing context emitted an ELF"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
    }
}

#[test]
fn generic_nested_result_contexts_preserve_thirty_two_type_bindings() {
    let root = nested_result_stdlib();
    let parameters = (0..32)
        .map(|slot| format!("T{slot}"))
        .collect::<Vec<_>>()
        .join(", ");
    let shapes = [
        "i32",
        "bool",
        "str",
        "Cell<str>",
        "[str; 2]",
        "[[i32; 0]; 2]",
        "u32",
        "char",
    ];
    let concrete = (0..32)
        .map(|slot| shapes[slot % shapes.len()])
        .collect::<Vec<_>>()
        .join(", ");
    let declarations = format!(
        "pub enum Mine<{parameters}> {{ Empty, Values({parameters}) }} pub fn empty<{parameters}>() -> Mine<{parameters}> {{ return Empty(); }}"
    );
    std::fs::write(
        root.0.path().join("core/nested_wide.lani"),
        format!(
            "module core::nested_wide;\n{}",
            declarations.replace("Mine", "ImportedMine")
        ),
    )
    .expect("wide nested result module");
    let source = format!(
        r#"
import core::nested_wide;
struct Cell<T> {{ value: T }}
{declarations}
fn read(value: Mine<{concrete}>) -> i32 {{ return match (value) {{ Empty => 41, _ => 1 }}; }}
fn read_imported(value: core::nested_wide::ImportedMine<{concrete}>) -> i32 {{ return match (value) {{ core::nested_wide::Empty => 43, _ => 1 }}; }}
fn main() -> i32 {{
    let local: [Mine<{concrete}>; 1] = [empty()];
    let imported: [ImportedMine<{concrete}>; 1] = [core::nested_wide::empty()];
    if (read(local[0]) != 41 || read(empty()) != 41 || read_imported(imported[0]) != 43 || read_imported(core::nested_wide::empty()) != 43) {{ return 1; }}
    return 0;
}}
"#
    );
    execute_with_stdlib(
        "wide nested result environment",
        &source,
        root.0.path(),
        b"",
        0,
    );
}

#[test]
fn ordinary_match_in_condition_header_executes() {
    execute(
        "match condition structural brace owner",
        include_str!("fixtures/stdlib_foundation/repro_match_in_condition_brace_owner.lani"),
    );
}

#[test]
fn generic_nested_condition_headers_preserve_branches_and_loop_effects() {
    execute_with_stdout(
        "generic nested condition ownership and runtime effects",
        include_str!("fixtures/stdlib_foundation/repro_generic_nested_condition_headers.lani"),
        b"1\n2\n3\n4\n5\n6\n",
    );
}

#[test]
fn generic_record_literal_receiving_contexts_execute() {
    for (label, source) in [
        (
            "ordinary argument record context",
            include_str!("fixtures/stdlib_foundation/repro_call_record_literal_context.lani"),
        ),
        (
            "local enum payload record context",
            include_str!(
                "fixtures/stdlib_foundation/repro_local_option_record_literal_context.lani"
            ),
        ),
        (
            "imported enum payload record context",
            include_str!(
                "fixtures/stdlib_foundation/repro_generic_option_record_literal_context.lani"
            ),
        ),
    ] {
        execute(label, source);
    }
}

#[test]
fn explicit_record_constructor_composed_types_execute() {
    let root = record_context_stdlib();
    execute_with_stdlib(
        "explicit record constructors across type compositions",
        include_str!("fixtures/stdlib_foundation/repro_explicit_record_constructor_types.lani"),
        root.0.path(),
        "Ω\nΩ\nλ\nΩ\n".as_bytes(),
        0,
    );
}

#[test]
fn explicit_record_constructor_actual_arguments_reject_context_conflicts() {
    let root = record_context_stdlib();
    for (label, source) in [
        (
            "call",
            "struct Cell<T> { value: T } fn read(v: Cell<u32>) -> i32 { return 0; } fn main() -> i32 { return read(Cell<i32> { value: 1 }); }",
        ),
        (
            "binding",
            "struct Cell<T> { value: T } fn main() -> i32 { let v: Cell<u32> = Cell<i32> { value: 1 }; return 0; }",
        ),
        (
            "return",
            "struct Cell<T> { value: T } fn make() -> Cell<u32> { return Cell<i32> { value: 1 }; } fn main() -> i32 { return 0; }",
        ),
        (
            "nested",
            "struct Cell<T> { value: T } struct Envelope<T> { child: Cell<T> } fn main() -> i32 { let v: Envelope<u32> = Envelope<u32> { child: Cell<i32> { value: 1 } }; return 0; }",
        ),
        (
            "explicit field",
            "struct Cell<T> { value: T } fn main() -> i32 { let v = Cell<bool> { value: 1 }; return 0; }",
        ),
        (
            "imported nested",
            "import core::record_context; fn main() -> i32 { let v: core::record_context::ImportedEnvelope<u32> = core::record_context::ImportedEnvelope<u32> { child: core::record_context::ImportedCell<i32> { value: 1 } }; return 0; }",
        ),
    ] {
        let entry = common::TempArtifact::new("explicit_record_conflict", label, Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = root.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("explicit record conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| panic!("{label}: conflicting explicit constructor emitted an ELF"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic.primary_label.is_some(),
            "{label}: {diagnostic:?}"
        );
    }
}

#[test]
fn generic_record_literal_receiving_contexts_compose_values_and_scopes() {
    execute_with_stdout(
        "record receiving contexts across composed values and generic bodies",
        include_str!("fixtures/stdlib_foundation/repro_record_context_compositions.lani"),
        "left\nΩ\nλ\n".as_bytes(),
    );
}

fn record_context_stdlib() -> ReceiverTestStdlib {
    let root = ReceiverTestStdlib::new();
    for (name, source) in [
        (
            "record_context",
            include_str!("fixtures/stdlib_foundation/repro_record_context_imported_module.lani"),
        ),
        ("option", include_str!("../stdlib/core/option.lani")),
        (
            "result_bool",
            include_str!("../stdlib/core/result_bool.lani"),
        ),
    ] {
        std::fs::write(root.0.path().join(format!("core/{name}.lani")), source)
            .expect("record context module");
    }
    root
}

#[test]
fn generic_record_literal_receiving_contexts_preserve_imported_identity() {
    let root = record_context_stdlib();
    execute_with_stdlib(
        "imported record receiving contexts and payloads",
        include_str!("fixtures/stdlib_foundation/repro_record_context_imported.lani"),
        root.0.path(),
        "Ω\n".as_bytes(),
        0,
    );
}

#[test]
fn generic_record_literal_receiving_contexts_preserve_thirty_two_fields() {
    record_context_thirty_two_fields(false);
}

#[test]
fn explicit_record_constructor_thirty_two_parameters_execute() {
    record_context_thirty_two_fields(true);
}

fn record_context_thirty_two_fields(explicit: bool) {
    let params = (0..32)
        .map(|slot| format!("T{slot}"))
        .collect::<Vec<_>>()
        .join(", ");
    let shapes = [
        "bool",
        "u32",
        "str",
        "Cell<i32>",
        "[i32; 2]",
        "[[str; 0]; 2]",
        "&Item",
        "[i32]",
    ];
    let values = [
        "false",
        "4294967295",
        "\"Ω\"",
        "Cell { value: 7 }",
        "[40, 2]",
        "[[], []]",
        "item.borrow()",
        "view",
    ];
    let concrete = (0..32)
        .map(|slot| shapes[slot % 8])
        .collect::<Vec<_>>()
        .join(", ");
    let fields = (0..32)
        .map(|slot| format!("f{slot}: T{slot}"))
        .collect::<Vec<_>>()
        .join(", ");
    let initializers = (0..32)
        .map(|slot| format!("f{slot}: {}", values[slot % 8]))
        .collect::<Vec<_>>()
        .join(", ");
    let checks = (0..32)
        .map(|slot| {
            let field = format!("value.f{slot}");
            let condition = match slot % 8 {
                0 => field,
                1 => format!("{field} != 4294967295"),
                2 => format!("std::io::println({field}) != 3"),
                3 => format!("{field}.value != 7"),
                4 => format!("{field}[0] != 40 || {field}[1] != 2"),
                5 => format!("length({field}) != 2"),
                6 => format!("{field}.value != 9"),
                _ => format!("{field}[0] != 1 || {field}[1] != 2"),
            };
            format!("if ({condition}) {{ return {}; }}", slot + 1)
        })
        .collect::<Vec<_>>()
        .join("\n");
    let source = format!(
        r#"
import std::io;
struct Cell<T> {{ value: T }}
struct Item {{ value: i32 }}
impl Item {{ fn borrow(&self) -> &Item {{ return self; }} }}
struct Mine<{params}> {{ {fields} }}
fn length<T, const N: usize>(value: [T; N]) -> usize {{ return N; }}
fn view(value: [i32]) -> [i32] {{ return value; }}
fn read(value: Mine<{concrete}>) -> i32 {{
    {checks}
    value.f7[1] = 12;
    if (value.f31[1] != 12) {{ return 40; }}
    return 0;
}}
fn main() -> i32 {{
    let item: Item = Item {{ value: 9 }};
    let values: [i32; 3] = [1, 2, 3];
    let view: [i32] = view(values);
    let status: i32 = read({constructor} {{ {initializers} }});
    if (status != 0) {{ return status; }}
    if (values[1] != 12) {{ return 41; }}
    return 0;
}}
"#,
        constructor = if explicit {
            format!("Mine<{concrete}>")
        } else {
            "Mine".into()
        },
    );
    execute_with_stdout(
        if explicit {
            "thirty-two explicit record parameters"
        } else {
            "thirty-two record context fields"
        },
        &source,
        "Ω\nΩ\nΩ\nΩ\n".as_bytes(),
    );
}

#[test]
fn generic_record_literal_receiving_contexts_reject_conflicting_fields() {
    let root = record_context_stdlib();
    for (label, source) in [
        (
            "scalar field",
            "struct Cell<T> { value: T } fn read(v: Cell<bool>) -> i32 { return 0; } fn main() -> i32 { return read(Cell { value: 1 }); }",
        ),
        (
            "known value field",
            "struct Cell<T> { value: T } fn read(v: Cell<bool>) -> i32 { return 0; } fn main() -> i32 { let number: i32 = 1; return read(Cell { value: number }); }",
        ),
        (
            "nominal field",
            "struct Cell<T> { value: T } struct Other<T> { value: T } fn read(v: Cell<bool>) -> i32 { return 0; } fn main() -> i32 { return read(Other { value: true }); }",
        ),
        (
            "array length",
            "struct Cell<T> { value: T } fn read(v: Cell<[i32; 2]>) -> i32 { return 0; } fn main() -> i32 { return read(Cell { value: [1, 2, 3] }); }",
        ),
        (
            "nested nominal",
            "struct Cell<T> { value: T } struct Other<T> { value: T } fn read(v: Cell<Cell<bool>>) -> i32 { return 0; } fn main() -> i32 { return read(Cell { value: Other { value: true } }); }",
        ),
        (
            "imported scalar",
            "import core::record_context; fn main() -> i32 { if (core::record_context::flag(core::record_context::ImportedCell { value: 1 })) { return 0; } return 1; }",
        ),
        (
            "imported nested",
            "import core::record_context; struct Other<T> { value: T } fn main() -> i32 { let text: str = core::record_context::envelope(core::record_context::ImportedEnvelope { child: Other { value: true } }); return 0; }",
        ),
    ] {
        let entry = common::TempArtifact::new("record_context_conflict", label, Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = root.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout("record receiving conflict", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .err()
        .unwrap_or_else(|| panic!("{label}: conflicting field emitted an ELF"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic.primary_label.is_some(),
            "{label}: {diagnostic:?}"
        );
    }
}

#[test]
fn imported_required_bindings_reject_unused_and_late_slots_before_codegen() {
    let stdlib = ReceiverTestStdlib::new();
    let types = (0..32)
        .map(|i| format!("T{i}"))
        .collect::<Vec<_>>()
        .join(", ");
    let constants = (0..32)
        .map(|i| format!("const N{i}: usize"))
        .collect::<Vec<_>>()
        .join(", ");
    let type_parameters = (0..31)
        .map(|i| format!("v{i}: T{i}"))
        .collect::<Vec<_>>()
        .join(", ");
    let constant_parameters = (0..31)
        .map(|i| format!("v{i}: [i32; N{i}]"))
        .collect::<Vec<_>>()
        .join(", ");
    std::fs::write(stdlib.0.path().join("core/requirements.lani"), format!(r#"
module core::requirements;
pub fn missing_type<T>() -> i32 {{ return 7; }}
pub fn unused_constant<const N: usize>() -> i32 {{ return 7; }}
pub fn used_constant<const N: usize>() -> usize {{ return N; }}
pub fn middle_constant<const N: usize, const M: usize, const K: usize>(a: [i32; N], b: [i32; K]) -> i32 {{ return 7; }}
pub fn last_type<{types}>({type_parameters}) -> i32 {{ return 7; }}
pub fn last_constant<{constants}>({constant_parameters}) -> i32 {{ return 7; }}
pub struct Plain {{ value: i32 }}
impl Plain {{
    pub fn make<T>() -> i32 {{ return 7; }}
    pub fn length<const N: usize>() -> usize {{ return N; }}
}}
"#)).expect("declared imported requirements");
    let type_arguments = vec!["1"; 31].join(", ");
    let constant_arguments = vec!["[1]"; 31].join(", ");
    for (label, call) in [
        (
            "unused imported type",
            "core::requirements::missing_type()".to_string(),
        ),
        (
            "unused imported constant",
            "core::requirements::unused_constant()".to_string(),
        ),
        (
            "used imported constant",
            "core::requirements::used_constant()".to_string(),
        ),
        (
            "missing middle imported constant",
            "core::requirements::middle_constant([1], [2, 3])".to_string(),
        ),
        (
            "missing imported type slot 31",
            format!("core::requirements::last_type({type_arguments})"),
        ),
        (
            "missing imported constant slot 31",
            format!("core::requirements::last_constant({constant_arguments})"),
        ),
        (
            "associated imported type",
            "core::requirements::Plain::make()".to_string(),
        ),
        (
            "associated imported constant",
            "core::requirements::Plain::length()".to_string(),
        ),
    ] {
        let entry = common::TempArtifact::new("imported_required_slot", label, Some("lani"));
        entry.write_str(&format!("module app::main; import core::requirements; fn main() -> i32 {{ let value = {call}; return 0; }}"));
        let path = entry.path().to_path_buf();
        let root = stdlib.0.path().to_path_buf();
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
        })
        .err()
        .unwrap_or_else(|| panic!("{label}: unbound declared slots emitted an executable"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {error:?}");
        assert!(
            diagnostic.primary_label.is_some(),
            "{label}: {diagnostic:?}"
        );
    }
}

#[test]
fn explicit_callable_arguments_validate_own_headers() {
    for (label, source, message) in [
        ("arguments on a nongeneric function", "fn keep(v: i32) -> i32 { return v; } fn main() -> i32 { return keep<i32>(42); }", "argument count does not match"),
        ("too few own arguments", "fn keep<T, U>(v: T) -> T { return v; } fn main() -> i32 { return keep<i32>(42); }", "argument count does not match"),
        ("too many own arguments", "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { return keep<i32, bool>(42); }", "argument count does not match"),
        ("type supplied for constant slot", "fn stamp<const N: usize>() -> i32 { return 42; } fn main() -> i32 { return stamp<i32>(); }", "does not match the declared parameter kind"),
        ("receiver slots are not own method slots", "struct Box<T> { v: T } impl<T> Box<T> { fn make<U>(v: U) -> U { return v; } } fn main() -> i32 { return Box<bool>::make<i32, bool>(42); }", "argument count does not match"),
    ] {
        let error = common::run_gpu_codegen_with_timeout("explicit callable own header", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(source))
        }).err().unwrap_or_else(|| panic!("{label}: invalid explicit arguments emitted an ELF"));
        let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
            panic!("{label}: expected a source diagnostic: {error:?}");
        };
        assert_eq!(diagnostic.code, "LNC0027", "{label}: {diagnostic:?}");
        assert!(format!("{diagnostic:?}").contains(message), "{label}: {diagnostic:?}");
    }
}

#[test]
fn explicit_callable_arguments_execute_scalar_and_unused_bindings() {
    execute_with_status("explicit scalar bindings", r#"
fn keep<T>(v: T) -> T { return v; }
fn stamp<T>() -> i32 { return 42; }
fn main() -> i32 {
    let number = keep<i32>(42);
    let flag = keep<bool>(false);
    let unsigned = keep<u32>(7);
    if (flag || unsigned != 7) { return 1; }
    if (stamp<[bool; 0]>() != 42) { return 2; }
    return number;
}
"#, b"", 42);
}

#[test]
fn explicit_callable_arguments_execute_compound_and_symbolic_bindings() {
    execute_with_status("explicit compound and caller symbolic bindings", r#"
struct Cell<T> { value: T }
fn keep<T>(v: T) -> T { return v; }
fn relay<T>(v: T) -> T { return keep<T>(v); }
fn empty<T>() -> [T; 0] { return []; }
fn main() -> i32 {
    let value: Cell<[i32; 2]> = Cell { value: [40, 2] };
    let result = keep<Cell<[i32; 2]>>(value);
    let copy = relay<Cell<[i32; 2]>>(result);
    let zero: [[bool; 0]; 0] = empty<[bool; 0]>();
    return copy.value[0] + copy.value[1];
}
"#, b"", 42);
}

#[test]
fn explicit_callable_arguments_execute_independent_receiver_and_method_headers() {
    execute_with_status("independent receiver method headers", include_str!(
        "fixtures/stdlib_foundation/repro_explicit_method_binding.lani"), b"", 42);
    execute_with_status("unused own method type through qualified identity", r#"
struct Box<T> { value: T }
impl<T> Box<T> { fn stamp<U>() -> i32 { return 42; } }
fn main() -> i32 { return Box<bool>::stamp<[i32; 2]>(); }
"#, b"", 42);
}

#[test]
fn explicit_dotted_arguments_execute_compounds_constants_and_symbolic_scopes() {
    execute("explicit dotted method reproduction", include_str!(
        "fixtures/stdlib_foundation/repro_explicit_dotted_method_binding.lani"));
    execute(r#"explicit dotted method compositions"#, r#"
struct Boxed<T> { value: T }
struct Pair<A, B> { first: A, second: B }
impl<T> Boxed<T> {
    fn pair<U, const N: usize>(&self, value: [U; N]) -> Pair<T, [U; N]> {
        return Pair { first: self.value, second: value };
    }
    fn keep<U>(self, value: U) -> U { return value; }
    fn stamp<U>(&self) -> i32 { return 17; }
}
fn relay<T, U, const N: usize>(receiver: Boxed<T>, value: [U; N]) -> Pair<T, [U; N]> {
    return receiver.pair<U, N>(value);
}
fn main() -> i32 {
    let receiver: Boxed<bool> = Boxed { value: false };
    let values: [[i32; 2]; 2] = [[5, 8], [-3, 9]];
    let result = receiver.pair<[i32; 2], 2>(values);
    let empty = receiver.pair<[bool; 2], 0>([]);
    let replay = relay(receiver, values);
    let chained = receiver.keep<Boxed<i32>>(Boxed { value: 23 }).keep<[bool; 2]>([false, true]);
    let chained_stamp = receiver.keep<Boxed<i32>>(Boxed { value: 23 }).stamp<[bool; 0]>();
    values[0] = [99, 100];
    if (result.first || result.second[0][0] != 5 || result.second[1][1] != 9) { return 1; }
    if (empty.first || replay.second[0][1] != 8 || replay.second[1][0] != -3) { return 2; }
    if (chained[0] || !chained[1] || receiver.stamp<[str; 0]>() != 17 || chained_stamp != 17) { return 3; }
    return 0;
}
"#);
}

#[test]
fn explicit_dotted_arguments_execute_imported_method_headers() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/dotted.lani"), r#"
module core::dotted;
pub struct Boxed<T> { value: T }
pub impl<T> Boxed<T> {
    pub fn keep<U>(&self, value: U) -> U { return value; }
    pub fn copy<U, const N: usize>(&self, value: [U; N]) -> [U; N] { return value; }
    pub fn stamp<U>(&self) -> i32 { return 42; }
}
"#).unwrap();
    execute_with_stdlib("imported explicit dotted method headers", r#"
import core::dotted;
import std::io;
fn relay<T, U>(receiver: core::dotted::Boxed<T>, value: U) -> U { return receiver.keep<U>(value); }
fn main() -> i32 {
    let receiver: core::dotted::Boxed<bool> = core::dotted::Boxed { value: false };
    let words: [str; 2] = ["first", "second"];
    let copy = receiver.copy<str, 2>(words);
    words[0] = "changed";
    std::io::println(relay(receiver, copy[0]));
    std::io::println(receiver.keep<str>(copy[1]));
    let chained = receiver.keep<core::dotted::Boxed<i32>>(core::dotted::Boxed { value: 23 });
    if (chained.keep<[bool; 2]>([false, true])[0]) { return 1; }
    return receiver.keep<core::dotted::Boxed<i32>>(core::dotted::Boxed { value: 23 }).stamp<[[bool; 0]; 0]>();
}
"#, stdlib.0.path(), b"first\nsecond\n", 42);
}

#[test]
fn explicit_dotted_arguments_reject_conflicts_and_wrong_headers() {
    for (label, call, code) in [
        ("known boolean conflicts with explicit integer", "value.keep<i32>(false)", "LNC0006"),
        ("receiver type is not an extra own method argument", "value.keep<bool, i32>(42)", "LNC0027"),
        ("type cannot bind a method constant", "value.length<i32>()", "LNC0027"),
        ("late method binding preserves explicit conflict", "value.keep<Boxed<i32>>(Boxed { value: 3 }).keep<i32>(false)", "LNC0006"),
    ] {
        let source = format!(r#"
struct Boxed<T> {{ value: T }}
impl<T> Boxed<T> {{
    fn keep<U>(self, value: U) -> U {{ return value; }}
    fn length<const N: usize>(self) -> usize {{ return N; }}
}}
fn main() -> i32 {{ let value: Boxed<bool> = Boxed {{ value: false }}; let wrong = {call}; return 0; }}
"#);
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        }).err().unwrap_or_else(|| panic!("{label}: invalid method application emitted an ELF"));
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, code, "{label}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
    }
}

#[test]
fn implicit_method_receivers_preserve_argument_constraints() {
    for receiver in ["self", "&self"] {
        for imported in [false, true] {
            let stdlib = ReceiverTestStdlib::new();
            let definitions = format!(r#"
pub struct Boxed<T> {{ value: T }}
pub impl<T> Boxed<T> {{
    pub fn integer({receiver}, value: i32) -> i32 {{ return value; }}
    pub fn pair({receiver}, value: [i32; 2]) -> [i32; 2] {{ return value; }}
    pub fn same<U>({receiver}, left: U, right: U) -> U {{ return left; }}
}}
"#);
            let prelude = if imported {
                std::fs::write(stdlib.0.path().join("core/method_rows.lani"),
                    format!("module core::method_rows;\n{definitions}")).unwrap();
                "import core::method_rows;".to_owned()
            } else { definitions };
            let main = |body: &str| format!("{prelude}\nfn main() -> i32 {{ let value: Boxed<bool> = Boxed {{ value: false }}; {body} }}");
            let label = format!("implicit {receiver} parameter rows imported={imported}");
            execute_with_stdlib(&label, &main("let values = value.pair([40, 2]); if (value.same(false, true)) { return 1; } return value.integer(values[0] + values[1]);"),
                stdlib.0.path(), b"", 42);
            for call in ["value.integer(false)", "value.pair([false, true])", "value.same(false, 42)"] {
                let entry = common::TempArtifact::new("method_parameter_rows", "invalid", Some("lani"));
                entry.write_str(&main(&format!("let wrong = {call}; return 0;")));
                let path = entry.path().to_path_buf();
                let root = stdlib.0.path().to_path_buf();
                let error = common::run_gpu_codegen_with_timeout(&label, move || {
                    pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
                }).err().unwrap_or_else(|| panic!("{label}: {call} emitted an ELF"));
                let diagnostic = error.to_public_diagnostic();
                assert_eq!(diagnostic.code, "LNC0006", "{label}: {call}: {error:?}");
                assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
            }
        }
    }
}

#[test]
fn explicit_callable_arguments_execute_32_ordered_unused_slots() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let arguments = (0..32).map(|i| if i % 2 == 0 { "[i32; 0]" } else { "bool" }).collect::<Vec<_>>().join(", ");
    let source = format!("fn stamp<{parameters}>() -> i32 {{ return 42; }} fn main() -> i32 {{ return stamp<{arguments}>(); }}");
    execute_with_status("32 explicit own type slots", &source, b"", 42);
}

#[test]
fn explicit_callable_arguments_execute_imported_bindings() {
    let stdlib = ReceiverTestStdlib::new();
    execute_with_stdlib("imported explicit bindings", r#"
import core::relay;
fn main() -> i32 {
    let values: [i32; 2] = [40, 2];
    let result = core::relay::keep<[i32; 2]>(values);
    if (core::relay::keep<bool>(false)) { return 1; }
    return result[0] + result[1];
}
"#, stdlib.0.path(), b"", 42);
}

#[test]
fn explicit_callable_arguments_reject_value_and_result_conflicts() {
    for (label, source) in [
        ("known bool conflicts with i32", include_str!("fixtures/stdlib_foundation/repro_explicit_callable_binding.lani")),
        ("result annotation cannot rewrite explicit bool", "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { let value: i32 = keep<bool>(false); return value; }"),
        ("associated result cannot rewrite own type", "struct Box<T> { v: T } impl<T> Box<T> { fn make<U>(v: U) -> U { return v; } } fn main() -> i32 { let value: bool = Box<bool>::make<i32>(42); return 42; }"),
        ("explicit array element conflict", "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { let value: [bool; 2] = [false, true]; let wrong = keep<[i32; 2]>(value); return 42; }"),
    ] {
        let error = common::run_gpu_codegen_with_timeout("explicit binding conflict", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(source))
        }).err().unwrap_or_else(|| panic!("{label}: conflicting explicit binding emitted an ELF"));
        let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
            panic!("{label}: expected a source language diagnostic: {error:?}");
        };
        assert_eq!(diagnostic.code, "LNC0006", "{label}: must reject the conflicting type: {diagnostic:?}");
    }
}

#[test]
fn explicit_callable_arguments_execute_string_reference_and_slice_forms() {
    execute_with_status("explicit reference and slice aliases", r#"
import std::io;
fn keep<T>(v: T) -> T { return v; }
fn view(v: [str]) -> [str] { return v; }
struct Item { value: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn main() -> i32 {
    let item: Item = Item { value: 40 };
    let borrowed: &Item = keep<&Item>(item.borrow());
    item.value = 42;
    let words: [str; 2] = ["before", "tail"];
    let slice: [str] = view(words);
    let shared = keep<[str]>(slice);
    shared[0] = "after";
    std::io::println(keep<str>(words[0]));
    std::io::println(shared[1]);
    return borrowed.value;
}
"#, b"after\ntail\n", 42);
}

#[test]
fn explicit_callable_arguments_execute_imported_own_method_headers() {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/explicit.lani"), r#"
module core::explicit;
pub struct Box<T> { value: T }
pub impl<T> Box<T> {
    pub fn make<U>(v: U) -> U { return v; }
    pub fn stamp<U>() -> i32 { return 42; }
}
"#).unwrap();
    execute_with_stdlib("imported independent explicit method headers", r#"
import core::explicit;
fn main() -> i32 {
    let values: [i32; 2] = [40, 2];
    let result = core::explicit::Box<bool>::make<[i32; 2]>(values);
    if (core::explicit::Box<str>::stamp<[[bool; 0]; 0]>() != 42) { return 1; }
    return result[0] + result[1];
}
"#, stdlib.0.path(), b"", 42);
    execute_with_stdlib("inferred imported associated receiver identity", r#"
import core::explicit;
fn main() -> i32 {
    let values: [i32; 2] = [40, 2];
    let result = core::explicit::Box<bool>::make(values);
    return result[0] + result[1];
}
"#, stdlib.0.path(), b"", 42);
}

#[test]
fn explicit_callable_arguments_execute_32_used_structural_slots() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let fields = (0..32).map(|i| format!("f{i}: T{i}")).collect::<Vec<_>>().join(", ");
    let types = (0..32).map(|i| match i % 3 { 0 => "i32", 1 => "bool", _ => "[i32; 2]" }).collect::<Vec<_>>().join(", ");
    let values = (0..32).map(|i| match i % 3 {
        0 => format!("f{i}: {}", 100 + i),
        1 => format!("f{i}: true"),
        _ => format!("f{i}: [{}, {}]", 100 + i, 200 + i),
    }).collect::<Vec<_>>().join(", ");
    let checks = (0..32).map(|i| match i % 3 {
        0 => format!("if (copy.f{i} != {}) {{ return 1; }}", 100 + i),
        1 => format!("if (!copy.f{i}) {{ return 2; }}"),
        _ => format!("if (copy.f{i}[0] != {} || copy.f{i}[1] != {}) {{ return 3; }}", 100 + i, 200 + i),
    }).collect::<Vec<_>>().join("\n");
    for imported in [false, true] {
        let stdlib = ReceiverTestStdlib::new();
        let declarations = format!("pub struct Mine<{parameters}> {{ {fields} }} pub fn keep<{parameters}>(v: Mine<{parameters}>) -> Mine<{parameters}> {{ return v; }}");
        let (import, prefix, local) = if imported {
            std::fs::write(stdlib.0.path().join("core/explicit32.lani"), format!("module core::explicit32; {declarations}")).unwrap();
            ("import core::explicit32;", "core::explicit32::", "".to_string())
        } else { ("", "", declarations) };
        let source = format!("{import} {local} fn main() -> i32 {{ let original: {prefix}Mine<{types}> = {prefix}Mine<{types}> {{ {values} }}; let copy = {prefix}keep<{types}>(original); {checks} copy.f0 = -1; copy.f2[1] = -2; if (original.f0 != 100 || original.f2[1] != 202) {{ return 4; }} return 42; }}");
        execute_with_stdlib(&format!("32 explicit used structural slots imported={imported}"), &source, stdlib.0.path(), b"", 42);
    }
}


#[test]
fn explicit_constant_arguments_execute_literals_and_zero() {
    execute_with_status("explicit constant scalar results", r#"
fn length<const N: usize>() -> usize { return N; }
fn stamp<T, const N: usize>() -> usize { return N; }
fn empty<T, const N: usize>() -> [T; 0] { return []; }
fn main() -> i32 {
    if (length<0>() != 0 || length<3>() != 3) { return 1; }
    if (length<2147483648>() / 2 != 1073741824) { return 3; }
    if (stamp<[[bool; 0]; 0], 42>() != 42) { return 2; }
    let zero: [str; 0] = empty<str, 0>();
    return 42;
}
"#, b"", 42);
}

#[test]
fn explicit_constant_arguments_execute_mixed_types_and_caller_parameters() {
    execute_with_status("mixed explicit constant and scoped caller bindings", r#"
fn keep<T, const N: usize>(v: [T; N]) -> [T; N] { return v; }
fn relay<T, const N: usize>(v: [T; N]) -> [T; N] { return keep<T, N>(v); }
fn main() -> i32 {
    let original: [[i32; 2]; 3] = [[40, 2], [3, 4], [5, 6]];
    let copy = keep<[i32; 2], 3>(original);
    let forwarded = relay<[i32; 2], 3>(copy);
    copy[0][0] = 99;
    if (original[0][0] != 40 || forwarded[0][0] != 40) { return 1; }
    return forwarded[0][0] + forwarded[0][1];
}
"#, b"", 42);
}

fn explicit_constant_stdlib() -> ReceiverTestStdlib {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/explicit_constants.lani"), r#"
module core::explicit_constants;
pub fn length<const N: usize>() -> usize { return N; }
pub fn scalar_relay<const N: usize>() -> usize { return length<N>(); }
pub fn keep<T, const N: usize>(v: [T; N]) -> [T; N] { return v; }
pub fn relay<T, const N: usize>(v: [T; N]) -> [T; N] { return keep<T, N>(v); }
pub struct Box<T> { value: T }
pub impl<T, const N: usize> Box<[T; N]> {
    pub fn width<U, const M: usize>(value: [U; M]) -> usize { return N * 10 + M; }
}
"#).unwrap();
    stdlib
}

#[test]
fn explicit_constant_arguments_execute_imported_bindings() {
    let stdlib = explicit_constant_stdlib();
    execute_with_stdlib("imported explicit constants and symbolic forwarding", r#"
import core::explicit_constants;
fn main() -> i32 {
    let original: [i32; 2] = [40, 2];
    let copy = core::explicit_constants::keep<i32, 2>(original);
    let forwarded = core::explicit_constants::relay<i32, 2>(copy);
    copy[1] = 99;
    if (original[1] != 2 || forwarded[1] != 2) { return 1; }
    if (core::explicit_constants::length<0>() != 0) { return 2; }
    return forwarded[0] + forwarded[1];
}
"#, stdlib.0.path(), b"", 42);
}

#[test]
fn explicit_constant_arguments_execute_independent_method_domains() {
    execute_with_status("local explicit constants alongside receiver constants", r#"
struct Box<T> { value: T }
impl<T, const N: usize> Box<[T; N]> {
    fn width<U, const M: usize>(value: [U; M]) -> usize { return N * 10 + M; }
}
fn main() -> i32 {
    let values: [i32; 3] = [40, 2, 0];
    if (Box<[bool; 2]>::width<i32, 3>(values) != 23) { return 1; }
    return 42;
}
"#, b"", 42);
    let stdlib = explicit_constant_stdlib();
    execute_with_stdlib("imported explicit constants alongside receiver constants", r#"
import core::explicit_constants;
fn main() -> i32 {
    let values: [i32; 3] = [40, 2, 0];
    if (core::explicit_constants::Box<[bool; 2]>::width<i32, 3>(values) != 23) { return 1; }
    return 42;
}
"#, stdlib.0.path(), b"", 42);
}

#[test]
fn explicit_constant_arguments_execute_both_thirty_two_slot_domains() {
    let header = (0..32).map(|i| format!("T{i}, const C{i}: usize")).collect::<Vec<_>>().join(", ");
    let arguments = (0..32).map(|i| format!("{}, {i}", if i % 2 == 0 { "[[i32; 0]; 0]" } else { "bool" })).collect::<Vec<_>>().join(", ");
    let sum = (0..32).map(|i| format!("C{i}")).collect::<Vec<_>>().join(" + ");
    let declaration = format!("pub fn measure<{header}>() -> usize {{ return {sum}; }}");
    for imported in [false, true] {
        let stdlib = explicit_constant_stdlib();
        let (import, prefix, local) = if imported {
            std::fs::write(stdlib.0.path().join("core/constant32.lani"), format!("module core::constant32; {declaration}")).unwrap();
            ("import core::constant32;", "core::constant32::", "".to_string())
        } else { ("", "", declaration.clone()) };
        let source = format!("{import} {local} fn main() -> i32 {{ if ({prefix}measure<{arguments}>() != 496) {{ return 1; }} return 42; }}");
        execute_with_stdlib(&format!("32 type and constant domains imported={imported}"), &source, stdlib.0.path(), b"", 42);
    }
}

#[test]
fn explicit_constant_arguments_reject_kind_and_arity_errors() {
    for (label, source) in [
        ("constant supplied for type", "fn keep<T>(v: T) -> T { return v; } fn main() -> i32 { return keep<3>(42); }"),
        ("missing interleaved constant", "fn keep<T, const N: usize>(v: T) -> T { return v; } fn main() -> i32 { return keep<i32>(42); }"),
        ("runtime value is not constant parameter", "fn length<const N: usize>() -> usize { return N; } fn main() -> i32 { let count = 3; let size = length<count>(); return 42; }"),
        ("reserved invalid constant payload", "fn length<const N: usize>() -> usize { return N; } fn main() -> i32 { let size = length<4294967295>(); return 42; }"),
    ] {
        let error = common::run_gpu_codegen_with_timeout("invalid explicit constant header", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(source))
        }).err().unwrap_or_else(|| panic!("{label}: invalid binding emitted an ELF"));
        let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
            panic!("{label}: expected a language diagnostic: {error:?}");
        };
        assert_eq!(diagnostic.code, "LNC0027", "{label}: {diagnostic:?}");
        assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
    }
}

#[test]
fn explicit_constant_arguments_reject_value_and_result_conflicts() {
    for (label, source) in [
        ("known array length conflicts", "fn keep<T, const N: usize>(v: [T; N]) -> [T; N] { return v; } fn main() -> i32 { let values: [i32; 3] = [1, 2, 3]; let wrong = keep<i32, 2>(values); return 42; }"),
        ("result cannot rewrite explicit length", "fn keep<T, const N: usize>(v: [T; N]) -> [T; N] { return v; } fn main() -> i32 { let values: [i32; 3] = [1, 2, 3]; let wrong: [i32; 2] = keep<i32, 3>(values); return 42; }"),
    ] {
        let error = common::run_gpu_codegen_with_timeout("conflicting explicit constant", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(source))
        }).err().unwrap_or_else(|| panic!("{label}: conflicting binding emitted an ELF"));
        let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
            panic!("{label}: expected a language diagnostic: {error:?}");
        };
        assert_eq!(diagnostic.code, "LNC0006", "{label}: {diagnostic:?}");
        assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
    }
}


#[test]
fn explicit_constant_arguments_reject_noninteger_parameter_types() {
    for annotation in ["bool", "f32", "str", "[i32; 2]"] {
        let source = format!("fn stamp<const N: {annotation}>() -> i32 {{ return 42; }} fn main() -> i32 {{ return stamp<1>(); }}");
        let error = common::run_gpu_codegen_with_timeout("noninteger explicit constant parameter", move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        }).err().unwrap_or_else(|| panic!("{annotation}: integer bits bound to a noninteger parameter"));
        let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
            panic!("{annotation}: expected a language diagnostic: {error:?}");
        };
        assert_eq!(diagnostic.code, "LNC0006", "{annotation}: {diagnostic:?}");
        assert!(diagnostic.primary_label.is_some(), "{annotation}: {diagnostic:?}");
    }
    let stdlib = explicit_constant_stdlib();
    std::fs::write(stdlib.0.path().join("core/noninteger_constant.lani"), "module core::noninteger_constant; pub fn stamp<const N: bool>() -> i32 { return 42; }").unwrap();
    let entry = common::TempArtifact::new("explicit_noninteger_constant", "entry", Some("lani"));
    std::fs::write(entry.path(), "import core::noninteger_constant; fn main() -> i32 { return core::noninteger_constant::stamp<1>(); }").unwrap();
    let entry_path = entry.path().to_path_buf();
    let root = stdlib.0.path().to_path_buf();
    let error = common::run_gpu_codegen_with_timeout("imported noninteger explicit constant", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry_path, &root))
    }).err().expect("source-backed imports must reject noninteger constant declarations");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn explicit_constant_arguments_do_not_make_constant_names_into_types() {
    let source = "fn wrong<const N: usize>(value: N) -> i32 { return 42; } fn main() -> i32 { return wrong<3>(0); }";
    let error = common::run_gpu_codegen_with_timeout("constant name is not a type annotation", move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
        pollster::block_on(compiler.compile_source_to_x86_64(source))
    }).err().expect("a scoped constant name in a type annotation must reject");
    assert_eq!(error.to_public_diagnostic().code, "LNC0007", "{error:?}");
}

#[test]
fn explicit_constant_arguments_execute_constant_only_forwarding() {
    execute_with_status("constant-only forwarding without signature bindings",
        include_str!("fixtures/stdlib_foundation/repro_explicit_constant_only_forwarding.lani"), b"", 42);
    let stdlib = explicit_constant_stdlib();
    execute_with_stdlib("imported constant-only forwarding without signature bindings", r#"
import core::explicit_constants;
fn main() -> i32 {
    if (core::explicit_constants::scalar_relay<0>() != 0 || core::explicit_constants::scalar_relay<3>() != 3) { return 1; }
    return 42;
}
"#, stdlib.0.path(), b"", 42);
}

#[test]
fn nominal_constant_arguments_preserve_owned_values() {
    let source = include_str!("fixtures/stdlib_foundation/repro_mixed_nominal_constant_arguments.lani");
    execute_with_status("nominal constant ordinary values", &source.replace(
        "fn keep<T>(value: T) -> T", "fn keep(value: Buffer<i32, 3>) -> Buffer<i32, 3>"), b"", 42);
    execute_with_status("nominal constant generic values", source, b"", 42);
}

#[test]
fn nominal_constant_record_values_execute() {
    let source = include_str!("fixtures/stdlib_foundation/repro_mixed_nominal_constant_arguments.lani")
        .replace("keep(original)", "original");
    execute_with_status("nominal constant record storage", &source, b"", 42);
}

#[test]
fn nominal_constant_first_headers_preserve_type_domains_and_owned_values() {
    let source = include_str!("fixtures/stdlib_foundation/repro_mixed_nominal_constant_arguments.lani")
        .replace("struct Buffer<T, const N: usize>", "struct Buffer<const N: usize, T>")
        .replace("Buffer<i32, 3>", "Buffer<3, i32>");
    execute_with_status("constant-first ordinary record", &source.replace(
        "fn keep<T>(value: T) -> T", "fn keep(value: Buffer<3, i32>) -> Buffer<3, i32>"), b"", 42);
    execute_with_status("constant-first generic record", &source, b"", 42);
}

#[test]
fn nominal_constant_arguments_preserve_unused_identity_and_zero_lengths() {
    execute_with_status("nominal zero and unused constants", r#"
struct Buffer<const N: usize, T> { values: [T; N] }
struct Flag<const K: usize, T> { value: T }
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let empty: Buffer<0, i32> = Buffer<0, i32> { values: [] };
    let copied: Buffer<0, i32> = keep(empty);
    let first: Flag<3, bool> = Flag<3, bool> { value: true };
    let second: Flag<4, bool> = Flag<4, bool> { value: false };
    let kept_first: Flag<3, bool> = keep(first);
    let kept_second: Flag<4, bool> = keep(second);
    if (!kept_first.value || kept_second.value) { return 1; }
    return 42;
}
"#, b"", 42);
}

#[test]
fn nominal_constant_arguments_compose_with_caller_scopes_option_and_result() {
    execute_with_status("nominal constants through caller scopes and algebraic values", r#"
import core::option;
import core::result;
struct Buffer<const N: usize, T> { values: [T; N] }
fn keep<T>(value: T) -> T { return value; }
fn relay<const N: usize, T>(value: Buffer<N, T>) -> Buffer<N, T> { return keep(value); }
fn main() -> i32 {
    let original: Buffer<3, i32> = Buffer<3, i32> { values: [12, 20, 10] };
    let wrapped: core::option::Option<Buffer<3, i32>> = core::option::Some(relay<3, i32>(original));
    let selected: Buffer<3, i32> = core::option::unwrap_or(keep(wrapped), original);
    let success: core::result::Result<Buffer<3, i32>, bool> = core::result::Ok(selected);
    let result: Buffer<3, i32> = core::result::unwrap_or(keep(success), original);
    result.values[0] = 99;
    if (original.values[0] != 12 || result.values[0] != 99) { return 1; }
    return original.values[0] + original.values[1] + original.values[2];
}
"#, b"", 42);
}

fn nominal_constant_stdlib() -> ReceiverTestStdlib {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/nominal_constants.lani"), r#"
module core::nominal_constants;
pub struct Buffer<const N: usize, T> { values: [T; N] }
pub fn keep<const N: usize, T>(value: Buffer<N, T>) -> Buffer<N, T> { return value; }
pub impl<const N: usize, T> Buffer<N, T> {
    pub fn copied(value: Buffer<N, T>) -> Buffer<N, T> { return keep<N, T>(value); }
    pub fn width<U, const M: usize>(value: [U; M]) -> usize { return N * 10 + M; }
}
"#).expect("nominal constants module");
    stdlib
}

#[test]
fn nominal_constant_arguments_execute_imported_records_functions_and_methods() {
    let stdlib = nominal_constant_stdlib();
    execute_with_stdlib("imported nominal constants and associated method domains", r#"
import core::nominal_constants;
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let original: core::nominal_constants::Buffer<3, i32> = core::nominal_constants::Buffer<3, i32> { values: [12, 20, 10] };
    let forwarded = core::nominal_constants::keep<3, i32>(original);
    let copied = core::nominal_constants::Buffer<3, i32>::copied(keep(forwarded));
    copied.values[0] = 99;
    if (original.values[0] != 12 || forwarded.values[0] != 12 || copied.values[0] != 99) { return 1; }
    let flags: [bool; 2] = [true, false];
    if (core::nominal_constants::Buffer<3, i32>::width<bool, 2>(flags) != 32) { return 2; }
    return original.values[0] + original.values[1] + original.values[2];
}
"#, stdlib.0.path(), b"", 42);
}

fn nominal_fixed_stdlib() -> ReceiverTestStdlib {
    let stdlib = ReceiverTestStdlib::new();
    std::fs::write(stdlib.0.path().join("core/nominal_fixed.lani"), r#"
module core::nominal_fixed;
pub struct Buffer<T, const N: usize> { values: [T; N] }
pub fn make(seed: i32) -> Buffer<i32, 3> { return Buffer<i32, 3> { values: [seed, 1, 1] }; }
pub fn first<T, const N: usize>(b: Buffer<T, N>) -> T { return b.values[0]; }
"#).expect("nominal fixed module");
    stdlib
}

#[test]
fn nominal_constant_arguments_cross_imported_concrete_signatures() {
    // The dependency interface carries `make`'s `Buffer<i32, 3>` with its
    // constant identity, so the importer rebuilds the same nominal type.
    let stdlib = nominal_fixed_stdlib();
    execute_with_stdlib("imported concrete constant arguments", r#"
import core::nominal_fixed;
fn main() -> i32 {
    let b: core::nominal_fixed::Buffer<i32, 3> = core::nominal_fixed::make(40);
    return core::nominal_fixed::first(b) + b.values[1] + b.values[2];
}
"#, stdlib.0.path(), b"", 42);
    let entry = common::TempArtifact::new("generic_types", "imported constant argument mismatch", Some("lani"));
    entry.write_str(r#"
import core::nominal_fixed;
fn main() -> i32 {
    let b: core::nominal_fixed::Buffer<i32, 4> = core::nominal_fixed::make(40);
    return b.values[0];
}
"#);
    let path = entry.path().to_path_buf();
    let root = stdlib.0.path().to_path_buf();
    let error = common::run_gpu_codegen_with_timeout("imported constant argument mismatch", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    })
    .expect_err("Buffer<i32, 3> must not convert to Buffer<i32, 4>");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0006", "{error:?}");
}

#[test]
fn nominal_constant_arguments_execute_thirty_two_interleaved_operands() {
    let header = (0..16).map(|i| format!("const N{i}: usize, T{i}")).collect::<Vec<_>>().join(", ");
    let arguments = (0..16).map(|i| format!("{}, {}", if i == 7 { 3 } else { i }, if i == 15 { "bool" } else { "i32" })).collect::<Vec<_>>().join(", ");
    for imported in [false, true] {
        let stdlib = nominal_constant_stdlib();
        let declaration = format!("pub struct Wide<{header}> {{ first: T0, last: T15, values: [T7; N7] }}");
        let (import, prefix, local) = if imported {
            std::fs::write(stdlib.0.path().join("core/nominal_wide.lani"),
                format!("module core::nominal_wide; {declaration}")).unwrap();
            ("import core::nominal_wide;", "core::nominal_wide::", "")
        } else { ("", "", declaration.as_str()) };
        execute_with_stdlib(&format!("32 nominal operands preserve domain slots imported={imported}"), &format!(r#"
{import}
{local}
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{
    let original: {prefix}Wide<{arguments}> = {prefix}Wide<{arguments}> {{ first: 12, last: true, values: [12, 20, 10] }};
    let copied: {prefix}Wide<{arguments}> = keep(original);
    copied.values[0] = 99;
    if (copied.first != 12 || !copied.last || original.values[0] != 12 || copied.values[0] != 99) {{ return 1; }}
    return original.values[0] + original.values[1] + original.values[2];
}}
"#), stdlib.0.path(), b"", 42);
    }
}

#[test]
fn nominal_constant_arguments_preserve_compound_payloads_and_aliases() {
    // The same program checks both declaration paths. Owned aggregates must copy;
    // descriptors inside those aggregates must continue to alias their referents.
    for imported in [false, true] {
        let stdlib = nominal_constant_stdlib();
        let declaration = std::fs::read_to_string(stdlib.0.path().join("core/nominal_constants.lani")).unwrap();
        let (declarations, prefix) = if imported {
            ("import core::nominal_constants;".to_owned(), "core::nominal_constants::")
        } else {
            (declaration.replace("module core::nominal_constants;", ""), "")
        };
        let source = r#"
import std::io;
$DECLARATIONS
struct Item { value: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
struct Empty {}
fn slices(values: [i32]) -> i32 {
    let original: $BUFFER<1, [i32]> = $BUFFER<1, [i32]> { values: [values] };
    let copied = $BUFFER<1, [i32]>::copied(original);
    values[0] = 17;
    copied.values[0][1] = 25;
    if (original.values[0][0] != 17 || values[1] != 25) { return 1; }
    return 0;
}
fn main() -> i32 {
    let words: $BUFFER<2, str> = $BUFFER<2, str> { values: ["Ω", "λ"] };
    let copied_words = $BUFFER<2, str>::copied(words);
    copied_words.values[0] = "changed";
    std::io::println(words.values[0]);
    std::io::println(copied_words.values[0]);
    let arrays: $BUFFER<2, [bool; 2]> = $BUFFER<2, [bool; 2]> { values: [[false, true], [true, false]] };
    let copied_arrays = $BUFFER<2, [bool; 2]>::copied(arrays);
    copied_arrays.values[0][0] = true;
    if (arrays.values[0][0] || !copied_arrays.values[0][0] || !arrays.values[1][0]) { return 2; }
    let item: Item = Item { value: 12 };
    let references: $BUFFER<1, &Item> = $BUFFER<1, &Item> { values: [item.borrow()] };
    let copied_references = $BUFFER<1, &Item>::copied(references);
    item.value = 42;
    if (references.values[0].value != 42 || copied_references.values[0].value != 42) { return 3; }
    let inner: $BUFFER<2, i32> = $BUFFER<2, i32> { values: [12, 30] };
    let nested: $BUFFER<1, $BUFFER<2, i32>> = $BUFFER<1, $BUFFER<2, i32>> { values: [inner] };
    let copied_nested = $BUFFER<1, $BUFFER<2, i32>>::copied(nested);
    copied_nested.values[0].values[0] = 99;
    if (nested.values[0].values[0] != 12 || copied_nested.values[0].values[0] != 99) { return 4; }
    let empty: $BUFFER<2, Empty> = $BUFFER<2, Empty> { values: [Empty {}, Empty {}] };
    let copied_empty = $BUFFER<2, Empty>::copied(empty);
    if ($BUFFER<2, Empty>::width<bool, 0>([]) != 20) { return 5; }
    if (slices([12, 30]) != 0) { return 6; }
    return item.value;
}
"#.replace("$DECLARATIONS", &declarations)
            .replace("$BUFFER", &format!("{prefix}Buffer"));
        execute_with_stdlib(&format!("compound nominal constants imported={imported}"),
            &source, stdlib.0.path(), "Ω\nchanged\n".as_bytes(), 42);
    }
}

#[test]
fn nominal_constant_arguments_reject_equal_width_identity_conflicts() {
    let source = r#"
struct Flag<const N: usize, T> { value: T }
fn need(value: Flag<4, bool>) -> bool { return value.value; }
fn main() -> i32 {
    let actual: Flag<3, bool> = Flag<3, bool> { value: true };
    if (need(actual)) { return 42; }
    return 1;
}
"#;
    let error = common::run_gpu_codegen_with_timeout("distinct unused nominal constants", move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
        pollster::block_on(compiler.compile_source_to_x86_64(source))
    }).expect_err("different constants cannot unify because native widths match");
    assert!(format!("{error:?}").contains("LNC0006"), "{error:?}");
}

#[test]
fn generic_enum_constructors_infer_complete_payload_types() {
    execute("inferred local enum payloads and body replay",
        include_str!("fixtures/stdlib_foundation/generic_enum_inferred_constructors.lani"));
    execute("inferred imported enum payloads and body replay",
        include_str!("fixtures/stdlib_foundation/generic_enum_inferred_imports.lani"));
}

#[test]
fn generic_enum_constructor_headers_bind_types_and_constants() {
    let root = ReceiverTestStdlib::new();
    let declaration = "pub enum Packet<A, const N: usize, B> { Data([A; N], B), Absent }";
    std::fs::write(root.0.path().join("core/packets.lani"),
        format!("module core::packets; {declaration}")).unwrap();
    for imported in [false, true] {
        let definitions = if imported { "import core::packets;" } else { declaration };
        let prefix = if imported { "core::packets::" } else { "" };
        let source = format!(r#"
{definitions}
fn main() -> i32 {{
 let packet = {prefix}Data([41, 43], false);
 let values: [i32; 2] = match (packet) {{ {prefix}Data(v, flag) -> v, {prefix}Absent -> [0, 0] }};
 let absent = {prefix}Absent<i32, 0, bool>();
 let missing: bool = match (absent) {{ {prefix}Absent -> true, _ -> false }};
 let empty: [i32; 0] = [];
 let zero = {prefix}Data(empty, true);
 let present: bool = match (zero) {{ {prefix}Data(v, flag) -> flag, _ -> false }};
 if (values[0] != 41 || values[1] != 43 || !missing || !present) {{ return 1; }}
 return 0;
}}
"#);
        execute_with_stdlib("enum headers bind both parameter domains", &source, root.0.path(), b"", 0);
    }
}

#[test]
fn generic_enum_constructors_reject_inconsistent_and_missing_bindings() {
    for source in [
        "enum Pair<T> { Both(T, T), Missing } fn main() -> i32 { let value = Both(true, 42); return 0; }",
        "enum Pair<A, B> { First(A), Missing } fn main() -> i32 { let value = First(42); return 0; }",
        "enum Maybe<T> { Value(T), Missing } fn main() -> i32 { let value = Missing(); return 0; }",
        "enum Maybe<T> { Value(T), Missing } fn main() -> i32 { let value: Maybe<bool> = Value(42); return 0; }",
        "import core::option; fn main() -> i32 { let value = core::option::None(); return 0; }",
        "import core::result; fn main() -> i32 { let value = core::result::Ok(42); return 0; }",
        "import core::option; fn main() -> i32 { let value: core::option::Option<bool> = core::option::Some(42); return 0; }",
    ] {
        let entry = common::TempArtifact::new("constructor_binding", "rejected", Some("lani"));
        entry.write_str(source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let error = common::run_gpu_codegen_with_timeout("constructor binding rejection", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        }).expect_err("inconsistent or incomplete constructor binding must not emit an ELF");
        let diagnostic = error.to_public_diagnostic();
        assert!(matches!(diagnostic.code.as_str(), "LNC0006" | "LNC0011" | "LNC0047"), "{source}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{source}: {error:?}");
    }
}

#[test]
fn generic_enum_constructors_infer_thirty_two_bindings_from_payloads() {
    let parameters = (0..32).map(|slot| format!("T{slot}")).collect::<Vec<_>>().join(", ");
    let mut arguments = vec!["bool"; 32];
    arguments[31] = "[i32; 2]";
    let arguments = arguments.join(", ");
    let definitions = format!("pub struct Wide<{parameters}> {{ first: T0, last: T31 }} pub enum Packet<{parameters}> {{ Data(Wide<{parameters}>), Missing }}");
    let root = ReceiverTestStdlib::new();
    std::fs::write(root.0.path().join("core/wide_packet.lani"),
        format!("module core::wide_packet; {definitions}")).unwrap();
    for imported in [false, true] {
        let declarations = if imported { "import core::wide_packet;" } else { &definitions };
        let prefix = if imported { "core::wide_packet::" } else { "" };
        execute_with_stdlib("32 inferred constructor bindings", &format!(r#"
{declarations}
fn main() -> i32 {{
 let payload: {prefix}Wide<{arguments}> = {prefix}Wide {{ first: false, last: [41, 43] }};
 let packet = {prefix}Data(payload);
 payload.last[0] = 47;
 let recovered: {prefix}Wide<{arguments}> = match (packet) {{ {prefix}Data(v) -> v, _ -> payload }};
 if (recovered.first || recovered.last[0] != 41 || recovered.last[1] != 43 || payload.last[0] != 47) {{ return 1; }}
 return 0;
}}
"#), root.0.path(), b"", 0);
    }
}

#[test]
fn generic_unit_variant_values_receive_complete_types() {
    execute("generic unit return in nested array context",
        include_str!("fixtures/stdlib_foundation/repro_generic_bare_unit_variant.lani"));
    execute("unit values in fields, arguments, arrays, and match results", r#"
enum Maybe<T> { Value(T), Missing }
struct Holder<T> { value: T }
fn keep<T>(value: T) -> T { return value; }
fn read(value: Maybe<i32>) -> i32 { return match (value) { Value(v) -> v, Missing -> 42 }; }
fn main() -> i32 {
 let field: Holder<Maybe<[i32; 2]>> = Holder { value: Missing };
 let array: [Maybe<bool>; 2] = [Missing, Value(false)];
 let result: Maybe<[i32; 2]> = match (true) { true -> Missing, false -> Value([41, 43]) };
 let absent: bool = match (keep(field.value)) { Missing -> true, _ -> false };
 let selected: bool = match (result) { Missing -> true, _ -> false };
 let first: bool = match (array[0]) { Missing -> true, _ -> false };
 if (!absent || !selected || !first || read(Missing) != 42) { return 1; }
 return 0;
}
"#);
}

fn inferred_record_stdlib(declarations: &str) -> ReceiverTestStdlib {
    let root = ReceiverTestStdlib::new();
    std::fs::write(root.0.path().join("core/inferred_record.lani"),
        format!("module core::inferred_record; {declarations}")).unwrap();
    root
}

#[test]
fn generic_record_fields_infer_complete_types() {
    execute("nested inferred record in inferred enum",
        include_str!("fixtures/stdlib_compiler_state/enum-inference-local-compound-spaced.lani"));
    let declarations = "pub struct Cell<T> { value: T } pub struct Pair<A, B> { first: A, second: B }";
    for imported in [false, true] {
        let root = inferred_record_stdlib(declarations);
        let source = r#"
import std::io;
$DECLARATIONS
struct Empty {}
struct Item { value: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn keep<T>(value: T) -> T { return value; }
fn unsigned_nested(value: $P::Pair<$P::Cell<u32>, bool>) -> u32 { return value.first.value; }
fn unsigned_array(value: [$P::Cell<u32>; 1]) -> u32 { return value[0].value; }
fn exercise(view: [i32]) -> i32 {
    let borrowed = $P::Cell { value: view };
    let copied = keep(borrowed);
    copied.value[1] = 43;
    if (view[1] != 43 || borrowed.value[1] != 43) { return 1; }
    return 0;
}
fn main() -> i32 {
    if (unsigned_nested($P::Pair { first: $P::Cell { value: 4294967295 }, second: false }) != 4294967295) { return 5; }
    if (unsigned_array([$P::Cell { value: 4294967295 }]) != 4294967295) { return 6; }
    let original = $P::Pair { second: false, first: $P::Cell { value: [41, 43] } };
    let copied = keep(original);
    copied.first.value[0] = 47;
    if (original.first.value[0] != 41 || copied.first.value[0] != 47 || copied.second) { return 2; }
    let empty: [i32; 0] = [];
    let zeros = $P::Pair { first: empty, second: Empty {} };
    let copied_zeros = keep(zeros);
    let item: Item = Item { value: 41 };
    let reference = $P::Cell { value: item.borrow() };
    let copied_reference = keep(reference);
    item.value = 43;
    if (copied_reference.value.value != 43 || reference.value.value != 43) { return 3; }
    let text = $P::Pair { first: "hello", second: true };
    let copied_text = keep(text);
    if (!copied_text.second) { return 4; }
    std::io::println(copied_text.first);
    return exercise([41, 42]);
}
"#.replace("$DECLARATIONS", if imported { "import core::inferred_record;" } else { declarations })
    .replace("$P::", if imported { "core::inferred_record::" } else { "" });
        execute_with_stdlib(&format!("inferred record compositions imported={imported}"),
            &source, root.0.path(), b"hello\n", 0);
    }
}

#[test]
fn generic_record_fields_infer_constant_and_symbolic_parameters() {
    let declarations = r#"
pub struct Packet<A, const N: usize, B> { values: [A; N], flag: B }
pub struct Cell<T> { value: T }
pub struct WithEmpty<T> { empty: [T; 0], witness: T }
pub fn wrap<T>(value: T) -> Cell<T> { let wrapped = Cell { value: value }; return wrapped; }
pub fn pack<T, const N: usize>(value: [T; N]) -> Packet<T, N, bool> {
    let result = Packet { flag: false, values: value }; return result;
}
"#;
    for imported in [false, true] {
        let root = inferred_record_stdlib(declarations);
        let source = r#"
$DECLARATIONS
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let packet = $P::Packet { flag: true, values: [41, 43] };
    let copied = keep(packet);
    copied.values[1] = 47;
    if (!packet.flag || packet.values[1] != 43 || copied.values[1] != 47) { return 1; }
    let wrapped = $P::wrap(packet);
    if (!wrapped.value.flag || wrapped.value.values[0] != 41) { return 2; }
    let packed = $P::pack([41, 43]);
    if (packed.flag || packed.values[1] != 43) { return 3; }
    let inferred_empty = $P::WithEmpty { empty: [], witness: 42 };
    let copied_empty = keep(inferred_empty);
    if (copied_empty.witness != 42) { return 5; }
    let empty: [i32; 0] = [];
    let zero = $P::Packet { values: empty, flag: false };
    let copied_zero = keep(zero);
    if (copied_zero.flag) { return 4; }
    return 0;
}
"#.replace("$DECLARATIONS", if imported { "import core::inferred_record;" } else { declarations })
    .replace("$P::", if imported { "core::inferred_record::" } else { "" });
        execute_with_stdlib(&format!("inferred record domains imported={imported}"),
            &source, root.0.path(), b"", 0);
    }
}

#[test]
fn generic_record_fields_infer_thirty_two_bindings() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let fields = (0..32).map(|i| format!("f{i}: T{i}")).collect::<Vec<_>>().join(", ");
    let values = (0..32).rev().map(|i| format!("f{i}: {}", if i == 31 { "[41, 43]" } else if i % 2 == 0 { "true" } else { "false" })).collect::<Vec<_>>().join(", ");
    let assertions = (0..31).map(|i| format!("if (original.f{i} != {} || copied.f{i} != {}) {{ return 2; }}", i % 2 == 0, i % 2 == 0)).collect::<Vec<_>>().join("\n");
    let declarations = format!("pub struct Wide<{parameters}> {{ {fields} }}");
    for imported in [false, true] {
        let root = inferred_record_stdlib(&declarations);
        let prefix = if imported { "core::inferred_record::" } else { "" };
        let definitions = if imported { "import core::inferred_record;" } else { &declarations };
        execute_with_stdlib(&format!("32 inferred record fields imported={imported}"), &format!(r#"
{definitions}
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{
    let original = {prefix}Wide {{ {values} }};
    let copied = keep(original);
    copied.f31[0] = 47;
    {assertions}
    if (original.f31[0] != 41 || copied.f31[0] != 47 || copied.f31[1] != 43) {{ return 1; }}
    return 0;
}}
"#), root.0.path(), b"", 0);
    }
}

#[test]
fn generic_record_field_constraints_reject_conflicts_and_missing_bindings() {
    for (declarations, expression) in [
        ("pub struct Pair<T> { first: T, second: T }", "Pair { first: true, second: 42 }"),
        ("pub struct Pair<T> { first: T, second: T }", "Pair { second: 42, first: true }"),
        ("pub struct Pair<T, const N: usize> { first: [T; N], second: [T; N] }", "Pair { first: [41, 43], second: [47] }"),
        ("pub struct Cell<A, B> { value: A }", "Cell { value: 42 }"),
        ("pub struct Cell<T> { value: T }", "Cell { wrong: 42 }"),
        ("pub struct Pair<T> { first: T, second: T }", "Pair { first: 42 }"),
        ("pub struct Pair<T> { first: T, second: T }", "Pair { first: 42, first: 43, second: 44 }"),
    ] {
        for imported in [false, true] {
            let root = inferred_record_stdlib(declarations);
            let definitions = if imported { "import core::inferred_record;" } else { declarations };
            let expression = if imported { format!("core::inferred_record::{expression}") } else { expression.to_owned() };
            let entry = common::TempArtifact::new("inferred_record", "rejected", Some("lani"));
            entry.write_str(&format!("{definitions} fn main() -> i32 {{ let value = {expression}; return 0; }}"));
            let path = entry.path().to_path_buf();
            let stdlib = root.0.path().to_path_buf();
            let error = common::run_gpu_codegen_with_timeout("inferred record constraints", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            }).expect_err("inconsistent, incomplete, and malformed records must not emit an ELF");
            let diagnostic = error.to_public_diagnostic();
            assert!(matches!(diagnostic.code.as_str(), "LNC0006" | "LNC0042" | "LNC0047"), "{expression}: {error:?}");
            assert!(diagnostic.primary_label.is_some(), "{expression}: {error:?}");
        }
    }
}


fn execute_borrowed_enum_routes(label: &str, declarations: &str, program: &str) {
    let root = unit_value_stdlib(declarations);
    for imported in [false, true] {
        let source = program
            .replace("$DECLARATIONS", if imported { "import core::unit_values;" } else { declarations })
            .replace("$P::", if imported { "core::unit_values::" } else { "" });
        execute_with_stdlib(&format!("{label}, imported={imported}"),
            &source, root.0.path(), b"", 0);
    }
}

#[test]
fn borrowed_enum_concrete_methods_preserve_boolean_payloads() {
    execute_borrowed_enum_routes("borrowed concrete enum bool", r#"
pub enum Maybe<T> { Some(T), None }
pub impl Maybe<bool> {
    pub fn unwrap_or(&self, fallback: bool) -> bool {
        return match (self) { Some(value) -> value, None -> fallback };
    }
}
"#, r#"
$DECLARATIONS
fn main() -> i32 {
    let yes: $P::Maybe<bool> = $P::Some(true);
    let no: $P::Maybe<bool> = $P::Some(false);
    let missing: $P::Maybe<bool> = $P::None();
    if (!yes.unwrap_or(false) || no.unwrap_or(true)) { return 1; }
    if (!missing.unwrap_or(true) || missing.unwrap_or(false)) { return 2; }
    return 0;
}
"#);
}

#[test]
fn borrowed_enum_generic_methods_preserve_array_copies_and_slice_aliases() {
    execute_borrowed_enum_routes("borrowed generic enum compound payloads", r#"
pub enum Maybe<T> { Some(T), None }
pub impl<T> Maybe<T> {
    pub fn unwrap_or(&self, fallback: T) -> T {
        return match (self) { Some(value) -> value, None -> fallback };
    }
}
"#, r#"
$DECLARATIONS
fn check_slices(view: [i32], fallback: [i32]) -> i32 {
    let present: $P::Maybe<[i32]> = $P::Some(view);
    let absent: $P::Maybe<[i32]> = $P::None();
    let selected: [i32] = present.unwrap_or(fallback);
    let alternative: [i32] = absent.unwrap_or(fallback);
    if (selected[0] != 31 || selected[1] != 37 || alternative[0] != 41 || alternative[1] != 43) { return 3; }
    selected[1] = 53;
    alternative[0] = 59;
    if (view[1] != 53 || fallback[0] != 59 || view[0] != 31 || fallback[1] != 43) { return 4; }
    let again: [i32] = present.unwrap_or(fallback);
    if (again[1] != 53) { return 5; }
    return 0;
}
fn main() -> i32 {
    let present: $P::Maybe<[i32; 2]> = $P::Some([11, 22]);
    let absent: $P::Maybe<[i32; 2]> = $P::None();
    let fallback: [i32; 2] = [-3, -5];
    let selected: [i32; 2] = present.unwrap_or(fallback);
    let alternative: [i32; 2] = absent.unwrap_or(fallback);
    if (selected[0] != 11 || selected[1] != 22 || alternative[0] != -3 || alternative[1] != -5) { return 1; }
    selected[0] = 99;
    alternative[1] = 101;
    let again: [i32; 2] = present.unwrap_or(fallback);
    if (again[0] != 11 || again[1] != 22 || fallback[0] != -3 || fallback[1] != -5) { return 2; }
    return check_slices([31, 37], [41, 43]);
}
"#);
}

#[test]
fn borrowed_enum_wildcards_preserve_multiword_and_zero_sized_payload_offsets() {
    execute_borrowed_enum_routes("borrowed enum ignored payload offsets", r#"
pub struct Empty {}
pub enum Packet<T> { Missing, Data(T, bool) }
pub impl<T> Packet<T> {
    pub fn flag(&self) -> bool {
        return match (self) { Data(_, flag) -> flag, Missing -> false };
    }
}
"#, r#"
$DECLARATIONS
fn main() -> i32 {
    let wide_yes: $P::Packet<[i32; 3]> = $P::Data([0, 0, 0], true);
    let wide_no: $P::Packet<[i32; 3]> = $P::Data([31, 37, 41], false);
    let wide_missing: $P::Packet<[i32; 3]> = $P::Missing();
    if (!wide_yes.flag() || wide_no.flag() || wide_missing.flag()) { return 1; }
    let empty_yes: $P::Packet<$P::Empty> = $P::Data($P::Empty {}, true);
    let empty_no: $P::Packet<$P::Empty> = $P::Data($P::Empty {}, false);
    let empty_missing: $P::Packet<$P::Empty> = $P::Missing();
    if (!empty_yes.flag() || empty_no.flag() || empty_missing.flag()) { return 2; }
    return 0;
}
"#);
}

#[test]
fn structural_annotations_preserve_local_and_imported_nominal_children() {
    execute_borrowed_enum_routes("structural nominal annotation children", r#"
pub fn keep<T>(value: T) -> T { return value; }
pub struct Item { value: i32 }
pub impl Item {
    pub fn borrow(&self) -> &Item { return self; }
}
pub struct Cell<T> { value: T }
pub impl<T> Cell<T> {
    pub fn borrow(&self) -> &Cell<T> { return self; }
}
"#, r#"
$DECLARATIONS
fn check_slice(items: [$P::Item]) -> i32 {
    if (items[0].value != 31 || items[1].value != 37) { return 1; }
    items[1].value = 53;
    return 0;
}
fn main() -> i32 {
    let item: $P::Item = $P::Item { value: 41 };
    let borrowed: &$P::Item = $P::keep(item.borrow());
    item.value = 47;
    if (borrowed.value != 47) { return 2; }
    let items: [$P::Item; 2] = [$P::Item { value: 31 }, $P::Item { value: 37 }];
    if (check_slice(items) != 0 || items[1].value != 53) { return 3; }
    let copied: [$P::Item; 2] = $P::keep(items);
    copied[0].value = 61;
    if (items[0].value != 31 || copied[0].value != 61 || copied[1].value != 53) { return 4; }
    let cell: $P::Cell<i32> = $P::Cell { value: 43 };
    let generic_borrowed: &$P::Cell<i32> = cell.borrow();
    cell.value = 59;
    if (generic_borrowed.value != 59) { return 5; }
    return 0;
}
"#);
}

#[test]
fn borrowed_enum_reference_payload_preserves_alias_and_following_boolean() {
    execute_borrowed_enum_routes("borrowed enum reference payload width", r#"
pub struct Item { head: i32, tail: i32, sentinel: i32 }
pub impl Item {
    pub fn borrow(&self) -> &Item { return self; }
}
pub enum Packet { Missing, Data(&Item, bool) }
pub impl Packet {
    pub fn borrow(&self) -> &Packet { return self; }
    pub fn item_or(&self, fallback: &Item) -> &Item {
        return match (self) { Data(item, _) -> item, Missing -> fallback };
    }
    pub fn flag(&self) -> bool {
        return match (self) { Data(_, flag) -> flag, Missing -> false };
    }
}
pub fn keep<T>(value: T) -> T { return value; }
"#, r#"
$DECLARATIONS
fn main() -> i32 {
    let first: $P::Item = $P::Item { head: 11, tail: 22, sentinel: 97 };
    let second: $P::Item = $P::Item { head: 33, tail: 44, sentinel: 101 };
    let fallback: $P::Item = $P::Item { head: 47, tail: 53, sentinel: 103 };
    let yes: $P::Packet = $P::Data(first.borrow(), true);
    let no: $P::Packet = $P::Data(second.borrow(), false);
    let absent: $P::Packet = $P::Missing();
    let copied: $P::Packet = $P::keep(yes);
    let copied_no: $P::Packet = $P::keep(no);
    let borrowed: &$P::Packet = copied.borrow();
    let selected: &$P::Item = borrowed.item_or(fallback.borrow());
    let other: &$P::Item = copied_no.item_or(fallback.borrow());
    let missing: &$P::Item = absent.item_or(fallback.borrow());
    if (!borrowed.flag() || copied_no.flag() || absent.flag()) { return 1; }
    first.head = 59;
    second.tail = 61;
    fallback.head = 67;
    if (selected.head != 59 || selected.tail != 22 || selected.sentinel != 97) { return 2; }
    if (other.head != 33 || other.tail != 61 || other.sentinel != 101) { return 3; }
    if (missing.head != 67 || missing.tail != 53 || missing.sentinel != 103) { return 4; }
    yes = $P::Missing();
    if (!borrowed.flag() || copied_no.flag() || yes.flag()) { return 5; }
    return 0;
}
"#);
}

fn unit_value_stdlib(declarations: &str) -> ReceiverTestStdlib {
    let root = ReceiverTestStdlib::new();
    std::fs::write(root.0.path().join("core/unit_values.lani"),
        format!("module core::unit_values; {declarations}")).unwrap();
    root
}

#[test]
fn generic_unit_values_preserve_complete_local_and_imported_types() {
    execute_with_status("original imported bare unit value",
        include_str!("fixtures/stdlib_compiler_state/variant-path-imported-unit.lani"), b"", 42);
    let declarations = "pub enum Maybe<T> { Missing, Value(T) } pub enum Packet<A, const N: usize, B> { Absent, Data([A; N], B) } pub enum Plain { Quiet, Words([str; 2]) }";
    for imported in [false, true] {
        let root = unit_value_stdlib(declarations);
        let source = r#"
import std::io;
$DECLARATIONS
struct Holder<T> { value: T }
struct Empty {}
struct Item { value: i32 }
impl Item { fn borrow(&self) -> &Item { return self; } }
fn keep<T>(value: T) -> T { return value; }
fn missing<T>() -> $P::Maybe<T> { return $P::Missing; }
fn absent<A, const N: usize, B>() -> $P::Packet<A, N, B> { return $P::Absent; }
fn read(value: $P::Maybe<i32>) -> i32 { return match(value) { $P::Missing -> 42, _ -> 1 }; }
fn borrow_case(view: [i32]) -> i32 {
    let value: $P::Maybe<[i32]> = $P::Missing;
    if (!(match(value) { $P::Missing -> true, _ -> false })) { return 1; }
    value = $P::Value(view);
    let copied = keep(value);
    let recovered: [i32] = match(copied) { $P::Value(v) -> v, _ -> view };
    recovered[1] = 43;
    if (view[1] != 43) { return 2; }
    return 0;
}
fn main() -> i32 {
    let field: Holder<$P::Maybe<[str; 2]>> = Holder { value: $P::Missing };
    let values: [$P::Maybe<[i32; 2]>; 2] = [$P::Missing, $P::Value([41, 43])];
    let copied = keep(values);
    values[0] = $P::Value([1, 2]);
    let result: $P::Maybe<[i32; 2]> = match(true) { true -> $P::Missing, false -> $P::Value([47, 53]) };
    let direct: $P::Maybe<[bool; 0]> = missing();
    let packet: $P::Packet<i32, 0, Empty> = absent();
    let reference: $P::Maybe<&Item> = $P::Missing;
    let item = Item { value: 41 };
    reference = $P::Value(item.borrow());
    let copied_reference = keep(reference);
    item.value = 43;
    let recovered: &Item = match(copied_reference) { $P::Value(v) -> v, _ -> item.borrow() };
    if (recovered.value != 43) { return 3; }
    if (!(match(field.value) { $P::Missing -> true, _ -> false }) ||
        !(match(copied[0]) { $P::Missing -> true, _ -> false }) ||
        !(match(result) { $P::Missing -> true, _ -> false }) ||
        !(match(direct) { $P::Missing -> true, _ -> false }) ||
        !(match(packet) { $P::Absent -> true, _ -> false }) || read($P::Missing) != 42) { return 4; }
    let plain = $P::Quiet;
    let copied_plain = keep(plain);
    plain = $P::Words(["hello", "Ω"]);
    if (!(match(copied_plain) { $P::Quiet -> true, _ -> false })) { return 5; }
    let text: [str; 2] = match(plain) { $P::Words(v) -> v, _ -> ["bad", "bad"] };
    std::io::println(text[0]);
    std::io::println(text[1]);
    return borrow_case([41, 42]);
}
"#.replace("$DECLARATIONS", if imported { "import core::unit_values;" } else { declarations })
    .replace("$P::", if imported { "core::unit_values::" } else { "" });
        execute_with_stdlib(&format!("complete unit values imported={imported}"),
            &source, root.0.path(), "hello\nΩ\n".as_bytes(), 0);
    }
}

#[test]
fn imported_nongeneric_unit_values_have_complete_types_without_annotations() {
    let root = unit_value_stdlib("pub enum Plain { Quiet, Words([str; 2]) } pub enum Marker { MarkerOnly }");
    for source in [
        "import core::unit_values; fn main() -> i32 { let value = core::unit_values::MarkerOnly; return match(value) { core::unit_values::MarkerOnly -> 42 }; }",
        "import core::unit_values; fn keep<T>(value:T)->T {return value;} fn main() -> i32 { let value = keep(core::unit_values::Quiet); return match(value) { core::unit_values::Quiet -> 42, _ -> 1 }; }",
        "import core::unit_values; fn main() -> i32 { return match(core::unit_values::Quiet) { core::unit_values::Quiet -> 42, _ -> 1 }; }",
    ] {
        execute_with_stdlib("nongeneric imported unit type", source, root.0.path(), b"", 42);
    }
}

#[test]
fn generic_unit_values_retain_thirty_two_context_bindings() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let definitions = format!("pub enum Wide<{parameters}> {{ Missing, Present(T0, T31) }}");
    let mut arguments = vec!["bool";32]; arguments[0] = "str"; arguments[31] = "[i32; 2]";
    let arguments = arguments.join(", ");
    for imported in [false,true] {
        let root = unit_value_stdlib(&definitions);
        let declarations = if imported { "import core::unit_values;" } else { &definitions };
        let prefix = if imported { "core::unit_values::" } else { "" };
        let source = format!(r#"
{declarations}
fn missing<{parameters}>() -> {prefix}Wide<{parameters}> {{ return {prefix}Missing; }}
fn keep<T>(value:T)->T {{return value;}}
fn main()->i32 {{
 let value: {prefix}Wide<{arguments}> = missing();
 let copied = keep(value);
 value = {prefix}Present("hello", [41,43]);
 if (!(match(copied) {{ {prefix}Missing -> true, _ -> false }})) {{return 1;}}
 let array: [i32;2] = match(value) {{ {prefix}Present(text,v) -> v, _ -> [0,0] }};
 return array[0]+array[1]-42;
}}
"#);
        execute_with_stdlib(&format!("32 unit context bindings imported={imported}"),
            &source,root.0.path(),b"",42);
    }
}

#[test]
fn generic_unit_values_reject_missing_and_incompatible_contexts() {
    let definitions = "pub enum Maybe<T> { Missing, Value(T) } pub enum Other<T> { OtherMissing, OtherValue(T) }";
    for imported in [false,true] {
        let root = unit_value_stdlib(definitions);
        for body in [
            "let value = $P::Missing;",
            "let value: $P::Other<bool> = $P::Missing;",
            "let value: $P::Maybe<i32> = $P::Value;",
            "let value: $P::Maybe<i32> = $P::Missing; let other: $P::Maybe<bool> = value;",
        ] {
            let declarations = if imported { "import core::unit_values;" } else { definitions };
            let body = body.replace("$P::",if imported { "core::unit_values::" } else { "" });
            let source = format!("{declarations} fn main()->i32 {{ {body} return 0; }}");
            let entry = common::TempArtifact::new("unit_values", "invalid_context", Some("lani"));
            entry.write_str(&source);
            let path = entry.path().to_owned(); let stdlib = root.0.path().to_owned();
            let error = common::run_gpu_codegen_with_timeout("unit value context rejection", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path,&stdlib))
            }).expect_err("invalid unit or payload value must reject");
            let diagnostic = error.to_public_diagnostic();
            assert!(matches!(diagnostic.code.as_str(), "LNC0005" | "LNC0006" | "LNC0047"),"{source}: {error:?}");
            assert!(diagnostic.primary_label.is_some(),"{source}: {error:?}");
        }
    }
}

#[test]
fn explicit_generic_arguments_preserve_unrelated_member_comparisons() {
    for (label, source) in [
        ("comparison before a later shift", include_str!("fixtures/stdlib_compiler_state/member-comparison-shift.lani")),
        ("comparisons in separate functions", include_str!("fixtures/stdlib_compiler_state/member-comparison-close.lani")),
        ("comparisons and explicit generic calls", r#"
struct Pair { low: i32 }
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let left = Pair { low: 7 }; let low = 3;
    let yes = (low < left.low) && (left.low > (low));
    let checks = [low < left.low];
    if (!checks[0]) { return 2; }
    let bits = left.low >> (1);
    let values = keep<[i32; 2]>([bits, 39]);
    if (!yes) { return 1; }
    return values[0] + values[1];
}
"#),
    ] { execute_with_status(label, source, b"", 42); }
}

#[test]
fn imported_bare_nominal_annotations_preserve_composed_values() {
    let root = unit_value_stdlib(r#"
pub struct Words { values: [str; 2] }
pub enum Choice { Empty, Texts(Words) }
pub fn words() -> Words { return Words { values: ["hello", "Ω"] }; }
pub fn choice(full: bool) -> Choice { if (full) { return Texts(words()); } return Empty; }
"#);
    execute_with_stdlib("imported bare nominal annotations", r#"
import core::unit_values;
import std::io;
fn keep<T>(value: T) -> T { return value; }
fn relay(value: core::unit_values::Words) -> core::unit_values::Words {
    let copied: core::unit_values::Words = keep(value); return copied;
}
fn main() -> i32 {
    let record: core::unit_values::Words = core::unit_values::words();
    let copied = relay(record); copied.values[0] = "changed";
    let full: core::unit_values::Choice = core::unit_values::choice(true);
    let empty: core::unit_values::Choice = core::unit_values::choice(false);
    let values = [keep(full), keep(empty)];
    let count = match (values[0]) { core::unit_values::Texts(v) -> 1, _ -> 0 };
    let vacant = match (values[1]) { core::unit_values::Empty -> true, _ -> false };
    if (count != 1 || !vacant) { return 1; }
    std::io::println(record.values[0]); std::io::println(copied.values[0]);
    std::io::println(record.values[1]);
    return 42;
}
"#, root.0.path(), "hello\nchanged\nΩ\n".as_bytes(), 42);
}

#[test]
fn qualified_enum_variants_retain_their_parent_declarations() {
    for reversed in [false, true] {
        let a = "pub enum A<T> { Value(T), Missing }";
        let b = "pub enum B<T> { Value(T), Missing }";
        let declarations = if reversed { format!("{b} {a}") } else { format!("{a} {b}") };
        for imported in [false, true] {
            let root = unit_value_stdlib(&declarations);
            let source = r#"
$DECLARATIONS
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let first: $P::A<bool> = $P::A::Missing();
    let second = $P::B::Value([41, 43]);
    let bare: $P::B<[i32; 2]> = $P::B::Missing;
    let filled: $P::A<bool> = $P::A::Value(true);
    let copied = keep(second);
    if (!(match (first) { $P::A::Missing -> true, _ -> false })) { return 1; }
    if (!(match (bare) { $P::B::Missing -> true, _ -> false })) { return 2; }
    if (!(match (filled) { $P::A::Value(v) -> v, _ -> false })) { return 3; }
    return match (copied) { $P::B::Value(v) -> v[0] + v[1] - 42, _ -> 4 };
}
"#.replace("$DECLARATIONS", if imported { "import core::unit_values;" } else { &declarations })
    .replace("$P::", if imported { "core::unit_values::" } else { "" });
            execute_with_stdlib(&format!("qualified variants imported={imported} reversed={reversed}"),
                &source, root.0.path(), b"", 42);
        }
    }
}

#[test]
fn qualified_enum_variants_reject_ambiguous_and_unrelated_names() {
    let declarations = "pub enum A<T> { Value(T), Missing } pub enum B<T> { Value(T), Missing }";
    for expression in ["Value(42)", "Missing", "A::Absent()", "B::Value(42)"] {
        for imported in [false, true] {
            let root = unit_value_stdlib(declarations);
            let definitions = if imported { "import core::unit_values;" } else { declarations };
            let prefix = if imported { "core::unit_values::" } else { "" };
            let source = format!("{definitions} fn main() -> i32 {{ let value: {prefix}A<bool> = {prefix}{expression}; return 0; }}");
            let entry = common::TempArtifact::new("qualified_variants", "rejected", Some("lani"));
            entry.write_str(&source); let entry = entry.path().to_owned(); let stdlib = root.0.path().to_owned();
            let error = common::run_gpu_codegen_with_timeout("variant ownership rejection", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
            }).expect_err("ambiguous names and unrelated enum families must not emit code");
            let diagnostic = error.to_public_diagnostic();
            assert!(matches!(diagnostic.code.as_str(), "LNC0005" | "LNC0006" | "LNC0042"), "{expression}, imported={imported}: {error:?}");
            assert!(diagnostic.primary_label.is_some(), "{error:?}");
        }
    }
}

#[test]
fn qualified_enum_variants_bind_parent_applications() {
    let declarations = "pub enum A<T> { Value(T), Missing } pub enum Packet<T, const N: usize, F> { Absent, Data([T; N], F) } pub enum Flag { On, Off }";
    for imported in [false, true] {
        let root = unit_value_stdlib(declarations);
        let source = r#"
$DECLARATIONS
fn keep<T>(value: T) -> T { return value; }
fn main() -> i32 {
    let flag = $P::Flag::On();
    let off = $P::Flag::Off;
    if (!(match (flag) { $P::Flag::On -> true, _ -> false })) { return 1; }
    if (!(match (off) { $P::Flag::Off -> true, _ -> false })) { return 2; }
    let absent = $P::A<bool>::Missing();
    let bare = $P::A<[i32; 2]>::Missing;
    let payload = $P::A<[i32; 2]>::Value([41, 43]);
    let packet = $P::Packet<i32, 2, bool>::Data([41, 43], true);
    let empty = $P::Packet<i32, 0, bool>::Absent;
    if (!(match (absent) { $P::A::Missing -> true, _ -> false })) { return 3; }
    if (!(match (bare) { $P::A::Missing -> true, _ -> false })) { return 4; }
    if (!(match (empty) { $P::Packet::Absent -> true, _ -> false })) { return 5; }
    let copied = keep(payload);
    let answer = match (copied) { $P::A::Value(v) -> v[0] + v[1] - 42, _ -> 1 };
    let valid = match (packet) { $P::Packet::Data(v, f) -> f && v[0] == 41 && v[1] == 43, _ -> false };
    if (!valid) { return 6; }
    return answer;
}
"#.replace("$DECLARATIONS", if imported { "import core::unit_values;" } else { declarations })
    .replace("$P::", if imported { "core::unit_values::" } else { "" });
        execute_with_stdlib(&format!("qualified parent applications imported={imported}"), &source, root.0.path(), b"", 42);
    }
}

#[test]
fn qualified_enum_variant_parent_forms_execute_independently() {
    for (label, declarations, value, pattern, body) in [
        ("called concrete unit", "enum Flag { On, Off }", "Flag::On()", "Flag::On", "42"),
        ("bare concrete unit", "enum Flag { On, Off }", "Flag::Off", "Flag::Off", "42"),
        ("called explicit unit", "enum A<T> { Value(T), Missing }", "A<bool>::Missing()", "A::Missing", "42"),
        ("bare explicit unit", "enum A<T> { Value(T), Missing }", "A<[i32; 2]>::Missing", "A::Missing", "42"),
        ("called explicit array", "enum A<T> { Value(T), Missing }", "A<[i32; 2]>::Value([41, 43])", "A::Value(v)", "v[0] + v[1] - 42"),
        ("called mixed header", "enum Packet<T, const N: usize, F> { Absent, Data([T; N], F) }", "Packet<i32, 2, bool>::Data([41, 43], true)", "Packet::Data(v, f)", "v[0] + v[1] - 42"),
        ("bare mixed header", "enum Packet<T, const N: usize, F> { Absent, Data([T; N], F) }", "Packet<i32, 0, bool>::Absent", "Packet::Absent", "42"),
    ] {
        let declarations = declarations.replace("enum ", "pub enum ");
        for imported in [false, true] {
            let root = unit_value_stdlib(&declarations);
            let definitions = if imported { "import core::unit_values;" } else { &declarations };
            let prefix = if imported { "core::unit_values::" } else { "" };
            execute_with_stdlib(&format!("{label}, imported={imported}"), &format!("{definitions} fn main() -> i32 {{ let value = {prefix}{value}; return match (value) {{ {prefix}{pattern} -> {body}, _ -> 1 }}; }}"), root.0.path(), b"", 42);
        }
    }
}

#[test]
fn qualified_enum_variants_preserve_wide_and_symbolic_parent_headers() {
    let parameters = (0..32).map(|i| format!("T{i}")).collect::<Vec<_>>().join(", ");
    let definitions = format!("pub enum Wide<{parameters}> {{ Missing, Present(T0, T31) }}");
    let mut arguments = vec!["bool"; 32];
    arguments[0] = "str";
    arguments[31] = "[i32; 2]";
    let arguments = arguments.join(", ");
    for imported in [false, true] {
        let root = unit_value_stdlib(&definitions);
        let declarations = if imported { "import core::unit_values;" } else { &definitions };
        let prefix = if imported { "core::unit_values::" } else { "" };
        let source = format!(r#"
import std::io;
{declarations}
fn missing<{parameters}>() -> {prefix}Wide<{parameters}> {{
    return {prefix}Wide<{parameters}>::Missing;
}}
fn make<{parameters}>(first: T0, last: T31) -> {prefix}Wide<{parameters}> {{
    return {prefix}Wide<{parameters}>::Present(first, last);
}}
fn keep<T>(value: T) -> T {{ return value; }}
fn main() -> i32 {{
    let empty = missing<{arguments}>();
    let value = make<{arguments}>("hello", [41, 43]);
    let copied = keep(value);
    value = {prefix}Wide<{arguments}>::Missing();
    if (!(match (empty) {{ {prefix}Wide::Missing -> true, _ -> false }}) ||
        !(match (value) {{ {prefix}Wide::Missing -> true, _ -> false }})) {{ return 1; }}
    let text = match (copied) {{ {prefix}Wide::Present(text, values) -> text, _ -> "bad" }};
    std::io::println(text);
    let pair = match (copied) {{ {prefix}Wide::Present(text, values) -> values, _ -> [0, 0] }};
    return pair[0] + pair[1] - 42;
}}
"#);
        execute_with_stdlib(&format!("qualified wide symbolic headers imported={imported}"), &source, root.0.path(), b"hello\n", 42);
    }
}

#[test]
fn qualified_enum_variants_forward_symbolic_parameters() {
    let definitions = "pub enum Packet<T, const N: usize, F> { Absent, Data([T; N], F) }";
    for constructor in ["Data(values, flag)", "Packet::Data<T, N, F>(values, flag)", "Packet<T, N, F>::Data(values, flag)"] {
        for imported in [false, true] {
            let root = unit_value_stdlib(definitions);
            let declarations = if imported { "import core::unit_values;" } else { definitions };
            let prefix = if imported { "core::unit_values::" } else { "" };
            let source = format!(r#"
{declarations}
fn packet<T, const N: usize, F>(values: [T; N], flag: F) -> {prefix}Packet<T, N, F> {{
    return {prefix}{constructor};
}}
fn empty<T, const N: usize, F>() -> {prefix}Packet<T, N, F> {{
    return {prefix}Packet<T, N, F>::Absent;
}}
fn main() -> i32 {{
    let zero = empty<i32, 0, bool>();
    if (!(match (zero) {{ {prefix}Packet::Absent -> true, _ -> false }})) {{ return 1; }}
    let composed = packet([41, 43], true);
    let valid = match (composed) {{ {prefix}Packet::Data(values, flag) -> flag && values[0] == 41 && values[1] == 43, _ -> false }};
    if (!valid) {{ return 2; }}
    return 42;
}}
"#);
            execute_with_stdlib(&format!("symbolic {constructor}, imported={imported}"), &source, root.0.path(), b"", 42);
        }
    }
}

#[test]
fn qualified_enum_variants_reject_conflicting_parent_applications() {
    let declarations = "pub enum A<T> { Value(T), Missing } pub enum Packet<T, const N: usize, F> { Absent, Data([T; N], F) } pub enum Flag { On, Off }";
    for expression in ["A<bool>::Value(42)", "A<bool, i32>::Missing()", "A<bool, i32>::Missing", "A<bool>::Missing<i32>()", "Packet<i32, 2, bool>::Data([41, 43, 47], true)", "Packet<i32, bool, 2>::Absent()", "Packet<i32, bool, 2>::Absent", "Flag<bool>::On()", "Flag<bool>::Off"] {
        for imported in [false, true] {
            let root = unit_value_stdlib(declarations);
            let definitions = if imported { "import core::unit_values;" } else { declarations };
            let prefix = if imported { "core::unit_values::" } else { "" };
            let entry = common::TempArtifact::new("qualified_parent", "rejected", Some("lani"));
            entry.write_str(&format!("{definitions} fn main() -> i32 {{ let value = {prefix}{expression}; return 0; }}"));
            let entry = entry.path().to_owned(); let stdlib = root.0.path().to_owned();
            let error = common::run_gpu_codegen_with_timeout("qualified parent constraints", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
            }).expect_err("explicit parent operands must constrain the constructor");
            let diagnostic = error.to_public_diagnostic();
            assert!(matches!(diagnostic.code.as_str(), "LNC0006" | "LNC0027"), "{expression}, imported={imported}: {error:?}");
            assert!(diagnostic.primary_label.is_some(), "{error:?}");
        }
    }
}


#[test]
fn qualified_enum_variants_bind_qualifier_scope_before_members() {
    let root = ReceiverTestStdlib::new();
    std::fs::write(root.0.path().join("core/choices.lani"),
        "module core::choices; pub enum Choice<T> { Imported(T), Missing }").unwrap();
    std::fs::write(root.0.path().join("core/left.lani"),
        "module core::left; pub enum Choice<T> { Left(T), Missing }").unwrap();
    std::fs::write(root.0.path().join("core/right.lani"),
        "module core::right; pub enum Choice<T> { Right(T), Missing }").unwrap();
    let reject = |label: &str, source: &str| {
        let entry = common::TempArtifact::new("qualifier_scope", label, Some("lani"));
        entry.write_str(source);
        let entry_path = entry.path().to_owned(); let stdlib = root.0.path().to_owned();
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry_path, &stdlib))
        }).expect_err("an invalid qualifier must not emit code");
        let diagnostic = error.to_public_diagnostic();
        assert!(matches!(diagnostic.code.as_str(), "LNC0005" | "LNC0042"), "{label}: {error:?}");
        assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
    };
    for qualifier in ["Choice", "Choice<i32>"] {
        reject("local type shadows imported variant owner", &format!(
            "import core::choices; enum Choice<T> {{ Local(T) }} fn main() -> i32 {{ let wrong = {qualifier}::Imported(42); return 0; }}"));
    }
    execute_with_stdlib("local qualifier and explicit imported qualifier coexist", r#"
import core::choices;
enum Choice<T> { Local(T) }
fn main() -> i32 {
    let local = Choice<i32>::Local(19);
    let external = core::choices::Choice<i32>::Imported(23);
    return (match (local) { Choice::Local(v) -> v }) +
        (match (external) { core::choices::Choice::Imported(v) -> v, _ -> 0 });
}
"#, root.0.path(), b"", 42);
    for imports in ["import core::left; import core::right;", "import core::right; import core::left;"] {
        for expression in ["Choice<i32>::Left(42)", "Choice<i32>::Missing"] {
            reject("ambiguous type cannot be selected by member name", &format!(
                "{imports} fn main() -> i32 {{ let wrong = {expression}; return 0; }}"));
        }
        execute_with_stdlib("full qualifiers distinguish imported parents", &format!(r#"
{imports}
fn main() -> i32 {{
    let left = core::left::Choice<i32>::Left(19);
    let right = core::right::Choice<i32>::Right(23);
    return (match (left) {{ core::left::Choice::Left(v) -> v, _ -> 0 }}) +
        (match (right) {{ core::right::Choice::Right(v) -> v, _ -> 0 }});
}}
"#), root.0.path(), b"", 42);
    }
}


#[test]
fn generic_marker_blanket_impl_executes_scalar_and_compound_forwarding() {
    execute_with_status("generic marker blanket parameter root", r#"
struct Cell<T> { value: T }
trait Mark {}
impl<T> Mark for T {}
fn keep<T>(value: T) -> T where T: Mark { return value; }
fn forward<T>(value: T) -> T where T: Mark { return keep(value); }
fn main() -> i32 {
    let scalar = forward(19);
    let pair = forward([7, 11]);
    let cell: Cell<i32> = Cell { value: 23 };
    let copied = forward(cell);
    if (pair[0] != 7 || pair[1] != 11) { return 1; }
    return scalar + copied.value - 42;
}
"#, b"", 0);
}

#[test]
fn generic_marker_proof_dags_execute_nested_symbolic_forwarding() {
    execute_with_status("generic marker nested symbolic proof", r#"
struct Cell<T> { value: T }
trait Mark {}
impl Mark for i32 {}
impl<T> Mark for Cell<T> where T: Mark {}
impl<T, const N: usize> Mark for [T; N] where T: Mark {}
fn keep<T>(value: T) -> T where T: Mark { return value; }
fn lift<T>(value: T) -> Cell<T> where T: Mark {
    let cell: Cell<T> = Cell { value: value };
    return keep(cell);
}
fn main() -> i32 {
    let nested: Cell<Cell<i32>> = lift(lift(42));
    let pair = keep([19, 23]);
    let triple = keep([11, 13, 18]);
    if (pair[0] != 19 || pair[1] != 23 || triple[0] != 11 || triple[1] != 13 || triple[2] != 18) { return 1; }
    return nested.value.value - 42;
}
"#, b"", 0);
}

#[test]
fn generic_marker_proof_dags_execute_imported_provider_with_caller_owned_base() {
    let root = ReceiverTestStdlib::new();
    std::fs::write(root.0.path().join("core/generic_markers.lani"), r#"
module core::generic_markers;
pub struct Cell<T> { value: T }
pub trait Mark {}
pub impl<T> Mark for Cell<T> where T: Mark {}
pub fn keep<T>(value: T) -> T where T: Mark { return value; }
pub fn lift<T>(value: T) -> Cell<T> where T: Mark {
    let cell: Cell<T> = Cell { value: value };
    return keep(cell);
}
"#).expect("write marker-only generic provider");
    execute_with_stdlib("generic marker imported proof with caller base", r#"
import core::generic_markers;
pub impl core::generic_markers::Mark for i32 {}
fn main() -> i32 {
    let first = core::generic_markers::lift(19);
    let nested = core::generic_markers::lift(core::generic_markers::lift(23));
    return first.value + nested.value.value - 42;
}
"#, root.0.path(), b"", 0);
}

#[test]
fn generic_trait_methods_execute_inherited_environments_at_different_layouts() {
    execute_with_status("generic trait method inherited layouts", r#"
struct Cell<T> { value: T, result: i32 }
trait Read { fn read(&self) -> i32; }
impl<T> Read for Cell<T> { fn read(&self) -> i32 { return self.result; } }
fn main() -> i32 {
    let a: Cell<i32> = Cell { value: 7, result: 19 };
    let b: Cell<[i32;3]> = Cell { value: [1,2,3], result: 23 };
    return a.read() + b.read() - 42;
}
"#, b"", 0);
}

#[test]
fn generic_trait_methods_execute_imported_impl_bounds_from_caller() {
    let root = ReceiverTestStdlib::new();
    std::fs::write(root.0.path().join("core/generic_methods.lani"), r#"
module core::generic_methods;
pub struct Cell<T, const N: usize> { values: [T;N], result: i32 }
pub trait Mark {}
pub trait Read { pub fn read(&self) -> i32; }
pub impl<T, const N: usize> Read for Cell<T,N> where T: Mark {
    pub fn read(&self) -> i32 { return self.result; }
}
pub fn cell<T, const N: usize>(values: [T;N], result: i32) -> Cell<T,N> {
    return Cell { values: values, result: result };
}
"#).unwrap();
    execute_with_stdlib("imported generic trait method caller evidence", r#"
import core::generic_methods;
pub impl core::generic_methods::Mark for i32 {}
fn main() -> i32 {
    let a = core::generic_methods::cell([7], 19);
    let b = core::generic_methods::cell([1,2,3], 23);
    return a.read() + b.read() - 42;
}
"#, root.0.path(), b"", 0);
}

#[test]
fn inherent_method_bounds_keep_own_enclosing_and_shadowed_parameters_distinct() {
    execute_with_status("inherent method owned and enclosing bounds", r#"
trait Mark {}
trait Other {}
impl Mark for i32 {}
impl Other for bool {}
struct Cell<T> { value: T }
fn bounded<U>(value: U) -> U where U: Other { return value; }
fn marked<U>(value: U) -> U where U: Mark { return value; }
impl<T> Cell<T> where T: Mark {
    fn pick<U>(&self, value: U) -> U where U: Other {
        let checked: T = marked(self.value);
        return bounded(value);
    }
    fn inherited(&self) -> T where T: Mark { return marked(self.value); }
    fn shadow<T>(&self, value: T) -> T where T: Other { return bounded(value); }
}
fn main() -> i32 {
    let cell: Cell<i32> = Cell { value: 7 };
    if (!cell.pick(true) || cell.shadow(false)) { return 1; }
    return cell.inherited() - 7;
}
"#, b"", 0);
}

#[test]
fn generic_method_calls_require_every_inherited_and_own_prerequisite() {
    for (label, source) in [
        ("impl prerequisite", r#"
struct Cell<T> { value: T }
trait Mark {}
trait Read { fn read(&self) -> i32; }
impl<T> Read for Cell<T> where T: Mark { fn read(&self) -> i32 { return 42; } }
fn main() -> i32 { let cell: Cell<i32> = Cell { value: 7 }; return cell.read(); }
"#),
        ("method prerequisite", r#"
struct Cell<T> { value: T }
trait Mark {}
impl<T> Cell<T> { fn keep<U>(&self, value: U) -> U where U: Mark { return value; } }
fn main() -> i32 { let cell: Cell<i32> = Cell { value: 7 }; cell.keep(false); return 0; }
"#),
        ("constant shadows enclosing type", r#"
struct Cell<T> { value: T }
trait Mark {}
impl<T> Cell<T> { fn invalid<const T: usize>(&self) -> i32 where T: Mark { return 0; } }
fn main() -> i32 { return 0; }
"#),
    ] { reject_trait_program(label, source, "LNC0008"); }
}

#[test]
fn generic_trait_methods_keep_unimplemented_required_member_contracts_explicit() {
    reject_trait_program("own trait method generic header", r#"
trait Read { fn read<U>(value: U) -> U; }
fn main() -> i32 { return 0; }
"#, "LNC0021");
    reject_trait_program("trait method own prerequisite", r#"
trait Mark {}
trait Read<T> { fn read(value: T) -> T where T: Mark; }
fn main() -> i32 { return 0; }
"#, "LNC0021");
}

#[test]
fn generic_bound_member_calls_route_to_local_implementation_members() {
    // The uncalled body resolves `value.read()` to the required member and
    // stays a template; it publishes no native definition.
    execute("uncalled bound-member template", r#"
trait Read { fn read(&self) -> i32; }
fn via<T>(value: T) -> i32 where T: Read { return value.read(); }
fn main() -> i32 { return 0; }
"#);
    for (label, source) in [
        ("by-value member", include_str!("fixtures/generics_matrix/p12_generic_trait_bound.lani")),
        ("reference member", r#"
trait Read { fn read(&self) -> i32; }
struct Cell { v: i32 }
impl Read for Cell { fn read(&self) -> i32 { return self.v; } }
fn via<T>(value: T) -> i32 where T: Read { return value.read(); }
fn main() -> i32 { return via(Cell { v: 42 }); }
"#),
        ("scalar implementation", r#"
trait Twice { fn twice(self) -> i32; }
impl Twice for i32 { fn twice(self) -> i32 { return self + self; } }
fn go<T>(x: T) -> i32 where T: Twice { return x.twice(); }
fn main() -> i32 { return go(21); }
"#),
    ] {
        execute_with_status(label, source, b"", 42);
    }
}

#[test]
fn generic_bound_member_calls_reject_unroutable_implementations() {
    // A generic implementation needs its own call environment, which the
    // symbolic selection cannot have produced; it rejects instead of routing.
    reject_trait_program("generic implementation", r#"
trait Read { fn read(&self) -> i32; }
struct Box<U> { v: U, n: i32 }
impl<U> Read for Box<U> { fn read(&self) -> i32 { return self.n; } }
fn via<T>(value: T) -> i32 where T: Read { return value.read(); }
fn main() -> i32 { return via(Box { v: true, n: 0 }); }
"#, "LNC0027");
}


#[test]
fn generic_marker_proof_dags_reject_overlap_missing_base_and_cycles_before_elf() {
    for (label, source, code) in [
        ("generic marker overlap ignores differing prerequisites", r#"
struct Cell<T> { value: T }
trait Mark {}
trait Left {}
trait Right {}
impl<T> Mark for Cell<T> where T: Left {}
impl<T> Mark for Cell<T> where T: Right {}
fn main() -> i32 { return 0; }
"#, "LNC0017"),
        ("generic marker wrapper needs a base proof", r#"
struct Cell<T> { value: T }
trait Mark {}
impl<T> Mark for Cell<T> where T: Mark {}
fn keep<T>(value: T) -> T where T: Mark { return value; }
fn main() -> i32 {
    let value: Cell<i32> = Cell { value: 42 };
    let copied = keep(value);
    return copied.value;
}
"#, "LNC0008"),
        ("generic marker recursive prerequisite is not a proof", r#"
trait Mark {}
impl<T> Mark for T where T: Mark {}
fn keep<T>(value: T) -> T where T: Mark { return value; }
fn main() -> i32 { return keep(42); }
"#, "LNC0008"),
    ] {
        let source = source.to_owned();
        // Each case gets a fresh compiler; no malformed state is reused and no
        // successful receipt is fabricated to skip the native publication gate.
        let error = common::run_gpu_codegen_with_timeout(label, move || {
            let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                .expect("GPU compiler");
            pollster::block_on(compiler.compile_source_to_x86_64(&source))
        }).expect_err("unproved or incoherent marker contract must not return ELF bytes");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, code, "{label}: {error:?}");
        if code == "LNC0017" {
            assert!(diagnostic.notes.iter().any(|note|
                note.contains("program catalog GPU admission/coherence failed: [5,")),
                "zero-call program must fail global head coherence: {error:?}");
        } else {
            assert!(diagnostic.primary_label.is_some(),
                "missing or cyclic proof must identify the retained call: {error:?}");
        }
    }
}

#[test]
fn generic_trait_operands_and_results_execute_imported_compound_copies() {
    let root = ReceiverTestStdlib::new();
    std::fs::write(
        root.0.path().join("core/trait_result.lani"),
        r#"
module core::trait_result;
pub struct Cell<T> { before: i32, value: T, after: i32 }
pub trait Read<R> { pub fn read(&self) -> R; }
pub impl<T> Read<T> for Cell<T> {
    pub fn read(&self) -> T { return self.value; }
}
pub fn cell<T>(value: T, before: i32, after: i32) -> Cell<T> {
    return Cell { before: before, value: value, after: after };
}
"#,
    )
    .expect("write public generic trait result provider");
    execute_with_stdlib(
        "imported trait operand and compound result copies",
        r#"
import core::trait_result;
struct Inner<T> { values: T }
struct Packet { nested: Inner<[i32;2]>, flags: [bool;3], tail: i32 }
fn main() -> i32 {
    let a = core::trait_result::cell([19,-23,41], 1009, 1013);
    let payload: Packet = Packet {
        nested: Inner { values: [67,-71] }, flags: [true,false,true], tail: 73
    };
    let b = core::trait_result::cell(payload, 2003, 2011);
    // No result annotations: each imported read must retain its complete T.
    let first = a.read();
    let second = b.read();
    a.value = [53,59,61];
    b.value = Packet {
        nested: Inner { values: [79,83] }, flags: [false,true,false], tail: 89
    };
    if (first[0] != 19 || first[1] != -23 || first[2] != 41) { return 1; }
    if (second.nested.values[0] != 67 || second.nested.values[1] != -71 ||
        !second.flags[0] || second.flags[1] || !second.flags[2] || second.tail != 73) { return 2; }
    first[0] = 97;
    second.nested.values[1] = -101;
    let updated_a = a.read();
    let updated_b = b.read();
    if (updated_a[0] != 53 || updated_a[1] != 59 || updated_a[2] != 61) { return 3; }
    if (updated_b.nested.values[0] != 79 || updated_b.nested.values[1] != 83 ||
        updated_b.flags[0] || !updated_b.flags[1] || updated_b.flags[2] || updated_b.tail != 89) { return 4; }
    if (a.before != 1009 || a.after != 1013 || b.before != 2003 || b.after != 2011) { return 5; }
    return 0;
}
"#,
        root.0.path(),
        b"",
        0,
    );
}

#[test]
fn generic_trait_method_calls_reject_unbound_impl_trait_operands() {
    // R is a legitimate impl-header member because it occurs in the trait
    // operand. Neither Cell<T> nor tag's arguments/result can bind it. Direct
    // lookup must not invent an implementation argument from the receiver.
    reject_trait_program(
        "impl trait operand has no method-call binding",
        r#"
struct Cell<T> { value: T }
trait Tag<R> { fn tag(&self) -> i32; }
impl<T,R> Tag<R> for Cell<T> { fn tag(&self) -> i32 { return 7; } }
fn main() -> i32 {
    let cell: Cell<i32> = Cell { value: 19 };
    return cell.tag();
}
"#,
        "LNC0006",
    );
}

#[test]
fn generic_impl_qualified_prerequisites_respect_source_module_visibility() {
    // No import: public qualified trait bounds deliberately use the predicate
    // fallback, while the same private trait must remain inaccessible.
    let consumer = r#"
module app;
struct Cell<T> { value: T }
trait Local {}
impl<T> Local for Cell<T> where T: hidden::Gate {}
fn keep<T>(value: T) -> T where T: Local { return value; }
fn main() -> i32 {
    let original: Cell<i32> = Cell { value: 42 };
    let copied = keep(original);
    return copied.value - 42;
}
"#;
    for public in [true, false] {
        let visibility = if public { "pub " } else { "" };
        let provider = format!(
            "module hidden; {visibility}trait Gate {{}} {visibility}impl Gate for i32 {{}}"
        );
        let consumer = consumer.to_owned();
        let compiled = common::run_gpu_codegen_with_timeout(
            "qualified generic impl prerequisite visibility",
            move || {
                let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
                    .expect("GPU compiler");
                pollster::block_on(compiler.compile_source_pack_to_x86_64(&[provider, consumer]))
            },
        );
        if public {
            let elf = compiled.expect("public qualified prerequisite works without an import");
            let output = common::run_x86_64_elf_output(
                "qualified generic impl prerequisite",
                "generic_module_visibility",
                &elf,
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                output.stdout.is_empty() && output.stderr.is_empty(),
                "{output:?}"
            );
        } else {
            let error = compiled.expect_err("foreign private prerequisite must not emit an ELF");
            let diagnostic = error.to_public_diagnostic();
            assert_eq!(diagnostic.code, "LNC0008", "{error:?}");
            assert!(diagnostic.primary_label.is_some(), "{error:?}");
        }
    }
}

// Primitive-width migration acceptance: compile and execute native programs.
macro_rules! primitive_width_success {
    ($name:ident, $file:literal) => {
        #[test]
        fn $name() {
            execute(stringify!($name), include_str!(concat!("fixtures/stdlib_foundation/native_primitive_width/", $file)));
        }
    };
}
macro_rules! primitive_width_trap {
    ($name:ident, $file:literal, $status:literal) => {
        #[test]
        fn $name() {
            execute_with_status(stringify!($name), include_str!(concat!("fixtures/stdlib_foundation/native_primitive_width/traps/", $file)), b"", $status);
        }
    };
}
fn reject_primitive_width_fixture(label: &str, source: &str, code: &str, magnitude: Option<&str>) {
    let owned = source.to_owned();
    let error = common::run_gpu_codegen_with_timeout(label, move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).expect("GPU compiler");
        pollster::block_on(compiler.compile_source_to_x86_64(&owned))
    }).err().unwrap_or_else(|| panic!("{label}: invalid source emitted an executable"));
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, code, "{label}: {error:?}");
    let primary = diagnostic.primary_label.as_ref().unwrap_or_else(|| panic!("{label}: missing source label: {error:?}"));
    if let Some(magnitude) = magnitude {
        let start = source.find(magnitude).expect("fixture magnitude");
        let end = start + magnitude.len();
        let label_start = primary.byte_start.expect("literal byte start");
        let label_end = primary.byte_end.expect("literal byte end");
        assert!(label_start < end && label_end > start,
            "{label}: diagnostic must identify the offending literal: {diagnostic:?}");
    }
}
macro_rules! primitive_width_reject {
    ($name:ident, $file:literal, $code:literal, $magnitude:expr) => {
        #[test]
        fn $name() {
            reject_primitive_width_fixture(stringify!($name), include_str!(concat!("fixtures/stdlib_foundation/native_primitive_width/reject/", $file)), $code, $magnitude);
        }
    };
}
primitive_width_success!(native_primitive_width_literal_roundtrip, "literal-roundtrip.lani");
primitive_width_success!(native_primitive_width_operators, "operators.lani");
primitive_width_success!(native_primitive_width_generic_composition, "generic-composition.lani");
primitive_width_success!(native_primitive_width_contextual_arithmetic, "contextual-arithmetic.lani");
primitive_width_success!(native_primitive_width_narrow_normalization, "narrow-normalization.lani");

#[test]
fn native_primitive_width_imported_values_and_stack_arguments() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/native_primitive_width/imported/stdlib");
    execute_with_stdlib("primitive imported values and stack arguments",
        include_str!("fixtures/stdlib_foundation/native_primitive_width/imported/main.lani"),
        &root, b"", 0);
}
primitive_width_trap!(native_primitive_width_trap_shift_width, "shift-width.lani", 102);
primitive_width_trap!(native_primitive_width_trap_shift_high_count, "shift-high-count.lani", 102);
primitive_width_trap!(native_primitive_width_trap_shift_negative_count, "shift-negative-count.lani", 102);
primitive_width_trap!(native_primitive_width_trap_division_zero, "division-zero.lani", 103);
primitive_width_trap!(native_primitive_width_trap_signed_division_overflow, "signed-division-overflow.lani", 104);
primitive_width_trap!(native_primitive_width_trap_signed_remainder_overflow, "signed-remainder-overflow.lani", 104);
primitive_width_trap!(native_primitive_width_trap_array_index_high, "array-index-high.lani", 101);
primitive_width_trap!(native_primitive_width_trap_slice_index_high, "slice-index-high.lani", 101);
primitive_width_reject!(native_primitive_width_reject_u64_overflow, "u64-overflow.lani", "LNC0069", Some("18446744073709551616"));
primitive_width_reject!(native_primitive_width_reject_i64_positive_overflow, "i64-positive-overflow.lani", "LNC0069", Some("9223372036854775808"));
primitive_width_reject!(native_primitive_width_reject_i64_negative_overflow, "i64-negative-overflow.lani", "LNC0069", Some("9223372036854775809"));
primitive_width_reject!(native_primitive_width_reject_u32_overflow, "u32-overflow.lani", "LNC0069", Some("4294967296"));
primitive_width_reject!(native_primitive_width_reject_i8_positive_overflow, "i8-positive-overflow.lani", "LNC0069", Some("128"));
primitive_width_reject!(native_primitive_width_reject_i8_negative_overflow, "i8-negative-overflow.lani", "LNC0069", Some("129"));
primitive_width_reject!(native_primitive_width_reject_u8_overflow, "u8-overflow.lani", "LNC0069", Some("256"));
primitive_width_reject!(native_primitive_width_reject_i16_positive_overflow, "i16-positive-overflow.lani", "LNC0069", Some("32768"));
primitive_width_reject!(native_primitive_width_reject_i16_negative_overflow, "i16-negative-overflow.lani", "LNC0069", Some("32769"));
primitive_width_reject!(native_primitive_width_reject_u16_overflow, "u16-overflow.lani", "LNC0069", Some("65536"));
primitive_width_reject!(native_primitive_width_reject_unsigned_negative, "unsigned-negative.lani", "LNC0069", Some("1"));
primitive_width_reject!(native_primitive_width_reject_default_i32_overflow, "default-i32-overflow.lani", "LNC0069", Some("2147483648"));
primitive_width_reject!(native_primitive_width_reject_array_extent_overflow, "array-extent-overflow.lani", "LNC0069", Some("4294967296"));
primitive_width_reject!(native_primitive_width_reject_named_call_coercion, "named-call-coercion.lani", "LNC0006", None);
primitive_width_reject!(native_primitive_width_reject_mixed_arithmetic_coercion, "mixed-arithmetic-coercion.lani", "LNC0006", None);
primitive_width_reject!(native_primitive_width_reject_named_field_coercion, "named-field-coercion.lani", "LNC0006", None);
primitive_width_reject!(native_primitive_width_reject_named_generic_coercion, "named-generic-coercion.lani", "LNC0006", None);
primitive_width_reject!(native_primitive_width_reject_deep_named_arithmetic_coercion, "deep-named-arithmetic-coercion.lani", "LNC0006", None);
primitive_width_reject!(native_primitive_width_reject_named_signed_unsigned_coercion, "named-signed-unsigned-coercion.lani", "LNC0006", None);
primitive_width_reject!(native_primitive_width_reject_named_integer_float_coercion, "named-integer-float-coercion.lani", "LNC0006", None);
primitive_width_success!(native_primitive_width_literal_spellings, "literal-spellings.lani");
primitive_width_reject!(native_primitive_width_reject_hex_overflow, "hex-overflow.lani", "LNC0069", Some("0x1_0000_0000_0000_0000"));
primitive_width_reject!(native_primitive_width_reject_binary_overflow, "binary-overflow.lani", "LNC0069", Some("0b1_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000"));
primitive_width_reject!(native_primitive_width_reject_octal_overflow, "octal-overflow.lani", "LNC0069", Some("0O2_000_000_000_000_000_000_000"));
primitive_width_reject!(native_primitive_width_reject_separated_decimal_overflow, "separated-decimal-overflow.lani", "LNC0069", Some("18_446_744_073_709_551_616"));

#[test]
fn native_primitive_width_unit_compositions_preserve_effects_and_sentinels() {
    execute_with_status(
        "unit generic values, compound returns, and stack argument",
        include_str!("fixtures/stdlib_foundation/native_primitive_width/unit-composition.lani"),
        b"11\n12\n13\n14\n15\n17\n",
        0,
    );
}

#[test]
fn native_primitive_width_reject_imported_named_scalar_coercion() {
    let source = include_str!("fixtures/stdlib_foundation/native_primitive_width/imported/reject-named-scalar.lani");
    let entry = common::TempArtifact::new("primitive_width", "imported_named_scalar", Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/native_primitive_width/imported/stdlib");
    let error = common::run_gpu_codegen_with_timeout("imported named scalar coercion", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    }).err().expect("an imported signature must not coerce a named scalar");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0006", "{error:?}");
    assert!(diagnostic.primary_label.is_some(), "{error:?}");
}

// Range induction acceptance: compile and execute native programs.
macro_rules! range_width_success {
    ($name:ident, $file:literal) => {
        #[test]
        fn $name() {
            execute(stringify!($name), include_str!(concat!("fixtures/stdlib_foundation/native_range_width/", $file)));
        }
    };
}
macro_rules! range_width_imported_success {
    ($name:ident, $file:literal) => {
        #[test]
        fn $name() {
            let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("tests/fixtures/stdlib_foundation/native_range_width/named/stdlib");
            execute_with_stdlib(stringify!($name), include_str!(concat!("fixtures/stdlib_foundation/native_range_width/", $file)),
                &root, b"", 0);
        }
    };
}
range_width_success!(native_range_width_direct_wide, "direct-wide.lani");
range_width_success!(native_range_width_narrow, "narrow.lani");
range_width_success!(native_range_width_bound_snapshot, "bound-snapshot.lani");
range_width_success!(native_range_width_postfix_endpoints, "postfix-endpoints.lani");
range_width_success!(native_range_width_open_ended, "open-ended.lani");
range_width_imported_success!(native_range_width_named, "named/main.lani");
range_width_imported_success!(native_range_width_repeated_empty_inclusive, "named/repeated-empty-inclusive.lani");

range_width_success!(native_range_reduced_direct_empty_return, "reduced/direct-empty-return.lani");
range_width_success!(native_range_reduced_direct_nonempty_return, "reduced/direct-nonempty-return.lani");
range_width_imported_success!(native_range_reduced_named_empty_return, "reduced/named-empty-return.lani");
range_width_imported_success!(native_range_reduced_named_nonempty_return, "reduced/named-nonempty-return.lani");
range_width_success!(native_range_reduced_open_terminal_continue, "reduced/open-terminal-continue.lani");
range_width_success!(native_range_reduced_full_range_break, "reduced/full-range-break.lani");
range_width_success!(native_range_reduced_compound_break_paths, "reduced/compound-break-paths.lani");
range_width_success!(native_range_reduced_nested_postfix_endpoints, "reduced/nested-postfix-endpoints.lani");
range_width_success!(native_range_reduced_nested_terminal_continue, "reduced/nested-terminal-continue.lani");
range_width_success!(native_range_reduced_dead_call, "reduced/dead-call.lani");
range_width_success!(native_range_reduced_dead_aggregate, "reduced/dead-aggregate.lani");

// These are executable native acceptance, not type-check-only float admission.
// The GPU decimal helper has its independent bit-oracle test package.
macro_rules! float_payload_success {
    ($name:ident, $file:literal) => {
        #[test]
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        fn $name() {
            execute(stringify!($name), include_str!(concat!("fixtures/stdlib_foundation/native_float_payload/", $file)));
        }
    };
}
float_payload_success!(native_float_payload_option_scalars, "option-scalars.lani");
float_payload_success!(native_float_payload_nested_results, "nested-results.lani");
float_payload_success!(native_float_payload_arithmetic_f64, "arithmetic-f64.lani");
float_payload_success!(native_float_payload_arithmetic_f32, "arithmetic-f32.lani");
float_payload_success!(native_float_payload_literal_contexts, "literal-contexts.lani");
float_payload_success!(native_float_payload_portable_literals, "portable-literals.lani");

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn native_float_payload_imported_stack_arguments_and_copies() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/native_float_payload/imported/stdlib");
    execute_with_stdlib("native_float_payload_imported_stack_arguments_and_copies",
        include_str!("fixtures/stdlib_foundation/native_float_payload/imported/main.lani"),
        &root, b"", 0);
}

macro_rules! float_payload_reject {
    ($name:ident, $file:literal, $code:literal) => {
        #[test]
        fn $name() {
            let entry = common::TempArtifact::new("float_payload_reject", stringify!($name), Some("lani"));
            entry.write_str(include_str!(concat!("fixtures/stdlib_foundation/native_float_payload/", $file)));
            let path = entry.path().to_path_buf();
            let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
            let error = common::run_gpu_codegen_with_timeout(stringify!($name), move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            }).expect_err("invalid float program must not emit an executable");
            let diagnostic = error.to_public_diagnostic();
            assert_eq!(diagnostic.code, $code, "{error:?}");
            assert!(diagnostic.primary_label.is_some(), "{error:?}");
        }
    };
}
float_payload_reject!(native_float_payload_reject_named_width, "reject-named-width.lani", "LNC0006");
float_payload_reject!(native_float_payload_reject_named_option_width, "reject-named-option-width.lani", "LNC0006");
float_payload_reject!(native_float_payload_reject_f32_overflow, "reject-f32-overflow.lani", "LNC0070");
float_payload_reject!(native_float_payload_reject_f64_overflow, "reject-f64-overflow.lani", "LNC0070");
float_payload_reject!(native_float_payload_reject_computed_constant, "reject-computed-constant.lani", "LNC0071");

fn reject_portable_constant_fixture(label: &str, source: &str, stdlib: &std::path::Path) {
    let entry = common::TempArtifact::new("portable_typed_constants", label, Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let root = stdlib.to_path_buf();
    let error = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &root))
    })
    .expect_err("a mismatched imported constant contract must not emit an ELF");
    let laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) = error else {
        panic!("{label}: expected a language diagnostic: {error:?}");
    };
    assert_eq!(diagnostic.code, "LNC0006", "{label}: {diagnostic:?}");
    assert!(diagnostic.primary_label.is_some(), "{label}: {diagnostic:?}");
}

#[test]
fn imported_portable_constants_execute_full_values_and_preserve_declared_scalars() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/portable_typed_constants/typed_values/stdlib");
    execute_with_stdlib(
        "imported typed constants and nested nominal forwarding",
        include_str!("fixtures/stdlib_foundation/portable_typed_constants/typed_values/main.lani"),
        &root,
        b"",
        0,
    );
}

#[test]
fn imported_portable_constants_reject_named_scalar_mismatch() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/portable_typed_constants/typed_values/stdlib");
    reject_portable_constant_fixture(
        "imported named u32 cannot bind a u64 constant parameter",
        include_str!("fixtures/stdlib_foundation/portable_typed_constants/typed_values/reject_named_scalar.lani"),
        &root,
    );
}

#[test]
fn imported_portable_array_elements_preserve_slice_borrows() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/portable_typed_constants/nested_slice/stdlib");
    execute_with_stdlib(
        "imported slice with constant array elements",
        include_str!("fixtures/stdlib_foundation/portable_typed_constants/nested_slice/main.lani"),
        &root,
        b"",
        0,
    );
}

#[test]
fn imported_portable_slice_borrow_rejects_wrong_inner_array_length() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/portable_typed_constants/nested_slice/stdlib");
    reject_portable_constant_fixture(
        "root slice borrow cannot change nested array length",
        include_str!("fixtures/stdlib_foundation/portable_typed_constants/nested_slice/reject_inner_length.lani"),
        &root,
    );
}

#[test]
fn local_typed_constants_execute_full_width_and_signed_operands() {
    execute(
        "local typed constants execute full width and signed operands",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/explicit-constant-source-v1/runtime_typed_operands.lani"),
    );
}

#[test]
fn array_count_projection_executes_named_inferred_and_forwarded_values() {
    execute(
        "array count projection executes named inferred and forwarded values",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/array-source-consumers-v1/runtime_count_identity.lani"),
    );
}

#[test]
fn array_count_projection_preserves_empty_arrays() {
    execute(
        "array count projection preserves empty arrays",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/array-source-consumers-v1/runtime_empty_count.lani"),
    );
}

#[test]
fn typed_array_receiver_executes_through_adjusted_borrow() {
    execute(
        "typed array receiver executes through adjusted borrow",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/array-native-readers-v1/runtime_adjusted_receiver.lani"),
    );
}

#[test]
fn typed_array_enum_fields_preserve_layout_and_following_fields() {
    execute(
        "typed array enum fields preserve layout and following fields",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/array-native-readers-v1/runtime_enum_array_field.lani"),
    );
}

#[test]
fn array_only_inference_preserves_nested_count_projection() {
    execute(
        "array only inference preserves nested count projection",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/constant-claim-provenance-v1/runtime_array_only_nested_count.lani"),
    );
}

#[test]
fn ordinary_constant_identity_wins_over_count_claim_in_both_orders() {
    execute(
        "ordinary constant identity wins over count claim in both orders",
        include_str!("fixtures/stdlib_foundation/typed_constant_transport/constant-claim-provenance-v1/runtime_mixed_claim_priority.lani"),
    );
}

#[test]
fn typed_constant_implementation_count_accepts_zero_and_u8_boundary() {
    execute(
        "typed constant implementation count accepts zero and u8 boundary",
        include_str!("fixtures/stdlib_foundation/typed_owned_constants/array_count_impl_boundary.lani"),
    );
}

#[test]
fn typed_constant_prerequisite_normalizes_owned_count_projection() {
    execute(
        "typed constant prerequisite normalizes owned count projection",
        include_str!("fixtures/stdlib_foundation/typed_owned_constants/array_count_impl_prerequisite.lani"),
    );
}

#[test]
fn typed_constant_implementation_count_rejects_u8_overflow() {
    reject_trait_program(
        "array count cannot bind an overflowing u8 implementation constant",
        include_str!("fixtures/stdlib_foundation/typed_owned_constants/array_count_impl_overflow.lani"),
        "LNC0008",
    );
}

#[test]
fn float_constant_operands_select_declared_width_and_preserve_bits() {
    execute(
        "direct float constant widths, rounding, subnormals and signed zero",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/direct.lani"),
    );
}

#[test]
fn named_float_constants_preserve_annotation_through_generic_forwarding() {
    execute(
        "named float constants and generic forwarding",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/named.lani"),
    );
}

#[test]
fn imported_float_constants_preserve_bits_through_nested_generic_nominals() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/typed_float_constants/imported/stdlib");
    execute_with_stdlib(
        "imported float constants and nested nominal forwarding",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/imported/main.lani"),
        &root,
        b"",
        0,
    );
}

#[test]
fn float_constant_operands_reject_named_scalar_mismatch() {
    reject_trait_program(
        "named f32 cannot bind an f64 constant parameter",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/reject_named_width.lani"),
        "LNC0006",
    );
}

#[test]
fn float_constant_identity_distinguishes_signed_zero() {
    reject_trait_program(
        "generic constant identity distinguishes positive and negative zero",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/reject_zero_identity.lani"),
        "LNC0006",
    );
}

#[test]
fn float_constant_operands_reject_f32_overflow() {
    reject_trait_program(
        "f32 generic constant rejects an overflowing literal",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/reject_f32_overflow.lani"),
        "LNC0027",
    );
}

#[test]
fn float_constant_operands_reject_f64_overflow() {
    reject_trait_program(
        "f64 generic constant rejects an overflowing literal",
        include_str!("fixtures/stdlib_foundation/typed_float_constants/reject_f64_overflow.lani"),
        "LNC0027",
    );
}
