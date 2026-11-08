#!/bin/bash
# Builds the fork app from `main` merged with the latest upstream nightly, plus any feature
# branches being tested, into a DMG under ~/.cache/t3code-fork/out/<version>/.
# Install the result with fork/install.sh.
#
#   fork/build.sh                         main + latest nightly
#   fork/build.sh feat/my-feature ...     also apply these branches, for testing
#   fork/build.sh --tag v0.1.8-nightly.20261104.4179   a specific nightly
#   fork/build.sh --dry-run [...]         stop after merging and applying; build nothing
#
# Work happens in a separate checkout (~/.cache/t3code-fork/worktree), never in this one.
# On a conflict it stops, names the files and changes nothing. After a successful build,
# local `main` includes the nightly; push it with `git push origin main`.

set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

tag=""
dry_run=false
branches=()
while (($#)); do
  case "$1" in
    --tag)
      tag="${2:?--tag needs a value}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h | --help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *)
      branches+=("$1")
      shift
      ;;
  esac
done

# shellcheck disable=SC1091
[[ -f "$HOME/.config/vite-plus/env" ]] && source "$HOME/.config/vite-plus/env"
for tool in git vp mise cargo; do
  command -v "$tool" >/dev/null || die "$tool is not installed (see fork/README.md)"
done

cd "$REPO_DIR"
[[ -n "$tag" ]] || tag="$(latest_nightly_tag)"
version="${tag#v}"
note "Nightly: $tag"

# A fresh clone of the fork has only `origin`.
git remote get-url upstream >/dev/null 2>&1 ||
  git remote add upstream "https://github.com/$UPSTREAM_REPO.git"
git fetch -q upstream main "+refs/tags/$tag:refs/tags/$tag"
git fetch -q origin

# Local main follows origin/main when someone pushed there; never silently diverge.
if git merge-base --is-ancestor main origin/main; then
  if [[ "$(git branch --show-current)" == "main" ]]; then
    git merge -q --ff-only origin/main
  else
    git update-ref refs/heads/main origin/main
  fi
elif ! git merge-base --is-ancestor origin/main main; then
  die "local main and origin/main have diverged; reconcile them first"
fi

worktree="$CACHE_DIR/worktree"
mkdir -p "$CACHE_DIR/logs"
if [[ ! -e "$worktree/.git" ]]; then
  note "Creating the build checkout at $worktree (first run only) ..."
  git worktree add -q --no-checkout --detach "$worktree" main
  # Upstream's vendored .repos tree holds orphaned gitlinks that break checkout.
  git -C "$worktree" sparse-checkout set --no-cone '/*' '!/.repos/'
fi
git -C "$worktree" merge --abort 2>/dev/null || true
git -C "$worktree" reset -q --hard 2>/dev/null || true
# Keep installed packages and the Rust build between runs; they make rebuilds fast.
git -C "$worktree" clean -fdxq -e node_modules -e native/resource-monitor/target
git -C "$worktree" checkout -q --detach main

main_before="$(git -C "$worktree" rev-parse HEAD)"
if ! git -C "$worktree" merge -q --no-edit -m "Merge upstream $tag into main" "$tag"; then
  conflicts="$(git -C "$worktree" diff --name-only --diff-filter=U | sed 's/^/  /')"
  git -C "$worktree" merge --abort
  die "main conflicts with $tag in:
$conflicts
Ask Claude to merge $tag into main."
fi
main_synced="$(git -C "$worktree" rev-parse HEAD)"

for branch in ${branches[@]+"${branches[@]}"}; do
  ref="origin/$branch"
  git rev-parse -q --verify "$ref^{commit}" >/dev/null || ref="$branch"
  head="$(git rev-parse --verify "$ref^{commit}")" || die "no branch named $branch"
  if git merge-base --is-ancestor "$head" main; then
    note "Skipping $branch: already in main."
    continue
  fi
  # Apply only the branch's own changes, not the upstream commits it was based on. Branches
  # start from main, so they carry fork/, which main already has.
  base="$(git merge-base upstream/main "$head")"
  if ! git diff --binary "$base" "$head" -- . ':(exclude)fork' |
    git -C "$worktree" apply --3way --index -q; then
    conflicts="$(git -C "$worktree" diff --name-only --diff-filter=U | sed 's/^/  /')"
    git -C "$worktree" reset -q --hard
    die "$branch does not apply on top of main + $tag:
$conflicts
Ask Claude to update $branch."
  fi
  git -C "$worktree" commit -q -m "Apply $branch (${head:0:10})"
  note "Applied $branch (${head:0:10})"
done

if [[ "$dry_run" == true ]]; then
  note "Dry run: main + $tag ${branches[*]+and ${branches[*]} }merge and apply cleanly. Nothing built."
  exit 0
fi

log="$CACHE_DIR/logs/build-$version.log"
out="$CACHE_DIR/out/$version"
rm -rf "$out"
note "Building $version (about 5-10 minutes; log: $log) ..."
(
  cd "$worktree"
  cp .env.example .env # Public T3 Connect identifiers, the same ones official builds embed.
  vp install
  mise exec "node@$NODE_VERSION" -- node scripts/update-release-package-versions.ts "$version"
  # Without an update feed the unsigned app reports updates as unavailable instead of failing.
  env -u GITHUB_REPOSITORY -u T3CODE_DESKTOP_UPDATE_REPOSITORY \
    mise exec "node@$NODE_VERSION" -- node scripts/build-desktop-artifact.ts \
    --platform mac --target dmg --arch arm64 --build-version "$version" --output-dir "$out"
) >"$log" 2>&1 || {
  tail -n 30 "$log" >&2
  die "build failed; full log: $log"
}
find "$out" -mindepth 1 ! -name '*.dmg' -exec rm -rf {} +
dmg="$(find "$out" -name '*.dmg' | head -n 1)"
[[ -n "$dmg" ]] || die "the build produced no DMG; see $log"

# Keep the three newest builds.
find "$CACHE_DIR/out" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 ls -dt |
  tail -n +4 | while IFS= read -r old; do rm -rf "$old"; done

if [[ "$main_synced" != "$main_before" ]]; then
  if [[ "$(git branch --show-current)" == "main" ]]; then
    note "Your checkout is on main: run 'git merge --ff-only $main_synced' to take the nightly."
  else
    git update-ref refs/heads/main "$main_synced" "$main_before"
    note "Local main now includes $tag. Push it with: git push origin main"
  fi
fi

note "Built: $dmg"
note "Install it from Terminal with: $REPO_DIR/fork/install.sh"
