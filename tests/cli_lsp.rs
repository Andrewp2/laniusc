use std::{
    io::Write,
    path::PathBuf,
    process::{Child, Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

const CLI_LSP_TIMEOUT: Duration = Duration::from_secs(30);
const CHILD_PROCESS_POLL_INTERVAL: Duration = Duration::from_millis(2);

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_lsp_capabilities_reports_no_run_diagnostic_contract() {
    let mut command = Command::new(laniusc_bin());
    command.arg("lsp").arg("capabilities");
    let output =
        command_output_with_timeout("laniusc lsp capabilities", &mut command, CLI_LSP_TIMEOUT);

    assert!(
        output.status.success(),
        "lsp capabilities should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "lsp capabilities should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("capabilities output should be JSON");
    assert_eq!(document["schema_name"], "laniusc.lsp.capabilities");
    assert_eq!(document["schema_version"], 15);
    assert_eq!(document["status"], "stdio-handshake-ready");
    assert_eq!(document["server"]["name"], "laniusc");
    assert_eq!(document["server"]["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(document["server"]["stdio"], true);
    assert_lsp_supported_methods_include(
        &document["server"]["stdio_methods"],
        &[
            "initialize",
            "initialized",
            "textDocument/didOpen",
            "textDocument/didChange",
            "textDocument/didClose",
            "textDocument/formatting",
            "textDocument/diagnostic",
            "shutdown",
            "exit",
        ],
    );
    assert_lsp_supported_methods_do_not_include(
        &document["server"]["stdio_methods"],
        &["textDocument/rangeFormatting", "workspace/symbol"],
    );
    assert_eq!(document["language_id"], "lanius");
    assert_eq!(document["position_encoding"], "utf-16");
    assert_eq!(document["diagnostic_source"], "laniusc");
    assert_eq!(
        document["diagnostic_registry"]["schema_version"],
        laniusc_compiler::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        document["diagnostic_registry"]["no_run_guards"]["source_scanning"],
        false
    );
    assert_lsp_diagnostic_formats(&document["diagnostic_formats"]);
    assert_lsp_distribution_contract(&document["distribution"]);
    assert_lsp_transport_metadata(&document["transport"]);
    assert_lsp_error_data_metadata(&document["error_data"]);
    assert_eq!(document["document_sync"]["open_close"], true);
    assert_eq!(document["document_sync"]["change"], 1);
    assert_eq!(document["document_sync"]["change_kind"], "full");
    assert_eq!(document["document_sync"]["incremental_changes"], false);
    assert_lsp_workspace_metadata(&document["workspace"]);
    assert_eq!(document["formatting"]["document_formatting_provider"], true);
    assert_formatter_policy(&document["formatting"]["policy"]);
    assert_eq!(document["formatting"]["method"], "textDocument/formatting");
    assert_eq!(
        document["formatting"]["edit_strategy"],
        "single full-document replacement when formatting changes"
    );
    assert_eq!(document["formatting"]["range_formatting_provider"], false);
    assert_lsp_formatting_request_options(&document["formatting"]["request_options"]);
    assert_eq!(document["formatting"]["cli_command"], "laniusc fmt --stdin");
    assert_eq!(
        document["formatting"]["cli_check_command"],
        "laniusc fmt --stdin --check"
    );
    assert_eq!(
        document["formatting"]["formatter_contract"],
        "unstable-alpha lexical full-document formatter"
    );
    assert_eq!(document["formatting"]["source_compilation"], false);
    assert_eq!(document["formatting"]["source_scanning"], false);
    assert_eq!(document["formatting"]["gpu_device_creation"], false);
    assert_eq!(document["formatting"]["target_codegen"], false);
    assert_lsp_lifecycle_metadata(&document["lifecycle"]);
    assert_lsp_document_diagnostics_metadata(&document["document_diagnostics"]);
    assert_lsp_claim_boundaries(&document["claim_boundaries"]);
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);

    let codes = document["diagnostic_registry"]["codes"]
        .as_array()
        .expect("diagnostic registry should expose code metadata");
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0016"
            && code["category"] == "parsing"
            && code["primary_label_policy"] == "required"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0018"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == document["diagnostic_source"]
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0028"
            && code["title"] == "unsupported LSP method"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == document["diagnostic_source"]
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0029"
            && code["title"] == "invalid LSP message"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == document["diagnostic_source"]
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0033"
            && code["title"] == "invalid generic parameter list"
            && code["category"] == "type checking"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == document["diagnostic_source"]
            && code["lsp_severity"] == 1
    }));

    let unsupported_features = document["diagnostic_registry"]["unsupported_features"]
        .as_array()
        .expect("diagnostic registry should expose unsupported-boundary metadata");
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0017"
            && feature["boundary"] == "x86 backend"
            && feature["next_step"]
                .as_str()
                .is_some_and(|next_step| next_step.contains("--emit=wasm"))
    }));
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0022"
            && feature["boundary"] == "linked-output contract descriptor"
            && feature["next_step"]
                .as_str()
                .is_some_and(|next_step| next_step.contains("target bytes"))
    }));
}

#[test]
fn cli_lsp_serve_handles_initialize_shutdown_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout("laniusc lsp serve --stdio", child, CLI_LSP_TIMEOUT);
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "lsp serve should not print diagnostics during handshake\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(responses.len(), 2, "initialize and shutdown should respond");
    let initialize = responses
        .iter()
        .find(|response| response["id"] == 1)
        .expect("initialize response should be present");
    assert_eq!(initialize["jsonrpc"], "2.0");
    assert_eq!(initialize["result"]["serverInfo"]["name"], "laniusc");
    assert_eq!(
        initialize["result"]["serverInfo"]["version"],
        env!("CARGO_PKG_VERSION")
    );
    assert_eq!(
        initialize["result"]["capabilities"]["positionEncoding"],
        "utf-16"
    );
    assert_eq!(
        initialize["result"]["capabilities"]["textDocumentSync"]["openClose"],
        true
    );
    assert_eq!(
        initialize["result"]["capabilities"]["textDocumentSync"]["change"],
        1
    );
    assert_eq!(
        initialize["result"]["capabilities"]["diagnosticProvider"]["workspaceDiagnostics"],
        false
    );
    assert_eq!(
        initialize["result"]["capabilities"]["documentFormattingProvider"],
        true
    );
    assert_eq!(
        initialize["result"]["capabilities"]["workspaceSymbolProvider"],
        false
    );
    assert_eq!(
        initialize["result"]["capabilities"]["workspace"]["workspaceFolders"]["supported"],
        false
    );
    assert_eq!(
        initialize["result"]["capabilities"]["workspace"]["workspaceFolders"]["changeNotifications"],
        false
    );
    let laniusc = &initialize["result"]["capabilities"]["experimental"]["laniusc"];
    assert_eq!(laniusc["schema_name"], "laniusc.lsp.experimental");
    assert_eq!(laniusc["schema_version"], 13);
    assert_eq!(laniusc["language_id"], "lanius");
    assert_eq!(laniusc["diagnostic_source"], "laniusc");
    assert_eq!(
        laniusc["diagnostic_registry"]["schema_version"],
        laniusc_compiler::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        laniusc["diagnostic_registry"]["no_run_guards"]["source_scanning"],
        false
    );
    assert_lsp_diagnostic_formats(&laniusc["diagnostic_formats"]);
    assert_lsp_distribution_contract(&laniusc["distribution"]);
    assert_lsp_transport_metadata(&laniusc["transport"]);
    assert_lsp_error_data_metadata(&laniusc["error_data"]);
    assert_lsp_workspace_metadata(&laniusc["workspace"]);
    assert_lsp_supported_methods_do_not_include(
        &laniusc["supported_methods"],
        &["textDocument/rangeFormatting", "workspace/symbol"],
    );
    assert_eq!(laniusc["formatting"]["document_formatting_provider"], true);
    assert_formatter_policy(&laniusc["formatting"]["policy"]);
    assert_eq!(laniusc["formatting"]["method"], "textDocument/formatting");
    assert_eq!(
        laniusc["formatting"]["edit_strategy"],
        "single full-document replacement when formatting changes"
    );
    assert_eq!(laniusc["formatting"]["range_formatting_provider"], false);
    assert_lsp_formatting_request_options(&laniusc["formatting"]["request_options"]);
    assert_eq!(laniusc["formatting"]["cli_command"], "laniusc fmt --stdin");
    assert_eq!(
        laniusc["formatting"]["cli_check_command"],
        "laniusc fmt --stdin --check"
    );
    assert_eq!(
        laniusc["formatting"]["formatter_contract"],
        "unstable-alpha lexical full-document formatter"
    );
    assert_eq!(laniusc["formatting"]["source_compilation"], false);
    assert_eq!(laniusc["formatting"]["source_scanning"], false);
    assert_eq!(laniusc["formatting"]["gpu_device_creation"], false);
    assert_eq!(laniusc["formatting"]["target_codegen"], false);
    assert_lsp_lifecycle_metadata(&laniusc["lifecycle"]);
    assert_eq!(laniusc["document_diagnostics"], true);
    assert_lsp_document_diagnostics_metadata(&laniusc["document_diagnostics_metadata"]);
    assert_lsp_claim_boundaries(&laniusc["claim_boundaries"]);
    assert_eq!(laniusc["no_run_guards"]["source_compilation"], false);
    assert_eq!(laniusc["no_run_guards"]["source_scanning"], false);
    assert_eq!(laniusc["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(laniusc["no_run_guards"]["target_codegen"], false);

    let shutdown = responses
        .iter()
        .find(|response| response["id"] == 2)
        .expect("shutdown response should be present");
    assert_eq!(shutdown["jsonrpc"], "2.0");
    assert!(shutdown["result"].is_null());
}

#[test]
fn cli_lsp_serve_accepts_exit_before_initialize_without_response() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve pre-initialize exit notification",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly when exit arrives before initialize\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "pre-initialize exit notification should not produce a JSON-RPC response\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        output.stderr.is_empty(),
        "pre-initialize exit should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_lsp_serve_rejects_reinitialize_without_resetting_session() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/reinitialize.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": "fn fn main(){return 1;}"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 8,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/reinitialize.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve reinitialize rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after rejecting a repeated initialize request\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "repeated initialize rejection should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        4,
        "initial initialize, repeated initialize, formatting, and shutdown should respond"
    );
    let repeated_initialize = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("repeated initialize response should be present");
    assert_eq!(repeated_initialize["jsonrpc"], "2.0");
    assert_eq!(repeated_initialize["error"]["code"], -32600);
    assert_eq!(
        repeated_initialize["error"]["message"],
        "LSP server is already initialized"
    );
    assert_invalid_lsp_message_diagnostic(
        &repeated_initialize["error"]["data"],
        "initialize request has already completed",
    );
    assert_eq!(
        repeated_initialize["error"]["data"]["failure_boundary"],
        "lsp-lifecycle-reinitialize"
    );

    let formatting = responses
        .iter()
        .find(|response| response["id"] == 8)
        .expect("formatting response should be present after repeated initialize rejection");
    assert_eq!(formatting["jsonrpc"], "2.0");
    assert_eq!(
        formatting["result"]
            .as_array()
            .expect("formatting should still see the already-open document")
            .len(),
        1,
        "repeated initialize rejection should not reset open documents"
    );
}

#[test]
fn cli_lsp_serve_does_not_answer_shutdown_notification() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve shutdown notification",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after shutdown notification\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "shutdown notification should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        1,
        "shutdown notification and exit notification should not produce responses"
    );
    assert_eq!(responses[0]["jsonrpc"], "2.0");
    assert_eq!(responses[0]["id"], 1);
    assert!(responses[0]["result"]["capabilities"].is_object());
}

#[test]
fn cli_lsp_serve_rejects_requests_after_shutdown_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/after-shutdown.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve post-shutdown request rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after rejecting a post-shutdown request\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "post-shutdown LSP request rejection should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, shutdown, and post-shutdown request should respond"
    );
    let rejected = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("post-shutdown request response should be present");
    assert_eq!(rejected["jsonrpc"], "2.0");
    assert_eq!(rejected["error"]["code"], -32600);
    assert_eq!(rejected["error"]["message"], "LSP server has shut down");
    assert_invalid_lsp_message_diagnostic(&rejected["error"]["data"], "only exit is accepted");
    assert_eq!(
        rejected["error"]["data"]["failure_boundary"],
        "lsp-lifecycle-post-shutdown"
    );
}

#[test]
fn cli_lsp_serve_rejects_requests_before_initialize_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/pre-initialize.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": "fn main(){return 0;}"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/pre-initialize.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 8,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/pre-initialize.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve pre-initialize request rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after rejecting a pre-initialize request\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "pre-initialize LSP request rejection should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        4,
        "pre-initialize request, initialize, post-initialize formatting, and shutdown should respond"
    );
    let pre_initialize = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("pre-initialize request response should be present");
    assert_eq!(pre_initialize["jsonrpc"], "2.0");
    assert_eq!(pre_initialize["error"]["code"], -32002);
    assert_eq!(
        pre_initialize["error"]["message"],
        "LSP server is not initialized"
    );
    assert_invalid_lsp_message_diagnostic(
        &pre_initialize["error"]["data"],
        "initialize request has not completed",
    );
    assert_eq!(
        pre_initialize["error"]["data"]["failure_boundary"],
        "lsp-lifecycle-pre-initialize"
    );
    assert_lsp_supported_methods_include(
        &pre_initialize["error"]["data"]["allowed_methods"],
        &["initialize", "exit"],
    );

    let post_initialize = responses
        .iter()
        .find(|response| response["id"] == 8)
        .expect("post-initialize formatting response should be present");
    assert_eq!(post_initialize["jsonrpc"], "2.0");
    assert_eq!(post_initialize["error"]["code"], -32602);
    assert_eq!(
        post_initialize["error"]["message"],
        "invalid textDocument/formatting parameters"
    );
    assert_invalid_lsp_message_diagnostic(
        &post_initialize["error"]["data"],
        "textDocument/formatting requested a document that is not open",
    );
}

#[test]
fn cli_lsp_serve_accepts_document_lifecycle_notifications_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "initialized",
                "params": {}
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/lifecycle.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": "fn fn main() {}\n"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/lifecycle.lani",
                        "version": 2
                    },
                    "contentChanges": [
                        { "text": "fn main() {\n    return 0;\n}\n" }
                    ]
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didClose",
                "params": {
                    "textDocument": { "uri": "file:///tmp/lifecycle.lani" }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve document lifecycle notifications",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after document lifecycle notifications\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "document lifecycle notifications should not print diagnostics or compile source\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        2,
        "only initialize and shutdown should respond to notification-only document lifecycle"
    );
    assert!(
        responses.iter().any(|response| response["id"] == 1),
        "initialize response should be present"
    );
    assert!(
        responses.iter().any(|response| response["id"] == 2),
        "shutdown response should be present"
    );
}

#[test]
fn cli_lsp_serve_rejects_wrong_language_id_without_opening_document() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/wrong-language.lani",
                        "languageId": "rust",
                        "version": 1,
                        "text": "fn main(){return 1;}"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 8,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/wrong-language.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve wrong language id didOpen rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after rejecting a wrong-language didOpen\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "wrong-language didOpen rejection should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        4,
        "initialize, rejected didOpen, rejected formatting, and shutdown should respond"
    );
    let rejected_open = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("rejected didOpen response should be present");
    assert_eq!(rejected_open["jsonrpc"], "2.0");
    assert_eq!(rejected_open["error"]["code"], -32602);
    assert_eq!(
        rejected_open["error"]["message"],
        "invalid textDocument/didOpen parameters"
    );
    assert_invalid_lsp_message_diagnostic(&rejected_open["error"]["data"], "expected \"lanius\"");

    let formatting = responses
        .iter()
        .find(|response| response["id"] == 8)
        .expect("formatting response should be present after rejected didOpen");
    assert_eq!(formatting["jsonrpc"], "2.0");
    assert_eq!(formatting["error"]["code"], -32602);
    assert_eq!(
        formatting["error"]["message"],
        "invalid textDocument/formatting parameters"
    );
    assert_invalid_lsp_message_diagnostic(
        &formatting["error"]["data"],
        "textDocument/formatting requested a document that is not open",
    );
}

#[test]
fn cli_lsp_serve_did_change_notification_does_not_implicitly_open_document() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/not-open-change.lani",
                        "version": 2
                    },
                    "contentChanges": [
                        { "text": "fn main(){return 1;}" }
                    ]
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/not-open-change.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve unopened didChange notification",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after an unopened didChange notification\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unopened didChange notifications should not print diagnostics or compile source\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, rejected formatting request, and shutdown should respond"
    );
    let formatting = responses
        .iter()
        .find(|response| response["id"] == 3)
        .expect("formatting response should be present");
    assert_eq!(formatting["jsonrpc"], "2.0");
    assert_eq!(formatting["error"]["code"], -32602);
    assert_eq!(
        formatting["error"]["message"],
        "invalid textDocument/formatting parameters"
    );
    assert_invalid_lsp_message_diagnostic(
        &formatting["error"]["data"],
        "textDocument/formatting requested a document that is not open",
    );
}

#[test]
fn cli_lsp_serve_returns_document_formatting_edits_without_compiling_source() {
    let original = "fn fn main(){// \u{1f600}\r\nreturn 1;}";
    let formatted = "\
fn fn main() {
    // \u{1f600}
    return 1;
}
";
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/formatting.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": original
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/formatting.lani",
                        "version": 2
                    },
                    "contentChanges": [
                        { "text": formatted }
                    ]
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 4,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve document formatting",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after document formatting\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "document formatting should stay inside LSP responses and not compile source\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        4,
        "initialize, two formatting requests, and shutdown should respond"
    );
    let formatting = responses
        .iter()
        .find(|response| response["id"] == 3)
        .expect("formatting response should be present");
    assert_eq!(formatting["jsonrpc"], "2.0");
    let edits = formatting["result"]
        .as_array()
        .expect("formatting response should return an edit array");
    assert_eq!(
        edits.len(),
        1,
        "unformatted source should get one full-document edit"
    );
    assert_eq!(edits[0]["range"]["start"]["line"], 0);
    assert_eq!(edits[0]["range"]["start"]["character"], 0);
    assert_eq!(edits[0]["range"]["end"]["line"], 1);
    assert_eq!(edits[0]["range"]["end"]["character"], 10);
    assert_eq!(edits[0]["newText"], formatted);

    let no_change = responses
        .iter()
        .find(|response| response["id"] == 4)
        .expect("second formatting response should be present");
    assert_eq!(no_change["jsonrpc"], "2.0");
    assert_eq!(
        no_change["result"]
            .as_array()
            .expect("formatted source response should return an edit array")
            .len(),
        0,
        "already-formatted source should not get a no-op edit"
    );
}

#[test]
fn cli_lsp_serve_rejects_formatting_requests_without_options_without_mutating_document() {
    let original = "fn main(){return 1;}";
    let formatted = "\
fn main() {
    return 1;
}
";
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/formatting-options.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": original
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting-options.lani" }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 8,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting-options.lani" },
                    "options": { "tabSize": 0, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 9,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting-options.lani" },
                    "options": { "tabSize": 4, "insertSpaces": "yes" }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 11,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting-options.lani" },
                    "options": { "tabSize": 2, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 12,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting-options.lani" },
                    "options": { "tabSize": 4, "insertSpaces": false }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 10,
                "method": "textDocument/formatting",
                "params": {
                    "textDocument": { "uri": "file:///tmp/formatting-options.lani" },
                    "options": { "tabSize": 4, "insertSpaces": true }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve formatting options rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after rejecting malformed formatting params\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "malformed formatting params should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        8,
        "initialize, five rejected formatting requests, valid formatting, and shutdown should respond"
    );
    assert_formatting_param_error(&responses, 7, "params.options object");
    assert_formatting_param_error(&responses, 8, "params.options.tabSize");
    assert_formatting_param_error(&responses, 9, "params.options.insertSpaces");
    assert_formatting_param_error(&responses, 11, "tabSize must be 4");
    assert_formatting_param_error(&responses, 12, "insertSpaces must be true");

    let valid_formatting = responses
        .iter()
        .find(|response| response["id"] == 10)
        .expect("valid formatting response should be present after rejected request");
    assert_eq!(valid_formatting["jsonrpc"], "2.0");
    let edits = valid_formatting["result"]
        .as_array()
        .expect("valid formatting response should return an edit array");
    assert_eq!(
        edits.len(),
        1,
        "malformed formatting request should not mutate the open document"
    );
    assert_eq!(edits[0]["newText"], formatted);
}

#[test]
fn cli_lsp_serve_rejects_incremental_document_changes_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/incremental.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": "fn main() {\n    return 0;\n}\n"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/incremental.lani",
                        "version": 2
                    },
                    "contentChanges": [
                        {
                            "range": {
                                "start": { "line": 1, "character": 11 },
                                "end": { "line": 1, "character": 12 }
                            },
                            "rangeLength": 1,
                            "text": "1"
                        }
                    ]
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve incremental didChange rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after rejecting an incremental change\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "incremental didChange rejection should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, rejected didChange, and shutdown should respond"
    );
    let rejected_change = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("rejected didChange response should be present");
    assert_eq!(rejected_change["jsonrpc"], "2.0");
    assert_eq!(rejected_change["error"]["code"], -32602);
    assert_eq!(
        rejected_change["error"]["message"],
        "invalid textDocument/didChange parameters"
    );
    assert_invalid_lsp_message_diagnostic(
        &rejected_change["error"]["data"],
        "ranged incremental changes are not supported",
    );
}

#[test]
fn cli_lsp_serve_rejects_full_document_change_items_without_text_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/full-change-text.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": "fn main() {\n    return 0;\n}\n"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/full-change-text.lani",
                        "version": 2
                    },
                    "contentChanges": [
                        { "text": "fn main() {\n    return 1;\n}\n" },
                        { "metadata": "not a document change" }
                    ]
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve malformed full-document didChange rejection",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after rejecting a malformed full-document change\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "malformed didChange rejection should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, rejected didChange, and shutdown should respond"
    );
    let rejected_change = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("rejected didChange response should be present");
    assert_eq!(rejected_change["jsonrpc"], "2.0");
    assert_eq!(rejected_change["error"]["code"], -32602);
    assert_eq!(
        rejected_change["error"]["message"],
        "invalid textDocument/didChange parameters"
    );
    assert_invalid_lsp_message_diagnostic(
        &rejected_change["error"]["data"],
        "contentChanges[1] did not include string text",
    );
}

#[test]
fn cli_lsp_serve_reports_unsupported_method_with_stable_diagnostic_data() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "textDocument/completion",
                "params": {
                    "textDocument": { "uri": "file:///tmp/app.lani" },
                    "position": { "line": 0, "character": 0 }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout("laniusc lsp serve --stdio", child, CLI_LSP_TIMEOUT);
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after unsupported request\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "lsp serve should keep unsupported-method diagnostics inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, unsupported request, and shutdown should respond"
    );
    let unsupported = responses
        .iter()
        .find(|response| response["id"] == 7)
        .expect("unsupported method response should be present");
    assert_eq!(unsupported["jsonrpc"], "2.0");
    assert_eq!(unsupported["error"]["code"], -32601);
    assert_eq!(unsupported["error"]["message"], "unsupported LSP method");

    let data = &unsupported["error"]["data"];
    assert_eq!(data["schema_name"], "laniusc.lsp.error-data");
    assert_eq!(data["schema_version"], 2);
    assert_eq!(data["failure_boundary"], "lsp-method-dispatch");
    assert_eq!(data["requested_method"], "textDocument/completion");
    assert_lsp_supported_methods_include(
        &data["supported_methods"],
        &[
            "initialize",
            "initialized",
            "textDocument/didOpen",
            "textDocument/didChange",
            "textDocument/didClose",
            "textDocument/formatting",
            "textDocument/diagnostic",
            "shutdown",
            "exit",
        ],
    );
    assert_eq!(data["no_run_guards"]["source_compilation"], false);
    assert_eq!(data["no_run_guards"]["source_scanning"], false);
    assert_eq!(data["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(data["no_run_guards"]["target_codegen"], false);

    let diagnostic = &data["diagnostic"];
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0028");
    assert_eq!(diagnostic["title"], "unsupported LSP method");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unsupported LSP method");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0028"
    );
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unsupported-method diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("textDocument/completion")),
        "diagnostic notes should identify the unsupported method"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("textDocument/diagnostic")),
        "diagnostic notes should list supported methods"
    );
}

#[test]
fn cli_lsp_serve_ignores_unsupported_notifications_without_protocol_response() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/completion",
                "params": {
                    "textDocument": { "uri": "file:///tmp/notification.lani" },
                    "position": { "line": 0, "character": 0 }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve unsupported notification",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after an unsupported notification\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unsupported LSP notifications should not escape to stderr\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        2,
        "unsupported notifications should not produce JSON-RPC responses"
    );
    let initialize = responses
        .iter()
        .find(|response| response["id"] == 1)
        .expect("initialize response should be present");
    assert_eq!(initialize["jsonrpc"], "2.0");
    assert!(initialize["result"]["capabilities"].is_object());

    let shutdown = responses
        .iter()
        .find(|response| response["id"] == 2)
        .expect("shutdown response should be present");
    assert_eq!(shutdown["jsonrpc"], "2.0");
    assert!(shutdown["result"].is_null());
}

#[test]
fn cli_lsp_serve_returns_document_diagnostics_for_opened_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": "file:///tmp/broken.lani",
                        "languageId": "lanius",
                        "version": 1,
                        "text": "fn fn main() {}\n"
                    }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "textDocument/diagnostic",
                "params": {
                    "textDocument": { "uri": "file:///tmp/broken.lani" }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout("laniusc lsp serve --stdio", child, CLI_LSP_TIMEOUT);
    assert!(
        output.status.success(),
        "lsp serve should exit cleanly after document diagnostics\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "document diagnostics should stay inside LSP responses\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, diagnostic pull, and shutdown should respond"
    );
    let diagnostic_response = responses
        .iter()
        .find(|response| response["id"] == 3)
        .expect("document diagnostic response should be present");
    assert_eq!(diagnostic_response["jsonrpc"], "2.0");
    assert_eq!(diagnostic_response["result"]["kind"], "full");
    let items = diagnostic_response["result"]["items"]
        .as_array()
        .expect("document diagnostic response should include diagnostic items");
    assert!(
        !items.is_empty(),
        "malformed opened source should produce at least one diagnostic"
    );
    let diagnostic = &items[0];
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["code"], "LNC0016");
    assert_eq!(diagnostic["data"]["title"], "syntax error");
    assert_eq!(diagnostic["data"]["category"], "parsing");
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc_compiler::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc_compiler::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["explain_command"],
        "laniusc diagnostics explain LNC0016"
    );
    assert_eq!(
        diagnostic["data"]["primary_label"]["path"],
        "/tmp/broken.lani"
    );
    assert!(diagnostic["range"]["start"]["line"].is_number());
    assert!(diagnostic["range"]["start"]["character"].is_number());
    assert!(diagnostic["range"]["end"]["line"].is_number());
    assert!(diagnostic["range"]["end"]["character"].is_number());
}

#[test]
fn cli_lsp_serve_rejects_unopened_document_diagnostic_without_compiling_source() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "textDocument/diagnostic",
                "params": {
                    "textDocument": { "uri": "file:///tmp/not-open.lani" }
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve unopened document diagnostic",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after unopened document diagnostics\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unopened document diagnostics should be reported inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "initialize, rejected diagnostic pull, and shutdown should respond"
    );
    let diagnostic_response = responses
        .iter()
        .find(|response| response["id"] == 3)
        .expect("rejected diagnostic response should be present");
    assert_eq!(diagnostic_response["jsonrpc"], "2.0");
    assert_eq!(diagnostic_response["error"]["code"], -32602);
    assert_eq!(
        diagnostic_response["error"]["message"],
        "invalid textDocument/diagnostic parameters"
    );
    assert_invalid_lsp_message_diagnostic(
        &diagnostic_response["error"]["data"],
        "textDocument/diagnostic requested a document that is not open",
    );
}

#[test]
fn cli_lsp_serve_reports_malformed_framing_with_stable_diagnostic_data() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        stdin
            .write_all(b"X-Lanius-Test: missing-content-length\r\n\r\n")
            .expect("write malformed LSP frame");
        stdin.flush().expect("flush malformed LSP frame");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve malformed framing",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep running after malformed framing\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "malformed LSP framing should be reported inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        2,
        "malformed frame and shutdown should both produce responses"
    );

    let framing_error = responses
        .iter()
        .find(|response| response["id"].is_null() && response.get("error").is_some())
        .expect("malformed-frame response should be present");
    assert_eq!(framing_error["jsonrpc"], "2.0");
    assert_eq!(framing_error["error"]["code"], -32700);
    assert_eq!(framing_error["error"]["message"], "invalid LSP frame");
    assert_invalid_lsp_message_diagnostic(
        &framing_error["error"]["data"],
        "LSP message missing Content-Length header",
    );

    let shutdown = responses
        .iter()
        .find(|response| response["id"] == 2)
        .expect("shutdown response should be present after malformed frame");
    assert_eq!(shutdown["jsonrpc"], "2.0");
    assert!(shutdown["result"].is_null());
}

#[test]
fn cli_lsp_serve_drains_known_length_invalid_frame_body_before_next_message() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        let invalid_body = serde_json::to_vec(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": 99,
            "method": "shutdown"
        }))
        .expect("serialize invalid-frame body");
        write!(
            stdin,
            "X-Lanius-Test malformed header\r\nContent-Length: {}\r\n\r\n",
            invalid_body.len()
        )
        .expect("write malformed LSP frame header");
        stdin
            .write_all(&invalid_body)
            .expect("write malformed LSP frame body");
        stdin.flush().expect("flush malformed LSP frame");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve malformed framing with known body length",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep the next frame aligned after draining an invalid frame body\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "invalid frame recovery should stay inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "invalid frame, initialize, and shutdown should respond once each"
    );

    let framing_error = responses
        .iter()
        .find(|response| response["id"].is_null() && response.get("error").is_some())
        .expect("malformed-frame response should be present");
    assert_eq!(framing_error["jsonrpc"], "2.0");
    assert_eq!(framing_error["error"]["code"], -32700);
    assert_eq!(framing_error["error"]["message"], "invalid LSP frame");
    assert_invalid_lsp_message_diagnostic(&framing_error["error"]["data"], "malformed LSP header");

    let initialize = responses
        .iter()
        .find(|response| response["id"] == 1)
        .expect("initialize response should be present after invalid frame recovery");
    assert_eq!(initialize["jsonrpc"], "2.0");
    assert_eq!(
        initialize["result"]["serverInfo"]["name"], "laniusc",
        "the invalid frame body should not be processed as shutdown"
    );

    let shutdown = responses
        .iter()
        .find(|response| response["id"] == 2)
        .expect("shutdown response should be present after invalid frame recovery");
    assert_eq!(shutdown["jsonrpc"], "2.0");
    assert!(shutdown["result"].is_null());
}

#[test]
fn cli_lsp_serve_rejects_duplicate_content_length_and_recovers_next_frame() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        let invalid_body = serde_json::to_vec(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": 99,
            "method": "shutdown"
        }))
        .expect("serialize invalid-frame body");
        write!(
            stdin,
            "Content-Length: {}\r\nContent-Length: {}\r\n\r\n",
            invalid_body.len(),
            invalid_body.len()
        )
        .expect("write duplicate Content-Length LSP frame header");
        stdin
            .write_all(&invalid_body)
            .expect("write duplicate Content-Length LSP frame body");
        stdin
            .flush()
            .expect("flush duplicate Content-Length LSP frame");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout(
        "laniusc lsp serve duplicate Content-Length framing",
        child,
        CLI_LSP_TIMEOUT,
    );
    assert!(
        output.status.success(),
        "lsp serve should keep the next frame aligned after rejecting duplicate Content-Length\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "duplicate Content-Length should be reported inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        3,
        "duplicate-length frame, initialize, and shutdown should respond once each"
    );

    let framing_error = responses
        .iter()
        .find(|response| response["id"].is_null() && response.get("error").is_some())
        .expect("duplicate Content-Length response should be present");
    assert_eq!(framing_error["jsonrpc"], "2.0");
    assert_eq!(framing_error["error"]["code"], -32700);
    assert_eq!(framing_error["error"]["message"], "invalid LSP frame");
    assert_invalid_lsp_message_diagnostic(
        &framing_error["error"]["data"],
        "duplicate LSP Content-Length header",
    );

    let initialize = responses
        .iter()
        .find(|response| response["id"] == 1)
        .expect("initialize response should be present after duplicate header recovery");
    assert_eq!(initialize["jsonrpc"], "2.0");
    assert_eq!(
        initialize["result"]["serverInfo"]["name"], "laniusc",
        "the duplicate-length frame body should not be processed as shutdown"
    );

    let shutdown = responses
        .iter()
        .find(|response| response["id"] == 2)
        .expect("shutdown response should be present after duplicate header recovery");
    assert_eq!(shutdown["jsonrpc"], "2.0");
    assert!(shutdown["result"].is_null());
}

#[test]
fn cli_lsp_serve_reports_invalid_messages_with_stable_diagnostic_data() {
    let mut child = Command::new(laniusc_bin())
        .arg("lsp")
        .arg("serve")
        .arg("--stdio")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn laniusc lsp serve --stdio");
    {
        let stdin = child.stdin.as_mut().expect("LSP child should expose stdin");
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": null,
                    "rootUri": null,
                    "capabilities": {}
                }
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 8
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "1.0",
                "id": 10,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!([
                {
                    "jsonrpc": "2.0",
                    "id": 9,
                    "method": "shutdown"
                }
            ]),
        );
        write_raw_lsp_body(stdin, br#"{"jsonrpc":"2.0","id":9,"method":"shutdown""#);
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "shutdown"
            }),
        );
        write_lsp_message(
            stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "method": "exit"
            }),
        );
    }

    let output = child_output_with_timeout("laniusc lsp serve --stdio", child, CLI_LSP_TIMEOUT);
    assert!(
        output.status.success(),
        "lsp serve should keep running after invalid messages\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "invalid LSP messages should be reported inside JSON-RPC error data\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let responses = parse_lsp_responses(&output.stdout);
    assert_eq!(
        responses.len(),
        6,
        "initialize, wrong-version, missing-method, non-object, parse-error, and shutdown should respond"
    );

    let missing_method = responses
        .iter()
        .find(|response| response["id"] == 8)
        .expect("missing-method response should be present");
    assert_eq!(missing_method["jsonrpc"], "2.0");
    assert_eq!(missing_method["error"]["code"], -32600);
    assert_eq!(
        missing_method["error"]["message"],
        "JSON-RPC request must include method"
    );
    assert_invalid_lsp_message_diagnostic(
        &missing_method["error"]["data"],
        "request object did not include a string method field",
    );

    let wrong_version = responses
        .iter()
        .find(|response| response["id"] == 10)
        .expect("wrong JSON-RPC version response should be present");
    assert_eq!(wrong_version["jsonrpc"], "2.0");
    assert_eq!(wrong_version["error"]["code"], -32600);
    assert_eq!(
        wrong_version["error"]["message"],
        "JSON-RPC request must use version 2.0"
    );
    assert_invalid_lsp_message_diagnostic(
        &wrong_version["error"]["data"],
        "request object did not include jsonrpc: \"2.0\"",
    );

    let non_object_request = responses
        .iter()
        .find(|response| {
            response["id"].is_null()
                && response["error"]["message"] == "JSON-RPC message must be a request object"
        })
        .expect("non-object JSON-RPC response should be present");
    assert_eq!(non_object_request["jsonrpc"], "2.0");
    assert_eq!(non_object_request["error"]["code"], -32600);
    assert_invalid_lsp_message_diagnostic(
        &non_object_request["error"]["data"],
        "message body was valid JSON but not a JSON-RPC request object",
    );

    let parse_error = responses
        .iter()
        .find(|response| {
            response["id"].is_null()
                && response["error"]["message"]
                    .as_str()
                    .is_some_and(|message| message.starts_with("invalid JSON-RPC payload"))
        })
        .expect("parse-error response should be present");
    assert_eq!(parse_error["jsonrpc"], "2.0");
    assert_eq!(parse_error["error"]["code"], -32700);
    assert!(
        parse_error["error"]["message"]
            .as_str()
            .is_some_and(|message| message.starts_with("invalid JSON-RPC payload")),
        "parse-error response should describe invalid JSON\nresponse:\n{parse_error}"
    );
    assert_invalid_lsp_message_diagnostic(
        &parse_error["error"]["data"],
        "message body was not valid JSON",
    );
}

fn command_output_with_timeout(context: &str, command: &mut Command, timeout: Duration) -> Output {
    let child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|err| panic!("{context}: spawn command: {err}"));
    child_output_with_timeout(context, child, timeout)
}

fn child_output_with_timeout(context: &str, mut child: Child, timeout: Duration) -> Output {
    let start = Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_)) => return child.wait_with_output().expect("collect command output"),
            Ok(None) => {}
            Err(err) => panic!("{context}: wait for command: {err}"),
        }

        if start.elapsed() >= timeout {
            if let Err(err) = child.kill() {
                panic!("{context}: kill timed-out command: {err}");
            }
            let output = child
                .wait_with_output()
                .expect("collect timed-out command output");
            panic!(
                "{context} timed out after {} ms\nstdout:\n{}\nstderr:\n{}",
                timeout.as_millis(),
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }

        thread::sleep(CHILD_PROCESS_POLL_INTERVAL);
    }
}

fn write_lsp_message(stdin: &mut impl Write, message: &serde_json::Value) {
    let body = serde_json::to_vec(message).expect("serialize LSP test message");
    write_raw_lsp_body(stdin, &body);
}

fn write_raw_lsp_body(stdin: &mut impl Write, body: &[u8]) {
    write!(stdin, "Content-Length: {}\r\n\r\n", body.len()).expect("write LSP frame header");
    stdin.write_all(&body).expect("write LSP frame body");
    stdin.flush().expect("flush LSP frame");
}

fn assert_formatting_param_error(responses: &[serde_json::Value], id: i64, expected_note: &str) {
    let rejected_formatting = responses
        .iter()
        .find(|response| response["id"] == id)
        .expect("rejected formatting response should be present");
    assert_eq!(rejected_formatting["jsonrpc"], "2.0");
    assert_eq!(rejected_formatting["error"]["code"], -32602);
    assert_eq!(
        rejected_formatting["error"]["message"],
        "invalid textDocument/formatting parameters"
    );
    assert_invalid_lsp_message_diagnostic(&rejected_formatting["error"]["data"], expected_note);
}

fn assert_invalid_lsp_message_diagnostic(data: &serde_json::Value, expected_note: &str) {
    assert_eq!(data["schema_name"], "laniusc.lsp.error-data");
    assert_eq!(data["schema_version"], 2);
    assert!(
        data["failure_boundary"]
            .as_str()
            .is_some_and(|boundary| boundary.starts_with("lsp-")),
        "LSP error data should name the protocol or lifecycle failure boundary"
    );
    assert_lsp_supported_methods_include(
        &data["supported_methods"],
        &[
            "initialize",
            "initialized",
            "textDocument/didOpen",
            "textDocument/didChange",
            "textDocument/didClose",
            "textDocument/formatting",
            "textDocument/diagnostic",
            "shutdown",
            "exit",
        ],
    );
    assert_eq!(data["no_run_guards"]["source_compilation"], false);
    assert_eq!(data["no_run_guards"]["source_scanning"], false);
    assert_eq!(data["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(data["no_run_guards"]["target_codegen"], false);

    let diagnostic = &data["diagnostic"];
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0029");
    assert_eq!(diagnostic["title"], "invalid LSP message");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "invalid LSP message");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0029"
    );
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("invalid-message diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains(expected_note)),
        "diagnostic notes should identify the invalid request shape"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("textDocument/diagnostic")),
        "diagnostic notes should list supported methods"
    );
}

fn assert_lsp_error_data_metadata(value: &serde_json::Value) {
    assert_eq!(value["schema_name"], "laniusc.lsp.error-data");
    assert_eq!(value["schema_version"], 2);
    assert_eq!(value["transport"], "json-rpc-error-data");
    assert_eq!(value["diagnostic_field"], "diagnostic");
    assert_eq!(value["supported_methods_field"], "supported_methods");
    assert_eq!(value["no_run_guards_field"], "no_run_guards");
    assert_eq!(value["failure_boundary_field"], "failure_boundary");
    assert_eq!(value["requested_method_field"], "requested_method");
    assert_eq!(
        value["failure_boundaries"]["message_validation"],
        "lsp-protocol-message-validation"
    );
    assert_eq!(
        value["failure_boundaries"]["pre_initialize"],
        "lsp-lifecycle-pre-initialize"
    );
    assert_eq!(
        value["failure_boundaries"]["post_shutdown"],
        "lsp-lifecycle-post-shutdown"
    );
    assert_eq!(
        value["failure_boundaries"]["reinitialize"],
        "lsp-lifecycle-reinitialize"
    );
    assert_eq!(
        value["failure_boundaries"]["method_dispatch"],
        "lsp-method-dispatch"
    );
    assert_eq!(
        value["failure_boundaries"]["document_diagnostics"],
        "lsp-open-document-diagnostics"
    );
    assert_eq!(value["json_rpc_error_codes"]["parse_error"], -32700);
    assert_eq!(value["json_rpc_error_codes"]["invalid_request"], -32600);
    assert_eq!(value["json_rpc_error_codes"]["method_not_found"], -32601);
    assert_eq!(value["json_rpc_error_codes"]["invalid_params"], -32602);
    assert_eq!(value["json_rpc_error_codes"]["internal_error"], -32603);
    assert_eq!(
        value["json_rpc_error_codes"]["server_not_initialized"],
        -32002
    );
    assert_eq!(value["diagnostic_codes"]["unsupported_method"], "LNC0028");
    assert_eq!(value["diagnostic_codes"]["invalid_message"], "LNC0029");
    assert_lsp_unsupported_method_contract(&value["unsupported_method"]);
}

fn assert_lsp_transport_metadata(value: &serde_json::Value) {
    assert_eq!(value["schema_name"], "laniusc.lsp.transport");
    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["server_mode"], "stdio");
    assert_eq!(value["framing"], "content-length");
    assert_eq!(
        value["required_headers"]
            .as_array()
            .expect("LSP transport should list required headers")
            .iter()
            .map(|header| header
                .as_str()
                .expect("required LSP header should be a string"))
            .collect::<Vec<_>>(),
        vec!["Content-Length"]
    );
    assert_eq!(value["headers_case_insensitive"], true);
    assert_eq!(
        value["additional_headers"],
        "ignored when syntactically valid"
    );
    assert_eq!(value["header_terminator"], "crlf-crlf");
    assert_eq!(value["content_length_units"], "bytes");
    assert_eq!(value["body_encoding"], "utf-8-json-rpc");
    assert_eq!(value["response_stream"], "stdout");
    assert_eq!(value["stderr_diagnostics"], false);
    assert_eq!(value["invalid_frame_error_code"], -32700);
    assert!(value["invalid_frame_response_id"].is_null());
    assert_eq!(
        value["duplicate_content_length_policy"],
        "invalid-frame-before-method-dispatch"
    );
    assert_eq!(
        value["missing_content_length_policy"],
        "invalid-frame-before-method-dispatch"
    );
    assert_lsp_supported_methods_include(
        &value["message_kinds"]["request_methods"],
        &[
            "initialize",
            "textDocument/formatting",
            "textDocument/diagnostic",
            "shutdown",
        ],
    );
    assert_lsp_supported_methods_include(
        &value["message_kinds"]["notification_methods"],
        &[
            "initialized",
            "textDocument/didOpen",
            "textDocument/didChange",
            "textDocument/didClose",
            "shutdown",
            "exit",
        ],
    );
    assert_eq!(
        value["message_kinds"]["unsupported_notification_policy"],
        "ignored-without-response"
    );
    assert_eq!(value["no_run_guards"]["source_compilation"], false);
    assert_eq!(value["no_run_guards"]["source_scanning"], false);
    assert_eq!(value["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(value["no_run_guards"]["target_codegen"], false);
}

fn assert_lsp_unsupported_method_contract(value: &serde_json::Value) {
    assert_eq!(value["request_error_code"], -32601);
    assert_eq!(value["request_diagnostic_code"], "LNC0028");
    assert_eq!(value["request_failure_boundary"], "lsp-method-dispatch");
    assert_eq!(value["request_records_method_field"], "requested_method");
    assert_eq!(
        value["request_supported_methods_field"],
        "supported_methods"
    );
    assert_eq!(value["request_id_required_for_error"], true);
    assert_eq!(value["notification_response"], false);
    assert_eq!(value["notification_diagnostic"], false);
    assert_eq!(value["notification_policy"], "ignored");
    assert_eq!(value["no_run_guards"]["source_compilation"], false);
    assert_eq!(value["no_run_guards"]["source_scanning"], false);
    assert_eq!(value["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(value["no_run_guards"]["target_codegen"], false);
}

fn assert_lsp_diagnostic_formats(value: &serde_json::Value) {
    assert_eq!(
        value["schema_version"],
        laniusc_compiler::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(value["cli_flag"], "--diagnostic-format");
    assert_eq!(value["default_format"], "text");
    assert_eq!(
        value["accepted_formats"]
            .as_array()
            .expect("LSP diagnostic formats should list accepted selectors")
            .iter()
            .map(|format| format
                .as_str()
                .expect("diagnostic format selector should be a string"))
            .collect::<Vec<_>>(),
        vec!["text", "json", "lsp-json"]
    );
    assert_eq!(value["no_run_guards"]["source_compilation"], false);
    assert_eq!(value["no_run_guards"]["source_scanning"], false);
    assert_eq!(value["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(value["no_run_guards"]["target_codegen"], false);

    let formats = value["formats"]
        .as_array()
        .expect("LSP diagnostic formats should include format rows");
    let names = formats
        .iter()
        .map(|format| {
            format["name"]
                .as_str()
                .expect("diagnostic format row name should be a string")
        })
        .collect::<Vec<_>>();
    assert_eq!(names, vec!["text", "json", "lsp-json"]);
    assert!(formats.iter().any(|format| {
        format["name"] == "lsp-json"
            && format["payload"] == "LSP Diagnostic JSON object"
            && format["payload_schema_name"]
                == laniusc_compiler::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_NAME
            && format["payload_schema_version"]
                == laniusc_compiler::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
            && format["payload_schema_location"] == "data"
            && format["position_encoding"] == "utf-16"
            && format["language_server_envelope"] == false
    }));
}

fn assert_lsp_formatting_request_options(value: &serde_json::Value) {
    assert_eq!(value["params_options_required"], true);
    assert_eq!(value["tab_size_lsp_field"], "tabSize");
    assert_eq!(value["tab_size"], 4);
    assert_eq!(value["insert_spaces_lsp_field"], "insertSpaces");
    assert_eq!(value["insert_spaces"], true);
    assert_eq!(value["additional_options"], "ignored");
}

fn assert_formatter_policy(value: &serde_json::Value) {
    assert_eq!(value["schema_name"], "laniusc.formatter.policy");
    assert_eq!(value["schema_version"], 1);
    assert_eq!(
        value["formatter_contract"],
        "unstable-alpha lexical full-document formatter"
    );
    assert_eq!(value["formatter_kind"], "lexical");
    assert_eq!(value["document_scope"], "full-document");
    assert_eq!(value["range_formatting"], false);
    assert_eq!(value["syntax_parsing"], false);
    assert_eq!(value["type_checking"], false);
    assert_eq!(value["semantic_rewrites"], false);
    assert!(
        value["token_preservation"]
            .as_str()
            .is_some_and(|policy| policy.contains("non-whitespace token text")
                && policy.contains("token order")),
        "formatter policy should state the durable token-preservation contract"
    );
    assert_eq!(value["line_endings"], "lf");
    assert_eq!(value["indent"]["style"], "spaces");
    assert_eq!(value["indent"]["size"], 4);
    assert_eq!(value["cli"]["format_stdin"], "laniusc fmt --stdin");
    assert_eq!(value["cli"]["check_stdin"], "laniusc fmt --stdin --check");
    assert_lsp_formatting_request_options(&value["lsp"]["request_options"]);
    assert_eq!(value["diagnostic_codes"]["check_failed"], "LNC0019");
    assert_eq!(value["diagnostic_codes"]["input_read_failed"], "LNC0040");
    assert_eq!(value["diagnostic_codes"]["output_write_failed"], "LNC0034");
    assert_eq!(value["diagnostic_codes"]["output_stream_failed"], "LNC0035");
    assert_eq!(value["no_run_guards"]["source_compilation"], false);
    assert_eq!(value["no_run_guards"]["source_scanning"], false);
    assert_eq!(value["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(value["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(value["no_run_guards"]["target_codegen"], false);
}

fn assert_lsp_distribution_contract(value: &serde_json::Value) {
    assert_eq!(value["release_channel"], "source-worktree");
    assert_eq!(
        value["status"],
        "not-production-release; no stable install artifact or package manager channel"
    );
    assert_eq!(value["stable_install_artifact"], false);
    assert_eq!(value["package_manager_channel"], false);
    assert_eq!(value["release_artifact_workflow"], false);
    assert_eq!(value["source_control_required_for_claims"], true);
    assert_eq!(value["production_release_claim"], false);
}

fn assert_lsp_document_diagnostics_metadata(value: &serde_json::Value) {
    assert_eq!(value["method"], "textDocument/diagnostic");
    assert_eq!(value["provider_kind"], "pull");
    assert_eq!(value["report_kind"], "full");
    assert_eq!(value["document_scope"], "open-document-text");
    assert_eq!(value["publish_diagnostics"], false);
    assert_eq!(value["inter_file_dependencies"], false);
    assert_eq!(value["workspace_diagnostics"], false);
    assert_eq!(value["result_id_supported"], false);
    assert_eq!(value["source_scanning"], false);
    assert_eq!(value["source_root_loading"], false);
    assert_eq!(value["stdlib_root_loading"], false);
    assert_eq!(value["source_compilation"], true);
    assert_eq!(value["gpu_device_creation"], true);
    assert_eq!(value["target_codegen"], false);
}

fn assert_lsp_workspace_metadata(value: &serde_json::Value) {
    assert_eq!(value["workspace_folders"], false);
    assert_eq!(value["workspace_folder_changes"], false);
    assert_eq!(value["workspace_symbol_provider"], false);
    assert_eq!(value["configuration_requests"], false);
    assert_eq!(value["file_operations"], false);
    assert_eq!(value["workspace_diagnostics"], false);
    assert_eq!(value["source_root_loading"], false);
    assert_eq!(value["stdlib_root_loading"], false);
    assert_eq!(
        value["open_document_scope"],
        "explicit textDocument/didOpen documents only"
    );
    assert_eq!(value["initialize_root_uri"], "ignored");
    assert_eq!(value["initialize_workspace_folders"], "ignored");
}

fn assert_lsp_claim_boundaries(value: &serde_json::Value) {
    assert_eq!(value["schema_name"], "laniusc.lsp.claim-boundaries");
    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["evidence_kind"], "public-boundary-metadata");
    assert_eq!(
        value["claim_boundary"],
        "stdio protocol metadata and single-open-document pull diagnostics only"
    );
    assert_eq!(value["capabilities_are_performance_evidence"], false);
    assert_eq!(value["capabilities_are_production_readiness_claim"], false);
    assert_eq!(value["production_editor_ready"], false);
    assert_eq!(value["workspace_claim_status"], "not-supported");
    assert_eq!(value["latency_claim_status"], "not-measured");
    assert_eq!(value["throughput_claim_status"], "not-measured");
    assert_eq!(value["local_performance_claim_status"], "not-claimable");
    assert_eq!(
        value["measurement_evidence_policy"],
        "local-artifacts-only; capabilities metadata is not performance evidence"
    );
    assert_eq!(
        value["required_performance_evidence"],
        "local LSP latency/responsiveness artifacts separate from lanius.measurement-summary.v1 compiler throughput artifacts"
    );
    assert_eq!(
        value["claim_blockers"]
            .as_array()
            .expect("LSP claim blockers should be an array")
            .iter()
            .map(|blocker| blocker
                .as_str()
                .expect("LSP claim blocker should be a string"))
            .collect::<Vec<_>>(),
        vec![
            "no workspace diagnostics",
            "no source-root loading",
            "no stdlib-root loading",
            "no local LSP latency artifacts",
            "not a release artifact",
        ]
    );
    assert_eq!(value["no_run_guards"]["source_compilation"], false);
    assert_eq!(value["no_run_guards"]["source_scanning"], false);
    assert_eq!(value["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(value["no_run_guards"]["target_codegen"], false);
}

fn assert_lsp_lifecycle_metadata(value: &serde_json::Value) {
    assert_eq!(
        value["pre_initialize_allowed_methods"]
            .as_array()
            .expect("pre-initialize methods should be an array")
            .iter()
            .map(|method| method
                .as_str()
                .expect("pre-initialize method should be a string"))
            .collect::<Vec<_>>(),
        vec!["initialize", "exit"]
    );
    assert_eq!(
        value["post_shutdown_allowed_methods"]
            .as_array()
            .expect("post-shutdown methods should be an array")
            .iter()
            .map(|method| method
                .as_str()
                .expect("post-shutdown method should be a string"))
            .collect::<Vec<_>>(),
        vec!["exit"]
    );
    assert_eq!(value["repeated_initialize_rejected"], true);
    assert_eq!(value["repeated_initialize_preserves_session"], true);
    assert_eq!(value["stateful_notifications_before_initialize"], "ignored");
    assert_eq!(value["stateful_notifications_after_shutdown"], "ignored");
}

fn assert_lsp_supported_methods_include(value: &serde_json::Value, expected: &[&str]) {
    let methods = value
        .as_array()
        .expect("supported methods should be an array")
        .iter()
        .map(|method| {
            method
                .as_str()
                .expect("supported method should be a string")
        })
        .collect::<Vec<_>>();
    for method in expected {
        assert!(
            methods.contains(method),
            "supported LSP method inventory should include {method:?}; got {methods:?}"
        );
    }
}

fn assert_lsp_supported_methods_do_not_include(value: &serde_json::Value, forbidden: &[&str]) {
    let methods = value
        .as_array()
        .expect("supported methods should be an array")
        .iter()
        .map(|method| {
            method
                .as_str()
                .expect("supported method should be a string")
        })
        .collect::<Vec<_>>();
    for method in forbidden {
        assert!(
            !methods.contains(method),
            "supported LSP method inventory should not claim {method:?}; got {methods:?}"
        );
    }
}

fn parse_lsp_responses(stdout: &[u8]) -> Vec<serde_json::Value> {
    let mut responses = Vec::new();
    let mut offset = 0;
    while offset < stdout.len() {
        let header_end = find_header_end(&stdout[offset..])
            .unwrap_or_else(|| panic!("missing LSP header terminator at byte {offset}"))
            + offset;
        let header = std::str::from_utf8(&stdout[offset..header_end])
            .expect("LSP response header should be UTF-8");
        let content_length = header
            .lines()
            .find_map(|line| {
                let (name, value) = line.split_once(':')?;
                name.eq_ignore_ascii_case("content-length")
                    .then(|| value.trim().parse::<usize>().expect("valid Content-Length"))
            })
            .expect("LSP response should include Content-Length");
        let body_start = header_end + 4;
        let body_end = body_start + content_length;
        assert!(
            body_end <= stdout.len(),
            "LSP response body should fit inside stdout"
        );
        responses.push(
            serde_json::from_slice(&stdout[body_start..body_end])
                .expect("LSP response body should be JSON"),
        );
        offset = body_end;
    }
    responses
}

fn find_header_end(bytes: &[u8]) -> Option<usize> {
    bytes.windows(4).position(|window| window == b"\r\n\r\n")
}
