# examples

Placeholder values that make this repository's checks real, and the shortest readable answer to
"what does a declaration actually look like".

- [`all/values.nix`](all/values.nix) — one complete household: both domains in two namespaces, each
  anchored by exactly one workload; an application that must run as root and takes its whole access
  model from one named Secret key, beside one that runs as a supplied UID and needs a named key of a
  very different kind; an application that reads its identity numbers from policy environment this
  repository refuses to supply; an application with two state directories, one nested inside the
  other in the layout its image ships, and a scheduler that stops while it sleeps; and a **companion**
  that keeps no record of its own, serving a tracker that idles at zero — so it has to arrive
  through the same front everything else uses, which is the one arrangement that lets both of them
  sleep.

  `nix flake check` renders it through the real app grammar and the real renderer and then asserts
  the manifests field by field, so a module that stops evaluating — or that grows a required value
  nobody supplies — fails in CI rather than in somebody's cluster.

**Nothing in here is real.** Every namespace, node path, Secret name, image reference, identity
number and slot is invented for the check. That is not a disclaimer, it is the design: every one of
those is a fleet fact, and this repository supplies none of them — see the main
[README](../README.md).

The one thing worth copying rather than replacing: the example gives each domain **its own**
namespace, because two domains resolving to one namespace is the split written down and not acted
on, and this repository refuses it. A household that likes the domain names may simply use them as
the namespace values; this file does not, only because everything in it is deliberately invented.
