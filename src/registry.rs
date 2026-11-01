//! Optional Docker config.json credentials for private registry pulls.
//! Never log or serialize the decoded credentials.

use std::{collections::HashMap, env, fs};

use bollard::auth::DockerCredentials;
use serde::Deserialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("unable to read SYSTOWER_DOCKER_AUTH_CONFIG: {0}")]
    Read(#[from] std::io::Error),
    #[error("invalid Docker registry credentials file: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("registry '{0}' uses an external Docker credential helper; provide inline auth in a read-only config.json secret")]
    ExternalHelper(String),
}

#[derive(Debug, Deserialize, Default)]
struct DockerAuthFile {
    #[serde(default)]
    auths: HashMap<String, DockerCredentials>,
    #[serde(default, rename = "credsStore")]
    creds_store: Option<String>,
    #[serde(default, rename = "credHelpers")]
    cred_helpers: HashMap<String, String>,
}

pub fn credentials_for_image(image: &str) -> Result<Option<DockerCredentials>, RegistryError> {
    let Ok(path) = env::var("SYSTOWER_DOCKER_AUTH_CONFIG") else {
        return Ok(None);
    };
    if path.trim().is_empty() {
        return Ok(None);
    }
    let text = fs::read_to_string(path)?;
    parse_credentials(image, &text)
}

fn parse_credentials(
    image: &str,
    contents: &str,
) -> Result<Option<DockerCredentials>, RegistryError> {
    let file: DockerAuthFile = serde_json::from_str(contents)?;
    let host = registry_host(image);

    for (key, mut auth) in file.auths {
        if normalize_registry_host(&key) != host {
            continue;
        }
        if has_inline_credentials(&auth) {
            auth.serveraddress = Some(host.clone());
            return Ok(Some(auth));
        }
    }
    if file.creds_store.as_deref().is_some_and(|value| !value.is_empty())
        || file.cred_helpers.keys().any(|key| normalize_registry_host(key) == host)
    {
        return Err(RegistryError::ExternalHelper(host));
    }
    Ok(None)
}

/// Docker Hub is implied unless the first path component is a registry host.
fn registry_host(image: &str) -> String {
    let first = image.split('/').next().unwrap_or_default();
    if first.contains('.') || first.contains(':') || first == "localhost" {
        normalize_registry_host(first)
    } else {
        "docker.io".into()
    }
}

fn normalize_registry_host(key: &str) -> String {
    let host = key
        .trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .split('/')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase();
    match host.as_str() {
        "index.docker.io" | "registry-1.docker.io" => "docker.io".into(),
        _ => host,
    }
}

fn has_inline_credentials(auth: &DockerCredentials) -> bool {
    auth.auth.as_deref().is_some_and(|s| !s.is_empty())
        || auth.identitytoken.as_deref().is_some_and(|s| !s.is_empty())
        || auth.registrytoken.as_deref().is_some_and(|s| !s.is_empty())
        || (auth.username.as_deref().is_some_and(|s| !s.is_empty())
            && auth.password.as_deref().is_some_and(|s| !s.is_empty()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ghcr_auth_config_is_loaded_for_matching_image_only() {
        let config = r#"{"auths":{"ghcr.io":{"auth":"dGVzdDpwYXNz"}}}"#;
        let auth = parse_credentials("ghcr.io/example/private:v1", config)
            .unwrap()
            .unwrap();
        assert_eq!(auth.auth.as_deref(), Some("dGVzdDpwYXNz"));
        assert_eq!(auth.serveraddress.as_deref(), Some("ghcr.io"));
        assert!(parse_credentials("docker.io/library/alpine:latest", config)
            .unwrap()
            .is_none());
    }

    #[test]
    fn docker_hub_alias_matches_implicit_images() {
        let config = r#"{"auths":{"https://index.docker.io/v1/":{"auth":"abc"}}}"#;
        assert!(parse_credentials("nginx:alpine", config).unwrap().is_some());
        assert!(parse_credentials("library/nginx:alpine", config)
            .unwrap()
            .is_some());
    }

    #[test]
    fn credentials_helpers_are_not_silently_assumed_available() {
        let config = r#"{"auths":{"ghcr.io":{}},"credHelpers":{"ghcr.io":"desktop"}}"#;
        assert!(matches!(
            parse_credentials("ghcr.io/team/api:v1", config),
            Err(RegistryError::ExternalHelper(_))
        ));
    }

    #[test]
    fn invalid_registry_file_fails_without_credential_leaks() {
        assert!(matches!(
            parse_credentials("ghcr.io/test/api", "bad json"),
            Err(RegistryError::InvalidJson(_))
        ));
    }
}
