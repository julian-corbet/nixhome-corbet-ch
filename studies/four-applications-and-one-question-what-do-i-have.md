# Four applications, and one question three of them answer

**Finding.** Three of the four applications this repository catalogues can be described as "it
tracks what I have", and two of those three genuinely overlap: they are two answers to one question
rather than two halves of a bigger one. The third only shares the English word. The distinction
that survives contact with the software is **what one row is** — and it is mechanical rather than
editorial, which is why it became a field (`unit`) instead of a paragraph.

**What this is based on.** The four applications' own storage and configuration as deployed: which
files each one writes, what its database holds, what it demands in its environment before it will
start, and what it serves on its port. Not their project descriptions — every one of those uses the
word "inventory", which is exactly how this question gets lost.

## The three claims, side by side

| | asset tracker | home inventory | household ERP | chore tracker |
|---|---|---|---|---|
| one row is | one physical object | one physical object | a product *type* | an obligation |
| carries a quantity | no | yes, on the row | **yes, and it moves** | no |
| carries an identity (serial, receipt) | yes | yes | no | n/a |
| carries a location | no | **yes, nested** | yes, per product | n/a |
| what makes work appear | a warranty or service date | a warranty or service date | a **threshold** and a best-before date | a **recurrence rule** |
| store | one JSON document + files | SQLite + attachment tree | SQLite + files | SQLite |
| access model | one shared PIN | accounts, API keys, a pepper | accounts | accounts, and a row belongs to a person |

## Where the real line falls

**A quantity that moves is not an inventory of objects.** The household ERP knows you hold six of
something. It does not know *which* six, there is nowhere to put a serial number, and consuming one
is a decrement rather than a deletion — the record is a level, and the level is the point. Both
object trackers do the opposite: two of the same model are two rows, because the warranty, the
receipt and the photograph belong to one of them and not the other, and the row exists to be
individually identified for years.

That is the whole overlap between the ERP and the other two, and it is a word rather than a
capability. Nothing is duplicated by running both.

**The two object trackers are the real overlap, and it is not resolvable by design.** They answer
the same question about the same objects, and the differences are of scale and access rather than
of subject:

- the asset tracker keeps everything in **one JSON document**, which is the sharpest fact about it.
  That is entirely adequate for a few dozen valuable things and is a liability at a few thousand;
  it also means the whole record is a single file, so a backup of the directory is the inventory
  and a truncated write of it is the inventory too.
- the home inventory keeps a **database with nested locations and labels**, which is what makes
  "where is it" a first-class question rather than a note field.
- the asset tracker's access model is **one shared PIN**: no accounts, so no per-person attribution
  and no read-only access for anybody. The home inventory has accounts, API keys and a pepper that
  encrypts them.

So a household running both has **two places an object can be recorded and nothing that reconciles
them**. That is not a bug to be fixed here — some households genuinely want a small, PIN-gated list
of high-value items separate from the everything-in-the-house database — but it is a decision, and
it has to be made once and written down. This repository's contribution is to make the collision
visible in the option surface rather than to pretend the two are complementary: both carry
`unit = "object"`, both sit in the `belongings` domain, and
[`../checks/catalogue-eval.nix`](../checks/catalogue-eval.nix) asserts that those two facts stay
in step, so the claim cannot quietly stop being true.

## The overlap inside the second domain, which is smaller and also real

The household ERP has a chores module, and the chore tracker is a chore tracker. Both hold recurring
obligations, both compute what is due. The differences that matter in practice:

- a chore in the ERP is attached to the household's stock world — it can consume a product, and it
  lives beside the shopping list;
- a chore in the chore tracker is attached to a **person**, and assignment is the reason the
  application exists at all. It also notifies, on its own schedule, which the ERP does not (see
  [`scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md`](scale-to-zero-is-not-free-for-an-application-with-a-scheduler.md)).

Again: two places, nothing reconciling them, and a decision to make once. Filing them in the same
domain is the honest arrangement — they are both about what comes round — and it is why the domain
is named for the *question* rather than for either application.

## What it decided here

1. **The `unit` field**, which is the only thing that separates the three "what do I have" claims
   without appealing to marketing. It is asserted rather than described: the two `object` trackers
   must be exactly the two in `belongings`, or the check fails.
2. **The two domains, and their names.** The split is between *what you keep* and *what runs out or
   comes round* — not between "assets" and "home", which are two words for the same thing and one of
   which was also the name of an application inside its own group.
3. **The refusal to name a namespace after an application in it**, enforced in
   [`../modules/cluster.nix`](../modules/cluster.nix) against the value a consumer supplies. A group
   named after one of its members reads as though that member defined the group, and the next
   candidate then gets filed by resemblance to it rather than by the rule — which is precisely how
   an asset tracker and a home inventory ended up looking like a category.
