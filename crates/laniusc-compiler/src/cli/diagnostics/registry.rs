use crate::{
    cli::common::{
        LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION,
        LANIUS_DIAGNOSTIC_CODES_SCHEMA_VERSION,
    },
    compiler::{
        DiagnosticCodeInfo,
        diagnostic_explain_command,
        diagnostic_explanation,
        diagnostic_registry,
    },
};

const DIAGNOSTIC_CODES_SCHEMA_NAME: &str = "laniusc.diagnostics.codes";
const DIAGNOSTIC_CODE_SCHEMA_NAME: &str = "laniusc.diagnostics.code";
const DIAGNOSTIC_CODE_SCHEMA_VERSION: u32 = 2;
const DIAGNOSTIC_CATEGORIES_SCHEMA_NAME: &str = "laniusc.diagnostics.categories";
const DIAGNOSTIC_CODE_SELECTOR_EXAMPLES: &[&str] = &[
    "LNC0018",
    "lnc0018",
    "error[LNC0018]: unsupported CLI option value",
];
const DIAGNOSTIC_CODE_SELECTOR_PATTERNS: &[&str] = &[
    "LNCdddd",
    "lncdddd",
    "copied text containing one LNCdddd token",
];

/// Returns the diagnostic-code index used by tooling and `diagnostics codes`.
pub(super) fn diagnostic_codes_json_pretty() -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let codes = registry
        .codes
        .iter()
        .map(diagnostic_code_row_json)
        .collect::<Vec<_>>();
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_CODES_SCHEMA_VERSION,
        "schema_name": DIAGNOSTIC_CODES_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "code_count": codes.len(),
        "codes": codes,
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

/// Returns one diagnostic-code record selected by a stable code-like string.
pub(super) fn diagnostic_code_json_pretty(code: &str) -> Result<String, serde_json::Error> {
    let explanation = diagnostic_explanation(code);
    let diagnostic = explanation
        .diagnostic
        .as_ref()
        .map(diagnostic_code_row_json);
    let document = serde_json::json!({
        "schema_version": DIAGNOSTIC_CODE_SCHEMA_VERSION,
        "schema_name": DIAGNOSTIC_CODE_SCHEMA_NAME,
        "registry_schema_version": explanation.registry_schema_version,
        "requested_code": explanation.requested_code,
        "known": explanation.known,
        "diagnostic": diagnostic,
        "explain_command": diagnostic_explain_command(&explanation.requested_code),
        "accepted_selector_examples": DIAGNOSTIC_CODE_SELECTOR_EXAMPLES,
        "accepted_selector_patterns": DIAGNOSTIC_CODE_SELECTOR_PATTERNS,
        "code_index_command": "laniusc diagnostics codes",
        "registry_command": "laniusc diagnostics registry",
        "no_run_guards": explanation.no_run_guards
    });
    serde_json::to_string_pretty(&document)
}

/// Returns diagnostic categories grouped with their stable codes.
pub(super) fn diagnostic_categories_json_pretty() -> Result<String, serde_json::Error> {
    let registry = diagnostic_registry();
    let categories = registry
        .categories
        .iter()
        .map(|category| {
            let codes = registry
                .codes
                .iter()
                .filter(|code| code.category == *category)
                .map(diagnostic_code_row_json)
                .collect::<Vec<_>>();
            let unsupported_feature_codes = registry
                .unsupported_features
                .iter()
                .filter_map(|feature| {
                    registry
                        .codes
                        .iter()
                        .any(|code| code.code == feature.code && code.category == *category)
                        .then_some(feature.code)
                })
                .collect::<Vec<_>>();
            serde_json::json!({
                "name": category,
                "code_count": codes.len(),
                "codes": codes,
                "unsupported_feature_codes": unsupported_feature_codes,
            })
        })
        .collect::<Vec<_>>();
    let document = serde_json::json!({
        "schema_version": LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION,
        "schema_name": DIAGNOSTIC_CATEGORIES_SCHEMA_NAME,
        "registry_schema_version": registry.schema_version,
        "category_count": categories.len(),
        "categories": categories,
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    });
    serde_json::to_string_pretty(&document)
}

fn diagnostic_code_row_json(code: &DiagnosticCodeInfo) -> serde_json::Value {
    serde_json::json!({
        "code": code.code,
        "title": code.title,
        "category": code.category,
        "primary_label_policy": code.primary_label_policy,
        "default_severity": code.default_severity,
        "lsp_source": code.lsp_source,
        "lsp_severity": code.lsp_severity,
        "explain_command": diagnostic_explain_command(code.code),
    })
}
