use std::{collections::BTreeMap, path::Path};

use super::super::package_manifest::{
    is_package_module_reserved_segment,
    valid_package_module_ident_segment,
    valid_package_module_path_segment,
};
use crate::compiler::{CompileError, Diagnostic, diagnostic_label_from_source_span};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PathKind {
    Module,
    Import,
}

/// Leading import declaration parsed from a package source file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct LeadingImportPath {
    /// Parsed import path in canonical module syntax.
    pub(super) path: String,
    /// Byte offset where the import declaration begins.
    pub(super) start: usize,
    /// Byte length of the import declaration.
    pub(super) len: usize,
}

impl PathKind {
    fn label(self) -> &'static str {
        match self {
            PathKind::Module => "module",
            PathKind::Import => "import",
        }
    }
}

/// Parses an optional leading `module` declaration from a source file.
///
/// Imports before a module declaration and non-leading module declarations are
/// rejected with source diagnostics because package-lock discovery relies on
/// module declarations being the first semantic declaration in a file.
pub(super) fn leading_module_path(
    source: &str,
    source_path: &Path,
) -> Result<Option<String>, CompileError> {
    let bytes = source.as_bytes();
    let offset = skip_ws_and_comments(source, 0, source_path)?;
    if !keyword_at(bytes, offset, b"module") {
        if keyword_at(bytes, offset, b"import") {
            return Err(import_before_module_declaration_diagnostic(
                source,
                source_path,
                offset,
            ));
        }
        reject_non_leading_module_without_leading_declaration(source, offset, source_path)?;
        return Ok(None);
    }

    let offset = offset + "module".len();
    let (module_path, next_offset) = parse_path(source, offset, source_path, PathKind::Module)?;
    let next_offset = expect_semicolon(source, next_offset, source_path, "module")?;
    ensure_no_additional_module_declaration(source, next_offset, source_path, &module_path)?;
    Ok(Some(module_path))
}

/// Parses and validates the required module declaration for a package source file.
///
/// The declared module path must match the module path implied by the source
/// file's package-relative path.
pub(super) fn required_leading_module_path(
    source: &str,
    source_path: &Path,
    expected_relative_path: &Path,
    expected_module_path: &str,
) -> Result<String, CompileError> {
    let Some(module_path) = leading_module_path(source, source_path)? else {
        return Err(missing_leading_module_declaration_diagnostic(
            source,
            source_path,
            expected_relative_path,
            expected_module_path,
        ));
    };
    if module_path != expected_module_path {
        let module_start = skip_ws_and_comments(source, 0, source_path).unwrap_or(0);
        return Err(module_file_mapping_mismatch_diagnostic(
            source,
            source_path,
            module_start,
            module_declaration_label_len(source.as_bytes(), module_start),
            &module_path,
            expected_relative_path,
            expected_module_path,
        ));
    }
    Ok(module_path)
}

/// Returns leading import paths for a module source file.
///
/// The parser accepts only leading import declarations, rejects aliases and
/// quoted imports, and rejects imports of the module itself.
pub(super) fn leading_import_paths_for_module(
    source: &str,
    source_path: &Path,
    source_module_path: &str,
) -> Result<Vec<String>, CompileError> {
    leading_import_path_records_for_module(source, source_path, source_module_path).map(|imports| {
        imports
            .into_iter()
            .map(|import| import.path)
            .collect::<Vec<_>>()
    })
}

/// Returns leading import declarations with their source spans.
///
/// The span data is used for diagnostics while the path strings are used to
/// build the package-lock import graph.
pub(super) fn leading_import_path_records_for_module(
    source: &str,
    source_path: &Path,
    source_module_path: &str,
) -> Result<Vec<LeadingImportPath>, CompileError> {
    leading_import_paths(source, source_path, Some(source_module_path))
}

fn leading_import_paths(
    source: &str,
    source_path: &Path,
    source_module_path: Option<&str>,
) -> Result<Vec<LeadingImportPath>, CompileError> {
    let bytes = source.as_bytes();
    let mut imports = Vec::new();
    let mut seen_imports = BTreeMap::new();
    let mut offset = 0usize;

    loop {
        offset = skip_ws_and_comments(source, offset, source_path)?;
        if keyword_at(bytes, offset, b"module") {
            offset += "module".len();
            let (_, next_offset) = parse_path(source, offset, source_path, PathKind::Module)?;
            offset = expect_semicolon(source, next_offset, source_path, "module")?;
            continue;
        }
        if keyword_at(bytes, offset, b"import") {
            let import_start = offset;
            offset += "import".len();
            offset = skip_ws_and_comments(source, offset, source_path)?;
            if bytes.get(offset) == Some(&b'"') {
                let quoted_end = skip_quoted_import_path(source, offset, source_path)?;
                return Err(unsupported_import_form_diagnostic(
                    source,
                    source_path,
                    import_start,
                    quoted_end.saturating_sub(import_start),
                ));
            }
            let (path, next_offset) = parse_path(source, offset, source_path, PathKind::Import)?;
            offset = skip_ws_and_comments(source, next_offset, source_path)?;
            if keyword_at(bytes, offset, b"as") {
                return Err(unsupported_import_alias_diagnostic(
                    source,
                    source_path,
                    offset,
                    import_alias_label_len(source.as_bytes(), offset),
                ));
            }
            let declaration_end = expect_semicolon(source, offset, source_path, "import")?;
            if source_module_path == Some(path.as_str()) {
                return Err(self_import_diagnostic(
                    source,
                    source_path,
                    import_start,
                    declaration_end.saturating_sub(import_start),
                    &path,
                ));
            }
            if let Some(first_import_start) = seen_imports.get(&path) {
                return Err(duplicate_leading_import_diagnostic(
                    source,
                    source_path,
                    import_start,
                    declaration_end.saturating_sub(import_start),
                    &path,
                    *first_import_start,
                ));
            }
            seen_imports.insert(path.clone(), import_start);
            offset = declaration_end;
            imports.push(LeadingImportPath {
                path,
                start: import_start,
                len: declaration_end.saturating_sub(import_start),
            });
            continue;
        }
        reject_non_leading_imports(source, offset, source_path)?;
        return Ok(imports);
    }
}

/// Returns whether a string is a valid package-lock import path.
pub(super) fn valid_import_path(path: &str) -> bool {
    valid_module_like_path(path)
}

/// Returns whether a string is a valid package-lock module path.
pub(super) fn valid_module_path(path: &str) -> bool {
    valid_module_like_path(path)
}

/// Converts a dotted package name into a module path, if every segment is valid.
///
/// Package names use `.` separators, while source modules use `::` separators.
/// Invalid or reserved module segments return `None`.
pub(super) fn package_name_module_path(package: &str) -> Option<String> {
    let segments = package.split('.').collect::<Vec<_>>();
    if segments.is_empty()
        || !segments
            .iter()
            .all(|segment| valid_package_module_path_segment(segment))
    {
        return None;
    }
    Some(segments.join("::"))
}

fn reject_non_leading_module_without_leading_declaration(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<(), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = offset;

    while offset < bytes.len() {
        offset = skip_ws_and_comments(source, offset, source_path)?;
        if offset >= bytes.len() {
            break;
        }
        if bytes.get(offset) == Some(&b'"') {
            offset = skip_string_literal(source, offset, source_path)?;
            continue;
        }
        if bytes.get(offset) == Some(&b'\'') {
            offset = skip_char_literal(source, offset, source_path)?;
            continue;
        }
        if keyword_at_anywhere(bytes, offset, b"module") {
            let module_start = offset;
            offset += "module".len();
            let (module_path, _) = parse_path(source, offset, source_path, PathKind::Module)?;
            return Err(non_leading_module_without_leading_declaration_diagnostic(
                source,
                source_path,
                module_start,
                &module_path,
            ));
        }
        offset += 1;
    }

    Ok(())
}

fn reject_non_leading_imports(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<(), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = offset;

    while offset < bytes.len() {
        offset = skip_ws_and_comments(source, offset, source_path)?;
        if offset >= bytes.len() {
            break;
        }
        if bytes.get(offset) == Some(&b'"') {
            offset = skip_string_literal(source, offset, source_path)?;
            continue;
        }
        if bytes.get(offset) == Some(&b'\'') {
            offset = skip_char_literal(source, offset, source_path)?;
            continue;
        }
        if keyword_at_anywhere(bytes, offset, b"import") {
            return Err(non_leading_import_diagnostic(source, source_path, offset));
        }
        offset += 1;
    }

    Ok(())
}

fn ensure_no_additional_module_declaration(
    source: &str,
    offset: usize,
    source_path: &Path,
    first_module_path: &str,
) -> Result<(), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = offset;
    let mut still_leading_declarations = true;

    loop {
        offset = skip_ws_and_comments(source, offset, source_path)?;
        if offset >= bytes.len() {
            return Ok(());
        }
        if keyword_at_anywhere(bytes, offset, b"module") {
            let module_start = offset;
            offset += "module".len();
            let (module_path, _) = parse_path(source, offset, source_path, PathKind::Module)?;
            if still_leading_declarations {
                return Err(multiple_leading_module_declarations_diagnostic(
                    source,
                    source_path,
                    module_start,
                    first_module_path,
                    &module_path,
                ));
            }
            return Err(non_leading_module_after_leading_declaration_diagnostic(
                source,
                source_path,
                module_start,
                first_module_path,
                &module_path,
            ));
        }
        if still_leading_declarations && keyword_at(bytes, offset, b"import") {
            let import_start = offset;
            offset += "import".len();
            offset = skip_ws_and_comments(source, offset, source_path)?;
            if bytes.get(offset) == Some(&b'"') {
                let quoted_end = skip_quoted_import_path(source, offset, source_path)?;
                return Err(unsupported_import_form_diagnostic(
                    source,
                    source_path,
                    import_start,
                    quoted_end.saturating_sub(import_start),
                ));
            } else {
                let (_, next_offset) = parse_path(source, offset, source_path, PathKind::Import)?;
                offset = next_offset;
            }
            offset = skip_ws_and_comments(source, offset, source_path)?;
            if keyword_at(bytes, offset, b"as") {
                return Err(unsupported_import_alias_diagnostic(
                    source,
                    source_path,
                    offset,
                    import_alias_label_len(source.as_bytes(), offset),
                ));
            }
            offset = expect_semicolon(source, offset, source_path, "import")?;
            continue;
        }
        still_leading_declarations = false;
        if bytes.get(offset) == Some(&b'"') {
            offset = skip_string_literal(source, offset, source_path)?;
        } else if bytes.get(offset) == Some(&b'\'') {
            offset = skip_char_literal(source, offset, source_path)?;
        } else {
            offset += 1;
        }
    }
}

fn parse_path(
    source: &str,
    offset: usize,
    source_path: &Path,
    kind: PathKind,
) -> Result<(String, usize), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = skip_ws_and_comments(source, offset, source_path)?;
    let mut segments = Vec::new();

    loop {
        let segment_start = offset;
        if kind == PathKind::Import && bytes.get(segment_start) == Some(&b'*') {
            return Err(unsupported_import_glob_diagnostic(
                source,
                source_path,
                segment_start,
            ));
        }
        offset = match parse_ident(bytes, offset) {
            Some(offset) => offset,
            None => {
                if let Some(segment_end) = invalid_path_segment_tail_end(source, segment_start) {
                    return Err(invalid_path_segment_diagnostic(
                        source,
                        source_path,
                        segment_start,
                        &source[segment_start..segment_end],
                        kind,
                    ));
                }
                return Err(expected_path_segment_diagnostic(
                    source,
                    source_path,
                    segment_start,
                    kind,
                ));
            }
        };
        if let Some(segment_end) = invalid_path_segment_tail_end(source, offset) {
            return Err(invalid_path_segment_diagnostic(
                source,
                source_path,
                segment_start,
                &source[segment_start..segment_end],
                kind,
            ));
        }
        let segment = &source[segment_start..offset];
        if !valid_package_module_path_segment(segment) {
            return Err(invalid_path_segment_diagnostic(
                source,
                source_path,
                segment_start,
                segment,
                kind,
            ));
        }
        segments.push(segment);
        let segment_end = offset;
        let separator_offset = skip_ws_and_comments(source, offset, source_path)?;
        if invalid_path_separator(bytes, separator_offset) {
            return Err(path_separator_diagnostic(
                source,
                source_path,
                separator_offset,
                kind,
            ));
        }
        if bytes.get(separator_offset..separator_offset + 2) != Some(b"::") {
            offset = segment_end;
            break;
        }
        offset = separator_offset + 2;
        offset = skip_ws_and_comments(source, offset, source_path)?;
    }

    Ok((segments.join("::"), offset))
}

fn invalid_path_separator(bytes: &[u8], offset: usize) -> bool {
    match bytes.get(offset) {
        Some(b'/' | b'\\' | b'.') => true,
        Some(b':') => bytes.get(offset..offset + 2) != Some(b"::"),
        _ => false,
    }
}

fn invalid_path_segment_tail_end(source: &str, start: usize) -> Option<usize> {
    let byte = *source.as_bytes().get(start)?;
    if byte.is_ascii_whitespace() || matches!(byte, b';' | b':' | b'/' | b'\\' | b'.') {
        return None;
    }

    let mut end = start;
    for (relative_index, ch) in source[start..].char_indices() {
        if ch.is_whitespace() || matches!(ch, ';' | ':' | '/' | '\\' | '.') {
            break;
        }
        end = start + relative_index + ch.len_utf8();
    }

    (end > start).then_some(end)
}

fn path_separator_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    kind: PathKind,
) -> CompileError {
    let label_message = format!("{} paths must use `::` separators", kind.label());
    match kind {
        PathKind::Module => CompileError::Diagnostic(
            Diagnostic::error("LNC0016", "syntax error")
                .with_primary_label(diagnostic_label_from_source_span(
                    source_path,
                    source,
                    start,
                    1,
                    label_message,
                ))
                .with_note(
                    "package replay does not normalize filesystem path separators or package-name separators into module declarations",
                )
                .with_note(
                    "module identity must come from source module-path declarations such as `module app::main;`",
                ),
        ),
        PathKind::Import => CompileError::Diagnostic(
            Diagnostic::error("LNC0011", "unsupported import form")
                .with_primary_label(diagnostic_label_from_source_span(
                    source_path,
                    source,
                    start,
                    1,
                    label_message,
                ))
                .with_note(
                    "package lockfile import graphs record module-path imports such as `import app::module;`",
                )
                .with_note(
                    "filesystem path separators and package-name separators cannot be normalized into semantic module identity during package replay",
                ),
        ),
    }
}

fn expected_path_segment_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    kind: PathKind,
) -> CompileError {
    let label_message = format!("expected {} path segment", kind.label());
    match kind {
        PathKind::Module => CompileError::Diagnostic(
            Diagnostic::error("LNC0016", "syntax error").with_primary_label(
                diagnostic_label_from_source_span(source_path, source, start, 1, label_message),
            ),
        ),
        PathKind::Import => CompileError::Diagnostic(
            Diagnostic::error("LNC0011", "unsupported import form")
                .with_primary_label(diagnostic_label_from_source_span(
                    source_path,
                    source,
                    start,
                    1,
                    label_message,
                ))
                .with_note(
                    "package replay metadata records module-path imports such as `import app::module;`",
                )
                .with_note(
                    "import paths must use source identifier segments so persisted import graphs cannot encode non-source module evidence",
                ),
        ),
    }
}

fn invalid_path_segment_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    segment: &str,
    kind: PathKind,
) -> CompileError {
    let label_message = format!("invalid {} path segment", kind.label());
    let invalid_segment_note = invalid_path_segment_note(segment, kind);
    match kind {
        PathKind::Module => CompileError::Diagnostic(
            Diagnostic::error("LNC0016", "syntax error")
                .with_primary_label(diagnostic_label_from_source_span(
                    source_path,
                    source,
                    start,
                    segment.len(),
                    label_message,
                ))
                .with_note(
                    "module declarations in package replay metadata must use source identifier segments",
                )
                .with_note(invalid_segment_note),
        ),
        PathKind::Import => CompileError::Diagnostic(
            Diagnostic::error("LNC0011", "unsupported import form")
                .with_primary_label(diagnostic_label_from_source_span(
                    source_path,
                    source,
                    start,
                    segment.len(),
                    label_message,
                ))
                .with_note(
                    "package replay metadata records module-path imports such as `import app::module;`",
                )
                .with_note(invalid_segment_note),
        ),
    }
}

fn invalid_path_segment_note(segment: &str, kind: PathKind) -> String {
    if is_package_module_reserved_segment(segment) {
        return format!(
            "reserved keywords cannot be used as {} path segments because module identity comes from parsed module/import records",
            kind.label()
        );
    }
    if !valid_package_module_ident_segment(segment) {
        return format!(
            "{} path segments must be ASCII identifiers; package replay does not normalize package-name or filesystem punctuation into module identity",
            kind.label()
        );
    }
    format!(
        "{} path segments must be source identifiers and must not be reserved keywords",
        kind.label()
    )
}

fn skip_quoted_import_path(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    skip_string_literal(source, offset, source_path)
}

fn unsupported_import_form_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                len,
                "package lockfiles require module-path imports here",
            ))
            .with_note(
                "package lockfile import graphs record module-path imports such as `import app::module;`",
            )
            .with_note(
                "quoted imports are unsupported in this edition and are rejected instead of being persisted as incomplete package metadata",
            ),
    )
}

fn unsupported_import_alias_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                len,
                "import aliases are not supported by package replay",
            ))
            .with_note(
                "package lockfile import graphs currently persist module-path imports such as `import app::module;`",
            )
            .with_note(
                "alias metadata must be represented by parsed module/import records before lockfiles can replay it",
            ),
    )
}

fn unsupported_import_glob_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                1,
                "import globs are not supported by package replay",
            ))
            .with_note(
                "package lockfile import graphs currently persist explicit module-path imports such as `import app::module;`",
            )
            .with_note(
                "glob visibility must be represented by parsed module/import records before lockfiles can replay it",
            ),
    )
}

fn import_before_module_declaration_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                "import".len(),
                "imports must follow a leading module declaration",
            ))
            .with_note(
                "package replay requires the source module identity before collecting import graph edges",
            )
            .with_note(
                "move `module path;` before imports so control-plane source paths cannot stand in for source module identity",
            ),
    )
}

fn import_alias_label_len(bytes: &[u8], start: usize) -> usize {
    let mut end = start + "as".len();
    while bytes
        .get(end)
        .is_some_and(|byte| byte.is_ascii_whitespace())
    {
        end += 1;
    }
    if let Some(alias_end) = parse_ident(bytes, end) {
        end = alias_end;
    }
    end.saturating_sub(start)
}

fn non_leading_import_diagnostic(source: &str, source_path: &Path, start: usize) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                "import".len(),
                "imports must appear before other items",
            ))
            .with_note(
                "package replay metadata stays complete only when module-path imports are leading declarations",
            )
            .with_note(
                "move package imports before functions, constants, structs, and other items",
            ),
    )
}

fn self_import_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
    import_path: &str,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                len.max("import".len()),
                "module imports itself",
            ))
            .with_note(format!(
                "source module `{import_path}` cannot import its own module path"
            ))
            .with_note(
                "package replay rejects self-imports before persisting import graph metadata so lockfiles cannot make control-plane paths stand in for source module identity",
            ),
    )
}

fn duplicate_leading_import_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
    import_path: &str,
    first_import_start: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                len.max("import".len()),
                "duplicate import declaration",
            ))
            .with_note(format!(
                "package replay found repeated leading import `{import_path}` in one source file"
            ))
            .with_note(format!(
                "first `{import_path}` import appears earlier in this source file on line {}",
                source_line_number_at(source, first_import_start)
            ))
            .with_note(
                "package lockfiles require one source-level import declaration per module path until duplicate import semantics are represented by parsed import records",
            ),
    )
}

fn source_line_number_at(source: &str, offset: usize) -> usize {
    source
        .as_bytes()
        .iter()
        .take(offset.min(source.len()))
        .filter(|byte| **byte == b'\n')
        .count()
        + 1
}

fn non_leading_module_without_leading_declaration_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    module_path: &str,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                "module".len(),
                "module declarations must appear before other items",
            ))
            .with_note(
                "package replay metadata requires the first non-comment declaration in each source file to be its module path",
            )
            .with_note(format!(
                "found non-leading module declaration `{module_path}`; move it to the start of the file or remove it",
            )),
    )
}

fn multiple_leading_module_declarations_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    first_module_path: &str,
    module_path: &str,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                "module".len(),
                "duplicate module declaration",
            ))
            .with_note(
                "package replay metadata requires exactly one leading module declaration per source file",
            )
            .with_note(format!(
                "found leading module declaration `{module_path}` after leading module `{first_module_path}`; remove the duplicate so persisted source identity is unambiguous",
            )),
    )
}

fn non_leading_module_after_leading_declaration_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    first_module_path: &str,
    module_path: &str,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                "module".len(),
                "module declarations must appear before other items",
            ))
            .with_note(
                "package replay metadata requires exactly one leading module declaration per source file",
            )
            .with_note(format!(
                "found non-leading module declaration `{module_path}` after leading module `{first_module_path}`; remove it or keep only the source file's module identity",
            )),
    )
}

fn missing_leading_module_declaration_diagnostic(
    source: &str,
    source_path: &Path,
    expected_relative_path: &Path,
    expected_module_path: &str,
) -> CompileError {
    let start = skip_ws_and_comments(source, 0, source_path).unwrap_or(0);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                start,
                1,
                "expected leading module declaration",
            ))
            .with_note(
                "package replay metadata requires the first non-comment declaration in each source file to be its module path",
            )
            .with_note(format!(
                "resolved source-root relative path {} maps to expected module `{expected_module_path}`",
                expected_relative_path.display()
            ))
            .with_note(format!(
                "add `module {expected_module_path};` before imports or items so stale source-root metadata cannot stand in for source module identity",
            )),
    )
}

fn module_file_mapping_mismatch_diagnostic(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
    module_path: &str,
    expected_relative_path: &Path,
    expected_module_path: &str,
) -> CompileError {
    let mut diagnostic = Diagnostic::error("LNC0015", "invalid module path")
        .with_primary_label(diagnostic_label_from_source_span(
            source_path,
            source,
            start,
            len,
            "module declaration does not match source-root path",
        ))
        .with_note(format!(
            "source declares module `{module_path}`, but resolved source-root relative path {} maps to `{expected_module_path}`",
            expected_relative_path.display()
        ));
    if let Some(extra_prefix) = module_path
        .strip_suffix(expected_module_path)
        .and_then(|prefix| prefix.strip_suffix("::"))
        .filter(|prefix| !prefix.is_empty())
    {
        diagnostic = diagnostic.with_note(format!(
            "declared module prefix `{extra_prefix}` is not part of source-root relative module `{expected_module_path}`; package names and source-root directory names are control-plane loading metadata and must not be prepended to source module declarations",
        ));
    }
    CompileError::Diagnostic(diagnostic.with_note(
        "package replay validates file-to-module metadata before writing lockfiles so source-root paths cannot replace source module declarations",
    ))
}

fn module_declaration_label_len(bytes: &[u8], start: usize) -> usize {
    let mut end = start.min(bytes.len());
    while end < bytes.len() && bytes.get(end) != Some(&b';') && bytes.get(end) != Some(&b'\n') {
        end += 1;
    }
    if bytes.get(end) == Some(&b';') {
        end += 1;
    }
    end.saturating_sub(start).max("module".len())
}

fn skip_string_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    skip_quoted_literal(source, offset, source_path, b'"', "string literal")
}

fn skip_char_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    skip_quoted_literal(source, offset, source_path, b'\'', "character literal")
}

fn skip_quoted_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
    quote: u8,
    label: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let literal_start = offset;
    let mut offset = offset + 1;
    while let Some(byte) = bytes.get(offset) {
        if *byte == b'\\' {
            if bytes
                .get(offset + 1)
                .is_none_or(|next| matches!(*next, b'\n' | b'\r'))
            {
                return Err(malformed_literal_error(
                    source,
                    source_path,
                    literal_start,
                    label,
                ));
            }
            offset = (offset + 2).min(bytes.len());
            continue;
        }
        if matches!(*byte, b'\n' | b'\r') {
            return Err(malformed_literal_error(
                source,
                source_path,
                literal_start,
                label,
            ));
        }
        if *byte == quote {
            return Ok(offset + 1);
        }
        offset += 1;
    }
    Err(malformed_literal_error(
        source,
        source_path,
        literal_start,
        label,
    ))
}

fn malformed_literal_error(
    source: &str,
    source_path: &Path,
    offset: usize,
    label: &str,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                offset,
                1,
                format!("malformed {label}"),
            ))
            .with_note(
                "package source-root replay must not skip malformed literals while discovering module/import metadata",
            ),
    )
}

fn expect_semicolon(
    source: &str,
    offset: usize,
    source_path: &Path,
    context: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let semicolon_offset = offset;
    let offset = skip_ws_and_comments(source, offset, source_path)?;
    if bytes.get(offset) == Some(&b';') {
        return Ok(offset + 1);
    }
    Err(missing_semicolon_diagnostic(
        source,
        source_path,
        semicolon_offset,
        context,
    ))
}

fn missing_semicolon_diagnostic(
    source: &str,
    source_path: &Path,
    offset: usize,
    context: &str,
) -> CompileError {
    let label_offset = missing_semicolon_label_offset(source.as_bytes(), offset);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                label_offset,
                1,
                format!("expected ';' after {context} path"),
            ))
            .with_note(
                "package replay records leading module/import metadata exactly as parsed from source",
            )
            .with_note(
                "terminate module and import declarations before other package source items",
            ),
    )
}

fn missing_semicolon_label_offset(bytes: &[u8], offset: usize) -> usize {
    let mut offset = offset.min(bytes.len());
    if bytes
        .get(offset)
        .is_some_and(|byte| !byte.is_ascii_whitespace())
    {
        return offset;
    }
    while offset > 0
        && bytes
            .get(offset - 1)
            .is_some_and(|byte| byte.is_ascii_whitespace())
    {
        offset -= 1;
    }
    offset
}

fn skip_ws_and_comments(
    source: &str,
    mut offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    loop {
        while bytes
            .get(offset)
            .is_some_and(|byte| byte.is_ascii_whitespace())
        {
            offset += 1;
        }
        if bytes.get(offset..offset + 2) == Some(b"//") {
            offset += 2;
            while bytes.get(offset).is_some_and(|byte| *byte != b'\n') {
                offset += 1;
            }
            continue;
        }
        if bytes.get(offset..offset + 2) == Some(b"/*") {
            let comment_start = offset;
            offset += 2;
            while offset + 1 < bytes.len() && bytes.get(offset..offset + 2) != Some(b"*/") {
                offset += 1;
            }
            if offset + 1 >= bytes.len() {
                return Err(unterminated_block_comment_error(
                    source,
                    source_path,
                    comment_start,
                ));
            }
            offset += 2;
            continue;
        }
        return Ok(offset);
    }
}

fn unterminated_block_comment_error(
    source: &str,
    source_path: &Path,
    offset: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(diagnostic_label_from_source_span(
                source_path,
                source,
                offset,
                2,
                "unterminated block comment",
            ))
            .with_note(
                "package source-root replay must not skip malformed comments while discovering module/import metadata",
            ),
    )
}

fn keyword_at(bytes: &[u8], offset: usize, keyword: &[u8]) -> bool {
    bytes.get(offset..offset + keyword.len()) == Some(keyword)
        && bytes
            .get(offset + keyword.len())
            .is_none_or(|byte| !is_ident_continue(*byte))
}

fn keyword_at_anywhere(bytes: &[u8], offset: usize, keyword: &[u8]) -> bool {
    keyword_at(bytes, offset, keyword)
        && offset
            .checked_sub(1)
            .and_then(|previous| bytes.get(previous))
            .is_none_or(|byte| !is_ident_continue(*byte))
}

fn parse_ident(bytes: &[u8], offset: usize) -> Option<usize> {
    let first = *bytes.get(offset)?;
    if !is_ident_start(first) {
        return None;
    }
    let mut end = offset + 1;
    while bytes.get(end).is_some_and(|byte| is_ident_continue(*byte)) {
        end += 1;
    }
    Some(end)
}

fn valid_module_like_path(path: &str) -> bool {
    let mut count = 0usize;
    for segment in path.split("::") {
        count += 1;
        if !valid_package_module_path_segment(segment) {
            return false;
        }
    }
    count != 0
}

fn is_ident_start(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphabetic()
}

fn is_ident_continue(byte: u8) -> bool {
    is_ident_start(byte) || byte.is_ascii_digit()
}
