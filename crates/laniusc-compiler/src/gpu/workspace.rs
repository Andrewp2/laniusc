//! Physical storage plan produced from compiler-graph resource lifetimes.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkspaceUsageClass {
    Storage,
    StorageIndirect,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceAssignment {
    pub name: &'static str,
    pub slot: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkspaceSlotPlan {
    pub slot: u32,
    pub bytes: u64,
    pub usage: WorkspaceUsageClass,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkspacePlan {
    pub assignments: Vec<WorkspaceAssignment>,
    pub slots: Vec<WorkspaceSlotPlan>,
}
