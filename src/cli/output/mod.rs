mod contract;
mod diagnostics;
mod emission;
mod error;
mod stream;

pub(crate) use emission::{CliEmission, write_cli_emission};
pub(crate) use error::CliOutputError;
pub(crate) use stream::write_output_stream_bytes;

#[cfg(test)]
mod tests;
