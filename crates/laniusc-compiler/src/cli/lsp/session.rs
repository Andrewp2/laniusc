use std::{
    collections::HashMap,
    io::{self, BufRead, Write},
};

use super::{
    capabilities,
    document::{self, OpenDocument},
    protocol::{self, FrameRead},
};
use crate::cli::{
    common::{
        CliError,
        LANIUS_LSP_INTERNAL_ERROR_CODE,
        LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
        LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
        LANIUS_LSP_PARSE_ERROR_CODE,
        extra_cli_argument_error,
        missing_cli_option_value_error,
    },
    help::print_lsp_help,
};

/// Runs the stdio LSP server after validating `laniusc lsp serve` options.
pub(super) fn run_serve(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let mut saw_stdio = false;
    for arg in args {
        match arg.as_str() {
            "--stdio" => saw_stdio = true,
            "-h" | "--help" => {
                print_lsp_help();
                return Ok(());
            }
            other => {
                return Err(extra_cli_argument_error(
                    "laniusc lsp serve",
                    other,
                    "--stdio",
                ));
            }
        }
    }
    if !saw_stdio {
        return Err(missing_cli_option_value_error(
            "laniusc lsp serve",
            "--stdio",
        ));
    }

    run_stdio(io::stdin().lock(), io::stdout().lock())
}

fn run_stdio(mut input: impl BufRead, mut output: impl Write) -> Result<(), CliError> {
    let mut initialize_received = false;
    let mut shutdown_received = false;
    let mut documents = HashMap::<String, OpenDocument>::new();
    loop {
        let body = match protocol::read_framed_body(&mut input)? {
            FrameRead::Body(body) => body,
            FrameRead::InvalidFrame(note) => {
                let response = protocol::invalid_message_error_response(
                    serde_json::Value::Null,
                    LANIUS_LSP_PARSE_ERROR_CODE,
                    "invalid LSP frame",
                    note,
                );
                protocol::write_response(&mut output, &response)?;
                continue;
            }
            FrameRead::EndOfInput => break,
        };
        let request: serde_json::Value = match serde_json::from_slice(&body) {
            Ok(request) => request,
            Err(err) => {
                let response = protocol::invalid_message_error_response(
                    serde_json::Value::Null,
                    LANIUS_LSP_PARSE_ERROR_CODE,
                    format!("invalid JSON-RPC payload: {err}"),
                    "message body was not valid JSON",
                );
                protocol::write_response(&mut output, &response)?;
                continue;
            }
        };
        if !request.is_object() {
            let response = protocol::invalid_message_error_response(
                serde_json::Value::Null,
                LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
                "JSON-RPC message must be a request object",
                "message body was valid JSON but not a JSON-RPC request object",
            );
            protocol::write_response(&mut output, &response)?;
            continue;
        }
        let id = request
            .get("id")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        if request.get("jsonrpc").and_then(serde_json::Value::as_str) != Some("2.0") {
            if !id.is_null() {
                let response = protocol::invalid_message_error_response(
                    id,
                    LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
                    "JSON-RPC request must use version 2.0",
                    "request object did not include jsonrpc: \"2.0\"",
                );
                protocol::write_response(&mut output, &response)?;
            }
            continue;
        }
        let Some(method) = request.get("method").and_then(serde_json::Value::as_str) else {
            if !id.is_null() {
                let response = protocol::invalid_message_error_response(
                    id,
                    LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
                    "JSON-RPC request must include method",
                    "request object did not include a string method field",
                );
                protocol::write_response(&mut output, &response)?;
            }
            continue;
        };
        if !initialize_received && method != "initialize" && method != "exit" {
            if !id.is_null() {
                let response = protocol::server_not_initialized_error_response(id);
                protocol::write_response(&mut output, &response)?;
            }
            continue;
        }
        if shutdown_received && method != "exit" {
            if !id.is_null() {
                let response = protocol::invalid_message_error_response_with_boundary(
                    id,
                    LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
                    "LSP server has shut down",
                    "server has already processed shutdown; only exit is accepted",
                    protocol::LSP_FAILURE_BOUNDARY_POST_SHUTDOWN,
                );
                protocol::write_response(&mut output, &response)?;
            }
            continue;
        }
        if initialize_received && method == "initialize" {
            if !id.is_null() {
                let response = protocol::invalid_message_error_response_with_boundary(
                    id,
                    LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
                    "LSP server is already initialized",
                    "initialize request has already completed; repeated initialize requests are rejected before changing server state",
                    protocol::LSP_FAILURE_BOUNDARY_REINITIALIZE,
                );
                protocol::write_response(&mut output, &response)?;
            }
            continue;
        }
        match method {
            "initialize" => {
                initialize_received = true;
                let response = capabilities::initialize_response(id);
                protocol::write_response(&mut output, &response)?;
            }
            "initialized" => {
                if !id.is_null() {
                    let response = protocol::null_result_response(id);
                    protocol::write_response(&mut output, &response)?;
                }
            }
            "textDocument/didOpen" => match document::open_from_request(&request) {
                Ok((uri, document)) => {
                    documents.insert(uri, document);
                    if !id.is_null() {
                        let response = protocol::null_result_response(id);
                        protocol::write_response(&mut output, &response)?;
                    }
                }
                Err(note) => {
                    if !id.is_null() {
                        let response = protocol::invalid_message_error_response(
                            id,
                            LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                            "invalid textDocument/didOpen parameters",
                            note,
                        );
                        protocol::write_response(&mut output, &response)?;
                    }
                }
            },
            "textDocument/didChange" => match document::change_from_request(&request) {
                Ok((uri, document)) => {
                    if !documents.contains_key(&uri) {
                        if !id.is_null() {
                            let response = protocol::invalid_message_error_response(
                                id,
                                LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                                "invalid textDocument/didChange parameters",
                                "textDocument/didChange requested a document that is not open",
                            );
                            protocol::write_response(&mut output, &response)?;
                        }
                        continue;
                    }
                    documents.insert(uri, document);
                    if !id.is_null() {
                        let response = protocol::null_result_response(id);
                        protocol::write_response(&mut output, &response)?;
                    }
                }
                Err(note) => {
                    if !id.is_null() {
                        let response = protocol::invalid_message_error_response(
                            id,
                            LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                            "invalid textDocument/didChange parameters",
                            note,
                        );
                        protocol::write_response(&mut output, &response)?;
                    }
                }
            },
            "textDocument/didClose" => match document::uri_from_request(&request) {
                Ok(uri) => {
                    documents.remove(&uri);
                    if !id.is_null() {
                        let response = protocol::null_result_response(id);
                        protocol::write_response(&mut output, &response)?;
                    }
                }
                Err(note) => {
                    if !id.is_null() {
                        let response = protocol::invalid_message_error_response(
                            id,
                            LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                            "invalid textDocument/didClose parameters",
                            note,
                        );
                        protocol::write_response(&mut output, &response)?;
                    }
                }
            },
            "textDocument/formatting" => {
                if !id.is_null() {
                    match document::formatting_uri_from_request(&request) {
                        Ok(uri) => {
                            let Some(document) = documents.get(&uri) else {
                                let response = protocol::invalid_message_error_response(
                                    id,
                                    LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                                    "invalid textDocument/formatting parameters",
                                    "textDocument/formatting requested a document that is not open",
                                );
                                protocol::write_response(&mut output, &response)?;
                                continue;
                            };
                            let response = serde_json::json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "result": document::formatting_edits(&document.text)
                            });
                            protocol::write_response(&mut output, &response)?;
                        }
                        Err(note) => {
                            let response = protocol::invalid_message_error_response(
                                id,
                                LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                                "invalid textDocument/formatting parameters",
                                note,
                            );
                            protocol::write_response(&mut output, &response)?;
                        }
                    }
                }
            }
            "textDocument/diagnostic" => {
                if !id.is_null() {
                    match document::uri_from_request(&request) {
                        Ok(uri) => {
                            let Some(document) = documents.get(&uri) else {
                                let response = protocol::invalid_message_error_response(
                                    id,
                                    LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                                    "invalid textDocument/diagnostic parameters",
                                    "textDocument/diagnostic requested a document that is not open",
                                );
                                protocol::write_response(&mut output, &response)?;
                                continue;
                            };
                            match document::diagnostic_items(&uri, &document.text) {
                                Ok(items) => {
                                    let response = serde_json::json!({
                                        "jsonrpc": "2.0",
                                        "id": id,
                                        "result": {
                                            "kind": "full",
                                            "items": items
                                        }
                                    });
                                    protocol::write_response(&mut output, &response)?;
                                }
                                Err(message) => {
                                    let response = protocol::error_response_with_data(
                                        id,
                                        LANIUS_LSP_INTERNAL_ERROR_CODE,
                                        "document diagnostics failed",
                                        serde_json::json!({
                                            "failure_boundary": protocol::LSP_FAILURE_BOUNDARY_DOCUMENT_DIAGNOSTICS,
                                            "requested_method": "textDocument/diagnostic",
                                            "message": message,
                                            "no_run_guards": {
                                                "source_compilation": true,
                                                "source_scanning": false,
                                                "gpu_device_creation": true,
                                                "target_codegen": false
                                            }
                                        }),
                                    );
                                    protocol::write_response(&mut output, &response)?;
                                }
                            }
                        }
                        Err(note) => {
                            let response = protocol::invalid_message_error_response(
                                id,
                                LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
                                "invalid textDocument/diagnostic parameters",
                                note,
                            );
                            protocol::write_response(&mut output, &response)?;
                        }
                    }
                }
            }
            "shutdown" => {
                shutdown_received = true;
                if !id.is_null() {
                    let response = protocol::null_result_response(id);
                    protocol::write_response(&mut output, &response)?;
                }
            }
            "exit" => break,
            other => {
                if !id.is_null() {
                    let response = protocol::unsupported_method_error_response(id, other);
                    protocol::write_response(&mut output, &response)?;
                }
            }
        }
        if shutdown_received && method == "exit" {
            break;
        }
    }
    Ok(())
}
