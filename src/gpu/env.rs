use std::path::PathBuf;

use log::warn;

fn warn_missing_env(var: &str, default: &str) {
    warn!("{var} is unset; using default '{default}'");
}

fn warn_invalid_env(var: &str, value: &str, default: &str) {
    warn!("{var} has invalid value '{value}'; using default '{default}'");
}

pub(crate) fn env_string(name: &str, default: &str) -> String {
    match std::env::var(name) {
        Ok(value) => value,
        Err(_) => {
            warn_missing_env(name, default);
            default.to_string()
        }
    }
}

pub(crate) fn env_path(name: &str, default: PathBuf) -> PathBuf {
    let default_display = default.display().to_string();
    match std::env::var_os(name) {
        Some(value) => value.into(),
        None => {
            warn_missing_env(name, &default_display);
            default
        }
    }
}

pub(crate) fn env_u64(name: &str, default: u64) -> u64 {
    let default_display = default.to_string();
    match std::env::var(name) {
        Ok(value) => match value.parse::<u64>() {
            Ok(n) if n > 0 => n,
            Ok(n) => {
                warn!("{name} value {n} must be greater than 0; using default {default_display}");
                default
            }
            Err(err) => {
                warn!("{name} could not be parsed as u64 ({err}); using default {default_display}");
                default
            }
        },
        Err(_) => {
            warn_missing_env(name, &default_display);
            default
        }
    }
}

/// env var parser used where anything other than explicit false/0 means true.
pub(crate) fn env_bool_truthy(name: &str, default: bool) -> bool {
    let default_display = if default { "true" } else { "false" };
    match std::env::var(name) {
        Ok(value) => {
            let normalized = value.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "0" | "false" => false,
                _ => {
                    if matches!(normalized.as_str(), "1" | "true") {
                        true
                    } else {
                        warn_invalid_env(name, &value, default_display);
                        true
                    }
                }
            }
        }
        _ => {
            warn_missing_env(name, default_display);
            default
        }
    }
}

/// env var parser used for strict boolean flags where only "1"/"true" are enabled.
pub(crate) fn env_bool_strict(name: &str, default: bool) -> bool {
    let default_display = if default { "true" } else { "false" };
    match std::env::var(name) {
        Ok(value) => {
            let normalized = value.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "1" | "true" => true,
                "0" | "false" => false,
                _ => {
                    warn_invalid_env(name, &value, default_display);
                    default
                }
            }
        }
        Err(_) => {
            warn_missing_env(name, default_display);
            default
        }
    }
}

pub(crate) fn env_u64_min(name: &str, default: u64, min: u64) -> u64 {
    let default_display = default.to_string();
    match std::env::var(name) {
        Ok(value) => match value.parse::<u64>() {
            Ok(n) if n >= min => n,
            Ok(n) => {
                warn!("{name} has value {n}; must be >= {min}; using default {default_display}");
                default
            }
            Err(err) => {
                warn!("{name} could not be parsed as u64 ({err}); using default {default_display}");
                default
            }
        },
        Err(_) => {
            warn_missing_env(name, &default_display);
            default
        }
    }
}

pub(crate) fn env_usize(name: &str, default: usize) -> usize {
    let default_display = default.to_string();
    match std::env::var(name) {
        Ok(value) => match value.parse::<usize>() {
            Ok(n) if n > 0 => n,
            Ok(n) => {
                warn!("{name} value {n} must be greater than 0; using default {default_display}");
                default
            }
            Err(err) => {
                warn!(
                    "{name} could not be parsed as usize ({err}); using default {default_display}"
                );
                default
            }
        },
        Err(_) => {
            warn_missing_env(name, &default_display);
            default
        }
    }
}
