use std::{
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum TransactionState {
    Planned,
    ImagePulled,
    OriginalStopping,
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

    pub fn from_record(record: TransactionRecord) -> Self {
        Self { record }
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
                TransactionState::OriginalStopping
            )
            | (
                TransactionState::OriginalStopping,
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
                TransactionState::OriginalStopping,
                TransactionState::RollingBack
            )
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

    pub fn interrupted(&self) -> Result<Vec<TransactionRecord>, StateError> {
        let file = File::open(&self.path).map_err(|source| StateError::Read {
            path: self.path.clone(),
            source,
        })?;
        let mut records = std::collections::HashMap::new();
        for line in BufReader::new(file).lines() {
            let line = line.map_err(|source| StateError::Read {
                path: self.path.clone(),
                source,
            })?;
            let record: TransactionRecord = serde_json::from_str(&line)?;
            records.insert(record.transaction_id.clone(), record);
        }
        Ok(records
            .into_values()
            .filter(|record| {
                !matches!(
                    record.state,
                    TransactionState::Committed
                        | TransactionState::RolledBack
                        | TransactionState::RollbackFailed
                )
            })
            .collect())
    }
}

pub struct InstanceLock {
    _file: File,
}

impl InstanceLock {
    /// Acquire an exclusive OS-level lock on `path`.
    ///
    /// Uses kernel-managed locks (`flock` on Unix, exclusive `share_mode(0)` on Windows)
    /// so locks are automatically released on process exit, crash, `SIGKILL`, or
    /// container restart—even when the restarted process reuses the same PID (e.g. PID 1).
    pub fn acquire(path: impl AsRef<Path>) -> Result<Self, StateError> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent).map_err(|source| StateError::Write {
                    path: parent.to_path_buf(),
                    source,
                })?;
            }
        }

        let mut file = open_and_lock(&path)?;
        file.set_len(0).map_err(|source| StateError::Write {
            path: path.clone(),
            source,
        })?;
        file.seek(SeekFrom::Start(0))
            .map_err(|source| StateError::Write {
                path: path.clone(),
                source,
            })?;
        writeln!(file, "{}", std::process::id()).map_err(|source| StateError::Write {
            path: path.clone(),
            source,
        })?;
        file.sync_data().map_err(|source| StateError::Write {
            path: path.clone(),
            source,
        })?;
        Ok(Self { _file: file })
    }
}

#[cfg(unix)]
fn open_and_lock(path: &Path) -> Result<File, StateError> {
    use std::os::fd::AsRawFd;

    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)
        .map_err(|source| StateError::Open {
            path: path.to_path_buf(),
            source,
        })?;

    // Retry only on EINTR; EWOULDBLOCK/EAGAIN means another live process holds the lock.
    loop {
        let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if rc == 0 {
            return Ok(file);
        }
        let err = std::io::Error::last_os_error();
        if err.raw_os_error() == Some(libc::EINTR) {
            continue;
        }
        if matches!(
            err.raw_os_error(),
            Some(libc::EWOULDBLOCK) | Some(libc::EAGAIN)
        ) {
            return Err(StateError::AlreadyLocked(path.to_path_buf()));
        }
        return Err(StateError::Open {
            path: path.to_path_buf(),
            source: err,
        });
    }
}

#[cfg(windows)]
fn open_and_lock(path: &Path) -> Result<File, StateError> {
    use std::os::windows::fs::OpenOptionsExt;

    const ERROR_SHARING_VIOLATION: i32 = 32;
    match OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .share_mode(0)
        .open(path)
    {
        Ok(file) => Ok(file),
        Err(source) if source.raw_os_error() == Some(ERROR_SHARING_VIOLATION) => {
            Err(StateError::AlreadyLocked(path.to_path_buf()))
        }
        Err(source) => Err(StateError::Open {
            path: path.to_path_buf(),
            source,
        }),
    }
}

#[cfg(not(any(unix, windows)))]
fn open_and_lock(path: &Path) -> Result<File, StateError> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)
        .map_err(|source| StateError::Open {
            path: path.to_path_buf(),
            source,
        })
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
    fn stale_lock_owned_by_missing_process_is_reclaimed() {
        let path = temp_path("stale-lock");
        let _ = fs::remove_file(&path);
        fs::write(&path, "4294967295\n").unwrap();
        let lock = InstanceLock::acquire(&path).unwrap();
        drop(lock);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn stale_lock_with_current_pid_is_reclaimed() {
        let path = temp_path("stale-self-pid-lock");
        let _ = fs::remove_file(&path);
        fs::write(&path, format!("{}\n", std::process::id())).unwrap();
        let lock = InstanceLock::acquire(&path).unwrap();
        assert!(matches!(
            InstanceLock::acquire(&path),
            Err(StateError::AlreadyLocked(_))
        ));
        drop(lock);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn acquire_creates_missing_parent_directory() {
        let dir = temp_path("lock-parent-dir");
        let _ = fs::remove_dir_all(&dir);
        let path = dir.join("nested").join("state.jsonl.lock");
        let lock = InstanceLock::acquire(&path).unwrap();
        assert!(path.exists());
        drop(lock);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn interrupted_returns_only_non_terminal_transactions() {
        let path = temp_path("interrupted");
        let _ = fs::remove_file(&path);
        let journal = StateJournal::open(&path).unwrap();
        let base = TransactionRecord {
            transaction_id: "tx-active".into(),
            container_id: "abc".into(),
            state: TransactionState::ReplacementStarted,
            image: "example:v2".into(),
        };
        journal.append(&base).unwrap();
        journal
            .append(&TransactionRecord {
                transaction_id: "tx-done".into(),
                state: TransactionState::Committed,
                ..base.clone()
            })
            .unwrap();
        let interrupted = journal.interrupted().unwrap();
        assert_eq!(interrupted.len(), 1);
        assert_eq!(interrupted[0].transaction_id, "tx-active");
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
            TransactionState::OriginalStopping,
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
