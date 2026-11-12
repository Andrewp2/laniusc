use crate::common;

use laniusc_compiler::compiler::{CompileError, NativeCSignature, NativeCType};

#[test]
fn checked_c_declarations_reject_unsupported_unused_signatures() {
    let cases = [
        include_str!("fixtures/native_c/unsupported_narrow.lani"),
        include_str!("fixtures/native_c/unsupported_bool.lani"),
        include_str!("fixtures/native_c/unsupported_string.lani"),
        include_str!("fixtures/native_c/unsupported_aggregate.lani"),
        include_str!("fixtures/native_c/unsupported_record_float.lani"),
        include_str!("fixtures/native_c/unsupported_record_generic.lani"),
        include_str!("fixtures/native_c/unsupported_record_nested.lani"),
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
                assert!(
                    diagnostic.message.contains("native C signature"),
                    "{source}\n{diagnostic:?}"
                );
            }
            other => panic!("expected source diagnostic for {source}: {other:?}"),
        }
    }
}

/// The link metadata of a record is the C type of its one field. A private
/// record of a private declaration is resolved the same way.
#[test]
fn checked_c_record_metadata_is_the_field_type() {
    let interface = common::semantic_interface_with_timeout(
        75,
        &[r#"
module native::records;
pub struct Cookie { sequence: u32 }
struct Handle { raw: ptr }
pub extern "C" fn make(value: i64) -> Cookie;
extern "C" fn open(cookie: Cookie, flags: i32) -> Handle;
"#],
    )
    .expect("checked C record interface");
    let bindings = interface
        .native_c_functions()
        .expect("record native bindings");
    assert_eq!(bindings.len(), 2);
    let make = bindings.iter().find(|binding| binding.name == "make").unwrap();
    assert_eq!(
        make.signature,
        NativeCSignature {
            parameters: vec![NativeCType::I64],
            result: NativeCType::U32,
            variadic: false,
        }
    );
    let open = bindings.iter().find(|binding| binding.name == "open").unwrap();
    assert_eq!(
        open.signature,
        NativeCSignature {
            parameters: vec![NativeCType::U32, NativeCType::I32],
            result: NativeCType::Ptr,
            variadic: false,
        }
    );
}

#[test]
fn checked_c_float_metadata_retains_parameter_and_result_widths() {
    let interface = common::semantic_interface_with_timeout(
        74,
        &[r#"
module native::floats;
pub extern "C" fn mixed(value: f32, scale: f64, index: i32) -> f64;
pub extern "C" fn single() -> f32;
"#],
    )
    .expect("checked C floating-point interface");
    let bindings = interface
        .native_c_functions()
        .expect("float native bindings");
    assert_eq!(bindings.len(), 2);
    let mixed = bindings
        .iter()
        .find(|binding| binding.name == "mixed")
        .unwrap();
    assert_eq!(
        mixed.signature,
        NativeCSignature {
            parameters: vec![NativeCType::F32, NativeCType::F64, NativeCType::I32],
            result: NativeCType::F64,
            variadic: false,
        }
    );
    let single = bindings
        .iter()
        .find(|binding| binding.name == "single")
        .unwrap();
    assert_eq!(
        single.signature,
        NativeCSignature {
            parameters: vec![],
            result: NativeCType::F32,
            variadic: false,
        }
    );
}

#[test]
fn checked_c_metadata_preserves_private_identity_and_runtime_name_collisions() {
    let interface = common::semantic_interface_with_timeout(
        71,
        &[r#"
module native::api;
extern "C" fn private_c(value: i64, count: usize) -> ptr;
pub extern "C" fn close(value: i32) -> i32;
pub extern "C" fn format(output: ptr, size: usize, ...) -> i32;
pub extern "lanius_std" fn argc() -> i32;
pub extern "unbound" fn write(value: i32) -> i32;
"#],
    )
    .expect("checked C interface");
    let bindings = interface.native_c_functions().expect("checked bindings");
    assert_eq!(bindings.len(), 3);
    // `...` is a fact of the prototype: a flag, not a parameter.
    let format = bindings
        .iter()
        .find(|binding| binding.name == "format")
        .unwrap();
    assert_eq!(
        format.signature,
        NativeCSignature {
            parameters: vec![NativeCType::Ptr, NativeCType::Usize],
            result: NativeCType::I32,
            variadic: true,
        }
    );
    assert_eq!(
        interface.declarations[format.identity[2] as usize].flags,
        6
    );
    let private = bindings
        .iter()
        .find(|binding| binding.name == "private_c")
        .unwrap();
    assert_eq!(
        private.signature,
        NativeCSignature {
            parameters: vec![NativeCType::I64, NativeCType::Usize],
            result: NativeCType::Ptr,
            variadic: false,
        }
    );
    assert_eq!(
        &private.identity[..2],
        &[interface.library_id, interface.unit_id]
    );
    assert_eq!(
        interface.declarations[private.identity[2] as usize].flags,
        3
    );
    let close = bindings
        .iter()
        .find(|binding| binding.name == "close")
        .unwrap();
    assert_eq!(
        interface.declarations[close.identity[2] as usize].value_lo,
        u32::MAX,
        "a C function named close must retain a foreign call"
    );
    let named = |name: &str| {
        interface
            .declarations
            .iter()
            .find(|row| {
                &interface.name_bytes[row.name_byte_start as usize
                    ..(row.name_byte_start + row.name_byte_len) as usize]
                    == name.as_bytes()
            })
            .unwrap()
    };
    assert_eq!(named("argc").value_lo, 33);
    assert_eq!(named("write").value_lo, u32::MAX);

    common::type_check_source_pack_with_dependencies_with_timeout(
        72,
        &[r#"
module app::main;
import native::api;
fn main() -> i32 { return close(0); }
"#],
        vec![interface.clone()],
    )
    .expect("public C import");
    common::type_check_source_pack_with_dependencies_with_timeout(
        72,
        &[r#"
module app::main;
import native::api;
fn main() -> i32 { let value: ptr = private_c(0, 0); return 0; }
"#],
        vec![interface],
    )
    .expect_err("hidden C declarations must stay out of dependency name lookup");
}

#[test]
fn checked_c_signatures_accept_the_profile_parameter_limit() {
    let parameters = (0..32)
        .map(|index| format!("p{index}: i64"))
        .collect::<Vec<_>>()
        .join(", ");
    let source = format!("pub extern \"C\" fn native_thirty_two({parameters}) -> u64;");
    let interface =
        common::semantic_interface_with_timeout(73, &[&source]).expect("32 C parameters");
    let bindings = interface.native_c_functions().unwrap();
    assert_eq!(bindings[0].signature.parameters, vec![NativeCType::I64; 32]);
    assert_eq!(bindings[0].signature.result, NativeCType::U64);
    let source = source.replace(") -> u64", ", overflow: i64) -> u64");
    common::type_check_source_with_timeout(&source)
        .expect_err("33 C parameters exceed checked profile");
}
