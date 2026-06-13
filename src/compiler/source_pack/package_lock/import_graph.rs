use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use super::{
    PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID,
    PACKAGE_LOCKFILE_USER_LIBRARY_ID,
    package_lockfile_error,
    source_scan::{valid_import_path, valid_module_path},
    validate_resolved_source_path,
};
use crate::compiler::{CompileError, SourcePackLibraryDependency};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct PackageLockfileImportGraph {
    pub(super) library_dependencies: Vec<SourcePackLibraryDependency>,
    pub(super) imports: Vec<PackageLockfileImportEdge>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct PackageLockfileImportEdge {
    pub(super) source_library_id: u32,
    pub(super) source_path: PathBuf,
    pub(super) source_module_path: String,
    pub(super) import_path: String,
    pub(super) target_library_id: u32,
    pub(super) target_path: PathBuf,
    pub(super) target_module_path: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct PackageLockfileImportSearchRoot {
    pub(super) library_id: u32,
    pub(super) label: &'static str,
    pub(super) root: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct PackageLockfileResolvedImport {
    pub(super) library_id: u32,
    pub(super) label: &'static str,
    pub(super) path: PathBuf,
}

impl PackageLockfileImportGraph {
    pub(super) fn validate_shape(&self) -> Result<(), CompileError> {
        let mut seen_dependencies = BTreeSet::new();
        let mut previous_dependency: Option<&SourcePackLibraryDependency> = None;
        for dependency in &self.library_dependencies {
            validate_import_graph_library_id(
                "import graph library dependency source",
                dependency.library_id,
            )?;
            validate_import_graph_library_id(
                "import graph library dependency target",
                dependency.depends_on_library_id,
            )?;
            if dependency.library_id == dependency.depends_on_library_id {
                return Err(package_lockfile_error(format!(
                    "library {} depends on itself",
                    dependency.library_id
                )));
            }
            if dependency.library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID
                && dependency.depends_on_library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID
            {
                return Err(package_lockfile_error(format!(
                    "package boundary: stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID} may not depend on package/user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID}"
                )));
            }
            if !seen_dependencies.insert((dependency.library_id, dependency.depends_on_library_id))
            {
                return Err(package_lockfile_error(format!(
                    "duplicate import graph library dependency {} -> {}; package lockfile replay metadata allows one coarse dependency edge per library pair",
                    dependency.library_id, dependency.depends_on_library_id
                )));
            }
            if let Some(previous_dependency) = previous_dependency {
                if (
                    previous_dependency.library_id,
                    previous_dependency.depends_on_library_id,
                ) > (dependency.library_id, dependency.depends_on_library_id)
                {
                    return Err(package_lockfile_error(format!(
                        "import graph library dependencies must be sorted by library id and dependency library id; dependency {} -> {} appears after {} -> {}; regenerate the package lockfile from the package manifest",
                        dependency.library_id,
                        dependency.depends_on_library_id,
                        previous_dependency.library_id,
                        previous_dependency.depends_on_library_id
                    )));
                }
            }
            previous_dependency = Some(dependency);
        }

        let allowed_cross_library_imports = self
            .library_dependencies
            .iter()
            .map(|dependency| (dependency.library_id, dependency.depends_on_library_id))
            .collect::<BTreeSet<_>>();
        let mut seen_imports = BTreeSet::new();
        let mut endpoint_module_paths = BTreeMap::new();
        let mut endpoint_path_identities = BTreeMap::new();
        let mut seen_source_import_targets = BTreeMap::new();
        let mut cross_library_imports = BTreeSet::new();
        let mut previous_import: Option<&PackageLockfileImportEdge> = None;
        for (edge_index, import) in self.imports.iter().enumerate() {
            validate_import_graph_library_id(
                &format!("import graph edge {edge_index} source"),
                import.source_library_id,
            )?;
            validate_import_graph_library_id(
                &format!("import graph edge {edge_index} target"),
                import.target_library_id,
            )?;
            validate_resolved_source_path("import graph source file", &import.source_path)?;
            validate_resolved_source_path("import graph target file", &import.target_path)?;
            if !valid_import_path(&import.import_path) {
                return Err(package_lockfile_error(format!(
                    "invalid import graph path {:?}",
                    import.import_path
                )));
            }
            if !valid_module_path(&import.source_module_path) {
                return Err(package_lockfile_error(format!(
                    "invalid import graph source module path {:?}",
                    import.source_module_path
                )));
            }
            if import.source_module_path == import.import_path {
                return Err(package_lockfile_error(format!(
                    "import graph semantic self-cycle: source module {} in library {} {} imports its own module path; package imports must resolve to a different module identity",
                    import.source_module_path,
                    import.source_library_id,
                    import.source_path.display()
                )));
            }
            if !valid_module_path(&import.target_module_path) {
                return Err(package_lockfile_error(format!(
                    "invalid import graph target module path {:?}",
                    import.target_module_path
                )));
            }
            if import.target_module_path != import.import_path {
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} import path {} resolves to target module {}; package imports must resolve by declared module identity",
                    import.import_path, import.target_module_path
                )));
            }
            validate_import_graph_endpoint_module_identity(
                edge_index,
                "source",
                import.source_library_id,
                &import.source_module_path,
                &import.source_path,
                &mut endpoint_module_paths,
            )?;
            validate_import_graph_endpoint_module_identity(
                edge_index,
                "target",
                import.target_library_id,
                &import.target_module_path,
                &import.target_path,
                &mut endpoint_module_paths,
            )?;
            if import.source_library_id != import.target_library_id
                && !allowed_cross_library_imports
                    .contains(&(import.source_library_id, import.target_library_id))
            {
                if import.source_library_id == PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID
                    && import.target_library_id == PACKAGE_LOCKFILE_USER_LIBRARY_ID
                {
                    return Err(package_lockfile_error(format!(
                        "package boundary: stdlib source {} imports user source-root module {}; stdlib sources may not import package/user roots (target {})",
                        import.source_path.display(),
                        import.import_path,
                        import.target_path.display()
                    )));
                }
                return Err(package_lockfile_error(format!(
                    "import graph edge {edge_index} from library {} to library {} is not permitted by the library dependency graph",
                    import.source_library_id, import.target_library_id
                )));
            }
            if import.source_library_id == import.target_library_id
                && import.source_path == import.target_path
            {
                return Err(package_lockfile_error(format!(
                    "import graph self-cycle: source {} in library {} imports its own module {}; package imports must resolve to a different source file",
                    import.source_path.display(),
                    import.source_library_id,
                    import.import_path
                )));
            }
            validate_import_graph_endpoint_path_identity(
                edge_index,
                "source",
                import.source_library_id,
                &import.source_module_path,
                &import.source_path,
                &mut endpoint_path_identities,
            )?;
            validate_import_graph_endpoint_path_identity(
                edge_index,
                "target",
                import.target_library_id,
                &import.target_module_path,
                &import.target_path,
                &mut endpoint_path_identities,
            )?;
            if import.source_library_id != import.target_library_id {
                cross_library_imports.insert((import.source_library_id, import.target_library_id));
            }
            let source_import_key = (
                import.source_library_id,
                import.source_path.clone(),
                import.import_path.clone(),
            );
            let target_key = (import.target_library_id, import.target_path.clone());
            if let Some(previous_target) = seen_source_import_targets.get(&source_import_key) {
                if previous_target != &target_key {
                    let (previous_library_id, previous_path) = previous_target;
                    return Err(package_lockfile_error(format!(
                        "ambiguous import graph edge {} from library {} {}; previous target library {} {}, new target library {} {}; package imports must resolve to one target per source import path",
                        import.import_path,
                        import.source_library_id,
                        import.source_path.display(),
                        previous_library_id,
                        previous_path.display(),
                        import.target_library_id,
                        import.target_path.display()
                    )));
                }
            } else {
                seen_source_import_targets.insert(source_import_key, target_key);
            }
            if !seen_imports.insert(import.identity_key()) {
                return Err(package_lockfile_error(format!(
                    "duplicate import graph edge {} from library {} {} to library {} {}",
                    import.import_path,
                    import.source_library_id,
                    import.source_path.display(),
                    import.target_library_id,
                    import.target_path.display()
                )));
            }
            if let Some(previous_import) = previous_import {
                if compare_import_edge_identity(previous_import, import).is_gt() {
                    return Err(package_lockfile_error(format!(
                        "import graph edges must be sorted by source library, source path, import path, target library, and target path; edge {} from library {} {} to library {} {} appears after edge {} from library {} {} to library {} {}; regenerate the package lockfile from the package manifest",
                        import.import_path,
                        import.source_library_id,
                        import.source_path.display(),
                        import.target_library_id,
                        import.target_path.display(),
                        previous_import.import_path,
                        previous_import.source_library_id,
                        previous_import.source_path.display(),
                        previous_import.target_library_id,
                        previous_import.target_path.display()
                    )));
                }
            }
            previous_import = Some(import);
        }
        for dependency in &self.library_dependencies {
            if !cross_library_imports
                .contains(&(dependency.library_id, dependency.depends_on_library_id))
            {
                return Err(package_lockfile_error(format!(
                    "import graph library dependency {} -> {} has no matching cross-library import edge",
                    dependency.library_id, dependency.depends_on_library_id
                )));
            }
        }
        Ok(())
    }
}

fn validate_import_graph_endpoint_module_identity(
    edge_index: usize,
    endpoint: &str,
    library_id: u32,
    module_path: &str,
    path: &Path,
    endpoint_module_paths: &mut BTreeMap<(u32, String), PathBuf>,
) -> Result<(), CompileError> {
    let module_key = (library_id, module_path.to_string());
    if let Some(previous_path) = endpoint_module_paths.get(&module_key) {
        if previous_path != path {
            return Err(package_lockfile_error(format!(
                "import graph edge {edge_index} {endpoint} module path {module_path} in library {library_id} is already associated with {}; package lockfile import graphs require one source file per module identity, not {}",
                previous_path.display(),
                path.display()
            )));
        }
        return Ok(());
    }
    endpoint_module_paths.insert(module_key, path.to_path_buf());
    Ok(())
}

fn validate_import_graph_endpoint_path_identity(
    edge_index: usize,
    endpoint: &str,
    library_id: u32,
    module_path: &str,
    path: &Path,
    endpoint_path_identities: &mut BTreeMap<PathBuf, (u32, String)>,
) -> Result<(), CompileError> {
    if let Some((previous_library_id, previous_module_path)) = endpoint_path_identities.get(path) {
        if *previous_library_id == library_id && previous_module_path.as_str() == module_path {
            return Ok(());
        }
        return Err(package_lockfile_error(format!(
            "import graph edge {edge_index} {endpoint} path {} is already associated with library {} module {}; package lockfile import graphs require one library/module identity per canonical source path, not library {} module {}",
            path.display(),
            previous_library_id,
            previous_module_path,
            library_id,
            module_path
        )));
    }
    endpoint_path_identities.insert(path.to_path_buf(), (library_id, module_path.to_string()));
    Ok(())
}

fn validate_import_graph_library_id(label: &str, library_id: u32) -> Result<(), CompileError> {
    match library_id {
        PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID | PACKAGE_LOCKFILE_USER_LIBRARY_ID => Ok(()),
        other => Err(package_lockfile_error(format!(
            "{label} library {other} is unsupported; package lockfile import graphs currently support stdlib library {PACKAGE_LOCKFILE_STDLIB_LIBRARY_ID} and package/user library {PACKAGE_LOCKFILE_USER_LIBRARY_ID}"
        ))),
    }
}

impl PackageLockfileImportEdge {
    pub(super) fn identity_key(&self) -> (u32, PathBuf, String, u32, PathBuf) {
        (
            self.source_library_id,
            self.source_path.clone(),
            self.import_path.clone(),
            self.target_library_id,
            self.target_path.clone(),
        )
    }
}

pub(super) fn compare_import_edge_identity(
    left: &PackageLockfileImportEdge,
    right: &PackageLockfileImportEdge,
) -> std::cmp::Ordering {
    left.source_library_id
        .cmp(&right.source_library_id)
        .then_with(|| left.source_path.cmp(&right.source_path))
        .then_with(|| left.import_path.cmp(&right.import_path))
        .then_with(|| left.target_library_id.cmp(&right.target_library_id))
        .then_with(|| left.target_path.cmp(&right.target_path))
}

pub(super) fn import_graph_edge_summary(imports: &[PackageLockfileImportEdge]) -> String {
    if imports.is_empty() {
        return "none".to_string();
    }
    let mut edges = imports
        .iter()
        .take(8)
        .map(|edge| {
            format!(
                "{} from library {} {} to library {} {}",
                edge.import_path,
                edge.source_library_id,
                edge.source_path.display(),
                edge.target_library_id,
                edge.target_path.display()
            )
        })
        .collect::<Vec<_>>();
    if imports.len() > edges.len() {
        edges.push(format!("{} more", imports.len() - edges.len()));
    }
    edges.join("; ")
}

pub(super) fn import_graph_reachable_files_from_entry(
    entry_key: &(u32, PathBuf),
    import_graph: &PackageLockfileImportGraph,
) -> BTreeSet<(u32, PathBuf)> {
    let mut edges_by_source = BTreeMap::<(u32, PathBuf), Vec<(u32, PathBuf)>>::new();
    for import in &import_graph.imports {
        edges_by_source
            .entry((import.source_library_id, import.source_path.clone()))
            .or_default()
            .push((import.target_library_id, import.target_path.clone()));
    }

    let mut reachable = BTreeSet::new();
    let mut pending = vec![entry_key.clone()];
    while let Some(file_key) = pending.pop() {
        if !reachable.insert(file_key.clone()) {
            continue;
        }
        if let Some(targets) = edges_by_source.get(&file_key) {
            pending.extend(
                targets
                    .iter()
                    .filter(|target| !reachable.contains(*target))
                    .cloned(),
            );
        }
    }
    reachable
}

pub(super) fn validate_import_graph_module_endpoint(
    edge_index: usize,
    endpoint: &str,
    library_id: u32,
    path: &Path,
    edge_module_path: &str,
    source_identity_module_path: &str,
    package_module_path: Option<&str>,
    package: &str,
) -> Result<(), CompileError> {
    if edge_module_path == source_identity_module_path {
        return Ok(());
    }
    if package_module_path == Some(edge_module_path) {
        return Err(package_lockfile_error(format!(
            "import graph edge {edge_index} {endpoint} module path {:?} matches package metadata {:?}, but source identity module is {:?} for library {} {}; package names are control-plane identity and must not replace GPU module declarations",
            edge_module_path,
            package,
            source_identity_module_path,
            library_id,
            path.display()
        )));
    }
    Err(package_lockfile_error(format!(
        "import graph edge {edge_index} {endpoint} module path {:?} does not match source identity module {:?} for library {} {}",
        edge_module_path,
        source_identity_module_path,
        library_id,
        path.display()
    )))
}
