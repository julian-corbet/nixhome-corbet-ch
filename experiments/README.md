# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
file below.

- `probe-readiness.sh` — starts every application in [`../lib/trackers.nix`](../lib/trackers.nix)
  from its catalogued image, against an empty directory, and measures how long each one takes before
  its **declared readiness endpoint** answers. Reads the names, images, ports, probe paths and
  initial delays out of the catalogue rather than a second hand-kept list.

  It answers three things no evaluation can: whether the endpoint still exists, what a genuinely
  cold first start costs (two of these applications migrate their own schema on it, which is the
  slowest start they will ever have), and — deliberately — that every one of them comes up happily
  against an empty directory and reports itself healthy. That last one is not a reassurance. It is
  the demonstration of why `hostPath` state defaults to `Directory` rather than
  `DirectoryOrCreate`: an application that finds nothing does not fail, it initialises a fresh empty
  store and then presents it as the household's inventory.

  **It has not been run from this repository.** It needs a container runtime and network access, and
  the numbers currently in the catalogue were extracted from running deployments rather than
  measured by this script. Running it is how a reader confirms them, or discovers that upstream has
  moved.

## Why this lives here and not in `checks/`

`checks/` is `nix flake check`-wired and evaluates offline. It proves everything about a shape — that
the catalogue's taxonomy holds, that no domain is named after an application inside it, that every
guard in the module fires and that the manifests come out with the right fields in them. It cannot
prove that an image's health endpoint still exists this week, or what a cold start costs on somebody
else's hardware. Those are facts about the world: they change without this repository changing, and
asserting them at evaluation time would need either network access from a pure evaluation or a
snapshot that silently goes stale.

So the split is deliberate and matches what every sibling repository does with its own verification:
eval-time checks for anything internal and deterministic, a hand-run script for anything that depends
on what upstream is shipping today.

## What is deliberately NOT verified here

**Image tags.** The catalogue names image *repositories* and no versions at all, because which
version a household is willing to be migrated to is that household's decision — and for the two
applications that migrate their own schema on start, it is the only decision in this repository that
a restart of the previous image does not undo. There is no version here to check, and checking that
a repository exists would prove nothing about the tag somebody actually deploys. The script takes a
tag as an argument for exactly that reason.

**Anything about whether an application WORKS.** The script mounts nothing, supplies no credential
and keeps nothing. It can tell you an application started; it cannot tell you it is usable, and a
green run is not a substitute for opening it.

**The identity models.** Which user an image runs as, and what it does to the directory it is given,
is written up in [`../studies/three-identity-models-across-four-images.md`](../studies/three-identity-models-across-four-images.md)
rather than probed, because the failure it causes is visible in a container's own logs and the
dangerous half — `fsGroup` recursively chowning a host directory — cannot be tested anywhere it
would be safe to test it.

If something in here turns out to matter in a different way, distil the actual finding into
[`../studies/`](../studies/README.md) and let the experiment stay disposable (or delete it).

See the main [README](../README.md) for the project itself.
