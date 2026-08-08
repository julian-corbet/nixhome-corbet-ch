# Scale-to-zero is not free for an application with a scheduler

**Finding.** Idling a workload at zero replicas is lossless for an application that computes
everything in answer to a request, and lossy in a specific and invisible way for one that does work
on a timer. The reminders are not late. They are **never evaluated** — the interval simply did not
happen — and the first thing that runs after a wake is a fresh evaluation of what is due *now*.

For a household that is frequently the right trade. It is a terrible one to make by accident, which
is the whole reason this repository carries a `background` field instead of leaving scale-to-zero as
a uniform switch.

**What this is based on.** Which of the catalogued applications runs a timed loop at all. Three of
them are request/response by construction — one is a PHP application behind a web server, which has
no process to run a timer in between requests, and the other two compute their due dates as queries
when a page is asked for. One runs a scheduler for due, pre-due and overdue reminders and holds a
realtime channel open for clients that are watching.

## The shape of the loss

An always-on chore tracker fires a reminder at the moment a chore falls due — a message, a
notification, whatever it is wired to.

The same tracker at zero replicas:

- at the moment the chore falls due, **there is no process**. Nothing is queued and nothing is
  retried, because nothing observed the moment.
- the next HTTP request wakes the pod. The scheduler starts, evaluates what is due, and finds the
  chore — now overdue.
- so the reminder arrives **when somebody next opens the application**, which is precisely the
  moment they did not need reminding.

The realtime channel behaves the same way from the other end: a client that was connected is
disconnected when the pod goes, reconnects on the next wake, and has no record of what it missed in
between.

None of this shows up anywhere. There is no failed sync, no error in a log, no restart. The
application is doing exactly what it was told.

## Why the answer is a warning and not a refusal

Because for most households it really is fine, and a repository that refused it would be making a
decision that belongs to the household:

- the chores are still correct — nothing is lost from the record, only from the *notification*;
- the wake is cheap and the application is opened often enough that "overdue" is a useful state
  rather than a missed one;
- and the alternative costs a permanently resident process for an application used a few minutes a
  day, which is exactly the cost scale-to-zero exists to avoid.

What is not acceptable is discovering it from a reminder that never arrived. So the module says so
at render time, naming what specifically stops:

> `chores` scales to zero, and while it is at zero it is not running a reminder scheduler (due,
> pre-due and overdue) and a realtime channel that pushes changes to open clients.

## The second-order case, which is not a warning

An application that idles at zero also cannot be woken by anything inside the cluster, which is a
separate finding with a separate consequence and is refused rather than warned about — see
[`a-companion-cannot-wake-the-tracker-it-depends-on.md`](a-companion-cannot-wake-the-tracker-it-depends-on.md).

## What it decided here

1. **The `background` field** on every catalogue entry: what the application does when nobody is
   looking, or `null` when everything it computes is computed in answer to a request. A `null` is a
   claim rather than a blank, and [`../checks/catalogue-eval.nix`](../checks/catalogue-eval.nix)
   requires every entry to make one.
2. **The warning**, which quotes the field rather than saying "this may not work" — a warning that
   does not name what stops is a warning people turn off.
3. **`nixhome.dormantWhileAsleep`**, a read-only list of exactly the workloads that idle at zero
   *and* have work that only happens while they are running. The point of it is that it is
   countable: every entry on it is a household deciding that a reminder arriving on the next visit
   is good enough, and a decision like that should be visible in one place rather than reconstructed
   from four declarations.
