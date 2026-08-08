# studies

Written-up findings: things that were worked out while building this repository, turned out to
matter, and are worth recording properly — with the reasoning, not just the result.

A study earns its place here once it changed a decision in the main project. See the main
[README](../README.md) for the project itself.

| File | Finding |
|---|---|
| `four-applications-and-one-question-what-do-i-have.md` | Three of the four applications here can be described as "it tracks what I have", and the description is what hides the difference. The distinction that survives contact with the software is **what one row is**: one physical object, a product type carrying a quantity that moves, or an obligation with a recurrence rule. That reduces the overlap to one honest statement — the two object trackers really are two answers to one question and running both means deciding which is authoritative, while the household ERP shares only the English word "inventory". Decided the `unit` field, the two domain names, and the refusal to name a namespace after an application inside it. |
| `a-companion-cannot-wake-the-tracker-it-depends-on.md` | A wake front stands in front of the address the outside world uses, never in front of the in-cluster Service — so a workload that dials the Service of a tracker idling at zero reaches a Deployment with no pods, nothing wakes, and both workloads report healthy while the write is lost. Pointing the dependent workload at the same front everybody else uses fixes it completely and lets **both** idle at zero. Decided `nixhome.companions.<name>.reaches` and the assertion that refuses the broken combination by name. |
| `scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md` | Idling at zero is lossless for an application that computes everything in answer to a request, and lossy in an invisible way for one that does work on a timer: the reminders are not late, the interval never happened. Three of the four here are request/response by construction; one runs a scheduler and a realtime channel. Decided the `background` field, the warning that quotes it, and the countable `nixhome.dormantWhileAsleep` report. |
| `three-identity-models-across-four-images.md` | Four images, three different answers to "which user does this run as and who owns its directory" — one that must be root, one that reads a UID pair from its environment and chowns for you, and two that run as whatever they are given and chown nothing. Each wrong answer fails differently and none of them looks like an identity problem. Plus the rule common to all of them: `fsGroup` on node-path state recursively chowns the host directory. Decided the `identity` field, that it never carries a number, and that `null` in it is an admission rather than a to-do. |
