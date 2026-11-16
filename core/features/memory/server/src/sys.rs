//! The few system calls the standard library and tokio do not wrap, kept in
//! one module because they need `unsafe` (plan 22, phase C, 2026-11-15):
//!
//! - kqueue `EVFILT_PROC`/`NOTE_EXIT`, so the engine learns that a `claude`
//!   ended the moment it does, with no polling timer (the engine is not the
//!   parent of those processes, so `waitpid` cannot tell it);
//! - the effective uid, to refuse connections from another user;
//! - clearing close-on-exec on the two descriptors a restart hands to the
//!   next image, and taking them back on the other side;
//! - for `cadex-memory run` (plan 22 phase E, 2026-11-16): the host name of
//!   the lease owner label (upstream asks `sysinfo`, not in this crate), and
//!   `setsid` in the engine the launcher starts, so it leaves the terminal's
//!   session as launch.zig's `POSIX_SPAWN_SETSID` does.

use std::io;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};

/// The effective uid of this process.
pub(crate) fn effective_uid() -> u32 {
    // SAFETY: geteuid has no preconditions and cannot fail.
    unsafe { libc::geteuid() }
}

/// Let `fd` survive `exec` (std and tokio open everything close-on-exec).
pub(crate) fn inherit_on_exec(fd: RawFd) -> io::Result<()> {
    // SAFETY: fcntl on a descriptor we own; F_SETFD with 0 only clears FD_CLOEXEC.
    if unsafe { libc::fcntl(fd, libc::F_SETFD, 0) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// Take ownership of a descriptor the previous image passed by number, and
/// mark it close-on-exec again so no child (git) inherits it.
pub(crate) fn adopt(fd: RawFd) -> io::Result<OwnedFd> {
    // SAFETY: F_GETFD only reads the descriptor flags; a closed fd fails with EBADF.
    if unsafe { libc::fcntl(fd, libc::F_GETFD) } < 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: the descriptor is open (checked above) and nothing else in this
    // image owns it: it was handed over by number on the command line.
    let owned = unsafe { OwnedFd::from_raw_fd(fd) };
    // SAFETY: as in inherit_on_exec, on a descriptor we now own.
    unsafe { libc::fcntl(owned.as_raw_fd(), libc::F_SETFD, libc::FD_CLOEXEC) };
    Ok(owned)
}

/// This machine's host name, `None` if it cannot be read.
pub(crate) fn host_name() -> Option<String> {
    let mut buf = [0u8; 256];
    // SAFETY: gethostname writes at most `buf.len()` bytes into a buffer we own.
    if unsafe { libc::gethostname(buf.as_mut_ptr().cast(), buf.len()) } != 0 {
        return None;
    }
    let len = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    String::from_utf8(buf[..len].to_vec()).ok().filter(|name| !name.trim().is_empty())
}

/// Make `command`'s child the leader of a new session (no controlling
/// terminal: a Ctrl-C or a closed tab of the launcher never reaches it).
pub(crate) fn new_session_on_spawn(command: &mut std::process::Command) {
    use std::os::unix::process::CommandExt;
    // SAFETY: setsid is async-signal-safe, the only kind of call allowed
    // between fork and exec, and touches no memory of the parent.
    unsafe {
        command.pre_exec(|| if libc::setsid() < 0 { Err(io::Error::last_os_error()) } else { Ok(()) });
    }
}

/// A kqueue that reports the exit of the processes it watches.
pub(crate) struct ProcWatch {
    kq: OwnedFd,
}

impl ProcWatch {
    pub(crate) fn new() -> io::Result<Self> {
        // SAFETY: kqueue takes no arguments; a negative result is an error.
        let fd = unsafe { libc::kqueue() };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        // SAFETY: a fresh descriptor that nothing else owns.
        let kq = unsafe { OwnedFd::from_raw_fd(fd) };
        // SAFETY: as in adopt; a restart must not hand the kqueue on.
        unsafe { libc::fcntl(kq.as_raw_fd(), libc::F_SETFD, libc::FD_CLOEXEC) };
        Ok(Self { kq })
    }

    /// Start watching `pid`. `Ok(false)` when it is already gone.
    pub(crate) fn watch(&self, pid: i32) -> io::Result<bool> {
        let change = libc::kevent {
            ident: pid as libc::uintptr_t,
            filter: libc::EVFILT_PROC,
            flags: libc::EV_ADD | libc::EV_ONESHOT,
            fflags: libc::NOTE_EXIT,
            data: 0,
            udata: std::ptr::null_mut(),
        };
        // SAFETY: one valid change record in, no event list out, no timeout.
        let r = unsafe {
            libc::kevent(self.kq.as_raw_fd(), &change, 1, std::ptr::null_mut(), 0, std::ptr::null())
        };
        if r < 0 {
            let error = io::Error::last_os_error();
            return if error.raw_os_error() == Some(libc::ESRCH) { Ok(false) } else { Err(error) };
        }
        Ok(true)
    }

    /// Block until a watched process exits; its pid. Other threads may call
    /// `watch` meanwhile (kqueue allows changes while one thread waits).
    pub(crate) fn wait(&self) -> io::Result<i32> {
        loop {
            // SAFETY: an all-zero kevent is a valid output buffer.
            let mut event: libc::kevent = unsafe { std::mem::zeroed() };
            // SAFETY: no changes in, room for one event out, wait forever.
            let r = unsafe {
                libc::kevent(self.kq.as_raw_fd(), std::ptr::null(), 0, &mut event, 1, std::ptr::null())
            };
            if r < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if r == 1 && event.filter == libc::EVFILT_PROC {
                return Ok(event.ident as i32);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_kqueue_reports_a_child_that_ends_and_refuses_a_dead_pid() {
        let watch = ProcWatch::new().unwrap();
        let mut child = std::process::Command::new("/bin/sleep").arg("30").spawn().unwrap();
        let pid = child.id() as i32;
        assert!(watch.watch(pid).unwrap());
        child.kill().unwrap();
        assert_eq!(watch.wait().unwrap(), pid);
        child.wait().unwrap();
        assert!(!watch.watch(pid).unwrap(), "a reaped pid counts as ended");
    }
}
