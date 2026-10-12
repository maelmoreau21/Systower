use std::time::Duration;

use reqwest::Client;
use serde::Serialize;
use thiserror::Error;

use crate::config::Config;

#[derive(Debug, Clone, Serialize)]
pub struct NotificationEvent {
    pub event: String,
    pub title: String,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum NotificationError {
    #[error("notification request failed: {0}")]
    Request(#[from] reqwest::Error),
}

#[derive(Clone)]
pub struct Notifier {
    client: Client,
    webhook: Option<String>,
    discord: Option<String>,
    slack: Option<String>,
    telegram: Option<(String, String)>,
}

impl Notifier {
    pub fn from_config(config: &Config) -> Result<Self, reqwest::Error> {
        let client = Client::builder().timeout(Duration::from_secs(10)).build()?;
        Ok(Self {
            client,
            webhook: non_empty(&config.notify_webhook),
            discord: non_empty(&config.notify_discord),
            slack: non_empty(&config.notify_slack),
            telegram: match (
                non_empty(&config.notify_telegram_token),
                non_empty(&config.notify_telegram_chat),
            ) {
                (Some(token), Some(chat)) => Some((token, chat)),
                _ => None,
            },
        })
    }

    pub async fn send(&self, event: &NotificationEvent) -> Result<(), NotificationError> {
        if let Some(url) = &self.webhook {
            self.client
                .post(url)
                .json(event)
                .send()
                .await?
                .error_for_status()?;
        }
        if let Some(url) = &self.discord {
            self.client
                .post(url)
                .json(&MessagePayload {
                    content: format!("{}\n{}", event.title, event.message),
                })
                .send()
                .await?
                .error_for_status()?;
        }
        if let Some(url) = &self.slack {
            self.client
                .post(url)
                .json(&MessagePayload {
                    content: format!("{}\n{}", event.title, event.message),
                })
                .send()
                .await?
                .error_for_status()?;
        }
        if let Some((token, chat)) = &self.telegram {
            let url = format!("https://api.telegram.org/bot{token}/sendMessage");
            self.client
                .post(url)
                .json(&TelegramPayload {
                    chat_id: chat,
                    text: format!("{}\n{}", event.title, event.message),
                })
                .send()
                .await?
                .error_for_status()?;
        }
        Ok(())
    }
}

#[derive(Serialize)]
struct MessagePayload {
    content: String,
}

#[derive(Serialize)]
struct TelegramPayload<'a> {
    chat_id: &'a str,
    text: String,
}

fn non_empty(value: &str) -> Option<String> {
    (!value.trim().is_empty()).then(|| value.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn event_serializes_without_credentials() {
        let event = NotificationEvent {
            event: "update.success".into(),
            title: "Updated api".into(),
            message: "sha256:new".into(),
        };
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("update.success"));
        assert!(!json.contains("token"));
    }
}
