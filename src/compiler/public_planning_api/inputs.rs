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
    ExplicitSourcePack::from_libraries(libraries)
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

pub fn load_explicit_source_libraries_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<ExplicitSourcePack, CompileError>
where
    P: AsRef<Path>,
{
    let mut source_libraries = Vec::with_capacity(libraries.len());
    for library in libraries {
        let label = format!("library {}", library.library_id);
        let sources = read_explicit_source_paths(&label, &library.paths)?;
        source_libraries.push(ExplicitSourceLibrary {
            library_id: library.library_id,
            sources,
            dependency_library_ids: library.dependency_library_ids,
        });
    }
    ExplicitSourcePack::from_libraries(source_libraries)
}
