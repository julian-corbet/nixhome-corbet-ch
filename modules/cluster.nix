#
# nixhome's surface: declare what the household runs, and render it.
#
# ── THIS MODULE DOES NOT IMPLEMENT KUBERNETES, AND THAT IS THE WHOLE DESIGN ─────────────────────
#
# There is a sibling repository whose entire subject is the app grammar -- an app declares WHAT IT
# NEEDS (an image, ports, an exposure class, whether it scales to zero, which existing claims or
# node paths hold its state, which existing Secrets it consumes) and that grammar renders the Argo
# CD Application, the Namespace, the Deployment and the Service. Everything this module can express
# in those terms is expressed in them: it DEFINES INTO `nixk3s.apps` and renders no Kubernetes
# object of its own.
#
# THERE IS NO SECOND ROUTE OUT OF IT HERE, and that is worth stating because a sibling repository
# in this family has one. A database tier has to deliver an operator's vendor chart and a custom
# resource whose schema belongs to somebody else's API version, so it renders those one level below
# the grammar and counts them. Nothing in a household is shaped like that: four applications and a
# companion, each an image with a port and a directory. So every workload this module declares goes
# through the grammar in full, the untyped surface is empty, and ../checks/cluster-eval.nix asserts
# that it stays empty.
#
# IMPORT THE GRAMMAR ALONGSIDE THIS MODULE. `nixk3s.apps` is declared there, not here, and a render
# that composes this module without it fails with "the option `nixk3s.apps' does not exist". That
# is a hard requirement rather than an optional integration: a version of this module that quietly
# rendered its own Deployments when the grammar was absent would be the second implementation this
# repository exists to not have.
#
# The grammar is NOT a flake input here, for the reason the sibling catalogues state for
# themselves: this repository is options plus a catalogue, taking `config`/`lib` from whichever
# evaluation composes it, so composing it can never add another flake's whole input closure to a
# consumer's. The input exists for `nix flake check` alone, which renders this module through the
# real grammar and asserts the manifests that come out.
#
# ── WHAT THIS MODULE ADDS ──────────────────────────────────────────────────────────────────────
#
# The one thing the grammar cannot know: what a household application IS. Which port it listens on,
# which directories it writes and what is lost when one of them is not mounted, how long its schema
# migration takes before a probe means anything, which environment variables carry a credential it
# cannot start without, what it does when nobody is looking -- and, for the one workload that is
# not authoritative for anything, which tracker it feeds and how it must reach it.
#
# ── THE DOMAIN DECIDES THE NAMESPACE ───────────────────────────────────────────────────────────
#
# Every tracker in the catalogue names a `domain` -- `belongings` for the record of what is owned,
# `housekeeping` for the record of what runs out and what comes round. A companion inherits the
# domain of the tracker it serves, because a companion belongs beside the thing it writes to.
#
# That is not a label. A workload's NAMESPACE comes from its domain: this module declares one
# namespace option per domain the catalogue contains, with NO DEFAULT, and evaluation fails naming
# the option the moment a workload of that domain is declared. What a cluster calls its household
# namespaces is a value; that there are two of them, split that way, is knowledge.
#
# THE NAMING RULE IS ENFORCED RATHER THAN ASKED FOR. A namespace value equal to any application in
# the catalogue is refused: a group named after one of its members reads as though that member were
# the group's definition, which is exactly what makes the next candidate get filed by resemblance
# instead of by the rule. Two domains resolving to ONE namespace is refused for the same reason --
# it would collapse the split into a word nobody acts on.
#
# ── NOTHING HERE ALLOCATES ANYTHING ────────────────────────────────────────────────────────────
#
# No address, no slot number, no namespace value, no node path, no UID and no hostname appears
# anywhere in this repository. Each is a fleet fact and each is a parameter the consumer supplies.
# The slots this module governs are checked for collisions inside the household and for nothing
# else; which RANGE they may come from is a different question, answered by the sibling band model,
# and `nixhome.homePlatform.origin` is the one switch that hands them to it.
#
# ── NO LIVENESS PROBE IS SYNTHESIZED ───────────────────────────────────────────────────────────
#
# The catalogue carries a readiness probe for every entry and no liveness probe for any of them,
# and that is the grammar's own rule followed rather than an omission: a guessed liveness probe is
# the classic way to put a slow-starting application into a restart loop that looks like the
# application's fault, and two entries here migrate a schema on start. A household that wants one
# defines it on the rendered object, where it is typed and checked.
#
# ONE NAMESPACE. Everything declared here lives under `nixhome`, like every repository in this
# family.
{ config, lib, ... }:
let
  cfg = config.nixhome;
  platform = cfg.homePlatform;

  catalogue = import ../lib/trackers.nix { };

  # The domains the catalogue contains, derived rather than listed: adding a tracker in a new
  # domain adds its namespace option automatically, and a domain nobody uses cannot linger as a
  # dead option.
  domains = lib.unique (lib.mapAttrsToList (_: e: e.domain) catalogue.trackers);

  enabledOf = attrs: lib.filterAttrs (_: w: w.enable) attrs;

  trackers = enabledOf cfg.trackers;
  companions = enabledOf cfg.companions;

  catTracker = w: catalogue.trackers.${w.tracker};
  catCompanion = w: catalogue.companions.${w.companion};

  # A companion's domain is the domain of the tracker its CATALOGUE ENTRY serves -- read from the
  # catalogue rather than from the declaration, so it stays total even while a declaration is
  # wrong: the assertions below are what report a bad `serves`, and a resolution that threw first
  # would take the whole evaluation down before any of them could.
  entryDomain = x:
    if x.kind == "tracker"
    then x.entry.domain
    else catalogue.trackers.${x.entry.serves}.domain;

  # Every declared workload, tagged with its kind and its catalogue entry, in one list. Almost
  # every guard here is about the household as a whole -- two workloads on one slot, two workloads
  # creating one namespace, two domains landing in one namespace -- so they are written against
  # this rather than against two separate tables.
  allWorkloads =
    lib.mapAttrsToList (name: w: { inherit name w; kind = "tracker"; entry = catTracker w; }) trackers
    ++ lib.mapAttrsToList (name: w: { inherit name w; kind = "companion"; entry = catCompanion w; }) companions;

  domainOf = x: entryDomain x;
  namespaceOf = x: if x.w.namespace != null then x.w.namespace else platform.namespaces.${domainOf x};

  ## ---------------------------------------------------------------------
  ## Translation into the app grammar
  ## ---------------------------------------------------------------------

  # The catalogue's repository plus the declaration's version, unless the declaration names a whole
  # reference itself -- which is what pinning by digest looks like, and what the grammar warns
  # about the absence of.
  imageOf = entry: w: if w.image != null then w.image else "${entry.image}:${w.version}";

  portsOf = entry: lib.mapAttrs (_: number: { inherit number; }) entry.ports;

  # The knowledge/value split, in one function: WHERE inside the container comes from the
  # catalogue, WHAT BACKS IT comes from the declaration, and neither side can supply the other's
  # half.
  stateOf = entry: w:
    lib.mapAttrs
      (key: backing: {
        mountPath = entry.state.${key};
        inherit (backing) claim hostPath hostPathType readOnly;
      })
      w.state;

  # Which variables this declaration says come from which Secret, grouped the way the grammar wants
  # them: one entry per SECRET, carrying every variable sourced from it. A Secret named in both
  # forms is one entry consuming it both ways rather than two entries fighting over the key.
  varsFromSecret = w: secret:
    lib.mapAttrs (_: r: r.key)
      (lib.filterAttrs (_: r: r.secret == secret) w.secretEnv);

  secretNamesOf = w:
    lib.unique (w.envFromSecrets ++ lib.mapAttrsToList (_: r: r.secret) w.secretEnv);

  secretsOf = w:
    lib.listToAttrs (map
      (s: lib.nameValuePair s (
        { secret = s; }
        // lib.optionalAttrs (lib.elem s w.envFromSecrets) { envFrom = true; }
        // lib.optionalAttrs (varsFromSecret w s != { }) { env = varsFromSecret w s; }
      ))
      (secretNamesOf w));

  probesOf = entry: {
    readiness = { port = entry.primaryPort; } // entry.readiness;
  };

  # Handed to the band model only when the consumer says it is part of the render: `origin` and
  # `slot` are ITS terms, and defining them into a render that does not declare them is an eval
  # error rather than a graceful no-op.
  addressingOf = w:
    lib.optionalAttrs (platform.origin != null) {
      origin = platform.origin;
      inherit (w) slot;
    };

  mkApp = x:
    let inherit (x) entry w; in
    {
      namespace = namespaceOf x;
      inherit (w) createNamespace project exposure scaling;
      image = imageOf entry w;
      ports = portsOf entry;
      state = stateOf entry w;
      secrets = secretsOf w;
      env = entry.env // w.env;
      args = entry.args ++ w.args;
      probes = probesOf entry;
    }
    // addressingOf w;

  ## ---------------------------------------------------------------------
  ## Derived facts the guards are written against
  ## ---------------------------------------------------------------------

  slotClaims = lib.filter (x: x.w.slot != null) allWorkloads;
  claimantsOf = slot: map (x: x.name) (lib.filter (x: x.w.slot == slot) slotClaims);
  duplicatedSlots =
    lib.filter (slot: lib.length (claimantsOf slot) > 1)
      (lib.unique (map (x: x.w.slot) slotClaims));

  creatorsOf = ns: map (x: x.name) (lib.filter (x: x.w.createNamespace && namespaceOf x == ns) allWorkloads);
  usedNamespaces = lib.unique (map namespaceOf allWorkloads);

  declaredDomains = lib.unique (map domainOf allWorkloads);
  domainsIn = ns: lib.filter (d: lib.any (x: domainOf x == d && namespaceOf x == ns) allWorkloads) declaredDomains;

  # Every application name the catalogue knows, in either group. The set a namespace value may not
  # collide with.
  catalogueNames = lib.attrNames catalogue.trackers ++ lib.attrNames catalogue.companions;

  # Which variables a declaration has actually arranged to receive. A wholesale Secret covers
  # everything by construction, and nothing here can see inside it -- which is why it warns.
  coversWholesale = w: w.envFromSecrets != [ ];
  namedVars = w: lib.attrNames w.secretEnv;
  uncovered = x:
    if coversWholesale x.w then [ ]
    else lib.subtractLists (namedVars x.w) x.entry.requiredSecretEnv;

  # The tracker declaration a companion feeds, when it names one that exists.
  servedBy = x: lib.filter (t: t.name == x.w.serves) (lib.filter (y: y.kind == "tracker") allWorkloads);

  ## ---------------------------------------------------------------------
  ## Assertions
  ##
  ## Every message is a total function of the workload: an assertion's message is forced whether or
  ## not the assertion holds, so one that only works in the failing case takes the whole evaluation
  ## down instead of reporting anything.
  ## ---------------------------------------------------------------------

  showSlot = w: if w.slot == null then "(none)" else toString w.slot;
  showList = l: lib.concatMapStringsSep ", " (n: "`${n}`") l;

  stateAssertions = lib.concatMap
    (x:
      let inherit (x) name w entry; in
      [
        {
          # Every directory the application writes has to be backed by something. One that comes up
          # with an unbacked directory looks healthy and quietly loses it at the next restart --
          # which for the chore tracker means losing the file its credentials are in, and for the
          # asset tracker means losing the uploads while the record survives.
          assertion = lib.attrNames w.state == lib.attrNames entry.state;
          message =
            "nixhome: `${name}` must back every directory it writes, and backs "
            + (if w.state == { } then "none" else showList (lib.attrNames w.state))
            + ". It writes: "
            + lib.concatStringsSep ", " (lib.mapAttrsToList (k: p: "`${k}` at ${p}") entry.state)
            + ". An unbacked directory is not an error at runtime -- the application starts, uses the "
            + "container's own filesystem, and loses it at the next restart.";
        }
        {
          assertion = lib.all
            (backing: (backing.claim == null) != (backing.hostPath == null))
            (lib.attrValues w.state);
          message =
            "nixhome: `${name}` backs a directory with neither or both of `claim` and `hostPath`. "
            + "State needs exactly one backing: an existing claim by name, or a path on the node.";
        }
        {
          # A credential that never arrives is not a startup failure for every application here --
          # one of them starts, serves, and simply cannot do the thing the variable was for.
          assertion = uncovered x == [ ];
          message =
            "nixhome: `${name}` cannot be correct without " + showList entry.requiredSecretEnv
            + " in its environment, and nothing here supplies " + showList (uncovered x)
            + ". Name the variable in `secretEnv` (a Secret and a key, never a value), or load a whole "
            + "Secret with `envFromSecrets`. See that entry's own note in lib/trackers.nix for what the "
            + "variable is and what goes wrong when it is absent or changes.";
        }
      ])
    allWorkloads;

  companionAssertions = lib.concatMap
    (x:
      let inherit (x) name w entry; in
      [
        {
          assertion = servedBy x != [ ];
          message =
            "nixhome: companion `${name}` serves `${w.serves}`, which is not a tracker declared in "
            + "`nixhome.trackers` (declared: "
            + (if trackers == { } then "none" else showList (lib.attrNames trackers))
            + "). A companion keeps no record of its own -- every action it takes lands in the tracker's "
            + "database -- so one deployed beside nothing writes to nothing.";
        }
        {
          assertion = servedBy x == [ ] || (lib.head (servedBy x)).w.tracker == entry.serves;
          message =
            "nixhome: companion `${name}` serves declaration `${w.serves}`, which runs "
            + "`${lib.concatMapStringsSep "" (t: t.w.tracker) (servedBy x)}` -- but this companion feeds "
            + "`${entry.serves}` and speaks nothing else. Point it at a declaration of that application.";
        }
        {
          # THE WAKE INTERLOCK. A wake front stands in front of the address the outside world uses,
          # never in front of the in-cluster Service: a companion that dials the Service of a
          # tracker idling at zero reaches a Deployment with no pods, the tracker never wakes, and
          # both workloads report healthy while the write is lost.
          assertion =
            servedBy x == [ ]
            || w.reaches == "front"
            || (lib.head (servedBy x)).w.scaling != "scale-to-zero";
          message =
            "nixhome: companion `${name}` reaches `${w.serves}` in-cluster, and `${w.serves}` is declared "
            + "`scale-to-zero`. A wake front stands in front of the address the outside world uses, not in "
            + "front of the Service -- so this request arrives at a Deployment with no pods, nothing wakes "
            + "it, and the write is lost while both workloads report healthy. Either set "
            + "`reaches = \"front\"` and configure the companion with the same address everything else "
            + "uses (which lets BOTH of them idle at zero), or take `${w.serves}` off scale-to-zero.";
        }
      ])
    (lib.filter (x: x.kind == "companion") allWorkloads);

  householdAssertions =
    map
      (slot: {
        assertion = false;
        message =
          "nixhome: slot ${toString slot} is claimed by more than one workload: " + showList (claimantsOf slot)
          + ". A slot is one identity in every address space the fleet maps it into, so two claimants is a "
          + "collision in all of them at once.";
      })
      duplicatedSlots
    ++ lib.concatMap
      (ns: [
        {
          assertion = lib.length (creatorsOf ns) <= 1;
          message =
            "nixhome: namespace `${ns}` is created by more than one workload: " + showList (creatorsOf ns)
            + ". Two Applications owning one Namespace fight over it. Let exactly one anchor it, or anchor "
            + "it in the tenancy layer and set `createNamespace = false` on all of them.";
        }
        {
          # THE NAMING RULE, mechanical. A group named after one of its members reads as though that
          # member were the group's definition -- which is precisely how the next candidate ends up
          # filed by resemblance instead of by the rule.
          assertion = !(lib.elem ns catalogueNames);
          message =
            "nixhome: namespace `${ns}` is the name of an application this catalogue holds. A namespace "
            + "named after one of the things inside it reads as though that thing defined the group, and "
            + "the next application filed there gets filed by resemblance rather than by the rule. The "
            + "domains are " + showList domains + " -- name the namespace for what the group IS.";
        }
        {
          # The split is the point. Two domains sharing one namespace collapses it into a word
          # nobody acts on.
          assertion = lib.length (domainsIn ns) <= 1;
          message =
            "nixhome: namespace `${ns}` holds workloads from more than one domain: " + showList (domainsIn ns)
            + ". The domains are what separates the record of WHAT YOU KEEP from the record of what runs "
            + "out and what comes round, and one namespace holding both is the split written down and not "
            + "acted on. Give each domain its own namespace in `nixhome.homePlatform.namespaces`.";
        }
      ])
      usedNamespaces;

  ## ---------------------------------------------------------------------
  ## Warnings
  ## ---------------------------------------------------------------------

  warnings =
    map
      (x: {
        when = x.entry.background != null && x.w.scaling == "scale-to-zero";
        message =
          "nixhome: `${x.name}` scales to zero, and while it is at zero it is not running "
          + "${x.entry.background}. That work is not late, it is never evaluated until the next request "
          + "wakes the pod. For a household that is often an acceptable trade -- it is a decision rather "
          + "than a fault -- but it is a decision, so it is said here instead of being discovered from a "
          + "reminder that never arrived.";
      })
      allWorkloads
    ++ map
      (x: {
        when = x.entry.requiredSecretEnv != [ ] && coversWholesale x.w && namedVars x.w == [ ];
        message =
          "nixhome: `${x.name}` needs " + showList x.entry.requiredSecretEnv
          + " and receives whole Secret(s) " + showList x.w.envFromSecrets
          + " instead. Nothing here can see inside a Secret, so a missing or misspelled key is not "
          + "catchable at eval and will surface as the application's own startup error. Name the "
          + "variables in `secretEnv` if you want that checked.";
      })
      allWorkloads
    ++ map
      (x: {
        when = x.w.slot != null && platform.origin == null;
        message =
          "nixhome: `${x.name}` claims slot ${showSlot x.w}, and `nixhome.homePlatform.origin` is unset -- "
          + "so the number is checked for collisions inside the household, and by nothing for which RANGE "
          + "it may come from. Set the origin when the band model is part of the same render.";
      })
      allWorkloads
    ++ map
      (ns: {
        when = creatorsOf ns == [ ];
        message =
          "nixhome: nothing declared here anchors namespace `${ns}`, so it must already exist or be "
          + "created by the tenancy layer. That is a perfectly good arrangement -- it is the better one "
          + "for a namespace that outlives every workload in it -- but a render into a namespace nobody "
          + "created fails at sync rather than at eval, which is a long way from the cause.";
      })
      usedNamespaces;

  ## ---------------------------------------------------------------------
  ## Option shapes shared by both kinds of workload
  ## ---------------------------------------------------------------------

  backingType = lib.types.submodule {
    options = {
      claim = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          NAME of an existing PersistentVolumeClaim backing this directory. A name, never a path.
          Nothing here creates the claim: it outlives every version of the application that mounts
          it, so its existence is not the application's to declare.
        '';
      };

      hostPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path on the NODE backing this directory instead of a claim, and in practice the common
          answer for a household: the directory is usually a filesystem somebody curates, snapshots
          and backs up deliberately, and the record it holds is the point of the whole application.

          IT PINS THE WORKLOAD TO A NODE, because the path only exists on one. The VALUE is a fleet
          fact and belongs to the consumer that passes it in -- no path appears anywhere in this
          repository.
        '';
      };

      hostPathType = lib.mkOption {
        type = lib.types.enum [ "Directory" "DirectoryOrCreate" ];
        default = "Directory";
        description = ''
          Whether a missing node path is an error or is created empty. `Directory` (the default)
          refuses to start, which is the right answer for a household's own record: every
          application here INITIALISES AN EMPTY STORE when it finds one, and a fresh empty
          inventory reports itself perfectly healthy. `DirectoryOrCreate` is for a directory that
          genuinely starts out empty on a first run.
        '';
      };

      readOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Mount read-only. Never right for the directory holding the record; occasionally right for
          something mounted alongside it.
        '';
      };
    };
  };

  secretRefType = lib.types.submodule {
    options = {
      secret = lib.mkOption {
        type = lib.types.str;
        description = "NAME of an existing Secret. A name, never a value.";
      };
      key = lib.mkOption {
        type = lib.types.str;
        description = "Which key inside that Secret carries this variable.";
      };
    };
  };

  commonOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to render this workload. Declaring the attribute is declaring the workload, so this
        defaults to true; set false to park a declaration without rendering it.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      example = "1.2.3";
      description = ''
        Which version this workload runs, used as the image tag. REQUIRED, with no default anywhere
        in this repository, and that is deliberate rather than an oversight: two of these
        applications migrate their own schema on start, and a migration is the one operation here
        that a restart of the previous image does not undo. Which version a household is willing to
        be migrated to is that household's decision and this catalogue will not make it.

        Prefer `image` with a digest over this alone -- see that option.
      '';
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Whole image reference, replacing the catalogue's repository plus `version`. Set it to PIN BY
        DIGEST (`repository:tag@sha256:...`), which is the only way two syncs of an identical
        rendered tree cannot run different code -- and, for the two applications that migrate on
        start, the only way a deploy nobody reviewed cannot migrate a database.

        `null` (the default) builds the reference from the catalogue's repository and `version`.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Namespace this workload lands in, overriding the one its DOMAIN resolves to. `null` (the
        default) takes `nixhome.homePlatform.namespaces.<domain>`, which is the arrangement this
        module is written for: what a workload records decides where it lives.

        Setting it is legitimate and rare. A companion pulled out of its tracker's namespace still
        works, and still writes to the same database; it simply stops being obviously part of the
        same thing.
      '';
    };

    createNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this workload anchors its namespace. Defaults to false: a namespace holding a
        household's records outlives every workload in it, and the better owner is usually the
        tenancy layer. Exactly one workload may anchor one namespace; two fails eval, and none
        warns.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = platform.project;
      defaultText = lib.literalExpression "config.nixhome.homePlatform.project";
      description = "Delivery project this workload's Application belongs to.";
    };

    slot = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = ''
        THE POSITION this workload holds in the fleet's ordered identity space. Not an address --
        the layers underneath map it into however many address spaces the fleet keeps, which is
        exactly why nothing here moves one.

        The VALUE is a fleet fact and belongs to the consumer that passes it in. What this module
        does with it is refuse two workloads on one number. Which RANGE the numbers may come from is
        a different question, answered by the band model -- see `nixhome.homePlatform.origin`.

        `null` is right for a workload that renders no Service. Every application in this catalogue
        renders one, so in practice every workload declared here takes a slot.
      '';
    };

    exposure = lib.mkOption {
      type = lib.types.enum [ "internal" "nb" "public" ];
      default = "internal";
      description = ''
        WHO can reach this workload, as a class and never an address.

        `internal` is the default and is rarely the final answer here -- these are applications a
        person opens, from a phone in a supermarket as often as from a desk. It is the default
        anyway, because the alternative is this repository deciding that a household's record of
        what it owns faces the internet. Choose it deliberately, in the place that knows what fronts
        it.
      '';
    };

    scaling = lib.mkOption {
      type = lib.types.enum [ "always" "scale-to-zero" ];
      default = "always";
      description = ''
        `always` -- a running replica this workload owns.
        `scale-to-zero` -- idles at zero, and a wake front brings it up on the next request.

        THE HONEST ANSWER DEPENDS ON THE APPLICATION, not on the household's taste, and the
        catalogue is what knows the difference: an application that computes everything in answer to
        a request has nothing to miss while it sleeps, and one with a scheduler silently defers
        every reminder it would have sent. Setting this on a workload with background work warns and
        says what stops.

        It also has a consequence for anything that DEPENDS on this workload from inside the
        cluster: a wake front stands in front of the address the outside world uses, so an
        in-cluster caller cannot wake it. That is refused rather than warned about -- see
        `nixhome.companions.<name>.reaches`.
      '';
    };

    state = lib.mkOption {
      type = lib.types.attrsOf backingType;
      default = { };
      description = ''
        What BACKS each directory this application writes, keyed by the catalogue's own name for it.
        Where each one lands inside the container is knowledge and comes from the catalogue; what
        holds it is a value and comes from here.

        Every directory the catalogue names must appear. This is the option that matters most in
        this repository: the directory IS the household's record, and an application whose store is
        unbacked starts, looks healthy, and presents an empty inventory as though that were the
        truth.
      '';
    };

    secretEnv = lib.mkOption {
      type = lib.types.attrsOf secretRefType;
      default = { };
      example = lib.literalExpression ''
        { EXAMPLE_APPLICATION_PIN = { secret = "example-secret"; key = "pin"; }; }
      '';
      description = ''
        Environment variables sourced from individual Secret keys, as
        `<VARIABLE> = { secret = "<name>"; key = "<key>"; }`. Renders a `secretKeyRef`, so no value
        passes through Nix or the rendered tree.

        Preferred over `envFromSecrets` for anything the catalogue lists in `requiredSecretEnv`,
        because naming the variable is what makes its absence catchable here rather than in the
        application's startup log.
      '';
    };

    envFromSecrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        NAMES of existing Secrets loaded wholesale into the environment. Convenient and blunt: the
        application gets whatever the Secret happens to contain, and nothing here can see inside it,
        so a missing key surfaces as the application's own error. It satisfies a
        `requiredSecretEnv` and warns while doing so.
      '';
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra plain environment, merged OVER whatever the catalogue supplies. Plain is the operative
        word: a credential belongs in a Secret, and an address belongs to whatever allocates
        addresses -- the app grammar scans these values and refuses an address literal.

        This is where a household's POLICY goes, and there is more of it here than in most subjects:
        the timezone every due date is computed in, whether registration is open, the identity
        numbers an image that reads them should drop to. The catalogue supplies what an application
        needs in order to be CORRECT and never what one household wants it to do.
      '';
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra entrypoint arguments, appended to whatever the catalogue supplies.";
    };
  };
in
{
  options.nixhome.homePlatform = {
    namespaces = lib.mkOption {
      description = ''
        WHICH NAMESPACE each domain's workloads land in. One option per domain the catalogue
        contains, each with NO DEFAULT: evaluation fails naming the option the moment a workload of
        that domain is declared, because what a cluster calls its household namespaces is a value
        and a default here would be this repository deciding it.

        That there are two domains, split between the record of what you KEEP and the record of what
        RUNS OUT or COMES ROUND, is knowledge and is not negotiable here. Which words a cluster uses
        for them is not -- though a household that likes the domain names may simply reuse them.

        Two domains may not resolve to one namespace, and a namespace may not be named after an
        application inside it. Both fail eval.
      '';
      example = lib.literalExpression ''
        { belongings = "example-belongings"; housekeeping = "example-housekeeping"; }
      '';
      type = lib.types.submodule {
        options = lib.genAttrs domains (domain: lib.mkOption {
          type = lib.types.str;
          description = "Namespace for the `${domain}` domain.";
        });
      };
      default = { };
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        Delivery project every workload here lands in unless it says otherwise.

        Defaults to `default` -- the delivery tool's own built-in project, which permits every
        destination and is therefore the answer that cannot break a render. It is not the answer to
        leave in place: name a project of your own so the household is governed like everything
        else.
      '';
    };

    origin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "nixhome";
      description = ''
        The declaring-origin name to stamp on these workloads, handing their slots to the BAND MODEL
        -- which governs which range of the identity space a declaring repository's workloads may
        take a number from.

        `null` by default because `origin` and `slot` are that model's terms: defining them into a
        render that does not include it fails with "the option does not exist". Set this only when
        it is part of the same render, and set it to the name that model binds a band for. WHICH
        band that is is fleet layout and lives in the repository that owns the fleet.
      '';
    };
  };

  options.nixhome.trackers = lib.mkOption {
    default = { };
    description = ''
      The household's own records, keyed by a name of your choosing. A tracker is an application
      whose product IS a record that outlives every session with it -- of the objects you own, of
      the stock you hold, or of the work that comes round -- and it is authoritative for whatever it
      records.

      Each names an application from the catalogue and the version it runs. Where it lands is
      decided by that application's DOMAIN rather than by this declaration: what a tracker records
      is a property of the software, so the namespace follows from it.
    '';
    example = lib.literalExpression ''
      {
        example-inventory = {
          tracker = "homebox";
          version = "0.0.0";
          slot = N;
          exposure = "public";
          state.data.hostPath = "/example/state/inventory";
          secretEnv.HBOX_AUTH_API_KEY_PEPPER = { secret = "example-inventory"; key = "pepper"; };
        };

        example-chores = {
          tracker = "donetick";
          version = "0.0.0";
          slot = N + 1;
          # Its scheduler stops while it sleeps -- the module says so rather than leaving it to be
          # discovered from a reminder that never arrived.
          scaling = "scale-to-zero";
          state = {
            config.hostPath = "/example/state/chores";
            data.hostPath = "/example/state/chores/database";
          };
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule {
      options = commonOptions // {
        tracker = lib.mkOption {
          type = lib.types.enum (lib.attrNames catalogue.trackers);
          description =
            "Which application, from the catalogue. Available: "
              + lib.concatStringsSep ", " (lib.attrNames catalogue.trackers) + ".";
        };
      };
    });
  };

  options.nixhome.companions = lib.mkOption {
    default = { };
    description = ''
      Workloads that exist only to FEED a tracker, keyed by a name of your choosing. A companion
      keeps no record of its own: everything it does becomes a change in somebody else's database,
      so turning it off loses a way of writing rather than anything written.

      It inherits the domain -- and therefore the namespace -- of the tracker it serves, and this
      module governs the relationship rather than merely recording it: the tracker has to be
      declared, it has to be the application this companion actually speaks to, and how the
      companion reaches it has to be an arrangement that works when the tracker is asleep.
    '';
    example = lib.literalExpression ''
      {
        example-scanner = {
          companion = "barcodebuddy";
          serves = "example-groceries";
          version = "0.0.0";
          slot = N;
          # Its tracker idles at zero, so it has to arrive the way everything else does.
          reaches = "front";
          state.config.hostPath = "/example/state/groceries/scanner";
        };
      }
    '';
    type = lib.types.attrsOf (lib.types.submodule {
      options = commonOptions // {
        companion = lib.mkOption {
          type = lib.types.enum (lib.attrNames catalogue.companions);
          description =
            "Which companion, from the catalogue. Available: "
              + lib.concatStringsSep ", " (lib.attrNames catalogue.companions) + ".";
        };

        serves = lib.mkOption {
          type = lib.types.str;
          description = ''
            WHICH DECLARATION in `nixhome.trackers` this companion feeds -- your name for it, not
            the catalogue's. It must exist and it must run the application this companion actually
            speaks to; both are checked, because a companion pointed at nothing writes to nothing
            and looks perfectly healthy doing it.
          '';
        };

        reaches = lib.mkOption {
          type = lib.types.enum [ "in-cluster" "front" ];
          default = "in-cluster";
          description = ''
            HOW this companion reaches the tracker it feeds.

            `in-cluster` -- straight to the tracker's Service, the shorter path and the right answer
            whenever the tracker is always running.
            `front` -- through the same address everything else uses, and therefore through whatever
            wakes the tracker.

            THIS RENDERS NOTHING, and it is not a decoration for that. The URL lives inside the
            companion's own configuration, on its state directory, where somebody typed it into a
            form -- so this option is the only way that fact becomes checkable at all. Declaring
            `in-cluster` against a tracker that idles at zero fails eval, naming both: the request
            would arrive at a Deployment with no pods, nothing would wake it, and the write would be
            lost while both workloads reported healthy.
          '';
        };
      };
    });
  };

  # ── Computed, read-only ───────────────────────────────────────────────────────────────────────
  options.nixhome.slots = lib.mkOption {
    type = lib.types.attrsOf lib.types.ints.unsigned;
    readOnly = true;
    default = lib.listToAttrs
      (map (x: lib.nameValuePair x.name x.w.slot) (lib.filter (x: x.w.slot != null) allWorkloads));
    defaultText = lib.literalExpression "every declared workload that claims a slot";
    description = ''
      workload -> the position it claims. Nothing is rendered from it here: what an address looks
      like is the private layer's business, and this is what that layer reads to build one.
    '';
  };

  options.nixhome.domains = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    default = lib.listToAttrs (map (x: lib.nameValuePair x.name (domainOf x)) allWorkloads);
    defaultText = lib.literalExpression "read from the catalogue, for every declared workload";
    description = ''
      workload -> the domain it belongs to, read from the catalogue rather than from the
      declaration. Published because it is the thing that decided where each workload landed, and a
      reader should be able to see that without re-deriving it.
    '';
  };

  options.nixhome.namespaces = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    default = lib.listToAttrs
      (map (d: lib.nameValuePair d (namespaceOf (lib.head (lib.filter (x: domainOf x == d) allWorkloads))))
        declaredDomains);
    defaultText = lib.literalExpression "the namespace each DECLARED domain resolved to";
    description = ''
      domain -> the namespace its workloads landed in, for every domain actually declared. Only the
      declared ones: reading the namespace of a domain nobody uses would force an option the
      consumer had no reason to set.
    '';
  };

  options.nixhome.dormantWhileAsleep = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name)
      (lib.filter (x: x.entry.background != null && x.w.scaling == "scale-to-zero") allWorkloads);
    defaultText = lib.literalExpression "computed from the declared workloads and the catalogue";
    description = ''
      Workloads that idle at zero AND have work that only happens while they are running -- so that
      work is not late, it is never evaluated until something wakes them.

      Read-only, and the point of it is that it is COUNTABLE. Every entry here is a household
      deciding that a reminder arriving on the next visit is good enough, which is a perfectly
      reasonable decision and a terrible one to make by accident.
    '';
  };

  config = {
    # THE WHOLE RENDER, and there is nothing else: every workload this repository declares is
    # described as an app, in somebody else's vocabulary.
    nixk3s.apps = lib.listToAttrs (map (x: lib.nameValuePair x.name (mkApp x)) allWorkloads);

    nixidy.assertions = stateAssertions ++ companionAssertions ++ householdAssertions;
    nixidy.warnings = warnings;
  };
}
