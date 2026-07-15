mod common;

use laniusc_compiler::{
    codegen::{
        unit::{
            CodegenUnitLimits,
            SourcePackArtifactTarget,
            SourcePackBuildShardLimits,
            SourcePackJob,
            SourcePackJobBatchLimits,
            SourcePackJobPhase,
            SourcePackLinkObjectBatch,
        },
        wasm::{GpuWasmRelocatableObject, GpuWasmRelocationTargetKind},
        x86::{GpuX86ObjectSection, GpuX86RelocatableObject, GpuX86RelocationTargetKind},
    },
    compiler::{
        AsyncPagedArtifactBuildExecutor,
        CompileError,
        EntrySourceRoots,
        ExplicitSourceLibraryPathStream,
        ExplicitSourcePathFile,
        GpuCompiler,
        GpuSemanticInterfaceArtifact,
        GpuSemanticInterfaceMemberKind,
        GpuSemanticInterfaceTypeKind,
        GpuSourcePackArtifactDescriptor,
        GpuSourcePackArtifactExecutor,
        GpuSourcePackCodegenObjectFormat,
        load_entry_path_manifest_with_source_root,
        load_entry_path_manifest_with_source_root_and_stdlib,
        load_entry_path_manifest_with_stdlib,
        load_entry_with_source_root,
        load_entry_with_source_roots,
        load_entry_with_stdlib,
        run_path_stream_worker_to_wasm,
        run_path_stream_worker_to_x86_64,
        type_check_entry_with_source_root,
        type_check_entry_with_source_roots,
        type_check_entry_with_stdlib,
    },
};

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking:\n{src}"),
        Err(CompileError::Diagnostic(_)) => {}
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
        Err(CompileError::Diagnostic(_)) => {}
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_accepts(sources: &[&str]) {
    common::type_check_source_pack_with_timeout(sources)
        .unwrap_or_else(|err| panic!("source pack should pass GPU type checking: {err:?}"));
}

fn semantic_interface_name<'a>(bytes: &'a [u8], start: u32, len: u32) -> &'a str {
    let start = start as usize;
    let end = start + len as usize;
    std::str::from_utf8(&bytes[start..end]).expect("validated interface name should be UTF-8")
}

#[test]
fn semantic_interface_exports_public_checked_graph_on_gpu() {
    let artifact = common::semantic_interface_with_timeout(
        37,
        &[
            r#"module core::math;
pub fn visible(value: i32) -> i32 { return value; }
pub fn transform(values: [i32; 4]) -> [i32; 4] { return values; }
pub fn notify(value: i32) { return; }
pub fn keep<T>(value: T) -> T { return value; }
pub fn keep_array<T, const N: usize>(values: [T; N]) -> [T; N] { return values; }
pub struct Boxed<T> {
    value: T,
}
fn hidden() -> i32 { return 0; }
fn hidden_array() -> i32 {
    let local: [i32; 4] = [1, 2, 3, 4];
    return local[0];
}
pub const ANSWER: i32 = 42;
pub enum Signal {
    Stop,
    Go(i32),
}
"#,
            r#"module app::main;
import core::math;
fn main() -> i32 { return visible(ANSWER); }
"#,
        ],
    )
    .expect("GPU semantic-interface export should succeed");

    assert_eq!(artifact.library_id, 37);
    assert_eq!(artifact.modules.len(), 2);
    let declaration_names = artifact
        .declarations
        .iter()
        .map(|declaration| {
            semantic_interface_name(
                &artifact.name_bytes,
                declaration.name_byte_start,
                declaration.name_byte_len,
            )
        })
        .collect::<std::collections::BTreeSet<_>>();
    assert!(declaration_names.contains("visible"));
    assert!(declaration_names.contains("transform"));
    assert!(declaration_names.contains("notify"));
    assert!(declaration_names.contains("keep"));
    assert!(declaration_names.contains("keep_array"));
    assert!(declaration_names.contains("Boxed"));
    assert!(declaration_names.contains("ANSWER"));
    assert!(declaration_names.contains("Signal"));
    assert!(declaration_names.contains("Stop"));
    assert!(declaration_names.contains("Go"));
    assert!(!declaration_names.contains("hidden"));
    assert!(!declaration_names.contains("hidden_array"));
    assert!(!declaration_names.contains("main"));
    assert!(
        artifact
            .declarations
            .iter()
            .all(|declaration| declaration.signature_type != u32::MAX),
        "every exported declaration should reference its GPU-materialized signature type"
    );
    let member_count = |name: &str| {
        artifact
            .declarations
            .iter()
            .find(|declaration| {
                semantic_interface_name(
                    &artifact.name_bytes,
                    declaration.name_byte_start,
                    declaration.name_byte_len,
                ) == name
            })
            .map(|declaration| declaration.member_count)
            .unwrap_or(u32::MAX)
    };
    assert_eq!(
        member_count("keep"),
        2,
        "generic parameter plus value parameter"
    );
    assert_eq!(
        member_count("keep_array"),
        3,
        "type parameter, const parameter, and value parameter"
    );
    assert_eq!(member_count("Boxed"), 2, "generic parameter plus field");
    assert_eq!(member_count("Signal"), 2, "two enum variants");

    let declaration_index = |name: &str| {
        artifact
            .declarations
            .iter()
            .position(|declaration| {
                semantic_interface_name(
                    &artifact.name_bytes,
                    declaration.name_byte_start,
                    declaration.name_byte_len,
                ) == name
            })
            .expect("expected exported declaration")
    };
    let keep_declaration = artifact.declarations[declaration_index("keep")];
    let keep_signature = artifact.types[keep_declaration.signature_type as usize];
    let keep_type_edges = &artifact.type_edges[keep_signature.first_edge as usize
        ..(keep_signature.first_edge + keep_signature.edge_count) as usize];
    assert_eq!(
        keep_type_edges.len(),
        2,
        "parameter followed by return type"
    );
    for edge in keep_type_edges {
        let ty = artifact.types[edge.type_index as usize];
        assert_eq!(
            ty.kind,
            GpuSemanticInterfaceTypeKind::GenericParameter as u32
        );
        assert_eq!(
            ty.payload_lo, keep_declaration.first_member,
            "generic parameter uses must identify the owning declaration member"
        );
    }
    let boxed_declaration = artifact.declarations[declaration_index("Boxed")];
    let boxed_field = artifact.members[(boxed_declaration.first_member + 1) as usize];
    let boxed_field_type = artifact.types[boxed_field.type_index as usize];
    assert_eq!(
        boxed_field_type.payload_lo, boxed_declaration.first_member,
        "same-named generic parameters from different declarations must not alias"
    );
    assert!(artifact.types.iter().all(|ty| {
        ty.kind != GpuSemanticInterfaceTypeKind::Declaration as u32
            || ty.payload_lo != artifact.library_id
            || ty.nominal_unit_id == artifact.unit_id
    }));

    let members_of = |declaration_name: &str| {
        let declaration = artifact
            .declarations
            .iter()
            .find(|declaration| {
                semantic_interface_name(
                    &artifact.name_bytes,
                    declaration.name_byte_start,
                    declaration.name_byte_len,
                ) == declaration_name
            })
            .expect("expected exported declaration");
        let first = declaration.first_member as usize;
        let end = first + declaration.member_count as usize;
        artifact.members[first..end]
            .iter()
            .map(|member| {
                (
                    semantic_interface_name(
                        &artifact.name_bytes,
                        member.name_byte_start,
                        member.name_byte_len,
                    ),
                    member.kind,
                )
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(
        members_of("keep"),
        vec![
            (
                "T",
                GpuSemanticInterfaceMemberKind::GenericTypeParameter as u32
            ),
            ("value", GpuSemanticInterfaceMemberKind::Parameter as u32),
        ]
    );
    assert_eq!(
        members_of("keep_array"),
        vec![
            (
                "T",
                GpuSemanticInterfaceMemberKind::GenericTypeParameter as u32
            ),
            (
                "N",
                GpuSemanticInterfaceMemberKind::GenericConstParameter as u32
            ),
            ("values", GpuSemanticInterfaceMemberKind::Parameter as u32),
        ]
    );
    assert_eq!(
        members_of("Boxed"),
        vec![
            (
                "T",
                GpuSemanticInterfaceMemberKind::GenericTypeParameter as u32
            ),
            ("value", GpuSemanticInterfaceMemberKind::Field as u32),
        ]
    );
    assert_eq!(
        members_of("Signal"),
        vec![
            ("Stop", GpuSemanticInterfaceMemberKind::EnumVariant as u32),
            ("Go", GpuSemanticInterfaceMemberKind::EnumVariant as u32),
        ]
    );

    let signal_index = artifact
        .declarations
        .iter()
        .position(|declaration| {
            semantic_interface_name(
                &artifact.name_bytes,
                declaration.name_byte_start,
                declaration.name_byte_len,
            ) == "Signal"
        })
        .expect("public enum should have a persisted declaration index");
    for variant_name in ["Stop", "Go"] {
        let variant = artifact
            .declarations
            .iter()
            .find(|declaration| {
                semantic_interface_name(
                    &artifact.name_bytes,
                    declaration.name_byte_start,
                    declaration.name_byte_len,
                ) == variant_name
            })
            .expect("public enum variant should be exported");
        assert_eq!(variant.owner_declaration, signal_index as u32);
    }

    let module_paths = artifact
        .modules
        .iter()
        .map(|module| {
            let first = module.first_segment as usize;
            let end = first + module.segment_count as usize;
            artifact.module_segments[first..end]
                .iter()
                .map(|segment| {
                    semantic_interface_name(
                        &artifact.name_bytes,
                        segment.name_byte_start,
                        segment.name_byte_len,
                    )
                })
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    assert!(module_paths.iter().any(|path| path == &["core", "math"]));
    assert!(module_paths.iter().any(|path| path == &["app", "main"]));

    let encoded = artifact
        .to_bytes()
        .expect("complete GPU semantic interface should serialize");
    let decoded = laniusc_compiler::compiler::GpuSemanticInterfaceArtifact::from_bytes(&encoded)
        .expect("serialized GPU semantic interface should decode");
    assert_eq!(decoded, artifact);
}

#[test]
fn dependency_nominals_from_distinct_units_of_one_library_do_not_alias() {
    let alpha = common::semantic_interface_with_timeout(
        7,
        &[r#"module alpha::api;
pub struct AlphaToken { value: i32 }
pub fn accept_alpha(value: AlphaToken) -> i32 { return 1; }
"#],
    )
    .expect("first same-library unit should export");
    let mut beta = common::semantic_interface_with_timeout(
        7,
        &[r#"module beta::api;
pub struct BetaToken { value: i32 }
pub fn accept_beta(value: BetaToken) -> i32 { return 2; }
"#],
    )
    .expect("second same-library unit should export");
    beta.unit_id = 1;
    for ty in &mut beta.types {
        if ty.kind == GpuSemanticInterfaceTypeKind::Declaration as u32
            && ty.payload_lo == beta.library_id
        {
            ty.nominal_unit_id = beta.unit_id;
        }
    }
    beta.validate()
        .expect("second unit should retain valid full nominal identities");

    let accepted = r#"module app::main;
import alpha::api;
import beta::api;
fn use_alpha(value: AlphaToken) -> i32 { return accept_alpha(value); }
fn use_beta(value: BetaToken) -> i32 { return accept_beta(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[accepted],
        vec![alpha.clone(), beta.clone()],
    )
    .expect("distinct same-library unit nominals should resolve independently");

    let rejected = r#"module app::main;
import alpha::api;
import beta::api;
fn wrong(value: BetaToken) -> i32 { return accept_alpha(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[rejected],
        vec![alpha, beta],
    )
    .expect_err("same-library declarations from different units must not compare equal");
}

#[test]
fn type_checker_resolves_dependency_interface_module_import_on_gpu() {
    let dependency = common::semantic_interface_with_timeout(
        7,
        &[r#"module core::math;
pub type CountBase = i32;
pub type Count = CountBase;
pub struct Token { value: i32 }
pub struct Boxed<T> { value: T }
pub struct Wrapped<T> { value: T }
pub struct Wide<A, B, C, D, E, F> { a: A, b: B, c: C, d: D, e: E, f: F }
pub fn identity(value: Count) -> Count { return value; }
pub fn keep_token(value: Token) -> Token { return value; }
pub fn keep_boxed(value: Boxed<i32>) -> Boxed<i32> { return value; }
pub fn keep_four(values: [i32; 4]) -> [i32; 4] { return values; }
pub fn keep_generic<T>(value: T) -> T { return value; }
pub fn keep_pair<T>(left: T, right: T) -> T { return left; }
"#],
    )
    .expect("dependency semantic interface should compile");
    let dependency_decl = |name: &str| {
        dependency
            .declarations
            .iter()
            .find(|declaration| {
                semantic_interface_name(
                    &dependency.name_bytes,
                    declaration.name_byte_start,
                    declaration.name_byte_len,
                ) == name
            })
            .expect("dependency declaration should be exported")
    };
    assert_ne!(
        dependency_decl("Boxed").signature_type,
        dependency_decl("Wrapped").signature_type,
        "distinct nominal declarations need distinct canonical signature nodes"
    );
    let module_only_dependent = r#"module app::main;
import core::math;
fn main() -> i32 { return 0; }
"#;

    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[module_only_dependent],
        vec![dependency.clone()],
    )
    .expect("dependency module import should resolve from its semantic interface");

    let declaration_dependent = r#"module app::main;
import core::math;
fn main() -> Count {
    let value: Count = identity(37);
    return value;
}
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[declaration_dependent],
        vec![dependency.clone()],
    )
    .expect("public dependency declarations and signatures should resolve from the interface");

    let nominal_dependent = r#"module app::main;
import core::math;
fn forward(value: Token) -> Token { return keep_token(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[nominal_dependent],
        vec![dependency.clone()],
    )
    .expect("canonical dependency nominal identities should survive local declarations and calls");

    let generic_nominal_dependent = r#"module app::main;
import core::math;
fn forward(value: Boxed<i32>) -> Boxed<i32> { return value; }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[generic_nominal_dependent],
        vec![dependency.clone()],
    )
    .expect("instantiated dependency nominal identities should preserve their generic arguments");

    let compound_call_dependent = r#"module app::main;
import core::math;
fn forward(value: Boxed<i32>) -> Boxed<i32> { return keep_boxed(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[compound_call_dependent],
        vec![dependency.clone()],
    )
    .expect("dependency calls should preserve concrete generic parameter and return graphs");

    let wrong_compound_call_nominal = r#"module app::main;
import core::math;
fn wrong(value: Wrapped<i32>) -> Boxed<i32> { return keep_boxed(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_compound_call_nominal],
        vec![dependency.clone()],
    )
    .expect_err("dependency calls must compare the nominal identity of generic arguments");

    let wrong_compound_call_argument = r#"module app::main;
import core::math;
fn wrong(value: Boxed<bool>) -> Boxed<i32> { return keep_boxed(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_compound_call_argument],
        vec![dependency.clone()],
    )
    .expect_err("dependency calls must compare concrete generic argument types");

    let wrong_compound_call_return_nominal = r#"module app::main;
import core::math;
fn wrong(value: Boxed<i32>) -> Wrapped<i32> { return keep_boxed(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_compound_call_return_nominal],
        vec![dependency.clone()],
    )
    .expect_err("dependency call results must retain their generic nominal identity");

    let wrong_compound_call_return_argument = r#"module app::main;
import core::math;
fn wrong(value: Boxed<i32>) -> Boxed<bool> { return keep_boxed(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_compound_call_return_argument],
        vec![dependency.clone()],
    )
    .expect_err("dependency call results must retain their concrete generic arguments");

    let array_call_dependent = r#"module app::main;
import core::math;
fn forward(values: [i32; 4]) -> [i32; 4] { return keep_four(values); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[array_call_dependent],
        vec![dependency.clone()],
    )
    .expect("dependency calls should preserve concrete array element and length types");

    let wrong_array_call_element = r#"module app::main;
import core::math;
fn wrong(values: [bool; 4]) -> [i32; 4] { return keep_four(values); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_array_call_element],
        vec![dependency.clone()],
    )
    .expect_err("dependency calls must compare concrete array element types");

    let wrong_array_call_length = r#"module app::main;
import core::math;
fn wrong(values: [i32; 8]) -> [i32; 4] { return keep_four(values); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_array_call_length],
        vec![dependency.clone()],
    )
    .expect_err("dependency calls must compare concrete array lengths");

    let generic_function_dependent = r#"module app::main;
import core::math;
fn forward(value: i32) -> i32 { return keep_generic(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[generic_function_dependent],
        vec![dependency.clone()],
    )
    .expect("dependency function generics should be inferred from call arguments");

    let inconsistent_generic_function_call = r#"module app::main;
import core::math;
fn wrong(left: i32, right: bool) -> i32 { return keep_pair(left, right); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[inconsistent_generic_function_call],
        vec![dependency.clone()],
    )
    .expect_err("all claims for an imported function generic must agree");

    let wrong_generic_function_return = r#"module app::main;
import core::math;
fn wrong(value: i32) -> bool { return keep_generic(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_generic_function_return],
        vec![dependency.clone()],
    )
    .expect_err("an imported generic return must use the inferred argument type");

    let compound_generic_function = r#"module app::main;
import core::math;
fn forward(left: Boxed<i32>, right: Boxed<i32>) -> Boxed<i32> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[compound_generic_function],
        vec![dependency.clone()],
    )
    .expect("imported function generics should retain compound nominal identity");

    let inconsistent_compound_generic_function = r#"module app::main;
import core::math;
fn wrong(left: Boxed<i32>, right: Wrapped<i32>) -> Boxed<i32> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[inconsistent_compound_generic_function],
        vec![dependency.clone()],
    )
    .expect_err("compound claims for an imported function generic must agree exactly");

    let inconsistent_compound_generic_argument = r#"module app::main;
import core::math;
fn wrong(left: Boxed<i32>, right: Boxed<bool>) -> Boxed<i32> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[inconsistent_compound_generic_argument],
        vec![dependency.clone()],
    )
    .expect_err("compound generic claims must compare their concrete arguments in parallel");

    let wide_compound_generic_function = r#"module app::main;
import core::math;
fn forward(
    left: Wide<i32, bool, i32, bool, i32, bool>,
    right: Wide<i32, bool, i32, bool, i32, bool>
) -> Wide<i32, bool, i32, bool, i32, bool> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wide_compound_generic_function],
        vec![dependency.clone()],
    )
    .expect("compound generic claim comparison must not have a four-argument limit");

    let wrong_wide_compound_generic_function = r#"module app::main;
import core::math;
fn wrong(
    left: Wide<i32, bool, i32, bool, i32, bool>,
    right: Wide<i32, bool, i32, bool, bool, bool>
) -> Wide<i32, bool, i32, bool, i32, bool> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_wide_compound_generic_function],
        vec![dependency.clone()],
    )
    .expect_err("wide compound generic claims must compare every argument row");

    let wrong_compound_generic_return = r#"module app::main;
import core::math;
fn wrong(value: Boxed<i32>) -> Wrapped<i32> { return keep_generic(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_compound_generic_return],
        vec![dependency.clone()],
    )
    .expect_err("an imported compound generic return must retain exact nominal identity");

    let wrong_compound_generic_return_argument = r#"module app::main;
import core::math;
fn wrong(value: Boxed<i32>) -> Boxed<bool> { return keep_generic(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_compound_generic_return_argument],
        vec![dependency.clone()],
    )
    .expect_err("an imported compound generic return must retain concrete arguments");

    let wrong_generic_nominal = r#"module app::main;
import core::math;
fn wrong(value: Boxed<i32>) -> Wrapped<i32> { return value; }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_generic_nominal],
        vec![dependency.clone()],
    )
    .expect_err("distinct dependency generic nominal identities must not compare equal");

    let wrong_generic_argument = r#"module app::main;
import core::math;
fn wrong(value: Boxed<i32>) -> Boxed<bool> { return value; }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_generic_argument],
        vec![dependency.clone()],
    )
    .expect_err("dependency generic arguments must participate in structural type equality");

    let wrong_argument = r#"module app::main;
import core::math;
fn main() -> i32 { return identity(true); }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_argument],
        vec![dependency.clone()],
    )
    .expect_err("dependency parameter types must participate in call checking");

    let wrong_nominal_argument = r#"module app::main;
import core::math;
fn main() -> i32 { keep_token(1); return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_nominal_argument],
        vec![dependency],
    )
    .expect_err("dependency nominal parameter identities must reject scalar arguments");
}

#[test]
fn semantic_interface_export_preserves_transitive_dependency_nominal_identity() {
    let core = common::semantic_interface_with_timeout(
        7,
        &[r#"module core::types;
pub struct Token { value: i32 }
pub struct Other { value: i32 }
"#],
    )
    .expect("core semantic interface should compile");

    let middle = common::semantic_interface_with_dependencies_with_timeout(
        8,
        &[r#"module middle::api;
import core::types;
pub fn forward(value: Token) -> Token { return value; }
"#],
        vec![core.clone()],
    )
    .expect("middle interface should export signatures that reference a dependency nominal");

    let accepted = r#"module app::main;
import core::types;
import middle::api;
fn use_forward(value: Token) -> Token { return forward(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[accepted],
        vec![core.clone(), middle.clone()],
    )
    .expect("a transitive dependency nominal should retain its originating library identity");

    let rejected = r#"module app::main;
import core::types;
import middle::api;
fn wrong(value: Other) -> Token { return forward(value); }
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[rejected],
        vec![core, middle],
    )
    .expect_err("a distinct dependency nominal must not satisfy the transitive signature");
}

#[test]
fn bounded_wasm_worker_persists_and_consumes_dependency_semantic_interfaces() {
    let core_source =
        common::TempArtifact::new("laniusc_bounded_interface", "core", Some("lanius"));
    core_source.write_str(
        r#"module core::types;
pub struct Token { value: i32 }
"#,
    );
    let middle_source =
        common::TempArtifact::new("laniusc_bounded_interface", "middle", Some("lanius"));
    middle_source.write_str(
        r#"module middle::api;
import core::types;
pub fn forward(value: Token) -> Token { return value; }
"#,
    );
    let artifact_root = common::temp_artifact_path("laniusc_bounded_interface", "artifacts", None);
    let worker_root = artifact_root.clone();
    let core_path = core_source.path().to_path_buf();
    let middle_path = middle_source.path().to_path_buf();
    let core_len = std::fs::metadata(&core_path)
        .expect("stat core source")
        .len() as usize;
    let middle_len = std::fs::metadata(&middle_path)
        .expect("stat middle source")
        .len() as usize;

    let result = common::run_with_timeout("bounded semantic-interface worker", move || {
        pollster::block_on(async move {
            let compiler = GpuCompiler::new().await?;
            let mut executor = GpuSourcePackArtifactExecutor::new(
                &compiler,
                &worker_root,
                SourcePackArtifactTarget::Wasm,
            );
            let core_job = SourcePackJob {
                job_index: 0,
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: 0,
                library_job_index: None,
                library_id: 7,
                first_source_index: 0,
                source_file_count: 1,
                source_bytes: core_len,
                source_lines: 2,
                oversized_source_file: false,
                dependency_job_indices: Vec::new(),
            };
            let core_files = [ExplicitSourcePathFile {
                library_id: 7,
                path: core_path,
                byte_len: core_len,
                modified_unix_nanos: None,
                line_count: Some(2),
            }];
            let core_handle = executor
                .begin_library_interface(&core_job, &core_files)
                .await?;
            let core_artifact = executor
                .finish_library_interface(&core_job, core_handle)
                .await?;

            let middle_job = SourcePackJob {
                job_index: 1,
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: 1,
                library_job_index: None,
                library_id: 8,
                first_source_index: 1,
                source_file_count: 1,
                source_bytes: middle_len,
                source_lines: 3,
                oversized_source_file: false,
                dependency_job_indices: vec![0],
            };
            let middle_files = [ExplicitSourcePathFile {
                library_id: 8,
                path: middle_path,
                byte_len: middle_len,
                modified_unix_nanos: None,
                line_count: Some(3),
            }];
            let mut middle_handle = executor
                .begin_library_interface(&middle_job, &middle_files)
                .await?;
            executor
                .add_library_interface_dependency_batch(
                    &middle_job,
                    &mut middle_handle,
                    &[core_artifact],
                )
                .await?;
            executor
                .finish_library_interface(&middle_job, middle_handle)
                .await?;
            Ok::<_, CompileError>(worker_root)
        })
    })
    .expect("bounded worker should compile dependency interfaces");
    let artifact_root = result;

    let core_interface_path =
        artifact_root.join("gpu-source-pack/wasm/semantic-interface/job-0.lnsi");
    let middle_interface_path =
        artifact_root.join("gpu-source-pack/wasm/semantic-interface/job-1.lnsi");
    let core = GpuSemanticInterfaceArtifact::from_bytes(
        &std::fs::read(&core_interface_path).expect("read persisted core interface"),
    )
    .expect("parse persisted core interface");
    let middle = GpuSemanticInterfaceArtifact::from_bytes(
        &std::fs::read(&middle_interface_path).expect("read persisted middle interface"),
    )
    .expect("parse persisted middle interface");
    assert_eq!(core.library_id, 7);
    assert_eq!(core.unit_id, 0);
    assert_eq!(middle.library_id, 8);
    assert_eq!(middle.unit_id, 1);
    assert!(middle.types.iter().any(|ty| {
        ty.kind == GpuSemanticInterfaceTypeKind::Declaration as u32 && ty.payload_lo == 7
    }));

    if std::env::var_os("LANIUS_KEEP_TEMP_ARTIFACTS").is_none() {
        std::fs::remove_dir_all(&artifact_root).expect("remove bounded worker artifact root");
    }
}

#[test]
fn bounded_wasm_work_queue_reaches_concrete_interface_execution() {
    let source = common::TempArtifact::new("laniusc_bounded_work_queue", "app", Some("lanius"));
    source.write_str(
        r#"module app::main;
pub fn answer() -> i32 { return 42; }
"#,
    );
    let artifact_root = common::temp_artifact_path("laniusc_bounded_work_queue", "artifacts", None);
    let worker_root = artifact_root.clone();
    let source_path = source.path().to_path_buf();

    let result = common::run_with_timeout("bounded WASM work queue", move || {
        for _ in 0..64 {
            let execution = pollster::block_on(run_path_stream_worker_to_wasm(
                vec![ExplicitSourceLibraryPathStream {
                    library_id: 7,
                    source_file_count: 1,
                    paths: vec![source_path.clone()],
                    dependency_library_ids: Vec::new(),
                }],
                &worker_root,
                CodegenUnitLimits::default(),
                SourcePackJobBatchLimits::default(),
                SourcePackBuildShardLimits::default(),
                "bounded-work-queue-test-worker",
                32,
                None,
                32,
            ));
            match execution {
                Ok(execution) => return Ok((execution, worker_root)),
                Err(CompileError::Diagnostic(diagnostic)) if diagnostic.code == "LNC0064" => {}
                Err(err) => return Err(err),
            }
        }
        panic!("bounded work-queue preparation did not complete after 64 chunks");
    })
    .expect("bounded work queue should execute all prepared jobs");
    let (execution, artifact_root) = result;
    assert!(execution.executed_item_count >= 1);
    let interface_path = artifact_root.join("gpu-source-pack/wasm/semantic-interface/job-0.lnsi");
    let interface = GpuSemanticInterfaceArtifact::from_bytes(
        &std::fs::read(&interface_path).expect("read work-queue semantic interface"),
    )
    .expect("parse work-queue semantic interface");
    assert_eq!(interface.library_id, 7);

    if std::env::var_os("LANIUS_KEEP_TEMP_ARTIFACTS").is_none() {
        std::fs::remove_dir_all(&artifact_root).expect("remove work-queue artifact root");
    }
}

#[test]
fn bounded_x86_executor_persists_a_parseable_relocatable_object() {
    let dependency =
        common::TempArtifact::new("laniusc_bounded_x86_object", "core", Some("lanius"));
    dependency.write_str(
        r#"module core::api;
pub fn unused() -> i32 { return 7; }
"#,
    );
    let source = common::TempArtifact::new("laniusc_bounded_x86_object", "app", Some("lanius"));
    source.write_str(
        r#"module app::main;
import core::api;
pub fn answer() -> i32 { return unused(); }
fn main() -> i32 { return answer(); }
"#,
    );
    let artifact_root = common::temp_artifact_path("laniusc_bounded_x86_object", "artifacts", None);
    let executor_root = artifact_root.clone();
    let dependency_path = dependency.path().to_path_buf();
    let dependency_len = std::fs::metadata(&dependency_path)
        .expect("stat x86 dependency source")
        .len() as usize;
    let source_path = source.path().to_path_buf();
    let source_len = std::fs::metadata(&source_path)
        .expect("stat x86 object source")
        .len() as usize;

    let result = common::run_with_timeout("bounded x86 object executor", move || {
        pollster::block_on(async move {
            let compiler = GpuCompiler::new().await?;
            let mut executor = GpuSourcePackArtifactExecutor::new(
                &compiler,
                &executor_root,
                SourcePackArtifactTarget::X86_64,
            );
            let dependency_files = [ExplicitSourcePathFile {
                library_id: 6,
                path: dependency_path,
                byte_len: dependency_len,
                modified_unix_nanos: None,
                line_count: Some(2),
            }];
            let source_files = [ExplicitSourcePathFile {
                library_id: 7,
                path: source_path,
                byte_len: source_len,
                modified_unix_nanos: None,
                line_count: Some(4),
            }];
            let dependency_job = SourcePackJob {
                job_index: 0,
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: 0,
                library_job_index: None,
                library_id: 6,
                first_source_index: 0,
                source_file_count: 1,
                source_bytes: dependency_len,
                source_lines: 2,
                oversized_source_file: false,
                dependency_job_indices: Vec::new(),
            };
            let dependency_handle = executor
                .begin_library_interface(&dependency_job, &dependency_files)
                .await?;
            let dependency_artifact = executor
                .finish_library_interface(&dependency_job, dependency_handle)
                .await?;
            let interface_job = SourcePackJob {
                job_index: 1,
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: 1,
                library_job_index: None,
                library_id: 7,
                first_source_index: 1,
                source_file_count: 1,
                source_bytes: source_len,
                source_lines: 4,
                oversized_source_file: false,
                dependency_job_indices: vec![0],
            };
            let mut interface_handle = executor
                .begin_library_interface(&interface_job, &source_files)
                .await?;
            executor
                .add_library_interface_dependency_batch(
                    &interface_job,
                    &mut interface_handle,
                    std::slice::from_ref(&dependency_artifact),
                )
                .await?;
            let interface_artifact = executor
                .finish_library_interface(&interface_job, interface_handle)
                .await?;
            let dependency_codegen_job = SourcePackJob {
                job_index: 3,
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: 0,
                library_job_index: Some(0),
                library_id: 6,
                first_source_index: 0,
                source_file_count: 1,
                source_bytes: dependency_len,
                source_lines: 2,
                oversized_source_file: false,
                dependency_job_indices: vec![0],
            };
            let dependency_codegen_handle = executor
                .begin_codegen_object(
                    &dependency_codegen_job,
                    &dependency_files,
                    &dependency_artifact,
                )
                .await?;
            let dependency_object_artifact = executor
                .finish_codegen_object(&dependency_codegen_job, dependency_codegen_handle)
                .await?;
            let codegen_job = SourcePackJob {
                job_index: 2,
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: 1,
                library_job_index: Some(1),
                library_id: 7,
                first_source_index: 1,
                source_file_count: 1,
                source_bytes: source_len,
                source_lines: 4,
                oversized_source_file: false,
                dependency_job_indices: vec![1, 0],
            };
            let mut codegen_handle = executor
                .begin_codegen_object(&codegen_job, &source_files, &interface_artifact)
                .await?;
            executor
                .add_codegen_object_dependency_batch(
                    &codegen_job,
                    &mut codegen_handle,
                    std::slice::from_ref(&dependency_artifact),
                )
                .await?;
            let app_object_artifact = executor
                .finish_codegen_object(&codegen_job, codegen_handle)
                .await?;
            let link_job = SourcePackJob {
                job_index: 4,
                phase: SourcePackJobPhase::Link,
                phase_unit_index: 0,
                library_job_index: None,
                library_id: 7,
                first_source_index: 0,
                source_file_count: 2,
                source_bytes: source_len + dependency_len,
                source_lines: 6,
                oversized_source_file: false,
                dependency_job_indices: vec![2, 3],
            };
            let mut link_handle = executor.begin_link_codegen_objects(&link_job).await?;
            executor
                .link_codegen_object_batch(
                    &link_job,
                    &mut link_handle,
                    &SourcePackLinkObjectBatch {
                        batch_index: 0,
                        input_object_artifact_indices: vec![0, 1],
                        source_bytes: source_len + dependency_len,
                        source_file_count: 2,
                        source_lines: 6,
                    },
                    &[app_object_artifact, dependency_object_artifact],
                )
                .await?;
            executor
                .finish_link_codegen_objects(&link_job, link_handle)
                .await?;
            Ok::<_, CompileError>(executor_root)
        })
    })
    .expect("bounded x86 executor should persist a codegen object");
    let artifact_root = result;

    let object_dir = artifact_root.join("gpu-source-pack/x86_64/codegen-object");
    let mut object_paths = std::fs::read_dir(&object_dir)
        .expect("read x86 codegen-object directory")
        .map(|entry| entry.expect("read x86 object directory entry").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "lnxo")
        })
        .collect::<Vec<_>>();
    object_paths.sort();
    assert_eq!(object_paths.len(), 2);
    let object_bytes = std::fs::read(&object_paths[0]).expect("read persisted x86 object");
    let object = GpuX86RelocatableObject::from_bytes(&object_bytes)
        .expect("persisted x86 object should parse and validate");
    assert_eq!(object.library_id, 7);
    assert_eq!(object.entry_offset, Some(0));
    assert!(!object.text.is_empty());
    assert_eq!(object.symbols.len(), 2);
    assert_eq!(object.symbols[0].section, GpuX86ObjectSection::Undefined);
    assert_eq!(object.symbols[1].section, GpuX86ObjectSection::Text);
    assert!(object.symbols[1].size > 0);
    assert!(object.relocations.iter().any(|relocation| {
        relocation.target_kind == GpuX86RelocationTargetKind::Symbol && relocation.target_index == 0
    }));
    let dependency_object = GpuX86RelocatableObject::from_bytes(
        &std::fs::read(&object_paths[1]).expect("read persisted dependency x86 object"),
    )
    .expect("persisted dependency x86 object should parse and validate");
    assert_eq!(dependency_object.library_id, 6);
    assert_eq!(dependency_object.entry_offset, None);
    assert_eq!(dependency_object.symbols.len(), 1);
    assert_eq!(
        dependency_object.symbols[0].section,
        GpuX86ObjectSection::Text
    );

    let descriptor_path = object_paths[0].with_extension("json");
    let descriptor = serde_json::from_slice::<GpuSourcePackArtifactDescriptor>(
        &std::fs::read(&descriptor_path).expect("read x86 codegen descriptor"),
    )
    .expect("parse x86 codegen descriptor");
    descriptor
        .validate_contract()
        .expect("x86 codegen descriptor should validate");
    let payload = descriptor
        .codegen_object_payload
        .expect("x86 codegen descriptor should reference its object payload");
    assert_eq!(
        payload.format,
        GpuSourcePackCodegenObjectFormat::LaniusX86_64
    );
    assert_eq!(payload.byte_len, object_bytes.len());
    assert_eq!(artifact_root.join(&payload.storage_key), object_paths[0]);

    let linked_descriptor_path =
        artifact_root.join("gpu-source-pack/x86_64/linked-output/job-4.json");
    let linked_descriptor = serde_json::from_slice::<GpuSourcePackArtifactDescriptor>(
        &std::fs::read(&linked_descriptor_path).expect("read x86 linked-output descriptor"),
    )
    .expect("parse x86 linked-output descriptor");
    linked_descriptor
        .validate_contract()
        .expect("x86 linked-output descriptor should validate");
    let emitted = linked_descriptor
        .output_record_arrays
        .iter()
        .find(|array| array.name == "emitted_byte_records")
        .expect("linked-output descriptor should contain emitted bytes");
    let linked_path = artifact_root.join(
        emitted
            .storage_key
            .as_deref()
            .expect("emitted bytes should reference the persisted ELF"),
    );
    let linked_bytes = std::fs::read(&linked_path).expect("read linked x86 ELF");
    assert_eq!(&linked_bytes[..4], b"\x7fELF");
    assert_eq!(emitted.element_count, Some(linked_bytes.len()));
    assert_eq!(emitted.byte_len, Some(linked_bytes.len()));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let mut permissions = std::fs::metadata(&linked_path)
            .expect("stat linked x86 ELF")
            .permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&linked_path, permissions).expect("chmod linked x86 ELF");
        let status = std::process::Command::new(&linked_path)
            .status()
            .expect("run linked x86 ELF");
        assert_eq!(status.code(), Some(7));
    }

    if std::env::var_os("LANIUS_KEEP_TEMP_ARTIFACTS").is_none() {
        std::fs::remove_dir_all(&artifact_root).expect("remove bounded x86 artifact root");
    }
}

#[test]
fn bounded_wasm_executor_links_persisted_cross_unit_objects() {
    let dependency =
        common::TempArtifact::new("laniusc_bounded_wasm_object", "core", Some("lanius"));
    dependency.write_str(
        r#"module core::api;
pub fn seven() -> i32 { return 7; }
"#,
    );
    let source = common::TempArtifact::new("laniusc_bounded_wasm_object", "app", Some("lanius"));
    source.write_str(
        r#"module app::main;
import core::api;
fn main() -> i32 { return seven(); }
"#,
    );
    let artifact_root =
        common::temp_artifact_path("laniusc_bounded_wasm_object", "artifacts", None);
    let executor_root = artifact_root.clone();
    let dependency_path = dependency.path().to_path_buf();
    let dependency_len = std::fs::metadata(&dependency_path).unwrap().len() as usize;
    let source_path = source.path().to_path_buf();
    let source_len = std::fs::metadata(&source_path).unwrap().len() as usize;

    let result = common::run_gpu_codegen_with_timeout("bounded Wasm object executor", move || {
        pollster::block_on(async move {
            let compiler = GpuCompiler::new().await?;
            let mut executor = GpuSourcePackArtifactExecutor::new(
                &compiler,
                &executor_root,
                SourcePackArtifactTarget::Wasm,
            );
            let dependency_files = [ExplicitSourcePathFile {
                library_id: 6,
                path: dependency_path,
                byte_len: dependency_len,
                modified_unix_nanos: None,
                line_count: Some(2),
            }];
            let source_files = [ExplicitSourcePathFile {
                library_id: 7,
                path: source_path,
                byte_len: source_len,
                modified_unix_nanos: None,
                line_count: Some(3),
            }];
            let dependency_job = SourcePackJob {
                job_index: 0,
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: 0,
                library_job_index: None,
                library_id: 6,
                first_source_index: 0,
                source_file_count: 1,
                source_bytes: dependency_len,
                source_lines: 2,
                oversized_source_file: false,
                dependency_job_indices: Vec::new(),
            };
            let dependency_handle = executor
                .begin_library_interface(&dependency_job, &dependency_files)
                .await?;
            let dependency_interface = executor
                .finish_library_interface(&dependency_job, dependency_handle)
                .await?;

            let interface_job = SourcePackJob {
                job_index: 1,
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: 1,
                library_job_index: None,
                library_id: 7,
                first_source_index: 1,
                source_file_count: 1,
                source_bytes: source_len,
                source_lines: 3,
                oversized_source_file: false,
                dependency_job_indices: vec![0],
            };
            let mut interface_handle = executor
                .begin_library_interface(&interface_job, &source_files)
                .await?;
            executor
                .add_library_interface_dependency_batch(
                    &interface_job,
                    &mut interface_handle,
                    std::slice::from_ref(&dependency_interface),
                )
                .await?;
            let app_interface = executor
                .finish_library_interface(&interface_job, interface_handle)
                .await?;

            let dependency_codegen_job = SourcePackJob {
                job_index: 3,
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: 0,
                library_job_index: Some(0),
                library_id: 6,
                first_source_index: 0,
                source_file_count: 1,
                source_bytes: dependency_len,
                source_lines: 2,
                oversized_source_file: false,
                dependency_job_indices: vec![0],
            };
            let dependency_codegen_handle = executor
                .begin_codegen_object(
                    &dependency_codegen_job,
                    &dependency_files,
                    &dependency_interface,
                )
                .await?;
            let dependency_object = executor
                .finish_codegen_object(&dependency_codegen_job, dependency_codegen_handle)
                .await?;

            let app_codegen_job = SourcePackJob {
                job_index: 2,
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: 1,
                library_job_index: Some(1),
                library_id: 7,
                first_source_index: 1,
                source_file_count: 1,
                source_bytes: source_len,
                source_lines: 3,
                oversized_source_file: false,
                dependency_job_indices: vec![1, 0],
            };
            let mut app_codegen_handle = executor
                .begin_codegen_object(&app_codegen_job, &source_files, &app_interface)
                .await?;
            executor
                .add_codegen_object_dependency_batch(
                    &app_codegen_job,
                    &mut app_codegen_handle,
                    std::slice::from_ref(&dependency_interface),
                )
                .await?;
            let app_object = executor
                .finish_codegen_object(&app_codegen_job, app_codegen_handle)
                .await?;

            let link_job = SourcePackJob {
                job_index: 4,
                phase: SourcePackJobPhase::Link,
                phase_unit_index: 0,
                library_job_index: None,
                library_id: 7,
                first_source_index: 0,
                source_file_count: 2,
                source_bytes: source_len + dependency_len,
                source_lines: 5,
                oversized_source_file: false,
                dependency_job_indices: vec![2, 3],
            };
            let mut link_handle = executor.begin_link_codegen_objects(&link_job).await?;
            executor
                .link_codegen_object_batch(
                    &link_job,
                    &mut link_handle,
                    &SourcePackLinkObjectBatch {
                        batch_index: 0,
                        input_object_artifact_indices: vec![0, 1],
                        source_bytes: source_len + dependency_len,
                        source_file_count: 2,
                        source_lines: 5,
                    },
                    &[app_object, dependency_object],
                )
                .await?;
            executor
                .finish_link_codegen_objects(&link_job, link_handle)
                .await?;
            Ok::<_, CompileError>(executor_root)
        })
    })
    .expect("bounded Wasm executor should link cross-unit objects");
    let artifact_root = result;

    let app_object_path = artifact_root.join("gpu-source-pack/wasm/codegen-object/job-2.lnwo");
    let app_object = GpuWasmRelocatableObject::from_bytes(
        &std::fs::read(&app_object_path).expect("read persisted app Wasm object"),
    )
    .expect("parse persisted app Wasm object");
    assert_eq!(app_object.library_id, 7);
    assert_eq!(app_object.entry_function, Some(0));
    assert!(app_object.relocations.iter().any(|relocation| {
        relocation.target_kind == GpuWasmRelocationTargetKind::Symbol
            && relocation.target_index == 0
    }));

    let descriptor: GpuSourcePackArtifactDescriptor = serde_json::from_slice(
        &std::fs::read(app_object_path.with_extension("json"))
            .expect("read Wasm object descriptor"),
    )
    .expect("parse Wasm object descriptor");
    descriptor
        .validate_contract()
        .expect("Wasm object descriptor should validate");
    assert_eq!(
        descriptor.codegen_object_payload.unwrap().format,
        GpuSourcePackCodegenObjectFormat::LaniusWasm
    );

    let linked_path = artifact_root.join("gpu-source-pack/wasm/linked-output/job-4.wasm");
    let linked = std::fs::read(&linked_path).expect("read linked Wasm module");
    assert_eq!(&linked[..8], b"\0asm\x01\0\0\0");
    if let Ok(node) = which::which("node") {
        let output = std::process::Command::new(node)
            .args([
                "-e",
                "const fs=require('fs'); WebAssembly.instantiate(fs.readFileSync(process.argv[1])).then(x=>process.stdout.write(String(x.instance.exports.main())))",
                linked_path.to_str().unwrap(),
            ])
            .output()
            .expect("run linked source-pack Wasm module");
        assert!(
            output.status.success(),
            "Node rejected linked source-pack Wasm: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.stdout, b"7");
    }

    if std::env::var_os("LANIUS_KEEP_TEMP_ARTIFACTS").is_none() {
        std::fs::remove_dir_all(&artifact_root).expect("remove bounded Wasm artifact root");
    }
}

#[test]
fn bounded_x86_work_queue_reaches_concrete_object_execution() {
    let source = common::TempArtifact::new("laniusc_bounded_x86_queue", "app", Some("lanius"));
    source.write_str(
        r#"module app::main;
fn main() -> i32 { return 0; }
"#,
    );
    let artifact_root = common::temp_artifact_path("laniusc_bounded_x86_queue", "artifacts", None);
    let worker_root = artifact_root.clone();
    let source_path = source.path().to_path_buf();

    let result = common::run_with_timeout("bounded x86 work queue", move || {
        for _ in 0..64 {
            let execution = pollster::block_on(run_path_stream_worker_to_x86_64(
                vec![ExplicitSourceLibraryPathStream {
                    library_id: 7,
                    source_file_count: 1,
                    paths: vec![source_path.clone()],
                    dependency_library_ids: Vec::new(),
                }],
                &worker_root,
                CodegenUnitLimits::default(),
                SourcePackJobBatchLimits::default(),
                SourcePackBuildShardLimits::default(),
                "bounded-x86-queue-test-worker",
                32,
                None,
                32,
            ));
            match execution {
                Ok(execution) => return Ok((execution, worker_root)),
                Err(CompileError::Diagnostic(diagnostic)) if diagnostic.code == "LNC0064" => {}
                Err(err) => return Err(err),
            }
        }
        panic!("bounded x86 work-queue preparation did not complete after 64 chunks");
    })
    .expect("bounded x86 work queue should execute its object job");
    let (execution, artifact_root) = result;
    assert!(execution.executed_item_count >= 2);
    let object_path = artifact_root.join("gpu-source-pack/x86_64/codegen-object/job-1.lnxo");
    GpuX86RelocatableObject::from_bytes(
        &std::fs::read(&object_path).expect("read work-queue x86 object"),
    )
    .expect("work-queue x86 object should parse and validate");

    if std::env::var_os("LANIUS_KEEP_TEMP_ARTIFACTS").is_none() {
        std::fs::remove_dir_all(&artifact_root).expect("remove bounded x86 queue artifact root");
    }
}

#[test]
fn type_checker_compares_nested_imported_generic_trees_without_a_depth_cap() {
    let deeply_nested_i32 = (0..32).fold("i32".to_string(), |inner, _| format!("Boxed<{inner}>"));
    let deeply_nested_bool = (0..32).fold("bool".to_string(), |inner, _| format!("Boxed<{inner}>"));
    let dependency_source = format!(
        r#"module core::nested;
pub struct Boxed<T> {{ value: T }}
pub struct Wrapped<T> {{ value: T }}
pub type Count = i32;
pub fn keep_pair<T>(left: T, right: T) -> T {{ return left; }}
pub fn accept_nested(value: Boxed<Boxed<Boxed<i32>>>) -> i32 {{ return 1; }}
pub fn produce_nested(value: Boxed<Boxed<Boxed<i32>>>) -> Boxed<Boxed<Boxed<i32>>> {{
    return value;
}}
pub fn accept_deep(value: {deeply_nested_i32}) -> i32 {{ return 1; }}
pub fn accept_alias_leaf(value: Boxed<Boxed<Count>>) -> i32 {{ return 1; }}
"#
    );
    let dependency = common::semantic_interface_with_timeout(7, &[dependency_source.as_str()])
        .expect("nested generic dependency interface should compile");

    let plain_nested_return = r#"module app::main;
import core::nested;
fn forward(value: Boxed<Boxed<Boxed<i32>>>) -> Boxed<Boxed<Boxed<i32>>> {
    return value;
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[plain_nested_return],
        vec![dependency.clone()],
    )
    .expect("equal nested imported type annotations should compare structurally");

    let nested_dependency_parameter = r#"module app::main;
import core::nested;
fn main() -> i32 {
    let value: Boxed<Boxed<Boxed<i32>>>;
    return accept_nested(value);
}
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[nested_dependency_parameter],
        vec![dependency.clone()],
    )
    .expect("dependency canonical signatures should compare complete nested type trees");

    let wrong_dependency_parameter_leaf = r#"module app::main;
import core::nested;
fn main() -> i32 {
    let value: Boxed<Boxed<Boxed<bool>>>;
    return accept_nested(value);
}
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_dependency_parameter_leaf],
        vec![dependency.clone()],
    )
    .expect_err("dependency canonical signatures must reject a different deepest scalar");

    let wrong_dependency_parameter_nominal = r#"module app::main;
import core::nested;
fn main() -> i32 {
    let value: Boxed<Boxed<Wrapped<i32>>>;
    return accept_nested(value);
}
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_dependency_parameter_nominal],
        vec![dependency.clone()],
    )
    .expect_err("dependency canonical signatures must reject a different nested nominal type");

    let nested_dependency_result = r#"module app::main;
import core::nested;
fn forward(value: Boxed<Boxed<Boxed<i32>>>) -> Boxed<Boxed<Boxed<i32>>> {
    return produce_nested(value);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[nested_dependency_result],
        vec![dependency.clone()],
    )
    .expect("dependency canonical results should compare complete nested type trees");

    let wrong_nested_dependency_result = r#"module app::main;
import core::nested;
fn wrong(value: Boxed<Boxed<Boxed<i32>>>) -> Boxed<Boxed<Boxed<bool>>> {
    return produce_nested(value);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_nested_dependency_result],
        vec![dependency.clone()],
    )
    .expect_err("dependency canonical results must reject a different deepest scalar");

    let deep_dependency_parameter = format!(
        r#"module app::main;
import core::nested;
fn main() -> i32 {{
    let value: {deeply_nested_i32};
    return accept_deep(value);
}}
"#
    );
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[deep_dependency_parameter.as_str()],
        vec![dependency.clone()],
    )
    .expect("canonical/local comparison must not impose a nesting-depth cap");

    let wrong_deep_dependency_parameter = format!(
        r#"module app::main;
import core::nested;
fn main() -> i32 {{
    let value: {deeply_nested_bool};
    return accept_deep(value);
}}
"#
    );
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_deep_dependency_parameter.as_str()],
        vec![dependency.clone()],
    )
    .expect_err("deep canonical/local comparison must still inspect the final leaf");

    let nested_dependency_aliases = r#"module app::main;
import core::nested;
fn main() -> i32 {
    let expanded_leaf: Boxed<Boxed<i32>>;
    return accept_alias_leaf(expanded_leaf);
}
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[nested_dependency_aliases],
        vec![dependency.clone()],
    )
    .expect("nested canonical scalar aliases should normalize inside compound trees");

    let nested_compound_generic_function = r#"module app::main;
import core::nested;
fn forward(
    left: Boxed<Boxed<Boxed<i32>>>,
    right: Boxed<Boxed<Boxed<i32>>>
) -> Boxed<Boxed<Boxed<i32>>> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[nested_compound_generic_function],
        vec![dependency.clone()],
    )
    .expect("compound generic claims should compare nested type trees without a depth cap");

    let wrong_nested_compound_generic_argument = r#"module app::main;
import core::nested;
fn wrong(
    left: Boxed<Boxed<Boxed<i32>>>,
    right: Boxed<Boxed<Boxed<bool>>>
) -> Boxed<Boxed<Boxed<i32>>> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_nested_compound_generic_argument],
        vec![dependency.clone()],
    )
    .expect_err("nested compound generic claims must compare their deepest concrete arguments");

    let wrong_nested_compound_generic_nominal = r#"module app::main;
import core::nested;
fn wrong(
    left: Boxed<Boxed<Boxed<i32>>>,
    right: Boxed<Boxed<Wrapped<i32>>>
) -> Boxed<Boxed<Boxed<i32>>> {
    return keep_pair(left, right);
}
fn main() -> i32 { return 0; }
"#;
    common::type_check_source_pack_with_dependencies_with_timeout(
        9,
        &[wrong_nested_compound_generic_nominal],
        vec![dependency],
    )
    .expect_err("nested compound generic claims must retain deep nominal identity");
}

fn assert_source_pack_case_accepts(sources: &'static [&'static str], app_source: &'static str) {
    let mut sources = sources.to_vec();
    if !app_source.is_empty() {
        sources.push(app_source);
    }
    assert_gpu_type_check_pack_accepts(&sources);
}

#[test]
fn resident_typechecker_always_records_hir_control_validation() {
    let resident = include_str!("../crates/laniusc-compiler/src/type_checker/resident.rs");
    let pass_loaders = include_str!("../crates/laniusc-compiler/src/type_checker/pass_loaders.rs");

    assert!(
        resident.contains("&self.passes.control_hir")
            && resident.contains("&self.passes.scope_hir"),
        "resident type checking should not select token-derived control/scope passes"
    );
    assert!(
        !resident.contains("uses_hir_control")
            && !resident.contains("&self.passes.control\n")
            && !resident.contains("&self.passes.scope\n"),
        "resident type checking must not fall back to lexer-token syntax validation"
    );
    assert!(
        !pass_loaders.contains("type_check_control\", \"type_checker/control\"")
            && !pass_loaders.contains("type_check_scope\", \"type_checker/scope\""),
        "token-derived control/scope shaders should not be loaded by resident type checking"
    );
}

#[test]
fn type_checker_accepts_leading_module_metadata() {
    assert_gpu_type_check_accepts("module app::main;");
    assert_gpu_type_check_accepts("module app::main; fn main() { return 0; }");
}

#[test]
fn type_checker_rejects_self_import_through_gpu_module_resolver() {
    match common::type_check_source_pack_with_timeout(&[r#"module app::main;
import app::main;
fn main() { return 0; }
"#])
    {
        Ok(()) => panic!("self-import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(
                diagnostic.code, "LNC0002",
                "direct self-import diagnostics should use the reserved cycle code"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("self-import should report LNC0002, got raw GPU type-check error: {message}");
        }
        Err(other) => panic!("expected GPU resolver rejection, got {other:?}"),
    }
}

#[test]
fn type_checker_rejects_two_module_import_cycle_through_gpu_module_resolver() {
    match common::type_check_source_pack_with_timeout(&[
        r#"module app::main;
import app::helper;
fn main() { return 0; }
"#,
        r#"module app::helper;
import app::main;
"#,
    ]) {
        Ok(()) => panic!("two-module import cycle should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(
                diagnostic.code, "LNC0002",
                "two-module import cycles should use the reserved cycle code"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "two-module import cycle should report LNC0002, got raw GPU type-check error: {message}"
            );
        }
        Err(other) => panic!("expected GPU resolver rejection, got {other:?}"),
    }
}

#[test]
#[ignore = "requires GPU SCC/topological import-cycle checkpoint beyond direct and two-module cycles"]
fn type_checker_rejects_three_module_import_cycle_through_gpu_topological_checkpoint() {
    match common::type_check_source_pack_with_timeout(&[
        r#"module app::main;
import app::middle;
fn main() { return 0; }
"#,
        r#"module app::middle;
import app::leaf;
"#,
        r#"module app::leaf;
import app::main;
"#,
    ]) {
        Ok(()) => panic!("three-module import cycle should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(
                diagnostic.code, "LNC0002",
                "arbitrary import cycles should use the reserved cycle code"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "three-module import cycle should report LNC0002, got raw GPU type-check error: {message}"
            );
        }
        Err(other) => panic!("expected GPU resolver rejection, got {other:?}"),
    }
}

#[test]
fn type_checker_accepts_acyclic_three_module_import_chain() {
    assert_gpu_type_check_pack_accepts(&[
        r#"module app::main;
import app::middle;
fn main() { return 0; }
"#,
        r#"module app::middle;
import app::leaf;
"#,
        r#"module app::leaf;
"#,
    ]);
}

#[test]
fn type_checker_unresolved_source_pack_import_reports_stable_diagnostic() {
    let source = r#"module app::main;
import core::math;
fn main() { return 0; }
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("unresolved import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0010");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unresolved import diagnostic should point at the import path token");
            assert_eq!(label.path, std::path::PathBuf::from("<source pack file 0>"));
            assert_eq!(label.line, 2);
            assert_eq!(label.column, 8);
            assert_eq!(label.source_line, Some("import core::math;".to_string()));
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0010]: unresolved import"));
            assert!(rendered.contains("<source pack file 0>:2:8"));
            assert!(rendered.contains("import core::math;"));
            assert!(rendered.contains("imported module not found"));
            assert!(
                !rendered.contains("GPU type check rejected"),
                "diagnostic should not expose raw GPU rejection:\n{rendered}"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("unresolved import should report LNC0010, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected GPU resolver diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_source_pack_syntax_failure_reports_stable_diagnostic() {
    let sources = [
        "module app::main;\n",
        "module app::bad;\nfn fn bad() -> i32 { return 1; }\n",
    ];

    match common::type_check_source_pack_with_timeout(&sources) {
        Ok(()) => panic!("malformed source-pack file should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0016");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("syntax diagnostic should point at malformed source");
            assert_eq!(label.path, std::path::PathBuf::from("<source pack file 1>"));
            assert_eq!(label.line, 2);
            assert_eq!(
                label.source_line,
                Some("fn fn bad() -> i32 { return 1; }".to_string())
            );
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0016]: syntax error"));
            assert!(rendered.contains("<source pack file 1>:2:"));
            assert!(rendered.contains("fn fn bad() -> i32 { return 1; }"));
            assert!(
                !rendered.contains("GPU type check rejected"),
                "syntax diagnostic should not expose raw GPU rejection:\n{rendered}"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "malformed source-pack file should report LNC0016, got raw GPU error: {message}"
            );
        }
        Err(other) => panic!("expected GPU syntax diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_string_import_reports_stable_diagnostic() {
    let source = r#"module app::main;
import "stdlib/core/math.lani";
fn main() { return 0; }
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("quoted import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0011");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0011]: unsupported import form"));
            assert!(rendered.contains("<source pack file 0>:2:1"));
            assert!(rendered.contains("import \"stdlib/core/math.lani\";"));
            assert!(rendered.contains("only module-path imports are supported here"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("quoted import should report LNC0011, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected unsupported import diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_resolves_imports_beyond_the_legacy_path_depth() {
    assert_gpu_type_check_pack_accepts(&[
        r#"module a::b::c::d::e::f::g::h::i;
pub fn answer() -> i32 { return 42; }
"#,
        r#"module app::main;
import a::b::c::d::e::f::g::h::i;
fn main() -> i32 { return answer(); }
"#,
    ]);
}

#[test]
fn type_checker_duplicate_source_pack_module_reports_stable_diagnostic() {
    let first = r#"module a::b::c::d::e::f::g::h::i;
pub fn one() -> i32 { return 1; }
"#;
    let duplicate = r#"module a::b::c::d::e::f::g::h::i;
pub fn two() -> i32 { return 2; }
"#;

    match common::type_check_source_pack_with_timeout(&[first, duplicate]) {
        Ok(()) => panic!("duplicate module declarations should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0013");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0013]: duplicate module declaration"));
            assert!(rendered.contains("<source pack file 1>:1:8"));
            assert!(rendered.contains("module a::b::c::d::e::f::g::h::i;"));
            assert!(rendered.contains("already declared in the source pack"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("duplicate module should report LNC0013, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected duplicate-module diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_distinguishes_deep_paths_with_a_long_common_prefix() {
    assert_gpu_type_check_pack_accepts(&[
        r#"module a::b::c::d::e::f::g::h::i::left;
pub fn from_left() -> i32 { return 1; }
"#,
        r#"module a::b::c::d::e::f::g::h::i::right;
pub fn from_right() -> i32 { return 2; }
"#,
        r#"module app::main;
import a::b::c::d::e::f::g::h::i::left;
import a::b::c::d::e::f::g::h::i::right;
fn main() -> i32 { return from_left() + from_right(); }
"#,
    ]);
}

#[test]
fn type_checker_accepts_modules_beyond_the_legacy_path_depth() {
    let source = r#"module a::b::c::d::e::f::g::h::i;
fn main() { return 0; }
"#;
    assert_gpu_type_check_pack_accepts(&[source]);
}

#[test]
fn semantic_interface_exports_arbitrary_depth_module_segments() {
    let artifact = common::semantic_interface_with_timeout(
        41,
        &[r#"module a::b::c::d::e::f::g::h::i;
pub fn answer() -> i32 { return 42; }
"#],
    )
    .expect("deep module interface should be materialized on the GPU");
    assert_eq!(artifact.modules.len(), 1);
    let module = artifact.modules[0];
    let first = module.first_segment as usize;
    let end = first + module.segment_count as usize;
    let path = artifact.module_segments[first..end]
        .iter()
        .map(|segment| {
            semantic_interface_name(
                &artifact.name_bytes,
                segment.name_byte_start,
                segment.name_byte_len,
            )
        })
        .collect::<Vec<_>>();
    assert_eq!(path, ["a", "b", "c", "d", "e", "f", "g", "h", "i"]);
}

#[test]
fn type_checker_resolves_qualified_types_beyond_the_legacy_path_depth() {
    let declaration = r#"module a::b::c::d::e::f::g::h::i;
pub type Thing = i32;
"#;
    let source = r#"module app::main;
import a::b::c::d::e::f::g::h::i;
fn main() {
    let value: a::b::c::d::e::f::g::h::i::Thing = 0;
    return 0;
}
"#;
    assert_gpu_type_check_pack_accepts(&[declaration, source]);
}

#[test]
fn type_checker_resolves_qualified_values_beyond_the_legacy_path_depth() {
    let declaration = r#"module a::b::c::d::e::f::g::h::i;
pub fn value() -> i32 { return 7; }
"#;
    let source = r#"module app::main;
import a::b::c::d::e::f::g::h::i;
fn main() {
    return a::b::c::d::e::f::g::h::i::value();
}
"#;
    assert_gpu_type_check_pack_accepts(&[declaration, source]);
}

#[test]
fn type_checker_resolves_path_prefixes_across_workgroups() {
    let path = (0..300)
        .map(|i| format!("segment_{i}"))
        .collect::<Vec<_>>()
        .join("::");
    let declaration = format!("module {path};\npub fn answer() -> i32 {{ return 42; }}\n");
    let consumer =
        format!("module app::main;\nimport {path};\nfn main() -> i32 {{ return answer(); }}\n");
    assert_gpu_type_check_pack_accepts(&[&declaration, &consumer]);
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
fn type_checker_rejects_private_cross_module_type_aliases_on_gpu() {
    assert_gpu_type_check_pack_accepts(&[r#"
module core::count;

type Count = i32;

fn keep(value: core::count::Count) -> Count {
    return value;
}

fn main() {
    let value: core::count::Count = keep(1);
    return value;
}
"#]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::count;

type Count = i32;
"#,
        r#"
module app::main;

import core::count;

fn main() {
    let value: core::count::Count = 1;
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::count;

type Count = i32;
"#,
        r#"
module app::main;

import core::count;

fn main() {
    let value: Count = 1;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_entry_stdlib_root_loads_imported_module() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;
import core::i32;

fn main() {
    let min_value: i32 = core::i32::MIN;
    let max_value: i32 = MAX;
    let bits: u32 = core::i32::BITS;
    let bytes: u32 = BYTES;
    if (min_value != core::i32::MIN || max_value != core::i32::MAX || bits != 32 || bytes != 4) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load imported stdlib module");
    let expected_stdlib_path = stdlib_root.join("core/i32.lani");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == expected_stdlib_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry.path())
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root stdlib import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("source-root stdlib import should type check");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_unsigned_integer_metadata() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "unsigned_ints", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::u32;
import core::u8;

fn main() {
    let u32_bits: u32 = core::u32::BITS;
    let u32_bytes: u32 = core::u32::BYTES;
    let u8_bits: u32 = core::u8::BITS;
    let u8_bytes: u32 = core::u8::BYTES;
    let u32_floor: u32 = core::u32::MIN;
    let byte_ceiling: u8 = core::u8::MAX;
    if (u32_bits != 32 || u32_bytes != 4 || u8_bits != 8 || u8_bytes != 1) {
        return 1;
    }
    if (u32_floor != 0 || byte_ceiling != 255) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load unsigned integer stdlib modules");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani"))
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani"))
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry.path())
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root unsigned integer metadata",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("unsigned integer metadata should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_runtime_contract() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "runtime_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let allocator: core::runtime::Capability = core::runtime::HAS_ALLOCATOR;
    let clock: Capability = core::runtime::HAS_CLOCK;
    let panic_hook: Capability = core::runtime::HAS_PANIC_HOOK;
    let host: Capability = core::runtime::HAS_HOST_SERVICES;
    let threads: Capability = core::runtime::has_threads();
    let secure_rng: core::runtime::Capability = core::runtime::has_secure_rng();
    let gpu: Capability = core::runtime::has_gpu();
    let process: Capability = core::runtime::has_process();
    let env: core::runtime::Capability = has_env();
    let runtime_services: Capability = core::runtime::has_runtime_services();
    let contract_only: core::runtime::Capability =
        core::runtime::runtime_services_are_contract_only();
    let threads_status: RuntimeServiceStatus =
        core::runtime::service_status(core::runtime::SERVICE_THREADS_ID);
    let process_status: core::runtime::RuntimeServiceStatus =
        service_status(core::runtime::SERVICE_PROCESS_ID);
    let threads_unavailable: Capability =
        core::runtime::service_is_unavailable(core::runtime::SERVICE_THREADS_ID);
    let process_available: Capability =
        core::runtime::service_is_available(core::runtime::SERVICE_PROCESS_ID);
    let unknown_service_unknown: core::runtime::Capability = service_is_unknown(99);
    let secure_rng_needs_binding: Capability =
        service_requires_runtime_binding(SERVICE_SECURE_RNG_ID);
    let gpu_needs_binding: Capability =
        core::runtime::service_requires_runtime_binding(core::runtime::SERVICE_GPU_ID);
    let env_needs_binding: core::runtime::Capability =
        service_requires_runtime_binding(core::runtime::SERVICE_ENV_ID);
    if (allocator || clock || panic_hook || host || threads || secure_rng || gpu || process || env || runtime_services || !contract_only) {
        return 1;
    }
    if (threads_status != SERVICE_STATUS_UNAVAILABLE || process_status != SERVICE_STATUS_UNAVAILABLE) {
        return 1;
    }
    if (!threads_unavailable || process_available || !unknown_service_unknown) {
        return 1;
    }
    if (!secure_rng_needs_binding || !gpu_needs_binding || !env_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::runtime from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::runtime import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::runtime should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_target_capability_contract() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "target_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::target;

fn main() {
    let native: Capability = core::target::is_native();
    let wasm: core::target::Capability = is_wasm();
    let panic_hook: Capability = core::target::has_panic_hook();
    let host_services: core::target::Capability = has_host_services();
    let process: Capability = core::target::has_process();
    let env: core::target::Capability = has_env();
    let host_services_const: Capability = core::target::HAS_HOST_SERVICES;
    let process_const: core::target::Capability = HAS_PROCESS;
    let freestanding: Capability = core::target::is_freestanding();
    if (!native || wasm || panic_hook || host_services || process || env || host_services_const || process_const || !freestanding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::target from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/target.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::target import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::target capability contract should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_accepts_core_target_capability_contract_source_pack() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/target.lani"),
        r#"
module app::main;

import core::target;

fn main() {
    let native: Capability = core::target::is_native();
    let wasm: core::target::Capability = is_wasm();
    let panic_hook: Capability = core::target::has_panic_hook();
    let host_services: core::target::Capability = has_host_services();
    let process: Capability = core::target::has_process();
    let env: core::target::Capability = has_env();
    let host_services_const: Capability = core::target::HAS_HOST_SERVICES;
    let process_const: core::target::Capability = HAS_PROCESS;
    let freestanding: Capability = core::target::is_freestanding();
    if (!native || wasm || panic_hook || host_services || process || env || host_services_const || process_const || !freestanding) {
        return 1;
    }
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_bool_contract() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "bool_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::bool;

fn main() {
    let different: bool = core::bool::ne(true, false);
    let same: bool = core::bool::eq(different, true);
    let selected: i32 = core::bool::select_i32(different, 7, 99);
    let fallback: i32 = core::bool::choose_i32(false, 11, 42);
    if (same && selected == 7 && fallback == 42) {
        return 0;
    }
    return 1;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::bool from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/bool.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::bool import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::bool helpers should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_mem_generics() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "mem_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::mem;

fn main() {
    let number: i32 = identity(7);
    let flag: bool = identity(false);
    let left: i32 = first(number, 11);
    let right: bool = second(flag, true);
    let selected_number: i32 = select(right, left, 0);
    let selected_flag: bool = select(false, right, flag);
    let qualified_number: i32 = core::mem::identity(selected_number);
    if (selected_flag) {
        return qualified_number;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::mem from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/mem.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::mem import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::mem generic helpers should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_source_root_loads_user_module_imports() {
    let source_root = common::temp_artifact_path("laniusc_source_root", "user_root", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("helper.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn one() -> i32 {
    return 1;
}
"#,
    )
    .expect("write helper module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::one();
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root(&entry_path, &source_root)
        .expect("source-root path manifest should load imported user module");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == helper_path)
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root user module import",
        type_check_entry_with_source_root(entry_path.clone(), source_root.clone()),
    )
    .expect("source-root user module import should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp user source root");
}

#[test]
fn source_root_imports_use_gpu_module_declarations_not_host_paths() {
    let source_root = common::temp_artifact_path("laniusc_source_root", "mismatched_module", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("helper.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::renamed;

pub fn one() -> i32 {
    return 1;
}
"#,
    )
    .expect("write mismatched helper module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::one();
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root(&entry_path, &source_root)
        .expect("source-root loader should load the path candidate");
    assert_eq!(manifest.files.len(), 2);
    assert!(manifest.files.iter().any(|file| file.path == helper_path));

    match common::block_on_gpu_with_timeout(
        "GPU type check source-root module declaration mismatch",
        type_check_entry_with_source_root(entry_path.clone(), source_root.clone()),
    ) {
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0010");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("module/path mismatch diagnostic should point at the import path");
            assert_eq!(label.path, entry_path);
            assert_eq!(label.line, 4);
            assert_eq!(label.column, 8);
            assert_eq!(label.source_line, Some("import app::helper;".to_string()));
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0010]: unresolved import"));
            assert!(rendered.contains("import app::helper;"));
            assert!(rendered.contains("imported module not found"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("module/path mismatch should report LNC0010, got raw GPU error: {message}");
        }
        other => panic!(
            "expected GPU resolver diagnostic for module/path identity mismatch, got {other:?}"
        ),
    }

    std::fs::remove_dir_all(&source_root).expect("remove temp user source root");
}

#[test]
fn source_root_loader_can_combine_user_and_stdlib_roots() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let source_root = common::temp_artifact_path("laniusc_source_root", "user_and_stdlib", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("helper.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn id(value: i32) -> i32 {
    return value;
}
"#,
    )
    .expect("write helper module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;
import core::i32;

fn main() {
    let value: i32 = core::i32::MIN;
    return app::helper::id(value);
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should load user and stdlib imports");
    let expected_stdlib_path = stdlib_root.join("core/i32.lani");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == expected_stdlib_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == helper_path)
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout(
        "GPU type check combined source-root and stdlib imports",
        async move { type_check_entry_with_source_roots(entry_path, &roots).await },
    )
    .expect("combined source-root and stdlib imports should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp user/std source root");
}

#[test]
fn source_root_user_module_takes_precedence_over_stdlib_candidate() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let source_root = common::temp_artifact_path("laniusc_source_root", "user_stdlib_shadow", None);
    let app_root = source_root.join("app");
    let core_root = source_root.join("core");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    std::fs::create_dir_all(&core_root).expect("create temp core source root");
    let user_core_i32_path = core_root.join("i32.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &user_core_i32_path,
        r#"
module core::i32;

pub fn local_only() -> i32 {
    return 11;
}
"#,
    )
    .expect("write user core::i32 module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import core::i32;

fn main() {
    let value: i32 = core::i32::local_only();
    return value;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should prefer user module before stdlib fallback");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == user_core_i32_path),
        "core::i32 should resolve to the user source-root candidate"
    );
    assert!(
        !manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "stdlib fallback must not be loaded when a user source root resolves the module"
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout(
        "GPU type check source-root module precedence over stdlib fallback",
        async move { type_check_entry_with_source_roots(entry_path, &roots).await },
    )
    .expect("user source-root module should shadow the stdlib fallback during type checking");

    std::fs::remove_dir_all(&source_root).expect("remove temp user/std shadow source root");
}

#[test]
fn source_root_stdlib_nested_import_stays_inside_stdlib_boundary() {
    let root = common::temp_artifact_path("laniusc_source_root", "stdlib_nested_boundary", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    std::fs::create_dir_all(&user_core_root).expect("create temp user core root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create temp stdlib core root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create temp stdlib std root");

    let user_shared_path = user_core_root.join("shared.lani");
    let stdlib_shared_path = stdlib_core_root.join("shared.lani");
    let shim_path = stdlib_std_root.join("shim.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &user_shared_path,
        r#"
module core::shared;

pub fn value() -> bool {
    return false;
}
"#,
    )
    .expect("write user core::shared module");
    std::fs::write(
        &stdlib_shared_path,
        r#"
module core::shared;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write stdlib core::shared module");
    std::fs::write(
        &shim_path,
        r#"
module std::shim;

import core::shared;

pub fn forwarded() -> i32 {
    return core::shared::value();
}
"#,
    )
    .expect("write stdlib shim module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import std::shim;

fn main() {
    let value: i32 = std::shim::forwarded();
    return value;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should keep stdlib nested imports inside stdlib");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == shim_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_shared_path),
        "stdlib shim's nested core::shared import should resolve inside the stdlib root"
    );
    assert!(
        !manifest
            .files
            .iter()
            .any(|file| file.path == user_shared_path),
        "stdlib nested imports must not cross back into the user source root"
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root.clone()),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout("GPU type check stdlib nested import boundary", async move {
        type_check_entry_with_source_roots(entry_path, &roots).await
    })
    .expect("stdlib nested import should type check against the stdlib candidate");

    std::fs::remove_dir_all(&root).expect("remove temp stdlib nested boundary root");
}

#[test]
fn source_root_user_module_can_import_stdlib_dependency() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let source_root =
        common::temp_artifact_path("laniusc_source_root", "user_module_stdlib_dependency", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("int_gate.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::int_gate;

import core::i32;

pub fn min_value() -> i32 {
    return core::i32::MIN;
}
"#,
    )
    .expect("write helper module with stdlib dependency");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::int_gate;

fn main() {
    if (app::int_gate::min_value() < 0) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should load transitive stdlib imports");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 imported by the source-root helper"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == helper_path)
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout(
        "GPU type check source-root user module with stdlib dependency",
        async move { type_check_entry_with_source_roots(entry_path, &roots).await },
    )
    .expect("source-root user module stdlib dependency should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp source-root stdlib dependency dir");
}

#[test]
fn source_root_user_module_can_import_user_dependency() {
    let source_root =
        common::temp_artifact_path("laniusc_source_root", "user_module_user_dependency", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let leaf_path = app_root.join("leaf.lani");
    let gate_path = app_root.join("gate.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write transitive leaf module");
    std::fs::write(
        &gate_path,
        r#"
module app::gate;

import app::leaf;

pub fn forwarded() -> i32 {
    return app::leaf::value();
}
"#,
    )
    .expect("write helper module with user dependency");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::gate;

fn main() {
    let value: i32 = app::gate::forwarded();
    return value;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root(&entry_path, &source_root)
        .expect("source-root path manifest should load transitive user imports");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == gate_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == leaf_path),
        "path manifest should include app::leaf imported by the source-root helper"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root user module with user dependency",
        type_check_entry_with_source_root(entry_path.clone(), source_root.clone()),
    )
    .expect("source-root user module dependency should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp source-root user dependency dir");
}

#[test]
fn source_root_loader_reports_missing_stdlib_module_path() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "missing", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::missing;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect_err("missing imported stdlib module should fail before GPU");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0001");
            let message = diagnostic.render();
            assert!(message.contains("error[LNC0001]"));
            assert!(message.contains("core::missing"));
            assert!(message.contains(&entry.path().display().to_string()));
            assert!(message.contains("core/missing.lani"));
            assert!(message.contains("import core::missing;"));
            assert!(message.contains("imported here"));
        }
        other => panic!("expected frontend source-root error, got {other:?}"),
    }
}

#[test]
fn source_root_loader_rejects_ambiguous_user_module_path() {
    let root = common::temp_artifact_path("laniusc_source_root", "ambiguous", None);
    let left_root = root.join("left");
    let right_root = root.join("right");
    std::fs::create_dir_all(left_root.join("app")).expect("create left source root");
    std::fs::create_dir_all(right_root.join("app")).expect("create right source root");
    let left_helper = left_root.join("app/helper.lani");
    let right_helper = right_root.join("app/helper.lani");
    std::fs::write(
        &left_helper,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write left helper");
    std::fs::write(
        &right_helper,
        "module app::helper;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write right helper");
    let entry = common::TempArtifact::new("laniusc_source_root", "ambiguous_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::helper;
fn main() { return 0; }
"#,
    );

    let roots = EntrySourceRoots {
        stdlib_root: None,
        user_roots: vec![left_root.clone(), right_root.clone()],
    };
    let err = load_entry_with_source_roots(entry.path(), &roots)
        .expect_err("source-root loader should reject ambiguous modules before GPU");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0003");
            let message = diagnostic.render();
            assert!(message.contains("error[LNC0003]"));
            assert!(message.contains("app::helper"));
            assert!(message.contains(&left_helper.display().to_string()));
            assert!(message.contains(&right_helper.display().to_string()));
            assert!(message.contains("import app::helper;"));
            assert!(message.contains("ambiguous import"));
        }
        other => panic!("expected ambiguous source-root diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp ambiguous source roots");
}

#[test]
fn source_root_loader_leaves_quoted_imports_for_gpu_rejection() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "quoted", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import "stdlib/core/i32.lani";
fn main() { return 0; }
"#,
    );

    let source_pack = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root loader should not host-include quoted imports");
    assert_eq!(source_pack.sources.len(), 1);
    let result = common::block_on_gpu_with_timeout(
        "GPU type check source-root quoted import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    );
    match result {
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0011");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0011]: unsupported import form"));
            assert!(rendered.contains(&entry.path().display().to_string()));
            assert!(rendered.contains("import \"stdlib/core/i32.lani\";"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("quoted import should report LNC0011, got raw GPU error: {message}");
        }
        other => panic!("expected GPU type check rejection for quoted import, got {other:?}"),
    }
}

#[test]
fn source_root_loader_deduplicates_import_cycles_without_semantic_rejection() {
    let root = common::temp_artifact_path("laniusc_source_root", "cycle", None);
    let stdlib_root = root.join("stdlib");
    let core_root = stdlib_root.join("core");
    std::fs::create_dir_all(&core_root).expect("create temp stdlib core root");
    let a_path = core_root.join("a.lani");
    let b_path = core_root.join("b.lani");
    std::fs::write(
        &a_path,
        r#"
module core::a;
import core::b;
pub const A: i32 = 1;
"#,
    )
    .expect("write core::a");
    std::fs::write(
        &b_path,
        r#"
module core::b;
import core::a;
pub const B: i32 = 2;
"#,
    )
    .expect("write core::b");
    let entry = common::TempArtifact::new("laniusc_source_root", "cycle_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::a;
fn main() { return 0; }
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root loader should use import cycles only as recursion guards");
    assert_eq!(
        manifest.files.len(),
        3,
        "entry plus two cyclic imports should be loaded once each"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == a_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == b_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry.path())
    );

    std::fs::remove_dir_all(&root).expect("remove temp source-root cycle test dir");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_stdlib_symlink_escape() {
    let root = common::temp_artifact_path("laniusc_source_root", "symlink", None);
    let stdlib_root = root.join("stdlib");
    let outside_root = root.join("outside");
    std::fs::create_dir_all(stdlib_root.join("core")).expect("create temp stdlib root");
    std::fs::create_dir_all(&outside_root).expect("create outside root");
    let outside_module = outside_root.join("escape.lani");
    std::fs::write(&outside_module, "module core::escape;\n").expect("write outside module");
    std::os::unix::fs::symlink(&outside_module, stdlib_root.join("core/escape.lani"))
        .expect("create stdlib symlink escape");
    let entry = common::TempArtifact::new("laniusc_source_root", "symlink_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::escape;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect_err("stdlib-root loader should reject symlink escapes");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0004");
            let message = diagnostic.render();
            assert!(message.contains("core::escape"));
            assert!(message.contains("outside stdlib root"));
            assert!(message.contains("import core::escape;"));
        }
        other => panic!("expected frontend symlink escape error, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp source-root symlink test dir");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_stdlib_symlink_to_non_source_file() {
    let root = common::temp_artifact_path("laniusc_source_root", "stdlib_non_source", None);
    let stdlib_root = root.join("stdlib");
    let core_root = stdlib_root.join("core");
    std::fs::create_dir_all(&core_root).expect("create temp stdlib root");
    let non_source_module = core_root.join("helper.txt");
    std::fs::write(&non_source_module, "module core::helper;\n")
        .expect("write non-source stdlib module target");
    std::os::unix::fs::symlink(&non_source_module, core_root.join("helper.lani"))
        .expect("create stdlib symlink to non-source file");
    let canonical_non_source =
        std::fs::canonicalize(&non_source_module).expect("canonicalize non-source target");
    let entry = common::TempArtifact::new(
        "laniusc_source_root",
        "stdlib_non_source_entry",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;
import core::helper;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect_err("stdlib-root loader should reject non-source canonical import targets");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0030");
            let message = diagnostic.render();
            assert!(message.contains("core::helper"));
            assert!(message.contains("stdlib root"));
            assert!(message.contains(&canonical_non_source.display().to_string()));
            assert!(message.contains("import core::helper;"));
            assert!(message.contains("canonical .lani source files"));
            assert!(!message.contains("GPU frontend error"));
        }
        other => panic!("expected frontend stdlib non-source diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp stdlib non-source test dir");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_user_symlink_escape() {
    let root = common::temp_artifact_path("laniusc_source_root", "user_symlink", None);
    let source_root = root.join("src");
    let outside_root = root.join("outside");
    std::fs::create_dir_all(source_root.join("app")).expect("create temp source root");
    std::fs::create_dir_all(&outside_root).expect("create outside root");
    let outside_module = outside_root.join("escape.lani");
    std::fs::write(&outside_module, "module app::escape;\n").expect("write outside module");
    std::os::unix::fs::symlink(&outside_module, source_root.join("app/escape.lani"))
        .expect("create user source-root symlink escape");
    let entry =
        common::TempArtifact::new("laniusc_source_root", "user_symlink_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::escape;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_source_root(entry.path(), &source_root)
        .expect_err("source-root loader should reject user symlink escapes");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0004");
            let message = diagnostic.render();
            assert!(message.contains("app::escape"));
            assert!(message.contains("outside source root"));
            assert!(message.contains("import app::escape;"));
        }
        other => panic!("expected frontend user symlink escape error, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp user source-root symlink test dir");
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
            "core::bool",
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
            "core::i32",
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
            "core::char+u32",
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
            "core::u8+i64",
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
            "core::f32",
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

    for (label, sources, app_source) in cases {
        let mut sources = sources.to_vec();
        if !app_source.is_empty() {
            sources.push(app_source);
        }
        common::type_check_source_pack_with_timeout(&sources).unwrap_or_else(|err| {
            panic!("{label} source pack should pass GPU type checking: {err:?}")
        });
    }
}

#[test]
fn type_checker_keeps_f32_arithmetic_results_as_f32() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y - right.y, self.z * right.z);
    }

    fn scale(self, factor: f32) -> Vec3 {
        return Vec3::new(self.x / factor, -self.y, self.z + 1.0);
    }
}

fn take(value: f32) -> f32 {
    return value;
}

fn main() {
    let left: Vec3 = Vec3::new(1.0, 2.0, 3.0);
    let right: Vec3 = Vec3::new(4.0, 5.0, 6.0);
    let sum: Vec3 = left.add(right);
    let scaled: Vec3 = sum.scale(2.0);
    let value: f32 = take(scaled.x + 0.5);
    if (value > 0.0) {
        return 0;
    }
    return 1;
}
"#,
    );
}

#[test]
fn type_checker_accepts_qualified_generic_type_associated_call() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/std/vec.lani"),
        r#"
module app::main;

import std::vec;

struct Sphere {
    radius: f32,
}

fn main() {
    let world: std::vec::Vec<Sphere> = std::vec::Vec<Sphere>::new();
    let count: i32 = world.len();
    return count;
}
"#,
    ]);
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
        include_str!("../stdlib/core/result.lani"),
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
        include_str!("../stdlib/core/result.lani"),
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
        include_str!("../stdlib/core/result.lani"),
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
fn type_checker_accepts_source_pack_generic_callee_at_two_concrete_types() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn identity<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module other::id;

pub fn identity(value: bool) -> bool {
    return value;
}
"#,
        r#"
module app::main;

import core::id;
import other::id;

fn main() {
    let number: i32 = core::id::identity(7);
    let flag: bool = core::id::identity(false);
    let decoy: bool = other::id::identity(flag);
    if (decoy) {
        return number;
    }
    return 0;
}
"#,
    ]);
}

#[test]
fn rejects_non_constructor_symbolic_enum_returns() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
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

import core::math;

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
fn type_checker_resolves_qualified_generic_call_arguments_by_ordinal() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module math::generic;

pub fn same<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import math::generic;

fn main() {
    let value: i32 = math::generic::same(1, 2);
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module math::generic;

pub fn same<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import math::generic;

fn main() {
    let value: i32 = math::generic::same(1, false);
    return value;
}
"#,
    ]);
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
    let zero_ptr: u32 = 0;
    let zero_len: usize = 0;
    let sleep_zero: i64 = 0;
    let args: i32 = std::process::argc();
    let first_arg_len: i32 = std::process::arg_len(0);
    let vars: i32 = std::env::var_count();
    let first_var_len: i32 = std::env::var_key_len(0);
    let file: i32 = std::fs::open_read(zero_ptr, zero_len);
    let bytes: i32 = std::fs::read(file, zero_ptr, zero_len);
    let now: i64 = std::time::monotonic_now_ns();
    let slept: i32 = std::time::sleep_ms(sleep_zero);
    let tcp: i32 = std::net::tcp_connect(zero_ptr, zero_len, 80);
    let udp: i32 = std::net::udp_bind(zero_ptr, zero_len, 53);
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
    let size: usize = 16;
    let grown_size: usize = 32;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(size, align);
    let grown: u32 = alloc::allocator::realloc(ptr, size, grown_size, align);
    let stdin_count: i32 = std::io::read_stdin(grown, grown_size);
    let stdout_count: i32 = std::io::write_stdout(grown, grown_size);
    let stderr_count: i32 = std::io::write_stderr(grown, grown_size);
    let flushed: i32 = std::io::flush_stderr();
    std::io::print_i32(stdin_count + stdout_count + stderr_count + flushed);
    alloc::allocator::dealloc(grown, grown_size, align);
    alloc::allocator::alloc_failed(grown_size, align);
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
    let native: Capability = core::target::is_native();
    let has_stdio: core::target::Capability = core::target::HAS_STDIO;
    let threaded: Capability = core::target::has_threads();
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

import core::cmp;

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
fn type_checker_resolves_trait_bounds_beyond_the_legacy_path_depth() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module root::one::two::three::four::five::six::seven::eight::nine;

pub trait Marker {
}

pub impl Marker for i32 {
}
"#,
        r#"
module app;

import root::one::two::three::four::five::six::seven::eight::nine;

fn keep<T>(value: T) -> T where T: root::one::two::three::four::five::six::seven::eight::nine::Marker {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_associated_calls_beyond_the_legacy_path_depth() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module root::one::two::three::four::five::six::seven::eight::nine;

pub struct Counter {
    value: i32,
}

pub impl Counter {
    pub fn answer() -> i32 {
        return 42;
    }
}
"#,
        r#"
module app;

import root::one::two::three::four::five::six::seven::eight::nine;

fn main() {
    return root::one::two::three::four::five::six::seven::eight::nine::Counter::answer();
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_leaf_name_trait_impl_for_different_qualified_bound() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module other::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}

pub impl other::cmp::Eq<i32> for i32 {
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
}

#[test]
fn type_checker_rejects_unqualified_trait_impl_for_different_module_bound() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module other::cmp;

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
fn type_checker_resolves_public_import_despite_private_imported_name_collision() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::private_limits;

const VALUE: bool = false;
"#,
        r#"
module core::public_limits;

pub const VALUE: i32 = 7;
"#,
        r#"
module app::main;

import core::private_limits;
import core::public_limits;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::private_math;

fn choose() -> bool {
    return false;
}
"#,
        r#"
module core::public_math;

pub fn choose() -> i32 {
    return 7;
}
"#,
        r#"
module app::main;

import core::private_math;
import core::public_math;

fn main() {
    let value: i32 = choose();
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_public_type_import_despite_private_imported_name_collision() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::private_types;

struct Token {
    hidden: bool,
}
"#,
        r#"
module core::public_types;

pub struct Token {
    value: i32,
}
"#,
        r#"
module app::main;

import core::private_types;
import core::public_types;

fn take(value: Token) -> i32 {
    return value.value;
}

fn main() {
    let item: Token = Token { value: 9 };
    return take(item);
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
fn type_checker_rejects_ambiguous_imported_name_after_duplicate_reimport_prefix() {
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
import core::left;
import core::right;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_ambiguous_imported_names_independent_of_source_and_import_order() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::right;

pub const VALUE: i32 = 2;
"#,
        r#"
module core::left;

pub const VALUE: i32 = 1;
"#,
        r#"
module app::main;

import core::right;
import core::left;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_keeps_imported_type_and_value_namespaces_separate() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::types;

pub struct Shared {
    value: i32,
}
"#,
        r#"
module core::values;

pub const Shared: i32 = 7;
"#,
        r#"
module app::main;

import core::types;
import core::values;

fn take(value: Shared) -> i32 {
    return value.value;
}

fn main() {
    let item: Shared = Shared { value: Shared };
    return take(item);
}
"#,
    ]);
}

#[test]
fn type_checker_prefers_local_declarations_over_imported_names() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::shadowed;

pub struct Item {
    flag: bool,
}

pub const VALUE: bool = false;
"#,
        r#"
module app::main;

import core::shadowed;

struct Item {
    value: i32,
}

const VALUE: i32 = 7;

fn take(item: Item) -> i32 {
    return item.value;
}

fn main() {
    let item: Item = Item { value: VALUE };
    return take(item);
}
"#,
    ]);
}

#[test]
fn type_checker_does_not_make_imported_names_transitively_visible() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::leaf;

pub const VALUE: i32 = 7;
"#,
        r#"
module core::mid;

import core::leaf;

pub fn forwarded() -> i32 {
    return core::leaf::VALUE;
}
"#,
        r#"
module app::main;

import core::mid;

fn main() {
    let value: i32 = VALUE;
    return value;
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
