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
    assert_eq!(document["schema_version"], 4);
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
        &["textDocument/rangeFormatting"],
    );
    assert_eq!(document["language_id"], "lanius");
    assert_eq!(document["position_encoding"], "utf-16");
    assert_eq!(document["diagnostic_source"], "laniusc");
    assert_eq!(document["diagnostic_registry"]["schema_version"], 5);
    assert_eq!(document["document_sync"]["open_close"], true);
    assert_eq!(document["document_sync"]["change"], 1);
    assert_eq!(document["document_sync"]["change_kind"], "full");
    assert_eq!(document["document_sync"]["incremental_changes"], false);
    assert_eq!(document["formatting"]["document_formatting_provider"], true);
    assert_eq!(document["formatting"]["method"], "textDocument/formatting");
    assert_eq!(
        document["formatting"]["edit_strategy"],
        "single full-document replacement when formatting changes"
    );
    assert_eq!(document["formatting"]["range_formatting_provider"], false);
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
    assert_eq!(document["formatting"]["gpu_device_creation"], false);
    assert_eq!(document["formatting"]["target_codegen"], false);
    assert_eq!(
        document["document_diagnostics"]["method"],
        "textDocument/diagnostic"
    );
    assert_eq!(document["document_diagnostics"]["report_kind"], "full");
    assert_eq!(document["document_diagnostics"]["source_compilation"], true);
    assert_eq!(document["document_diagnostics"]["target_codegen"], false);
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
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
    let laniusc = &initialize["result"]["capabilities"]["experimental"]["laniusc"];
    assert_eq!(laniusc["schema_version"], 2);
    assert_eq!(laniusc["language_id"], "lanius");
    assert_eq!(laniusc["diagnostic_source"], "laniusc");
    assert_eq!(laniusc["diagnostic_registry"]["schema_version"], 5);
    assert_lsp_supported_methods_do_not_include(
        &laniusc["supported_methods"],
        &["textDocument/rangeFormatting"],
    );
    assert_eq!(laniusc["formatting"]["document_formatting_provider"], true);
    assert_eq!(laniusc["formatting"]["method"], "textDocument/formatting");
    assert_eq!(
        laniusc["formatting"]["edit_strategy"],
        "single full-document replacement when formatting changes"
    );
    assert_eq!(laniusc["formatting"]["range_formatting_provider"], false);
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
    assert_eq!(laniusc["formatting"]["gpu_device_creation"], false);
    assert_eq!(laniusc["formatting"]["target_codegen"], false);
    assert_eq!(laniusc["document_diagnostics"], true);
    assert_eq!(laniusc["no_run_guards"]["source_compilation"], false);
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
    assert_eq!(data["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(data["no_run_guards"]["target_codegen"], false);

    let diagnostic = &data["diagnostic"];
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0028");
    assert_eq!(diagnostic["title"], "unsupported LSP method");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unsupported LSP method");
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
    assert_eq!(diagnostic["data"]["registry_schema_version"], 5);
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
        4,
        "initialize, missing-method, parse-error, and shutdown should respond"
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

    let parse_error = responses
        .iter()
        .find(|response| response["id"].is_null() && response.get("error").is_some())
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

fn assert_invalid_lsp_message_diagnostic(data: &serde_json::Value, expected_note: &str) {
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
    assert_eq!(data["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(data["no_run_guards"]["target_codegen"], false);

    let diagnostic = &data["diagnostic"];
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0029");
    assert_eq!(diagnostic["title"], "invalid LSP message");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "invalid LSP message");
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
