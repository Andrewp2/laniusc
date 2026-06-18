/// Parses a non-negative integer used by CLI limit flags.
pub(crate) fn parse_usize_value(flag: &str, value: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|err| format!("{flag} requires a non-negative integer, got {value:?}: {err}"))
}
