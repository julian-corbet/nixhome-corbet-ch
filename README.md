# nixhome

**The self-hosted applications that run a household, declared: what you own, what you have to
restock, and what has to get done — with the knowledge that makes each one actually run.**

It renders no Kubernetes object of its own. Everything expressible as an app is expressed in
[nixk3s](https://github.com/julian-corbet/nixk3s-corbet-ch)'s app grammar; what this repository adds
is the one thing that grammar cannot know — what a household application *is*.

## Two domains, and the rule that separates them

A household record is one of two things, and which one is a property of the software rather than a
preference:

> **`belongings`** — the record names a **thing you keep**: one durable object with its own
> identity, answering where it is, what it cost, and when its warranty or its next service falls
> due. Rows are created once and deleted once, and nothing about a belonging is a quantity.
>
> **`housekeeping`** — the record names something that **runs out or comes round**: a quantity that
> depletes and has to be restocked, or an obligation that recurs on a schedule. The row is not the
> point; the level and the date are, and both move without anybody editing anything.

**The tell, when a candidate looks like both: does the record get consumed?** A drill is a
belonging. The drill bits you use up are stock. "Sharpen the bits every spring" is a chore. Same
shelf, three different records, and only the first is still there in five years with the same
identity.

The split is **load-bearing, not decorative**: a workload's namespace comes from its domain, so the
distinction decides where things land instead of merely describing them. And **neither domain is
named after an application inside it** — that is a rule, enforced twice. No domain name may be a
catalogue key (`checks/catalogue-eval.nix`), and no *namespace value a consumer supplies* may be
one either (`modules/cluster.nix` refuses it). A group named after one of its members reads as
though that member were the group's definition, and the next candidate then gets filed by
resemblance to it rather than by the rule.

## What this is

A catalogue in two groups and one option namespace, `nixhome`, like every repository in this family.

**[`lib/trackers.nix`](lib/trackers.nix)** — what a household runs, in two groups because the subject
genuinely contains two kinds of workload. `trackers` are applications whose product **is** a record
that outlives every session with it, and which are authoritative for whatever they record.
`companions` exist only to **feed** a tracker: they keep no record of their own, everything they do
becomes a change in somebody else's database, and turning one off loses a way of writing rather than
anything written.

Each entry carries the application's own knowledge: which port it listens on, which directories it
writes and what is lost when one of them is not mounted, how long its schema migration takes before
a probe means anything, which environment variables carry a credential it cannot start without,
which identity model its image implements, and **what it does when nobody is looking**.

```nix
# Composed into a nixidy environment ALONGSIDE nixk3s's app grammar.
# Every value below is a fleet fact the consumer supplies; this repository ships none of them.
nixhome.homePlatform = {
  namespaces = { belongings = "…"; housekeeping = "…"; };  # one per domain, no defaults
  project = "…";
  origin = "nixhome";                                      # hands the slots to the band model
};

nixhome.trackers = {
  things   = { tracker = "dumbassets"; version = "…"; slot = N;
               state.data.hostPath = "…";                       # where inside the container is ours
               secretEnv.DUMBASSETS_PIN = { secret = "…"; key = "…"; }; };  # by name, never by value
  stuff    = { tracker = "homebox";  version = "…"; slot = N + 1; … };
  supplies = { tracker = "grocy";    version = "…"; slot = N + 2; scaling = "scale-to-zero"; … };
  jobs     = { tracker = "donetick"; version = "…"; slot = N + 3;
               state = { config.hostPath = "…"; data.hostPath = "…"; }; };  # two, and both are needed
};

# No record of its own. Its tracker idles at zero, so it must arrive through the same front
# everything else uses — the in-cluster route is refused at eval, because it would wake nothing.
nixhome.companions.scanner = {
  companion = "barcodebuddy"; serves = "supplies"; version = "…"; slot = N + 4;
  reaches = "front";
};
```

## Four applications, three of which answer one question

Stated plainly rather than papered over, because a reader will notice it in the first minute: an
asset tracker, a home inventory and a household ERP with stock management **all** claim to track
what you have. Two of them genuinely overlap.

The distinction that survives contact with the software is **what one row is**, and it is a field
(`unit`) rather than a paragraph:

| `unit` | one row is | in domain |
|---|---|---|
| `object` | one physical thing, identified individually and kept. Two of the same model are two rows, because the warranty and the receipt belong to one of them. | `belongings` |
| `product` | a **type**, carrying a quantity. The record knows you hold six; it does not know which six, and there is nowhere to put a serial number. | `housekeeping` |
| `task` | an obligation with a recurrence rule and no physical referent at all — what is stored is when it is next due and who owes it. | `housekeeping` |

So the honest summary is one sentence instead of three vague ones. **The two `object` trackers are
two answers to one question**: a household running both has two places an object can be recorded and
nothing that reconciles them, which is a decision to make once and write down rather than a bug —
some households really do want a small PIN-gated list of valuables separate from the
everything-in-the-house database. **The household ERP overlaps them only on the English word
"inventory"**, because a quantity that moves is not an inventory of objects.

The option surface makes that visible instead of hiding it, and
[`checks/catalogue-eval.nix`](checks/catalogue-eval.nix) asserts that the two `object` trackers are
exactly the two in `belongings` — so the claim cannot quietly stop being true. Full reasoning, with
the evidence:
[`studies/four-applications-and-one-question-what-do-i-have.md`](studies/four-applications-and-one-question-what-do-i-have.md).

## It consumes the app grammar; it does not reimplement Kubernetes

`modules/cluster.nix` **defines into `nixk3s.apps`** and renders nothing itself. Each application
declares an image, ports, state, secrets, an exposure class and a scaling class in the grammar's own
vocabulary, and the grammar renders the Application, the Namespace, the Deployment and the Service.
Import the grammar alongside this module — it is a hard requirement, and a version of this module
that quietly rendered its own Deployments when the grammar was absent would be the second
implementation this repository exists to not have.

**There is no second route out of it here**, and that is worth stating because a sibling repository
in this family has one: a database tier has to deliver an operator's vendor chart and a custom
resource whose schema belongs to somebody else's API version, so it renders those one level below
the grammar and counts them. Nothing in a household is shaped like that — four applications and a
companion, each an image with a port and a directory. **The untyped surface here is empty, and
`checks/cluster-eval.nix` asserts that it stays empty.**

Neither flake is an input of the other for a consumer. `nixk3s` and `nixidy` are **checks-only**
inputs here, so `nix flake check` can render this module through the real grammar and assert the
manifests that come out — rather than asserting that a module which merely mentions `nixk3s.apps`
evaluates.

## Scale-to-zero, and what it actually costs

A household application is opened for a few minutes a day, so idling it at zero replicas is most of
the reason to run a wake front at all. It is **lossless** for an application that computes everything
in answer to a request, and **lossy in an invisible way** for one that does work on a timer: the
reminders are not late, the interval never happened, and the first thing that runs after a wake is a
fresh evaluation of what is due *now*.

That is knowledge about the application rather than a preference, so the catalogue carries it
(`background`), the module **warns naming exactly what stops**, and `nixhome.dormantWhileAsleep` is
a countable list of the workloads it applies to — because every entry on it is a household deciding
that a reminder arriving on the next visit is good enough, and a decision like that should be in one
place rather than reconstructed from four declarations.
[`studies/scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md`](studies/scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md)

**Its second-order consequence is refused rather than warned about.** A wake front stands in front of
the address the outside world uses, never in front of the in-cluster Service — so a companion that
dials the Service of a sleeping tracker reaches a Deployment with no pods, nothing wakes, and the
write is lost while both workloads report healthy. Pointing the companion at the same front
everybody else uses fixes it completely and lets **both** idle at zero, which is why
`companions.<name>.reaches` exists and why the broken combination fails eval by name.
[`studies/a-companion-cannot-wake-the-tracker-it-depends-on.md`](studies/a-companion-cannot-wake-the-tracker-it-depends-on.md)

## Three identity models across four images

They implement three different answers to "which user does this run as, and who owns the directory
it writes" — one that **must** be root (it writes into its own application directory at startup and a
non-root UID crash-loops), one that reads a UID pair from its environment and chowns for you, and two
that run as whatever they are given and chown nothing, so the directory must already be right.

Each wrong answer fails differently and none of them looks like an identity problem when you meet
it. The catalogue records the model (`identity`) and **never the number**: which UID a household uses
is a value. Plus the rule common to all three — `fsGroup` on node-path state recursively chowns the
host directory itself, which is somebody's curated filesystem rather than a scratch volume.
[`studies/three-identity-models-across-four-images.md`](studies/three-identity-models-across-four-images.md)

## What belongs here, and what does not

The placement rule, stated in [`lib/trackers.nix`](lib/trackers.nix)'s own header so the next
candidate is decidable rather than argued:

> Does the thing keep the household's own record — what is owned, what is held, what is due — or
> feed something that does? Yes → here. No → whichever repository owns the thing it actually is.

**"A person uses it at home" is not the test**, and that clause matters more than it looks: almost
every self-hosted application is used at home, and if location were the test this catalogue would
swallow the whole application layer. A dashboard that links to these four is a page of links; a
note-taker that happens to hold a shopping list is a note-taker. The test is whether the application
**is the household's record** of something.

**Not the application cookbook's.** [nixapps](https://github.com/julian-corbet/nixapps-corbet-ch)
describes *ordinary* self-hosted applications — independent recipes, each complete on its own, paired
with a short values file. These four are not four independent recipes: they are one subsystem with a
shared domain model, a namespace that follows from what an application records, and a dependency
between two of them that has to be governed rather than documented. That is the difference, and it
is the same difference that took the database tier out of the cookbook.

**Also not here: capacity of any kind.** Replica counts, resource requests and limits, storage sizes,
node selectors. Those are decisions about one site's hardware, and this repository supplies what
software needs in order to be *correct*, never what it needs in order to be the right *size*. `env`
is where a consumer merges its own tuning — and its own policy — in.

**And no host plane at all.** There are no `nixosModules` here and no packages claimed from any
host's catalogue, which is a statement rather than a gap: a household's record lives in a cluster and
is read through a browser, so there is no command line to install on a workstation.

## Public mechanism, private layout

**No address, no slot number, no namespace value, no node path, no UID and no hostname appears
anywhere in this repository.** Every one of those is a fleet fact and is a parameter the consumer
supplies.

`nixhome.homePlatform.namespaces` has **no default for any domain**, and evaluation fails naming the
option the moment a workload of that domain is declared: what a cluster calls its household
namespaces is a value, and a default would be this repository deciding it. That there are two
domains, split that way, is knowledge and is not negotiable here — which words a cluster uses for
them is not, though a household that likes the domain names may simply reuse them.

The slots this module governs are checked for collisions inside the household and for nothing else.
Which **range** they may come from is a different question, answered by nixk3s's band model;
`nixhome.homePlatform.origin` is the one switch that hands them to it, and which band that origin
binds is fleet layout that lives in the repository owning the fleet.

What is public is the mechanism: the catalogue, the knowledge in it, the render, and the guards.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | `nixidyModules`, `lib.*`, `checks`. No `nixosModules` — see above. |
| `lib/trackers.nix` | The catalogue: four trackers and one companion, the two domains, and the knowledge that makes each one run. |
| `modules/cluster.nix` | The surface: translates declarations into `nixk3s.apps`, resolves each workload's namespace from its domain, and governs the companion relationship. |
| `checks/` | Three checks that really evaluate — see below. |
| `examples/all/values.nix` | Placeholder values that make the render check real. Nothing in it is a real fleet fact. |
| `experiments/probe-readiness.sh` | Cold-start measurement against the catalogued images, hand-run. |
| `studies/` | Written-up findings that changed a decision here. |

## Checks

`nix flake check` runs three, and none of them is syntax-only.

**`catalogue-eval`** asserts the catalogue's integrity and turns the two rules its header argues in
prose into things a machine refuses: that no domain — and no unit — is named after an application
inside it; that the taxonomy is exactly two domains and both are populated; that the two `object`
trackers are exactly the two in `belongings`, so the overlap claim stays true; that no entry carries
a version in any field and every image is a repository with no tag; that every entry names a
complete probe, says what it does when nobody is looking (a `null` is a claim, never a blank), and
names an identity model or an explicit null; and that the two entries carrying a trap — the image
that must run as root, the one with a scheduler — are exactly the ones the studies were written
about, so a third cannot appear without somebody revisiting them.

**`cluster-eval`** renders the module through the real grammar and the real renderer, in both
directions. An empty household defines no app at all and raises no assertion of its own; a declared
one's whole contribution is exactly its workloads and **every one of them went through the grammar**;
the domain decides the namespace and a companion inherits its tracker's; the catalogue's knowledge
reaches the grammar (image, port, mount path, probe shape and timing, the environment an application
needs to be correct, policy merged over it); a credential is a reference and no liveness probe is
ever synthesized. Then eleven declarations that must each be **refused** — an unbacked directory,
state with neither or both backings, a required credential variable nobody supplied, a companion
serving nothing, a companion serving the wrong application, a companion reaching a sleeping tracker
in-cluster, two workloads on one slot, two workloads creating one namespace, a namespace named after
an application inside it, two domains in one namespace — against a control that must render. Two
have their *message* asserted by content, because `tryEval` can only say *that* something was
refused. And each refusal must come from **this module's own guard**: a `tryEval` that caught a type
error or a typo in the fixture looks exactly like a guard firing, and would let every case pass while
nothing was being checked.

**`cluster-render`** parses the manifests actually produced and asserts them field by field, because
a module that type-checks can still render an application whose Service targets a port nothing
listens on, or whose store is mounted somewhere it does not write — and *that* one presents an empty
inventory as the household's record. Among others: the mount path is the *catalogue's* and the
backing is the *declaration's*; state forces `Recreate`, never a rolling update; the credential is a
`secretKeyRef` and no Secret object is ever rendered; the two-directory application gets both, at the
paths its own image expects; an always-on workload owns its replica count and a sleeping one renders
none; every created Namespace carries the annotation that stops it being cascade-deleted; and no
Service carries a pinned address, an external IP or a node port.

## Status

**Pre-alpha.** The catalogue's knowledge is extracted from a deployment that runs all five workloads
— two `belongings` trackers, a household ERP, a chore tracker and the ERP's barcode companion — but
this repository has not yet replaced that deployment's own declarations, and the four applications
still have independent recipes in the application cookbook. This is where they are going; the
cookbook keeps the ordinary applications that merely happen to be used at home.

The domain model, the guards and the render are complete and checked. What is not yet done is a
second household using it, which is the only thing that finds out whether the two domains hold for
anybody else's four applications.

## Related projects

Part of the same independently-usable module family:
[nixk3s](https://github.com/julian-corbet/nixk3s-corbet-ch) (the app grammar this consumes, and the
band model its slots answer to),
[nixapps](https://github.com/julian-corbet/nixapps-corbet-ch) (the cookbook of ordinary self-hosted
applications, where an application that is not a household record belongs), and
[nixdb](https://github.com/julian-corbet/nixdb-corbet-ch) (the database tier — none of the
applications here needs it, which is most of why they suit a household: every one of them keeps its
own store in a directory).

## License

MIT License &copy; 2026 Julian Corbet
