mod common;

use laniusc::{
    codegen::unit::{SourcePackArtifactTarget, SourcePackJob, SourcePackJobPhase},
    compiler::{
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
            .all(|api| api.diagnostic_code == "LNC0038"
                && api.current_status == "known-unbound"
                && !api.executable),
        "runtime-bound API diagnostics must not mark any stdlib extern executable"
    );

    for api in RUNTIME_BOUND_API_DIAGNOSTICS {
        assert!(
            runtime_service_boundary_diagnostic_info(api.service_id).is_some(),
            "{} should point at a known runtime service boundary",
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

    let print_i32 = runtime_bound_api_diagnostic_info("std::io::print_i32")
        .expect("stdio print_i32 should have a public runtime-bound API row");
    assert_eq!(
        print_i32.service_id, GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        "stdio print_i32 should map to the stdio runtime service"
    );
    assert_eq!(print_i32.module_path, "std::io");
    assert_eq!(print_i32.executable_probe, "print_i32_is_executable()");
    assert_eq!(
        print_i32.binding_probe,
        "print_i32_requires_runtime_binding()"
    );
    assert!(
        runtime_bound_api_diagnostic_info("std::io::println").is_none(),
        "unknown stdlib APIs should not be described as known runtime boundaries"
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
    let row_byte_len = row_count * 3 * u64::try_from(std::mem::size_of::<u32>()).unwrap();
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
    let allocator_in_range: Capability =
        service_id_in_descriptor_range(SERVICE_ALLOCATOR_ID);
    let test_harness_in_range: core::runtime::Capability =
        core::runtime::service_id_in_descriptor_range(core::runtime::SERVICE_TEST_HARNESS_ID);
    let zero_in_range: Capability = core::runtime::service_id_in_descriptor_range(0);
    let future_in_range: core::runtime::Capability = service_id_in_descriptor_range(99);
    let runtime_services: core::runtime::Capability = core::runtime::has_runtime_services();
    let contract_only: Capability = runtime_services_are_contract_only();
    let stdio_service_contract_only: core::runtime::Capability =
        core::runtime::service_is_contract_only(core::runtime::SERVICE_STDIO_ID);
    let unknown_service_contract_only: Capability = service_is_contract_only(99);
    let stdio_descriptor_known: Capability =
        service_descriptor_is_known(core::runtime::SERVICE_STDIO_ID);
    let unknown_descriptor_known: core::runtime::Capability =
        core::runtime::service_descriptor_is_known(99);
    let stdio_has_binding: Capability =
        service_has_runtime_binding(core::runtime::SERVICE_STDIO_ID);
    let stdio_is_unbound: core::runtime::Capability =
        core::runtime::service_is_unbound(core::runtime::SERVICE_STDIO_ID);
    let stdio_fail_closed: Capability =
        service_is_fail_closed(core::runtime::SERVICE_STDIO_ID);
    let stdio_uses_lnc0038_boundary: core::runtime::Capability =
        core::runtime::service_binding_diagnostic_is_lnc0038(core::runtime::SERVICE_STDIO_ID);
    let unknown_uses_lnc0038_boundary: Capability =
        service_binding_diagnostic_is_lnc0038(99);
    let stdio_api_needs_binding: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_binding(core::runtime::SERVICE_STDIO_ID);
    let unknown_api_needs_binding: Capability = runtime_bound_api_requires_binding(99);
    let stdio_api_blocked: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_blocked(core::runtime::SERVICE_STDIO_ID);
    let unknown_api_blocked: Capability = runtime_bound_api_is_blocked(99);
    if (service_count != declared_count || service_count != 13) {
        return 1;
    }
    if (metadata_version != declared_metadata_version || metadata_version != 1) {
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
        || !stdio_service_contract_only
        || unknown_service_contract_only
        || !stdio_descriptor_known
        || unknown_descriptor_known
        || stdio_has_binding
        || !stdio_is_unbound
        || !stdio_fail_closed
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
    let runtime_needs_binding: core::runtime::Capability =
        core::runtime::service_requires_runtime_binding(allocator_service_id);
    if (raw_service_id != declared_raw_service_id || raw_service_id != allocator_service_id) {
        return 1;
    }
    if (raw_abi != runtime_abi || raw_status != declared_unavailable || raw_status != runtime_status) {
        return 1;
    }
    if (!raw_known || !runtime_known || raw_binding || raw_available || raw_executable) {
        return 1;
    }
    if (!raw_blocked || !raw_needs_binding || !runtime_needs_binding) {
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
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i64.lani"))
    );

    common::block_on_gpu_with_timeout(
        "GPU type check stdlib-root core::i64 width metadata",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::i64 width metadata should type check through --stdlib-root");
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
    let first_service_in_range: Capability = service_id_in_descriptor_range(first_service_id);
    let last_service_in_range: core::runtime::Capability =
        core::runtime::service_id_in_descriptor_range(last_service_id);
    let allocator_abi: RuntimeAbiVersion = runtime_abi_version_for_service(allocator_id);
    let unknown_service_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(99);
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
        core::runtime::service_status(99);
    let available_status: RuntimeServiceStatus = SERVICE_STATUS_AVAILABLE;
    let network_unavailable: Capability = core::runtime::service_is_unavailable(network_id);
    let process_available: Capability = core::runtime::service_is_available(process_id);
    let stdio_api_executable: core::runtime::Capability =
        core::runtime::runtime_bound_api_is_executable(core::runtime::SERVICE_STDIO_ID);
    let stdio_api_needs_binding: core::runtime::Capability =
        core::runtime::runtime_bound_api_requires_binding(core::runtime::SERVICE_STDIO_ID);
    let unknown_api_needs_binding: Capability = runtime_bound_api_requires_binding(99);
    let unknown_service_unknown: core::runtime::Capability = service_is_unknown(99);
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
        core::runtime::service_status(99);
    let allocator_abi: alloc::allocator::AllocatorRuntimeAbiVersion =
        allocator_runtime_abi_version();
    let declared_abi: AllocatorRuntimeAbiVersion = ALLOCATOR_RUNTIME_ABI_VERSION;
    let runtime_abi: core::runtime::RuntimeAbiVersion =
        core::runtime::runtime_abi_version_for_service(runtime_allocator_id);
    let allocator_available: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_is_available();
    let allocator_blocked: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_is_blocked();
    let declared_binding: AllocatorCapability = ALLOCATOR_HAS_RUNTIME_BINDING;
    let allocator_needs_binding: alloc::allocator::AllocatorCapability =
        alloc::allocator::allocator_requires_runtime_binding();
    let imported_needs_binding: AllocatorCapability =
        allocator_requires_runtime_binding();
    let allocator_contract_only: AllocatorCapability =
        allocator_host_abi_is_contract_only();
    let alloc_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::alloc_is_executable();
    let alloc_blocked: AllocatorCapability = alloc_is_blocked();
    let alloc_needs_binding: AllocatorCapability =
        alloc_requires_runtime_binding();
    let realloc_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::realloc_is_executable();
    let realloc_blocked: AllocatorCapability =
        alloc::allocator::realloc_is_blocked();
    let realloc_needs_binding: AllocatorCapability =
        realloc_requires_runtime_binding();
    let dealloc_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::dealloc_is_executable();
    let dealloc_blocked: AllocatorCapability =
        alloc::allocator::dealloc_is_blocked();
    let dealloc_needs_binding: AllocatorCapability =
        dealloc_requires_runtime_binding();
    let alloc_failed_executable: alloc::allocator::AllocatorCapability =
        alloc::allocator::alloc_failed_is_executable();
    let alloc_failed_blocked: AllocatorCapability =
        alloc_failed_is_blocked();
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
    if (!allocator_known || !allocator_metadata_available || allocator_available || !allocator_blocked || declared_binding || !allocator_needs_binding || !imported_needs_binding || !allocator_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (alloc_executable || realloc_executable || dealloc_executable || alloc_failed_executable) {
        return 1;
    }
    if (!alloc_blocked || !realloc_blocked || !dealloc_blocked || !alloc_failed_blocked) {
        return 1;
    }
    if (!alloc_needs_binding || !realloc_needs_binding || !dealloc_needs_binding || !alloc_failed_needs_binding) {
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
    let io_known: StdioCapability = std::io::stdio_service_is_known();
    let io_status: std::io::StdioServiceStatus = std::io::stdio_service_status();
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_stdio_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(99);
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
    if (!io_known || io_available || !io_blocked || !io_needs_binding || print_i32_executable || !print_i32_blocked || !print_i32_needs_binding || runtime_api_executable || !runtime_api_needs_binding || !runtime_needs_binding) {
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
    let stdio_needs_binding: StdioCapability = stdio_requires_runtime_binding();
    let stdio_contract_only: StdioCapability = stdio_host_abi_is_contract_only();
    let stdout_executable: std::io::StdioCapability =
        std::io::write_stdout_is_executable();
    let stdout_blocked: std::io::StdioCapability =
        std::io::write_stdout_is_blocked();
    let stdout_needs_binding: StdioCapability =
        write_stdout_requires_runtime_binding();
    let stderr_executable: std::io::StdioCapability =
        std::io::write_stderr_is_executable();
    let stderr_blocked: StdioCapability = write_stderr_is_blocked();
    let stderr_needs_binding: StdioCapability =
        write_stderr_requires_runtime_binding();
    let stdin_executable: std::io::StdioCapability =
        std::io::read_stdin_is_executable();
    let stdin_blocked: std::io::StdioCapability = std::io::read_stdin_is_blocked();
    let stdin_needs_binding: StdioCapability =
        read_stdin_requires_runtime_binding();
    let flush_stdout_executable: std::io::StdioCapability =
        std::io::flush_stdout_is_executable();
    let flush_stdout_blocked: StdioCapability = flush_stdout_is_blocked();
    let flush_stdout_needs_binding: StdioCapability =
        flush_stdout_requires_runtime_binding();
    let flush_stderr_executable: std::io::StdioCapability =
        std::io::flush_stderr_is_executable();
    let flush_stderr_blocked: std::io::StdioCapability =
        std::io::flush_stderr_is_blocked();
    let flush_stderr_needs_binding: StdioCapability =
        flush_stderr_requires_runtime_binding();
    let print_i32_executable: std::io::StdioCapability =
        std::io::print_i32_is_executable();
    let print_i32_blocked: StdioCapability = print_i32_is_blocked();
    let print_i32_needs_binding: StdioCapability =
        print_i32_requires_runtime_binding();
    if (stdio_available || !stdio_metadata_available || !stdio_blocked || !stdio_needs_binding || !stdio_contract_only) {
        return 1;
    }
    if (stdout_executable || stderr_executable || stdin_executable || flush_stdout_executable || flush_stderr_executable || print_i32_executable) {
        return 1;
    }
    if (!stdout_blocked || !stderr_blocked || !stdin_blocked || !flush_stdout_blocked || !flush_stderr_blocked || !print_i32_blocked) {
        return 1;
    }
    if (!stdout_needs_binding || !stderr_needs_binding || !stdin_needs_binding || !flush_stdout_needs_binding || !flush_stderr_needs_binding || !print_i32_needs_binding) {
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
    let panic_needs_binding: core::panic::PanicCapability =
        core::panic::panic_requires_runtime_binding();
    let unreachable_executable: core::panic::PanicCapability =
        core::panic::unreachable_is_executable();
    let unreachable_blocked: core::panic::PanicCapability =
        core::panic::unreachable_is_blocked();
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
        && !declared_binding
        && hook_needs_binding
        && hook_host_abi_contract_only
        && hook_contract_only
        && !panic_executable
        && panic_blocked
        && panic_needs_binding
        && !unreachable_executable
        && unreachable_blocked
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
    let clock_known: ClockCapability = std::time::clock_service_is_known();
    let clock_metadata_available: ClockCapability =
        std::time::clock_contract_metadata_is_available();
    let clock_status: std::time::ClockServiceStatus = std::time::clock_service_status();
    let declared_status: ClockServiceStatus = CLOCK_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_clock_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(99);
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
    let clock_needs_binding: ClockCapability = clock_requires_runtime_binding();
    let monotonic_executable: std::time::ClockCapability =
        std::time::monotonic_now_ns_is_executable();
    let monotonic_blocked: std::time::ClockCapability =
        std::time::monotonic_now_ns_is_blocked();
    let monotonic_needs_binding: ClockCapability =
        monotonic_now_ns_requires_runtime_binding();
    let system_executable: std::time::ClockCapability =
        std::time::system_now_unix_ms_is_executable();
    let system_blocked: ClockCapability = system_now_unix_ms_is_blocked();
    let system_needs_binding: ClockCapability =
        system_now_unix_ms_requires_runtime_binding();
    let sleep_executable: std::time::ClockCapability =
        std::time::sleep_ms_is_executable();
    let sleep_blocked: ClockCapability = std::time::sleep_ms_is_blocked();
    let sleep_needs_binding: ClockCapability = sleep_ms_requires_runtime_binding();
    if (clock_available || !clock_blocked || !clock_needs_binding) {
        return 1;
    }
    if (monotonic_executable || system_executable || sleep_executable) {
        return 1;
    }
    if (!monotonic_blocked || !system_blocked || !sleep_blocked) {
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
    let fs_known: FilesystemCapability = filesystem_service_is_known();
    let fs_status: std::fs::FilesystemServiceStatus = std::fs::filesystem_service_status();
    let declared_status: FilesystemServiceStatus = FILESYSTEM_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_fs_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(99);
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
    let fs_needs_binding: FilesystemCapability = filesystem_requires_runtime_binding();
    let fs_contract_only: FilesystemCapability = filesystem_host_abi_is_contract_only();
    let file_io_executable: std::fs::FilesystemCapability =
        std::fs::file_io_is_executable();
    let file_io_blocked: std::fs::FilesystemCapability =
        std::fs::file_io_is_blocked();
    let file_io_needs_binding: FilesystemCapability =
        file_io_requires_runtime_binding();
    let path_mutation_executable: std::fs::FilesystemCapability =
        std::fs::path_mutation_api_is_executable();
    let path_mutation_blocked: FilesystemCapability =
        path_mutation_api_is_blocked();
    let path_mutation_needs_binding: FilesystemCapability =
        path_mutation_api_requires_runtime_binding();
    if (fs_available || !fs_metadata_available || !fs_blocked || !fs_needs_binding || !fs_contract_only) {
        return 1;
    }
    if (file_io_executable || !file_io_blocked || !file_io_needs_binding) {
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
    let open_read_needs_binding: FilesystemCapability =
        open_read_requires_runtime_binding();
    let open_write_executable: std::fs::FilesystemCapability =
        std::fs::open_write_is_executable();
    let open_write_blocked: FilesystemCapability = open_write_is_blocked();
    let open_write_needs_binding: FilesystemCapability =
        open_write_requires_runtime_binding();
    let open_append_executable: std::fs::FilesystemCapability =
        std::fs::open_append_is_executable();
    let open_append_blocked: FilesystemCapability = open_append_is_blocked();
    let open_append_needs_binding: FilesystemCapability =
        open_append_requires_runtime_binding();
    let close_executable: std::fs::FilesystemCapability =
        std::fs::close_is_executable();
    let close_blocked: FilesystemCapability = close_is_blocked();
    let close_needs_binding: FilesystemCapability = close_requires_runtime_binding();
    let read_executable: std::fs::FilesystemCapability =
        std::fs::read_is_executable();
    let read_blocked: FilesystemCapability = read_is_blocked();
    let read_needs_binding: FilesystemCapability = read_requires_runtime_binding();
    let write_executable: std::fs::FilesystemCapability =
        std::fs::write_is_executable();
    let write_blocked: FilesystemCapability = write_is_blocked();
    let write_needs_binding: FilesystemCapability = write_requires_runtime_binding();
    if (file_io_executable || open_read_executable || open_write_executable || open_append_executable || close_executable || read_executable || write_executable) {
        return 1;
    }
    if (!file_io_blocked || !open_read_blocked || !open_write_blocked || !open_append_blocked || !close_blocked || !read_blocked || !write_blocked) {
        return 1;
    }
    if (!file_io_needs_binding || !open_read_needs_binding || !open_write_needs_binding || !open_append_needs_binding || !close_needs_binding || !read_needs_binding || !write_needs_binding) {
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
    let network_known: NetworkCapability = std::net::network_service_is_known();
    let network_metadata_available: NetworkCapability =
        std::net::network_contract_metadata_is_available();
    let network_status: std::net::NetworkServiceStatus = std::net::network_service_status();
    let declared_status: NetworkServiceStatus = NETWORK_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_network_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(99);
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
    let network_needs_binding: NetworkCapability = network_requires_runtime_binding();
    let tcp_executable: std::net::NetworkCapability = std::net::tcp_api_is_executable();
    let tcp_blocked: NetworkCapability = tcp_api_is_blocked();
    let tcp_needs_binding: NetworkCapability = tcp_api_requires_runtime_binding();
    let udp_executable: std::net::NetworkCapability = std::net::udp_api_is_executable();
    let udp_blocked: std::net::NetworkCapability = std::net::udp_api_is_blocked();
    let udp_needs_binding: NetworkCapability = udp_api_requires_runtime_binding();
    if (network_available || !network_blocked || !network_needs_binding) {
        return 1;
    }
    if (tcp_executable || udp_executable) {
        return 1;
    }
    if (!tcp_blocked || !udp_blocked) {
        return 1;
    }
    if (!tcp_needs_binding || !udp_needs_binding) {
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
    let declared_binding: HostServicesCapability =
        HOST_SERVICES_HAS_RUNTIME_BINDING;
    let host_needs_binding: std::host::HostServicesCapability =
        std::host::host_services_require_runtime_binding();
    let imported_needs_binding: HostServicesCapability =
        host_services_require_runtime_binding();
    let host_contract_only: HostServicesCapability =
        host_services_abi_is_contract_only();
    let host_api_executable: std::host::HostServicesCapability =
        std::host::host_services_api_is_executable();
    let host_api_blocked: std::host::HostServicesCapability =
        std::host::host_services_api_is_blocked();
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
    if (!host_known || !host_metadata_available || host_available || !host_blocked || declared_binding || !host_needs_binding || !imported_needs_binding || !host_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (host_api_executable || !host_api_blocked || !host_api_needs_binding) {
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
    let process_known: ProcessCapability = process_service_is_known();
    let process_status: std::process::ProcessServiceStatus =
        std::process::process_service_status();
    let declared_status: ProcessServiceStatus = PROCESS_SERVICE_STATUS_UNAVAILABLE;
    let runtime_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(runtime_process_id);
    let unknown_status: core::runtime::RuntimeServiceStatus =
        core::runtime::service_status(99);
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
    let process_needs_binding: ProcessCapability = process_requires_runtime_binding();
    let process_contract_only: ProcessCapability = process_host_abi_is_contract_only();
    let args_executable: std::process::ProcessCapability =
        std::process::process_args_is_executable();
    let args_blocked: std::process::ProcessCapability =
        std::process::process_args_is_blocked();
    let args_need_binding: ProcessCapability = process_args_requires_runtime_binding();
    let exit_executable: std::process::ProcessCapability =
        std::process::process_exit_is_executable();
    let exit_blocked: ProcessCapability = process_exit_is_blocked();
    let exit_needs_binding: ProcessCapability =
        std::process::process_exit_requires_runtime_binding();
    let argc_executable: std::process::ProcessCapability =
        std::process::argc_is_executable();
    let argc_blocked: ProcessCapability = argc_is_blocked();
    let argc_needs_binding: ProcessCapability = argc_requires_runtime_binding();
    let arg_len_executable: ProcessCapability = arg_len_is_executable();
    let arg_len_blocked: std::process::ProcessCapability =
        std::process::arg_len_is_blocked();
    let arg_len_needs_binding: ProcessCapability = arg_len_requires_runtime_binding();
    let arg_read_executable: ProcessCapability = arg_read_is_executable();
    let arg_read_blocked: std::process::ProcessCapability =
        std::process::arg_read_is_blocked();
    let arg_read_needs_binding: ProcessCapability = arg_read_requires_runtime_binding();
    let set_exit_code_executable: std::process::ProcessCapability =
        std::process::set_exit_code_is_executable();
    let set_exit_code_blocked: ProcessCapability = set_exit_code_is_blocked();
    let set_exit_code_needs_binding: ProcessCapability =
        set_exit_code_requires_runtime_binding();
    let exit_call_executable: ProcessCapability = exit_is_executable();
    let exit_call_blocked: std::process::ProcessCapability =
        std::process::exit_is_blocked();
    let exit_call_needs_binding: ProcessCapability = exit_requires_runtime_binding();
    if (process_available || !process_metadata_available || !process_blocked || !process_needs_binding || !process_contract_only) {
        return 1;
    }
    if (args_executable || !args_blocked || !args_need_binding) {
        return 1;
    }
    if (exit_executable || !exit_blocked || !exit_needs_binding) {
        return 1;
    }
    if (argc_executable || arg_len_executable || arg_read_executable || set_exit_code_executable || exit_call_executable) {
        return 1;
    }
    if (!argc_blocked || !arg_len_blocked || !arg_read_blocked || !set_exit_code_blocked || !exit_call_blocked) {
        return 1;
    }
    if (!argc_needs_binding || !arg_len_needs_binding || !arg_read_needs_binding || !set_exit_code_needs_binding || !exit_call_needs_binding) {
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
    if (!success_ok || !failure_ok || !alternate_failure_ok) {
        return 1;
    }
    if (process_available || !process_blocked || exit_executable || !exit_needs_binding) {
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
    let declared_binding: EnvCapability = ENV_HAS_RUNTIME_BINDING;
    let env_needs_binding: std::env::EnvCapability =
        std::env::env_requires_runtime_binding();
    let imported_needs_binding: EnvCapability = env_requires_runtime_binding();
    let env_contract_only: EnvCapability = env_host_abi_is_contract_only();
    let var_len_executable: std::env::EnvCapability =
        std::env::var_len_is_executable();
    let var_len_blocked: EnvCapability = var_len_is_blocked();
    let var_len_needs_binding: EnvCapability = var_len_requires_runtime_binding();
    let var_read_executable: std::env::EnvCapability =
        std::env::var_read_is_executable();
    let var_read_blocked: std::env::EnvCapability =
        std::env::var_read_is_blocked();
    let var_read_needs_binding: EnvCapability = var_read_requires_runtime_binding();
    let var_count_executable: std::env::EnvCapability =
        std::env::var_count_is_executable();
    let var_count_blocked: EnvCapability = var_count_is_blocked();
    let var_count_needs_binding: EnvCapability = var_count_requires_runtime_binding();
    let var_key_len_executable: std::env::EnvCapability =
        std::env::var_key_len_is_executable();
    let var_key_len_blocked: std::env::EnvCapability =
        std::env::var_key_len_is_blocked();
    let var_key_len_needs_binding: EnvCapability = var_key_len_requires_runtime_binding();
    let var_key_read_executable: std::env::EnvCapability =
        std::env::var_key_read_is_executable();
    let var_key_read_blocked: EnvCapability = var_key_read_is_blocked();
    let var_key_read_needs_binding: EnvCapability =
        var_key_read_requires_runtime_binding();
    let current_dir_len_executable: std::env::EnvCapability =
        std::env::current_dir_len_is_executable();
    let current_dir_len_blocked: std::env::EnvCapability =
        std::env::current_dir_len_is_blocked();
    let current_dir_len_needs_binding: EnvCapability =
        current_dir_len_requires_runtime_binding();
    let current_dir_read_executable: std::env::EnvCapability =
        std::env::current_dir_read_is_executable();
    let current_dir_read_blocked: EnvCapability = current_dir_read_is_blocked();
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
    if (!env_known || !env_metadata_available || env_available || !env_blocked || declared_binding || !env_needs_binding || !imported_needs_binding || !env_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (var_len_executable || var_read_executable || var_count_executable || var_key_len_executable || var_key_read_executable || current_dir_len_executable || current_dir_read_executable) {
        return 1;
    }
    if (!var_len_blocked || !var_read_blocked || !var_count_blocked || !var_key_len_blocked || !var_key_read_blocked || !current_dir_len_blocked || !current_dir_read_blocked) {
        return 1;
    }
    if (!var_len_needs_binding || !var_read_needs_binding || !var_count_needs_binding || !var_key_len_needs_binding || !var_key_read_needs_binding || !current_dir_len_needs_binding || !current_dir_read_needs_binding) {
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
    let secure_rng_needs_binding: RandomCapability =
        secure_rng_api_requires_runtime_binding();
    let fill_bytes_executable: std::random::RandomCapability =
        std::random::fill_secure_bytes_is_executable();
    let fill_bytes_blocked: RandomCapability =
        fill_secure_bytes_is_blocked();
    let fill_bytes_needs_binding: std::random::RandomCapability =
        std::random::fill_secure_bytes_requires_runtime_binding();
    let secure_u32_executable: RandomCapability =
        secure_u32_is_executable();
    let secure_u32_blocked: std::random::RandomCapability =
        std::random::secure_u32_is_blocked();
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
    if (!random_known || !random_metadata_available || random_available || !random_blocked || declared_binding || !random_needs_binding || !imported_needs_binding || !random_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (secure_rng_executable || !secure_rng_blocked || !secure_rng_needs_binding) {
        return 1;
    }
    if (fill_bytes_executable || secure_u32_executable) {
        return 1;
    }
    if (!fill_bytes_blocked || !secure_u32_blocked) {
        return 1;
    }
    if (!fill_bytes_needs_binding || !secure_u32_needs_binding) {
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
    let buffer_needs_binding: GpuCapability =
        gpu_buffer_api_requires_runtime_binding();
    let dispatch_executable: std::gpu::GpuCapability =
        std::gpu::gpu_dispatch_api_is_executable();
    let dispatch_blocked: GpuCapability =
        gpu_dispatch_api_is_blocked();
    let dispatch_needs_binding: GpuCapability =
        gpu_dispatch_api_requires_runtime_binding();
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
    if (!gpu_known || !gpu_metadata_available || gpu_available || !gpu_blocked || declared_binding || !gpu_needs_binding || !imported_needs_binding || !gpu_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (buffer_executable || dispatch_executable) {
        return 1;
    }
    if (!buffer_blocked || !buffer_needs_binding || !dispatch_blocked || !dispatch_needs_binding) {
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
    let spawn_needs_binding: ThreadCapability =
        thread_spawn_requires_runtime_binding();
    let join_executable: std::thread::ThreadCapability =
        std::thread::thread_join_is_executable();
    let join_blocked: ThreadCapability =
        thread_join_is_blocked();
    let join_needs_binding: ThreadCapability =
        thread_join_requires_runtime_binding();
    let yield_executable: std::thread::ThreadCapability =
        std::thread::thread_yield_is_executable();
    let yield_blocked: std::thread::ThreadCapability =
        std::thread::thread_yield_is_blocked();
    let yield_needs_binding: ThreadCapability =
        thread_yield_requires_runtime_binding();
    let current_id_executable: std::thread::ThreadCapability =
        std::thread::thread_current_id_is_executable();
    let current_id_blocked: ThreadCapability =
        thread_current_id_is_blocked();
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
    if (!thread_known || !thread_metadata_available || thread_available || !thread_blocked || declared_binding || !thread_needs_binding || !imported_needs_binding || !thread_contract_only || !runtime_needs_binding) {
        return 1;
    }
    if (spawn_executable || join_executable || yield_executable || current_id_executable) {
        return 1;
    }
    if (!spawn_blocked || !join_blocked || !yield_blocked || !current_id_blocked) {
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
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    let grown: u32 = alloc::allocator::realloc(ptr, 16, 32, 4);
    let stdin_count: i32 = std::io::read_stdin(grown, 32);
    let stdout_count: i32 = std::io::write_stdout(grown, 32);
    let stderr_count: i32 = std::io::write_stderr(grown, 32);
    let flushed_stdout: i32 = std::io::flush_stdout();
    let flushed_stderr: i32 = std::io::flush_stderr();
    let file: i32 = std::fs::open_read(0, 0);
    let written: i32 = std::fs::write(file, grown, 32);
    let read: i32 = std::fs::read(file, grown, 32);
    let closed: i32 = std::fs::close(file);
    let vars: i32 = std::env::var_count();
    let key_len: i32 = std::env::var_key_len(0);
    let value_len: i32 = std::env::var_len(0, 0);
    let value_read: i32 = std::env::var_read(0, 0, grown, 32);
    let arg_count: i32 = std::process::argc();
    let arg_len: i32 = std::process::arg_len(0);
    let arg_read: i32 = std::process::arg_read(0, grown, 32);
    let now_ns: i64 = std::time::monotonic_now_ns();
    let sleep_status: i32 = std::time::sleep_ms(0);
    let tcp: i32 = std::net::tcp_connect(0, 0, 80);
    let sent: i32 = std::net::tcp_send(tcp, grown, 32);
    let recv: i32 = std::net::tcp_recv(tcp, grown, 32);
    let udp: i32 = std::net::udp_bind(0, 0, 53);
    let udp_sent: i32 = std::net::udp_send_to(udp, 0, 0, 53, grown, 32);
    std::io::print_i32(stdin_count + stdout_count + stderr_count + flushed_stdout + flushed_stderr);
    std::process::set_exit_code(0);
    alloc::allocator::dealloc(grown, 32, 4);
    alloc::allocator::alloc_failed(64, 8);
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
