use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "akagi", about = "Akagi - Mahjong AI Assistant")]
pub struct Cli {
    #[arg(short, long, help = "Path to config.toml")]
    pub config: Option<PathBuf>,
    /// Overrides `capture.chromium.profile` for this run only. The browser
    /// profile decides which `device_id` the client reports, so switching it
    /// is switching identity — worth having as a launch argument rather than
    /// an edit that is easy to forget to undo.
    #[arg(
        short,
        long,
        value_name = "NAME",
        help = "Browser profile for this run"
    )]
    pub profile: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(args: &[&str]) -> Cli {
        Cli::parse_from(std::iter::once("akagi").chain(args.iter().copied()))
    }

    #[test]
    fn profile_is_absent_by_default() {
        assert_eq!(parse(&[]).profile, None);
    }

    #[test]
    fn profile_accepts_long_and_short_forms() {
        assert_eq!(parse(&["--profile", "jp"]).profile.as_deref(), Some("jp"));
        assert_eq!(parse(&["-p", "jp"]).profile.as_deref(), Some("jp"));
        assert_eq!(parse(&["--profile=jp"]).profile.as_deref(), Some("jp"));
    }

    #[test]
    fn profile_and_config_coexist() {
        let cli = parse(&["--config", "/tmp/c.toml", "--profile", "en"]);
        assert_eq!(
            cli.config.as_deref(),
            Some(std::path::Path::new("/tmp/c.toml"))
        );
        assert_eq!(cli.profile.as_deref(), Some("en"));
    }
}
