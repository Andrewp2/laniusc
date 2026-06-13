use laniusc::compiler::{
    RUNTIME_BOUND_API_DIAGNOSTICS,
    RUNTIME_BOUND_API_SELECTOR_KINDS,
    RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS,
    RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    diagnostic_registry,
    runtime_bound_api_diagnostic_info,
    runtime_service_boundary_diagnostic_info,
};

use crate::cli::common::{
    LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_VERSION,
};

pub(super) fn diagnostic_runtime_api_json_pretty(
    api_name: &str,
) -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let requested_api = diagnostic_runtime_selector(api_name);
    let (matched_by, runtime_bound_api) = diagnostic_runtime_api_for_selector(requested_api);
    let runtime_service_boundary =
        runtime_bound_api.and_then(|api| runtime_service_boundary_diagnostic_info(api.service_id));
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_VERSION,
        "schema_name": LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "requested_api": requested_api,
        "known": runtime_bound_api.is_some(),
        "matched_by": matched_by,
        "accepted_selector_kinds": RUNTIME_BOUND_API_SELECTOR_KINDS,
        "service_accepted_selector_kinds": RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        "selector_examples": runtime_api_selector_examples_json(),
        "canonical_api_name": runtime_bound_api.map(|api| api.api_name),
        "diagnostic_code": runtime_bound_api.map(|api| api.diagnostic_code),
        "runtime_bound_api": runtime_bound_api,
        "runtime_service_boundary": runtime_service_boundary,
        "runtime_api_index_command": "laniusc diagnostics runtime-apis",
        "runtime_service_index_command": "laniusc diagnostics runtime-services",
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

fn diagnostic_runtime_api_for_selector(
    requested_api: &str,
) -> (
    Option<&'static str>,
    Option<&'static laniusc::compiler::RuntimeBoundApiDiagnosticInfo>,
) {
    if let Some(api) = runtime_bound_api_diagnostic_info(requested_api) {
        return (Some("api_name"), Some(api));
    }
    let Some((service_name, api_leaf)) = requested_api.rsplit_once("::") else {
        return (None, None);
    };
    if service_name.contains("::") {
        return (None, None);
    }
    if let Some(api) = RUNTIME_BOUND_API_DIAGNOSTICS.iter().find(|api| {
        api.service_name == service_name && runtime_api_leaf_name(api.api_name) == api_leaf
    }) {
        return (Some("service_api_name"), Some(api));
    }
    (None, None)
}

fn runtime_api_leaf_name(api_name: &str) -> &str {
    api_name
        .rsplit_once("::")
        .map(|(_, leaf_name)| leaf_name)
        .unwrap_or(api_name)
}

pub(super) fn diagnostic_runtime_apis_json_pretty() -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_VERSION,
        "schema_name": LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "diagnostic_code": "LNC0038",
        "explain_command": "laniusc diagnostics explain LNC0038",
        "runtime_api_query_command": "laniusc diagnostics runtime-api API",
        "accepted_selector_kinds": RUNTIME_BOUND_API_SELECTOR_KINDS,
        "service_accepted_selector_kinds": RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        "selector_examples": runtime_api_selector_examples_json(),
        "service_selector_examples": runtime_service_selector_examples_json(),
        "runtime_bound_api_count": RUNTIME_BOUND_API_DIAGNOSTICS.len(),
        "runtime_service_boundary_count": RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len(),
        "runtime_bound_apis": RUNTIME_BOUND_API_DIAGNOSTICS,
        "runtime_service_boundaries": RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS,
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

pub(super) fn diagnostic_runtime_service_json_pretty(
    service_selector: &str,
) -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let requested_service = diagnostic_runtime_selector(service_selector);
    let (matched_by, runtime_service_boundary) =
        diagnostic_runtime_service_boundary_for_selector(requested_service);
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_VERSION,
        "schema_name": LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "requested_service": requested_service,
        "known": runtime_service_boundary.is_some(),
        "matched_by": matched_by,
        "accepted_selector_kinds": RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        "runtime_api_accepted_selector_kinds": RUNTIME_BOUND_API_SELECTOR_KINDS,
        "selector_examples": runtime_service_selector_examples_json(),
        "diagnostic_code": runtime_service_boundary.map(|service| service.diagnostic_code),
        "runtime_service_boundary": runtime_service_boundary,
        "runtime_api_index_command": "laniusc diagnostics runtime-apis",
        "runtime_service_index_command": "laniusc diagnostics runtime-services",
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

fn diagnostic_runtime_service_boundary_for_selector(
    requested_service: &str,
) -> (
    Option<&'static str>,
    Option<&'static laniusc::compiler::RuntimeServiceBoundaryDiagnosticInfo>,
) {
    if let Ok(service_id) = requested_service.parse::<u32>() {
        return match runtime_service_boundary_diagnostic_info(service_id) {
            Some(service) => (Some("service_id"), Some(service)),
            None => (None, None),
        };
    }
    if let Some(service) = RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|service| service.service_name == requested_service)
    {
        return (Some("service_name"), Some(service));
    }
    if let Some(service) = RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|service| service.module_path == requested_service)
    {
        return (Some("module_path"), Some(service));
    }
    if let Some(service) = RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|service| service.capability_constant == requested_service)
    {
        return (Some("capability_constant"), Some(service));
    }
    if let Some(service) = RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|service| service.status_probe == requested_service)
    {
        return (Some("status_probe"), Some(service));
    }
    if let Some(service) = RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|service| service.binding_probe == requested_service)
    {
        return (Some("binding_probe"), Some(service));
    }
    let (api_matched_by, runtime_bound_api) =
        diagnostic_runtime_api_for_selector(requested_service);
    if let (Some(api_matched_by), Some(api)) = (api_matched_by, runtime_bound_api) {
        return match runtime_service_boundary_diagnostic_info(api.service_id) {
            Some(service) => (Some(api_matched_by), Some(service)),
            None => (None, None),
        };
    }
    (None, None)
}

pub(super) fn diagnostic_runtime_service_apis_json_pretty(
    service_selector: &str,
) -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let requested_service = diagnostic_runtime_selector(service_selector);
    let (matched_by, runtime_service_boundary) =
        diagnostic_runtime_service_boundary_for_selector(requested_service);
    let runtime_bound_apis = runtime_service_boundary
        .map(|service| {
            RUNTIME_BOUND_API_DIAGNOSTICS
                .iter()
                .filter(|api| api.service_id == service.service_id)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_VERSION,
        "schema_name": LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "requested_service": requested_service,
        "known": runtime_service_boundary.is_some(),
        "matched_by": matched_by,
        "accepted_selector_kinds": RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        "runtime_api_accepted_selector_kinds": RUNTIME_BOUND_API_SELECTOR_KINDS,
        "selector_examples": runtime_service_selector_examples_json(),
        "diagnostic_code": runtime_service_boundary.map(|service| service.diagnostic_code),
        "runtime_service_boundary": runtime_service_boundary,
        "runtime_bound_api_count": runtime_bound_apis.len(),
        "runtime_bound_apis": runtime_bound_apis,
        "runtime_api_index_command": "laniusc diagnostics runtime-apis",
        "runtime_service_query_command": "laniusc diagnostics runtime-service SERVICE",
        "runtime_service_index_command": "laniusc diagnostics runtime-services",
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

pub(super) fn diagnostic_runtime_services_json_pretty() -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_VERSION,
        "schema_name": LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "diagnostic_code": "LNC0038",
        "explain_command": "laniusc diagnostics explain LNC0038",
        "runtime_api_index_command": "laniusc diagnostics runtime-apis",
        "accepted_selector_kinds": RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        "runtime_api_accepted_selector_kinds": RUNTIME_BOUND_API_SELECTOR_KINDS,
        "selector_examples": runtime_service_selector_examples_json(),
        "runtime_service_boundary_count": RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len(),
        "runtime_service_boundaries": RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS,
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

fn runtime_api_selector_examples_json() -> serde_json::Value {
    serde_json::json!({
        "api_name": "std::io::print_i32",
        "service_api_name": "stdio::print_i32"
    })
}

fn runtime_service_selector_examples_json() -> serde_json::Value {
    serde_json::json!({
        "service_id": laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        "service_name": "stdio",
        "module_path": "std::io",
        "capability_constant": "STDIO_HAS_RUNTIME_BINDING",
        "status_probe": "stdio_service_status()",
        "binding_probe": "stdio_requires_runtime_binding()",
        "api_name": "std::io::print_i32",
        "service_api_name": "stdio::print_i32"
    })
}

fn diagnostic_runtime_selector(selector: &str) -> &str {
    let selector = selector.trim();
    for quote in ['`', '"', '\''] {
        if let Some(inner) = selector
            .strip_prefix(quote)
            .and_then(|inner| inner.strip_suffix(quote))
        {
            return inner.trim();
        }
    }
    selector
}
