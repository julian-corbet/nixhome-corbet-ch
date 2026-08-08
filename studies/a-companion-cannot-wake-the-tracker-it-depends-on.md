# A companion cannot wake the tracker it depends on

**Finding.** When a workload idles at zero replicas behind an HTTP wake front, that front stands in
front of **the address the outside world uses** — not in front of the in-cluster Service. Anything
inside the cluster that dials the Service directly therefore reaches a Deployment with no pods: the
request fails, nothing wakes, and both workloads report perfectly healthy. The fix is not to keep
the tracker awake. It is to make the dependent workload arrive the same way everybody else does,
which lets **both** of them sleep.

**What this is based on.** The routing of a scale-to-zero HTTP add-on: an interceptor is selected by
the **host** on the request, holds the request while the scaler brings the Deployment from zero, and
then forwards it. The in-cluster Service of the sleeping workload participates in none of that — it
is the forward target, not the entry point.

## The arrangement that looks obviously right

A barcode companion sits beside a household ERP. A scan arrives, the companion looks the product up,
and it calls the ERP's HTTP API to add or remove stock. Both are in one namespace, so the companion
is configured with the ERP's in-cluster name. Short path, no round trip out of the cluster, no
dependency on anything external. It is the arrangement anybody would write first.

Then the ERP is allowed to idle at zero, because it is a household application that nobody opens for
days at a time and idling it back is most of the reason to run a wake front at all.

## What happens next

```
scan → companion → ERP Service → (no endpoints)
```

The Service exists. Its selector matches nothing, because the Deployment is at zero. The connection
is refused or hangs, the companion reports a failed sync, and **nothing anywhere wakes the ERP** —
the scaler never saw a request, because the request never passed the interceptor that would have
told it about one.

Three things make this expensive rather than merely broken:

1. **Both workloads are healthy.** The companion is running and answering its own port. The ERP is
   correctly asleep. Every probe passes and every Application is green.
2. **The failure is silent at the point that matters.** A scan is a fire-and-forget action from a
   phone or a hand scanner; nobody is watching a response code. The stock is simply never updated.
3. **It looks like an authentication problem.** The companion holds an API key for the ERP, so the
   first hypothesis is the key, and the key is fine.

## The fix, and why it is better than the obvious one

The obvious fix is to take the ERP off scale-to-zero. It works, and it gives up the thing the wake
front was for.

The fix that keeps both: **point the companion at the same address everything else uses**, so its
request traverses the interceptor exactly like a browser's would. The scan then *is* the wake:

```
scan → companion → the front → interceptor → ERP 0→1 → the request is forwarded
```

Both workloads can now idle at zero. The companion sleeps until a scan arrives; the scan wakes the
companion; the companion's API call wakes the ERP. The dependency stopped being a reason to keep
anything running.

The cost is one round trip out of the cluster and back for each scan, which for a household scanning
groceries is not a number anybody will ever notice.

## What it decided here

**`nixhome.companions.<name>.reaches`**, an enum of `in-cluster` and `front`, and the assertion that
refuses `in-cluster` when the tracker it serves is declared `scale-to-zero` — naming both workloads
and saying what to set instead.

Two things about that option are worth stating, because they look like weaknesses and are not:

- **It renders nothing.** The URL lives inside the companion's own configuration, on its state
  directory, where somebody typed it into a form. This repository cannot see that value and would
  not carry it if it could. The option exists so that the fact becomes *declarable* and therefore
  checkable at all — the alternative is a comment nobody reads next to a form nobody re-opens.
- **The default is the broken one.** `in-cluster` is the default because it is the right answer
  whenever the tracker is always running, and because it can no longer be the wrong answer silently:
  the exact combination that fails is the exact combination that is refused at evaluation.
