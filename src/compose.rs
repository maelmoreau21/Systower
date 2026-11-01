//! Explicit, service-scoped Docker Compose updates.
//! Compose remains the source of truth; never reconstruct a Compose service
//! from Docker Engine inspect output.

use std::{
    ffi::OsString,
    path::PathBuf,
    process::Command,
};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ComposeError {
    #[error("at least one Compose file is required")]
    MissingFile,
    #[error("at least one explicit service is required to avoid starting stopped services")]
    MissingService,
    #[error("Compose file is missing or not a regular file: {0}")]
    InvalidFile(PathBuf),
    #[error("Compose project directory does not exist: {0}")]
    InvalidDirectory(PathBuf),
    #[error("invalid Compose service name: {0}")]
    InvalidService(String),
    #[error("Compose command could not be executed: {0}")]
    Io(#[from] std::io::Error),
    #[error("docker compose {phase} failed with status {status}")]
    CommandFailed { phase: &'static str, status: String },
}

#[derive(Debug)]
pub struct ComposePlan {
    files: Vec<PathBuf>,
    project_directory: Option<PathBuf>,
    services: Vec<String>,
}

#[derive(Debug)]
pub struct ComposeStep {
    pub phase: &'static str,
    pub args: Vec<OsString>,
}

impl ComposePlan {
    pub fn new(
        files: Vec<PathBuf>,
        project_directory: Option<PathBuf>,
        services: Vec<String>,
    ) -> Result<Self, ComposeError> {
        if files.is_empty() {
            return Err(ComposeError::MissingFile);
        }
        if services.is_empty() {
            return Err(ComposeError::MissingService);
        }
        for service in &services {
            if !valid_service_name(service) {
                return Err(ComposeError::InvalidService(service.clone()));
            }
        }
        let mut normalized_files = Vec::with_capacity(files.len());
        for file in files {
            if !file.is_file() {
                return Err(ComposeError::InvalidFile(file));
            }
            normalized_files.push(file.canonicalize()?);
        }
        let project_directory = match project_directory {
            Some(directory) => {
                if !directory.is_dir() {
                    return Err(ComposeError::InvalidDirectory(directory));
                }
                Some(directory.canonicalize()?)
            }
            None => None,
        };
        Ok(Self {
            files: normalized_files,
            project_directory,
            services,
        })
    }

    pub fn services(&self) -> &[String] {
        &self.services
    }

    pub fn files(&self) -> &[PathBuf] {
        &self.files
    }

    pub fn steps(&self) -> Vec<ComposeStep> {
        let mut common = vec![OsString::from("compose")];
        for file in &self.files {
            common.push(OsString::from("--file"));
            common.push(file.as_os_str().to_owned());
        }
        if let Some(directory) = &self.project_directory {
            common.push(OsString::from("--project-directory"));
            common.push(directory.as_os_str().to_owned());
        }

        let mut config = common.clone();
        config.extend([OsString::from("config"), OsString::from("--quiet")]);

        let mut pull = common.clone();
        pull.extend([OsString::from("pull"), OsString::from("--ignore-buildable")]);
        pull.extend(self.services.iter().map(OsString::from));

        let mut up = common;
        up.extend([
            OsString::from("up"),
            OsString::from("--detach"),
            OsString::from("--no-deps"),
            OsString::from("--pull"),
            OsString::from("never"),
        ]);
        up.extend(self.services.iter().map(OsString::from));

        vec![
            ComposeStep {
                phase: "config",
                args: config,
            },
            ComposeStep {
                phase: "pull",
                args: pull,
            },
            ComposeStep {
                phase: "up",
                args: up,
            },
        ]
    }
}

/// Apply is deliberately explicit: previews never execute docker commands.
pub fn execute(plan: &ComposePlan, apply: bool) -> Result<(), ComposeError> {
    if !apply {
        return Ok(());
    }
    for step in plan.steps() {
        let result = Command::new("docker").args(&step.args).status()?;
        if !result.success() {
            return Err(ComposeError::CommandFailed {
                phase: step.phase,
                status: result.to_string(),
            });
        }
    }
    Ok(())
}

fn valid_service_name(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|first| first.is_ascii_alphanumeric())
        && chars.all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> (PathBuf, ComposePlan) {
        let file = std::env::temp_dir().join(format!(
            "systower-compose-test-{}-{}.yaml",
            std::process::id(),
            std::thread::current().name().unwrap_or("main")
        ));
        std::fs::write(&file, "services:\n  web:\n    image: nginx:alpine\n").unwrap();
        let plan = ComposePlan::new(vec![file.clone()], None, vec!["web".into()]).unwrap();
        (file, plan)
    }

    #[test]
    fn explicitly_selected_service_is_updated_without_deps() {
        let (file, plan) = sample();
        let steps = plan.steps();
        assert_eq!(steps.len(), 3);
        assert_eq!(steps[0].phase, "config");
        assert_eq!(steps[1].phase, "pull");
        assert_eq!(steps[2].phase, "up");
        assert_eq!(steps[1].args.last(), Some(&OsString::from("web")));
        assert!(steps[2].args.contains(&OsString::from("--no-deps")));
        assert!(steps[2].args.contains(&OsString::from("never")));
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn refusing_unscoped_updates_prevents_full_stack_startup() {
        let (file, _) = sample();
        let error = ComposePlan::new(vec![file.clone()], None, vec![]).unwrap_err();
        assert!(matches!(error, ComposeError::MissingService));
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn invalid_service_names_cannot_become_command_options() {
        let (file, _) = sample();
        let error = ComposePlan::new(vec![file.clone()], None, vec!["--profile".into()])
            .unwrap_err();
        assert!(matches!(error, ComposeError::InvalidService(_)));
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn preview_mode_never_executes_docker() {
        let (file, plan) = sample();
        execute(&plan, false).unwrap();
        std::fs::remove_file(file).unwrap();
    }

    #[test]
    fn project_directory_and_files_are_explicit() {
        let (file, _) = sample();
        let dir = file.parent().unwrap().to_path_buf();
        let plan = ComposePlan::new(vec![file.clone()], Some(dir), vec!["web".into()]).unwrap();
        let step = &plan.steps()[0];
        assert!(step.args.contains(&OsString::from("--project-directory")));
        std::fs::remove_file(file).unwrap();
    }
}
