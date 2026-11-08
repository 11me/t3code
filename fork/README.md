# T3 Code fork: build tooling

Scripts for running your own build of T3 Code: upstream nightlies plus your own features, built
locally into an unsigned macOS app.

- Fork: https://github.com/11me/t3code (`origin`). Upstream: `pingdotgg/t3code` (`upstream`).
- Installed app: `/Applications/T3 Code (Nightly).app`. It is unsigned, so in-app updates are off.
- Build cache, logs and backups: `~/.cache/t3code-fork/`.
- Private notes (backlog, history, agent instructions) live in `.fork/` at the repo root. It is
  excluded through `.git/info/exclude` and never committed.

## Branches

| Branch     | What it is                                                                                                                  |
| ---------- | --------------------------------------------------------------------------------------------------------------------------- |
| `patched`  | Upstream nightlies, this `fork/` folder, and your **tested** features. Builds come from here. The default branch on GitHub. |
| `main`     | A clean mirror of the latest upstream nightly, with none of your changes. `build.sh` moves it forward.                      |
| `feat/...` | A feature in progress, started from `patched`. It goes into `patched` once you have tried it and it works.                  |

Start feature branches from `patched`, not from `main` or upstream. A branch without `fork/`
removes these scripts from disk while it is checked out. `build.sh` skips `fork/` when it
applies a branch.

Upstream changes arrive only through published nightly tags, which upstream has already built
and released, never through upstream's moving `main` branch.

## Day to day

1. **A notification tells you when a new nightly is out.** A launchd job runs
   `fork/check.sh --notify` daily at 10:00 (or on wake), once per new nightly. It never
   builds or installs anything.
2. **Ask Claude to rebuild.** For example: "rebuild T3 Code", or "rebuild T3 Code with
   feat/xyz" to test a feature. Claude runs `fork/build.sh`, resolves conflicts if there are
   any, and pushes `patched` and `main`.
3. **Install from Terminal**, not from inside T3 Code, because it quits the app:

   ```sh
   <your t3code checkout>/fork/install.sh --open
   ```

If the new version misbehaves: `fork/install.sh --rollback --open`.

## Scripts

| Script                  | What it does                                                                                                                                                                                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `check.sh`              | Prints the installed and latest nightly. `--notify` also shows a notification; `--test` sends a test one.                                                                                                                                                          |
| `build.sh [feat/x ...]` | Merges the latest nightly into `patched` in a separate checkout, applies the feature branches you name, and builds a DMG into `~/.cache/t3code-fork/out/`. `--dry-run` stops before building; `--tag` picks a nightly. On a conflict it stops and changes nothing. |
| `install.sh`            | Installs the newest build: quits the app, re-signs ad hoc, keeps the old version. `--rollback` restores it, `--open` launches afterwards.                                                                                                                          |
| `notifier.sh`           | `install`, `uninstall`, `status` or `run` the daily check.                                                                                                                                                                                                         |

## Features: from idea to patched

1. Claude creates `feat/<name>` from `patched` and implements it, with tests and review.
2. Test it: "rebuild T3 Code with feat/<name>", then install and use it.
3. If it works: "merge feat/<name> into patched". Claude merges it, pushes `patched` and deletes the
   branch. Every later build includes it.
4. If it does not: the branch stays out of `patched`; fix it or drop it.

## When something breaks

- **Conflict with a new nightly:** `build.sh` stops and lists the files. Ask Claude to
  merge the nightly into `patched` (or update the feature branch). Your installed app keeps working.
- **Build failure:** the last lines are printed; the full log is in `~/.cache/t3code-fork/logs/`.
- **Daily check errors:** see `~/.cache/t3code-fork/check.log`.

## Requirements

`vp` (Vite+, `~/.config/vite-plus/env`), Node 26 through mise, Rust (`cargo`), and Xcode's
command-line tools. A build needs a few GB in `~/.cache/t3code-fork/`; the first one takes the
longest, later ones reuse installed packages and the Rust build.

## Set up on another Mac

```sh
git clone https://github.com/11me/t3code && cd t3code
fork/build.sh                # adds the upstream remote on first run
fork/install.sh --open       # from Terminal, not inside T3 Code
```

`fork/notifier.sh install` turns on the daily check there too. Treat a second Mac as
build-only: don't push `patched` or `main` from it, so the two copies never diverge. To build a feature that
isn't in `patched` yet, name its branch: `fork/build.sh feat/<name>`.

## Notes

- Stable and nightly T3 Code share `~/.t3/userdata` and one single-instance lock: run only one
  of `T3 Code (Beta)` and `T3 Code (Nightly)` at a time. Once a nightly has upgraded your data,
  an older stable may not open it until stable catches up.
- To stop the notifications: `fork/notifier.sh uninstall`.
