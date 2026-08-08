# Asserts the catalogue's own integrity, and turns the two rules its header argues in prose into
# things a machine refuses: the DOMAIN split and the NAMING rule.
#
# Here for the reason every sibling states for its own version of this file: `nix flake check` does
# not evaluate a repository's module outputs on its own, so a green check without it would prove
# nothing but flake syntax.
#
# ── WHAT IT PROVES ─────────────────────────────────────────────────────────────────────────────
#
#   - THE NAMING RULE, mechanically: no domain name is the name of an application inside it. A
#     group named after one of its members reads as though that member were the group's definition,
#     which is exactly how the next candidate gets filed by resemblance instead of by the rule.
#     ../modules/cluster.nix refuses a NAMESPACE value that collides the same way; this is the half
#     that has to hold at the catalogue level, where nobody can supply a value to fix it;
#   - the taxonomy is exactly two domains and every one of them is populated -- a domain nobody is
#     in is a word, not a category;
#   - THE OVERLAP, pinned rather than described: the two `object` trackers are exactly the two in
#     `belongings`, so the claim that they are two answers to one question stays true or this check
#     goes red;
#   - no entry carries a version anywhere, in any field, because which version a household is
#     willing to be migrated to is its own decision;
#   - the two entries that carry a trap -- the image that must run as root, the one with a scheduler
#     -- are exactly the ones the studies were written about, so a third cannot appear without
#     somebody revisiting them.
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell. Every question here is a
# question about NAMES, SHAPES and LISTS. Whether an image tag exists today, and what a cold start
# actually costs, are facts about the world that change without this repository changing -- see
# ../experiments/probe-readiness.sh.
{ pkgs, lib ? pkgs.lib }:
let
  catalogue = import ../lib/trackers.nix { };

  trackers = catalogue.trackers;
  companions = catalogue.companions;

  trackerNames = lib.attrNames trackers;
  companionNames = lib.attrNames companions;
  allNames = trackerNames ++ companionNames;

  trackerEntries = lib.attrValues trackers;
  companionEntries = lib.attrValues companions;
  allEntries = trackerEntries ++ companionEntries;

  domains = lib.unique (map (e: e.domain) trackerEntries);
  units = lib.unique (map (e: e.unit) trackerEntries);

  inDomain = d: lib.attrNames (lib.filterAttrs (_: e: e.domain == d) trackers);
  withUnit = u: lib.attrNames (lib.filterAttrs (_: e: e.unit == u) trackers);

  sorted = lib.sort (a: b: a < b);

  isPath = s: lib.isString s && lib.hasPrefix "/" s;
  isName = s: lib.isString s && s != "";

  # Every timing field, so a probe cannot be half-specified. `path` is checked separately because
  # null is a legitimate and meaningful value there.
  probeFields = [ "initialDelaySeconds" "periodSeconds" "timeoutSeconds" "failureThreshold" ];

  results = {
    # ── THE NAMING RULE ───────────────────────────────────────────────────────────────────────
    "no domain is named after an application inside it, in either group" =
      lib.intersectLists domains allNames == [ ];

    "and no unit is either -- the same trap one level down" =
      lib.intersectLists units allNames == [ ];

    "a companion never shares a name with a tracker, so one key is one workload" =
      lib.intersectLists trackerNames companionNames == [ ];

    # ── THE TAXONOMY ──────────────────────────────────────────────────────────────────────────
    "the taxonomy is exactly two domains" =
      sorted domains == [ "belongings" "housekeeping" ];

    "both domains are populated -- a domain nobody is in is a word, not a category" =
      lib.all (d: inDomain d != [ ]) domains;

    "every tracker names one of them, and nothing else" =
      lib.all (e: lib.elem e.domain domains) trackerEntries;

    # ── THE OVERLAP, PINNED ───────────────────────────────────────────────────────────────────
    # The claim this repository makes out loud is that the two `object` trackers are two answers to
    # ONE question while the `product` tracker overlaps them only on the English word "inventory".
    # That claim is only worth making if it stays true.
    "the units are exactly the three the catalogue argues for" =
      sorted units == [ "object" "product" "task" ];

    "the two `object` trackers are exactly the two in `belongings`" =
      sorted (withUnit "object") == sorted (inDomain "belongings");

    "a quantity that depletes and an obligation that recurs are both `housekeeping`" =
      sorted (withUnit "product" ++ withUnit "task") == sorted (inDomain "housekeeping");

    "no two trackers in one domain share a unit except the pair the overlap study is about" =
      lib.length (withUnit "product") == 1 && lib.length (withUnit "task") == 1;

    # ── NO VERSIONS ANYWHERE ──────────────────────────────────────────────────────────────────
    # A catalogue entry is a KIND of application, not a copy of one. Two of these migrate their own
    # schema on start, so the version is the household's decision and is required, defaultless, on
    # every declaration instead.
    "no entry carries a version field" =
      lib.all (e: !(e ? version)) allEntries;

    "every image is a repository with no tag -- a tag here would be a second pin nothing keeps honest" =
      lib.all (e: isName e.image && !(lib.hasInfix ":" e.image)) allEntries;

    # ── EVERY ENTRY IS COMPLETE ───────────────────────────────────────────────────────────────
    "every entry names at least one port, and its primary is one of them" =
      lib.all (e: e.ports != { } && (e.ports ? ${e.primaryPort})) allEntries;

    "every port is a real port number" =
      lib.all (e: lib.all (p: p > 0 && p < 65536) (lib.attrValues e.ports)) allEntries;

    "every entry writes at least one directory, and every one of them is an absolute container path" =
      lib.all (e: e.state != { } && lib.all isPath (lib.attrValues e.state)) allEntries;

    "every entry carries a complete readiness probe, and its path is absolute or a deliberate null" =
      lib.all
        (e: lib.all (f: e.readiness ? ${f} && e.readiness.${f} >= 0) probeFields
          && e.readiness.failureThreshold > 0
          && (e.readiness.path == null || isPath e.readiness.path))
        allEntries;

    "every entry says what it does when nobody is looking -- null is a claim, never a blank" =
      lib.all (e: e ? background && (e.background == null || isName e.background)) allEntries;

    "every entry names an identity model or an explicit null, and never a UID" =
      lib.all
        (e: e ? identity
          && (e.identity == null || lib.elem e.identity [ "root" "puid" "runAsUser" ]))
        allEntries;

    "every entry lists the credential variables it cannot be correct without, even when that list is empty" =
      lib.all
        (e: lib.isList e.requiredSecretEnv
          && lib.all isName e.requiredSecretEnv
          && lib.unique e.requiredSecretEnv == e.requiredSecretEnv)
        allEntries;

    "every entry explains itself" =
      lib.all (e: isName e.note) allEntries;

    # ── THE TRAPS, BY NAME ────────────────────────────────────────────────────────────────────
    # Both are written up in ../studies/. Pinned by name rather than by a count, so a third entry
    # with either property cannot arrive without the study being revisited.
    "exactly one image must run as root, and it is the asset tracker" =
      lib.attrNames (lib.filterAttrs (_: e: e.identity == "root") trackers) == [ "dumbassets" ];

    "exactly one application does work while nobody is looking, and it is the chore tracker" =
      lib.attrNames (lib.filterAttrs (_: e: e.background != null) trackers) == [ "donetick" ]
      && lib.all (e: e.background == null) companionEntries;

    "the two applications whose credentials do not arrive through the environment say so with an empty list" =
      trackers.donetick.requiredSecretEnv == [ ]
      && companions.barcodebuddy.requiredSecretEnv == [ ];

    # ── COMPANIONS POINT AT SOMETHING REAL ────────────────────────────────────────────────────
    "every companion serves a tracker this catalogue holds" =
      lib.all (e: trackers ? ${e.serves}) companionEntries;

    "a companion names the tracker it feeds and nothing about where to find it" =
      lib.all
        (e: !(e ? domain) && !(e ? unit) && !(e ? url) && !(e ? host) && !(e ? namespace))
        companionEntries;

    "no tracker names a companion, so the reference runs one way and a companion can be added without touching one" =
      lib.all (e: !(e ? serves) && !(e ? companion) && !(e ? companions)) trackerEntries;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixhome: catalogue-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
