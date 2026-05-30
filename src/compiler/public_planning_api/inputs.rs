use super::*;

pub fn load_explicit_source_pack_manifest_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<ExplicitSourcePack, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let mut libraries = Vec::with_capacity(2);
    let stdlib_sources = read_explicit_source_paths("stdlib", stdlib_paths)?;
    let has_stdlib_sources = !stdlib_sources.is_empty();
    if !stdlib_sources.is_empty() {
        libraries.push(ExplicitSourceLibrary {
            library_id: 0,
            sources: stdlib_sources,
            dependency_library_ids: Vec::new(),
        });
    }
    let user_sources = read_explicit_source_paths("user", user_paths)?;
    if !user_sources.is_empty() {
        libraries.push(ExplicitSourceLibrary {
            library_id: 1,
            sources: user_sources,
            dependency_library_ids: if has_stdlib_sources {
                vec![0]
            } else {
                Vec::new()
            },
        });
    }
    let source_paths = stdlib_paths
        .iter()
        .map(|path| Some(path.as_ref().to_path_buf()))
        .chain(
            user_paths
                .iter()
                .map(|path| Some(path.as_ref().to_path_buf())),
        )
        .collect();
    ExplicitSourcePack::from_libraries(libraries)?.with_source_paths(source_paths)
}

pub fn load_entry_with_stdlib<EP, RP>(
    entry_path: EP,
    stdlib_root: RP,
) -> Result<ExplicitSourcePack, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root.as_ref().to_path_buf()),
        user_roots: Vec::new(),
    };
    load_entry_with_source_roots(entry_path, &roots)
}

pub fn load_entry_with_source_root<EP, RP>(
    entry_path: EP,
    source_root: RP,
) -> Result<ExplicitSourcePack, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: None,
        user_roots: vec![source_root.as_ref().to_path_buf()],
    };
    load_entry_with_source_roots(entry_path, &roots)
}

pub fn load_entry_with_source_roots<EP>(
    entry_path: EP,
    roots: &EntrySourceRoots,
) -> Result<ExplicitSourcePack, CompileError>
where
    EP: AsRef<Path>,
{
    let (stdlib_paths, user_paths) = collect_entry_source_root_paths(entry_path.as_ref(), roots)?;
    load_explicit_source_pack_manifest_from_paths(&stdlib_paths, &user_paths)
}

pub fn load_entry_with_source_root_and_stdlib<EP, UP, SP>(
    entry_path: EP,
    source_root: UP,
    stdlib_root: SP,
) -> Result<ExplicitSourcePack, CompileError>
where
    EP: AsRef<Path>,
    UP: AsRef<Path>,
    SP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root.as_ref().to_path_buf()),
        user_roots: vec![source_root.as_ref().to_path_buf()],
    };
    load_entry_with_source_roots(entry_path, &roots)
}

pub fn load_entry_with_source_root_and_optional_stdlib<EP, UP, SP>(
    entry_path: EP,
    source_root: UP,
    stdlib_root: Option<SP>,
) -> Result<ExplicitSourcePack, CompileError>
where
    EP: AsRef<Path>,
    UP: AsRef<Path>,
    SP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: stdlib_root.map(|path| path.as_ref().to_path_buf()),
        user_roots: vec![source_root.as_ref().to_path_buf()],
    };
    let (stdlib_paths, user_paths) = collect_entry_source_root_paths(entry_path.as_ref(), &roots)?;
    load_explicit_source_pack_manifest_from_paths(&stdlib_paths, &user_paths)
}

pub fn load_explicit_source_pack_path_manifest_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let mut libraries = Vec::with_capacity(2);
    let has_stdlib_sources = !stdlib_paths.is_empty();
    if has_stdlib_sources {
        libraries.push(ExplicitSourceLibraryPaths {
            library_id: 0,
            paths: stdlib_paths
                .iter()
                .map(|path| path.as_ref().to_path_buf())
                .collect(),
            dependency_library_ids: Vec::new(),
        });
    }
    if !user_paths.is_empty() {
        libraries.push(ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: user_paths
                .iter()
                .map(|path| path.as_ref().to_path_buf())
                .collect(),
            dependency_library_ids: if has_stdlib_sources {
                vec![0]
            } else {
                Vec::new()
            },
        });
    }
    ExplicitSourcePackPathManifest::from_libraries(libraries)
}

pub fn load_entry_path_manifest_with_stdlib<EP, RP>(
    entry_path: EP,
    stdlib_root: RP,
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root.as_ref().to_path_buf()),
        user_roots: Vec::new(),
    };
    load_entry_path_manifest_with_source_roots(entry_path, &roots)
}

pub fn load_entry_path_manifest_with_source_root<EP, RP>(
    entry_path: EP,
    source_root: RP,
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: None,
        user_roots: vec![source_root.as_ref().to_path_buf()],
    };
    load_entry_path_manifest_with_source_roots(entry_path, &roots)
}

pub fn load_entry_path_manifest_with_source_roots<EP>(
    entry_path: EP,
    roots: &EntrySourceRoots,
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    EP: AsRef<Path>,
{
    let (stdlib_paths, user_paths) = collect_entry_source_root_paths(entry_path.as_ref(), roots)?;
    load_explicit_source_pack_path_manifest_from_paths(&stdlib_paths, &user_paths)
}

pub fn load_entry_path_manifest_with_source_root_and_stdlib<EP, UP, SP>(
    entry_path: EP,
    source_root: UP,
    stdlib_root: SP,
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    EP: AsRef<Path>,
    UP: AsRef<Path>,
    SP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root.as_ref().to_path_buf()),
        user_roots: vec![source_root.as_ref().to_path_buf()],
    };
    load_entry_path_manifest_with_source_roots(entry_path, &roots)
}

pub fn load_entry_path_manifest_with_source_root_and_optional_stdlib<EP, UP, SP>(
    entry_path: EP,
    source_root: UP,
    stdlib_root: Option<SP>,
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    EP: AsRef<Path>,
    UP: AsRef<Path>,
    SP: AsRef<Path>,
{
    let roots = EntrySourceRoots {
        stdlib_root: stdlib_root.map(|path| path.as_ref().to_path_buf()),
        user_roots: vec![source_root.as_ref().to_path_buf()],
    };
    let (stdlib_paths, user_paths) = collect_entry_source_root_paths(entry_path.as_ref(), &roots)?;
    load_explicit_source_pack_path_manifest_from_paths(&stdlib_paths, &user_paths)
}

pub fn load_explicit_source_libraries_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<ExplicitSourcePack, CompileError>
where
    P: AsRef<Path>,
{
    let mut source_libraries = Vec::with_capacity(libraries.len());
    let mut source_paths_by_library = BTreeMap::new();
    for library in libraries {
        let label = format!("library {}", library.library_id);
        let source_paths = library
            .paths
            .iter()
            .map(|path| Some(path.as_ref().to_path_buf()))
            .collect::<Vec<_>>();
        let sources = read_explicit_source_paths(&label, &library.paths)?;
        source_paths_by_library.insert(library.library_id, (0usize, source_paths));
        source_libraries.push(ExplicitSourceLibrary {
            library_id: library.library_id,
            sources,
            dependency_library_ids: library.dependency_library_ids,
        });
    }
    let source_pack = ExplicitSourcePack::from_libraries(source_libraries)?;
    let mut source_paths = Vec::with_capacity(source_pack.sources.len());
    for library_id in &source_pack.library_ids {
        let (next_index, library_paths) =
            source_paths_by_library.get_mut(library_id).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "explicit source pack path lookup lost library {library_id}"
                ))
            })?;
        let path = library_paths.get(*next_index).cloned().ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "explicit source pack path lookup lost source {} for library {library_id}",
                *next_index
            ))
        })?;
        *next_index += 1;
        source_paths.push(path);
    }
    source_pack.with_source_paths(source_paths)
}

const SOURCE_ROOT_IMPORT_FILE_LIMIT: usize = 1024;
const SOURCE_ROOT_IMPORT_PATH_SEGMENT_LIMIT: usize = 8;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct EntrySourceRoots {
    pub stdlib_root: Option<PathBuf>,
    pub user_roots: Vec<PathBuf>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceRootImport {
    path: String,
    source_path: PathBuf,
    line: usize,
    column: usize,
    source_line: String,
    label_len: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SourceRootLibrary {
    Stdlib,
    User,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceRootSearchRoot {
    library: SourceRootLibrary,
    label: &'static str,
    root: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceRootResolvedImport {
    library: SourceRootLibrary,
    root_label: &'static str,
    path: PathBuf,
}

fn collect_entry_source_root_paths(
    entry_path: &Path,
    roots: &EntrySourceRoots,
) -> Result<(Vec<PathBuf>, Vec<PathBuf>), CompileError> {
    let entry_path = entry_path.to_path_buf();
    let mut search_roots = Vec::with_capacity(roots.user_roots.len() + 1);
    for source_root in &roots.user_roots {
        search_roots.push(canonical_source_root(
            "source root",
            source_root,
            SourceRootLibrary::User,
        )?);
    }
    if let Some(stdlib_root) = &roots.stdlib_root {
        search_roots.push(canonical_source_root(
            "stdlib root",
            stdlib_root,
            SourceRootLibrary::Stdlib,
        )?);
    }
    if search_roots.is_empty() {
        return Err(CompileError::GpuFrontend(
            "source-root import loading requires at least one source root".into(),
        ));
    }

    let mut loaded_source_paths = BTreeSet::new();
    let mut stdlib_paths = Vec::new();
    let mut user_paths = vec![entry_path.clone()];

    let entry_source = read_source_for_import_discovery("entry", &entry_path)?;
    if let Ok(canonical_entry_path) = fs::canonicalize(&entry_path) {
        loaded_source_paths.insert(canonical_entry_path);
    }
    let entry_imports = leading_path_imports(&entry_source, &entry_path)?;

    for import in entry_imports {
        load_source_root_import(
            &import,
            SourceRootLibrary::User,
            &search_roots,
            &entry_path,
            &mut loaded_source_paths,
            &mut stdlib_paths,
            &mut user_paths,
        )?;
    }

    Ok((stdlib_paths, user_paths))
}

fn canonical_source_root(
    label: &'static str,
    root: &Path,
    library: SourceRootLibrary,
) -> Result<SourceRootSearchRoot, CompileError> {
    let root = fs::canonicalize(root).map_err(|err| {
        CompileError::GpuFrontend(format!("canonicalize {label} {}: {err}", root.display()))
    })?;
    if !root.is_dir() {
        return Err(CompileError::GpuFrontend(format!(
            "{label} {} is not a directory",
            root.display()
        )));
    }
    Ok(SourceRootSearchRoot {
        library,
        label,
        root,
    })
}

fn load_source_root_import(
    import: &SourceRootImport,
    importer_library: SourceRootLibrary,
    roots: &[SourceRootSearchRoot],
    entry_path: &Path,
    loaded_source_paths: &mut BTreeSet<PathBuf>,
    stdlib_paths: &mut Vec<PathBuf>,
    user_paths: &mut Vec<PathBuf>,
) -> Result<(), CompileError> {
    let resolved_import = resolve_source_root_import(import, roots, importer_library)?;
    if loaded_source_paths.contains(&resolved_import.path) {
        return Ok(());
    }

    let imported_file_count = stdlib_paths.len() + user_paths.len().saturating_sub(1);
    if imported_file_count >= SOURCE_ROOT_IMPORT_FILE_LIMIT {
        return Err(CompileError::GpuFrontend(format!(
            "source-root import loading reached the limit of {SOURCE_ROOT_IMPORT_FILE_LIMIT} imported files while loading {}",
            entry_path.display()
        )));
    }

    let imported_source =
        read_source_for_import_discovery("source-root import", &resolved_import.path)?;
    let nested_imports = leading_path_imports(&imported_source, &resolved_import.path)?;
    loaded_source_paths.insert(resolved_import.path.clone());
    let nested_importer_library = resolved_import.library;
    match resolved_import.library {
        SourceRootLibrary::Stdlib => stdlib_paths.push(resolved_import.path),
        SourceRootLibrary::User => user_paths.push(resolved_import.path),
    }
    for nested_import in nested_imports {
        load_source_root_import(
            &nested_import,
            nested_importer_library,
            roots,
            entry_path,
            loaded_source_paths,
            stdlib_paths,
            user_paths,
        )?;
    }

    Ok(())
}

fn resolve_source_root_import(
    import: &SourceRootImport,
    roots: &[SourceRootSearchRoot],
    importer_library: SourceRootLibrary,
) -> Result<SourceRootResolvedImport, CompileError> {
    let mut searched_paths = Vec::with_capacity(roots.len());

    if importer_library == SourceRootLibrary::Stdlib {
        let mut stdlib_matches = collect_source_root_import_matches(
            import,
            roots
                .iter()
                .filter(|root| root.library == SourceRootLibrary::Stdlib),
            &mut searched_paths,
        )?;
        if stdlib_matches.len() > 1 {
            return Err(ambiguous_source_root_module_error(import, &stdlib_matches));
        }
        if let Some(stdlib_match) = stdlib_matches.pop() {
            return Ok(stdlib_match);
        }

        let user_matches = collect_source_root_import_matches(
            import,
            roots
                .iter()
                .filter(|root| root.library == SourceRootLibrary::User),
            &mut searched_paths,
        )?;
        if !user_matches.is_empty() {
            return Err(source_root_package_boundary_error(import, &user_matches));
        }
        return Err(missing_source_root_module_error(import, &searched_paths));
    }

    let mut user_matches = collect_source_root_import_matches(
        import,
        roots
            .iter()
            .filter(|root| root.library == SourceRootLibrary::User),
        &mut searched_paths,
    )?;
    let mut stdlib_matches = collect_source_root_import_matches(
        import,
        roots
            .iter()
            .filter(|root| root.library == SourceRootLibrary::Stdlib),
        &mut searched_paths,
    )?;

    if user_matches.len() > 1 {
        return Err(ambiguous_source_root_module_error(import, &user_matches));
    }
    if stdlib_matches.len() > 1 {
        return Err(ambiguous_source_root_module_error(import, &stdlib_matches));
    }

    if let Some(user_match) = user_matches.first() {
        let overlapping_stdlib_matches = stdlib_matches
            .iter()
            .filter(|stdlib_match| stdlib_match.path == user_match.path)
            .cloned()
            .collect::<Vec<_>>();
        if !overlapping_stdlib_matches.is_empty() {
            let mut matches = vec![user_match.clone()];
            matches.extend(overlapping_stdlib_matches);
            return Err(ambiguous_source_root_module_error(import, &matches));
        }
        return Ok(user_matches.remove(0));
    }

    if let Some(stdlib_match) = stdlib_matches.pop() {
        return Ok(stdlib_match);
    }

    Err(missing_source_root_module_error(import, &searched_paths))
}

fn collect_source_root_import_matches<'a>(
    import: &SourceRootImport,
    roots: impl Iterator<Item = &'a SourceRootSearchRoot>,
    searched_paths: &mut Vec<PathBuf>,
) -> Result<Vec<SourceRootResolvedImport>, CompileError> {
    let mut matches = Vec::new();

    for root in roots {
        let import_path = source_root_module_path(&root.root, &import.path);
        searched_paths.push(import_path.clone());
        let canonical_import_path = match fs::canonicalize(&import_path) {
            Ok(path) => path,
            Err(_) => continue,
        };
        if !canonical_import_path.starts_with(&root.root) {
            return Err(source_root_escape_error(
                import,
                &canonical_import_path,
                root,
            ));
        }
        if !canonical_import_path.is_file() {
            continue;
        }
        if !is_lani_source_path(&canonical_import_path) {
            return Err(source_root_non_source_file_error(
                import,
                &canonical_import_path,
                root,
            ));
        }
        if !matches.iter().any(|candidate: &SourceRootResolvedImport| {
            candidate.path == canonical_import_path && candidate.library == root.library
        }) {
            matches.push(SourceRootResolvedImport {
                library: root.library,
                root_label: root.label,
                path: canonical_import_path,
            });
        }
    }

    Ok(matches)
}

fn is_lani_source_path(path: &Path) -> bool {
    path.extension().and_then(|extension| extension.to_str()) == Some("lani")
}

fn source_root_package_boundary_error(
    import: &SourceRootImport,
    matches: &[SourceRootResolvedImport],
) -> CompileError {
    let candidates = matches
        .iter()
        .map(|candidate| format!("{}: {}", candidate.root_label, candidate.path.display()))
        .collect::<Vec<_>>()
        .join("; ");
    CompileError::Diagnostic(
        Diagnostic::error(
            "LNC0024",
            format!("source-root package boundary for {}", import.path),
        )
        .with_primary_label(DiagnosticLabel::primary(
            import.source_path.clone(),
            import.line,
            import.column,
            import.label_len,
            Some(import.source_line.clone()),
            "stdlib import targets a user source root",
        ))
        .with_note("stdlib sources may not import package/user roots")
        .with_note(format!("user candidates: {candidates}")),
    )
}

fn ambiguous_source_root_module_error(
    import: &SourceRootImport,
    matches: &[SourceRootResolvedImport],
) -> CompileError {
    let candidates = matches
        .iter()
        .map(|candidate| format!("{}: {}", candidate.root_label, candidate.path.display()))
        .collect::<Vec<_>>()
        .join("; ");
    CompileError::Diagnostic(
        Diagnostic::error(
            "LNC0003",
            format!("ambiguous source-root module {}", import.path),
        )
        .with_primary_label(DiagnosticLabel::primary(
            import.source_path.clone(),
            import.line,
            import.column,
            import.label_len,
            Some(import.source_line.clone()),
            "ambiguous import",
        ))
        .with_note(format!("candidates: {candidates}")),
    )
}

fn source_root_non_source_file_error(
    import: &SourceRootImport,
    canonical_import_path: &Path,
    root: &SourceRootSearchRoot,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error(
            "LNC0030",
            format!(
                "source-root module {} resolves to non-source file",
                import.path
            ),
        )
        .with_primary_label(DiagnosticLabel::primary(
            import.source_path.clone(),
            import.line,
            import.column,
            import.label_len,
            Some(import.source_line.clone()),
            "imported here",
        ))
        .with_note(format!(
            "{} resolves to {} under {} {}",
            import.path,
            canonical_import_path.display(),
            root.label,
            root.root.display()
        ))
        .with_note("source-root imports must resolve to canonical .lani source files"),
    )
}

fn source_root_escape_error(
    import: &SourceRootImport,
    canonical_import_path: &Path,
    root: &SourceRootSearchRoot,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error(
            "LNC0004",
            format!("source-root module {} escapes {}", import.path, root.label),
        )
        .with_primary_label(DiagnosticLabel::primary(
            import.source_path.clone(),
            import.line,
            import.column,
            import.label_len,
            Some(import.source_line.clone()),
            "imported here",
        ))
        .with_note(format!(
            "{} resolves outside {} {}",
            canonical_import_path.display(),
            root.label,
            root.root.display()
        )),
    )
}

fn missing_source_root_module_error(
    import: &SourceRootImport,
    searched_paths: &[PathBuf],
) -> CompileError {
    let searched = searched_paths
        .iter()
        .map(|path| path.display().to_string())
        .collect::<Vec<_>>()
        .join("; ");
    CompileError::Diagnostic(
        Diagnostic::error(
            "LNC0001",
            format!("missing source-root module {}", import.path),
        )
        .with_primary_label(DiagnosticLabel::primary(
            import.source_path.clone(),
            import.line,
            import.column,
            import.label_len,
            Some(import.source_line.clone()),
            "imported here",
        ))
        .with_note(format!("searched {searched}")),
    )
}

fn read_source_for_import_discovery(label: &str, path: &Path) -> Result<String, CompileError> {
    fs::read_to_string(path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-root {label} source file ({}): {err}",
            path.display()
        ))
    })
}

fn source_root_module_path(source_root: &Path, import_path: &str) -> PathBuf {
    let mut path = source_root.to_path_buf();
    for segment in import_path.split("::") {
        path.push(segment);
    }
    path.set_extension("lani");
    path
}

fn leading_path_imports(
    source: &str,
    source_path: &Path,
) -> Result<Vec<SourceRootImport>, CompileError> {
    let bytes = source.as_bytes();
    let mut imports = Vec::new();
    let mut offset = 0usize;

    loop {
        offset = skip_ws_and_comments(bytes, offset);
        if keyword_at(bytes, offset, b"module") {
            offset += "module".len();
            let (_, next_offset) =
                parse_source_root_path(source, offset, source_path, SourceRootPathKind::Module)?;
            offset = expect_semicolon(source, next_offset, source_path, "module")?;
            continue;
        }
        if keyword_at(bytes, offset, b"import") {
            let import_offset = offset;
            offset += "import".len();
            offset = skip_ws_and_comments(bytes, offset);
            if bytes.get(offset) == Some(&b'"') {
                offset = skip_quoted_import_path(source, offset, source_path)?;
                offset = expect_semicolon(source, offset, source_path, "import")?;
                continue;
            }
            let (path, next_offset) =
                parse_source_root_path(source, offset, source_path, SourceRootPathKind::Import)?;
            let import_end = expect_semicolon(source, next_offset, source_path, "import")?;
            let (line, column) = line_column_at(source, import_offset);
            let (source_line, label_len) =
                source_line_and_label_len(source, import_offset, import_end);
            imports.push(SourceRootImport {
                path,
                source_path: source_path.to_path_buf(),
                line,
                column,
                source_line,
                label_len,
            });
            offset = import_end;
            continue;
        }
        return Ok(imports);
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SourceRootPathKind {
    Module,
    Import,
}

impl SourceRootPathKind {
    fn enforce_source_root_depth_limit(self) -> bool {
        matches!(self, SourceRootPathKind::Import)
    }
}

fn parse_source_root_path(
    source: &str,
    offset: usize,
    source_path: &Path,
    kind: SourceRootPathKind,
) -> Result<(String, usize), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = skip_ws_and_comments(bytes, offset);
    let path_start = offset;
    let mut segments = Vec::new();

    loop {
        let segment_start = offset;
        offset = parse_ident(bytes, offset).ok_or_else(|| {
            syntax_error_to_compile_error_for_source_span(source_path, source, segment_start, 1)
        })?;
        segments.push(&source[segment_start..offset]);
        if kind.enforce_source_root_depth_limit()
            && segments.len() > SOURCE_ROOT_IMPORT_PATH_SEGMENT_LIMIT
        {
            let (line, column) = line_column_at(source, path_start);
            let (source_line, label_len) = source_line_and_label_len(source, path_start, offset);
            return Err(source_root_import_path_too_deep_error(
                source_path,
                line,
                column,
                source_line,
                label_len,
            ));
        }
        offset = skip_ws_and_comments(bytes, offset);
        if bytes.get(offset..offset + 2) != Some(b"::") {
            break;
        }
        offset += 2;
        offset = skip_ws_and_comments(bytes, offset);
    }

    Ok((segments.join("::"), offset))
}

fn source_root_import_path_too_deep_error(
    source_path: &Path,
    line: usize,
    column: usize,
    source_line: String,
    label_len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0012", "import path too deep")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "import path exceeds the current resolver depth limit",
            ))
            .with_note(
                "source-root discovery supports at most eight module path segments in an import; module declarations are still validated by the GPU resolver",
            ),
    )
}

fn skip_quoted_import_path(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let quote_start = offset;
    let mut offset = offset + 1;
    while let Some(byte) = bytes.get(offset) {
        if *byte == b'\\' {
            offset = (offset + 2).min(bytes.len());
            continue;
        }
        if *byte == b'"' {
            return Ok(offset + 1);
        }
        offset += 1;
    }
    Err(syntax_error_to_compile_error_for_source_span(
        source_path,
        source,
        quote_start,
        source.len().saturating_sub(quote_start).max(1),
    ))
}

fn expect_semicolon(
    source: &str,
    offset: usize,
    source_path: &Path,
    _context: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let offset = skip_ws_and_comments(bytes, offset);
    if bytes.get(offset) == Some(&b';') {
        return Ok(offset + 1);
    }
    Err(syntax_error_to_compile_error_for_source_span(
        source_path,
        source,
        offset,
        1,
    ))
}

fn skip_ws_and_comments(bytes: &[u8], mut offset: usize) -> usize {
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
            offset += 2;
            while offset + 1 < bytes.len() && bytes.get(offset..offset + 2) != Some(b"*/") {
                offset += 1;
            }
            offset = (offset + 2).min(bytes.len());
            continue;
        }
        return offset;
    }
}

fn keyword_at(bytes: &[u8], offset: usize, keyword: &[u8]) -> bool {
    bytes.get(offset..offset + keyword.len()) == Some(keyword)
        && bytes
            .get(offset + keyword.len())
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

fn is_ident_start(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphabetic()
}

fn is_ident_continue(byte: u8) -> bool {
    is_ident_start(byte) || byte.is_ascii_digit()
}

fn line_column_at(source: &str, offset: usize) -> (usize, usize) {
    let mut line = 1usize;
    let mut column = 1usize;
    for byte in source.as_bytes().iter().take(offset.min(source.len())) {
        if *byte == b'\n' {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    (line, column)
}

fn source_line_and_label_len(
    source: &str,
    label_start: usize,
    label_end: usize,
) -> (String, usize) {
    let line_start = source[..label_start.min(source.len())]
        .rfind('\n')
        .map_or(0, |offset| offset + 1);
    let line_end = source[line_start..]
        .find('\n')
        .map_or(source.len(), |offset| line_start + offset);
    let source_line = source[line_start..line_end].to_string();
    let label_end = label_end.min(line_end);
    let label_len = label_end.saturating_sub(label_start).max(1);
    (source_line, label_len)
}
