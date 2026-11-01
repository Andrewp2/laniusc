use std::{
    fs,
    path::{Path, PathBuf},
};

use super::LSP_LANGUAGE_ID;
use crate::{
    compiler::{CompileError, type_check_entry_with_stdlib, type_check_source_with_gpu},
    formatter::format_source,
};

/// The `initializationOptions` key that names the standard-library root.
pub(super) const LSP_STDLIB_ROOT_OPTION: &str = "stdlibRoot";

/// Where the server finds the standard library for document diagnostics.
#[derive(Clone, Debug, Default)]
pub(super) struct LspSourceRoots {
    /// Root passed to the loader as `laniusc check --stdlib-root` would be.
    pub(super) stdlib_root: Option<PathBuf>,
}

impl LspSourceRoots {
    /// Chooses the stdlib root from an `initialize` request:
    /// `initializationOptions.stdlibRoot` (a path or `file:` URI), else a
    /// `stdlib/` directory next to the laniusc binary, else `stdlib/` in the
    /// workspace root (`rootUri`, `rootPath` or the first workspace folder).
    /// With none of these the server checks each document on its own.
    pub(super) fn from_initialize_request(request: &serde_json::Value) -> Self {
        let params = request.get("params");
        let configured = params
            .and_then(|params| params.get("initializationOptions"))
            .and_then(|options| options.get(LSP_STDLIB_ROOT_OPTION))
            .and_then(serde_json::Value::as_str)
            .filter(|root| !root.is_empty())
            .map(uri_label_path);
        let beside_binary = || {
            std::env::current_exe()
                .ok()
                .and_then(|exe| exe.parent().map(|dir| dir.join("stdlib")))
                .filter(|root| root.is_dir())
        };
        let in_workspace = || {
            params
                .and_then(workspace_root)
                .map(|root| root.join("stdlib"))
                .filter(|root| root.is_dir())
        };
        Self {
            stdlib_root: configured.or_else(beside_binary).or_else(in_workspace),
        }
    }
}

fn workspace_root(params: &serde_json::Value) -> Option<PathBuf> {
    let root_uri = params.get("rootUri").and_then(serde_json::Value::as_str);
    let root_path = params.get("rootPath").and_then(serde_json::Value::as_str);
    let first_folder = params
        .get("workspaceFolders")
        .and_then(serde_json::Value::as_array)
        .and_then(|folders| folders.first())
        .and_then(|folder| folder.get("uri"))
        .and_then(serde_json::Value::as_str);
    root_uri
        .or(root_path)
        .or(first_folder)
        .filter(|root| !root.is_empty())
        .map(uri_label_path)
}

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
/// This is the LSP path that may create a GPU device. With a stdlib root the
/// document is checked as `laniusc check --stdlib-root ROOT FILE` checks it:
/// its imports are loaded from the root and checked unit by unit. The open
/// text is checked, not the file: when the two differ the text is written to
/// a private overlay file for the check. Without a root the document is
/// checked on its own. Like `laniusc check`, both build and discard x86-64
/// output only when the frontend check finds no impl for a call bound, since
/// only a build selects generic impls.
pub(super) fn diagnostic_items(
    uri: &str,
    source: &str,
    roots: &LspSourceRoots,
) -> Result<Vec<serde_json::Value>, String> {
    let Some(stdlib_root) = roots.stdlib_root.as_deref() else {
        return match pollster::block_on(type_check_source_with_gpu(source)) {
            Ok(()) => Ok(Vec::new()),
            Err(err) => compile_error_to_lsp_diagnostic_items(uri, None, err),
        };
    };
    let saved_path = uri
        .starts_with("file://")
        .then(|| uri_label_path(uri))
        .filter(|path| fs::read_to_string(path).is_ok_and(|saved| saved == source));
    let (entry, overlay) = match saved_path {
        Some(path) => (path, None),
        None => {
            let overlay = write_overlay(uri, source)?;
            (overlay.clone(), Some(overlay))
        }
    };
    let checked = pollster::block_on(type_check_entry_with_stdlib(&entry, stdlib_root));
    if let Some(overlay) = overlay {
        let _ = fs::remove_file(overlay);
    }
    match checked {
        Ok(()) => Ok(Vec::new()),
        Err(err) => compile_error_to_lsp_diagnostic_items(uri, Some(&entry), err),
    }
}

/// Writes unsaved document text where the loader can read it. The overlay
/// keeps the document's file name so labels and module paths read the same.
fn write_overlay(uri: &str, source: &str) -> Result<PathBuf, String> {
    let dir = std::env::temp_dir().join(format!("laniusc-lsp-{}", std::process::id()));
    fs::create_dir_all(&dir)
        .map_err(|err| format!("create LSP overlay directory {}: {err}", dir.display()))?;
    let name = uri_label_path(uri)
        .file_name()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("document.lani"));
    let path = dir.join(name);
    fs::write(&path, source)
        .map_err(|err| format!("write LSP overlay {}: {err}", path.display()))?;
    Ok(path)
}

/// `entry` is the file checked for the document, when imports were loaded.
/// A label in the entry is relabeled with the document's path. A label in an
/// imported file keeps its path and moves to `relatedInformation`, and the
/// diagnostic itself sits at the start of the document, since its range
/// must lie in the document it is reported for.
fn compile_error_to_lsp_diagnostic_items(
    uri: &str,
    entry: Option<&Path>,
    err: CompileError,
) -> Result<Vec<serde_json::Value>, String> {
    let mut diagnostic = err.into_public_diagnostic();
    let mut elsewhere = false;
    if let Some(label) = diagnostic.primary_label.as_mut() {
        if entry.is_none_or(|entry| same_file(&label.path, entry)) {
            label.path = uri_label_path(uri);
        } else {
            elsewhere = true;
        }
    }
    let lsp = diagnostic.to_lsp_diagnostic();
    let mut value =
        serde_json::to_value(&lsp).map_err(|err| format!("serialize LSP diagnostic: {err}"))?;
    if elsewhere && let Some(label) = diagnostic.primary_label.as_ref() {
        let related = serde_json::json!([{
            "location": {
                "uri": format!("file://{}", label.path.display()),
                "range": value["range"].clone(),
            },
            "message": format!(
                "{}:{}:{}: {}",
                label.path.display(),
                label.line,
                label.column,
                label.message
            ),
        }]);
        value["relatedInformation"] = related;
        value["range"] = serde_json::json!({
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 0 },
        });
    }
    Ok(vec![value])
}

fn same_file(left: &Path, right: &Path) -> bool {
    left == right
        || matches!(
            (fs::canonicalize(left), fs::canonicalize(right)),
            (Ok(left), Ok(right)) if left == right
        )
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
        .map(|path| PathBuf::from(percent_decoded(path)))
        .unwrap_or_else(|| PathBuf::from(uri))
}

/// Decodes `%XX` escapes in a `file:` URI path (a space is `%20`).
fn percent_decoded(path: &str) -> String {
    let bytes = path.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        let escape = (bytes[index] == b'%')
            .then(|| path.get(index + 1..index + 3))
            .flatten()
            .and_then(|hex| u8::from_str_radix(hex, 16).ok());
        match escape {
            Some(byte) => {
                decoded.push(byte);
                index += 3;
            }
            None => {
                decoded.push(bytes[index]);
                index += 1;
            }
        }
    }
    String::from_utf8(decoded).unwrap_or_else(|_| path.to_string())
}

#[cfg(test)]
mod tests {
    use super::compile_error_to_lsp_diagnostic_items;
    use crate::compiler::{CompileError, Diagnostic, DiagnosticLabel};

    #[test]
    fn lsp_diagnostic_items_lower_raw_compile_errors_without_internal_detail() {
        let items = compile_error_to_lsp_diagnostic_items(
            "file:///workspace/main.lani",
            None,
            CompileError::GpuFrontend("GPU LL(1) parser rejected token: 4".to_string()),
        )
        .expect("raw compiler fallback should serialize as an LSP diagnostic");

        assert_eq!(items.len(), 1);
        let diagnostic = &items[0];
        assert_eq!(diagnostic["code"], "LNC0057");
        assert_eq!(diagnostic["message"], "compiler execution failed");
        assert_eq!(diagnostic["data"]["category"], "tooling");
        assert!(
            diagnostic["data"]["primary_label"].is_null(),
            "spanless fallback diagnostics should remain spanless in metadata"
        );

        let rendered =
            serde_json::to_string(diagnostic).expect("LSP diagnostic JSON should serialize");
        assert!(!rendered.contains("GPU"));
        assert!(!rendered.contains("LL(1)"));
        assert!(!rendered.contains("parser rejected token"));
        assert!(!rendered.contains("frontend error"));
    }

    #[test]
    fn lsp_diagnostic_items_relabel_structured_compile_error_with_request_uri() {
        let items = compile_error_to_lsp_diagnostic_items(
            "file:///workspace/current.lani",
            None,
            CompileError::Diagnostic(
                Diagnostic::error("LNC0016", "syntax error").with_primary_label(
                    DiagnosticLabel::primary(
                        "stale-path.lani",
                        2,
                        5,
                        1,
                        Some("let x = ;".to_string()),
                        "expected an expression here",
                    ),
                ),
            ),
        )
        .expect("structured compiler diagnostic should serialize as an LSP diagnostic");

        assert_eq!(items.len(), 1);
        let diagnostic = &items[0];
        assert_eq!(diagnostic["code"], "LNC0016");
        assert_eq!(
            diagnostic["data"]["primary_label"]["path"],
            "/workspace/current.lani"
        );
        assert_eq!(
            diagnostic["data"]["primary_label"]["message"],
            "expected an expression here"
        );
        assert_eq!(diagnostic["range"]["start"]["line"], 1);
        assert_eq!(diagnostic["range"]["start"]["character"], 4);
    }
}
