mod common;

use laniusc_compiler::compiler::{CompileError, NativeCSignature, NativeCType};

#[test]
fn checked_c_declarations_reject_unsupported_unused_signatures() {
    let cases = [
        include_str!("fixtures/native_c/unsupported_float.lani"),
        include_str!("fixtures/native_c/unsupported_double_result.lani"),
        include_str!("fixtures/native_c/unsupported_narrow.lani"),
        include_str!("fixtures/native_c/unsupported_bool.lani"),
        include_str!("fixtures/native_c/unsupported_string.lani"),
        include_str!("fixtures/native_c/unsupported_aggregate.lani"),
        include_str!("fixtures/native_c/unsupported_reference.lani"),
        include_str!("fixtures/native_c/unsupported_slice.lani"),
        include_str!("fixtures/native_c/unsupported_generic.lani"),
        include_str!("fixtures/native_c/unsupported_unit_parameter.lani"),
        include_str!("fixtures/native_c/unsupported_never_result.lani"),
    ];
    for source in cases {
        let error = common::type_check_source_with_timeout(source)
            .expect_err("an unused unsupported C declaration must be rejected");
        match error {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0006", "{source}\n{diagnostic:?}");
                assert!(diagnostic.message.contains("native C signature"), "{source}\n{diagnostic:?}");
            }
            other => panic!("expected source diagnostic for {source}: {other:?}"),
        }
    }
}

#[test]
fn checked_c_metadata_preserves_private_identity_and_runtime_name_collisions() {
    let interface = common::semantic_interface_with_timeout(71, &[r#"
module native::api;
extern "C" fn private_c(value: i64, count: usize) -> ptr;
pub extern "C" fn close(value: i32) -> i32;
pub extern "lanius_std" fn argc() -> i32;
pub extern "unbound" fn write(value: i32) -> i32;
"#]).expect("checked C interface");
    let bindings = interface.native_c_functions().expect("checked bindings");
    assert_eq!(bindings.len(), 2);
    let private = bindings.iter().find(|binding| binding.name == "private_c").unwrap();
    assert_eq!(private.signature, NativeCSignature {
        parameters: vec![NativeCType::I64, NativeCType::Usize], result: NativeCType::Ptr,
    });
    assert_eq!(&private.identity[..2], &[interface.library_id, interface.unit_id]);
    assert_eq!(interface.declarations[private.identity[2] as usize].flags, 3);
    let close = bindings.iter().find(|binding| binding.name == "close").unwrap();
    assert_eq!(interface.declarations[close.identity[2] as usize].value_lo, u32::MAX,
        "a C function named close must retain a foreign call");
    let named = |name: &str| interface.declarations.iter().find(|row| {
        &interface.name_bytes[row.name_byte_start as usize
            ..(row.name_byte_start + row.name_byte_len) as usize] == name.as_bytes()
    }).unwrap();
    assert_eq!(named("argc").value_lo, 33);
    assert_eq!(named("write").value_lo, u32::MAX);

    common::type_check_source_pack_with_dependencies_with_timeout(72, &[r#"
module app::main;
import native::api;
fn main() -> i32 { return close(0); }
"#], vec![interface.clone()]).expect("public C import");
    common::type_check_source_pack_with_dependencies_with_timeout(72, &[r#"
module app::main;
import native::api;
fn main() -> i32 { let value: ptr = private_c(0, 0); return 0; }
"#], vec![interface]).expect_err("hidden C declarations must stay out of dependency name lookup");
}

#[test]
fn checked_c_signatures_accept_the_profile_parameter_limit() {
    let parameters = (0..32).map(|index| format!("p{index}: i64")).collect::<Vec<_>>().join(", ");
    let source = format!("pub extern \"C\" fn native_thirty_two({parameters}) -> u64;");
    let interface = common::semantic_interface_with_timeout(73, &[&source]).expect("32 C parameters");
    let bindings = interface.native_c_functions().unwrap();
    assert_eq!(bindings[0].signature.parameters, vec![NativeCType::I64; 32]);
    assert_eq!(bindings[0].signature.result, NativeCType::U64);
    let source = source.replace(") -> u64", ", overflow: i64) -> u64");
    common::type_check_source_with_timeout(&source).expect_err("33 C parameters exceed checked profile");
}
