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
    let mut seen_user_roots: BTreeSet<PathBuf> = BTreeSet::new();
    for source_root in &roots.user_roots {
        let source_root =
            canonical_source_root("source root", source_root, SourceRootLibrary::User)?;
        if seen_user_roots.contains(&source_root.root) {
            return Err(CompileError::GpuFrontend(format!(
                "duplicate source root {}",
                source_root.root.display()
            )));
        }
        if let Some(overlapping_root) = seen_user_roots
            .iter()
            .find(|seen_root| source_roots_overlap(seen_root, &source_root.root))
        {
            return Err(CompileError::GpuFrontend(format!(
                "overlapping source roots {} and {}; user source roots must be disjoint so package-relative module identity is stable",
                overlapping_root.display(),
                source_root.root.display()
            )));
        }
        seen_user_roots.insert(source_root.root.clone());
        search_roots.push(source_root);
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

fn source_roots_overlap(left: &Path, right: &Path) -> bool {
    left.starts_with(right) || right.starts_with(left)
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
            let user_alias_matches = collect_source_root_import_alias_matches(
                import,
                roots
                    .iter()
                    .filter(|root| root.library == SourceRootLibrary::User),
                &stdlib_match.path,
                &mut searched_paths,
            )?;
            if !user_alias_matches.is_empty() {
                let mut matches = vec![stdlib_match.clone()];
                matches.extend(user_alias_matches);
                return Err(ambiguous_source_root_module_error(import, &matches));
            }
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

fn collect_source_root_import_alias_matches<'a>(
    import: &SourceRootImport,
    roots: impl Iterator<Item = &'a SourceRootSearchRoot>,
    canonical_target: &Path,
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
        if canonical_import_path.as_path() != canonical_target {
            continue;
        }
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
        offset = skip_ws_and_comments(source, bytes, offset, source_path)?;
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
            offset = skip_ws_and_comments(source, bytes, offset, source_path)?;
            if bytes.get(offset) == Some(&b'"') {
                let quoted_end = skip_quoted_import_path(source, offset, source_path)?;
                return Err(unsupported_source_root_quoted_import_error(
                    source,
                    source_path,
                    import_offset,
                    quoted_end.saturating_sub(import_offset),
                ));
            }
            let (path, next_offset) =
                parse_source_root_path(source, offset, source_path, SourceRootPathKind::Import)?;
            let next_offset = skip_ws_and_comments(source, bytes, next_offset, source_path)?;
            if keyword_at(bytes, next_offset, b"as") {
                return Err(unsupported_source_root_import_alias_error(
                    source,
                    source_path,
                    next_offset,
                    source_root_import_alias_label_len(bytes, next_offset),
                ));
            }
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
        reject_non_leading_source_root_imports(source, offset, source_path)?;
        return Ok(imports);
    }
}

fn reject_non_leading_source_root_imports(
    source: &str,
    offset: usize,
    source_path: &Path,
) -> Result<(), CompileError> {
    let bytes = source.as_bytes();
    let mut offset = offset;

    while offset < bytes.len() {
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
                return Err(unterminated_source_root_block_comment_error(
                    source,
                    source_path,
                    comment_start,
                ));
            }
            offset += 2;
            continue;
        }
        if bytes.get(offset) == Some(&b'"') {
            offset = skip_quoted_literal(source, offset, source_path, b'"', "string literal")?;
            continue;
        }
        if bytes.get(offset) == Some(&b'\'') {
            offset = skip_quoted_literal(source, offset, source_path, b'\'', "character literal")?;
            continue;
        }
        if keyword_at_anywhere(bytes, offset, b"import") {
            return Err(non_leading_source_root_import_error(
                source,
                source_path,
                offset,
            ));
        }
        offset += 1;
    }

    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SourceRootPathKind {
    Module,
    Import,
}

impl SourceRootPathKind {
    fn label(self) -> &'static str {
        match self {
            SourceRootPathKind::Module => "module",
            SourceRootPathKind::Import => "import",
        }
    }

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
    let mut offset = skip_ws_and_comments(source, bytes, offset, source_path)?;
    let path_start = offset;
    let mut segments = Vec::new();

    loop {
        let segment_start = offset;
        if kind == SourceRootPathKind::Import && bytes.get(segment_start) == Some(&b'*') {
            return Err(unsupported_source_root_import_glob_error(
                source,
                source_path,
                segment_start,
            ));
        }
        offset = parse_ident(bytes, offset).ok_or_else(|| {
            syntax_error_to_compile_error_for_source_span(source_path, source, segment_start, 1)
        })?;
        let segment = &source[segment_start..offset];
        if kind == SourceRootPathKind::Import
            && is_source_root_reserved_module_path_segment(segment)
        {
            return Err(invalid_source_root_import_path_segment_error(
                source,
                source_path,
                segment_start,
                segment,
            ));
        }
        segments.push(segment);
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
        offset = skip_ws_and_comments(source, bytes, offset, source_path)?;
        if invalid_source_root_path_separator(bytes, offset) {
            return Err(invalid_source_root_path_separator_error(
                source,
                source_path,
                offset,
                kind,
            ));
        }
        if bytes.get(offset..offset + 2) != Some(b"::") {
            break;
        }
        offset += 2;
        offset = skip_ws_and_comments(source, bytes, offset, source_path)?;
    }

    Ok((segments.join("::"), offset))
}

fn invalid_source_root_path_separator(bytes: &[u8], offset: usize) -> bool {
    match bytes.get(offset) {
        Some(b'/' | b'\\' | b'.') => true,
        Some(b':') => bytes.get(offset..offset + 2) != Some(b"::"),
        _ => false,
    }
}

fn invalid_source_root_path_separator_error(
    source: &str,
    source_path: &Path,
    start: usize,
    kind: SourceRootPathKind,
) -> CompileError {
    let (line, column) = line_column_at(source, start);
    let (source_line, label_len) = source_line_and_label_len(source, start, start + 1);
    let label_message = format!("{} paths must use `::` separators", kind.label());
    match kind {
        SourceRootPathKind::Module => CompileError::Diagnostic(
            Diagnostic::error("LNC0016", "syntax error")
                .with_primary_label(DiagnosticLabel::primary(
                    source_path.to_path_buf(),
                    line,
                    column,
                    label_len,
                    Some(source_line),
                    label_message,
                ))
                .with_note(
                    "source-root discovery does not normalize filesystem path separators or package-name separators into module declarations",
                )
                .with_note(
                    "module identity must come from GPU parser module-path tokens such as `module app::main;`",
                ),
        ),
        SourceRootPathKind::Import => CompileError::Diagnostic(
            Diagnostic::error("LNC0011", "unsupported import form")
                .with_primary_label(DiagnosticLabel::primary(
                    source_path.to_path_buf(),
                    line,
                    column,
                    label_len,
                    Some(source_line),
                    label_message,
                ))
                .with_note(
                    "source-root discovery records module-path imports such as `import app::module;`",
                )
                .with_note(
                    "filesystem path separators and package-name separators cannot be normalized into semantic module identity during package replay",
                ),
        ),
    }
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
    skip_quoted_literal(source, offset, source_path, b'"', "string literal")
}

fn skip_quoted_literal(
    source: &str,
    offset: usize,
    source_path: &Path,
    quote: u8,
    label: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let quote_start = offset;
    let mut offset = offset + 1;
    while let Some(byte) = bytes.get(offset) {
        if *byte == b'\\' {
            offset = (offset + 2).min(bytes.len());
            continue;
        }
        if *byte == b'\n' {
            return Err(malformed_source_root_literal_error(
                source,
                source_path,
                quote_start,
                label,
            ));
        }
        if *byte == quote {
            return Ok(offset + 1);
        }
        offset += 1;
    }
    Err(malformed_source_root_literal_error(
        source,
        source_path,
        quote_start,
        label,
    ))
}

fn non_leading_source_root_import_error(
    source: &str,
    source_path: &Path,
    import_offset: usize,
) -> CompileError {
    let (line, column) = line_column_at(source, import_offset);
    let (source_line, label_len) =
        source_line_and_label_len(source, import_offset, import_offset + "import".len());
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "imports must appear before other items",
            ))
            .with_note(
                "source-root/package discovery only loads leading module-path imports so package replay metadata stays complete",
            )
            .with_note("move imports directly after the module declaration"),
    )
}

fn unsupported_source_root_import_alias_error(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
) -> CompileError {
    let (line, column) = line_column_at(source, start);
    let (source_line, label_len) = source_line_and_label_len(source, start, start + len);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "import aliases are not supported by source-root discovery",
            ))
            .with_note(
                "source-root discovery only loads explicit module-path imports until alias metadata is represented by GPU module/import records",
            ),
    )
}

fn unsupported_source_root_import_glob_error(
    source: &str,
    source_path: &Path,
    start: usize,
) -> CompileError {
    let (line, column) = line_column_at(source, start);
    let (source_line, label_len) = source_line_and_label_len(source, start, start + 1);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "import globs are not supported by source-root discovery",
            ))
            .with_note(
                "source-root discovery must publish explicit module-path source candidates instead of expanding glob imports on the host",
            ),
    )
}

fn unsupported_source_root_quoted_import_error(
    source: &str,
    source_path: &Path,
    start: usize,
    len: usize,
) -> CompileError {
    let (line, column) = line_column_at(source, start);
    let (source_line, label_len) = source_line_and_label_len(source, start, start + len);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "quoted imports are not supported by source-root discovery",
            ))
            .with_note(
                "source-root discovery must publish explicit module-path source candidates instead of treating quoted paths as optional metadata",
            ),
    )
}

fn invalid_source_root_import_path_segment_error(
    source: &str,
    source_path: &Path,
    start: usize,
    segment: &str,
) -> CompileError {
    let (line, column) = line_column_at(source, start);
    let (source_line, label_len) = source_line_and_label_len(source, start, start + segment.len());
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "invalid import path segment",
            ))
            .with_note(
                "reserved keywords cannot be used as source-root import path segments",
            )
            .with_note(
                "source-root discovery must follow GPU module/import identifier records instead of normalizing invalid module paths into host file lookups",
            ),
    )
}

fn source_root_import_alias_label_len(bytes: &[u8], start: usize) -> usize {
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

fn expect_semicolon(
    source: &str,
    offset: usize,
    source_path: &Path,
    _context: &str,
) -> Result<usize, CompileError> {
    let bytes = source.as_bytes();
    let offset = skip_ws_and_comments(source, bytes, offset, source_path)?;
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

fn skip_ws_and_comments(
    source: &str,
    bytes: &[u8],
    mut offset: usize,
    source_path: &Path,
) -> Result<usize, CompileError> {
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
                return Err(unterminated_source_root_block_comment_error(
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

fn unterminated_source_root_block_comment_error(
    source: &str,
    source_path: &Path,
    comment_offset: usize,
) -> CompileError {
    let (line, column) = line_column_at(source, comment_offset);
    let (source_line, label_len) =
        source_line_and_label_len(source, comment_offset, comment_offset + 2);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                "unterminated block comment",
            ))
            .with_note(
                "source-root replay must not skip malformed comments while discovering module/import metadata",
            ),
    )
}

fn malformed_source_root_literal_error(
    source: &str,
    source_path: &Path,
    literal_offset: usize,
    label: &str,
) -> CompileError {
    let (line, column) = line_column_at(source, literal_offset);
    let (source_line, label_len) =
        source_line_and_label_len(source, literal_offset, literal_offset + 1);
    CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(DiagnosticLabel::primary(
                source_path.to_path_buf(),
                line,
                column,
                label_len,
                Some(source_line),
                format!("malformed {label}"),
            ))
            .with_note(
                "source-root replay must not skip malformed literals while discovering module/import metadata",
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

fn is_ident_start(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphabetic()
}

fn is_ident_continue(byte: u8) -> bool {
    is_ident_start(byte) || byte.is_ascii_digit()
}

fn is_source_root_reserved_module_path_segment(segment: &str) -> bool {
    matches!(
        segment,
        "break"
            | "const"
            | "continue"
            | "else"
            | "enum"
            | "extern"
            | "false"
            | "fn"
            | "for"
            | "if"
            | "impl"
            | "import"
            | "in"
            | "let"
            | "match"
            | "module"
            | "pub"
            | "return"
            | "self"
            | "struct"
            | "trait"
            | "true"
            | "type"
            | "where"
            | "while"
    )
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
