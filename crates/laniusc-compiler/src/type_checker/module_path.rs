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
mod projection;
mod record_discovery;
mod state;

pub(super) use create::create_with_passes as create_module_path_state_with_passes;
pub(super) use inputs::CreateInputs as ModulePathCreateInputs;
pub(super) use state::State as ModulePathState;
