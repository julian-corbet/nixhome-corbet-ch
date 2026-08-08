# Three identity models across four images, and one rule that applies to all of them

**Finding.** The four applications this repository catalogues implement **three different answers**
to "which user does this run as, and who owns the directory it writes". Getting the answer wrong
produces one of three failures — a crash loop before the first request, an application that starts
and cannot write, or a host directory silently rechowned out from under everything else that uses
it. None of the three looks like an identity problem when you meet it.

**What this is based on.** What each image does at startup with the directory it is given, and what
each one does when it is given a UID it did not expect.

## The three models

**`root` — the image must run as root.** The asset tracker writes into its own application directory
at startup, not only into the directory it was given. A non-root UID gets `EACCES` there and the
container exits before it serves anything, so this presents as a crash loop with a permissions error
in a path nobody mounted. Its data directory has to be owned to match, which makes it the one entry
here that does not fit a household's ordinary "everything runs as one unprivileged person" rule.

**`puid` — the image reads a UID and a GID from its environment.** The household ERP's image starts
as root, chowns the directory it was given to the pair it was told about, and drops. Two consequences
worth having in advance: the directory does **not** need to be correctly owned beforehand, and the
process does **not** stay root, so neither of the failures above applies. The numbers are values and
belong to whoever declares the workload.

**`runAsUser` — the image runs as whatever it is given and chowns nothing.** Both remaining
applications behave this way, and this is the model that fails quietly. Give it a UID that does not
own the directory and it starts perfectly well; the failure arrives when it opens its database, and
for an application whose database is the point that is a startup error about SQLite rather than
about permissions. The directory has to be right **before** the first start.

## The rule that applies to all three

**Never set `fsGroup` on node-path state.** It is the obvious fix for the third model — it makes the
volume group-writable by the pod — and on a hostPath backing it **recursively chowns the host
directory itself**. That directory is not a scratch volume: it is a curated filesystem that other
things read, that is snapshotted, and that has an ownership model of its own. The chown is applied
on every pod start, it is not undone, and it succeeds silently.

So the correct order of operations for the third model is to own the directory correctly once, out
of band, and never to reach for the option that appears to solve it from inside the pod.

## What it decided here

1. **The `identity` field** on every catalogue entry, with the three values above — because "runs as
   root" is knowledge about an image in the same way a port number is, and because a reader
   comparing four entries should be able to see that they are not the same and why.
2. **That the field never carries a number.** Which UID a household uses is a value; that an image
   *reads* one from its environment is knowledge. The ERP's numbers arrive through the declaration's
   own `env`, alongside the rest of that household's policy.
3. **That `null` is allowed and means "not established here".** One entry in the catalogue carries
   it. A guess in this field is worth less than an admission: a wrong one produces either a crash
   loop or an unwritable directory, and both look like something else entirely.
   [`../checks/catalogue-eval.nix`](../checks/catalogue-eval.nix) asserts that exactly one image
   requires root and that it is the one this study is about, so a second cannot arrive without
   somebody reading this.
