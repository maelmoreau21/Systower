use std::{str::FromStr, time::Duration};

use chrono::Utc;
use cron::Schedule;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SchedulerError {
    #[error("invalid cron schedule: {0}")]
    InvalidCron(String),
    #[error("cron schedule has no future occurrence")]
    NoNextOccurrence,
}

pub fn delay_until_next(cron_expression: &str) -> Result<Duration, SchedulerError> {
    let expression = format!("0 {cron_expression}");
    let schedule = Schedule::from_str(&expression)
        .map_err(|error| SchedulerError::InvalidCron(error.to_string()))?;
    let now = Utc::now();
    let next = schedule
        .upcoming(Utc)
        .next()
        .ok_or(SchedulerError::NoNextOccurrence)?;
    (next - now)
        .to_std()
        .map_err(|_| SchedulerError::NoNextOccurrence)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn five_field_schedule_has_a_future_occurrence() {
        let delay = delay_until_next("0 4 * * *").unwrap();
        assert!(delay <= Duration::from_secs(24 * 60 * 60));
    }

    #[test]
    fn malformed_schedule_is_rejected() {
        assert!(matches!(
            delay_until_next("not a schedule"),
            Err(SchedulerError::InvalidCron(_))
        ));
    }
}
