use std::io::{self, BufRead, Write};

use crate::{
    cli::common::{
        CliError,
        LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
        LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
        LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE,
        LANIUS_LSP_PARSE_ERROR_CODE,
        LANIUS_LSP_SERVER_NOT_INITIALIZED_ERROR_CODE,
        LSP_PRE_INITIALIZE_METHODS,
        LSP_STDIO_METHODS,
        lsp_error_data_metadata,
    },
    compiler::Diagnostic,
};

pub(super) const LSP_FAILURE_BOUNDARY_MESSAGE_VALIDATION: &str = "lsp-protocol-message-validation";
pub(super) const LSP_FAILURE_BOUNDARY_PRE_INITIALIZE: &str = "lsp-lifecycle-pre-initialize";
pub(super) const LSP_FAILURE_BOUNDARY_POST_SHUTDOWN: &str = "lsp-lifecycle-post-shutdown";
pub(super) const LSP_FAILURE_BOUNDARY_REINITIALIZE: &str = "lsp-lifecycle-reinitialize";
pub(super) const LSP_FAILURE_BOUNDARY_METHOD_DISPATCH: &str = "lsp-method-dispatch";
pub(super) const LSP_FAILURE_BOUNDARY_DOCUMENT_DIAGNOSTICS: &str = "lsp-open-document-diagnostics";

#[derive(Debug)]
pub(super) enum FrameRead {
    Body(Vec<u8>),
    InvalidFrame(String),
    EndOfInput,
}

pub(super) fn read_framed_body(input: &mut impl BufRead) -> Result<FrameRead, CliError> {
    let mut content_length = None;
    let mut frame_error: Option<String> = None;
    loop {
        let mut line = String::new();
        let read = input
            .read_line(&mut line)
            .map_err(|err| format!("read LSP header: {err}"))?;
        if read == 0 {
            return if frame_error.is_some() || content_length.is_some() {
                Ok(FrameRead::InvalidFrame(frame_error.unwrap_or_else(|| {
                    "LSP frame ended before the header terminator".to_string()
                })))
            } else {
                Ok(FrameRead::EndOfInput)
            };
        }
        let header = line.trim_end_matches(['\r', '\n']);
        if header.is_empty() {
            break;
        }
        let Some((name, value)) = header.split_once(':') else {
            frame_error.get_or_insert_with(|| format!("malformed LSP header {header:?}"));
            continue;
        };
        if name.eq_ignore_ascii_case("content-length") {
            match value.trim().parse::<usize>() {
                Ok(parsed) => {
                    if content_length.is_some() {
                        frame_error.get_or_insert_with(|| {
                            "duplicate LSP Content-Length header".to_string()
                        });
                    } else {
                        content_length = Some(parsed);
                    }
                }
                Err(err) => {
                    frame_error.get_or_insert_with(|| {
                        format!("invalid LSP Content-Length {value:?}: {err}")
                    });
                }
            }
        }
    }
    if let Some(note) = frame_error {
        if let Some(content_length) = content_length {
            let mut discarded_body = vec![0; content_length];
            if let Err(err) = input.read_exact(&mut discarded_body) {
                if err.kind() == io::ErrorKind::UnexpectedEof {
                    return Ok(FrameRead::InvalidFrame(format!(
                        "{note}; LSP body ended before Content-Length bytes were available while discarding invalid frame: {err}"
                    )));
                }
                return Err(format!("discard invalid LSP body: {err}").into());
            }
        }
        return Ok(FrameRead::InvalidFrame(note));
    }
    let Some(content_length) = content_length else {
        return Ok(FrameRead::InvalidFrame(
            "LSP message missing Content-Length header".to_string(),
        ));
    };
    let mut body = vec![0; content_length];
    match input.read_exact(&mut body) {
        Ok(()) => Ok(FrameRead::Body(body)),
        Err(err) if err.kind() == io::ErrorKind::UnexpectedEof => Ok(FrameRead::InvalidFrame(
            format!("LSP body ended before Content-Length bytes were available: {err}"),
        )),
        Err(err) => Err(format!("read LSP body: {err}").into()),
    }
}

pub(super) fn null_result_response(id: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": serde_json::Value::Null
    })
}

pub(super) fn write_response(
    output: &mut impl Write,
    response: &serde_json::Value,
) -> Result<(), CliError> {
    let body =
        serde_json::to_vec(response).map_err(|err| format!("serialize LSP response: {err}"))?;
    write!(output, "Content-Length: {}\r\n\r\n", body.len())
        .map_err(|err| format!("write LSP response header: {err}"))?;
    output
        .write_all(&body)
        .map_err(|err| format!("write LSP response body: {err}"))?;
    output
        .flush()
        .map_err(|err| format!("flush LSP response: {err}"))?;
    Ok(())
}

pub(super) fn error_response_with_data(
    id: serde_json::Value,
    code: i32,
    message: impl Into<String>,
    mut data: serde_json::Value,
) -> serde_json::Value {
    if let serde_json::Value::Object(data) = &mut data {
        data.entry("schema_name")
            .or_insert_with(|| serde_json::json!(LANIUS_LSP_ERROR_DATA_SCHEMA_NAME));
        data.entry("schema_version")
            .or_insert_with(|| serde_json::json!(LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION));
    }
    serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {
            "code": code,
            "message": message.into(),
            "data": data
        }
    })
}

pub(super) fn error_data_contract_metadata() -> serde_json::Value {
    let mut metadata = lsp_error_data_metadata();
    if let serde_json::Value::Object(fields) = &mut metadata {
        fields.insert(
            "failure_boundary_field".to_string(),
            serde_json::json!("failure_boundary"),
        );
        fields.insert(
            "requested_method_field".to_string(),
            serde_json::json!("requested_method"),
        );
        fields.insert(
            "failure_boundaries".to_string(),
            serde_json::json!({
                "message_validation": LSP_FAILURE_BOUNDARY_MESSAGE_VALIDATION,
                "pre_initialize": LSP_FAILURE_BOUNDARY_PRE_INITIALIZE,
                "post_shutdown": LSP_FAILURE_BOUNDARY_POST_SHUTDOWN,
                "reinitialize": LSP_FAILURE_BOUNDARY_REINITIALIZE,
                "method_dispatch": LSP_FAILURE_BOUNDARY_METHOD_DISPATCH,
                "document_diagnostics": LSP_FAILURE_BOUNDARY_DOCUMENT_DIAGNOSTICS
            }),
        );
        fields.insert(
            "unsupported_method".to_string(),
            serde_json::json!({
                "request_error_code": LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE,
                "request_diagnostic_code": "LNC0028",
                "request_failure_boundary": LSP_FAILURE_BOUNDARY_METHOD_DISPATCH,
                "request_records_method_field": "requested_method",
                "request_supported_methods_field": "supported_methods",
                "request_id_required_for_error": true,
                "notification_response": false,
                "notification_diagnostic": false,
                "notification_policy": "ignored",
                "no_run_guards": {
                    "source_compilation": false,
                    "source_scanning": false,
                    "gpu_device_creation": false,
                    "target_codegen": false
                }
            }),
        );
    }
    metadata
}

pub(super) fn transport_contract_metadata() -> serde_json::Value {
    serde_json::json!({
        "schema_name": "laniusc.lsp.transport",
        "schema_version": 1,
        "server_mode": "stdio",
        "framing": "content-length",
        "required_headers": ["Content-Length"],
        "headers_case_insensitive": true,
        "additional_headers": "ignored when syntactically valid",
        "header_terminator": "crlf-crlf",
        "content_length_units": "bytes",
        "body_encoding": "utf-8-json-rpc",
        "response_stream": "stdout",
        "stderr_diagnostics": false,
        "invalid_frame_error_code": LANIUS_LSP_PARSE_ERROR_CODE,
        "invalid_frame_response_id": serde_json::Value::Null,
        "duplicate_content_length_policy": "invalid-frame-before-method-dispatch",
        "missing_content_length_policy": "invalid-frame-before-method-dispatch",
        "message_kinds": {
            "request_methods": [
                "initialize",
                "textDocument/formatting",
                "textDocument/diagnostic",
                "shutdown"
            ],
            "notification_methods": [
                "initialized",
                "textDocument/didOpen",
                "textDocument/didChange",
                "textDocument/didClose",
                "shutdown",
                "exit"
            ],
            "unsupported_notification_policy": "ignored-without-response"
        },
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    })
}

pub(super) fn invalid_message_error_response(
    id: serde_json::Value,
    code: i32,
    message: impl Into<String>,
    note: impl Into<String>,
) -> serde_json::Value {
    invalid_message_error_response_with_boundary(
        id,
        code,
        message,
        note,
        LSP_FAILURE_BOUNDARY_MESSAGE_VALIDATION,
    )
}

pub(super) fn invalid_message_error_response_with_boundary(
    id: serde_json::Value,
    code: i32,
    message: impl Into<String>,
    note: impl Into<String>,
    failure_boundary: &'static str,
) -> serde_json::Value {
    let diagnostic = Diagnostic::error("LNC0029", "invalid LSP message")
        .with_note(note)
        .with_note(format!(
            "supported LSP methods: {}",
            LSP_STDIO_METHODS.join(", ")
        ));
    error_response_with_data(
        id,
        code,
        message,
        serde_json::json!({
            "failure_boundary": failure_boundary,
            "diagnostic": diagnostic,
            "supported_methods": LSP_STDIO_METHODS,
            "no_run_guards": {
                "source_compilation": false,
                "source_scanning": false,
                "gpu_device_creation": false,
                "target_codegen": false
            }
        }),
    )
}

pub(super) fn server_not_initialized_error_response(id: serde_json::Value) -> serde_json::Value {
    let diagnostic = Diagnostic::error("LNC0029", "invalid LSP message")
        .with_note("initialize request has not completed; document and shutdown requests are rejected before the server is initialized")
        .with_note(format!(
            "allowed methods before initialize completes: {}",
            LSP_PRE_INITIALIZE_METHODS.join(", ")
        ))
        .with_note(format!(
            "supported LSP methods: {}",
            LSP_STDIO_METHODS.join(", ")
        ));
    error_response_with_data(
        id,
        LANIUS_LSP_SERVER_NOT_INITIALIZED_ERROR_CODE,
        "LSP server is not initialized",
        serde_json::json!({
            "failure_boundary": LSP_FAILURE_BOUNDARY_PRE_INITIALIZE,
            "diagnostic": diagnostic,
            "allowed_methods": LSP_PRE_INITIALIZE_METHODS,
            "supported_methods": LSP_STDIO_METHODS,
            "no_run_guards": {
                "source_compilation": false,
                "source_scanning": false,
                "gpu_device_creation": false,
                "target_codegen": false
            }
        }),
    )
}

pub(super) fn unsupported_method_error_response(
    id: serde_json::Value,
    method: &str,
) -> serde_json::Value {
    let diagnostic = Diagnostic::error("LNC0028", "unsupported LSP method")
        .with_note(format!(
            "LSP method {method:?} is not supported by this stdio server"
        ))
        .with_note(format!(
            "supported LSP methods: {}",
            LSP_STDIO_METHODS.join(", ")
        ));
    let message = diagnostic.message.clone();
    error_response_with_data(
        id,
        LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE,
        message,
        serde_json::json!({
            "failure_boundary": LSP_FAILURE_BOUNDARY_METHOD_DISPATCH,
            "requested_method": method,
            "diagnostic": diagnostic,
            "supported_methods": LSP_STDIO_METHODS,
            "no_run_guards": {
                "source_compilation": false,
                "source_scanning": false,
                "gpu_device_creation": false,
                "target_codegen": false
            }
        }),
    )
}
