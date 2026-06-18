use std::io::Write;

use super::{CliOutputError, diagnostics::output_stream_write_diagnostic};

/// Writes bytes to stdout and reports stream failures as CLI output diagnostics.
pub(crate) fn write_stdout_bytes(
    emit: &str,
    operation: impl Into<String>,
    bytes: &[u8],
) -> Result<(), CliOutputError> {
    let operation = operation.into();
    let mut stdout = std::io::stdout();
    write_output_stream_bytes("stdout", emit, &operation, &mut stdout, bytes)
}

/// Writes bytes to a stream and flushes it with contextual diagnostics.
pub(crate) fn write_output_stream_bytes<W: Write>(
    stream: &str,
    emit: &str,
    operation: &str,
    writer: &mut W,
    bytes: &[u8],
) -> Result<(), CliOutputError> {
    writer
        .write_all(bytes)
        .map_err(|err| output_stream_write_diagnostic(stream, emit, operation, err))?;
    writer.flush().map_err(|err| {
        output_stream_write_diagnostic(stream, emit, format!("flush after {operation}"), err)
    })?;
    Ok(())
}
