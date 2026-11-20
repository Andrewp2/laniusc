//! Module, import, declaration, and path-resolution state for type checking.
//!
//! This submodule owns the relations that turn parser HIR item/path metadata
//! into module ids, import edges, declaration lookup tables, resolved type
//! paths, resolved value paths, and match/enum payload bindings.

mod bind_helpers;
mod buffers;
mod create;
mod dependency_visibility;
mod inputs;
mod layout;
mod module_index;
mod programs;
mod projection;
mod state;

pub(super) use create::create_with_passes as create_module_path_state_with_passes;
pub(super) use dependency_visibility::DependencyVisibilityState;
pub(super) use inputs::CreateInputs as ModulePathCreateInputs;
pub(super) use programs::MODULE_PROGRAM_SLOTS;
pub(super) use state::State as ModulePathState;
