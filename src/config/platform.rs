use serde::{Deserialize, Serialize};

use crate::schema;

/// Game platform whose traffic the proxy intercepts. Determines which
/// [`crate::bridge::Bridge`] is instantiated per WebSocket flow.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
pub enum Platform {
    #[default]
    Majsoul,
}

impl Platform {
    /// Short name used as a subdirectory under the log session
    /// (e.g. `<session>/<subdir>/<flow>.log`).
    pub fn subdir(self) -> &'static str {
        match self {
            Platform::Majsoul => "majsoul",
        }
    }
}

/// Map the bridge selector to its history-record tag. The two enums stay
/// separate because the schema enum carries extra variants (`Mjai`,
/// `Unknown`, and platforms this build no longer bridges) so records
/// written by other builds still deserialize.
impl From<Platform> for schema::Platform {
    fn from(p: Platform) -> Self {
        match p {
            Platform::Majsoul => schema::Platform::Majsoul,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PlatformConfig {
    pub kind: Platform,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_to_schema_platform_round_trip() {
        assert_eq!(
            schema::Platform::from(Platform::Majsoul),
            schema::Platform::Majsoul
        );
    }
}
