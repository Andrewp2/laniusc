mod common;

use std::collections::BTreeSet;

use laniusc_compiler::{
    codegen::unit::{SourcePackArtifactTarget, SourcePackJob, SourcePackJobPhase},
    compiler::{
        CompileError,
        GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID,
        GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID,
        GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID,
        GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION,
        GpuSourcePackArtifactDescriptor,
        RUNTIME_BOUND_API_DIAGNOSTICS,
        RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        SourcePackHierarchicalLinkExecutionPage,
        SourcePackHierarchicalLinkGroupKind,
        SourcePackLinkDescriptorSummary,
        compile_entry_to_wasm_with_stdlib,
        diagnostic_explanation_json_pretty,
        load_entry_path_manifest_with_stdlib,
        runtime_bound_api_diagnostic_info,
        runtime_service_boundary_diagnostic_info,
        type_check_entry_with_stdlib,
    },
};

const RUNTIME_DESCRIPTOR_CONSTANTS: &[(&str, &str, &str)] = &[
    (
        "RUNTIME_ABI_METADATA_VERSION",
        "RuntimeAbiMetadataVersion",
        "1",
    ),
    ("UNKNOWN_RUNTIME_ABI_VERSION", "RuntimeAbiVersion", "0"),
    ("RUNTIME_ABI_VERSION", "RuntimeAbiVersion", "1"),
    ("RUNTIME_SERVICE_COUNT", "RuntimeServiceCount", "13"),
    ("FIRST_RUNTIME_SERVICE_ID", "RuntimeServiceId", "1"),
    ("LAST_RUNTIME_SERVICE_ID", "RuntimeServiceId", "13"),
    (
        "RUNTIME_SERVICE_REQUIREMENT_FIELD_COUNT",
        "RuntimeServiceRequirementFieldCount",
        "3",
    ),
    (
        "RUNTIME_SERVICE_REQUIREMENT_SERVICE_ID_FIELD",
        "RuntimeServiceRequirementFieldIndex",
        "0",
    ),
    (
        "RUNTIME_SERVICE_REQUIREMENT_ABI_VERSION_FIELD",
        "RuntimeServiceRequirementFieldIndex",
        "1",
    ),
    (
        "RUNTIME_SERVICE_REQUIREMENT_STATUS_FIELD",
        "RuntimeServiceRequirementFieldIndex",
        "2",
    ),
    ("SERVICE_STATUS_UNKNOWN", "RuntimeServiceStatus", "0"),
    ("SERVICE_STATUS_UNAVAILABLE", "RuntimeServiceStatus", "1"),
    ("SERVICE_STATUS_AVAILABLE", "RuntimeServiceStatus", "2"),
    ("SERVICE_ALLOCATOR_ID", "RuntimeServiceId", "1"),
    ("SERVICE_FILESYSTEM_ID", "RuntimeServiceId", "2"),
    ("SERVICE_STDIO_ID", "RuntimeServiceId", "3"),
    ("SERVICE_CLOCK_ID", "RuntimeServiceId", "4"),
    ("SERVICE_NETWORK_ID", "RuntimeServiceId", "5"),
    ("SERVICE_PANIC_HOOK_ID", "RuntimeServiceId", "6"),
    ("SERVICE_HOST_SERVICES_ID", "RuntimeServiceId", "7"),
    ("SERVICE_THREADS_ID", "RuntimeServiceId", "8"),
    ("SERVICE_SECURE_RNG_ID", "RuntimeServiceId", "9"),
    ("SERVICE_GPU_ID", "RuntimeServiceId", "10"),
    ("SERVICE_PROCESS_ID", "RuntimeServiceId", "11"),
    ("SERVICE_ENV_ID", "RuntimeServiceId", "12"),
    ("SERVICE_TEST_HARNESS_ID", "RuntimeServiceId", "13"),
];

fn runtime_descriptor_value(name: &str) -> u32 {
    RUNTIME_DESCRIPTOR_CONSTANTS
        .iter()
        .find_map(|(candidate, _, value)| (*candidate == name).then_some(*value))
        .unwrap_or_else(|| panic!("missing runtime descriptor constant {name}"))
        .parse()
        .unwrap_or_else(|err| panic!("runtime descriptor constant {name} must be numeric: {err}"))
}

fn runtime_service_values() -> Vec<(&'static str, u32)> {
    RUNTIME_DESCRIPTOR_CONSTANTS
        .iter()
        .filter(|(name, type_name, _)| {
            *type_name == "RuntimeServiceId" && name.starts_with("SERVICE_")
        })
        .map(|(name, _, value)| {
            (
                *name,
                value
                    .parse()
                    .unwrap_or_else(|err| panic!("{name} must be numeric: {err}")),
            )
        })
        .collect()
}

fn runtime_bound_api_is_compiler_backed(api_name: &str) -> bool {
    matches!(
        api_name,
        "alloc::allocator::alloc"
            | "alloc::allocator::dealloc"
            | "std::io::write_stdout"
            | "std::io::write_stderr"
            | "std::io::read_stdin"
            | "std::io::print_i32"
            | "std::random::secure_u32"
            | "std::process::argc"
            | "std::process::arg_len"
            | "std::process::arg_read"
            | "std::process::exit"
    )
}

fn link_job() -> SourcePackJob {
    SourcePackJob {
        job_index: 7,
        phase: SourcePackJobPhase::Link,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 0,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    }
}

fn link_execution_page(
    final_output: bool,
    required_runtime_service_ids: Vec<u32>,
) -> SourcePackHierarchicalLinkExecutionPage {
    SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: 7,
        input_interface_count: 1,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 1,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: if final_output {
            "wasm/linked-output/job-7/src-0-1".into()
        } else {
            "wasm/partial-link/group-00000000/job-00000007".into()
        },
        final_output,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            required_runtime_abi_version: (!required_runtime_service_ids.is_empty())
                .then_some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION),
            required_runtime_service_ids,
            ..SourcePackLinkDescriptorSummary::default()
        },
    }
}

#[test]
fn linked_output_descriptor_json_rejects_output_record_on_input_array() {
    let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    let json = serde_json::to_string(&descriptor).expect("serialize linked-output descriptor");
    let roundtrip = serde_json::from_str::<GpuSourcePackArtifactDescriptor>(&json)
        .expect("parse public linked-output descriptor JSON");
    roundtrip
        .validate_contract()
        .expect("round-tripped linked-output descriptor contract is valid");

    let mut document =
        serde_json::to_value(&roundtrip).expect("serialize linked-output descriptor as JSON value");
    let input_record_array_name = document
        .get("input_record_arrays")
        .and_then(serde_json::Value::as_array)
        .and_then(|arrays| arrays.first())
        .and_then(|array| array.get("name"))
        .and_then(serde_json::Value::as_str)
        .expect("linked-output descriptor JSON should include input record arrays")
        .to_owned();
    let descriptor_records = document
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("linked-output descriptor JSON should include descriptor records");
    let output_record = descriptor_records
        .iter_mut()
        .find(|record| record.get("flow").and_then(serde_json::Value::as_str) == Some("Output"))
        .expect("linked-output descriptor JSON should include output descriptor records");
    *output_record
        .get_mut("record_array")
        .expect("descriptor record should include a record_array") =
        serde_json::Value::String(input_record_array_name);

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with mismatched split array reference");
    let err = parsed
        .validate_contract()
        .expect_err("output descriptor records must not reference input arrays");
    assert!(
        err.contains("outside output record arrays"),
        "unexpected descriptor validation error: {err}"
    );
}

#[test]
fn linked_output_descriptor_json_rejects_reserved_array_without_matching_record() {
    let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor
        .validate_contract()
        .expect("baseline linked-output descriptor contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor as JSON");
    let custom_section_array = serde_json::json!({
        "name": "custom_linked_section_records",
    });
    for arrays_key in ["output_record_arrays", "record_arrays"] {
        document
            .get_mut(arrays_key)
            .and_then(serde_json::Value::as_array_mut)
            .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"))
            .push(custom_section_array.clone());
    }

    let descriptor_records = document
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("linked-output descriptor JSON should include descriptor records");
    let linked_section_record = descriptor_records
        .iter_mut()
        .find(|record| {
            record
                .get("record_array")
                .and_then(serde_json::Value::as_str)
                == Some("linked_section_records")
        })
        .expect("linked-output descriptor JSON should include linked section records");
    linked_section_record["record_array"] =
        serde_json::Value::String("custom_linked_section_records".into());

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with an uncovered reserved output array");
    let err = parsed
        .validate_contract()
        .expect_err("reserved flat record arrays must have matching descriptor records");
    assert!(
        err.contains("reserved record array"),
        "unexpected reserved array validation error: {err}"
    );
    assert!(
        err.contains("linked_section_records"),
        "unexpected reserved array validation error: {err}"
    );
    assert!(
        err.contains("exactly one descriptor record"),
        "unexpected reserved array validation error: {err}"
    );
}

#[test]
fn linked_output_descriptor_json_rejects_bounded_reserved_array_without_record_count() {
    let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor
        .validate_contract()
        .expect("baseline linked-output descriptor contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor as JSON");
    for arrays_key in ["output_record_arrays", "record_arrays"] {
        let linked_symbol_array = document
            .get_mut(arrays_key)
            .and_then(serde_json::Value::as_array_mut)
            .and_then(|arrays| {
                arrays.iter_mut().find(|array| {
                    array.get("name").and_then(serde_json::Value::as_str)
                        == Some("linked_symbol_records")
                })
            })
            .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"));
        linked_symbol_array["element_count"] = serde_json::Value::from(2);
    }

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document.clone())
        .expect("parse descriptor JSON with a bounded reserved record array");
    assert_eq!(
        parsed
            .output_record_arrays
            .iter()
            .find(|array| array.name == "linked_symbol_records")
            .and_then(|array| array.element_count),
        Some(2),
        "persisted descriptor should retain the bounded linked-symbol row count"
    );
    let err = parsed
        .validate_contract()
        .expect_err("bounded reserved arrays must have matching descriptor record counts");
    assert!(
        err.contains("linked_symbol_records"),
        "unexpected bounded array count validation error: {err}"
    );
    assert!(
        err.contains("does not declare an element count"),
        "unexpected bounded array count validation error: {err}"
    );
    assert!(
        err.contains("bounded reserved arrays"),
        "unexpected bounded array count validation error: {err}"
    );

    let descriptor_records = document
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("linked-output descriptor JSON should include descriptor records");
    let linked_symbol_record = descriptor_records
        .iter_mut()
        .find(|record| {
            record
                .get("record_array")
                .and_then(serde_json::Value::as_str)
                == Some("linked_symbol_records")
        })
        .expect("linked-output descriptor JSON should include linked symbol records");
    linked_symbol_record["element_count"] = serde_json::Value::from(2);

    serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with matching bounded row counts")
        .validate_contract()
        .expect("matching bounded reserved array and descriptor record counts should validate");
}

#[test]
fn linked_output_descriptor_json_rejects_counted_record_without_counted_array() {
    let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor
        .validate_contract()
        .expect("baseline linked-output descriptor contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor as JSON");
    let descriptor_records = document
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("linked-output descriptor JSON should include descriptor records");
    let linked_symbol_record = descriptor_records
        .iter_mut()
        .find(|record| {
            record
                .get("record_array")
                .and_then(serde_json::Value::as_str)
                == Some("linked_symbol_records")
        })
        .expect("linked-output descriptor JSON should include linked symbol records");
    linked_symbol_record["element_count"] = serde_json::Value::from(2);

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with a counted descriptor record");
    assert_eq!(
        parsed
            .descriptor_records
            .iter()
            .find(|record| record.record_array == "linked_symbol_records")
            .and_then(|record| record.element_count),
        Some(2),
        "persisted descriptor should retain the standalone descriptor record count"
    );
    let err = parsed
        .validate_contract()
        .expect_err("counted descriptor records must require counted backing arrays");
    assert!(
        err.contains("linked_symbol_records"),
        "unexpected counted descriptor validation error: {err}"
    );
    assert!(
        err.contains("is unbounded"),
        "unexpected counted descriptor validation error: {err}"
    );
    assert!(
        err.contains("counted flat record arrays"),
        "unexpected counted descriptor validation error: {err}"
    );
}

#[test]
fn core_runtime_declared_service_ids_are_artifact_descriptor_contract_ids() {
    let service_ids = runtime_service_values();
    assert_eq!(
        service_ids.len(),
        GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT,
        "runtime contract should enumerate the expected active service descriptors"
    );
    assert_eq!(
        runtime_descriptor_value("RUNTIME_SERVICE_COUNT") as usize,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT,
        "core::runtime service count should match artifact descriptor runtime inventory"
    );
    assert_eq!(
        runtime_descriptor_value("FIRST_RUNTIME_SERVICE_ID"),
        GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID,
        "core::runtime first service id should match artifact descriptor runtime inventory"
    );
    assert_eq!(
        runtime_descriptor_value("LAST_RUNTIME_SERVICE_ID"),
        GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID,
        "core::runtime last service id should match artifact descriptor runtime inventory"
    );
    assert_eq!(
        runtime_descriptor_value("RUNTIME_ABI_VERSION"),
        GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
        "core::runtime ABI version should match artifact descriptor runtime ABI"
    );
    assert_eq!(
        service_ids
            .iter()
            .map(|(_, service_id)| *service_id)
            .collect::<Vec<_>>(),
        GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS.to_vec(),
        "core::runtime service ids should match artifact descriptor runtime ids"
    );

    for (service_name, service_id) in service_ids {
        let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &link_job(),
            0,
            1,
        );
        descriptor.set_required_runtime_services([service_id]);
        descriptor
            .output_record_arrays
            .retain(|array| array.name != "emitted_byte_records");
        descriptor
            .record_arrays
            .retain(|array| array.name != "emitted_byte_records");

        descriptor.validate_contract().unwrap_or_else(|err| {
            panic!("{service_name} ({service_id}) should be accepted as runtime contract metadata: {err}")
        });
    }
}

#[test]
fn runtime_service_boundary_diagnostic_catalog_matches_runtime_contract_ids() {
    let service_ids = runtime_service_values();
    assert_eq!(
        RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len(),
        service_ids.len(),
        "runtime boundary diagnostics should cover every declared runtime service"
    );
    assert_eq!(
        RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
            .iter()
            .map(|service| service.service_id)
            .collect::<Vec<_>>(),
        GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS.to_vec(),
        "runtime boundary diagnostics should use the canonical service-id order"
    );

    for ((service_constant, service_id), diagnostic) in service_ids
        .iter()
        .zip(RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.iter())
    {
        assert_eq!(
            diagnostic.diagnostic_code, "LNC0038",
            "{service_constant} should route known-unbound service failures through LNC0038"
        );
        assert_eq!(
            diagnostic.service_id, *service_id,
            "{service_constant} should share the stdlib/runtime descriptor id"
        );
        assert_eq!(
            diagnostic.current_status, "known-unbound",
            "{service_constant} should remain a known but unbound runtime boundary"
        );
        assert!(
            !diagnostic.executable,
            "{service_constant} must not become executable without a runtime binding"
        );
        assert_eq!(
            runtime_service_boundary_diagnostic_info(*service_id),
            Some(diagnostic),
            "{service_constant} should be discoverable by service id"
        );
    }
    assert!(
        runtime_service_boundary_diagnostic_info(0).is_none(),
        "unknown runtime service ids should not be described as known LNC0038 boundaries"
    );
}

#[test]
fn runtime_bound_api_diagnostic_catalog_keeps_stdlib_externs_fail_closed() {
    assert!(
        RUNTIME_BOUND_API_DIAGNOSTICS
            .iter()
            .filter(|api| !runtime_bound_api_is_compiler_backed(api.api_name))
            .all(|api| api.diagnostic_code == "LNC0038"
                && api.current_status == "known-unbound"
                && !api.executable),
        "runtime-bound API diagnostics must not mark any stdlib extern executable"
    );

    for api in RUNTIME_BOUND_API_DIAGNOSTICS {
        let service =
            runtime_service_boundary_diagnostic_info(api.service_id).unwrap_or_else(|| {
                panic!(
                    "{} should point at a known runtime service boundary",
                    api.api_name
                )
            });
        assert_eq!(
            api.service_capability_constant, service.capability_constant,
            "{} should carry the service-level capability constant",
            api.api_name
        );
        assert_eq!(
            api.service_module_path, service.module_path,
            "{} should carry the service-level module path",
            api.api_name
        );
        assert_eq!(
            api.service_status_probe, service.status_probe,
            "{} should carry the service-level status probe",
            api.api_name
        );
        assert_eq!(
            api.service_binding_probe, service.binding_probe,
            "{} should point at a known runtime service boundary",
            api.api_name
        );
        assert_eq!(
            api.service_current_status, service.current_status,
            "{} should carry the owning service status",
            api.api_name
        );
        assert_eq!(
            api.service_executable, service.executable,
            "{} should carry the owning service executable flag",
            api.api_name
        );
        assert!(
            api.api_name.starts_with(api.module_path),
            "{} should be namespaced under its stdlib module",
            api.api_name
        );
        assert_eq!(
            runtime_bound_api_diagnostic_info(api.api_name),
            Some(api),
            "{} should be discoverable by its qualified API name",
            api.api_name
        );
    }

    let write_stdout = runtime_bound_api_diagnostic_info("std::io::write_stdout")
        .expect("stdio write_stdout should have a public runtime-bound API row");
    assert_eq!(
        write_stdout.service_id, GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        "stdio write_stdout should map to the stdio runtime service"
    );
    assert_eq!(write_stdout.module_path, "std::io");
    let stdio_service =
        runtime_service_boundary_diagnostic_info(GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID)
            .expect("stdio runtime service boundary should be public");
    assert_eq!(
        write_stdout.service_capability_constant,
        stdio_service.capability_constant
    );
    assert_eq!(write_stdout.service_module_path, stdio_service.module_path);
    assert_eq!(
        write_stdout.service_status_probe,
        stdio_service.status_probe
    );
    assert_eq!(
        write_stdout.service_binding_probe,
        stdio_service.binding_probe
    );
    assert_eq!(
        write_stdout.service_current_status,
        stdio_service.current_status
    );
    assert_eq!(write_stdout.service_executable, stdio_service.executable);
    assert_eq!(
        write_stdout.executable_probe, "write_stdout_is_executable()",
        "stdio write_stdout should expose the exact executable probe"
    );
    assert!(
        !write_stdout.binding_probe.trim().is_empty(),
        "runtime-bound API rows should expose a binding probe label for tooling"
    );
    let print_i32 = runtime_bound_api_diagnostic_info("std::io::print_i32")
        .expect("stdio print_i32 should have a public executable API row");
    assert_eq!(
        print_i32.service_id,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID
    );
    assert_eq!(print_i32.module_path, "std::io");
    assert_eq!(print_i32.extern_abi, "compiler_print_i32");
    assert_eq!(print_i32.executable_probe, "print_i32_is_executable()");
    assert_eq!(
        print_i32.binding_probe,
        "print_i32_requires_runtime_binding()"
    );
    assert_eq!(print_i32.current_status, "executable-compiler-primitive");
    assert!(print_i32.executable);
    assert_eq!(
        print_i32.service_current_status,
        stdio_service.current_status
    );
    assert_eq!(print_i32.service_executable, stdio_service.executable);
    assert!(
        runtime_bound_api_diagnostic_info("std::io::println").is_none(),
        "unknown stdlib APIs should not be described as known runtime boundaries"
    );
}

#[test]
fn runtime_bound_api_diagnostic_catalog_exposes_extern_abi_namespaces() {
    let json = diagnostic_explanation_json_pretty("LNC0038")
        .expect("runtime-bound diagnostic explanation should serialize");
    let explanation: serde_json::Value =
        serde_json::from_str(&json).expect("runtime-bound diagnostic explanation should parse");
    let apis = explanation["runtime_bound_apis"]
        .as_array()
        .expect("LNC0038 explanation should include runtime-bound API rows");

    for (api_name, service_id, extern_abi, current_status, executable) in [
        (
            "alloc::allocator::alloc",
            1,
            "lanius_alloc",
            "executable-compiler-primitive",
            true,
        ),
        (
            "std::io::write_stdout",
            3,
            "compiler_host_stdio",
            "executable-compiler-primitive",
            true,
        ),
        (
            "core::panic::panic",
            6,
            "lanius_panic",
            "known-unbound",
            false,
        ),
    ] {
        let api = runtime_bound_api_diagnostic_info(api_name)
            .unwrap_or_else(|| panic!("{api_name} should have a runtime-bound API row"));
        assert_eq!(api.extern_abi, extern_abi);
        assert!(apis.iter().any(|row| {
            row["api_name"] == api_name
                && row["service_id"] == service_id
                && row["extern_abi"] == extern_abi
                && row["current_status"] == current_status
                && row["executable"] == executable
        }));
    }
}

#[test]
fn runtime_bound_api_diagnostic_catalog_has_unambiguous_service_api_selectors() {
    let mut qualified_api_names = BTreeSet::new();
    let mut service_api_selectors = BTreeSet::new();

    for api in RUNTIME_BOUND_API_DIAGNOSTICS {
        assert!(
            qualified_api_names.insert(api.api_name),
            "{} should appear only once in the runtime-bound API catalog",
            api.api_name
        );
        let (_, api_leaf_name) = api
            .api_name
            .rsplit_once("::")
            .unwrap_or_else(|| panic!("{} should be a qualified stdlib API", api.api_name));
        let service_api_selector = format!("{}::{}", api.service_name, api_leaf_name);
        assert!(
            service_api_selectors.insert(service_api_selector.clone()),
            "{service_api_selector} should identify exactly one runtime-bound API"
        );

        let service = runtime_service_boundary_diagnostic_info(api.service_id)
            .unwrap_or_else(|| panic!("{} should map to a runtime service", api.api_name));
        assert_eq!(
            api.service_name, service.service_name,
            "{service_api_selector} should use the owning runtime service name"
        );
        assert!(
            api.accepted_selector_kinds.contains(&"service_api_name")
                && service
                    .accepted_selector_kinds
                    .contains(&"service_api_name"),
            "{service_api_selector} should remain a public no-run selector"
        );
        if runtime_bound_api_is_compiler_backed(api.api_name) {
            assert_eq!(api.current_status, "executable-compiler-primitive");
            assert!(api.executable);
            if api.api_name == "std::io::print_i32" {
                assert_eq!(api.extern_abi, "compiler_print_i32");
            } else if api.api_name.starts_with("std::io::") {
                assert_eq!(api.extern_abi, "compiler_host_stdio");
            } else if api.api_name.starts_with("alloc::allocator::") {
                assert_eq!(api.extern_abi, "lanius_alloc");
            } else {
                assert_eq!(api.extern_abi, "lanius_std");
            }
        } else {
            assert_eq!(api.current_status, "known-unbound");
            assert!(
                !api.executable,
                "{service_api_selector} must remain contract-only until a runtime binding exists"
            );
        }
        assert_eq!(service.current_status, "known-unbound");
        assert!(
            !service.executable,
            "{service_api_selector} should not make the whole service executable"
        );
    }

    assert!(
        service_api_selectors.contains("stdio::write_stdout"),
        "the documented stdio service-qualified selector should stay available"
    );
    assert!(
        service_api_selectors.contains("stdio::print_i32"),
        "the executable stdio print_i32 selector should stay available"
    );
    assert_eq!(
        service_api_selectors.len(),
        RUNTIME_BOUND_API_DIAGNOSTICS.len(),
        "service-qualified runtime API selectors should cover every public runtime-bound API row"
    );
}

#[test]
fn process_exit_runtime_contract_distinguishes_bound_apis_from_exit_code_helpers() {
    let process_service_id = runtime_descriptor_value("SERVICE_PROCESS_ID");
    let process_service = runtime_service_boundary_diagnostic_info(process_service_id)
        .expect("process runtime service boundary should be public");

    let set_exit_code = runtime_bound_api_diagnostic_info("std::process::set_exit_code")
        .expect("std::process::set_exit_code should have a public runtime-bound API row");
    assert_eq!(
        set_exit_code.service_id, process_service_id,
        "std::process::set_exit_code should require the process runtime service"
    );
    assert_eq!(set_exit_code.module_path, "std::process");
    assert_eq!(
        set_exit_code.service_module_path,
        process_service.module_path
    );
    assert_eq!(
        set_exit_code.service_current_status,
        process_service.current_status
    );
    assert_eq!(set_exit_code.service_executable, process_service.executable);
    assert_eq!(set_exit_code.current_status, "known-unbound");
    assert!(
        !set_exit_code.executable,
        "std::process::set_exit_code must stay non-executable until it is bound"
    );

    for api_name in ["std::process::exit"] {
        let api = runtime_bound_api_diagnostic_info(api_name)
            .unwrap_or_else(|| panic!("{api_name} should have a public runtime-bound API row"));
        assert_eq!(
            api.service_id, process_service_id,
            "{api_name} should require the process runtime service"
        );
        assert_eq!(api.module_path, "std::process");
        assert_eq!(api.service_module_path, process_service.module_path);
        assert_eq!(api.service_current_status, process_service.current_status);
        assert_eq!(api.service_executable, process_service.executable);
        assert_eq!(api.current_status, "executable-compiler-primitive");
        assert!(
            api.executable,
            "{api_name} should be executable through the x86 backend"
        );
    }

    for helper_name in [
        "std::process::exit_success_code",
        "std::process::exit_failure_code",
        "std::process::exit_code_from_success",
        "std::process::exit_code_is_success",
        "std::process::exit_code_is_failure",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a pure exit-code helper, not a runtime-bound API"
        );
    }
}

#[test]
fn test_assert_helpers_do_not_require_test_harness_runtime_binding() {
    let harness_service =
        runtime_service_boundary_diagnostic_info(GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID)
            .expect("test harness runtime service boundary should be public");
    assert_eq!(
        harness_service.service_id,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID
    );
    assert_eq!(harness_service.module_path, "test::harness");
    assert_eq!(harness_service.current_status, "known-unbound");
    assert!(
        !harness_service.executable,
        "test harness service must stay non-executable until a runtime binding exists"
    );

    for helper_name in [
        "test::assert::is_true",
        "test::assert::is_false",
        "test::assert::eq_i32",
        "test::assert::ne_i32",
        "test::assert::lt_i32",
        "test::assert::le_i32",
        "test::assert::gt_i32",
        "test::assert::ge_i32",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} should remain usable without the test harness runtime service"
        );
    }
}

#[test]
fn runtime_boundary_explanation_keeps_stdlib_apis_contract_only() {
    let json = diagnostic_explanation_json_pretty("lnc0038")
        .expect("runtime-bound diagnostic explanation should serialize");
    let explanation: serde_json::Value =
        serde_json::from_str(&json).expect("runtime-bound diagnostic explanation should parse");

    assert_eq!(explanation["requested_code"], "LNC0038");
    let services = explanation["runtime_service_boundaries"]
        .as_array()
        .expect("LNC0038 explanation should include runtime service rows");
    let stdio_service = services
        .iter()
        .find(|service| {
            service["service_id"].as_u64()
                == Some(u64::from(GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID))
        })
        .expect("LNC0038 explanation should include the stdio service boundary");
    assert_eq!(stdio_service["module_path"], "std::io");
    assert_eq!(stdio_service["current_status"], "known-unbound");
    assert_eq!(stdio_service["executable"], false);
    assert!(
        stdio_service["binding_probe"]
            .as_str()
            .is_some_and(|probe| !probe.trim().is_empty()),
        "runtime service rows should expose a binding probe label for tooling"
    );

    let apis = explanation["runtime_bound_apis"]
        .as_array()
        .expect("LNC0038 explanation should include runtime-bound stdlib API rows");
    let write_stdout = apis
        .iter()
        .find(|api| api["api_name"] == "std::io::write_stdout")
        .expect("LNC0038 explanation should include std::io::write_stdout");
    assert_eq!(
        write_stdout["service_id"].as_u64(),
        Some(u64::from(GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID))
    );
    assert_eq!(
        write_stdout["service_module_path"],
        stdio_service["module_path"]
    );
    assert_eq!(
        write_stdout["service_current_status"],
        stdio_service["current_status"]
    );
    assert_eq!(
        write_stdout["service_binding_probe"],
        stdio_service["binding_probe"]
    );
    assert_eq!(
        write_stdout["service_executable"],
        stdio_service["executable"]
    );
    assert_eq!(
        write_stdout["current_status"],
        "executable-compiler-primitive"
    );
    assert_eq!(write_stdout["executable"], true);
    assert!(
        write_stdout["executable_probe"]
            .as_str()
            .is_some_and(|probe| !probe.trim().is_empty()),
        "runtime-bound API rows should expose an executable probe label for tooling"
    );
    assert!(
        write_stdout["binding_probe"]
            .as_str()
            .is_some_and(|probe| !probe.trim().is_empty()),
        "runtime-bound API rows should expose a binding probe label for tooling"
    );
    let print_i32 = apis
        .iter()
        .find(|api| api["api_name"] == "std::io::print_i32")
        .expect("LNC0038 explanation should include executable std::io::print_i32");
    assert_eq!(
        print_i32["service_id"].as_u64(),
        Some(u64::from(GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID))
    );
    assert_eq!(print_i32["extern_abi"], "compiler_print_i32");
    assert_eq!(print_i32["service_current_status"], "known-unbound");
    assert_eq!(print_i32["service_executable"], false);
    assert_eq!(print_i32["current_status"], "executable-compiler-primitive");
    assert_eq!(print_i32["executable"], true);

    assert!(
        apis.iter()
            .filter(|api| {
                !api["api_name"]
                    .as_str()
                    .is_some_and(runtime_bound_api_is_compiler_backed)
            })
            .all(|api| {
                api["diagnostic_code"] == "LNC0038"
                    && api["current_status"] == "known-unbound"
                    && api["executable"] == false
                    && api["service_current_status"] == "known-unbound"
                    && api["service_executable"] == false
            }),
        "runtime-bound stdlib APIs must stay contract-only until their service is bound"
    );
}

#[test]
fn core_runtime_service_ids_gate_linked_output_contract_bytes() {
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor.set_required_runtime_services([stdio_service_id]);

    let err = descriptor
        .validate_contract()
        .expect_err("runtime-bound linked-output descriptors must not declare target bytes");
    assert!(err.contains("target-byte output record array"));
    assert!(err.contains("unbound runtime services"));

    descriptor
        .output_record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .validate_contract()
        .expect("runtime-bound descriptor should remain valid as contract metadata only");

    let json = serde_json::to_string(&descriptor).expect("serialize runtime-bound descriptor");
    let document =
        serde_json::from_str::<serde_json::Value>(&json).expect("parse runtime descriptor JSON");
    let required_abi_version = document
        .get("required_runtime_abi_version")
        .and_then(|value| value.as_u64())
        .expect("runtime descriptor JSON should persist the required runtime ABI version");
    assert_eq!(
        required_abi_version,
        u64::from(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION),
        "runtime-bound descriptor should persist the stdlib ABI contract"
    );
    let required_service_ids = document
        .get("required_runtime_service_ids")
        .and_then(|value| value.as_array())
        .expect("runtime descriptor JSON should persist required service ids")
        .iter()
        .map(|value| value.as_u64())
        .collect::<Option<Vec<_>>>()
        .expect("runtime descriptor service ids should be numeric");
    assert_eq!(
        required_service_ids,
        vec![u64::from(stdio_service_id)],
        "runtime-bound descriptor should persist the stdlib service id contract"
    );
}

#[test]
fn runtime_bound_descriptor_persists_flat_service_requirement_rows() {
    let allocator_service_id = runtime_descriptor_value("SERVICE_ALLOCATOR_ID");
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let unavailable_status = runtime_descriptor_value("SERVICE_STATUS_UNAVAILABLE");
    let available_status = runtime_descriptor_value("SERVICE_STATUS_AVAILABLE");
    let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor.set_required_runtime_services([stdio_service_id, allocator_service_id]);
    descriptor
        .output_record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .validate_contract()
        .expect("runtime-bound descriptor rows should be valid contract metadata");

    let document =
        serde_json::to_value(&descriptor).expect("serialize runtime service descriptor rows");
    let required_service_ids = document
        .get("required_runtime_service_ids")
        .and_then(|value| value.as_array())
        .expect("runtime descriptor JSON should persist required service ids")
        .iter()
        .map(|value| value.as_u64())
        .collect::<Option<Vec<_>>>()
        .expect("runtime descriptor service ids should be numeric");
    assert_eq!(
        required_service_ids,
        vec![u64::from(allocator_service_id), u64::from(stdio_service_id)],
        "runtime descriptor service ids should be canonicalized for link queues"
    );

    let required_service_rows = document
        .get("required_runtime_services")
        .and_then(|value| value.as_array())
        .expect("runtime descriptor JSON should persist flat service requirement rows");
    assert_eq!(
        required_service_rows.len(),
        required_service_ids.len(),
        "runtime descriptor rows should align one-for-one with the service id list"
    );
    for (row, expected_service_id) in required_service_rows
        .iter()
        .zip([allocator_service_id, stdio_service_id])
    {
        assert_eq!(
            row.get("service_id").and_then(|value| value.as_u64()),
            Some(u64::from(expected_service_id)),
            "runtime service requirement row should carry the canonical service id"
        );
        assert_eq!(
            row.get("required_abi_version")
                .and_then(|value| value.as_u64()),
            Some(u64::from(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION)),
            "runtime service requirement row should pin the stdlib runtime ABI"
        );
        assert_eq!(
            row.get("service_status").and_then(|value| value.as_u64()),
            Some(u64::from(unavailable_status)),
            "runtime service requirement row should remain contract-only and unavailable"
        );
    }
    serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document.clone())
        .expect("parse persisted runtime service descriptor rows")
        .validate_contract()
        .expect("persisted runtime service descriptor rows should validate");

    let mut invalid_document = document;
    let service_rows = invalid_document
        .get_mut("required_runtime_services")
        .and_then(|value| value.as_array_mut())
        .expect("runtime descriptor JSON should expose mutable service rows");
    service_rows[1]["service_status"] = serde_json::Value::from(available_status);
    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(invalid_document)
        .expect("parse descriptor JSON with an invalid runtime service status row");
    let err = parsed
        .validate_contract()
        .expect_err("runtime service rows must not claim executable bindings");
    assert!(
        err.contains("claims available status"),
        "unexpected runtime service row validation error: {err}"
    );
}

#[test]
fn runtime_bound_descriptor_exposes_service_requirements_as_descriptor_records() {
    let allocator_service_id = runtime_descriptor_value("SERVICE_ALLOCATOR_ID");
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor.set_required_runtime_services([stdio_service_id, allocator_service_id]);
    descriptor
        .output_record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .validate_contract()
        .expect("runtime-bound descriptor should expose service rows as descriptor records");

    let document = serde_json::to_value(&descriptor).expect("serialize runtime descriptor records");
    let row_count = 2_u64;
    let field_count = runtime_descriptor_value("RUNTIME_SERVICE_REQUIREMENT_FIELD_COUNT");
    assert_eq!(
        runtime_descriptor_value("RUNTIME_SERVICE_REQUIREMENT_SERVICE_ID_FIELD"),
        0,
        "runtime service requirement rows should start with the service id"
    );
    assert_eq!(
        runtime_descriptor_value("RUNTIME_SERVICE_REQUIREMENT_ABI_VERSION_FIELD"),
        1,
        "runtime service requirement rows should pin the ABI version in the second field"
    );
    assert_eq!(
        runtime_descriptor_value("RUNTIME_SERVICE_REQUIREMENT_STATUS_FIELD"),
        2,
        "runtime service requirement rows should carry service status in the third field"
    );
    let row_byte_len =
        row_count * u64::from(field_count) * u64::try_from(std::mem::size_of::<u32>()).unwrap();
    for arrays_key in ["output_record_arrays", "record_arrays"] {
        let runtime_array = document
            .get(arrays_key)
            .and_then(serde_json::Value::as_array)
            .and_then(|arrays| {
                arrays.iter().find(|array| {
                    array.get("name").and_then(serde_json::Value::as_str)
                        == Some("runtime_service_requirement_records")
                })
            })
            .unwrap_or_else(|| {
                panic!("{arrays_key} should include runtime service requirement records")
            });
        assert_eq!(
            runtime_array
                .get("element_count")
                .and_then(serde_json::Value::as_u64),
            Some(row_count),
            "runtime service requirement record arrays should count service rows"
        );
        assert_eq!(
            runtime_array
                .get("byte_len")
                .and_then(serde_json::Value::as_u64),
            Some(row_byte_len),
            "runtime service requirement record arrays should describe three u32 fields per row"
        );
    }

    let runtime_record = document
        .get("descriptor_records")
        .and_then(serde_json::Value::as_array)
        .and_then(|records| {
            records.iter().find(|record| {
                record
                    .get("record_array")
                    .and_then(serde_json::Value::as_str)
                    == Some("runtime_service_requirement_records")
            })
        })
        .expect("descriptor records should include runtime service requirement rows");
    assert_eq!(
        runtime_record
            .get("domain")
            .and_then(serde_json::Value::as_str),
        Some("LinkedOutput"),
        "linked-output runtime service rows should be linked-output descriptor records"
    );
    assert_eq!(
        runtime_record
            .get("kind")
            .and_then(serde_json::Value::as_str),
        Some("RuntimeService"),
        "runtime service rows should use a public semantic descriptor record kind"
    );
    assert_eq!(
        runtime_record
            .get("flow")
            .and_then(serde_json::Value::as_str),
        Some("Output"),
        "runtime service rows should be output contract records"
    );
    assert_eq!(
        runtime_record
            .get("element_count")
            .and_then(serde_json::Value::as_u64),
        Some(row_count),
        "runtime service descriptor record should count the same rows as the service id set"
    );

    let mut missing_record = document;
    missing_record
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should expose descriptor records")
        .retain(|record| {
            record
                .get("record_array")
                .and_then(serde_json::Value::as_str)
                != Some("runtime_service_requirement_records")
        });
    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(missing_record)
        .expect("parse descriptor JSON missing runtime service descriptor record");
    let err = parsed
        .validate_contract()
        .expect_err("runtime-bound descriptors must tie service rows to descriptor records");
    assert!(
        err.contains("runtime service requirement records"),
        "unexpected runtime service descriptor record validation error: {err}"
    );
}

#[test]
fn runtime_service_requirements_are_a_canonical_descriptor_set() {
    let allocator_service_id = runtime_descriptor_value("SERVICE_ALLOCATOR_ID");
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor.set_required_runtime_services([
        stdio_service_id,
        allocator_service_id,
        stdio_service_id,
    ]);
    descriptor
        .output_record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .validate_contract()
        .expect("runtime services supplied through the builder should form a valid canonical set");

    assert_eq!(
        descriptor.required_runtime_service_ids,
        vec![allocator_service_id, stdio_service_id],
        "descriptor builders should sort and deduplicate runtime service ids"
    );
    assert_eq!(
        descriptor
            .required_runtime_services
            .iter()
            .map(|row| row.service_id)
            .collect::<Vec<_>>(),
        descriptor.required_runtime_service_ids,
        "runtime service rows should stay one-for-one with the canonical id set"
    );

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize canonical runtime descriptor");
    document
        .get_mut("required_runtime_service_ids")
        .and_then(serde_json::Value::as_array_mut)
        .expect("runtime descriptor JSON should expose service ids")
        .push(serde_json::Value::from(stdio_service_id));
    let duplicate_stdio_row = document
        .get("required_runtime_services")
        .and_then(serde_json::Value::as_array)
        .and_then(|rows| {
            rows.iter().find(|row| {
                row.get("service_id").and_then(serde_json::Value::as_u64)
                    == Some(u64::from(stdio_service_id))
            })
        })
        .cloned()
        .expect("runtime descriptor JSON should include a stdio service row");
    document
        .get_mut("required_runtime_services")
        .and_then(serde_json::Value::as_array_mut)
        .expect("runtime descriptor JSON should expose service rows")
        .push(duplicate_stdio_row);

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with a duplicated persisted runtime service id");
    let err = parsed
        .validate_contract()
        .expect_err("persisted duplicate runtime service ids must fail closed");
    assert!(
        err.contains("runtime service id 3 more than once"),
        "unexpected duplicate runtime service id validation error: {err}"
    );
}

#[test]
fn runtime_bound_descriptor_persists_runtime_abi_inventory_metadata() {
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor.set_required_runtime_services([stdio_service_id]);
    descriptor
        .output_record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .validate_contract()
        .expect("runtime-bound descriptor should persist ABI inventory metadata");

    let document =
        serde_json::to_value(&descriptor).expect("serialize runtime ABI inventory metadata");
    let runtime_abi = document
        .get("runtime_abi")
        .and_then(serde_json::Value::as_object)
        .expect("runtime-bound descriptor JSON should persist runtime ABI metadata");
    assert_eq!(
        runtime_abi
            .get("metadata_version")
            .and_then(serde_json::Value::as_u64),
        Some(u64::from(runtime_descriptor_value(
            "RUNTIME_ABI_METADATA_VERSION"
        ))),
        "runtime ABI metadata should carry the metadata format version"
    );
    assert_eq!(
        runtime_abi
            .get("abi_version")
            .and_then(serde_json::Value::as_u64),
        Some(u64::from(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION)),
        "runtime ABI metadata should pin the active runtime ABI"
    );
    assert_eq!(
        runtime_abi
            .get("service_count")
            .and_then(serde_json::Value::as_u64),
        Some(u64::from(runtime_descriptor_value("RUNTIME_SERVICE_COUNT"))),
        "runtime ABI metadata should expose the service inventory size"
    );
    assert_eq!(
        runtime_abi
            .get("first_service_id")
            .and_then(serde_json::Value::as_u64),
        Some(u64::from(runtime_descriptor_value(
            "FIRST_RUNTIME_SERVICE_ID"
        ))),
        "runtime ABI metadata should expose the first valid service id"
    );
    assert_eq!(
        runtime_abi
            .get("last_service_id")
            .and_then(serde_json::Value::as_u64),
        Some(u64::from(runtime_descriptor_value(
            "LAST_RUNTIME_SERVICE_ID"
        ))),
        "runtime ABI metadata should expose the last valid service id"
    );
    serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document.clone())
        .expect("parse persisted runtime ABI metadata")
        .validate_contract()
        .expect("persisted runtime ABI metadata should validate");

    let mut missing_metadata = document.clone();
    missing_metadata
        .as_object_mut()
        .expect("descriptor JSON should be an object")
        .remove("runtime_abi");
    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(missing_metadata)
        .expect("parse descriptor JSON missing runtime ABI metadata");
    let err = parsed
        .validate_contract()
        .expect_err("runtime-bound descriptors must persist ABI inventory metadata");
    assert!(
        err.contains("must persist runtime ABI metadata"),
        "unexpected runtime ABI metadata validation error: {err}"
    );

    let mut bad_inventory = document;
    bad_inventory["runtime_abi"]["service_count"] =
        serde_json::Value::from(runtime_descriptor_value("RUNTIME_SERVICE_COUNT") + 1);
    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(bad_inventory)
        .expect("parse descriptor JSON with bad runtime service inventory metadata");
    let err = parsed
        .validate_contract()
        .expect_err("runtime ABI metadata service inventory must match the stdlib contract");
    assert!(
        err.contains("runtime ABI metadata records service count"),
        "unexpected runtime ABI metadata inventory error: {err}"
    );
}

#[test]
fn descriptor_json_rejects_runtime_abi_metadata_without_required_services() {
    let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor
        .validate_contract()
        .expect("plain linked-output descriptor should not require runtime metadata");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor JSON");
    document["runtime_abi"] = serde_json::json!({
        "metadata_version": runtime_descriptor_value("RUNTIME_ABI_METADATA_VERSION"),
        "abi_version": runtime_descriptor_value("RUNTIME_ABI_VERSION"),
        "service_count": runtime_descriptor_value("RUNTIME_SERVICE_COUNT"),
        "first_service_id": runtime_descriptor_value("FIRST_RUNTIME_SERVICE_ID"),
        "last_service_id": runtime_descriptor_value("LAST_RUNTIME_SERVICE_ID"),
    });

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with orphan runtime ABI metadata");
    let roundtrip_json =
        serde_json::to_string(&parsed).expect("roundtrip descriptor with runtime ABI metadata");
    let roundtrip = serde_json::from_str::<GpuSourcePackArtifactDescriptor>(&roundtrip_json)
        .expect("parse round-tripped descriptor with orphan runtime ABI metadata");
    let err = roundtrip
        .validate_contract()
        .expect_err("runtime ABI metadata must be tied to required service ids");
    assert!(
        err.contains("runtime ABI metadata without required runtime service ids"),
        "unexpected runtime ABI metadata validation error: {err}"
    );
}

#[test]
fn link_descriptor_summary_runtime_services_persist_partial_rows_and_gate_final_bytes() {
    let allocator_service_id = runtime_descriptor_value("SERVICE_ALLOCATOR_ID");
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let unavailable_status = runtime_descriptor_value("SERVICE_STATUS_UNAVAILABLE");

    let partial_page = link_execution_page(false, vec![allocator_service_id, stdio_service_id]);
    let partial_descriptor =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&partial_page, 1, 1, 0);
    partial_descriptor
        .validate_contract()
        .expect("partial-link descriptors may carry unbound runtime requirements as metadata");
    assert_eq!(
        partial_descriptor.required_runtime_service_ids,
        vec![allocator_service_id, stdio_service_id],
        "partial-link descriptors should preserve canonical runtime service requirements"
    );

    let document = serde_json::to_value(&partial_descriptor)
        .expect("serialize partial-link runtime service descriptor");
    let service_rows = document
        .get("required_runtime_services")
        .and_then(|value| value.as_array())
        .expect("partial-link descriptor should persist runtime service rows");
    assert_eq!(
        service_rows.len(),
        partial_descriptor.required_runtime_service_ids.len(),
        "runtime requirement rows should stay one-for-one with the link summary services"
    );
    for (row, service_id) in service_rows
        .iter()
        .zip(partial_descriptor.required_runtime_service_ids.iter())
    {
        assert_eq!(
            row.get("service_id").and_then(|value| value.as_u64()),
            Some(u64::from(*service_id))
        );
        assert_eq!(
            row.get("service_status").and_then(|value| value.as_u64()),
            Some(u64::from(unavailable_status)),
            "link-summary runtime rows should remain unbound contract metadata"
        );
    }
    let runtime_record = document
        .get("descriptor_records")
        .and_then(serde_json::Value::as_array)
        .and_then(|records| {
            records.iter().find(|record| {
                record
                    .get("record_array")
                    .and_then(serde_json::Value::as_str)
                    == Some("runtime_service_requirement_records")
            })
        })
        .expect("partial-link descriptor should expose runtime service rows as descriptor records");
    assert_eq!(
        runtime_record
            .get("domain")
            .and_then(serde_json::Value::as_str),
        Some("PartialLink"),
        "link-summary runtime rows should become partial-link descriptor records"
    );
    assert_eq!(
        runtime_record
            .get("kind")
            .and_then(serde_json::Value::as_str),
        Some("RuntimeService"),
        "link-summary runtime rows should preserve the runtime-service record kind"
    );
    assert_eq!(
        runtime_record
            .get("element_count")
            .and_then(serde_json::Value::as_u64),
        Some(u64::try_from(partial_descriptor.required_runtime_service_ids.len()).unwrap()),
        "link-summary runtime record count should match the canonical service-id set"
    );

    let final_page = link_execution_page(true, vec![stdio_service_id]);
    let final_descriptor =
        GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
            &final_page,
            1,
            1,
            0,
        );
    let err = final_descriptor
        .validate_contract()
        .expect_err("final linked output must not claim executable bytes while runtime is unbound");
    assert!(err.contains("target-byte output record array"));
    assert!(err.contains("unbound runtime services"));
}

#[test]
fn link_descriptor_summary_runtime_services_are_abi_pinned() {
    let allocator_service_id = runtime_descriptor_value("SERVICE_ALLOCATOR_ID");
    let stdio_service_id = runtime_descriptor_value("SERVICE_STDIO_ID");
    let mut summary = SourcePackLinkDescriptorSummary::default();
    summary.set_required_runtime_services([stdio_service_id, allocator_service_id]);
    assert_eq!(
        summary.required_runtime_abi_version,
        Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION),
        "link execution summaries should pin the runtime ABI when services are required"
    );
    assert_eq!(
        summary.required_runtime_service_ids,
        vec![allocator_service_id, stdio_service_id],
        "link execution summaries should keep service ids canonical for flat descriptor rows"
    );

    let mut page = link_execution_page(false, Vec::new());
    page.descriptor_summary = summary.clone();
    let document = serde_json::to_value(&page).expect("serialize runtime-bound link page");
    let descriptor_summary = document
        .get("descriptor_summary")
        .and_then(|value| value.as_object())
        .expect("link execution page should persist descriptor summary metadata");
    assert_eq!(
        descriptor_summary
            .get("required_runtime_abi_version")
            .and_then(|value| value.as_u64()),
        Some(u64::from(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION)),
        "persisted link execution summary should carry the runtime ABI version"
    );

    let parsed_page = serde_json::from_value::<SourcePackHierarchicalLinkExecutionPage>(document)
        .expect("parse persisted runtime-bound link execution page");
    assert_eq!(
        parsed_page.descriptor_summary, summary,
        "link execution summary runtime metadata should survive JSON roundtrip"
    );

    let partial_descriptor =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&parsed_page, 1, 1, 0);
    partial_descriptor
        .validate_contract()
        .expect("ABI-pinned runtime link summary should produce valid contract metadata");
    assert_eq!(
        partial_descriptor.required_runtime_abi_version,
        Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION)
    );
    assert!(
        partial_descriptor
            .required_runtime_services
            .iter()
            .all(|row| row.required_abi_version == GPU_SOURCE_PACK_RUNTIME_ABI_VERSION),
        "runtime service rows should carry the ABI required by the link summary"
    );
}

#[test]
fn link_descriptor_summary_runtime_abi_mismatch_rejects_descriptor_contract() {
    let mut missing_abi = link_execution_page(false, Vec::new());
    missing_abi.descriptor_summary.required_runtime_service_ids =
        vec![GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID];
    let err =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&missing_abi, 1, 1, 0)
            .validate_contract()
            .expect_err("runtime-bound link summaries must declare the runtime ABI version");
    assert!(
        err.contains("must declare runtime ABI version"),
        "unexpected descriptor validation error: {err}"
    );

    let mut unknown_abi = link_execution_page(false, Vec::new());
    unknown_abi.descriptor_summary.required_runtime_abi_version =
        Some(GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION);
    unknown_abi.descriptor_summary.required_runtime_service_ids =
        vec![GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID];
    let err =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&unknown_abi, 1, 1, 0)
            .validate_contract()
            .expect_err(
                "unknown runtime ABI versions should not validate as runtime-bound metadata",
            );
    assert!(
        err.contains("unknown runtime ABI version"),
        "unexpected descriptor validation error: {err}"
    );

    let mut abi_without_services = link_execution_page(false, Vec::new());
    abi_without_services
        .descriptor_summary
        .required_runtime_abi_version = Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION);
    let err = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
        &abi_without_services,
        1,
        1,
        0,
    )
    .validate_contract()
    .expect_err("runtime ABI metadata without service ids should be rejected");
    assert!(
        err.contains("without required runtime service ids"),
        "unexpected descriptor validation error: {err}"
    );
}

#[test]
fn test_harness_runtime_service_descriptor_stays_contract_only_until_binding_exists() {
    let harness_service_id = runtime_descriptor_value("SERVICE_TEST_HARNESS_ID");
    assert_eq!(
        harness_service_id, GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID,
        "stdlib runtime inventory and artifact descriptor ids should agree on the test harness service"
    );

    let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &link_job(),
        0,
        1,
    );
    descriptor.set_required_runtime_services([harness_service_id]);

    let err = descriptor
        .validate_contract()
        .expect_err("unbound test harness service must not produce linked target bytes");
    assert!(
        err.contains("target-byte output record array") && err.contains("unbound runtime services"),
        "unexpected test harness descriptor validation error: {err}"
    );

    descriptor
        .output_record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .record_arrays
        .retain(|array| array.name != "emitted_byte_records");
    descriptor
        .validate_contract()
        .expect("test harness service requirements are valid as descriptor metadata only");

    let partial_page = link_execution_page(false, vec![harness_service_id]);
    GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&partial_page, 1, 1, 0)
        .validate_contract()
        .expect("partial-link descriptors may carry unbound test harness requirements forward");
}

#[test]
fn core_runtime_descriptor_inventory_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "inventory", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let metadata_version: RuntimeAbiMetadataVersion =
        core::runtime::runtime_abi_metadata_version();
    let declared_metadata_version: core::runtime::RuntimeAbiMetadataVersion =
        RUNTIME_ABI_METADATA_VERSION;
    let service_count: RuntimeServiceCount = core::runtime::runtime_service_count();
    let declared_count: core::runtime::RuntimeServiceCount = RUNTIME_SERVICE_COUNT;
    let first_id: RuntimeServiceId = first_runtime_service_id();
    let last_id: core::runtime::RuntimeServiceId = core::runtime::last_runtime_service_id();
    let first_declared: core::runtime::RuntimeServiceId = FIRST_RUNTIME_SERVICE_ID;
    let last_declared: RuntimeServiceId = core::runtime::LAST_RUNTIME_SERVICE_ID;
    let requirement_field_count: RuntimeServiceRequirementFieldCount =
        core::runtime::runtime_service_requirement_field_count();
    let declared_requirement_field_count: core::runtime::RuntimeServiceRequirementFieldCount =
        core::runtime::RUNTIME_SERVICE_REQUIREMENT_FIELD_COUNT;
    let requirement_service_id_field: RuntimeServiceRequirementFieldIndex =
        runtime_service_requirement_service_id_field();
    let requirement_abi_version_field: core::runtime::RuntimeServiceRequirementFieldIndex =
        core::runtime::runtime_service_requirement_abi_version_field();
    let requirement_status_field: RuntimeServiceRequirementFieldIndex =
        core::runtime::runtime_service_requirement_status_field();
    let zero_service_id: core::runtime::RuntimeServiceId = 0;
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let allocator_in_range: Capability =
        service_id_in_descriptor_range(SERVICE_ALLOCATOR_ID);
    let test_harness_in_range: core::runtime::Capability =
        core::runtime::service_id_in_descriptor_range(core::runtime::SERVICE_TEST_HARNESS_ID);
    let zero_in_range: Capability =
        core::runtime::service_id_in_descriptor_range(zero_service_id);
    let future_in_range: core::runtime::Capability =
        service_id_in_descriptor_range(unknown_service_id);
    let runtime_services: core::runtime::Capability = core::runtime::has_runtime_services();
    let contract_only: Capability = runtime_services_are_contract_only();
    let runtime_services_blocked: core::runtime::Capability =
        core::runtime::runtime_services_are_blocked();
    let stdio_service_contract_only: core::runtime::Capability =
        core::runtime::service_is_contract_only(core::runtime::SERVICE_STDIO_ID);
    let unknown_service_contract_only: Capability =
        service_is_contract_only(unknown_service_id);
    let stdio_descriptor_known: Capability =
        service_descriptor_is_known(core::runtime::SERVICE_STDIO_ID);
    let unknown_descriptor_known: core::runtime::Capability =
        core::runtime::service_descriptor_is_known(unknown_service_id);
    let stdio_has_binding: Capability =
        service_has_runtime_binding(core::runtime::SERVICE_STDIO_ID);
    let stdio_is_unbound: core::runtime::Capability =
        core::runtime::service_is_unbound(core::runtime::SERVICE_STDIO_ID);
    let stdio_fail_closed: Capability =
        service_is_fail_closed(core::runtime::SERVICE_STDIO_ID);
    let stdio_service_blocked: core::runtime::Capability =
        core::runtime::service_is_blocked(core::runtime::SERVICE_STDIO_ID);
    let unknown_service_blocked: Capability =
        service_is_blocked(unknown_service_id);
    let stdio_uses_lnc0038_boundary: core::runtime::Capability =
        core::runtime::service_binding_diagnostic_is_lnc0038(core::runtime::SERVICE_STDIO_ID);
    let unknown_uses_lnc0038_boundary: Capability =
        service_binding_diagnostic_is_lnc0038(unknown_service_id);
    let stdio_api_needs_binding: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_binding(core::runtime::SERVICE_STDIO_ID);
    let unknown_api_needs_binding: Capability =
        runtime_bound_api_requires_binding(unknown_service_id);
    let stdio_api_blocked: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_blocked(core::runtime::SERVICE_STDIO_ID);
    let unknown_api_blocked: Capability = runtime_bound_api_is_blocked(unknown_service_id);
    if (service_count != declared_count || service_count != 13) {
        return 1;
    }
    if (metadata_version != declared_metadata_version || metadata_version != 1) {
        return 1;
    }
    if (requirement_field_count != declared_requirement_field_count || requirement_field_count != 3) {
        return 1;
    }
    if (requirement_service_id_field != RUNTIME_SERVICE_REQUIREMENT_SERVICE_ID_FIELD || requirement_service_id_field != 0) {
        return 1;
    }
    if (requirement_abi_version_field != RUNTIME_SERVICE_REQUIREMENT_ABI_VERSION_FIELD || requirement_abi_version_field != 1) {
        return 1;
    }
    if (requirement_status_field != RUNTIME_SERVICE_REQUIREMENT_STATUS_FIELD || requirement_status_field != 2) {
        return 1;
    }
    if (first_id != first_declared || last_id != last_declared) {
        return 1;
    }
    if (first_id != SERVICE_ALLOCATOR_ID || last_id != SERVICE_TEST_HARNESS_ID) {
        return 1;
    }
    if (!allocator_in_range || !test_harness_in_range || zero_in_range || future_in_range) {
        return 1;
    }
    if (runtime_services
        || !contract_only
        || !runtime_services_blocked
        || !stdio_service_contract_only
        || unknown_service_contract_only
        || !stdio_descriptor_known
        || unknown_descriptor_known
        || stdio_has_binding
        || !stdio_is_unbound
        || !stdio_fail_closed
        || !stdio_service_blocked
        || !unknown_service_blocked
        || !stdio_uses_lnc0038_boundary
        || unknown_uses_lnc0038_boundary
        || !stdio_api_needs_binding
        || unknown_api_needs_binding
        || !stdio_api_blocked
        || !unknown_api_blocked)
    {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::runtime descriptor inventory",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::runtime descriptor inventory should type check through --stdlib-root");
}

#[test]
fn core_runtime_known_unbound_service_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "known_unbound_runtime_service",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let stdio_known_unbound: Capability =
        core::runtime::service_is_known_but_unbound(core::runtime::SERVICE_STDIO_ID);
    let allocator_api_known_unbound: core::runtime::Capability =
        runtime_bound_api_is_known_but_unbound(SERVICE_ALLOCATOR_ID);
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let unknown_service_known_unbound: Capability =
        core::runtime::service_is_known_but_unbound(unknown_service_id);
    let unknown_api_known_unbound: core::runtime::Capability =
        runtime_bound_api_is_known_but_unbound(unknown_service_id);
    let stdio_api_needs_binding: Capability =
        runtime_bound_api_requires_binding(core::runtime::SERVICE_STDIO_ID);
    if (!stdio_known_unbound || !allocator_api_known_unbound || !stdio_api_needs_binding) {
        return 1;
    }
    if (unknown_service_known_unbound || unknown_api_known_unbound) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root known-unbound runtime service contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("known-unbound runtime service contract should type check through --stdlib-root");
}

#[test]
fn core_runtime_bound_api_runtime_binding_alias_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "runtime_bound_api_binding_alias",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let stdio_service_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_STDIO_ID;
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let stdio_alias: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_runtime_binding(stdio_service_id);
    let stdio_existing: Capability =
        runtime_bound_api_requires_binding(stdio_service_id);
    let stdio_blocked: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_blocked(stdio_service_id);
    let unknown_alias: Capability =
        runtime_bound_api_requires_runtime_binding(unknown_service_id);
    let unknown_blocked: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_blocked(unknown_service_id);
    if (!stdio_alias || !stdio_existing || !stdio_blocked || !unknown_blocked) {
        return 1;
    }
    if (unknown_alias) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::runtime import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")
        }),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root runtime-bound API binding alias",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("runtime-bound API binding alias should type check through --stdlib-root");
}

#[test]
fn core_runtime_requirement_row_guard_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "requirement_row_guard",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let stdio_service_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_STDIO_ID;
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let active_abi: RuntimeAbiVersion = core::runtime::RUNTIME_ABI_VERSION;
    let unknown_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::UNKNOWN_RUNTIME_ABI_VERSION;
    let unavailable_status: RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_UNAVAILABLE;
    let available_status: core::runtime::RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_AVAILABLE;
    let unknown_status: RuntimeServiceStatus = SERVICE_STATUS_UNKNOWN;
    let stdio_service_known: Capability =
        runtime_service_requirement_service_is_known(stdio_service_id);
    let unknown_service_known: core::runtime::Capability =
        core::runtime::runtime_service_requirement_service_is_known(unknown_service_id);
    let active_abi_supported: Capability =
        core::runtime::runtime_service_requirement_abi_is_supported(active_abi);
    let unknown_abi_supported: core::runtime::Capability =
        runtime_service_requirement_abi_is_supported(unknown_abi);
    let unavailable_contract_status: Capability =
        core::runtime::runtime_service_requirement_status_is_contract_only(unavailable_status);
    let available_contract_status: core::runtime::Capability =
        runtime_service_requirement_status_is_contract_only(available_status);
    let unknown_contract_status: Capability =
        core::runtime::runtime_service_requirement_status_is_contract_only(unknown_status);
    let invalid_status: core::runtime::RuntimeServiceStatus = 99;
    let unavailable_status_declared: Capability =
        runtime_service_requirement_status_is_declared(unavailable_status);
    let unknown_status_declared: core::runtime::Capability =
        core::runtime::runtime_service_requirement_status_is_declared(unknown_status);
    let available_status_declared: Capability =
        runtime_service_requirement_status_is_declared(available_status);
    let invalid_status_declared: core::runtime::Capability =
        core::runtime::runtime_service_requirement_status_is_declared(invalid_status);
    let unavailable_status_fail_closed: Capability =
        runtime_service_requirement_status_is_fail_closed(unavailable_status);
    let unknown_status_fail_closed: core::runtime::Capability =
        core::runtime::runtime_service_requirement_status_is_fail_closed(unknown_status);
    let invalid_status_fail_closed: Capability =
        runtime_service_requirement_status_is_fail_closed(invalid_status);
    let available_status_fail_closed: core::runtime::Capability =
        core::runtime::runtime_service_requirement_status_is_fail_closed(available_status);
    let stdio_row_valid: Capability =
        runtime_service_requirement_row_is_valid(stdio_service_id, active_abi, unavailable_status);
    let stdio_row_known_unbound: core::runtime::Capability =
        core::runtime::runtime_service_requirement_row_is_known_unbound(stdio_service_id, active_abi, unavailable_status);
    let unknown_service_row: Capability =
        runtime_service_requirement_row_is_valid(unknown_service_id, active_abi, unavailable_status);
    let unknown_abi_row: core::runtime::Capability =
        core::runtime::runtime_service_requirement_row_is_valid(stdio_service_id, unknown_abi, unavailable_status);
    let available_status_row: Capability =
        runtime_service_requirement_row_is_valid(stdio_service_id, active_abi, available_status);
    let unknown_status_row: core::runtime::Capability =
        core::runtime::runtime_service_requirement_row_is_valid(stdio_service_id, active_abi, unknown_status);
    if (!stdio_service_known
        || unknown_service_known
        || !active_abi_supported
        || unknown_abi_supported
        || !unavailable_contract_status
        || available_contract_status
        || unknown_contract_status
        || !unavailable_status_declared
        || !unknown_status_declared
        || !available_status_declared
        || invalid_status_declared
        || !unavailable_status_fail_closed
        || !unknown_status_fail_closed
        || !invalid_status_fail_closed
        || available_status_fail_closed
        || !stdio_row_valid
        || !stdio_row_known_unbound
        || unknown_service_row
        || unknown_abi_row
        || available_status_row
        || unknown_status_row)
    {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::runtime import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")
        }),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root runtime service requirement row guard",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("runtime service requirement row guard should type check through --stdlib-root");
}

#[test]
fn core_runtime_raw_status_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_runtime", "raw_status_helpers", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let unknown_status: RuntimeServiceStatus = SERVICE_STATUS_UNKNOWN;
    let unavailable_status: core::runtime::RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_UNAVAILABLE;
    let available_status: RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_AVAILABLE;
    let invalid_status: core::runtime::RuntimeServiceStatus = 99;
    let unknown_is_unknown: Capability =
        runtime_service_status_is_unknown(unknown_status);
    let unavailable_is_unknown: core::runtime::Capability =
        core::runtime::runtime_service_status_is_unknown(unavailable_status);
    let unavailable_is_unavailable: Capability =
        runtime_service_status_is_unavailable(unavailable_status);
    let available_is_available: core::runtime::Capability =
        core::runtime::runtime_service_status_is_available(available_status);
    let invalid_declared: Capability =
        runtime_service_status_is_declared(invalid_status);
    let unknown_declared: core::runtime::Capability =
        core::runtime::runtime_service_status_is_declared(unknown_status);
    let unavailable_contract_only: Capability =
        runtime_service_status_is_contract_only(unavailable_status);
    let unknown_contract_only: core::runtime::Capability =
        core::runtime::runtime_service_status_is_contract_only(unknown_status);
    let available_contract_only: Capability =
        core::runtime::runtime_service_status_is_contract_only(available_status);
    let unavailable_fail_closed: core::runtime::Capability =
        core::runtime::runtime_service_status_is_fail_closed(unavailable_status);
    let unknown_fail_closed: Capability =
        runtime_service_status_is_fail_closed(unknown_status);
    let invalid_fail_closed: core::runtime::Capability =
        runtime_service_status_is_fail_closed(invalid_status);
    let available_fail_closed: Capability =
        core::runtime::runtime_service_status_is_fail_closed(available_status);
    let requirement_status_alias: core::runtime::Capability =
        runtime_service_requirement_status_is_contract_only(unavailable_status);
    if (!unknown_is_unknown
        || unavailable_is_unknown
        || !unavailable_is_unavailable
        || !available_is_available
        || invalid_declared
        || !unknown_declared
        || !unavailable_contract_only
        || unknown_contract_only
        || available_contract_only
        || !unavailable_fail_closed
        || !unknown_fail_closed
        || !invalid_fail_closed
        || available_fail_closed
        || !requirement_status_alias)
    {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::runtime import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")
        }),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::runtime raw status helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::runtime raw status helpers should type check through --stdlib-root");
}

#[test]
fn core_runtime_requirement_row_contract_only_alias_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "requirement_row_contract_only",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let stdio_service_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_STDIO_ID;
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let active_abi: RuntimeAbiVersion = core::runtime::RUNTIME_ABI_VERSION;
    let unknown_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::UNKNOWN_RUNTIME_ABI_VERSION;
    let unavailable_status: RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_UNAVAILABLE;
    let available_status: core::runtime::RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_AVAILABLE;
    let stdio_contract_only: core::runtime::Capability =
        core::runtime::runtime_service_requirement_row_is_contract_only(stdio_service_id, active_abi, unavailable_status);
    let stdio_known_unbound: Capability =
        runtime_service_requirement_row_is_known_unbound(stdio_service_id, active_abi, unavailable_status);
    let unknown_service_contract_only: core::runtime::Capability =
        runtime_service_requirement_row_is_contract_only(unknown_service_id, active_abi, unavailable_status);
    let unknown_abi_contract_only: Capability =
        core::runtime::runtime_service_requirement_row_is_contract_only(stdio_service_id, unknown_abi, unavailable_status);
    let available_status_contract_only: core::runtime::Capability =
        runtime_service_requirement_row_is_contract_only(stdio_service_id, active_abi, available_status);
    if (!stdio_contract_only || !stdio_known_unbound) {
        return 1;
    }
    if (unknown_service_contract_only || unknown_abi_contract_only || available_status_contract_only) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::runtime import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")
        }),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root runtime service requirement row contract-only alias",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("runtime service requirement row contract-only alias should type check through --stdlib-root");
}

#[test]
fn core_runtime_requirement_row_fail_closed_guard_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "requirement_row_fail_closed",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let stdio_service_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_STDIO_ID;
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let active_abi: RuntimeAbiVersion = core::runtime::RUNTIME_ABI_VERSION;
    let unknown_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::UNKNOWN_RUNTIME_ABI_VERSION;
    let unavailable_status: RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_UNAVAILABLE;
    let available_status: core::runtime::RuntimeServiceStatus =
        core::runtime::SERVICE_STATUS_AVAILABLE;
    let unknown_status: RuntimeServiceStatus = SERVICE_STATUS_UNKNOWN;
    let valid_row: core::runtime::Capability =
        core::runtime::runtime_service_requirement_row_is_valid(stdio_service_id, active_abi, unavailable_status);
    let valid_row_fail_closed: Capability =
        runtime_service_requirement_row_is_fail_closed(stdio_service_id, active_abi, unavailable_status);
    let unknown_service_fail_closed: core::runtime::Capability =
        runtime_service_requirement_row_is_fail_closed(unknown_service_id, active_abi, unavailable_status);
    let unknown_abi_fail_closed: Capability =
        core::runtime::runtime_service_requirement_row_is_fail_closed(stdio_service_id, unknown_abi, unavailable_status);
    let available_status_fail_closed: core::runtime::Capability =
        runtime_service_requirement_row_is_fail_closed(stdio_service_id, active_abi, available_status);
    let unknown_status_fail_closed: Capability =
        core::runtime::runtime_service_requirement_row_is_fail_closed(stdio_service_id, active_abi, unknown_status);
    if (!valid_row || valid_row_fail_closed) {
        return 1;
    }
    if (!unknown_service_fail_closed
        || !unknown_abi_fail_closed
        || !available_status_fail_closed
        || !unknown_status_fail_closed)
    {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::runtime import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")
        }),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root runtime service requirement row fail-closed guard",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "runtime service requirement row fail-closed guard should type check through --stdlib-root",
    );
}

#[test]
fn core_target_runtime_service_defaults_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "target_runtime_defaults",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::target;

fn main() {
    let runtime_services: core::target::Capability =
        core::target::has_runtime_services();
    let declared_runtime_services: core::target::Capability =
        core::target::HAS_RUNTIME_SERVICES;
    let runtime_services_blocked: core::target::Capability =
        core::target::runtime_services_are_blocked();
    let freestanding: core::target::Capability = core::target::is_freestanding();
    let filesystem: core::target::Capability = core::target::has_filesystem();
    let stdio: core::target::Capability = core::target::has_stdio();
    let network: core::target::Capability = core::target::has_network();
    let gpu: core::target::Capability = core::target::has_gpu();
    let test_harness: core::target::Capability =
        core::target::has_test_harness();
    if (runtime_services || declared_runtime_services || !runtime_services_blocked || !freestanding) {
        return 1;
    }
    if (filesystem || stdio || network || gpu || test_harness) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::target import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/target.lani")
        }),
        "path manifest should include core::target from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::target runtime-service defaults",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::target runtime-service defaults should type check through --stdlib-root");
}

#[test]
fn core_mem_value_helper_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "mem_contract", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::mem;

fn main() {
    let runtime_required: MemoryCapability = value_helpers_require_runtime();
    let allocator_required: core::mem::MemoryCapability =
        core::mem::value_helpers_require_allocator();
    let helpers_runtime_free: MemoryCapability =
        core::mem::value_helpers_are_runtime_free();
    let raw_available: core::mem::MemoryCapability = raw_memory_api_is_available();
    let raw_blocked: MemoryCapability = core::mem::raw_memory_api_is_blocked();
    let number: i32 = core::mem::identity(7);
    let flag: bool = identity(false);
    let first_number: i32 = first(number, 11);
    let second_flag: bool = core::mem::second(flag, true);
    let selected_number: i32 = select(second_flag, first_number, 0);
    let selected_flag: bool = core::mem::select(false, second_flag, flag);
    if (runtime_required
        || allocator_required
        || !helpers_runtime_free
        || raw_available
        || !raw_blocked)
    {
        return 1;
    }
    if (selected_flag) {
        return selected_number;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::mem");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/mem.lani")),
        "path manifest should include core::mem from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::mem value-helper contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::mem value-helper contract should type check through --stdlib-root");
}

#[test]
fn core_bool_public_helpers_wasm_compile_fails_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "core_bool_exec", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::bool;

fn main() {
    let true_value: bool = core::bool::from_i32(7);
    let false_value: bool = from_i32(0);
    let not_false: bool = core::bool::not(false_value);
    let both: bool = core::bool::and(true_value, not_false);
    let either: bool = core::bool::or(false_value, both);
    let exclusive: bool = core::bool::xor(either, false_value);
    let equal: bool = core::bool::eq(exclusive, true);
    let different: bool = core::bool::ne(false_value, true_value);
    let true_score: i32 = core::bool::to_i32(equal);
    let false_score: i32 = to_i32(false_value);
    let selected: i32 = core::bool::select_i32(different, 7, 99);
    let chosen: i32 = choose_i32(false_value, 11, 5);
    return selected + chosen + true_score + false_score - 13;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::bool import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/bool.lani")),
        "path manifest should include core::bool from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    let err = common::run_gpu_codegen_with_timeout(
        "GPU WASM compile stdlib-root core::bool public helpers",
        {
            let entry_path = entry.path().to_path_buf();
            let stdlib_root = stdlib_root.clone();
            move || pollster::block_on(compile_entry_to_wasm_with_stdlib(entry_path, stdlib_root))
        },
    )
    .expect_err("real core::bool stdlib-root helper execution should fail closed for WASM");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0036");
            assert_eq!(diagnostic.title, "WASM backend boundary");
            assert_eq!(diagnostic.category, "target codegen");
            assert!(
                diagnostic.message.contains("unsupported source shape"),
                "diagnostic should describe the WASM backend shape boundary: {diagnostic}"
            );
            assert!(
                diagnostic
                    .help
                    .as_deref()
                    .is_some_and(|help| help.contains("laniusc check")),
                "diagnostic should point users to check-only validation: {diagnostic}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("WASM backend boundary should include a primary label");
            assert!(
                label
                    .message
                    .contains("not supported by the WASM backend yet"),
                "primary label should name the backend boundary: {diagnostic}"
            );
        }
        other => panic!("expected stable WASM backend diagnostic, got {other:?}"),
    }
}

#[test]
fn core_i32_public_predicate_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "i32_predicates", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;

fn main() {
    let zero: bool = core::i32::is_zero(0);
    let positive_nonzero: bool = core::i32::is_nonzero(7);
    let negative_nonzero: bool = is_nonzero(-3);
    let zero_misses: bool = core::i32::is_nonzero(0);
    if (!zero || !positive_nonzero || !negative_nonzero || zero_misses) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::i32 import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 predicate helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32 predicate helpers should type check through --stdlib-root");
}

#[test]
fn core_i32_saturating_arithmetic_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "i32_saturating", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;

fn main() {
    let min_value: i32 = core::i32::MIN;
    let max_value: i32 = MAX;
    let normal_sum: i32 = core::i32::saturating_add(40, 2);
    let max_clamped: i32 = saturating_add(max_value, 1);
    let min_clamped: i32 = core::i32::saturating_add(min_value, -1);
    let normal_diff: i32 = saturating_sub(40, 2);
    let max_from_subtracting_negative: i32 =
        core::i32::saturating_sub(max_value, -1);
    let min_from_subtracting_positive: i32 =
        saturating_sub(min_value, 1);
    if (normal_sum != 42 || max_clamped != max_value || min_clamped != min_value) {
        return 1;
    }
    if (normal_diff != 38
        || max_from_subtracting_negative != max_value
        || min_from_subtracting_positive != min_value)
    {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::i32 import");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 saturating arithmetic helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32 saturating arithmetic helpers should type check through --stdlib-root");
}

#[test]
fn core_i32_saturating_abs_diff_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "i32_abs_diff", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;

fn main() {
    let forward: i32 = core::i32::saturating_abs_diff(10, 4);
    let reverse: i32 = saturating_abs_diff(4, 10);
    let equal: i32 = core::i32::saturating_abs_diff(-5, -5);
    let max_span: i32 = core::i32::saturating_abs_diff(core::i32::MAX, core::i32::MIN);
    if (forward != 6 || reverse != 6 || equal != 0) {
        return 1;
    }
    if (max_span != core::i32::MAX) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::i32 import");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::i32::saturating_abs_diff").is_none(),
        "core::i32::saturating_abs_diff is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i32 saturating abs diff helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i32 saturating abs diff helper should type check through --stdlib-root");
}

#[test]
fn core_unsigned_integer_nonzero_predicates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "unsigned_nonzero_predicates",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u32;
import core::u8;

fn main() {
    let zero_u32: bool = core::u32::is_nonzero(0);
    let value_u32: bool = core::u32::is_nonzero(17);
    let zero_u8: bool = core::u8::is_nonzero(0);
    let value_u8: bool = core::u8::is_nonzero(9);
    if (zero_u32 || !value_u32 || zero_u8 || !value_u8) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load unsigned integer modules");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root unsigned integer nonzero predicates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("unsigned integer nonzero predicates should type check through --stdlib-root");
}

#[test]
fn core_u32_alignment_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "u32_alignment_helpers",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u32;

fn main() {
    let zero: u32 = 0;
    let one: u32 = 1;
    let three: u32 = 3;
    let eight: u32 = 8;
    let sixteen: u32 = 16;
    let seventeen: u32 = 17;
    let twenty_four: u32 = 24;
    let twenty_six: u32 = 26;
    let almost_max: u32 = core::u32::MAX - three;
    let already_aligned: u32 = core::u32::align_up(sixteen, eight);
    let rounded_up: u32 = align_up(seventeen, eight);
    let zero_alignment: u32 = core::u32::align_up(seventeen, zero);
    let one_alignment: u32 = align_up(seventeen, one);
    let saturated: u32 = core::u32::align_up(almost_max, eight);
    let already_aligned_down: u32 = core::u32::align_down(sixteen, eight);
    let rounded_down: u32 = align_down(twenty_six, eight);
    let down_to_zero: u32 = core::u32::align_down(three, eight);
    let down_zero_alignment: u32 = align_down(seventeen, zero);
    let down_one_alignment: u32 = core::u32::align_down(seventeen, one);
    let zero_alignment_is_aligned: bool = core::u32::is_aligned(seventeen, zero);
    let one_alignment_is_aligned: bool = is_aligned(seventeen, one);
    let exact_alignment: bool = core::u32::is_aligned(twenty_four, eight);
    let missed_alignment: bool = is_aligned(twenty_six, eight);
    if (already_aligned != 16 || rounded_up != 24 || zero_alignment != 17 || one_alignment != 17) {
        return 1;
    }
    if (already_aligned_down != 16
        || rounded_down != 24
        || down_to_zero != 0
        || down_zero_alignment != 17
        || down_one_alignment != 17)
    {
        return 1;
    }
    if (!zero_alignment_is_aligned || !one_alignment_is_aligned || !exact_alignment || missed_alignment) {
        return 1;
    }
    return saturated - saturated;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u32");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u32::align_up").is_none(),
        "core::u32::align_up is a source-level helper and must not claim a runtime binding"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u32::align_down").is_none(),
        "core::u32::align_down is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 alignment helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32 alignment helpers should type check through --stdlib-root");
}

#[test]
fn core_u32_abs_diff_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "u32_abs_diff", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::u32;

fn main() {
    let zero: u32 = 0;
    let four: u32 = 4;
    let seven: u32 = 7;
    let ten: u32 = 10;
    let forward: u32 = core::u32::abs_diff(ten, four);
    let reverse: u32 = abs_diff(four, ten);
    let equal: u32 = core::u32::abs_diff(seven, seven);
    let span_to_max: u32 = core::u32::abs_diff(core::u32::MAX, zero);
    if (forward != 6 || reverse != 6 || equal != 0) {
        return 1;
    }
    if (span_to_max != core::u32::MAX) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u32 import");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani")),
        "path manifest should include core::u32 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u32::abs_diff").is_none(),
        "core::u32::abs_diff is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u32 abs diff helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u32 abs diff helper should type check through --stdlib-root");
}

#[test]
fn core_integer_parity_predicates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "integer_parity", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;
import core::u32;
import core::u8;

fn main() {
    let i32_even: bool = core::i32::is_even(-4);
    let i32_odd: bool = core::i32::is_odd(-3);
    let u32_even: bool = core::u32::is_even(42);
    let u32_odd: bool = core::u32::is_odd(17);
    let u8_even: bool = core::u8::is_even(8);
    let u8_odd: bool = core::u8::is_odd(9);
    if (!i32_even || !i32_odd || !u32_even || !u32_odd || !u8_even || !u8_odd) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load integer helper modules");
    assert_eq!(manifest.files.len(), 4);
    for relative_path in ["core/i32.lani", "core/u32.lani", "core/u8.lani"] {
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.library_id == 0 && file.path == stdlib_root.join(relative_path)),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root integer parity predicates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("integer parity predicates should type check through --stdlib-root");
}

#[test]
fn core_char_ascii_classification_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "char_ascii_classification",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::char;

fn main() {
    let digit: bool = core::char::is_ascii_digit('7');
    let lower: bool = is_ascii_lowercase('x');
    let upper: bool = core::char::is_ascii_uppercase('Q');
    let alpha: bool = is_ascii_alphabetic('m');
    let alnum: bool = core::char::is_ascii_alphanumeric('4');
    let word_alpha: bool = core::char::is_ascii_word('Z');
    let word_digit: bool = is_ascii_word('5');
    let word_underscore: bool = core::char::is_ascii_word('_');
    let word_rejects_punctuation: bool = is_ascii_word('-');
    let hex_upper: bool = core::char::is_ascii_hexdigit('F');
    let hex_lower: bool = is_ascii_hexdigit('a');
    let hex_rejects: bool = core::char::is_ascii_hexdigit('g');
    let space: bool = core::char::is_ascii_whitespace(' ');
    let tab: bool = is_ascii_whitespace('\t');
    let newline: bool = core::char::is_ascii_whitespace('\n');
    let visible_rejects: bool = is_ascii_whitespace('Z');
    let slash_punctuation: bool = core::char::is_ascii_punctuation('/');
    let at_punctuation: bool = is_ascii_punctuation('@');
    let bracket_punctuation: bool = core::char::is_ascii_punctuation('[');
    let underscore_punctuation: bool = is_ascii_punctuation('_');
    let brace_punctuation: bool = core::char::is_ascii_punctuation('{');
    let letter_punctuation: bool = core::char::is_ascii_punctuation('A');
    let digit_punctuation: bool = is_ascii_punctuation('9');
    let space_punctuation: bool = core::char::is_ascii_punctuation(' ');
    if (!digit || !lower || !upper || !alpha || !alnum || !word_alpha || !word_digit || !word_underscore || word_rejects_punctuation || !hex_upper || !hex_lower || hex_rejects || !space || !tab || !newline || visible_rejects) {
        return 1;
    }
    if (!slash_punctuation || !at_punctuation || !bracket_punctuation || !underscore_punctuation || !brace_punctuation || letter_punctuation || digit_punctuation || space_punctuation) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::char");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/char.lani")
        }),
        "path manifest should include core::char from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::char::is_ascii_punctuation").is_none(),
        "core::char::is_ascii_punctuation is a source-level helper and must not claim a runtime binding"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::char::is_ascii_word").is_none(),
        "core::char::is_ascii_word is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::char ASCII classification helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::char ASCII classification helpers should type check through --stdlib-root");
}

#[test]
fn core_char_ascii_case_equality_helper_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "char_ascii_case_equality",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::char;

fn main() {
    let equal_upper_lower: bool = core::char::eq_ignore_ascii_case('A', 'a');
    let equal_lower_upper: bool = eq_ignore_ascii_case('z', 'Z');
    let equal_same_digit: bool = core::char::eq_ignore_ascii_case('7', '7');
    let equal_same_punctuation: bool = eq_ignore_ascii_case('-', '-');
    let different_letters: bool = core::char::eq_ignore_ascii_case('A', 'b');
    let different_digits: bool = eq_ignore_ascii_case('7', '8');
    let different_punctuation: bool = core::char::eq_ignore_ascii_case('-', '_');
    if (!equal_upper_lower || !equal_lower_upper || !equal_same_digit || !equal_same_punctuation) {
        return 1;
    }
    if (different_letters || different_digits || different_punctuation) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::char");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/char.lani")
        }),
        "path manifest should include core::char from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::char::eq_ignore_ascii_case").is_none(),
        "core::char::eq_ignore_ascii_case is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::char ASCII case equality helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::char ASCII case equality helper should type check through --stdlib-root");
}

#[test]
fn core_ascii_printable_graphic_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "ascii_printable_graphic",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::char;
import core::u8;

fn main() {
    let char_bang_graphic: bool = core::char::is_ascii_graphic('!');
    let char_tilde_graphic: bool = core::char::is_ascii_graphic('~');
    let char_space_graphic: bool = core::char::is_ascii_graphic(' ');
    let char_space_printable: bool = core::char::is_ascii_printable(' ');
    let char_newline_printable: bool = core::char::is_ascii_printable('\n');
    let byte_bang_graphic: bool = core::u8::is_ascii_graphic(33);
    let byte_tilde_graphic: bool = core::u8::is_ascii_graphic(126);
    let byte_space_graphic: bool = core::u8::is_ascii_graphic(32);
    let byte_space_printable: bool = core::u8::is_ascii_printable(32);
    let byte_newline_printable: bool = core::u8::is_ascii_printable(10);
    if (!char_bang_graphic || !char_tilde_graphic || char_space_graphic) {
        return 1;
    }
    if (!char_space_printable || char_newline_printable) {
        return 1;
    }
    if (!byte_bang_graphic || !byte_tilde_graphic || byte_space_graphic) {
        return 1;
    }
    if (!byte_space_printable || byte_newline_printable) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load ASCII helper modules");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/char.lani")),
        "path manifest should include core::char from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core ASCII printable/graphic helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core ASCII printable/graphic helpers should type check through --stdlib-root");
}

#[test]
fn core_u8_ascii_case_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "u8_ascii_case", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::u8;

fn main() {
    let ascii_letter: bool = core::u8::is_ascii(65);
    let ascii_limit: bool = core::u8::is_ascii(127);
    let non_ascii_byte: bool = core::u8::is_ascii(200);
    let lower_a: u8 = core::u8::to_ascii_lowercase(65);
    let lower_z: u8 = core::u8::to_ascii_lowercase(90);
    let lower_digit: u8 = core::u8::to_ascii_lowercase(55);
    let upper_a: u8 = core::u8::to_ascii_uppercase(97);
    let upper_z: u8 = core::u8::to_ascii_uppercase(122);
    let upper_digit: u8 = core::u8::to_ascii_uppercase(55);
    let equal_upper_lower: bool = core::u8::eq_ignore_ascii_case(65, 97);
    let equal_lower_upper: bool = core::u8::eq_ignore_ascii_case(122, 90);
    let equal_digits: bool = core::u8::eq_ignore_ascii_case(55, 55);
    let different_digits: bool = core::u8::eq_ignore_ascii_case(55, 56);
    let different_punctuation: bool = core::u8::eq_ignore_ascii_case(45, 95);
    if (!ascii_letter || !ascii_limit || non_ascii_byte) {
        return 1;
    }
    if (lower_a != 97 || lower_z != 122 || lower_digit != 55) {
        return 1;
    }
    if (upper_a != 65 || upper_z != 90 || upper_digit != 55) {
        return 1;
    }
    if (!equal_upper_lower || !equal_lower_upper || !equal_digits || different_digits || different_punctuation) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u8");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u8::eq_ignore_ascii_case").is_none(),
        "core::u8::eq_ignore_ascii_case is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 ASCII case helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8 ASCII case helpers should type check through --stdlib-root");
}

#[test]
fn core_u8_ascii_hexdigit_value_helper_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "u8_ascii_hexdigit_value",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u8;

fn main() {
    let digit_byte: u8 = 57;
    let upper_byte: u8 = 65;
    let lower_byte: u8 = 102;
    let rejected_upper_byte: u8 = 71;
    let rejected_punctuation_byte: u8 = 47;
    let fallback: u8 = 255;
    let expected_digit: u8 = 9;
    let expected_upper: u8 = 10;
    let expected_lower: u8 = 15;
    let digit_value: u8 = core::u8::ascii_hexdigit_value_or(digit_byte, fallback);
    let upper_value: u8 = ascii_hexdigit_value_or(upper_byte, fallback);
    let lower_value: u8 = core::u8::ascii_hexdigit_value_or(lower_byte, fallback);
    let rejected_upper: u8 = ascii_hexdigit_value_or(rejected_upper_byte, fallback);
    let rejected_punctuation: u8 = core::u8::ascii_hexdigit_value_or(rejected_punctuation_byte, fallback);
    let digit_known: bool = core::u8::is_ascii_hexdigit(digit_byte);
    let upper_known: bool = is_ascii_hexdigit(upper_byte);
    let lower_known: bool = core::u8::is_ascii_hexdigit(lower_byte);
    let rejected_known: bool = core::u8::is_ascii_hexdigit(rejected_upper_byte);
    if (digit_value != expected_digit || upper_value != expected_upper || lower_value != expected_lower) {
        return 1;
    }
    if (rejected_upper != fallback || rejected_punctuation != fallback) {
        return 1;
    }
    if (!digit_known || !upper_known || !lower_known || rejected_known) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u8");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );
    assert!(
        runtime_bound_api_diagnostic_info("core::u8::ascii_hexdigit_value_or").is_none(),
        "core::u8::ascii_hexdigit_value_or is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 ASCII hex digit value helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8 ASCII hex digit value helper should type check through --stdlib-root");
}

#[test]
fn core_u8_ascii_control_punctuation_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "u8_ascii_control_punctuation",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::u8;

fn main() {
    let nul_control: bool = core::u8::is_ascii_control(0);
    let unit_separator_control: bool = is_ascii_control(31);
    let del_control: bool = core::u8::is_ascii_control(127);
    let space_control: bool = is_ascii_control(32);
    let slash_punctuation: bool = core::u8::is_ascii_punctuation(47);
    let at_punctuation: bool = is_ascii_punctuation(64);
    let bracket_punctuation: bool = core::u8::is_ascii_punctuation(91);
    let tick_punctuation: bool = is_ascii_punctuation(96);
    let brace_punctuation: bool = core::u8::is_ascii_punctuation(123);
    let letter_punctuation: bool = core::u8::is_ascii_punctuation(65);
    let digit_punctuation: bool = is_ascii_punctuation(57);
    let space_punctuation: bool = core::u8::is_ascii_punctuation(32);
    if (!nul_control || !unit_separator_control || !del_control || space_control) {
        return 1;
    }
    if (!slash_punctuation || !at_punctuation || !bracket_punctuation || !tick_punctuation || !brace_punctuation) {
        return 1;
    }
    if (letter_punctuation || digit_punctuation || space_punctuation) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::u8");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani")),
        "path manifest should include core::u8 from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::u8 ASCII control/punctuation helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::u8 ASCII control/punctuation helpers should type check through --stdlib-root");
}

#[test]
fn core_mem_raw_memory_contract_matches_allocator_runtime_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "mem_raw", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::mem;
import core::runtime;

fn main() {
    let raw_service_id: core::mem::RawMemoryServiceId =
        core::mem::raw_memory_service_id();
    let declared_raw_service_id: RawMemoryServiceId = RAW_MEMORY_SERVICE_ID;
    let allocator_service_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_ALLOCATOR_ID;
    let raw_abi: RawMemoryRuntimeAbiVersion =
        core::mem::raw_memory_runtime_abi_version();
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(allocator_service_id);
    let raw_status: RawMemoryServiceStatus = raw_memory_service_status();
    let declared_unavailable: core::mem::RawMemoryServiceStatus =
        core::mem::RAW_MEMORY_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(allocator_service_id);
    let raw_known: MemoryCapability = raw_memory_service_is_known();
    let raw_metadata_available: core::mem::MemoryCapability =
        core::mem::raw_memory_contract_metadata_is_available();
    let runtime_known: core::runtime::Capability =
        core::runtime::is_known_service(allocator_service_id);
    let raw_binding: core::mem::MemoryCapability =
        core::mem::raw_memory_has_runtime_binding();
    let raw_available: MemoryCapability = raw_memory_api_is_available();
    let raw_executable: core::mem::MemoryCapability =
        core::mem::raw_memory_api_is_executable();
    let raw_blocked: MemoryCapability = raw_memory_api_is_blocked();
    let raw_needs_binding: MemoryCapability =
        core::mem::raw_memory_api_requires_runtime_binding();
    let raw_contract_only: MemoryCapability = raw_memory_host_abi_is_contract_only();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(allocator_service_id);
    if (raw_service_id != declared_raw_service_id || raw_service_id != allocator_service_id) {
        return 1;
    }
    if (raw_abi != runtime_abi || raw_status != declared_unavailable || raw_status != runtime_status) {
        return 1;
    }
    if (!raw_known || !raw_metadata_available || !runtime_known || raw_binding || raw_available || raw_executable) {
        return 1;
    }
    if (!raw_blocked || !raw_needs_binding || !raw_contract_only || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::mem and core::runtime");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/mem.lani")),
        "path manifest should include core::mem from the stdlib root"
    );
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")
        }),
        "path manifest should include core::runtime from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::mem raw-memory runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::mem raw-memory contract should type check through --stdlib-root");
}

#[test]
fn core_i64_integer_width_metadata_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "i64_width", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i64;

fn main() {
    let min_value: i64 = core::i64::MIN;
    let max_value: i64 = MAX;
    let bits: u32 = core::i64::BITS;
    let bytes: u32 = BYTES;
    if (bits != 64 || bytes != 8) {
        return 1;
    }
    if (min_value == max_value) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::i64");
    for relative_path in ["core/i64.lani", "core/option.lani", "core/result.lani"] {
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.library_id == 0 && file.path == stdlib_root.join(relative_path)),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i64 width metadata",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64 width metadata should type check through --stdlib-root");
}

#[test]
fn core_i64_classification_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "i64_classification_helpers",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::i64;

fn main() {
    let min_abs: i64 = core::i64::saturating_abs(core::i64::MIN);
    let value_is_nonzero: bool = is_nonzero(-9);
    let even_negative: bool = core::i64::is_even(-4);
    let in_range: bool = core::i64::between_inclusive(5, -2, 9);
    if (min_abs != core::i64::MAX || !value_is_nonzero || !even_negative || !in_range) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::i64");
    for relative_path in ["core/i64.lani", "core/option.lani", "core/result.lani"] {
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.library_id == 0 && file.path == stdlib_root.join(relative_path)),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }
    for helper_name in [
        "core::i64::saturating_abs",
        "core::i64::is_nonzero",
        "core::i64::is_even",
        "core::i64::between_inclusive",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i64 classification helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64 classification helpers should type check through --stdlib-root");
}

#[test]
fn core_f32_sign_predicates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "f32_sign", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::f32;

fn main() {
    let negative: bool = core::f32::is_negative(-2.5);
    let positive: bool = is_positive(core::f32::ONE);
    let zero_negative: bool = core::f32::is_negative(core::f32::ZERO);
    let zero_positive: bool = is_positive(0.0);
    if (!negative || !positive || zero_negative || zero_positive) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::f32");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/f32.lani")),
        "path manifest should include core::f32 from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::f32 sign predicates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::f32 sign predicates should type check through --stdlib-root");
}

#[test]
fn core_runtime_descriptor_is_importable_from_source_pack() {
    common::type_check_source_pack_with_timeout(&[
        include_str!("../stdlib/core/runtime.lani"),
        r#"
module app::main;

import core::runtime;

fn main() {
    let metadata_version: core::runtime::RuntimeAbiMetadataVersion =
        core::runtime::runtime_abi_metadata_version();
    let declared_metadata_version: RuntimeAbiMetadataVersion =
        RUNTIME_ABI_METADATA_VERSION;
    let version: core::runtime::RuntimeAbiVersion = core::runtime::runtime_abi_version();
    let unknown_version: RuntimeAbiVersion = UNKNOWN_RUNTIME_ABI_VERSION;
    let first_service_id: core::runtime::RuntimeServiceId =
        core::runtime::first_runtime_service_id();
    let last_service_id: RuntimeServiceId = last_runtime_service_id();
    let allocator_id: RuntimeServiceId = SERVICE_ALLOCATOR_ID;
    let network_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_NETWORK_ID;
    let threads_id: RuntimeServiceId = SERVICE_THREADS_ID;
    let secure_rng_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_SECURE_RNG_ID;
    let gpu_id: RuntimeServiceId = core::runtime::SERVICE_GPU_ID;
    let process_id: RuntimeServiceId = core::runtime::SERVICE_PROCESS_ID;
    let env_id: core::runtime::RuntimeServiceId = SERVICE_ENV_ID;
    let test_harness_id: RuntimeServiceId = SERVICE_TEST_HARNESS_ID;
    let unknown_service_id: core::runtime::RuntimeServiceId = 99;
    let first_service_in_range: Capability = service_id_in_descriptor_range(first_service_id);
    let last_service_in_range: core::runtime::Capability =
        core::runtime::service_id_in_descriptor_range(last_service_id);
    let allocator_abi: RuntimeAbiVersion = runtime_abi_version_for_service(allocator_id);
    let unknown_service_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(unknown_service_id);
    let known_stdio: Capability = core::runtime::is_known_service(core::runtime::SERVICE_STDIO_ID);
    let known_network: core::runtime::Capability = is_known_service(network_id);
    let known_threads: core::runtime::Capability = core::runtime::is_known_service(threads_id);
    let allocator: Capability = core::runtime::has_allocator();
    let stdio: core::runtime::Capability = HAS_STDIO;
    let threads: Capability = core::runtime::has_threads();
    let secure_rng: core::runtime::Capability = has_secure_rng();
    let gpu: Capability = core::runtime::has_gpu();
    let process: Capability = core::runtime::has_process();
    let env: core::runtime::Capability = has_env();
    let test_harness: Capability = core::runtime::has_test_harness();
    let runtime_services: Capability = core::runtime::has_runtime_services();
    let contract_only: core::runtime::Capability =
        core::runtime::runtime_services_are_contract_only();
    let allocator_service: Capability = core::runtime::has_service(allocator_id);
    let network_service: core::runtime::Capability = has_service(network_id);
    let secure_rng_service: Capability = core::runtime::has_service(secure_rng_id);
    let process_service: Capability = core::runtime::has_service(process_id);
    let env_service: core::runtime::Capability = has_service(env_id);
    let test_harness_service: Capability = core::runtime::has_service(test_harness_id);
    let network_status: RuntimeServiceStatus = service_status(network_id);
    let threads_status: RuntimeServiceStatus = core::runtime::service_status(threads_id);
    let process_status: RuntimeServiceStatus = core::runtime::service_status(process_id);
    let env_status: core::runtime::RuntimeServiceStatus = service_status(env_id);
    let test_harness_status: RuntimeServiceStatus =
        core::runtime::service_status(test_harness_id);
    let unknown_service_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_service_id);
    let available_status: RuntimeServiceStatus = SERVICE_STATUS_AVAILABLE;
    let network_unavailable: Capability = core::runtime::service_is_unavailable(network_id);
    let process_available: Capability = core::runtime::service_is_available(process_id);
    let stdio_api_executable: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_executable(core::runtime::SERVICE_STDIO_ID);
    let stdio_api_needs_binding: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_binding(core::runtime::SERVICE_STDIO_ID);
    let unknown_api_needs_binding: Capability =
        runtime_bound_api_requires_binding(unknown_service_id);
    let unknown_service_unknown: core::runtime::Capability =
        service_is_unknown(unknown_service_id);
    let stdio_needs_binding: Capability =
        core::runtime::service_requires_runtime_binding(core::runtime::SERVICE_STDIO_ID);
    let host_services_need_binding: core::runtime::Capability =
        service_requires_runtime_binding(SERVICE_HOST_SERVICES_ID);
    let secure_rng_needs_binding: Capability =
        core::runtime::service_requires_runtime_binding(secure_rng_id);
    let gpu_needs_binding: Capability = service_requires_runtime_binding(gpu_id);
    let process_needs_binding: Capability =
        core::runtime::service_requires_runtime_binding(process_id);
    let env_needs_binding: core::runtime::Capability = service_requires_runtime_binding(env_id);
    let test_harness_needs_binding: Capability =
        core::runtime::service_requires_runtime_binding(test_harness_id);
    if (allocator || stdio || threads || secure_rng || gpu || process || env || test_harness || runtime_services || !contract_only || allocator_service || network_service || secure_rng_service || process_service || env_service || test_harness_service) {
        return 1;
    }
    if (metadata_version != declared_metadata_version || metadata_version != 1) {
        return 1;
    }
    if (!stdio_needs_binding || !host_services_need_binding || !secure_rng_needs_binding || !gpu_needs_binding || !process_needs_binding || !env_needs_binding || !test_harness_needs_binding) {
        return 1;
    }
    if (!first_service_in_range || !last_service_in_range || first_service_id != allocator_id || last_service_id != test_harness_id) {
        return 1;
    }
    if (network_status != SERVICE_STATUS_UNAVAILABLE || threads_status != SERVICE_STATUS_UNAVAILABLE || process_status != SERVICE_STATUS_UNAVAILABLE || env_status != SERVICE_STATUS_UNAVAILABLE || test_harness_status != SERVICE_STATUS_UNAVAILABLE || unknown_service_status != SERVICE_STATUS_UNKNOWN) {
        return 1;
    }
    if (!network_unavailable || process_available || stdio_api_executable || !stdio_api_needs_binding || unknown_api_needs_binding || !unknown_service_unknown) {
        return 1;
    }
    if (available_status == network_status) {
        return 1;
    }
    if (allocator_abi != version || unknown_service_abi != unknown_version) {
        return 1;
    }
    if (known_stdio && known_network && known_threads) {
        return 0;
    }
    return 0;
}
"#,
    ])
    .expect("core::runtime descriptor should type check through source-pack module imports");
}

#[test]
fn alloc_allocator_contract_type_checks_against_unbound_runtime_allocator_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "allocator", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import alloc::allocator;
import core::runtime;

fn main() {
    let allocator_service_id: alloc::allocator::AllocatorServiceId =
        alloc::allocator::allocator_service_id();
    let declared_allocator_id: AllocatorServiceId = ALLOCATOR_SERVICE_ID;
    let runtime_allocator_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_ALLOCATOR_ID;
    let unknown_runtime_service_id: core::runtime::RuntimeServiceId = 99;
    let allocator_known: AllocatorCapability =
        alloc::allocator::allocator_service_is_known();
    let allocator_metadata_available: AllocatorCapability =
        alloc::allocator::allocator_contract_metadata_is_available();
    let allocator_status: alloc::allocator::AllocatorServiceStatus =
        alloc::allocator::allocator_service_status();
    let declared_status: AllocatorServiceStatus =
        ALLOCATOR_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_allocator_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_runtime_service_id);
    let allocator_abi: alloc::allocator::AllocatorRuntimeAbiVersion =
        allocator_runtime_abi_version();
    let declared_abi: AllocatorRuntimeAbiVersion = ALLOCATOR_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_allocator_id);
    let allocator_available: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_is_available();
    let allocator_blocked: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_is_blocked();
    let allocator_known_unbound: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_is_known_but_unbound();
    let declared_binding: AllocatorCapability = ALLOCATOR_HAS_RUNTIME_BINDING;
    let declared_alloc_binding: AllocatorCapability = ALLOC_HAS_RUNTIME_BINDING;
    let declared_dealloc_binding: AllocatorCapability =
        DEALLOC_HAS_RUNTIME_BINDING;
    let allocator_needs_binding: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_requires_runtime_binding();
    let imported_needs_binding: AllocatorCapability =
        allocator_requires_runtime_binding();
    let allocator_contract_only: AllocatorCapability =
        allocator_host_abi_is_contract_only();
    let alloc_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::alloc_is_executable();
    let alloc_blocked: AllocatorCapability = alloc_is_blocked();
    let alloc_known_unbound: AllocatorCapability =
        alloc::allocator::alloc_is_known_but_unbound();
    let alloc_needs_binding: AllocatorCapability =
        alloc_requires_runtime_binding();
    let realloc_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::realloc_is_executable();
    let realloc_blocked: AllocatorCapability =
        alloc::allocator::realloc_is_blocked();
    let realloc_known_unbound: AllocatorCapability =
        realloc_is_known_but_unbound();
    let realloc_needs_binding: AllocatorCapability =
        realloc_requires_runtime_binding();
    let dealloc_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::dealloc_is_executable();
    let dealloc_blocked: AllocatorCapability =
        alloc::allocator::dealloc_is_blocked();
    let dealloc_known_unbound: alloc::allocator::AllocatorCapability =
        alloc::allocator::dealloc_is_known_but_unbound();
    let dealloc_needs_binding: AllocatorCapability =
        dealloc_requires_runtime_binding();
    let alloc_failed_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::alloc_failed_is_executable();
    let alloc_failed_blocked: AllocatorCapability =
        alloc_failed_is_blocked();
    let alloc_failed_known_unbound: AllocatorCapability =
        alloc_failed_is_known_but_unbound();
    let alloc_failed_needs_binding: AllocatorCapability =
        alloc_failed_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_allocator_id);
    if (allocator_service_id != declared_allocator_id || allocator_service_id != runtime_allocator_id) {
        return 1;
    }
    if (allocator_status != declared_status || allocator_status != runtime_status || allocator_status == unknown_status) {
        return 1;
    }
    if (allocator_abi != declared_abi || allocator_abi != runtime_abi) {
        return 1;
    }
    if (!allocator_known || !allocator_metadata_available || allocator_available || !allocator_blocked || !allocator_known_unbound || declared_binding || !declared_alloc_binding || !declared_dealloc_binding || !allocator_needs_binding || !imported_needs_binding || !allocator_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (!alloc_executable || realloc_executable || !dealloc_executable || alloc_failed_executable) {
        return 1;
    }
    if (alloc_blocked || !realloc_blocked || dealloc_blocked || !alloc_failed_blocked) {
        return 1;
    }
    if (alloc_known_unbound || !realloc_known_unbound || dealloc_known_unbound || !alloc_failed_known_unbound) {
        return 1;
    }
    if (alloc_needs_binding || !realloc_needs_binding || dealloc_needs_binding || !alloc_failed_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load alloc::allocator and core::runtime imports");
    assert!(manifest.files.iter().any(|file| {
        file.library_id == 0 && file.path == stdlib_root.join("alloc/allocator.lani")
    }));
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani"))
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root alloc::allocator runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "alloc::allocator should advertise the same unbound allocator service contract as core::runtime",
    );
}

#[test]
fn alloc_allocator_pointer_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "allocator_pointer_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import alloc::allocator;

fn main() {
    let unavailable: alloc::allocator::AllocatorPointer =
        alloc::allocator::ALLOCATOR_POINTER_UNAVAILABLE;
    let unavailable_from_fn: AllocatorPointer =
        allocator_pointer_unavailable();
    let non_null: alloc::allocator::AllocatorPointer = 16;
    let allocated: AllocatorPointer = alloc::allocator::alloc(16, 4);
    let reallocated: alloc::allocator::AllocatorPointer =
        alloc::allocator::realloc(non_null, 16, 32, 4);
    let unavailable_is_known: AllocatorCapability =
        alloc::allocator::allocator_pointer_is_unavailable(unavailable);
    let unavailable_is_available: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_pointer_is_available(unavailable);
    let non_null_is_available: AllocatorCapability =
        allocator_pointer_is_available(non_null);
    let non_null_is_unavailable: alloc::allocator::AllocatorCapability =
        allocator_pointer_is_unavailable(non_null);
    let allocation_fail_closed: AllocatorCapability =
        allocation_result_is_fail_closed(unavailable);
    let alloc_fail_closed: alloc::allocator::AllocatorCapability =
        alloc::allocator::alloc_result_is_fail_closed(unavailable);
    let realloc_fail_closed: AllocatorCapability =
        realloc_result_is_fail_closed(unavailable);
    let non_null_allocation_fail_closed: alloc::allocator::AllocatorCapability =
        allocation_result_is_fail_closed(non_null);
    let allocator_blocked: AllocatorCapability =
        alloc::allocator::allocator_is_blocked();
    let allocator_known_unbound: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_is_known_but_unbound();
    if (unavailable != 0 || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!unavailable_is_known || unavailable_is_available || !non_null_is_available || non_null_is_unavailable) {
        return 1;
    }
    if (!allocation_fail_closed || alloc_fail_closed || !realloc_fail_closed || non_null_allocation_fail_closed) {
        return 1;
    }
    if (!allocator_blocked || !allocator_known_unbound) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load alloc::allocator import");
    assert!(manifest.files.iter().any(|file| {
        file.library_id == 0 && file.path == stdlib_root.join("alloc/allocator.lani")
    }));
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root alloc::allocator pointer-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("alloc::allocator pointer-result helpers should type check while allocator service remains incomplete");
}

#[test]
fn std_io_contract_matches_unbound_runtime_stdio_service() {
    common::type_check_source_pack_with_timeout(&[
        include_str!("../stdlib/core/runtime.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import core::runtime;
import std::io;

fn main() {
    let io_service_id: std::io::StdioServiceId = std::io::stdio_service_id();
    let runtime_stdio_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_STDIO_ID;
    let unknown_runtime_service_id: core::runtime::RuntimeServiceId = 99;
    let io_known: StdioCapability = std::io::stdio_service_is_known();
    let io_status: std::io::StdioServiceStatus = std::io::stdio_service_status();
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_stdio_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_runtime_service_id);
    let io_abi: std::io::StdioRuntimeAbiVersion = stdio_runtime_abi_version();
    let declared_abi: StdioRuntimeAbiVersion = STDIO_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_stdio_id);
    let io_available: std::io::StdioCapability = std::io::stdio_is_available();
    let io_blocked: std::io::StdioCapability = std::io::stdio_is_blocked();
    let io_needs_binding: std::io::StdioCapability =
        std::io::stdio_requires_runtime_binding();
    let print_i32_executable: std::io::StdioCapability =
        std::io::print_i32_is_executable();
    let print_i32_blocked: std::io::StdioCapability =
        std::io::print_i32_is_blocked();
    let print_i32_needs_binding: std::io::StdioCapability =
        std::io::print_i32_requires_runtime_binding();
    let runtime_api_executable: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_executable(runtime_stdio_id);
    let runtime_api_needs_binding: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_binding(runtime_stdio_id);
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_stdio_id);
    if (io_service_id != runtime_stdio_id) {
        return 1;
    }
    if (io_status != runtime_status || io_status == unknown_status) {
        return 1;
    }
    if (io_abi != declared_abi || io_abi != runtime_abi) {
        return 1;
    }
    if (!io_known || io_available || !io_blocked || !io_needs_binding || !print_i32_executable || print_i32_blocked || print_i32_needs_binding || runtime_api_executable || !runtime_api_needs_binding || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    ])
    .expect("std::io should advertise the same unbound stdio service contract as core::runtime");
}

#[test]
fn std_io_public_stdio_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "stdio_api", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::io;

fn main() {
    let stdio_available: std::io::StdioCapability = std::io::stdio_is_available();
    let stdio_metadata_available: std::io::StdioCapability =
        std::io::stdio_contract_metadata_is_available();
    let stdio_blocked: std::io::StdioCapability = std::io::stdio_is_blocked();
    let stdio_known_unbound: std::io::StdioCapability =
        std::io::stdio_is_known_but_unbound();
    let stdio_needs_binding: StdioCapability = stdio_requires_runtime_binding();
    let stdio_contract_only: StdioCapability = stdio_host_abi_is_contract_only();
    let output_executable: std::io::StdioCapability =
        std::io::stdio_output_api_is_executable();
    let output_blocked: StdioCapability = stdio_output_api_is_blocked();
    let output_known_unbound: StdioCapability =
        stdio_output_api_is_known_but_unbound();
    let output_needs_binding: StdioCapability =
        stdio_output_api_requires_runtime_binding();
    let input_executable: std::io::StdioCapability =
        std::io::stdio_input_api_is_executable();
    let input_blocked: std::io::StdioCapability =
        std::io::stdio_input_api_is_blocked();
    let input_known_unbound: std::io::StdioCapability =
        std::io::stdio_input_api_is_known_but_unbound();
    let input_needs_binding: StdioCapability =
        stdio_input_api_requires_runtime_binding();
    let stdout_executable: std::io::StdioCapability =
        std::io::write_stdout_is_executable();
    let stdout_blocked: std::io::StdioCapability =
        std::io::write_stdout_is_blocked();
    let stdout_known_unbound: std::io::StdioCapability =
        std::io::write_stdout_is_known_but_unbound();
    let stdout_needs_binding: StdioCapability =
        write_stdout_requires_runtime_binding();
    let stderr_executable: std::io::StdioCapability =
        std::io::write_stderr_is_executable();
    let stderr_blocked: StdioCapability = write_stderr_is_blocked();
    let stderr_known_unbound: StdioCapability =
        write_stderr_is_known_but_unbound();
    let stderr_needs_binding: StdioCapability =
        write_stderr_requires_runtime_binding();
    let stdin_executable: std::io::StdioCapability =
        std::io::read_stdin_is_executable();
    let stdin_blocked: std::io::StdioCapability = std::io::read_stdin_is_blocked();
    let stdin_known_unbound: std::io::StdioCapability =
        std::io::read_stdin_is_known_but_unbound();
    let stdin_needs_binding: StdioCapability =
        read_stdin_requires_runtime_binding();
    let flush_stdout_executable: std::io::StdioCapability =
        std::io::flush_stdout_is_executable();
    let flush_stdout_blocked: StdioCapability = flush_stdout_is_blocked();
    let flush_stdout_known_unbound: StdioCapability =
        flush_stdout_is_known_but_unbound();
    let flush_stdout_needs_binding: StdioCapability =
        flush_stdout_requires_runtime_binding();
    let flush_stderr_executable: std::io::StdioCapability =
        std::io::flush_stderr_is_executable();
    let flush_stderr_blocked: std::io::StdioCapability =
        std::io::flush_stderr_is_blocked();
    let flush_stderr_known_unbound: std::io::StdioCapability =
        std::io::flush_stderr_is_known_but_unbound();
    let flush_stderr_needs_binding: StdioCapability =
        flush_stderr_requires_runtime_binding();
    let print_i32_executable: std::io::StdioCapability =
        std::io::print_i32_is_executable();
    let print_i32_blocked: StdioCapability = print_i32_is_blocked();
    let print_i32_known_unbound: StdioCapability =
        print_i32_is_known_but_unbound();
    let print_i32_needs_binding: StdioCapability =
        print_i32_requires_runtime_binding();
    if (stdio_available || !stdio_metadata_available || !stdio_blocked || !stdio_known_unbound || !stdio_needs_binding || !stdio_contract_only) {
        return 1;
    }
    if (!output_executable || !input_executable || !stdout_executable || !stderr_executable || !stdin_executable || flush_stdout_executable || flush_stderr_executable) {
        return 1;
    }
    if (output_blocked || input_blocked || stdout_blocked || stderr_blocked || stdin_blocked || !flush_stdout_blocked || !flush_stderr_blocked) {
        return 1;
    }
    if (output_known_unbound || input_known_unbound || stdout_known_unbound || stderr_known_unbound || stdin_known_unbound || !flush_stdout_known_unbound || !flush_stderr_known_unbound) {
        return 1;
    }
    if (output_needs_binding || input_needs_binding || stdout_needs_binding || stderr_needs_binding || stdin_needs_binding || !flush_stdout_needs_binding || !flush_stderr_needs_binding) {
        return 1;
    }
    if (!print_i32_executable || print_i32_blocked || print_i32_known_unbound || print_i32_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::io import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/io.lani"))
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::io public API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::io public API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_io_operation_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "stdio_operation_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::io;

fn main() {
    let ok: std::io::StdioOperationResult = std::io::STDIO_OPERATION_OK;
    let unavailable: StdioOperationResult = STDIO_OPERATION_UNAVAILABLE;
    let ok_from_fn: std::io::StdioOperationResult = std::io::stdio_operation_ok();
    let unavailable_from_fn: StdioOperationResult = stdio_operation_unavailable();
    let byte_count: std::io::StdioOperationResult = 12;
    let other_failure: StdioOperationResult = -2;
    let ptr: u32 = 0;
    let len: usize = 0;
    let stdin_result: std::io::StdioOperationResult = std::io::read_stdin(ptr, len);
    let stdout_result: StdioOperationResult = std::io::write_stdout(ptr, len);
    let stderr_result: std::io::StdioOperationResult =
        std::io::write_stderr(ptr, len);
    let flush_stdout_result: StdioOperationResult = std::io::flush_stdout();
    let flush_stderr_result: std::io::StdioOperationResult =
        std::io::flush_stderr();
    let ok_succeeded: StdioCapability = std::io::stdio_operation_succeeded(ok);
    let byte_count_succeeded: std::io::StdioCapability =
        stdio_operation_succeeded(byte_count);
    let unavailable_failed: std::io::StdioCapability =
        std::io::stdio_operation_failed(unavailable);
    let unavailable_is_known: StdioCapability =
        stdio_operation_is_unavailable(unavailable);
    let unavailable_is_fail_closed: std::io::StdioCapability =
        std::io::stdio_operation_is_fail_closed(unavailable);
    let other_failure_is_unavailable: StdioCapability =
        stdio_operation_is_unavailable(other_failure);
    let other_failure_is_fail_closed: std::io::StdioCapability =
        std::io::stdio_operation_is_fail_closed(other_failure);
    let stdio_blocked: StdioCapability = std::io::stdio_is_blocked();
    let stdio_known_unbound: std::io::StdioCapability =
        std::io::stdio_is_known_but_unbound();
    if (ok != 0 || unavailable != -1) {
        return 1;
    }
    if (ok_from_fn != ok || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!ok_succeeded || !byte_count_succeeded || !unavailable_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!stdio_blocked || !stdio_known_unbound) {
        return 1;
    }
    return ok + stdin_result + stdout_result + stderr_result + flush_stdout_result + flush_stderr_result - stdin_result - stdout_result - stderr_result - flush_stdout_result - flush_stderr_result;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::io import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/io.lani")),
        "path manifest should include std::io from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::io operation-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::io operation-result helpers should type check while stdio remains unbound");
}

#[test]
fn core_panic_hook_contract_type_checks_against_unbound_runtime_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "panic_hook", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::panic;
import core::runtime;

fn main() {
    let hook_id: core::panic::PanicHookServiceId = core::panic::panic_hook_service_id();
    let declared_hook_id: core::panic::PanicHookServiceId =
        core::panic::PANIC_HOOK_SERVICE_ID;
    let runtime_hook_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_PANIC_HOOK_ID;
    let hook_known: core::panic::PanicCapability =
        core::panic::panic_hook_service_is_known();
    let hook_metadata: core::panic::PanicCapability =
        core::panic::panic_hook_contract_metadata_is_available();
    let hook_status: core::panic::PanicHookServiceStatus =
        core::panic::panic_hook_service_status();
    let declared_status: core::panic::PanicHookServiceStatus =
        core::panic::PANIC_HOOK_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_hook_id);
    let hook_abi: core::panic::PanicHookRuntimeAbiVersion =
        core::panic::panic_hook_runtime_abi_version();
    let declared_hook_abi: core::panic::PanicHookRuntimeAbiVersion =
        core::panic::PANIC_HOOK_RUNTIME_ABI_VERSION;
    let runtime_hook_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_hook_id);
    let hook_available: core::panic::PanicCapability =
        core::panic::panic_hook_is_available();
    let hook_blocked: core::panic::PanicCapability =
        core::panic::panic_hook_is_blocked();
    let hook_known_unbound: core::panic::PanicCapability =
        core::panic::panic_hook_is_known_but_unbound();
    let declared_binding: core::panic::PanicCapability =
        core::panic::PANIC_HOOK_HAS_RUNTIME_BINDING;
    let hook_needs_binding: core::panic::PanicCapability =
        core::panic::panic_hook_requires_runtime_binding();
    let hook_host_abi_contract_only: core::panic::PanicCapability =
        core::panic::panic_hook_host_abi_is_contract_only();
    let hook_contract_only: core::panic::PanicCapability =
        core::panic::panic_hook_is_contract_only();
    let panic_executable: core::panic::PanicCapability =
        core::panic::panic_is_executable();
    let panic_blocked: core::panic::PanicCapability =
        core::panic::panic_is_blocked();
    let panic_known_unbound: core::panic::PanicCapability =
        core::panic::panic_is_known_but_unbound();
    let panic_needs_binding: core::panic::PanicCapability =
        core::panic::panic_requires_runtime_binding();
    let unreachable_executable: core::panic::PanicCapability =
        core::panic::unreachable_is_executable();
    let unreachable_blocked: core::panic::PanicCapability =
        core::panic::unreachable_is_blocked();
    let unreachable_known_unbound: core::panic::PanicCapability =
        core::panic::unreachable_is_known_but_unbound();
    let unreachable_needs_binding: core::panic::PanicCapability =
        core::panic::unreachable_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_hook_id);
    let known_runtime_service: core::runtime::Capability =
        core::runtime::is_known_service(hook_id);
    let contract_shape: core::panic::PanicCapability =
        hook_id == declared_hook_id
        && hook_id == runtime_hook_id
        && hook_status == declared_status
        && hook_status == runtime_status
        && hook_known
        && hook_metadata
        && hook_abi == declared_hook_abi
        && hook_abi == runtime_hook_abi
        && !hook_available
        && hook_blocked
        && hook_known_unbound
        && !declared_binding
        && hook_needs_binding
        && hook_host_abi_contract_only
        && hook_contract_only
        && !panic_executable
        && panic_blocked
        && panic_known_unbound
        && panic_needs_binding
        && !unreachable_executable
        && unreachable_blocked
        && unreachable_known_unbound
        && unreachable_needs_binding
        && runtime_needs_binding
        && known_runtime_service;
    if (!contract_shape) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::panic panic-hook contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "core::panic should advertise the same unbound panic-hook service contract as core::runtime",
    );
}

#[test]
fn std_time_contract_type_checks_against_unbound_runtime_clock_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "time", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::time;

fn main() {
    let clock_service_id: std::time::ClockServiceId = std::time::clock_service_id();
    let declared_clock_id: ClockServiceId = CLOCK_SERVICE_ID;
    let runtime_clock_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_CLOCK_ID;
    let unknown_runtime_service_id: core::runtime::RuntimeServiceId = 99;
    let clock_known: ClockCapability = std::time::clock_service_is_known();
    let clock_metadata_available: ClockCapability =
        std::time::clock_contract_metadata_is_available();
    let clock_status: std::time::ClockServiceStatus = std::time::clock_service_status();
    let declared_status: ClockServiceStatus = CLOCK_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_clock_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_runtime_service_id);
    let clock_abi: std::time::ClockRuntimeAbiVersion = clock_runtime_abi_version();
    let declared_abi: ClockRuntimeAbiVersion = CLOCK_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_clock_id);
    let clock_available: std::time::ClockCapability = std::time::clock_is_available();
    let declared_binding: ClockCapability = CLOCK_HAS_RUNTIME_BINDING;
    let clock_needs_binding: std::time::ClockCapability =
        std::time::clock_requires_runtime_binding();
    let imported_needs_binding: ClockCapability = clock_requires_runtime_binding();
    let clock_contract_only: ClockCapability = clock_host_abi_is_contract_only();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_clock_id);
    if (clock_service_id != runtime_clock_id || declared_clock_id != runtime_clock_id) {
        return 1;
    }
    if (clock_status != runtime_status || declared_status != runtime_status || clock_status == unknown_status) {
        return 1;
    }
    if (clock_abi != declared_abi || clock_abi != runtime_abi) {
        return 1;
    }
    if (!clock_known || !clock_metadata_available || clock_available || declared_binding || !clock_needs_binding || !imported_needs_binding || !clock_contract_only || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::time runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::time should advertise the same unbound clock service contract as core::runtime");
}

#[test]
fn std_time_public_clock_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "time_api", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::time;

fn main() {
    let clock_available: std::time::ClockCapability = std::time::clock_is_available();
    let clock_blocked: std::time::ClockCapability = std::time::clock_is_blocked();
    let clock_known_unbound: std::time::ClockCapability =
        std::time::clock_is_known_but_unbound();
    let clock_needs_binding: ClockCapability = clock_requires_runtime_binding();
    let clock_read_executable: std::time::ClockCapability =
        std::time::clock_read_api_is_executable();
    let clock_read_blocked: ClockCapability = clock_read_api_is_blocked();
    let clock_read_known_unbound: ClockCapability =
        clock_read_api_is_known_but_unbound();
    let clock_read_needs_binding: ClockCapability =
        clock_read_api_requires_runtime_binding();
    let clock_sleep_executable: std::time::ClockCapability =
        std::time::clock_sleep_api_is_executable();
    let clock_sleep_blocked: ClockCapability = clock_sleep_api_is_blocked();
    let clock_sleep_known_unbound: ClockCapability =
        clock_sleep_api_is_known_but_unbound();
    let clock_sleep_needs_binding: ClockCapability =
        clock_sleep_api_requires_runtime_binding();
    let monotonic_executable: std::time::ClockCapability =
        std::time::monotonic_now_ns_is_executable();
    let monotonic_blocked: std::time::ClockCapability =
        std::time::monotonic_now_ns_is_blocked();
    let monotonic_known_unbound: ClockCapability =
        monotonic_now_ns_is_known_but_unbound();
    let monotonic_needs_binding: ClockCapability =
        monotonic_now_ns_requires_runtime_binding();
    let system_executable: std::time::ClockCapability =
        std::time::system_now_unix_ms_is_executable();
    let system_blocked: ClockCapability = system_now_unix_ms_is_blocked();
    let system_known_unbound: ClockCapability =
        system_now_unix_ms_is_known_but_unbound();
    let system_needs_binding: ClockCapability =
        system_now_unix_ms_requires_runtime_binding();
    let sleep_executable: std::time::ClockCapability =
        std::time::sleep_ms_is_executable();
    let sleep_blocked: ClockCapability = std::time::sleep_ms_is_blocked();
    let sleep_known_unbound: ClockCapability = sleep_ms_is_known_but_unbound();
    let sleep_needs_binding: ClockCapability = sleep_ms_requires_runtime_binding();
    if (clock_available || !clock_blocked || !clock_known_unbound || !clock_needs_binding) {
        return 1;
    }
    if (clock_read_executable || !clock_read_blocked || !clock_read_known_unbound || !clock_read_needs_binding) {
        return 1;
    }
    if (clock_sleep_executable || !clock_sleep_blocked || !clock_sleep_known_unbound || !clock_sleep_needs_binding) {
        return 1;
    }
    if (monotonic_executable || system_executable || sleep_executable) {
        return 1;
    }
    if (!monotonic_blocked || !system_blocked || !sleep_blocked) {
        return 1;
    }
    if (!monotonic_known_unbound || !system_known_unbound || !sleep_known_unbound) {
        return 1;
    }
    if (!monotonic_needs_binding || !system_needs_binding || !sleep_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::time import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/time.lani")),
        "path manifest should include std::time from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::time API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::time clock API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_time_public_clock_calls_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "time_calls", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::time;

fn main() {
    let monotonic_ns: i64 = std::time::monotonic_now_ns();
    let unix_ms: i64 = std::time::system_now_unix_ms();
    let sleep_status: i32 = std::time::sleep_ms(0);
    let read_blocked: std::time::ClockCapability =
        std::time::clock_read_api_is_blocked();
    let sleep_blocked: std::time::ClockCapability =
        std::time::clock_sleep_api_is_blocked();
    if (!read_blocked || !sleep_blocked) {
        return 1;
    }
    if (monotonic_ns == unix_ms) {
        return sleep_status - sleep_status;
    }
    return sleep_status - sleep_status;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::time import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/time.lani")),
        "path manifest should include std::time from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::time public clock calls",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::time clock calls should type check through --stdlib-root while unbound");
}

#[test]
fn std_time_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "time_result_contract",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::time;

fn main() {
    let read_unavailable: std::time::ClockReadResult =
        std::time::CLOCK_READ_UNAVAILABLE;
    let read_unavailable_from_fn: ClockReadResult = clock_read_unavailable();
    let read_value: std::time::ClockReadResult = 42;
    let read_other_failure: ClockReadResult = -2;
    let monotonic_result: std::time::ClockReadResult =
        std::time::monotonic_now_ns();
    let system_result: ClockReadResult = system_now_unix_ms();
    let read_value_succeeded: std::time::ClockCapability =
        std::time::clock_read_result_succeeded(read_value);
    let read_unavailable_failed: ClockCapability =
        clock_read_result_failed(read_unavailable);
    let read_unavailable_is_known: std::time::ClockCapability =
        std::time::clock_read_result_is_unavailable(read_unavailable);
    let read_unavailable_is_fail_closed: ClockCapability =
        clock_read_result_is_fail_closed(read_unavailable);
    let read_other_failure_is_unavailable: std::time::ClockCapability =
        std::time::clock_read_result_is_unavailable(read_other_failure);
    let read_other_failure_is_fail_closed: ClockCapability =
        clock_read_result_is_fail_closed(read_other_failure);

    let sleep_ok: std::time::ClockSleepResult = std::time::CLOCK_SLEEP_OK;
    let sleep_unavailable: ClockSleepResult = CLOCK_SLEEP_UNAVAILABLE;
    let sleep_ok_from_fn: std::time::ClockSleepResult = std::time::clock_sleep_ok();
    let sleep_unavailable_from_fn: ClockSleepResult = clock_sleep_unavailable();
    let sleep_result: std::time::ClockSleepResult = std::time::sleep_ms(0);
    let sleep_other_failure: ClockSleepResult = -2;
    let sleep_ok_succeeded: ClockCapability =
        std::time::clock_sleep_result_succeeded(sleep_ok);
    let sleep_unavailable_failed: std::time::ClockCapability =
        clock_sleep_result_failed(sleep_unavailable);
    let sleep_unavailable_is_known: ClockCapability =
        std::time::clock_sleep_result_is_unavailable(sleep_unavailable);
    let sleep_unavailable_is_fail_closed: std::time::ClockCapability =
        std::time::clock_sleep_result_is_fail_closed(sleep_unavailable);
    let sleep_other_failure_is_unavailable: ClockCapability =
        clock_sleep_result_is_unavailable(sleep_other_failure);
    let sleep_other_failure_is_fail_closed: std::time::ClockCapability =
        clock_sleep_result_is_fail_closed(sleep_other_failure);

    if (read_unavailable != -1 || read_unavailable_from_fn != read_unavailable) {
        return 1;
    }
    if (!read_value_succeeded || !read_unavailable_failed || !read_unavailable_is_known || !read_unavailable_is_fail_closed) {
        return 1;
    }
    if (read_other_failure_is_unavailable || read_other_failure_is_fail_closed) {
        return 1;
    }
    if (sleep_ok != 0 || sleep_unavailable != -1 || sleep_ok_from_fn != sleep_ok || sleep_unavailable_from_fn != sleep_unavailable) {
        return 1;
    }
    if (!sleep_ok_succeeded || !sleep_unavailable_failed || !sleep_unavailable_is_known || !sleep_unavailable_is_fail_closed) {
        return 1;
    }
    if (sleep_other_failure_is_unavailable || sleep_other_failure_is_fail_closed) {
        return 1;
    }
    if (monotonic_result == system_result) {
        return sleep_result - sleep_result;
    }
    return sleep_result - sleep_result;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::time import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/time.lani")),
        "path manifest should include std::time from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::time result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::time result helpers should type check while clock services remain unbound");
}

#[test]
fn std_fs_contract_type_checks_against_unbound_runtime_filesystem_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "fs", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::fs;

fn main() {
    let fs_service_id: std::fs::FilesystemServiceId = std::fs::filesystem_service_id();
    let declared_fs_id: FilesystemServiceId = FILESYSTEM_SERVICE_ID;
    let runtime_fs_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_FILESYSTEM_ID;
    let unknown_runtime_service_id: core::runtime::RuntimeServiceId = 99;
    let fs_known: FilesystemCapability = filesystem_service_is_known();
    let fs_status: std::fs::FilesystemServiceStatus = std::fs::filesystem_service_status();
    let declared_status: FilesystemServiceStatus = FILESYSTEM_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_fs_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_runtime_service_id);
    let fs_abi: std::fs::FilesystemRuntimeAbiVersion =
        filesystem_runtime_abi_version();
    let declared_abi: FilesystemRuntimeAbiVersion = FILESYSTEM_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_fs_id);
    let fs_available: std::fs::FilesystemCapability = std::fs::filesystem_is_available();
    let declared_binding: FilesystemCapability = FILESYSTEM_HAS_RUNTIME_BINDING;
    let fs_needs_binding: std::fs::FilesystemCapability =
        std::fs::filesystem_requires_runtime_binding();
    let imported_needs_binding: FilesystemCapability =
        filesystem_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_fs_id);
    if (fs_service_id != runtime_fs_id || declared_fs_id != runtime_fs_id) {
        return 1;
    }
    if (fs_status != runtime_status || declared_status != runtime_status || fs_status == unknown_status) {
        return 1;
    }
    if (fs_abi != declared_abi || fs_abi != runtime_abi) {
        return 1;
    }
    if (!fs_known || fs_available || declared_binding || !fs_needs_binding || !imported_needs_binding || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::fs should advertise the same unbound filesystem service contract as core::runtime",
    );
}

#[test]
fn std_fs_public_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "fs_api", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::fs;

fn main() {
    let fs_available: std::fs::FilesystemCapability = std::fs::filesystem_is_available();
    let fs_metadata_available: std::fs::FilesystemCapability =
        std::fs::filesystem_contract_metadata_is_available();
    let fs_blocked: std::fs::FilesystemCapability = std::fs::filesystem_is_blocked();
    let fs_known_unbound: std::fs::FilesystemCapability =
        std::fs::filesystem_is_known_but_unbound();
    let fs_needs_binding: FilesystemCapability = filesystem_requires_runtime_binding();
    let fs_contract_only: FilesystemCapability = filesystem_host_abi_is_contract_only();
    let file_io_executable: std::fs::FilesystemCapability =
        std::fs::file_io_is_executable();
    let file_io_blocked: std::fs::FilesystemCapability =
        std::fs::file_io_is_blocked();
    let file_io_known_unbound: FilesystemCapability =
        file_io_is_known_but_unbound();
    let file_io_needs_binding: FilesystemCapability =
        file_io_requires_runtime_binding();
    let path_mutation_executable: std::fs::FilesystemCapability =
        std::fs::path_mutation_api_is_executable();
    let path_mutation_blocked: FilesystemCapability =
        path_mutation_api_is_blocked();
    let path_mutation_known_unbound: std::fs::FilesystemCapability =
        std::fs::path_mutation_api_is_known_but_unbound();
    let path_mutation_needs_binding: FilesystemCapability =
        path_mutation_api_requires_runtime_binding();
    if (fs_available || !fs_metadata_available || !fs_blocked || !fs_known_unbound || !fs_needs_binding || !fs_contract_only) {
        return 1;
    }
    if (file_io_executable || !file_io_blocked || !file_io_needs_binding) {
        return 1;
    }
    if (!file_io_known_unbound || !path_mutation_known_unbound) {
        return 1;
    }
    if (path_mutation_executable || !path_mutation_blocked || !path_mutation_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::fs import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/fs.lani")),
        "path manifest should include std::fs from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs public API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::fs public API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_fs_public_path_mutation_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "fs_path_mutation_api",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::fs;

fn main() {
    let path_mutation_executable: std::fs::FilesystemCapability =
        std::fs::path_mutation_api_is_executable();
    let path_mutation_blocked: FilesystemCapability =
        path_mutation_api_is_blocked();
    let path_mutation_needs_binding: FilesystemCapability =
        path_mutation_api_requires_runtime_binding();
    let remove_file_executable: std::fs::FilesystemCapability =
        std::fs::remove_file_is_executable();
    let remove_file_blocked: FilesystemCapability = remove_file_is_blocked();
    let remove_file_known_unbound: std::fs::FilesystemCapability =
        std::fs::remove_file_is_known_but_unbound();
    let remove_file_needs_binding: FilesystemCapability =
        remove_file_requires_runtime_binding();
    let create_dir_executable: std::fs::FilesystemCapability =
        std::fs::create_dir_is_executable();
    let create_dir_blocked: FilesystemCapability = create_dir_is_blocked();
    let create_dir_known_unbound: FilesystemCapability =
        create_dir_is_known_but_unbound();
    let create_dir_needs_binding: FilesystemCapability =
        create_dir_requires_runtime_binding();
    let remove_dir_executable: std::fs::FilesystemCapability =
        std::fs::remove_dir_is_executable();
    let remove_dir_blocked: FilesystemCapability = remove_dir_is_blocked();
    let remove_dir_known_unbound: std::fs::FilesystemCapability =
        std::fs::remove_dir_is_known_but_unbound();
    let remove_dir_needs_binding: FilesystemCapability =
        remove_dir_requires_runtime_binding();
    let rename_executable: std::fs::FilesystemCapability =
        std::fs::rename_is_executable();
    let rename_blocked: FilesystemCapability = rename_is_blocked();
    let rename_known_unbound: FilesystemCapability =
        rename_is_known_but_unbound();
    let rename_needs_binding: FilesystemCapability =
        rename_requires_runtime_binding();
    if (path_mutation_executable || remove_file_executable || create_dir_executable || remove_dir_executable || rename_executable) {
        return 1;
    }
    if (!path_mutation_blocked || !remove_file_blocked || !create_dir_blocked || !remove_dir_blocked || !rename_blocked) {
        return 1;
    }
    if (!remove_file_known_unbound || !create_dir_known_unbound || !remove_dir_known_unbound || !rename_known_unbound) {
        return 1;
    }
    if (!path_mutation_needs_binding || !remove_file_needs_binding || !create_dir_needs_binding || !remove_dir_needs_binding || !rename_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::fs import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/fs.lani")),
        "path manifest should include std::fs from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs path-mutation API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::fs path-mutation API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_fs_public_path_mutation_calls_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "fs_path_mutation_calls",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::fs;

fn main() {
    let remove_file_status: i32 = std::fs::remove_file(0, 0);
    let create_dir_status: i32 = std::fs::create_dir(0, 0);
    let remove_dir_status: i32 = std::fs::remove_dir(0, 0);
    let rename_status: i32 = std::fs::rename(0, 0, 0, 0);
    let path_mutation_blocked: std::fs::FilesystemCapability =
        std::fs::path_mutation_api_is_blocked();
    if (!path_mutation_blocked) {
        return 1;
    }
    return remove_file_status + create_dir_status + remove_dir_status + rename_status - remove_file_status - create_dir_status - remove_dir_status - rename_status;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::fs import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/fs.lani")),
        "path manifest should include std::fs from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs path-mutation public calls",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::fs path-mutation calls should type check through --stdlib-root while unbound");
}

#[test]
fn std_fs_public_file_io_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "fs_file_io_api", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::fs;

fn main() {
    let file_io_executable: std::fs::FilesystemCapability =
        std::fs::file_io_is_executable();
    let file_io_blocked: FilesystemCapability = file_io_is_blocked();
    let file_io_needs_binding: FilesystemCapability =
        file_io_requires_runtime_binding();
    let open_read_executable: std::fs::FilesystemCapability =
        std::fs::open_read_is_executable();
    let open_read_blocked: FilesystemCapability = open_read_is_blocked();
    let open_read_known_unbound: std::fs::FilesystemCapability =
        std::fs::open_read_is_known_but_unbound();
    let open_read_needs_binding: FilesystemCapability =
        open_read_requires_runtime_binding();
    let open_write_executable: std::fs::FilesystemCapability =
        std::fs::open_write_is_executable();
    let open_write_blocked: FilesystemCapability = open_write_is_blocked();
    let open_write_known_unbound: FilesystemCapability =
        open_write_is_known_but_unbound();
    let open_write_needs_binding: FilesystemCapability =
        open_write_requires_runtime_binding();
    let open_append_executable: std::fs::FilesystemCapability =
        std::fs::open_append_is_executable();
    let open_append_blocked: FilesystemCapability = open_append_is_blocked();
    let open_append_known_unbound: std::fs::FilesystemCapability =
        std::fs::open_append_is_known_but_unbound();
    let open_append_needs_binding: FilesystemCapability =
        open_append_requires_runtime_binding();
    let close_executable: std::fs::FilesystemCapability =
        std::fs::close_is_executable();
    let close_blocked: FilesystemCapability = close_is_blocked();
    let close_known_unbound: FilesystemCapability = close_is_known_but_unbound();
    let close_needs_binding: FilesystemCapability = close_requires_runtime_binding();
    let read_executable: std::fs::FilesystemCapability =
        std::fs::read_is_executable();
    let read_blocked: FilesystemCapability = read_is_blocked();
    let read_known_unbound: std::fs::FilesystemCapability =
        std::fs::read_is_known_but_unbound();
    let read_needs_binding: FilesystemCapability = read_requires_runtime_binding();
    let write_executable: std::fs::FilesystemCapability =
        std::fs::write_is_executable();
    let write_blocked: FilesystemCapability = write_is_blocked();
    let write_known_unbound: FilesystemCapability = write_is_known_but_unbound();
    let write_needs_binding: FilesystemCapability = write_requires_runtime_binding();
    if (!file_io_executable || !open_read_executable || !open_write_executable || !open_append_executable) {
        return 1;
    }
    if (!close_executable || !read_executable || !write_executable) {
        return 1;
    }
    if (file_io_blocked || open_read_blocked || open_write_blocked || open_append_blocked) {
        return 1;
    }
    if (close_blocked || read_blocked || write_blocked) {
        return 1;
    }
    if (open_read_known_unbound || open_write_known_unbound || open_append_known_unbound) {
        return 1;
    }
    if (close_known_unbound || read_known_unbound || write_known_unbound) {
        return 1;
    }
    if (file_io_needs_binding || open_read_needs_binding || open_write_needs_binding || open_append_needs_binding) {
        return 1;
    }
    if (close_needs_binding || read_needs_binding || write_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::fs import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/fs.lani")),
        "path manifest should include std::fs from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs file-I/O API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::fs file-I/O API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_fs_operation_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "fs_operation_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::fs;

fn main() {
    let ok: std::fs::FilesystemOperationResult = std::fs::FILESYSTEM_OPERATION_OK;
    let unavailable: FilesystemOperationResult = FILESYSTEM_OPERATION_UNAVAILABLE;
    let ok_from_fn: std::fs::FilesystemOperationResult = std::fs::filesystem_operation_ok();
    let unavailable_from_fn: FilesystemOperationResult =
        filesystem_operation_unavailable();
    let byte_count: std::fs::FilesystemOperationResult = 12;
    let other_failure: FilesystemOperationResult = -2;
    let ptr: u32 = 0;
    let len: usize = 0;
    let open_read_result: std::fs::FilesystemOperationResult =
        std::fs::open_read(ptr, len);
    let open_write_result: FilesystemOperationResult =
        std::fs::open_write(ptr, len);
    let open_append_result: std::fs::FilesystemOperationResult =
        std::fs::open_append(ptr, len);
    let close_result: FilesystemOperationResult = std::fs::close(0);
    let read_result: std::fs::FilesystemOperationResult =
        std::fs::read(0, ptr, len);
    let write_result: FilesystemOperationResult = std::fs::write(0, ptr, len);
    let remove_result: std::fs::FilesystemOperationResult =
        std::fs::remove_file(ptr, len);
    let create_result: FilesystemOperationResult = std::fs::create_dir(ptr, len);
    let remove_dir_result: std::fs::FilesystemOperationResult =
        std::fs::remove_dir(ptr, len);
    let rename_result: FilesystemOperationResult =
        std::fs::rename(ptr, len, ptr, len);
    let ok_succeeded: FilesystemCapability =
        std::fs::filesystem_operation_succeeded(ok);
    let byte_count_succeeded: std::fs::FilesystemCapability =
        filesystem_operation_succeeded(byte_count);
    let unavailable_failed: FilesystemCapability =
        std::fs::filesystem_operation_failed(unavailable);
    let unavailable_is_known: std::fs::FilesystemCapability =
        std::fs::filesystem_operation_is_unavailable(unavailable);
    let unavailable_is_fail_closed: FilesystemCapability =
        filesystem_operation_is_fail_closed(unavailable);
    let other_failure_is_unavailable: std::fs::FilesystemCapability =
        std::fs::filesystem_operation_is_unavailable(other_failure);
    let other_failure_is_fail_closed: FilesystemCapability =
        filesystem_operation_is_fail_closed(other_failure);
    let fs_blocked: std::fs::FilesystemCapability = std::fs::filesystem_is_blocked();
    let fs_known_unbound: FilesystemCapability =
        filesystem_is_known_but_unbound();
    if (ok != 0 || unavailable != -1) {
        return 1;
    }
    if (ok_from_fn != ok || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!ok_succeeded || !byte_count_succeeded || !unavailable_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!fs_blocked || !fs_known_unbound) {
        return 1;
    }
    return ok + open_read_result + open_write_result + open_append_result + close_result + read_result + write_result + remove_result + create_result + remove_dir_result + rename_result - open_read_result - open_write_result - open_append_result - close_result - read_result - write_result - remove_result - create_result - remove_dir_result - rename_result;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::fs import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/fs.lani")),
        "path manifest should include std::fs from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs operation-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::fs operation-result helpers should type check while filesystem remains unbound");
}

#[test]
fn std_fs_file_handle_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "fs_file_handle", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::fs;

fn main() {
    let invalid_handle: std::fs::FileHandle = std::fs::FILE_HANDLE_INVALID;
    let invalid_from_fn: FileHandle = file_handle_invalid();
    let opened_handle: std::fs::FileHandle = 4;
    let unavailable_result: FilesystemOperationResult =
        FILESYSTEM_OPERATION_UNAVAILABLE;
    let invalid_is_invalid: std::fs::FilesystemCapability =
        std::fs::file_handle_is_invalid(invalid_handle);
    let invalid_is_valid: FilesystemCapability =
        file_handle_is_valid(invalid_handle);
    let opened_is_valid: std::fs::FilesystemCapability =
        std::fs::file_handle_is_valid(opened_handle);
    let opened_is_invalid: FilesystemCapability =
        file_handle_is_invalid(opened_handle);
    let unavailable_is_fail_closed: std::fs::FilesystemCapability =
        filesystem_operation_is_fail_closed(unavailable_result);
    let fs_known_unbound: FilesystemCapability =
        filesystem_is_known_but_unbound();
    if (invalid_handle != -1 || invalid_from_fn != invalid_handle) {
        return 1;
    }
    if (!invalid_is_invalid || invalid_is_valid || !opened_is_valid || opened_is_invalid) {
        return 1;
    }
    if (!unavailable_is_fail_closed || !fs_known_unbound) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::fs import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/fs.lani")),
        "path manifest should include std::fs from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::fs file-handle contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::fs file-handle helpers should type check while filesystem remains unbound");
}

#[test]
fn std_net_contract_type_checks_against_unbound_runtime_network_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "net", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::net;

fn main() {
    let network_service_id: std::net::NetworkServiceId = std::net::network_service_id();
    let declared_network_id: NetworkServiceId = NETWORK_SERVICE_ID;
    let runtime_network_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_NETWORK_ID;
    let unknown_runtime_service_id: core::runtime::RuntimeServiceId = 99;
    let network_known: NetworkCapability = std::net::network_service_is_known();
    let network_metadata_available: NetworkCapability =
        std::net::network_contract_metadata_is_available();
    let network_status: std::net::NetworkServiceStatus = std::net::network_service_status();
    let declared_status: NetworkServiceStatus = NETWORK_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_network_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_runtime_service_id);
    let network_abi: std::net::NetworkRuntimeAbiVersion =
        network_runtime_abi_version();
    let declared_abi: NetworkRuntimeAbiVersion = NETWORK_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_network_id);
    let network_available: std::net::NetworkCapability = std::net::network_is_available();
    let declared_binding: NetworkCapability = NETWORK_HAS_RUNTIME_BINDING;
    let network_needs_binding: std::net::NetworkCapability =
        std::net::network_requires_runtime_binding();
    let imported_needs_binding: NetworkCapability = network_requires_runtime_binding();
    let network_contract_only: NetworkCapability = network_host_abi_is_contract_only();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_network_id);
    if (network_service_id != runtime_network_id || declared_network_id != runtime_network_id) {
        return 1;
    }
    if (network_status != runtime_status || declared_status != runtime_status || network_status == unknown_status) {
        return 1;
    }
    if (network_abi != declared_abi || network_abi != runtime_abi) {
        return 1;
    }
    if (!network_known || !network_metadata_available || network_available || declared_binding || !network_needs_binding || !imported_needs_binding || !network_contract_only || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::net runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::net should advertise the same unbound network service contract as core::runtime");
}

#[test]
fn std_net_public_socket_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "net_api", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::net;

fn main() {
    let network_available: std::net::NetworkCapability = std::net::network_is_available();
    let network_blocked: std::net::NetworkCapability = std::net::network_is_blocked();
    let network_known_unbound: std::net::NetworkCapability =
        std::net::network_is_known_but_unbound();
    let network_needs_binding: NetworkCapability = network_requires_runtime_binding();
    let tcp_executable: std::net::NetworkCapability = std::net::tcp_api_is_executable();
    let tcp_blocked: NetworkCapability = tcp_api_is_blocked();
    let tcp_known_unbound: std::net::NetworkCapability =
        std::net::tcp_api_is_known_but_unbound();
    let tcp_needs_binding: NetworkCapability = tcp_api_requires_runtime_binding();
    let tcp_connect_executable: std::net::NetworkCapability =
        std::net::tcp_connect_is_executable();
    let tcp_connect_blocked: NetworkCapability = tcp_connect_is_blocked();
    let tcp_connect_known_unbound: NetworkCapability =
        tcp_connect_is_known_but_unbound();
    let tcp_connect_needs_binding: NetworkCapability =
        tcp_connect_requires_runtime_binding();
    let tcp_bind_executable: std::net::NetworkCapability =
        std::net::tcp_bind_is_executable();
    let tcp_bind_blocked: NetworkCapability = tcp_bind_is_blocked();
    let tcp_bind_known_unbound: NetworkCapability = tcp_bind_is_known_but_unbound();
    let tcp_bind_needs_binding: NetworkCapability = tcp_bind_requires_runtime_binding();
    let tcp_listen_executable: std::net::NetworkCapability =
        std::net::tcp_listen_is_executable();
    let tcp_listen_blocked: NetworkCapability = tcp_listen_is_blocked();
    let tcp_listen_known_unbound: NetworkCapability =
        tcp_listen_is_known_but_unbound();
    let tcp_listen_needs_binding: NetworkCapability =
        tcp_listen_requires_runtime_binding();
    let tcp_accept_executable: std::net::NetworkCapability =
        std::net::tcp_accept_is_executable();
    let tcp_accept_blocked: NetworkCapability = tcp_accept_is_blocked();
    let tcp_accept_known_unbound: NetworkCapability =
        tcp_accept_is_known_but_unbound();
    let tcp_accept_needs_binding: NetworkCapability =
        tcp_accept_requires_runtime_binding();
    let tcp_close_executable: std::net::NetworkCapability =
        std::net::tcp_close_is_executable();
    let tcp_close_blocked: NetworkCapability = tcp_close_is_blocked();
    let tcp_close_known_unbound: NetworkCapability = tcp_close_is_known_but_unbound();
    let tcp_close_needs_binding: NetworkCapability =
        tcp_close_requires_runtime_binding();
    let tcp_send_executable: std::net::NetworkCapability =
        std::net::tcp_send_is_executable();
    let tcp_send_blocked: NetworkCapability = tcp_send_is_blocked();
    let tcp_send_known_unbound: NetworkCapability = tcp_send_is_known_but_unbound();
    let tcp_send_needs_binding: NetworkCapability = tcp_send_requires_runtime_binding();
    let tcp_recv_executable: std::net::NetworkCapability =
        std::net::tcp_recv_is_executable();
    let tcp_recv_blocked: NetworkCapability = tcp_recv_is_blocked();
    let tcp_recv_known_unbound: NetworkCapability = tcp_recv_is_known_but_unbound();
    let tcp_recv_needs_binding: NetworkCapability = tcp_recv_requires_runtime_binding();
    let udp_executable: std::net::NetworkCapability = std::net::udp_api_is_executable();
    let udp_blocked: std::net::NetworkCapability = std::net::udp_api_is_blocked();
    let udp_known_unbound: NetworkCapability = udp_api_is_known_but_unbound();
    let udp_needs_binding: NetworkCapability = udp_api_requires_runtime_binding();
    let udp_bind_executable: std::net::NetworkCapability =
        std::net::udp_bind_is_executable();
    let udp_bind_blocked: NetworkCapability = udp_bind_is_blocked();
    let udp_bind_known_unbound: NetworkCapability = udp_bind_is_known_but_unbound();
    let udp_bind_needs_binding: NetworkCapability = udp_bind_requires_runtime_binding();
    let udp_send_to_executable: std::net::NetworkCapability =
        std::net::udp_send_to_is_executable();
    let udp_send_to_blocked: NetworkCapability = udp_send_to_is_blocked();
    let udp_send_to_known_unbound: NetworkCapability =
        udp_send_to_is_known_but_unbound();
    let udp_send_to_needs_binding: NetworkCapability =
        udp_send_to_requires_runtime_binding();
    let udp_recv_from_executable: std::net::NetworkCapability =
        std::net::udp_recv_from_is_executable();
    let udp_recv_from_blocked: NetworkCapability = udp_recv_from_is_blocked();
    let udp_recv_from_known_unbound: NetworkCapability =
        udp_recv_from_is_known_but_unbound();
    let udp_recv_from_needs_binding: NetworkCapability =
        udp_recv_from_requires_runtime_binding();
    if (network_available || !network_blocked || !network_known_unbound || !network_needs_binding) {
        return 1;
    }
    if (tcp_executable || udp_executable) {
        return 1;
    }
    if (!tcp_blocked || !udp_blocked) {
        return 1;
    }
    if (!tcp_known_unbound || !udp_known_unbound) {
        return 1;
    }
    if (!tcp_needs_binding || !udp_needs_binding) {
        return 1;
    }
    if (tcp_connect_executable || tcp_bind_executable || tcp_listen_executable || tcp_accept_executable || tcp_close_executable || tcp_send_executable || tcp_recv_executable) {
        return 1;
    }
    if (!tcp_connect_blocked || !tcp_bind_blocked || !tcp_listen_blocked || !tcp_accept_blocked || !tcp_close_blocked || !tcp_send_blocked || !tcp_recv_blocked) {
        return 1;
    }
    if (!tcp_connect_known_unbound || !tcp_bind_known_unbound || !tcp_listen_known_unbound || !tcp_accept_known_unbound || !tcp_close_known_unbound || !tcp_send_known_unbound || !tcp_recv_known_unbound) {
        return 1;
    }
    if (!tcp_connect_needs_binding || !tcp_bind_needs_binding || !tcp_listen_needs_binding || !tcp_accept_needs_binding || !tcp_close_needs_binding || !tcp_send_needs_binding || !tcp_recv_needs_binding) {
        return 1;
    }
    if (udp_bind_executable || udp_send_to_executable || udp_recv_from_executable) {
        return 1;
    }
    if (!udp_bind_blocked || !udp_send_to_blocked || !udp_recv_from_blocked) {
        return 1;
    }
    if (!udp_bind_known_unbound || !udp_send_to_known_unbound || !udp_recv_from_known_unbound) {
        return 1;
    }
    if (!udp_bind_needs_binding || !udp_send_to_needs_binding || !udp_recv_from_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::net import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/net.lani")),
        "path manifest should include std::net from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::net socket API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::net TCP/UDP API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_net_public_listener_and_receive_calls_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "net_listener_receive_calls",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::net;

fn main() {
    let listener: i32 = std::net::tcp_bind(0, 0, 80);
    let listen_status: i32 = std::net::tcp_listen(listener, 1);
    let accepted: i32 = std::net::tcp_accept(listener);
    let close_listener_status: i32 = std::net::tcp_close(listener);
    let close_accepted_status: i32 = std::net::tcp_close(accepted);
    let udp_handle: i32 = std::net::udp_bind(0, 0, 53);
    let udp_send_status: i32 = std::net::udp_send_to(udp_handle, 0, 0, 0);
    let udp_receive_status: i32 = std::net::udp_recv_from(udp_handle, 0, 0, 0);
    let tcp_blocked: std::net::NetworkCapability = std::net::tcp_api_is_blocked();
    let udp_blocked: std::net::NetworkCapability = std::net::udp_api_is_blocked();
    if (!tcp_blocked || !udp_blocked) {
        return 1;
    }
    return listen_status + close_listener_status + close_accepted_status + udp_send_status + udp_receive_status - listen_status - close_listener_status - close_accepted_status - udp_send_status - udp_receive_status;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::net import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/net.lani")),
        "path manifest should include std::net from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::net listener and receive calls",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::net listener and receive calls should type check through --stdlib-root while unbound",
    );
}

#[test]
fn std_net_operation_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "net_operation_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::net;

fn main() {
    let ok: std::net::NetworkOperationResult = std::net::NETWORK_OPERATION_OK;
    let unavailable: NetworkOperationResult = NETWORK_OPERATION_UNAVAILABLE;
    let ok_from_fn: std::net::NetworkOperationResult =
        std::net::network_operation_ok();
    let unavailable_from_fn: NetworkOperationResult =
        network_operation_unavailable();
    let byte_count: std::net::NetworkOperationResult = 16;
    let other_failure: NetworkOperationResult = -2;
    let addr_ptr: u32 = 0;
    let addr_len: usize = 0;
    let endpoint_ptr: u32 = 0;
    let payload_ptr: u32 = 0;
    let payload_len: usize = 0;
    let tcp: std::net::NetworkOperationResult = std::net::tcp_connect(addr_ptr, addr_len, 80);
    let listen_status: NetworkOperationResult = tcp_listen(tcp, 1);
    let close_status: std::net::NetworkOperationResult = std::net::tcp_close(tcp);
    let udp: NetworkOperationResult = std::net::udp_bind(addr_ptr, addr_len, 53);
    let send_status: std::net::NetworkOperationResult =
        std::net::udp_send_to(udp, endpoint_ptr, payload_ptr, payload_len);
    let receive_status: NetworkOperationResult =
        udp_recv_from(udp, endpoint_ptr, payload_ptr, payload_len);
    let ok_succeeded: std::net::NetworkCapability =
        std::net::network_operation_succeeded(ok);
    let byte_count_succeeded: NetworkCapability =
        network_operation_succeeded(byte_count);
    let unavailable_failed: std::net::NetworkCapability =
        std::net::network_operation_failed(unavailable);
    let unavailable_is_known: NetworkCapability =
        network_operation_is_unavailable(unavailable);
    let unavailable_is_fail_closed: std::net::NetworkCapability =
        std::net::network_operation_is_fail_closed(unavailable);
    let other_failure_is_unavailable: NetworkCapability =
        network_operation_is_unavailable(other_failure);
    let other_failure_is_fail_closed: std::net::NetworkCapability =
        std::net::network_operation_is_fail_closed(other_failure);
    let network_blocked: NetworkCapability = std::net::network_is_blocked();
    let network_known_unbound: std::net::NetworkCapability =
        std::net::network_is_known_but_unbound();
    if (ok != 0 || unavailable != -1) {
        return 1;
    }
    if (ok_from_fn != ok || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!ok_succeeded || !byte_count_succeeded || !unavailable_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!network_blocked || !network_known_unbound) {
        return 1;
    }
    return ok + tcp + listen_status + close_status + udp + send_status + receive_status - tcp - listen_status - close_status - udp - send_status - receive_status;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::net import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/net.lani")),
        "path manifest should include std::net from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::net operation-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::net operation-result helpers should type check while networking remains unbound");
}

#[test]
fn std_host_contract_type_checks_against_unbound_aggregate_host_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "host", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::host;

fn main() {
    let host_service_id: std::host::HostServicesServiceId =
        std::host::host_services_service_id();
    let declared_host_id: HostServicesServiceId = HOST_SERVICES_SERVICE_ID;
    let runtime_host_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_HOST_SERVICES_ID;
    let host_known: HostServicesCapability =
        std::host::host_services_service_is_known();
    let host_metadata_available: std::host::HostServicesCapability =
        std::host::host_services_contract_metadata_is_available();
    let host_status: std::host::HostServicesServiceStatus =
        std::host::host_services_service_status();
    let declared_status: HostServicesServiceStatus =
        HOST_SERVICES_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_host_id);
    let host_abi: std::host::HostServicesRuntimeAbiVersion =
        host_services_runtime_abi_version();
    let declared_abi: HostServicesRuntimeAbiVersion =
        HOST_SERVICES_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_host_id);
    let host_available: std::host::HostServicesCapability =
        std::host::host_services_are_available();
    let host_blocked: HostServicesCapability = host_services_are_blocked();
    let host_known_unbound: std::host::HostServicesCapability =
        std::host::host_services_are_known_but_unbound();
    let declared_binding: HostServicesCapability =
        HOST_SERVICES_HAS_RUNTIME_BINDING;
    let host_needs_binding: std::host::HostServicesCapability =
        std::host::host_services_require_runtime_binding();
    let host_needs_binding_canonical: std::host::HostServicesCapability =
        std::host::host_services_requires_runtime_binding();
    let imported_needs_binding: HostServicesCapability =
        host_services_require_runtime_binding();
    let imported_needs_binding_canonical: HostServicesCapability =
        host_services_requires_runtime_binding();
    let host_contract_only: HostServicesCapability =
        host_services_abi_is_contract_only();
    let host_api_executable: std::host::HostServicesCapability =
        std::host::host_services_api_is_executable();
    let host_api_blocked: std::host::HostServicesCapability =
        std::host::host_services_api_is_blocked();
    let host_api_known_unbound: HostServicesCapability =
        host_services_api_is_known_but_unbound();
    let host_api_needs_binding: HostServicesCapability =
        host_services_api_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_host_id);
    if (host_service_id != declared_host_id || host_service_id != runtime_host_id) {
        return 1;
    }
    if (host_status != declared_status || host_status != runtime_status) {
        return 1;
    }
    if (host_abi != declared_abi || host_abi != runtime_abi) {
        return 1;
    }
    if (!host_known || !host_metadata_available || host_available || !host_blocked || !host_known_unbound || declared_binding || !host_needs_binding || !host_needs_binding_canonical || !imported_needs_binding || !imported_needs_binding_canonical || !host_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (host_api_executable || !host_api_blocked || !host_api_known_unbound || !host_api_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::host and core::runtime imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/host.lani")),
        "path manifest should include std::host from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::host aggregate host-service contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::host should advertise the same unbound aggregate host-service contract as core::runtime",
    );
}

#[test]
fn std_path_contract_type_checks_byte_classifiers_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "path", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::path;

fn main() {
    let slash: PathByte = PATH_SEPARATOR_UNIX;
    let backslash: PathByte = PATH_SEPARATOR_WINDOWS;
    let dot: PathByte = path_extension_separator_byte();
    let colon: PathByte = std::path::path_drive_separator_byte();
    let nul: PathByte = std::path::path_nul_byte();
    let drive_letter: PathByte = 67;
    let letter: PathByte = 97;
    let digit: PathByte = 55;
    let one_byte_component: std::path::PathComponentLength = 1;
    let two_byte_component: PathComponentLength = 2;
    let three_byte_component: std::path::PathComponentLength = 3;
    let metadata_available: PathCapability =
        path_contract_metadata_is_available();
    let lexical_available: PathCapability =
        path_lexical_byte_helpers_are_available();
    let allocation_executable: PathCapability =
        path_allocation_api_is_executable();
    let allocation_blocked: PathCapability = path_allocation_api_is_blocked();
    let allocation_known_unbound: PathCapability =
        path_allocation_api_is_known_but_unbound();
    let allocation_needs_allocator: PathCapability =
        path_allocation_api_requires_allocator();
    let host_normalization_executable: PathCapability =
        path_host_normalization_is_executable();
    let host_normalization_blocked: PathCapability =
        path_host_normalization_is_blocked();
    let host_normalization_known_unbound: PathCapability =
        path_host_normalization_is_known_but_unbound();
    let host_normalization_needs_runtime: PathCapability =
        path_host_normalization_requires_runtime_binding();
    let slash_is_separator: PathCapability =
        path_byte_is_separator(slash);
    let backslash_is_separator: PathCapability =
        path_byte_is_separator(backslash);
    let dot_is_separator: PathCapability =
        path_byte_is_separator(dot);
    let dot_is_extension: PathCapability =
        std::path::path_byte_is_extension_separator(dot);
    let colon_is_drive_separator: PathCapability =
        path_byte_is_drive_separator(colon);
    let drive_letter_is_windows_drive_letter: PathCapability =
        std::path::path_byte_is_windows_drive_letter(drive_letter);
    let letter_is_windows_drive_letter: PathCapability =
        path_byte_is_windows_drive_letter(letter);
    let digit_is_windows_drive_letter: PathCapability =
        path_byte_is_windows_drive_letter(digit);
    let digit_is_ascii_digit: PathCapability =
        std::path::path_byte_is_ascii_digit(digit);
    let letter_is_ascii_digit: PathCapability =
        path_byte_is_ascii_digit(letter);
    let nul_is_nul: PathCapability =
        std::path::path_byte_is_nul(nul);
    let slash_is_component_boundary: PathCapability =
        path_byte_is_component_boundary(slash);
    let nul_is_component_boundary: PathCapability =
        path_byte_is_component_boundary(nul);
    let letter_is_component_boundary: PathCapability =
        path_byte_is_component_boundary(letter);
    let current_dir_component: PathCapability =
        std::path::path_component_is_current_dir(dot, one_byte_component);
    let current_dir_rejects_name: PathCapability =
        path_component_is_current_dir(letter, one_byte_component);
    let current_dir_rejects_longer_component: PathCapability =
        path_component_is_current_dir(dot, two_byte_component);
    let parent_dir_component: PathCapability =
        std::path::path_component_is_parent_dir(dot, dot, two_byte_component);
    let parent_dir_rejects_single_dot: PathCapability =
        path_component_is_parent_dir(dot, dot, one_byte_component);
    let parent_dir_rejects_named_component: PathCapability =
        std::path::path_component_is_parent_dir(dot, letter, two_byte_component);
    let special_current_dir_component: PathCapability =
        path_component_is_current_or_parent_dir(dot, letter, one_byte_component);
    let special_parent_dir_component: PathCapability =
        std::path::path_component_is_current_or_parent_dir(dot, dot, two_byte_component);
    let special_rejects_longer_component: PathCapability =
        path_component_is_current_or_parent_dir(dot, dot, three_byte_component);
    let root_separator_component: PathCapability =
        std::path::path_component_is_root_separator(slash, one_byte_component);
    let windows_root_separator_component: PathCapability =
        path_component_is_root_separator(backslash, one_byte_component);
    let root_separator_rejects_dot: PathCapability =
        path_component_is_root_separator(dot, one_byte_component);
    let root_separator_rejects_longer_component: PathCapability =
        std::path::path_component_is_root_separator(slash, two_byte_component);
    let windows_drive_prefix_component: PathCapability =
        path_component_is_windows_drive_prefix(drive_letter, colon, two_byte_component);
    let windows_drive_prefix_rejects_digit: PathCapability =
        std::path::path_component_is_windows_drive_prefix(digit, colon, two_byte_component);
    let windows_drive_prefix_rejects_separator: PathCapability =
        path_component_is_windows_drive_prefix(drive_letter, slash, two_byte_component);
    let windows_drive_prefix_rejects_longer_component: PathCapability =
        path_component_is_windows_drive_prefix(drive_letter, colon, three_byte_component);
    let zero_can_start_component: PathCapability =
        path_byte_can_start_relative_component(nul);
    let letter_can_start_component: PathCapability =
        path_byte_can_start_relative_component(letter);
    let slash_can_continue_component: PathCapability =
        path_byte_can_continue_relative_component(slash);
    let letter_can_continue_component: PathCapability =
        path_byte_can_continue_relative_component(letter);
    let slash_kind: PathSeparatorKind =
        path_separator_kind(slash);
    let backslash_kind: PathSeparatorKind = path_separator_kind(backslash);
    let dot_kind: PathSeparatorKind =
        path_separator_kind(dot);
    if (!metadata_available || !lexical_available) {
        return 1;
    }
    if (allocation_executable || !allocation_blocked || !allocation_known_unbound || !allocation_needs_allocator) {
        return 1;
    }
    if (host_normalization_executable || !host_normalization_blocked || !host_normalization_known_unbound || !host_normalization_needs_runtime) {
        return 1;
    }
    if (!slash_is_separator || !backslash_is_separator || dot_is_separator) {
        return 1;
    }
    if (!dot_is_extension || !colon_is_drive_separator) {
        return 1;
    }
    if (!drive_letter_is_windows_drive_letter || !letter_is_windows_drive_letter || digit_is_windows_drive_letter) {
        return 1;
    }
    if (!digit_is_ascii_digit || letter_is_ascii_digit) {
        return 1;
    }
    if (!nul_is_nul || !slash_is_component_boundary || !nul_is_component_boundary || letter_is_component_boundary) {
        return 1;
    }
    if (!current_dir_component || current_dir_rejects_name || current_dir_rejects_longer_component) {
        return 1;
    }
    if (!parent_dir_component || parent_dir_rejects_single_dot || parent_dir_rejects_named_component) {
        return 1;
    }
    if (!special_current_dir_component || !special_parent_dir_component || special_rejects_longer_component) {
        return 1;
    }
    if (!root_separator_component || !windows_root_separator_component || root_separator_rejects_dot || root_separator_rejects_longer_component) {
        return 1;
    }
    if (!windows_drive_prefix_component || windows_drive_prefix_rejects_digit || windows_drive_prefix_rejects_separator || windows_drive_prefix_rejects_longer_component) {
        return 1;
    }
    if (zero_can_start_component || !letter_can_start_component) {
        return 1;
    }
    if (slash_can_continue_component || !letter_can_continue_component) {
        return 1;
    }
    if (slash_kind != PATH_SEPARATOR_UNIX_KIND || backslash_kind != PATH_SEPARATOR_WINDOWS_KIND || dot_kind != PATH_SEPARATOR_NONE) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::path import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/path.lani")),
        "path manifest should include std::path from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);
    assert!(
        runtime_bound_api_diagnostic_info("std::path::path_byte_is_ascii_digit").is_none(),
        "std::path::path_byte_is_ascii_digit is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::path byte classifier contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::path byte classifier helpers should type check while allocation and host normalization remain blocked",
    );
}

#[test]
fn std_path_unix_hidden_component_helper_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_runtime", "path_unix_hidden", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::path;

fn main() {
    let dot: std::path::PathByte = std::path::PATH_EXTENSION_SEPARATOR;
    let letter: PathByte = 97;
    let slash: std::path::PathByte = std::path::PATH_SEPARATOR_UNIX;
    let one: PathComponentLength = 1;
    let two: std::path::PathComponentLength = 2;
    let three: PathComponentLength = 3;
    let dotfile: PathCapability =
        std::path::path_component_is_unix_hidden(dot, letter, two);
    let current_dir: std::path::PathCapability =
        path_component_is_unix_hidden(dot, letter, one);
    let parent_dir: PathCapability =
        std::path::path_component_is_unix_hidden(dot, dot, two);
    let dotted_name: std::path::PathCapability =
        path_component_is_unix_hidden(dot, dot, three);
    let ordinary_name: PathCapability =
        std::path::path_component_is_unix_hidden(letter, dot, two);
    let root_separator: std::path::PathCapability =
        path_component_is_unix_hidden(slash, dot, one);
    if (!dotfile || current_dir || parent_dir || !dotted_name || ordinary_name || root_separator) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::path import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/path.lani")),
        "path manifest should include std::path from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::path Unix hidden-component helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::path Unix hidden-component helper should type check through --stdlib-root");
}

#[test]
fn std_process_contract_type_checks_against_unbound_runtime_process_service() {
    common::type_check_source_pack_with_timeout(&[
        include_str!("../stdlib/core/runtime.lani"),
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import core::runtime;
import std::process;

fn main() {
    let process_service_id: std::process::ProcessServiceId =
        std::process::process_service_id();
    let declared_process_id: ProcessServiceId = PROCESS_SERVICE_ID;
    let runtime_process_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_PROCESS_ID;
    let unknown_runtime_service_id: core::runtime::RuntimeServiceId = 99;
    let process_known: ProcessCapability = process_service_is_known();
    let process_status: std::process::ProcessServiceStatus =
        std::process::process_service_status();
    let declared_status: ProcessServiceStatus = PROCESS_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_process_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(unknown_runtime_service_id);
    let process_abi: std::process::ProcessRuntimeAbiVersion =
        process_runtime_abi_version();
    let declared_abi: ProcessRuntimeAbiVersion = PROCESS_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_process_id);
    let process_available: std::process::ProcessCapability =
        std::process::process_is_available();
    let declared_binding: ProcessCapability = PROCESS_HAS_RUNTIME_BINDING;
    let process_needs_binding: std::process::ProcessCapability =
        std::process::process_requires_runtime_binding();
    let imported_needs_binding: ProcessCapability = process_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_process_id);
    if (process_service_id != runtime_process_id || declared_process_id != runtime_process_id) {
        return 1;
    }
    if (process_status != runtime_status || declared_status != runtime_status || process_status == unknown_status) {
        return 1;
    }
    if (process_abi != declared_abi || process_abi != runtime_abi) {
        return 1;
    }
    if (!process_known || process_available || declared_binding || !process_needs_binding || !imported_needs_binding || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    ])
    .expect("std::process should advertise the same unbound process service contract as core::runtime");
}

#[test]
fn std_process_contract_type_checks_against_unbound_runtime_process_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "process", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::process;

fn main() {
    let process_service_id: std::process::ProcessServiceId =
        std::process::process_service_id();
    let runtime_process_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_PROCESS_ID;
    let process_status: std::process::ProcessServiceStatus =
        std::process::process_service_status();
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_process_id);
    let process_abi: ProcessRuntimeAbiVersion = process_runtime_abi_version();
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_process_id);
    let process_needs_binding: ProcessCapability = process_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_binding(runtime_process_id);
    if (process_service_id != runtime_process_id || process_status != runtime_status) {
        return 1;
    }
    if (process_abi != runtime_abi || !process_needs_binding || !runtime_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::process and core::runtime imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/process.lani")),
        "path manifest should include std::process from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")),
        "path manifest should include core::runtime from the stdlib root"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::process runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::process should advertise the same unbound process service contract through --stdlib-root",
    );
}

#[test]
fn std_process_public_api_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "process_api", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::process;

fn main() {
    let process_available: std::process::ProcessCapability =
        std::process::process_is_available();
    let process_metadata_available: std::process::ProcessCapability =
        std::process::process_contract_metadata_is_available();
    let process_blocked: ProcessCapability = process_is_blocked();
    let process_known_unbound: std::process::ProcessCapability =
        std::process::process_is_known_but_unbound();
    let process_needs_binding: ProcessCapability = process_requires_runtime_binding();
    let process_contract_only: ProcessCapability = process_host_abi_is_contract_only();
    let args_executable: std::process::ProcessCapability =
        std::process::process_args_is_executable();
    let args_blocked: std::process::ProcessCapability =
        std::process::process_args_is_blocked();
    let args_known_unbound: ProcessCapability = process_args_is_known_but_unbound();
    let args_need_binding: ProcessCapability = process_args_requires_runtime_binding();
    let exit_executable: std::process::ProcessCapability =
        std::process::process_exit_is_executable();
    let exit_blocked: ProcessCapability = process_exit_is_blocked();
    let exit_known_unbound: std::process::ProcessCapability =
        std::process::process_exit_is_known_but_unbound();
    let exit_needs_binding: ProcessCapability =
        std::process::process_exit_requires_runtime_binding();
    let argc_executable: std::process::ProcessCapability =
        std::process::argc_is_executable();
    let argc_blocked: ProcessCapability = argc_is_blocked();
    let argc_known_unbound: std::process::ProcessCapability =
        std::process::argc_is_known_but_unbound();
    let argc_needs_binding: ProcessCapability = argc_requires_runtime_binding();
    let arg_len_executable: ProcessCapability = arg_len_is_executable();
    let arg_len_blocked: std::process::ProcessCapability =
        std::process::arg_len_is_blocked();
    let arg_len_known_unbound: ProcessCapability = arg_len_is_known_but_unbound();
    let arg_len_needs_binding: ProcessCapability = arg_len_requires_runtime_binding();
    let arg_read_executable: ProcessCapability = arg_read_is_executable();
    let arg_read_blocked: std::process::ProcessCapability =
        std::process::arg_read_is_blocked();
    let arg_read_known_unbound: std::process::ProcessCapability =
        std::process::arg_read_is_known_but_unbound();
    let arg_read_needs_binding: ProcessCapability = arg_read_requires_runtime_binding();
    let set_exit_code_executable: std::process::ProcessCapability =
        std::process::set_exit_code_is_executable();
    let set_exit_code_blocked: ProcessCapability = set_exit_code_is_blocked();
    let set_exit_code_known_unbound: ProcessCapability =
        set_exit_code_is_known_but_unbound();
    let set_exit_code_needs_binding: ProcessCapability =
        set_exit_code_requires_runtime_binding();
    let exit_call_executable: ProcessCapability = exit_is_executable();
    let exit_call_blocked: std::process::ProcessCapability =
        std::process::exit_is_blocked();
    let exit_call_known_unbound: ProcessCapability = exit_is_known_but_unbound();
    let exit_call_needs_binding: ProcessCapability = exit_requires_runtime_binding();
    if (process_available || !process_metadata_available || !process_blocked || !process_known_unbound || !process_needs_binding || !process_contract_only) {
        return 1;
    }
    if (!args_executable || args_blocked || args_known_unbound || args_need_binding) {
        return 1;
    }
    if (!exit_executable || exit_blocked || exit_known_unbound || exit_needs_binding) {
        return 1;
    }
    if (!argc_executable || !arg_len_executable || !arg_read_executable || set_exit_code_executable || !exit_call_executable) {
        return 1;
    }
    if (argc_blocked || arg_len_blocked || arg_read_blocked || !set_exit_code_blocked || exit_call_blocked) {
        return 1;
    }
    if (argc_known_unbound || arg_len_known_unbound || arg_read_known_unbound || !set_exit_code_known_unbound || exit_call_known_unbound) {
        return 1;
    }
    if (argc_needs_binding || arg_len_needs_binding || arg_read_needs_binding || !set_exit_code_needs_binding || exit_call_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::process import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/process.lani")),
        "path manifest should include std::process from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::process public API runtime gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::process public API gate helpers should type check through --stdlib-root");
}

#[test]
fn std_process_argument_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "process_argument_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::process;

fn main() {
    let unavailable: std::process::ProcessArgumentResult =
        std::process::PROCESS_ARGUMENT_UNAVAILABLE;
    let unavailable_from_fn: ProcessArgumentResult =
        process_argument_unavailable();
    let empty_count: std::process::ProcessArgumentResult = 0;
    let byte_count: ProcessArgumentResult = 12;
    let other_failure: std::process::ProcessArgumentResult = -2;
    let ptr: u32 = 0;
    let len: usize = 0;
    let argc_result: std::process::ProcessArgumentResult = std::process::argc();
    let arg_len_result: ProcessArgumentResult = arg_len(0);
    let arg_read_result: std::process::ProcessArgumentResult =
        std::process::arg_read(0, ptr, len);
    let empty_succeeded: ProcessCapability =
        std::process::process_argument_result_succeeded(empty_count);
    let byte_count_succeeded: std::process::ProcessCapability =
        process_argument_result_succeeded(byte_count);
    let unavailable_failed: std::process::ProcessCapability =
        std::process::process_argument_result_failed(unavailable);
    let other_failure_failed: ProcessCapability =
        process_argument_result_failed(other_failure);
    let unavailable_is_known: ProcessCapability =
        process_argument_result_is_unavailable(unavailable);
    let unavailable_is_fail_closed: std::process::ProcessCapability =
        std::process::process_argument_result_is_fail_closed(unavailable);
    let other_failure_is_unavailable: ProcessCapability =
        process_argument_result_is_unavailable(other_failure);
    let other_failure_is_fail_closed: std::process::ProcessCapability =
        std::process::process_argument_result_is_fail_closed(other_failure);
    let args_blocked: std::process::ProcessCapability =
        std::process::process_args_is_blocked();
    let args_known_unbound: ProcessCapability =
        process_args_is_known_but_unbound();
    if (unavailable != -1) {
        return 1;
    }
    if (unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!empty_succeeded || !byte_count_succeeded || !unavailable_failed || !other_failure_failed) {
        return 1;
    }
    if (!unavailable_is_known || unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (args_blocked || args_known_unbound) {
        return 1;
    }
    return argc_result + arg_len_result + arg_read_result - argc_result - arg_len_result - arg_read_result;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::process import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/process.lani")),
        "path manifest should include std::process from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::process argument-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::process argument-result helpers should type check while process args remain unbound",
    );
}

#[test]
fn std_process_exit_code_contract_type_checks_without_runtime_binding() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_runtime", "process_exit_code", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::process;

fn main() {
    let success: std::process::ExitCode = std::process::EXIT_SUCCESS;
    let failure: ExitCode = EXIT_FAILURE;
    let success_from_fn: std::process::ExitCode =
        std::process::exit_success_code();
    let failure_from_fn: ExitCode = exit_failure_code();
    let success_from_bool: ExitCode =
        std::process::exit_code_from_success(true);
    let failure_from_bool: std::process::ExitCode =
        exit_code_from_success(false);
    let success_ok: ProcessCapability =
        std::process::exit_code_is_success(success);
    let failure_ok: std::process::ProcessCapability =
        exit_code_is_failure(failure);
    let alternate_failure_ok: ProcessCapability =
        std::process::exit_code_is_failure(2);
    let process_available: std::process::ProcessCapability =
        std::process::process_is_available();
    let process_blocked: ProcessCapability = process_is_blocked();
    let exit_executable: ProcessCapability = exit_is_executable();
    let exit_needs_binding: std::process::ProcessCapability =
        std::process::exit_requires_runtime_binding();
    if (success != 0 || failure != 1) {
        return 1;
    }
    if (success_from_fn != success || failure_from_fn != failure) {
        return 1;
    }
    if (success_from_bool != success || failure_from_bool != failure) {
        return 1;
    }
    if (!success_ok || !failure_ok || !alternate_failure_ok) {
        return 1;
    }
    if (process_available || !process_blocked || !exit_executable || exit_needs_binding) {
        return 1;
    }
    return success;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::process import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/process.lani")),
        "path manifest should include std::process from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::process exit-code contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::process exit-code helpers should type check without binding process runtime APIs",
    );
}

#[test]
fn std_env_contract_type_checks_against_unbound_runtime_env_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "env", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::env;

fn main() {
    let env_service_id: std::env::EnvServiceId = std::env::env_service_id();
    let declared_env_id: EnvServiceId = ENV_SERVICE_ID;
    let runtime_env_id: core::runtime::RuntimeServiceId = core::runtime::SERVICE_ENV_ID;
    let env_known: EnvCapability = std::env::env_service_is_known();
    let env_metadata_available: EnvCapability =
        std::env::env_contract_metadata_is_available();
    let env_status: std::env::EnvServiceStatus = std::env::env_service_status();
    let declared_status: EnvServiceStatus = ENV_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_env_id);
    let env_abi: std::env::EnvRuntimeAbiVersion = env_runtime_abi_version();
    let declared_abi: EnvRuntimeAbiVersion = ENV_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_env_id);
    let env_available: std::env::EnvCapability = std::env::env_is_available();
    let env_blocked: EnvCapability = env_is_blocked();
    let env_known_unbound: std::env::EnvCapability =
        std::env::env_is_known_but_unbound();
    let declared_binding: EnvCapability = ENV_HAS_RUNTIME_BINDING;
    let env_needs_binding: std::env::EnvCapability =
        std::env::env_requires_runtime_binding();
    let imported_needs_binding: EnvCapability = env_requires_runtime_binding();
    let env_contract_only: EnvCapability = env_host_abi_is_contract_only();
    let env_vars_executable: std::env::EnvCapability =
        std::env::environment_variables_api_is_executable();
    let env_vars_blocked: EnvCapability = environment_variables_api_is_blocked();
    let env_vars_known_unbound: EnvCapability =
        environment_variables_api_is_known_but_unbound();
    let env_vars_needs_binding: EnvCapability =
        environment_variables_api_requires_runtime_binding();
    let var_len_executable: std::env::EnvCapability =
        std::env::var_len_is_executable();
    let var_len_blocked: EnvCapability = var_len_is_blocked();
    let var_len_known_unbound: EnvCapability = var_len_is_known_but_unbound();
    let var_len_needs_binding: EnvCapability = var_len_requires_runtime_binding();
    let var_read_executable: std::env::EnvCapability =
        std::env::var_read_is_executable();
    let var_read_blocked: std::env::EnvCapability =
        std::env::var_read_is_blocked();
    let var_read_known_unbound: std::env::EnvCapability =
        std::env::var_read_is_known_but_unbound();
    let var_read_needs_binding: EnvCapability = var_read_requires_runtime_binding();
    let var_count_executable: std::env::EnvCapability =
        std::env::var_count_is_executable();
    let var_count_blocked: EnvCapability = var_count_is_blocked();
    let var_count_known_unbound: EnvCapability = var_count_is_known_but_unbound();
    let var_count_needs_binding: EnvCapability = var_count_requires_runtime_binding();
    let var_key_len_executable: std::env::EnvCapability =
        std::env::var_key_len_is_executable();
    let var_key_len_blocked: std::env::EnvCapability =
        std::env::var_key_len_is_blocked();
    let var_key_len_known_unbound: std::env::EnvCapability =
        std::env::var_key_len_is_known_but_unbound();
    let var_key_len_needs_binding: EnvCapability = var_key_len_requires_runtime_binding();
    let var_key_read_executable: std::env::EnvCapability =
        std::env::var_key_read_is_executable();
    let var_key_read_blocked: EnvCapability = var_key_read_is_blocked();
    let var_key_read_known_unbound: EnvCapability =
        var_key_read_is_known_but_unbound();
    let var_key_read_needs_binding: EnvCapability =
        var_key_read_requires_runtime_binding();
    let current_dir_executable: std::env::EnvCapability =
        std::env::current_dir_api_is_executable();
    let current_dir_blocked: EnvCapability = current_dir_api_is_blocked();
    let current_dir_known_unbound: EnvCapability =
        current_dir_api_is_known_but_unbound();
    let current_dir_needs_binding: EnvCapability =
        current_dir_api_requires_runtime_binding();
    let current_dir_len_executable: std::env::EnvCapability =
        std::env::current_dir_len_is_executable();
    let current_dir_len_blocked: std::env::EnvCapability =
        std::env::current_dir_len_is_blocked();
    let current_dir_len_known_unbound: std::env::EnvCapability =
        std::env::current_dir_len_is_known_but_unbound();
    let current_dir_len_needs_binding: EnvCapability =
        current_dir_len_requires_runtime_binding();
    let current_dir_read_executable: std::env::EnvCapability =
        std::env::current_dir_read_is_executable();
    let current_dir_read_blocked: EnvCapability = current_dir_read_is_blocked();
    let current_dir_read_known_unbound: EnvCapability =
        current_dir_read_is_known_but_unbound();
    let current_dir_read_needs_binding: EnvCapability =
        current_dir_read_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_env_id);
    if (env_service_id != declared_env_id || env_service_id != runtime_env_id) {
        return 1;
    }
    if (env_status != declared_status || env_status != runtime_status) {
        return 1;
    }
    if (env_abi != declared_abi || env_abi != runtime_abi) {
        return 1;
    }
    if (!env_known || !env_metadata_available || env_available || !env_blocked || !env_known_unbound || declared_binding || !env_needs_binding || !imported_needs_binding || !env_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (!env_vars_executable || !var_len_executable || !var_read_executable || !var_count_executable || !var_key_len_executable || !var_key_read_executable || current_dir_executable || current_dir_len_executable || !current_dir_read_executable) {
        return 1;
    }
    if (env_vars_blocked || env_vars_known_unbound || var_len_blocked || var_len_known_unbound || var_read_blocked || var_read_known_unbound || var_count_blocked || var_count_known_unbound || var_key_len_blocked || var_key_len_known_unbound || var_key_read_blocked || var_key_read_known_unbound || !current_dir_blocked || !current_dir_known_unbound || !current_dir_len_blocked || !current_dir_len_known_unbound || current_dir_read_blocked || current_dir_read_known_unbound) {
        return 1;
    }
    if (env_vars_needs_binding || var_len_needs_binding || var_read_needs_binding || var_count_needs_binding || var_key_len_needs_binding || var_key_read_needs_binding || !current_dir_needs_binding || !current_dir_len_needs_binding || current_dir_read_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::env and core::runtime imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/env.lani"))
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani"))
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::env runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::env should advertise the same unbound env service contract as core::runtime");
}

#[test]
fn std_env_public_read_calls_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "env_read_calls", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::env;

fn main() {
    let key_count: i32 = std::env::var_count();
    let key_len: i32 = std::env::var_key_len(0);
    let key_read: i32 = std::env::var_key_read(0, 0, 0);
    let value_len: i32 = std::env::var_len(0, 0);
    let value_read: i32 = std::env::var_read(0, 0, 0, 0);
    let current_len: i32 = std::env::current_dir_len();
    let current_read: i32 = std::env::current_dir_read(0, 0);
    let env_vars_blocked: std::env::EnvCapability =
        std::env::environment_variables_api_is_blocked();
    let current_dir_blocked: std::env::EnvCapability =
        std::env::current_dir_api_is_blocked();
    if (!env_vars_blocked || !current_dir_blocked) {
        return 1;
    }
    return key_count + key_len + key_read + value_len + value_read + current_len + current_read - key_count - key_len - key_read - value_len - value_read - current_len - current_read;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::env import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/env.lani")),
        "path manifest should include std::env from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::env public read calls",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::env read calls should type check through --stdlib-root while unbound");
}

#[test]
fn std_env_read_result_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_runtime", "env_read_result", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import std::env;

fn main() {
    let unavailable: std::env::EnvReadResult = std::env::ENV_READ_UNAVAILABLE;
    let unavailable_from_fn: EnvReadResult = env_read_unavailable();
    let empty_result: std::env::EnvReadResult = 0;
    let byte_count: EnvReadResult = 12;
    let other_failure: std::env::EnvReadResult = -2;
    let key_count: std::env::EnvReadResult = std::env::var_count();
    let value_len: EnvReadResult = var_len(0, 0);
    let current_len: std::env::EnvReadResult = std::env::current_dir_len();
    let empty_succeeded: EnvCapability =
        std::env::env_read_result_succeeded(empty_result);
    let byte_count_succeeded: std::env::EnvCapability =
        env_read_result_succeeded(byte_count);
    let unavailable_failed: EnvCapability =
        std::env::env_read_result_failed(unavailable);
    let unavailable_is_known: std::env::EnvCapability =
        std::env::env_read_result_is_unavailable(unavailable);
    let unavailable_is_fail_closed: EnvCapability =
        env_read_result_is_fail_closed(unavailable);
    let env_var_fail_closed: std::env::EnvCapability =
        std::env::environment_variable_read_result_is_fail_closed(unavailable);
    let current_dir_fail_closed: EnvCapability =
        current_dir_read_result_is_fail_closed(unavailable);
    let other_failure_is_unavailable: std::env::EnvCapability =
        std::env::env_read_result_is_unavailable(other_failure);
    let other_failure_is_fail_closed: EnvCapability =
        env_read_result_is_fail_closed(other_failure);
    let env_blocked: std::env::EnvCapability = std::env::env_is_blocked();
    let env_known_unbound: EnvCapability = env_is_known_but_unbound();
    if (unavailable != -1) {
        return 1;
    }
    if (unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!empty_succeeded || !byte_count_succeeded || !unavailable_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || env_var_fail_closed || current_dir_fail_closed) {
        return 1;
    }
    if (other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!env_blocked || !env_known_unbound) {
        return 1;
    }
    return key_count + value_len + current_len - key_count - value_len - current_len;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::env import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/env.lani")),
        "path manifest should include std::env from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::env read-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::env read-result helpers should type check while the env service remains unbound");
}

#[test]
fn std_random_contract_type_checks_against_unbound_secure_rng_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "random", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::random;

fn main() {
    let random_service_id: std::random::RandomServiceId =
        std::random::random_service_id();
    let declared_random_id: RandomServiceId = RANDOM_SERVICE_ID;
    let runtime_random_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_SECURE_RNG_ID;
    let random_known: RandomCapability = std::random::random_service_is_known();
    let random_metadata_available: std::random::RandomCapability =
        std::random::random_contract_metadata_is_available();
    let random_status: std::random::RandomServiceStatus =
        std::random::random_service_status();
    let declared_status: RandomServiceStatus = RANDOM_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_random_id);
    let random_abi: std::random::RandomRuntimeAbiVersion =
        random_runtime_abi_version();
    let declared_abi: RandomRuntimeAbiVersion = RANDOM_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_random_id);
    let random_available: std::random::RandomCapability =
        std::random::random_is_available();
    let random_blocked: RandomCapability = random_is_blocked();
    let random_known_unbound: std::random::RandomCapability =
        std::random::random_is_known_but_unbound();
    let declared_binding: RandomCapability = RANDOM_HAS_RUNTIME_BINDING;
    let random_needs_binding: std::random::RandomCapability =
        std::random::random_requires_runtime_binding();
    let imported_needs_binding: RandomCapability =
        random_requires_runtime_binding();
    let random_contract_only: RandomCapability =
        random_host_abi_is_contract_only();
    let secure_rng_executable: std::random::RandomCapability =
        std::random::secure_rng_api_is_executable();
    let secure_rng_blocked: std::random::RandomCapability =
        std::random::secure_rng_api_is_blocked();
    let secure_rng_known_unbound: RandomCapability =
        secure_rng_api_is_known_but_unbound();
    let secure_rng_needs_binding: RandomCapability =
        secure_rng_api_requires_runtime_binding();
    let fill_bytes_executable: std::random::RandomCapability =
        std::random::fill_secure_bytes_is_executable();
    let fill_bytes_blocked: RandomCapability =
        fill_secure_bytes_is_blocked();
    let fill_bytes_known_unbound: std::random::RandomCapability =
        std::random::fill_secure_bytes_is_known_but_unbound();
    let fill_bytes_needs_binding: std::random::RandomCapability =
        std::random::fill_secure_bytes_requires_runtime_binding();
    let secure_u32_executable: RandomCapability =
        secure_u32_is_executable();
    let secure_u32_blocked: std::random::RandomCapability =
        std::random::secure_u32_is_blocked();
    let secure_u32_known_unbound: RandomCapability =
        secure_u32_is_known_but_unbound();
    let secure_u32_needs_binding: RandomCapability =
        secure_u32_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_random_id);
    let fill_status: i32 = std::random::fill_secure_bytes(0, 0);
    let random_value: u32 = std::random::secure_u32();
    if (random_service_id != declared_random_id || random_service_id != runtime_random_id) {
        return 1;
    }
    if (random_status != declared_status || random_status != runtime_status) {
        return 1;
    }
    if (random_abi != declared_abi || random_abi != runtime_abi) {
        return 1;
    }
    if (!random_known || !random_metadata_available || random_available || !random_blocked || !random_known_unbound || declared_binding || !random_needs_binding || !imported_needs_binding || !random_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (secure_rng_executable || !secure_rng_blocked || !secure_rng_known_unbound || !secure_rng_needs_binding) {
        return 1;
    }
    if (fill_bytes_executable || !secure_u32_executable) {
        return 1;
    }
    if (!fill_bytes_blocked || secure_u32_blocked) {
        return 1;
    }
    if (!fill_bytes_known_unbound || secure_u32_known_unbound) {
        return 1;
    }
    if (!fill_bytes_needs_binding || secure_u32_needs_binding) {
        return 1;
    }
    return fill_status - fill_status;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::random and core::runtime imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/random.lani")),
        "path manifest should include std::random from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::random secure RNG contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::random should advertise the same unbound secure RNG service contract as core::runtime",
    );
}

#[test]
fn std_random_operation_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "random_operation_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::random;

fn main() {
    let ok: std::random::RandomOperationResult =
        std::random::RANDOM_OPERATION_OK;
    let unavailable: RandomOperationResult = RANDOM_OPERATION_UNAVAILABLE;
    let ok_from_fn: std::random::RandomOperationResult =
        std::random::random_operation_ok();
    let unavailable_from_fn: RandomOperationResult =
        random_operation_unavailable();
    let byte_count: std::random::RandomOperationResult = 16;
    let other_failure: RandomOperationResult = -2;
    let fill_result: std::random::RandomOperationResult =
        std::random::fill_secure_bytes(0, 0);
    let ok_succeeded: RandomCapability =
        std::random::random_operation_succeeded(ok);
    let byte_count_succeeded: std::random::RandomCapability =
        random_operation_succeeded(byte_count);
    let unavailable_failed: RandomCapability =
        std::random::random_operation_failed(unavailable);
    let unavailable_is_known: std::random::RandomCapability =
        std::random::random_operation_is_unavailable(unavailable);
    let unavailable_is_fail_closed: RandomCapability =
        random_operation_is_fail_closed(unavailable);
    let other_failure_is_unavailable: std::random::RandomCapability =
        std::random::random_operation_is_unavailable(other_failure);
    let other_failure_is_fail_closed: RandomCapability =
        random_operation_is_fail_closed(other_failure);
    let random_blocked: std::random::RandomCapability =
        std::random::random_is_blocked();
    let random_known_unbound: RandomCapability =
        random_is_known_but_unbound();
    if (ok != 0 || unavailable != -1) {
        return 1;
    }
    if (ok_from_fn != ok || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!ok_succeeded || !byte_count_succeeded || !unavailable_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!random_blocked || !random_known_unbound) {
        return 1;
    }
    return ok + fill_result - fill_result;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::random import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/random.lani")),
        "path manifest should include std::random from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::random operation-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::random operation-result helpers should type check while secure RNG remains unbound",
    );
}

#[test]
fn std_gpu_contract_type_checks_against_unbound_runtime_gpu_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "gpu", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::gpu;

fn main() {
    let gpu_service_id: std::gpu::GpuServiceId = std::gpu::gpu_service_id();
    let declared_gpu_id: GpuServiceId = GPU_SERVICE_ID;
    let runtime_gpu_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_GPU_ID;
    let gpu_known: GpuCapability = std::gpu::gpu_service_is_known();
    let gpu_status: std::gpu::GpuServiceStatus = std::gpu::gpu_service_status();
    let declared_status: GpuServiceStatus = GPU_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_gpu_id);
    let gpu_abi: std::gpu::GpuRuntimeAbiVersion = gpu_runtime_abi_version();
    let declared_abi: GpuRuntimeAbiVersion = GPU_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_gpu_id);
    let gpu_available: std::gpu::GpuCapability = std::gpu::gpu_is_available();
    let gpu_metadata_available: std::gpu::GpuCapability =
        std::gpu::gpu_contract_metadata_is_available();
    let gpu_blocked: std::gpu::GpuCapability = std::gpu::gpu_is_blocked();
    let gpu_known_unbound: GpuCapability = std::gpu::gpu_is_known_but_unbound();
    let declared_binding: GpuCapability = GPU_HAS_RUNTIME_BINDING;
    let gpu_needs_binding: std::gpu::GpuCapability =
        std::gpu::gpu_requires_runtime_binding();
    let imported_needs_binding: GpuCapability =
        gpu_requires_runtime_binding();
    let gpu_contract_only: GpuCapability = gpu_host_abi_is_contract_only();
    let buffer_executable: std::gpu::GpuCapability =
        std::gpu::gpu_buffer_api_is_executable();
    let buffer_blocked: std::gpu::GpuCapability =
        std::gpu::gpu_buffer_api_is_blocked();
    let buffer_known_unbound: GpuCapability =
        gpu_buffer_api_is_known_but_unbound();
    let buffer_needs_binding: GpuCapability =
        gpu_buffer_api_requires_runtime_binding();
    let buffer_alloc_executable: std::gpu::GpuCapability =
        std::gpu::buffer_alloc_is_executable();
    let buffer_alloc_blocked: GpuCapability = buffer_alloc_is_blocked();
    let buffer_alloc_known_unbound: GpuCapability =
        std::gpu::buffer_alloc_is_known_but_unbound();
    let buffer_alloc_needs_binding: GpuCapability =
        buffer_alloc_requires_runtime_binding();
    let buffer_free_executable: std::gpu::GpuCapability =
        std::gpu::buffer_free_is_executable();
    let buffer_free_blocked: GpuCapability = buffer_free_is_blocked();
    let buffer_free_known_unbound: GpuCapability =
        buffer_free_is_known_but_unbound();
    let buffer_free_needs_binding: GpuCapability =
        buffer_free_requires_runtime_binding();
    let buffer_write_executable: std::gpu::GpuCapability =
        std::gpu::buffer_write_is_executable();
    let buffer_write_blocked: GpuCapability = buffer_write_is_blocked();
    let buffer_write_known_unbound: std::gpu::GpuCapability =
        std::gpu::buffer_write_is_known_but_unbound();
    let buffer_write_needs_binding: GpuCapability =
        buffer_write_requires_runtime_binding();
    let buffer_read_executable: std::gpu::GpuCapability =
        std::gpu::buffer_read_is_executable();
    let buffer_read_blocked: GpuCapability = buffer_read_is_blocked();
    let buffer_read_known_unbound: GpuCapability =
        buffer_read_is_known_but_unbound();
    let buffer_read_needs_binding: GpuCapability =
        buffer_read_requires_runtime_binding();
    let dispatch_executable: std::gpu::GpuCapability =
        std::gpu::gpu_dispatch_api_is_executable();
    let dispatch_blocked: GpuCapability =
        gpu_dispatch_api_is_blocked();
    let dispatch_known_unbound: std::gpu::GpuCapability =
        std::gpu::gpu_dispatch_api_is_known_but_unbound();
    let dispatch_needs_binding: GpuCapability =
        gpu_dispatch_api_requires_runtime_binding();
    let dispatch_1d_executable: std::gpu::GpuCapability =
        std::gpu::dispatch_1d_is_executable();
    let dispatch_1d_blocked: GpuCapability = dispatch_1d_is_blocked();
    let dispatch_1d_known_unbound: GpuCapability =
        dispatch_1d_is_known_but_unbound();
    let dispatch_1d_needs_binding: GpuCapability =
        dispatch_1d_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_gpu_id);
    let handle: u32 = std::gpu::buffer_alloc(16);
    let write_status: i32 = std::gpu::buffer_write(handle, 0, 16);
    let read_status: i32 = std::gpu::buffer_read(handle, 0, 16);
    let dispatch_status: i32 = std::gpu::dispatch_1d(0, 1);
    let free_status: i32 = std::gpu::buffer_free(handle);
    if (gpu_service_id != declared_gpu_id || gpu_service_id != runtime_gpu_id) {
        return 1;
    }
    if (gpu_status != declared_status || gpu_status != runtime_status) {
        return 1;
    }
    if (gpu_abi != declared_abi || gpu_abi != runtime_abi) {
        return 1;
    }
    if (!gpu_known || !gpu_metadata_available || gpu_available || !gpu_blocked || !gpu_known_unbound || declared_binding || !gpu_needs_binding || !imported_needs_binding || !gpu_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (buffer_executable || buffer_alloc_executable || buffer_free_executable || buffer_write_executable || buffer_read_executable || dispatch_executable || dispatch_1d_executable) {
        return 1;
    }
    if (!buffer_blocked || !buffer_alloc_blocked || !buffer_free_blocked || !buffer_write_blocked || !buffer_read_blocked || !dispatch_blocked || !dispatch_1d_blocked) {
        return 1;
    }
    if (!buffer_known_unbound || !buffer_alloc_known_unbound || !buffer_free_known_unbound || !buffer_write_known_unbound || !buffer_read_known_unbound || !dispatch_known_unbound || !dispatch_1d_known_unbound) {
        return 1;
    }
    if (!buffer_needs_binding || !buffer_alloc_needs_binding || !buffer_free_needs_binding || !buffer_write_needs_binding || !buffer_read_needs_binding || !dispatch_needs_binding || !dispatch_1d_needs_binding) {
        return 1;
    }
    return write_status + read_status + dispatch_status + free_status - write_status - read_status - dispatch_status - free_status;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::gpu and core::runtime imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/gpu.lani")),
        "path manifest should include std::gpu from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::gpu runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::gpu should advertise the same unbound GPU service contract as core::runtime");
}

#[test]
fn std_gpu_operation_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "gpu_operation_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::gpu;

fn main() {
    let ok: std::gpu::GpuOperationResult = std::gpu::GPU_OPERATION_OK;
    let unavailable: GpuOperationResult = GPU_OPERATION_UNAVAILABLE;
    let ok_from_fn: std::gpu::GpuOperationResult =
        std::gpu::gpu_operation_ok();
    let unavailable_from_fn: GpuOperationResult =
        gpu_operation_unavailable();
    let byte_count: std::gpu::GpuOperationResult = 16;
    let other_failure: GpuOperationResult = -2;
    let ptr: u32 = 0;
    let byte_len: usize = 16;
    let kernel_id: u32 = 0;
    let workgroup_count: u32 = 1;
    let handle: u32 = std::gpu::buffer_alloc(byte_len);
    let write_result: std::gpu::GpuOperationResult =
        std::gpu::buffer_write(handle, ptr, byte_len);
    let read_result: GpuOperationResult = buffer_read(handle, ptr, byte_len);
    let dispatch_result: std::gpu::GpuOperationResult =
        std::gpu::dispatch_1d(kernel_id, workgroup_count);
    let free_result: GpuOperationResult = buffer_free(handle);
    let ok_succeeded: std::gpu::GpuCapability =
        std::gpu::gpu_operation_succeeded(ok);
    let byte_count_succeeded: GpuCapability =
        gpu_operation_succeeded(byte_count);
    let unavailable_failed: std::gpu::GpuCapability =
        std::gpu::gpu_operation_failed(unavailable);
    let unavailable_is_known: GpuCapability =
        gpu_operation_is_unavailable(unavailable);
    let unavailable_is_fail_closed: std::gpu::GpuCapability =
        std::gpu::gpu_operation_is_fail_closed(unavailable);
    let other_failure_is_unavailable: GpuCapability =
        gpu_operation_is_unavailable(other_failure);
    let other_failure_is_fail_closed: std::gpu::GpuCapability =
        std::gpu::gpu_operation_is_fail_closed(other_failure);
    let gpu_blocked: std::gpu::GpuCapability = std::gpu::gpu_is_blocked();
    let gpu_known_unbound: GpuCapability = gpu_is_known_but_unbound();
    if (ok != 0 || unavailable != -1) {
        return 1;
    }
    if (ok_from_fn != ok || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!ok_succeeded || !byte_count_succeeded || !unavailable_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!gpu_blocked || !gpu_known_unbound) {
        return 1;
    }
    return ok + write_result + read_result + dispatch_result + free_result - write_result - read_result - dispatch_result - free_result;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::gpu import");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/gpu.lani")),
        "path manifest should include std::gpu from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::gpu operation-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::gpu operation-result helpers should type check while GPU APIs remain unbound");
}

#[test]
fn std_thread_contract_type_checks_against_unbound_runtime_threads_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "thread", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import std::thread;

fn main() {
    let thread_service_id: std::thread::ThreadServiceId =
        std::thread::thread_service_id();
    let declared_thread_id: ThreadServiceId = THREAD_SERVICE_ID;
    let runtime_thread_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_THREADS_ID;
    let thread_known: ThreadCapability = std::thread::thread_service_is_known();
    let thread_metadata_available: ThreadCapability =
        std::thread::thread_contract_metadata_is_available();
    let thread_status: std::thread::ThreadServiceStatus =
        std::thread::thread_service_status();
    let declared_status: ThreadServiceStatus = THREAD_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_thread_id);
    let thread_abi: std::thread::ThreadRuntimeAbiVersion =
        thread_runtime_abi_version();
    let declared_abi: ThreadRuntimeAbiVersion = THREAD_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_thread_id);
    let thread_available: std::thread::ThreadCapability =
        std::thread::thread_is_available();
    let thread_blocked: std::thread::ThreadCapability =
        std::thread::thread_is_blocked();
    let thread_known_unbound: std::thread::ThreadCapability =
        std::thread::thread_is_known_but_unbound();
    let declared_binding: ThreadCapability = THREAD_HAS_RUNTIME_BINDING;
    let thread_needs_binding: std::thread::ThreadCapability =
        std::thread::thread_requires_runtime_binding();
    let imported_needs_binding: ThreadCapability =
        thread_requires_runtime_binding();
    let thread_contract_only: ThreadCapability = thread_host_abi_is_contract_only();
    let spawn_executable: std::thread::ThreadCapability =
        std::thread::thread_spawn_is_executable();
    let spawn_blocked: std::thread::ThreadCapability =
        std::thread::thread_spawn_is_blocked();
    let spawn_known_unbound: ThreadCapability =
        thread_spawn_is_known_but_unbound();
    let spawn_needs_binding: ThreadCapability =
        thread_spawn_requires_runtime_binding();
    let join_executable: std::thread::ThreadCapability =
        std::thread::thread_join_is_executable();
    let join_blocked: ThreadCapability =
        thread_join_is_blocked();
    let join_known_unbound: std::thread::ThreadCapability =
        std::thread::thread_join_is_known_but_unbound();
    let join_needs_binding: ThreadCapability =
        thread_join_requires_runtime_binding();
    let yield_executable: std::thread::ThreadCapability =
        std::thread::thread_yield_is_executable();
    let yield_blocked: std::thread::ThreadCapability =
        std::thread::thread_yield_is_blocked();
    let yield_known_unbound: ThreadCapability =
        thread_yield_is_known_but_unbound();
    let yield_needs_binding: ThreadCapability =
        thread_yield_requires_runtime_binding();
    let current_id_executable: std::thread::ThreadCapability =
        std::thread::thread_current_id_is_executable();
    let current_id_blocked: ThreadCapability =
        thread_current_id_is_blocked();
    let current_id_known_unbound: std::thread::ThreadCapability =
        std::thread::thread_current_id_is_known_but_unbound();
    let current_id_needs_binding: ThreadCapability =
        thread_current_id_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_thread_id);
    let handle: i32 = std::thread::spawn(0, 0);
    let current: i32 = std::thread::current_id();
    let yielded: i32 = std::thread::yield_now();
    let joined: i32 = std::thread::join(handle);
    if (thread_service_id != declared_thread_id || thread_service_id != runtime_thread_id) {
        return 1;
    }
    if (thread_status != declared_status || thread_status != runtime_status) {
        return 1;
    }
    if (thread_abi != declared_abi || thread_abi != runtime_abi) {
        return 1;
    }
    if (!thread_known || !thread_metadata_available || thread_available || !thread_blocked || !thread_known_unbound || declared_binding || !thread_needs_binding || !imported_needs_binding || !thread_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (spawn_executable || join_executable || yield_executable || current_id_executable) {
        return 1;
    }
    if (!spawn_blocked || !join_blocked || !yield_blocked || !current_id_blocked) {
        return 1;
    }
    if (!spawn_known_unbound || !join_known_unbound || !yield_known_unbound || !current_id_known_unbound) {
        return 1;
    }
    if (!spawn_needs_binding || !join_needs_binding || !yield_needs_binding || !current_id_needs_binding) {
        return 1;
    }
    return handle + current + yielded + joined - handle - current - yielded - joined;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::thread and core::runtime imports");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("std/thread.lani")),
        "path manifest should include std::thread from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::thread runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "std::thread should advertise the same unbound thread service contract as core::runtime",
    );
}

#[test]
fn std_thread_operation_result_contract_type_checks_fail_closed_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "thread_operation_result",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import std::thread;

fn main() {
    let ok: std::thread::ThreadOperationResult = std::thread::THREAD_OPERATION_OK;
    let unavailable: ThreadOperationResult = THREAD_OPERATION_UNAVAILABLE;
    let ok_from_fn: std::thread::ThreadOperationResult =
        std::thread::thread_operation_ok();
    let unavailable_from_fn: ThreadOperationResult =
        thread_operation_unavailable();
    let other_failure: std::thread::ThreadOperationResult = -2;
    let handle: std::thread::ThreadOperationResult = std::thread::spawn(0, 0);
    let current: ThreadOperationResult = std::thread::current_id();
    let yielded: std::thread::ThreadOperationResult = yield_now();
    let joined: ThreadOperationResult = std::thread::join(handle);
    let ok_succeeded: ThreadCapability =
        std::thread::thread_operation_succeeded(ok);
    let handle_succeeded: std::thread::ThreadCapability =
        thread_operation_succeeded(handle);
    let unavailable_failed: std::thread::ThreadCapability =
        std::thread::thread_operation_failed(unavailable);
    let other_failure_failed: ThreadCapability =
        thread_operation_failed(other_failure);
    let unavailable_is_known: ThreadCapability =
        std::thread::thread_operation_is_unavailable(unavailable);
    let unavailable_is_fail_closed: std::thread::ThreadCapability =
        std::thread::thread_operation_is_fail_closed(unavailable);
    let other_failure_is_unavailable: ThreadCapability =
        thread_operation_is_unavailable(other_failure);
    let other_failure_is_fail_closed: std::thread::ThreadCapability =
        std::thread::thread_operation_is_fail_closed(other_failure);
    let thread_blocked: ThreadCapability = std::thread::thread_is_blocked();
    let thread_known_unbound: std::thread::ThreadCapability =
        std::thread::thread_is_known_but_unbound();
    if (ok != 0 || unavailable != -1) {
        return 1;
    }
    if (ok_from_fn != ok || unavailable_from_fn != unavailable) {
        return 1;
    }
    if (!ok_succeeded || !handle_succeeded || !unavailable_failed || !other_failure_failed) {
        return 1;
    }
    if (!unavailable_is_known || !unavailable_is_fail_closed || other_failure_is_unavailable || other_failure_is_fail_closed) {
        return 1;
    }
    if (!thread_blocked || !thread_known_unbound) {
        return 1;
    }
    return ok + handle + current + yielded + joined - handle - current - yielded - joined;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load std::thread import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("std/thread.lani")
        }),
        "path manifest should include std::thread from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root std::thread operation-result contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("std::thread operation-result helpers should type check while threads remain unbound");
}

#[test]
fn test_harness_contract_type_checks_against_unbound_runtime_service_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "test_harness", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;
import test::harness;

fn main() {
    let harness_service_id: test::harness::TestHarnessServiceId =
        test::harness::test_harness_service_id();
    let declared_harness_id: TestHarnessServiceId = TEST_HARNESS_SERVICE_ID;
    let runtime_harness_id: core::runtime::RuntimeServiceId =
        core::runtime::SERVICE_TEST_HARNESS_ID;
    let harness_known: TestHarnessCapability =
        test::harness::test_harness_service_is_known();
    let harness_metadata_available: test::harness::TestHarnessCapability =
        test::harness::test_harness_contract_metadata_is_available();
    let harness_status: TestHarnessServiceStatus =
        test::harness::test_harness_service_status();
    let declared_status: test::harness::TestHarnessServiceStatus =
        TEST_HARNESS_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_harness_id);
    let harness_abi: test::harness::TestHarnessRuntimeAbiVersion =
        test_harness_runtime_abi_version();
    let declared_abi: TestHarnessRuntimeAbiVersion =
        TEST_HARNESS_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_harness_id);
    let harness_available: test::harness::TestHarnessCapability =
        test::harness::test_harness_is_available();
    let harness_blocked: TestHarnessCapability = test_harness_is_blocked();
    let declared_binding: TestHarnessCapability =
        TEST_HARNESS_HAS_RUNTIME_BINDING;
    let harness_needs_binding: test::harness::TestHarnessCapability =
        test::harness::test_harness_requires_runtime_binding();
    let imported_needs_binding: TestHarnessCapability =
        test_harness_requires_runtime_binding();
    let harness_contract_only: TestHarnessCapability =
        test_harness_abi_is_contract_only();
    let registration_executable: test::harness::TestHarnessCapability =
        test::harness::test_registration_is_executable();
    let registration_blocked: TestHarnessCapability =
        test_registration_is_blocked();
    let registration_needs_binding: TestHarnessCapability =
        test_registration_requires_runtime_binding();
    let discovery_executable: test::harness::TestHarnessCapability =
        test::harness::test_discovery_is_executable();
    let discovery_blocked: TestHarnessCapability =
        test_discovery_is_blocked();
    let discovery_needs_binding: TestHarnessCapability =
        test_discovery_requires_runtime_binding();
    let execution_executable: test::harness::TestHarnessCapability =
        test::harness::test_execution_is_executable();
    let execution_blocked: TestHarnessCapability =
        test_execution_is_blocked();
    let execution_needs_binding: TestHarnessCapability =
        test_execution_requires_runtime_binding();
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(runtime_harness_id);
    if (harness_service_id != declared_harness_id || harness_service_id != runtime_harness_id) {
        return 1;
    }
    if (harness_status != declared_status || harness_status != runtime_status) {
        return 1;
    }
    if (harness_abi != declared_abi || harness_abi != runtime_abi) {
        return 1;
    }
    if (!harness_known || !harness_metadata_available || harness_available || !harness_blocked || declared_binding || !harness_needs_binding || !imported_needs_binding || !harness_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (registration_executable || discovery_executable || execution_executable) {
        return 1;
    }
    if (!registration_blocked || !discovery_blocked || !execution_blocked) {
        return 1;
    }
    if (!registration_needs_binding || !discovery_needs_binding || !execution_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load test::harness and core::runtime imports");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("test/harness.lani")
        }),
        "path manifest should include test::harness from the stdlib root"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani")),
        "path manifest should include core::runtime from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root test::harness runtime contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect(
        "test::harness should advertise the unbound test harness service contract through --stdlib-root",
    );
}

#[test]
fn test_harness_known_unbound_gates_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "test_harness_known_unbound",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import test::harness;

fn main() {
    let harness_known_unbound: test::harness::TestHarnessCapability =
        test::harness::test_harness_is_known_but_unbound();
    let registration_known_unbound: TestHarnessCapability =
        test_registration_is_known_but_unbound();
    let discovery_known_unbound: test::harness::TestHarnessCapability =
        test::harness::test_discovery_is_known_but_unbound();
    let execution_known_unbound: TestHarnessCapability =
        test_execution_is_known_but_unbound();
    let execution_executable: test::harness::TestHarnessCapability =
        test::harness::test_execution_is_executable();
    if (!harness_known_unbound || !registration_known_unbound || !discovery_known_unbound || !execution_known_unbound) {
        return 1;
    }
    if (execution_executable) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load test::harness import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("test/harness.lani")
        }),
        "path manifest should include test::harness from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root test::harness known-unbound gates",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("test::harness known-unbound gate helpers should type check through --stdlib-root");
}

#[test]
fn test_harness_status_contract_type_checks_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "test_harness_status",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import test::harness;

fn main() {
    let passed: test::harness::TestHarnessStatus =
        test::harness::TEST_STATUS_PASSED;
    let failed: TestHarnessStatus = test::harness::test_status_failed();
    let skipped: test::harness::TestHarnessStatus = TEST_STATUS_SKIPPED;
    let unknown: TestHarnessStatus = 99;
    let passed_from_fn: TestHarnessStatus = test_status_passed();
    let skipped_from_fn: test::harness::TestHarnessStatus =
        test::harness::test_status_skipped();
    let passed_ok: test::harness::TestHarnessCapability =
        test::harness::test_status_is_passed(passed);
    let failed_ok: TestHarnessCapability = test_status_is_failed(failed);
    let skipped_ok: test::harness::TestHarnessCapability =
        test::harness::test_status_is_skipped(skipped);
    let success_ok: TestHarnessCapability =
        test_status_is_success(passed_from_fn);
    let failed_success: test::harness::TestHarnessCapability =
        test::harness::test_status_is_success(failed);
    let failure_ok: test::harness::TestHarnessCapability =
        test::harness::test_status_is_failure(failed);
    let skipped_failure: TestHarnessCapability =
        test_status_is_failure(skipped);
    let known_passed: TestHarnessCapability = test_status_is_known(passed);
    let known_skipped: test::harness::TestHarnessCapability =
        test::harness::test_status_is_known(skipped_from_fn);
    let unknown_known: TestHarnessCapability = test_status_is_known(unknown);
    if (passed != 0 || failed != 1 || skipped != 2) {
        return 1;
    }
    if (passed_from_fn != passed || skipped_from_fn != skipped) {
        return 1;
    }
    if (!passed_ok || !failed_ok || !skipped_ok || !success_ok || !failure_ok) {
        return 1;
    }
    if (failed_success || skipped_failure || !known_passed || !known_skipped || unknown_known) {
        return 1;
    }
    return failed + skipped - failed - skipped;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load test::harness import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("test/harness.lani")
        }),
        "path manifest should include test::harness from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);
    for helper_name in [
        "test::harness::test_status_passed",
        "test::harness::test_status_failed",
        "test::harness::test_status_skipped",
        "test::harness::test_status_is_known",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root test::harness status contract",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("test::harness status helpers should type check through --stdlib-root");
}

#[test]
fn test_assert_public_helpers_type_check_through_stdlib_root() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "test_assert", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import test::assert;

fn main() {
    let value: i32 = 7;
    test::assert::is_true(value == 7);
    test::assert::is_false(value == 8);
    test::assert::eq_i32(value, 7);
    test::assert::ne_i32(value, 8);
    test::assert::lt_i32(1, value);
    test::assert::le_i32(value, 7);
    test::assert::gt_i32(value, 1);
    test::assert::ge_i32(value, 7);
    return value - 7;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load test::assert import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("test/assert.lani")
        }),
        "path manifest should include test::assert from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root test::assert public helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("test::assert public helpers should type check through --stdlib-root");
}

#[test]
fn stdlib_root_host_abi_public_calls_type_check_against_declared_contracts() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "host_abi_calls", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import alloc::allocator;
import core::panic;
import std::env;
import std::fs;
import std::io;
import std::net;
import std::process;
import std::time;

fn main() {
    let zero_ptr: u32 = 0;
    let size: usize = 16;
    let grown_size: usize = 32;
    let align: usize = 4;
    let sleep_ms: i64 = 0;
    let ptr: u32 = alloc::allocator::alloc(size, align);
    let grown: u32 = alloc::allocator::realloc(ptr, size, grown_size, align);
    let stdin_count: i32 = std::io::read_stdin(grown, grown_size);
    let stdout_count: i32 = std::io::write_stdout(grown, grown_size);
    let stderr_count: i32 = std::io::write_stderr(grown, grown_size);
    let flushed_stdout: i32 = std::io::flush_stdout();
    let flushed_stderr: i32 = std::io::flush_stderr();
    let file: i32 = std::fs::open_read(zero_ptr, size);
    let written: i32 = std::fs::write(file, grown, grown_size);
    let read: i32 = std::fs::read(file, grown, grown_size);
    let closed: i32 = std::fs::close(file);
    let vars: i32 = std::env::var_count();
    let key_len: i32 = std::env::var_key_len(0);
    let value_len: i32 = std::env::var_len(zero_ptr, size);
    let value_read: i32 = std::env::var_read(zero_ptr, size, grown, grown_size);
    let arg_count: i32 = std::process::argc();
    let arg_len: i32 = std::process::arg_len(0);
    let arg_read: i32 = std::process::arg_read(0, grown, grown_size);
    let now_ns: i64 = std::time::monotonic_now_ns();
    let sleep_status: i32 = std::time::sleep_ms(sleep_ms);
    let tcp: i32 = std::net::tcp_connect(zero_ptr, size, 80);
    let sent: i32 = std::net::tcp_send(tcp, grown, grown_size);
    let recv: i32 = std::net::tcp_recv(tcp, grown, grown_size);
    let udp: i32 = std::net::udp_bind(zero_ptr, size, 53);
    let udp_sent: i32 = std::net::udp_send_to(udp, zero_ptr, grown, grown_size);
    std::process::set_exit_code(0);
    alloc::allocator::dealloc(grown, grown_size, align);
    alloc::allocator::alloc_failed(grown_size, align);
    core::panic::unreachable();
    if (written + read + closed + vars + key_len + value_len + value_read + arg_count + arg_len + arg_read + sleep_status + sent + recv + udp_sent == 0) {
        return 0;
    }
    if (now_ns == 0) {
        return 0;
    }
    return tcp + udp;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load host ABI stdlib imports");
    for relative_path in [
        "alloc/allocator.lani",
        "core/panic.lani",
        "std/env.lani",
        "std/fs.lani",
        "std/io.lani",
        "std/net.lani",
        "std/process.lani",
        "std/time.lani",
    ] {
        assert!(
            manifest.files.iter().any(|file| {
                file.library_id == 0 && file.path == stdlib_root.join(relative_path)
            }),
            "path manifest should include {relative_path} from the stdlib root"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root public host ABI calls",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("public host ABI declarations should type check through --stdlib-root while unbound");
}

#[test]
fn core_option_or_type_checks_through_stdlib_root_without_runtime_binding() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "option_or", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::option;

fn main() {
    let primary: core::option::Option<i32> = core::option::Some(7);
    let fallback: core::option::Option<i32> = core::option::Some(11);
    let selected: core::option::Option<i32> = core::option::or(primary, fallback);
    let selected_value: i32 = core::option::unwrap_or(selected, 0);
    let empty: core::option::Option<i32> = core::option::None;
    let recovered: core::option::Option<i32> =
        core::option::or(empty, core::option::Some(5));
    let recovered_value: i32 = core::option::unwrap_or(recovered, 0);
    if (selected_value != 7 || recovered_value != 5) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::option import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")
        }),
        "path manifest should include core::option from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);
    assert!(
        runtime_bound_api_diagnostic_info("core::option::or").is_none(),
        "core::option::or is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::option::or helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::option::or should type check through --stdlib-root");
}

#[test]
fn core_result_or_type_checks_through_stdlib_root_without_runtime_binding() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_stdlib_runtime", "result_or", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::result;

fn main() {
    let primary: core::result::Result<i32, bool> = core::result::Ok(7);
    let fallback: core::result::Result<i32, bool> = core::result::Ok(11);
    let selected: core::result::Result<i32, bool> = core::result::or(primary, fallback);
    let selected_value: i32 = core::result::unwrap_or(selected, 0);
    let failed: core::result::Result<i32, bool> = core::result::Err(false);
    let recovered: core::result::Result<i32, bool> =
        core::result::or(failed, core::result::Ok(5));
    let recovered_value: i32 = core::result::unwrap_or(recovered, 0);
    if (selected_value != 7 || recovered_value != 5) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core::result import");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")
        }),
        "path manifest should include core::result from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 2);
    assert!(
        runtime_bound_api_diagnostic_info("core::result::or").is_none(),
        "core::result::or is a source-level helper and must not claim a runtime binding"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::result::or helper",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::result::or should type check through --stdlib-root");
}

#[test]
fn core_option_result_contains_helpers_type_checks_through_stdlib_root_without_runtime_binding() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new(
        "laniusc_stdlib_runtime",
        "option_result_contains",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::result;

fn main() {
    let some: core::option::Option<i32> = core::option::Some(7);
    let none: core::option::Option<i32> = core::option::None;
    let ok: core::result::Result<i32, bool> = core::result::Ok(7);
    let err: core::result::Result<i32, bool> = core::result::Err(false);
    let option_hit: bool = core::option::contains_i32(some, 7);
    let option_miss: bool = core::option::contains_i32(some, 8);
    let none_hit: bool = core::option::contains_i32(none, 7);
    let result_hit: bool = core::result::contains_i32(ok, 7);
    let result_miss: bool = core::result::contains_i32(ok, 8);
    let err_hit: bool = core::result::contains_i32(err, 7);
    let ok_bool: core::result::Result<bool, i32> = core::result::Ok(true);
    let err_for_bool: core::result::Result<bool, i32> = core::result::Err(4);
    let result_bool_hit: bool = core::result::contains_bool(ok_bool, true);
    let result_bool_miss: bool = core::result::contains_bool(ok_bool, false);
    let result_bool_err_hit: bool = core::result::contains_bool(err_for_bool, true);
    let ok_u32: core::result::Result<u32, bool> = core::result::Ok(42);
    let err_for_u32: core::result::Result<u32, bool> = core::result::Err(false);
    let result_u32_hit: bool = core::result::contains_u32(ok_u32, 42);
    let result_u32_miss: bool = core::result::contains_u32(ok_u32, 43);
    let result_u32_err_hit: bool = core::result::contains_u32(err_for_u32, 42);
    let ok_u8: core::result::Result<u8, bool> = core::result::Ok(8);
    let err_for_u8: core::result::Result<u8, bool> = core::result::Err(false);
    let result_u8_hit: bool = core::result::contains_u8(ok_u8, 8);
    let result_u8_miss: bool = core::result::contains_u8(ok_u8, 9);
    let result_u8_err_hit: bool = core::result::contains_u8(err_for_u8, 8);
    let err_code: core::result::Result<i32, i32> = core::result::Err(9);
    let ok_code: core::result::Result<i32, i32> = core::result::Ok(1);
    let result_err_hit: bool = core::result::contains_err_i32(err_code, 9);
    let result_err_miss: bool = core::result::contains_err_i32(err_code, 10);
    let result_ok_err_hit: bool = core::result::contains_err_i32(ok_code, 9);
    let result_err_bool_hit: bool = core::result::contains_err_bool(err, false);
    let result_err_bool_miss: bool = core::result::contains_err_bool(err, true);
    let result_ok_err_bool_hit: bool = core::result::contains_err_bool(ok, false);
    let err_code_u32: core::result::Result<bool, u32> = core::result::Err(42);
    let ok_code_u32: core::result::Result<bool, u32> = core::result::Ok(true);
    let result_err_u32_hit: bool = core::result::contains_err_u32(err_code_u32, 42);
    let result_err_u32_miss: bool = core::result::contains_err_u32(err_code_u32, 43);
    let result_ok_err_u32_hit: bool = core::result::contains_err_u32(ok_code_u32, 42);
    let err_code_u8: core::result::Result<bool, u8> = core::result::Err(8);
    let ok_code_u8: core::result::Result<bool, u8> = core::result::Ok(true);
    let result_err_u8_hit: bool = core::result::contains_err_u8(err_code_u8, 8);
    let result_err_u8_miss: bool = core::result::contains_err_u8(err_code_u8, 9);
    let result_ok_err_u8_hit: bool = core::result::contains_err_u8(ok_code_u8, 8);
    if (!option_hit || option_miss || none_hit) {
        return 1;
    }
    if (!result_hit || result_miss || err_hit) {
        return 1;
    }
    if (!result_bool_hit || result_bool_miss || result_bool_err_hit) {
        return 1;
    }
    if (!result_u32_hit || result_u32_miss || result_u32_err_hit) {
        return 1;
    }
    if (!result_u8_hit || result_u8_miss || result_u8_err_hit) {
        return 1;
    }
    if (!result_err_hit || result_err_miss || result_ok_err_hit) {
        return 1;
    }
    if (!result_err_bool_hit || result_err_bool_miss || result_ok_err_bool_hit) {
        return 1;
    }
    if (!result_err_u32_hit || result_err_u32_miss || result_ok_err_u32_hit) {
        return 1;
    }
    if (!result_err_u8_hit || result_err_u8_miss || result_ok_err_u8_hit) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core option/result imports");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")
        }),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")
        }),
        "path manifest should include core::result from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);
    for helper_name in [
        "core::option::contains_i32",
        "core::result::contains_i32",
        "core::result::contains_bool",
        "core::result::contains_u32",
        "core::result::contains_u8",
        "core::result::contains_err_i32",
        "core::result::contains_err_bool",
        "core::result::contains_err_u32",
        "core::result::contains_err_u8",
    ] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core option/result contains helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core option/result contains helpers should type check through --stdlib-root");
}

#[test]
fn core_option_result_and_type_checks_through_stdlib_root_without_runtime_binding() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry =
        common::TempArtifact::new("laniusc_stdlib_runtime", "option_result_and", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::option;
import core::result;

fn main() {
    let option_primary: core::option::Option<i32> = core::option::Some(7);
    let option_next: core::option::Option<i32> = core::option::Some(11);
    let option_selected: core::option::Option<i32> =
        core::option::and(option_primary, option_next);
    let option_selected_value: i32 =
        core::option::unwrap_or(option_selected, 0);
    let option_empty: core::option::Option<i32> = core::option::None;
    let option_blocked: core::option::Option<i32> =
        core::option::and(option_empty, core::option::Some(13));
    let option_blocked_value: i32 =
        core::option::unwrap_or(option_blocked, 0);

    let result_primary: core::result::Result<i32, bool> = core::result::Ok(3);
    let result_next: core::result::Result<i32, bool> = core::result::Ok(5);
    let result_selected: core::result::Result<i32, bool> =
        core::result::and(result_primary, result_next);
    let result_selected_value: i32 =
        core::result::unwrap_or(result_selected, 0);
    let result_failed: core::result::Result<i32, bool> =
        core::result::Err(false);
    let result_blocked: core::result::Result<i32, bool> =
        core::result::and(result_failed, core::result::Ok(9));
    let result_blocked_value: i32 =
        core::result::unwrap_or(result_blocked, 0);

    if (option_selected_value != 11 || option_blocked_value != 0) {
        return 1;
    }
    if (result_selected_value != 5 || result_blocked_value != 0) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("stdlib-root path manifest should load core option/result imports");
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/option.lani")
        }),
        "path manifest should include core::option from the stdlib root"
    );
    assert!(
        manifest.files.iter().any(|file| {
            file.library_id == 0 && file.path == stdlib_root.join("core/result.lani")
        }),
        "path manifest should include core::result from the stdlib root"
    );
    assert_eq!(manifest.files.len(), 3);
    for helper_name in ["core::option::and", "core::result::and"] {
        assert!(
            runtime_bound_api_diagnostic_info(helper_name).is_none(),
            "{helper_name} is a source-level helper and must not claim a runtime binding"
        );
    }

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core option/result and helpers",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core option/result and helpers should type check through --stdlib-root");
}
