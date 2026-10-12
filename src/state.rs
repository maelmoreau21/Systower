use std::{
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum TransactionState {
    Planned,
    ImagePulled,
    BackupCreated,
    ReplacementStarted,
    HealthChecking,
    Committed,
    RollingBack,
    RolledBack,
    RollbackFailed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TransactionRecord {
    pub transaction_id: String,
    pub container_id: String,
    pub state: TransactionState,
    pub image: String,
}

#[derive(Debug, Error)]
pub enum StateError {
    #[error("cannot open state journal {path}: {source}")]
    Open {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("cannot read state journal {path}: {source}")]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("cannot write state journal {path}: {source}")]
    Write {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("invalid state journal record: {0}")]
    InvalidRecord(#[from] serde_json::Error),
    #[error("another Systower instance owns lock {0}")]
    AlreadyLocked(PathBuf),
    #[error("invalid transaction transition from {from:?} to {to:?}")]
    InvalidTransition {
        from: TransactionState,
        to: TransactionState,
    },
}

#[derive(Debug, Clone)]
pub struct Transaction {
    record: TransactionRecord,
}

impl Transaction {
    pub fn new(transaction_id: String, container_id: String, image: String) -> Self {
        Self {
            record: TransactionRecord {
                transaction_id,
                container_id,
                state: TransactionState::Planned,
                image,
            },
        }
    }

    pub fn record(&self) -> &TransactionRecord {
        &self.record
    }

    pub fn transition(&mut self, next: TransactionState) -> Result<(), StateError> {
        if !valid_transition(&self.record.state, &next) {
            return Err(StateError::InvalidTransition {
                from: self.record.state.clone(),
                to: next,
            });
        }
        self.record.state = next;
        Ok(())
    }
}

fn valid_transition(from: &TransactionState, to: &TransactionState) -> bool {
    matches!(
        (from, to),
        (TransactionState::Planned, TransactionState::ImagePulled)
            | (
                TransactionState::ImagePulled,
                TransactionState::BackupCreated
            )
            | (
                TransactionState::BackupCreated,
                TransactionState::ReplacementStarted
            )
            | (
                TransactionState::ReplacementStarted,
                TransactionState::HealthChecking
            )
            | (
                TransactionState::HealthChecking,
                TransactionState::Committed
            )
            | (TransactionState::ImagePulled, TransactionState::RollingBack)
            | (
                TransactionState::BackupCreated,
                TransactionState::RollingBack
            )
            | (
                TransactionState::ReplacementStarted,
                TransactionState::RollingBack
            )
            | (
                TransactionState::HealthChecking,
                TransactionState::RollingBack
            )
            | (TransactionState::RollingBack, TransactionState::RolledBack)
            | (
                TransactionState::RollingBack,
                TransactionState::RollbackFailed
            )
    )
}

pub struct StateJournal {
    path: PathBuf,
}

impl StateJournal {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StateError> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|source| StateError::Write {
                path: parent.to_path_buf(),
                source,
            })?;
        }
        OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .map_err(|source| StateError::Open {
                path: path.clone(),
                source,
            })?;
        Ok(Self { path })
    }

    pub fn append(&self, record: &TransactionRecord) -> Result<(), StateError> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)
            .map_err(|source| StateError::Open {
                path: self.path.clone(),
                source,
            })?;
        let line = serde_json::to_string(record)?;
        writeln!(file, "{line}").map_err(|source| StateError::Write {
            path: self.path.clone(),
            source,
        })?;
        file.sync_data().map_err(|source| StateError::Write {
            path: self.path.clone(),
            source,
        })
    }

    pub fn latest(&self, transaction_id: &str) -> Result<Option<TransactionRecord>, StateError> {
        let file = File::open(&self.path).map_err(|source| StateError::Read {
            path: self.path.clone(),
            source,
        })?;
        let mut latest = None;
        for line in BufReader::new(file).lines() {
            let line = line.map_err(|source| StateError::Read {
                path: self.path.clone(),
                source,
            })?;
            let record: TransactionRecord = serde_json::from_str(&line)?;
            if record.transaction_id == transaction_id {
                latest = Some(record);
            }
        }
        Ok(latest)
    }
}

pub struct InstanceLock {
    path: PathBuf,
    _file: File,
}

impl InstanceLock {
    pub fn acquire(path: impl AsRef<Path>) -> Result<Self, StateError> {
        let path = path.as_ref().to_path_buf();
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .map_err(|source| {
                if source.kind() == std::io::ErrorKind::AlreadyExists {
                    StateError::AlreadyLocked(path.clone())
                } else {
                    StateError::Open {
                        path: path.clone(),
                        source,
                    }
                }
            })?;
        Ok(Self { path, _file: file })
    }
}

impl Drop for InstanceLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("systower-{name}-{}", std::process::id()))
    }

    #[test]
    fn journal_recovers_latest_transaction_state() {
        let path = temp_path("journal");
        let _ = fs::remove_file(&path);
        let journal = StateJournal::open(&path).unwrap();
        let base = TransactionRecord {
            transaction_id: "tx-1".into(),
            container_id: "abc".into(),
            state: TransactionState::Planned,
            image: "example:v1".into(),
        };
        journal.append(&base).unwrap();
        journal
            .append(&TransactionRecord {
                state: TransactionState::Committed,
                ..base.clone()
            })
            .unwrap();
        assert_eq!(
            journal.latest("tx-1").unwrap().unwrap().state,
            TransactionState::Committed
        );
        let _ = fs::remove_file(path);
    }

    #[test]
    fn instance_lock_prevents_concurrent_owner() {
        let path = temp_path("lock");
        let _ = fs::remove_file(&path);
        let lock = InstanceLock::acquire(&path).unwrap();
        assert!(matches!(
            InstanceLock::acquire(&path),
            Err(StateError::AlreadyLocked(_))
        ));
        drop(lock);
        assert!(InstanceLock::acquire(&path).is_ok());
        let _ = fs::remove_file(path);
    }

    #[test]
    fn transaction_rejects_commit_before_health_check() {
        let mut transaction = Transaction::new("tx-2".into(), "abc".into(), "example:v2".into());
        let error = transaction
            .transition(TransactionState::Committed)
            .unwrap_err();
        assert!(matches!(error, StateError::InvalidTransition { .. }));
    }

    #[test]
    fn transaction_allows_verified_rollback_path() {
        let mut transaction = Transaction::new("tx-3".into(), "abc".into(), "example:v2".into());
        for state in [
            TransactionState::ImagePulled,
            TransactionState::BackupCreated,
            TransactionState::ReplacementStarted,
            TransactionState::HealthChecking,
            TransactionState::RollingBack,
            TransactionState::RolledBack,
        ] {
            transaction.transition(state).unwrap();
        }
        assert_eq!(transaction.record().state, TransactionState::RolledBack);
    }
}
