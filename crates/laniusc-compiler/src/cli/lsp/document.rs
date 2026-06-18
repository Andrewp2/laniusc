use std::path::PathBuf;

use super::LSP_LANGUAGE_ID;
use crate::{
    compiler::{CompileError, type_check_source_with_gpu},
    formatter::format_source,
};

#[derive(Clone, Debug)]
/// In-memory text for an LSP document that was explicitly opened by the client.
pub(super) struct OpenDocument {
    /// Latest full-document source text for the URI.
    pub(super) text: String,
}

impl OpenDocument {
    fn new(text: impl Into<String>) -> Self {
        Self { text: text.into() }
    }
}

/// Extracts an opened Lanius document from a `textDocument/didOpen` request.
pub(super) fn open_from_request(
    request: &serde_json::Value,
) -> Result<(String, OpenDocument), String> {
    let text_document = request
        .get("params")
        .and_then(|params| params.get("textDocument"))
        .ok_or_else(|| "didOpen request did not include params.textDocument".to_string())?;
    let uri = text_document
        .get("uri")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "didOpen request did not include textDocument.uri".to_string())?;
    let language_id = text_document
        .get("languageId")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "didOpen request did not include textDocument.languageId".to_string())?;
    if language_id != LSP_LANGUAGE_ID {
        return Err(format!(
            "didOpen request used languageId {language_id:?}; expected {LSP_LANGUAGE_ID:?}"
        ));
    }
    let text = text_document
        .get("text")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "didOpen request did not include textDocument.text".to_string())?;
    Ok((uri.to_string(), OpenDocument::new(text)))
}

/// Extracts a full-document replacement from a `textDocument/didChange` request.
///
/// The server intentionally rejects ranged incremental changes so diagnostics
/// and formatting operate on one coherent text buffer per open URI.
pub(super) fn change_from_request(
    request: &serde_json::Value,
) -> Result<(String, OpenDocument), String> {
    let uri = uri_from_request(request)?;
    let changes = request
        .get("params")
        .and_then(|params| params.get("contentChanges"))
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "didChange request did not include params.contentChanges".to_string())?;
    let mut text = None;
    for (index, change) in changes.iter().enumerate() {
        if change.get("range").is_some() || change.get("rangeLength").is_some() {
            return Err(
                "didChange only accepts full-document text changes; ranged incremental changes are not supported"
                    .to_string(),
            );
        }
        text = Some(
            change
                .get("text")
                .and_then(serde_json::Value::as_str)
                .ok_or_else(|| {
                    format!(
                        "didChange full-document contentChanges[{index}] did not include string text"
                    )
                })?,
        );
    }
    let text =
        text.ok_or_else(|| "didChange request did not include full-document text".to_string())?;
    Ok((uri, OpenDocument::new(text)))
}

/// Extracts `params.textDocument.uri` from an LSP request object.
pub(super) fn uri_from_request(request: &serde_json::Value) -> Result<String, String> {
    request
        .get("params")
        .and_then(|params| params.get("textDocument"))
        .and_then(|text_document| text_document.get("uri"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| "request did not include params.textDocument.uri".to_string())
}

/// Extracts a formatting request URI after validating supported options.
pub(super) fn formatting_uri_from_request(request: &serde_json::Value) -> Result<String, String> {
    let params = request
        .get("params")
        .ok_or_else(|| "textDocument/formatting request did not include params".to_string())?;
    let uri = params
        .get("textDocument")
        .and_then(|text_document| text_document.get("uri"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| {
            "textDocument/formatting request did not include params.textDocument.uri".to_string()
        })?;
    validate_formatting_options(params.get("options"))?;
    Ok(uri)
}

fn validate_formatting_options(options: Option<&serde_json::Value>) -> Result<(), String> {
    let options = options
        .and_then(serde_json::Value::as_object)
        .ok_or_else(|| {
            "textDocument/formatting request did not include params.options object".to_string()
        })?;
    let tab_size = options
        .get("tabSize")
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| {
            "textDocument/formatting params.options.tabSize must be a positive LSP uinteger"
                .to_string()
        })?;
    if tab_size == 0 || tab_size > i32::MAX as u64 {
        return Err(
            "textDocument/formatting params.options.tabSize must be a positive LSP uinteger"
                .to_string(),
        );
    }
    if tab_size != 4 {
        return Err(
            "textDocument/formatting params.options.tabSize must be 4 for the fixed-space formatter"
                .to_string(),
        );
    }
    let insert_spaces = options
        .get("insertSpaces")
        .and_then(serde_json::Value::as_bool)
        .ok_or_else(|| {
            "textDocument/formatting params.options.insertSpaces must be a boolean".to_string()
        })?;
    if !insert_spaces {
        return Err(
            "textDocument/formatting params.options.insertSpaces must be true for the fixed-space formatter"
                .to_string(),
        );
    }
    Ok(())
}

/// Produces LSP text edits for full-document formatting.
///
/// The formatter contract is lexical and either returns no edits or a single
/// whole-document replacement.
pub(super) fn formatting_edits(source: &str) -> Vec<serde_json::Value> {
    let formatted = format_source(source);
    if formatted == source {
        return Vec::new();
    }

    vec![serde_json::json!({
        "range": {
            "start": {
                "line": 0,
                "character": 0
            },
            "end": document_end_position(source)
        },
        "newText": formatted
    })]
}

/// Type-checks one open document and returns LSP diagnostic items.
///
/// This is the LSP path that may create a GPU device. It does not load source
/// roots, compile target bytes, or inspect workspace state.
pub(super) fn diagnostic_items(uri: &str, source: &str) -> Result<Vec<serde_json::Value>, String> {
    match pollster::block_on(type_check_source_with_gpu(source)) {
        Ok(()) => Ok(Vec::new()),
        Err(CompileError::Diagnostic(mut diagnostic)) => {
            if let Some(label) = diagnostic.primary_label.as_mut() {
                label.path = uri_label_path(uri);
            }
            serde_json::to_value(diagnostic.to_lsp_diagnostic())
                .map(|diagnostic| vec![diagnostic])
                .map_err(|err| format!("serialize LSP diagnostic: {err}"))
        }
        Err(err) => Err(err.to_string()),
    }
}

fn document_end_position(source: &str) -> serde_json::Value {
    let mut line = 0u32;
    let mut character = 0u32;
    let mut chars = source.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '\r' if chars.peek() == Some(&'\n') => {}
            '\r' | '\n' => {
                line = line.saturating_add(1);
                character = 0;
            }
            _ => {
                character = character.saturating_add(ch.len_utf16() as u32);
            }
        }
    }
    serde_json::json!({
        "line": line,
        "character": character
    })
}

fn uri_label_path(uri: &str) -> PathBuf {
    uri.strip_prefix("file://")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(uri))
}
