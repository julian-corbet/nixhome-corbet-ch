#!/usr/bin/env bash
# MEASURES THE ONE KIND OF KNOWLEDGE IN THIS CATALOGUE THAT IS NOT DERIVED: how long each
# application actually takes before its declared readiness endpoint answers, and whether that
# endpoint still answers at all.
#
# Everything else in lib/trackers.nix is a fact about a shape -- which port, which directory, which
# variable -- and is checked at evaluation time by checks/catalogue-eval.nix. The probe numbers are
# not that. They are a measurement of an image at a moment, they drift as upstream changes, and no
# eval-time check can see them: asserting them would need either a container runtime inside a pure
# evaluation or a snapshot that silently goes stale. That is the whole reason this file is in
# experiments/ and not in checks/.
#
# WHAT IT ANSWERS, per catalogued application:
#
#   1. does the declared readiness endpoint still exist? An HTTP path that has moved turns a
#      readiness probe into a permanent restart loop, and the catalogue would go on claiming it.
#   2. how long does a COLD FIRST START take? Two of these applications migrate their own schema on
#      the first start against an empty directory, which is the slowest start they will ever have --
#      and the one the initial delay and the failure budget exist for.
#   3. does the application come up at all against an EMPTY directory? It always does, and that is
#      the point rather than a reassurance: an application that finds nothing INITIALISES A FRESH
#      EMPTY STORE and then reports itself perfectly healthy, which is exactly the failure the
#      `Directory` hostPath type exists to prevent. This script demonstrates it on purpose.
#
# WHAT IT DELIBERATELY DOES NOT DO. It mounts nothing, it supplies no credential, and it keeps
# nothing: every container it starts is thrown away, so it can tell you an application STARTED and
# never that it WORKS. A run here is not a substitute for using the thing.
#
# NAMES ARE READ OUT OF lib/trackers.nix, never hand-maintained in this file -- a duplicated list
# goes stale in both directions, silently skipping entries that were added and still "verifying"
# entries that were removed.
#
# THE CATALOGUE CARRIES NO VERSIONS, on purpose (which version a household is willing to be migrated
# to is its own decision), so a tag has to be supplied here. `latest` is the default and is the
# honest one for this question: it measures what upstream is shipping today, which is what changes
# without this repository changing.
#
# Usage: ./experiments/probe-readiness.sh [--tag <tag>] [--runtime podman|docker] [--timeout <s>]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tag="latest"
runtime=""
timeout=300

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)     tag="$2"; shift 2 ;;
    --runtime) runtime="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$runtime" ]]; then
  if command -v podman >/dev/null 2>&1; then runtime=podman
  elif command -v docker >/dev/null 2>&1; then runtime=docker
  else
    echo "no container runtime found. Install one, or pass --runtime." >&2
    exit 2
  fi
fi

# Pure builtins on purpose: this only reads an attrset of strings and numbers, so it must work on a
# host with no <nixpkgs> channel at all. One line per entry, tab-separated, so the shell never has
# to parse Nix.
rows="$(nix-instantiate --eval --strict --expr '
  let
    cat = import ./lib/trackers.nix { };
    entries =
      builtins.concatLists (map
        (group: map (n: { name = n; e = cat.${group}.${n}; }) (builtins.attrNames cat.${group}))
        (builtins.attrNames cat));
    row = x:
      let e = x.e; in
      builtins.concatStringsSep "\t" [
        x.name
        e.image
        (toString e.ports.${e.primaryPort})
        (if e.readiness.path == null then "-" else e.readiness.path)
        (toString e.readiness.initialDelaySeconds)
      ];
  in builtins.concatStringsSep "\n" (map row entries)
' | sed 's/^"//; s/"$//; s/\\t/\t/g; s/\\n/\n/g')"

status=0
printf '== Cold first start against an EMPTY directory -- runtime %s, tag %s ==\n' "$runtime" "$tag"
printf '   The catalogue claims an endpoint and an initial delay. This measures both.\n\n'

while IFS=$'\t' read -r name image port path delay; do
  [[ -z "$name" ]] && continue

  container="nixhome-probe-$name-$$"
  printf -- '-- %s (%s:%s)\n' "$name" "$image" "$tag"

  if ! "$runtime" run -d --rm --name "$container" -P "$image:$tag" >/dev/null 2>&1; then
    printf '   FAIL could not start %s:%s\n\n' "$image" "$tag"
    status=1
    continue
  fi

  # shellcheck disable=SC2064
  trap "$runtime rm -f '$container' >/dev/null 2>&1 || true" EXIT

  hostport="$("$runtime" port "$container" "$port" 2>/dev/null | head -1 | sed 's/.*://')"
  if [[ -z "$hostport" ]]; then
    printf '   FAIL the container published no port for %s -- the catalogue port may be wrong\n\n' "$port"
    "$runtime" rm -f "$container" >/dev/null 2>&1 || true
    status=1
    continue
  fi

  start=$(date +%s)
  observed=""
  while (( $(date +%s) - start < timeout )); do
    if [[ "$path" == "-" ]]; then
      # A TCP connect, which is what the catalogue claims for an application with no cheap health
      # endpoint. Weaker than an HTTP probe and honestly so.
      if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$hostport" 2>/dev/null; then
        observed=$(( $(date +%s) - start )); break
      fi
    else
      if curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:$hostport$path" 2>/dev/null; then
        observed=$(( $(date +%s) - start )); break
      fi
    fi
    sleep 1
  done

  if [[ -z "$observed" ]]; then
    printf '   FAIL never answered %s within %ss. Either the endpoint moved or the budget is wrong.\n' \
      "${path/-/a TCP connect}" "$timeout"
    status=1
  else
    printf '   ok   answered after %ss (catalogue initialDelaySeconds = %s)\n' "$observed" "$delay"
    if (( observed > delay + 30 )); then
      printf '   NOTE it took %ss longer than the declared delay. The failure budget absorbs that today;\n' \
        "$(( observed - delay ))"
      printf '        if the gap keeps growing, the delay in lib/trackers.nix is the number to revisit.\n'
    fi
  fi

  "$runtime" rm -f "$container" >/dev/null 2>&1 || true
  trap - EXIT
  echo
done <<<"$rows"

if [[ $status -eq 0 ]]; then
  echo "Every catalogued application started cold and answered its declared readiness endpoint."
else
  echo "One or more applications did not -- see FAIL lines above." >&2
  exit 1
fi
