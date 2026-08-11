use std::path::PathBuf;

use super::{
    CompilationUnit,
    CompilationUnitLimits,
    CompilationUnitPlan,
    ExplicitSourcePackPathManifest,
    GpuCompiler,
};

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceIdentity {
    library_id: u32,
    path: PathBuf,
}

pub(super) struct StableUnitPlan {
    sources: Vec<SourceIdentity>,
    units: CompilationUnitPlan,
}

impl StableUnitPlan {
    fn source_identities(source_pack: &ExplicitSourcePackPathManifest) -> Vec<SourceIdentity> {
        source_pack
            .files
            .iter()
            .map(|file| SourceIdentity {
                library_id: file.library_id,
                path: file.path.clone(),
            })
            .collect()
    }

    fn refresh(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        limits: CompilationUnitLimits,
    ) -> Option<CompilationUnitPlan> {
        if self.sources != Self::source_identities(source_pack) {
            return None;
        }
        let limits = limits.normalized();
        let mut next_source_index = 0usize;
        let mut units = Vec::with_capacity(self.units.units.len());
        for (unit_index, previous) in self.units.units.iter().enumerate() {
            if previous.first_source_index != next_source_index || previous.source_file_count == 0 {
                return None;
            }
            let end = next_source_index.checked_add(previous.source_file_count)?;
            let files = source_pack.files.get(next_source_index..end)?;
            if files
                .iter()
                .any(|file| file.library_id != previous.library_id)
            {
                return None;
            }
            let source_bytes = files
                .iter()
                .try_fold(0usize, |total, file| total.checked_add(file.byte_len))?;
            let source_lines = files.iter().try_fold(0usize, |total, file| {
                total.checked_add(file.line_count.unwrap_or(0))
            })?;
            let oversized_source_file = files.len() == 1 && source_bytes > limits.max_source_bytes;
            if (!oversized_source_file && source_bytes > limits.max_source_bytes)
                || files.len() > limits.max_source_files
            {
                return None;
            }
            units.push(CompilationUnit {
                unit_index,
                library_id: previous.library_id,
                first_source_index: next_source_index,
                source_file_count: files.len(),
                source_bytes,
                source_lines,
                oversized_source_file,
            });
            next_source_index = end;
        }
        (next_source_index == source_pack.files.len()).then_some(CompilationUnitPlan { units })
    }
}

impl GpuCompiler<'_> {
    pub(super) fn stable_frontend_unit_plan(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        limits: CompilationUnitLimits,
    ) -> CompilationUnitPlan {
        let mut cache = self
            .stable_unit_plan
            .lock()
            .expect("stable unit-plan cache mutex poisoned");
        let units = cache
            .as_ref()
            .and_then(|cached| cached.refresh(source_pack, limits))
            .unwrap_or_else(|| source_pack.frontend_unit_plan(limits));
        *cache = Some(StableUnitPlan {
            sources: StableUnitPlan::source_identities(source_pack),
            units: units.clone(),
        });
        units
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiler::ExplicitSourcePathFile;

    fn file(index: usize, bytes: usize) -> ExplicitSourcePathFile {
        ExplicitSourcePathFile {
            library_id: 1,
            path: PathBuf::from(format!("source-{index}.lani")),
            byte_len: bytes,
            modified_unix_nanos: None,
            line_count: Some(1),
        }
    }

    #[test]
    fn stable_plan_preserves_boundaries_after_an_in_capacity_edit() {
        let limits = CompilationUnitLimits {
            max_source_bytes: 100,
            max_source_files: 10,
        };
        let original = ExplicitSourcePackPathManifest {
            files: vec![file(0, 60), file(1, 40), file(2, 60), file(3, 40)],
            library_dependencies: Vec::new(),
        };
        let units = original.frontend_unit_plan(limits);
        assert_eq!(
            units
                .units
                .iter()
                .map(|unit| unit.source_file_count)
                .collect::<Vec<_>>(),
            [2, 2]
        );
        let stable = StableUnitPlan {
            sources: StableUnitPlan::source_identities(&original),
            units,
        };
        let edited = ExplicitSourcePackPathManifest {
            files: vec![file(0, 55), file(1, 40), file(2, 65), file(3, 35)],
            library_dependencies: Vec::new(),
        };
        let refreshed = stable
            .refresh(&edited, limits)
            .expect("boundaries still fit");
        assert_eq!(
            refreshed
                .units
                .iter()
                .map(|unit| unit.source_file_count)
                .collect::<Vec<_>>(),
            [2, 2]
        );
        assert_eq!(
            refreshed
                .units
                .iter()
                .map(|unit| unit.source_bytes)
                .collect::<Vec<_>>(),
            [95, 100]
        );
    }

    #[test]
    fn stable_plan_rejects_a_boundary_that_exceeds_capacity() {
        let limits = CompilationUnitLimits {
            max_source_bytes: 100,
            max_source_files: 10,
        };
        let original = ExplicitSourcePackPathManifest {
            files: vec![file(0, 60), file(1, 40), file(2, 60)],
            library_dependencies: Vec::new(),
        };
        let stable = StableUnitPlan {
            sources: StableUnitPlan::source_identities(&original),
            units: original.frontend_unit_plan(limits),
        };
        let edited = ExplicitSourcePackPathManifest {
            files: vec![file(0, 61), file(1, 40), file(2, 59)],
            library_dependencies: Vec::new(),
        };
        assert!(stable.refresh(&edited, limits).is_none());
    }
}
