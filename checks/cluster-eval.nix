# Proves the cluster module resolves what it claims and REFUSES what it claims to refuse, both
# directions, through the real renderer and the real app grammar.
#
# Both halves matter and neither is enough alone. A guard nobody has watched fire is a comment; a
# guard that fires on everything is a wall. So every case below is a complete, otherwise-valid
# household with exactly one thing wrong, and the `control` case is the same shape with nothing
# wrong and MUST render -- without it, a typo in the shared base would make every other case "pass"
# for the wrong reason.
#
# Two refusals additionally have their MESSAGE asserted by content, because `tryEval` can only say
# THAT something was refused. For the wake interlock in particular, half of what is being checked is
# whether the refusal names both workloads and says what to do instead -- the failure it prevents is
# a lost write between two workloads that both report healthy, which is the kind nobody finds by
# looking at the cluster.
{ pkgs, lib, nixidy, appsModule, addressingModule, clusterModule }:
let
  base = {
    nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
    nixidy.target.branch = "main";
    nixhome.homePlatform = {
      namespaces = {
        belongings = "example-belongings";
        housekeeping = "example-housekeeping";
      };
      project = "example-home";
    };
  };

  mkEnv = values: nixidy.lib.mkEnv {
    inherit pkgs;
    modules = [ appsModule addressingModule clusterModule base values ];
  };

  renders = values:
    (builtins.tryEval (builtins.seq (mkEnv values).environmentPackage.drvPath true)).success;

  # The assertions themselves rather than the throw they eventually cause.
  failures = values:
    map (a: a.message)
      (lib.filter (a: !a.assertion) (mkEnv values).config.nixidy.assertions);

  sorted = lib.sort (a: b: a < b);

  ## ---------------------------------------------------------------------
  ## The floor: an empty household renders nothing at all
  ## ---------------------------------------------------------------------

  emptyCfg = (mkEnv { }).config;

  ## ---------------------------------------------------------------------
  ## The control: a complete household that must resolve
  ## ---------------------------------------------------------------------

  goodHousehold = {
    nixhome.trackers = {
      assets = {
        tracker = "dumbassets";
        version = "0.0.0";
        slot = 64;
        exposure = "public";
        createNamespace = true;
        state.data.hostPath = "/example/state/assets";
        secretEnv.DUMBASSETS_PIN = { secret = "example-assets"; key = "pin"; };
      };

      inventory = {
        tracker = "homebox";
        version = "0.0.0";
        slot = 65;
        exposure = "public";
        state.data.hostPath = "/example/state/inventory";
        secretEnv.HBOX_AUTH_API_KEY_PEPPER = { secret = "example-inventory"; key = "pepper"; };
      };

      groceries = {
        tracker = "grocy";
        version = "0.0.0";
        slot = 66;
        exposure = "public";
        scaling = "scale-to-zero";
        createNamespace = true;
        state.config.hostPath = "/example/state/groceries";
        env = { PUID = "1234"; PGID = "1234"; };
      };

      chores = {
        tracker = "donetick";
        version = "0.0.0";
        slot = 67;
        exposure = "public";
        scaling = "scale-to-zero";
        state = {
          config.hostPath = "/example/state/chores";
          data.hostPath = "/example/state/chores/database";
        };
      };
    };

    nixhome.companions.scanner = {
      companion = "barcodebuddy";
      serves = "groceries";
      version = "0.0.0";
      slot = 68;
      exposure = "public";
      scaling = "scale-to-zero";
      reaches = "front";
      state.config.hostPath = "/example/state/groceries/scanner";
    };
  };

  goodCfg = (mkEnv goodHousehold).config;

  workloadNames = [ "assets" "chores" "groceries" "inventory" "scanner" ];

  ## ---------------------------------------------------------------------
  ## The failing direction
  ## ---------------------------------------------------------------------

  # Each case is `goodHousehold` with one thing changed. Written as whole households rather than as
  # patches so that a reader can see what is wrong without reconstructing it.
  mustFail = {
    # Every directory the application writes must be backed. The chore tracker writes two, one
    # nested inside the other in the layout its image ships, and backing only the outer one produces
    # an application that starts, serves, and loses its database at the next restart.
    tracker-with-an-unbacked-directory =
      lib.recursiveUpdate goodHousehold {
        nixhome.trackers.chores.state = lib.mkForce { config.hostPath = "/example/state/chores"; };
      };

    state-with-no-backing =
      lib.recursiveUpdate goodHousehold {
        nixhome.trackers.assets.state.data.hostPath = lib.mkForce null;
      };

    state-with-both-backings =
      lib.recursiveUpdate goodHousehold {
        nixhome.trackers.assets.state.data.claim = "example-assets-data";
      };

    # The access model arriving from nowhere. This one does not crash the application -- it starts,
    # serves, and is either unreachable or unprotected depending on what it does with an unset
    # variable, which is precisely why it is refused rather than warned about.
    required-credential-variable-not-supplied =
      lib.recursiveUpdate goodHousehold {
        nixhome.trackers.assets.secretEnv = lib.mkForce { };
      };

    companion-serving-nothing =
      lib.recursiveUpdate goodHousehold {
        nixhome.companions.scanner.serves = lib.mkForce "no-such-declaration";
      };

    companion-serving-the-wrong-application =
      lib.recursiveUpdate goodHousehold {
        nixhome.companions.scanner.serves = lib.mkForce "chores";
      };

    # THE WAKE INTERLOCK. A wake front stands in front of the address the outside world uses, never
    # in front of the Service -- so this arrangement loses the write and wakes nothing, while both
    # workloads report healthy.
    companion-reaching-a-sleeping-tracker-in-cluster =
      lib.recursiveUpdate goodHousehold {
        nixhome.companions.scanner.reaches = lib.mkForce "in-cluster";
      };

    two-workloads-on-one-slot =
      lib.recursiveUpdate goodHousehold { nixhome.trackers.chores.slot = lib.mkForce 66; };

    two-workloads-creating-one-namespace =
      lib.recursiveUpdate goodHousehold { nixhome.trackers.inventory.createNamespace = true; };

    # THE NAMING RULE, as a value somebody supplied rather than as a name in the catalogue.
    namespace-named-after-an-application-inside-it =
      lib.recursiveUpdate goodHousehold {
        nixhome.homePlatform.namespaces.belongings = lib.mkForce "homebox";
      };

    # The split written down and not acted on.
    two-domains-in-one-namespace =
      lib.recursiveUpdate goodHousehold {
        nixhome.homePlatform.namespaces.housekeeping = lib.mkForce "example-belongings";
      };
  };

  wronglyRendered = lib.attrNames (lib.filterAttrs (_: v: v) (lib.mapAttrs (_: renders) mustFail));

  # A `tryEval` that caught a TYPE error, a missing option or a typo in the fixture looks exactly
  # like a guard firing, and would let every case below "pass" while this module checked nothing. So
  # each case additionally has to produce a failed assertion belonging to THIS module.
  refusedElsewhere = lib.attrNames
    (lib.filterAttrs
      (_: values: !(lib.any (m: lib.hasPrefix "nixhome: " m) (failures values)))
      mustFail);

  # The wake refusal, read as text. It has to name both workloads and say what to do instead,
  # because the failure it prevents is invisible from the cluster.
  wakeMessage =
    let
      msgs = lib.filter (m: lib.hasInfix "scanner" m)
        (failures mustFail.companion-reaching-a-sleeping-tracker-in-cluster);
    in
    if msgs == [ ] then "" else lib.head msgs;

  wakeMessageNames =
    lib.hasInfix "`scanner`" wakeMessage
    && lib.hasInfix "`groceries`" wakeMessage
    && lib.hasInfix "reaches" wakeMessage
    && lib.hasInfix "front" wakeMessage;

  # The unbacked-directory refusal has to say WHICH directories the application writes and where, or
  # the reader has to find that out somewhere else -- which is the whole failure this catalogue
  # exists to prevent.
  unbackedMessage =
    let
      msgs = lib.filter (m: lib.hasInfix "chores" m)
        (failures mustFail.tracker-with-an-unbacked-directory);
    in
    if msgs == [ ] then "" else lib.head msgs;

  unbackedMessageNames =
    lib.hasInfix "/config" unbackedMessage
    && lib.hasInfix "/usr/src/app/data" unbackedMessage;

  ## ---------------------------------------------------------------------
  ## The band model, when it is part of the same render
  ## ---------------------------------------------------------------------

  addressedCfg = (mkEnv (lib.recursiveUpdate goodHousehold {
    nixhome.homePlatform.origin = "nixhome";
    nixk3s.addressing = {
      enable = true;
      bands.example-personal = { base = 64; size = 16; };
      bindings.nixhome = "example-personal";
    };
  })).config;

  results = {
    # ── The floor ─────────────────────────────────────────────────────────────────────────────
    "an empty household defines no app in the grammar at all" =
      emptyCfg.nixk3s.apps == { };

    "an empty household reports no slots, no domains and nothing dormant" =
      emptyCfg.nixhome.slots == { }
      && emptyCfg.nixhome.domains == { }
      && emptyCfg.nixhome.namespaces == { }
      && emptyCfg.nixhome.dormantWhileAsleep == [ ];

    "an empty household raises no assertion of its own -- an unused module must be silent" =
      lib.all (a: a.assertion) emptyCfg.nixidy.assertions;

    # ── The control ───────────────────────────────────────────────────────────────────────────
    "a complete household renders" = renders goodHousehold;

    # THE UNTYPED SURFACE IS EMPTY, and this is the assertion that keeps it that way. The renderer
    # defines applications of its own regardless of what is declared, so "adds nothing but its own
    # workloads" is asserted as a DIFFERENCE against an empty household -- and every one of those
    # additions has to have come through the grammar.
    "every workload goes through the app grammar, and nothing goes around it" =
      sorted (lib.subtractLists (lib.attrNames emptyCfg.applications) (lib.attrNames goodCfg.applications))
      == workloadNames
      && sorted (lib.attrNames goodCfg.nixk3s.apps) == workloadNames;

    # ── The domain decides the namespace ──────────────────────────────────────────────────────
    "each workload lands in the namespace its DOMAIN resolves to, not one it named" =
      goodCfg.nixk3s.apps.assets.namespace == "example-belongings"
      && goodCfg.nixk3s.apps.inventory.namespace == "example-belongings"
      && goodCfg.nixk3s.apps.groceries.namespace == "example-housekeeping"
      && goodCfg.nixk3s.apps.chores.namespace == "example-housekeeping";

    "a companion inherits the domain of the tracker it serves, so it lands beside it" =
      goodCfg.nixhome.domains.scanner == "housekeeping"
      && goodCfg.nixk3s.apps.scanner.namespace == goodCfg.nixk3s.apps.groceries.namespace;

    "the domain report is read from the catalogue for every workload" =
      goodCfg.nixhome.domains == {
        assets = "belongings";
        inventory = "belongings";
        groceries = "housekeeping";
        chores = "housekeeping";
        scanner = "housekeeping";
      };

    "the namespace report covers exactly the domains actually declared" =
      goodCfg.nixhome.namespaces == {
        belongings = "example-belongings";
        housekeeping = "example-housekeeping";
      };

    # ── The catalogue's knowledge reaches the grammar ─────────────────────────────────────────
    "the image is the catalogue's repository plus THIS declaration's version" =
      goodCfg.nixk3s.apps.assets.image == "dumbwareio/dumbassets:0.0.0"
      && goodCfg.nixk3s.apps.groceries.image == "lscr.io/linuxserver/grocy:0.0.0";

    "the port and the mount path are the catalogue's, and the backing is the declaration's" =
      goodCfg.nixk3s.apps.assets.ports.http.number == 3000
      && goodCfg.nixk3s.apps.assets.state.data.mountPath == "/app/data"
      && goodCfg.nixk3s.apps.assets.state.data.hostPath == "/example/state/assets";

    "an application with two directories gets both, at the paths its own image expects" =
      goodCfg.nixk3s.apps.chores.state.config.mountPath == "/config"
      && goodCfg.nixk3s.apps.chores.state.data.mountPath == "/usr/src/app/data";

    "correctness environment comes from the catalogue and policy is merged over it" =
      goodCfg.nixk3s.apps.chores.env.DT_ENV == "selfhosted"
      && goodCfg.nixk3s.apps.groceries.env.PUID == "1234";

    "the probe watches the port the catalogue calls primary, with the application's own timing" =
      goodCfg.nixk3s.apps.assets.probes.readiness.port == "http"
      && goodCfg.nixk3s.apps.assets.probes.readiness.path == "/"
      && goodCfg.nixk3s.apps.groceries.probes.readiness.path == null
      && goodCfg.nixk3s.apps.groceries.probes.readiness.initialDelaySeconds == 15;

    "no liveness probe is ever synthesized -- two of these migrate a schema on start" =
      lib.all (a: a.probes.liveness == null && a.probes.startup == null)
        (lib.attrValues goodCfg.nixk3s.apps);

    # ── Credentials are references ────────────────────────────────────────────────────────────
    "a named credential arrives as a reference to a Secret and a key, never as a value" =
      goodCfg.nixk3s.apps.assets.secrets.example-assets.secret == "example-assets"
      && goodCfg.nixk3s.apps.assets.secrets.example-assets.env.DUMBASSETS_PIN == "pin"
      && goodCfg.nixk3s.apps.assets.secrets.example-assets.envFrom == false;

    "an application whose credentials live in its own config file names no Secret at all" =
      goodCfg.nixk3s.apps.chores.secrets == { }
      && goodCfg.nixk3s.apps.groceries.secrets == { };

    # ── Scale-to-zero, and what it costs ──────────────────────────────────────────────────────
    "the workload with background work is the one reported dormant, and only when it sleeps" =
      goodCfg.nixhome.dormantWhileAsleep == [ "chores" ]
      && (mkEnv (lib.recursiveUpdate goodHousehold {
        nixhome.trackers.chores.scaling = lib.mkForce "always";
      })).config.nixhome.dormantWhileAsleep == [ ];

    "the scaling class reaches the grammar, which is what decides whether a replica count renders" =
      goodCfg.nixk3s.apps.groceries.scaling == "scale-to-zero"
      && goodCfg.nixk3s.apps.assets.scaling == "always";

    # ── Slots ─────────────────────────────────────────────────────────────────────────────────
    "the slot report covers every workload that claims one" =
      goodCfg.nixhome.slots == { assets = 64; inventory = 65; groceries = 66; chores = 67; scanner = 68; };

    "with the band model in the render, every workload carries the declaring origin and its slot" =
      lib.all (a: a.origin == "nixhome") (lib.attrValues addressedCfg.nixk3s.apps)
      && addressedCfg.nixk3s.apps.groceries.slot == 66;

    "and without that switch the apps name no origin at all -- those are the band model's terms" =
      goodCfg.nixk3s.apps.assets.origin == null && goodCfg.nixk3s.apps.assets.slot == null;

    # ── The failing direction ─────────────────────────────────────────────────────────────────
    "every guard fires: nothing in the must-fail set renders" =
      wronglyRendered == [ ];

    "and each one is refused BY THIS MODULE, not by a type error that happens to look the same" =
      refusedElsewhere == [ ];

    "the wake refusal names both workloads and the arrangement that works" =
      wakeMessageNames;

    "the unbacked-directory refusal says which directories the application writes, and where" =
      unbackedMessageNames;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then
  pkgs.writeText "nixhome-cluster-eval" ''
    control renders, the floor holds, and every guard fires:
    ${lib.concatMapStringsSep "\n" (n: "  refused: ${n}") (lib.attrNames mustFail)}
  ''
else
  throw ''
    nixhome: cluster-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
    ${lib.optionalString (wronglyRendered != [ ])
      "Declarations that rendered but had to be refused: ${lib.concatStringsSep ", " wronglyRendered}"}
    ${lib.optionalString (refusedElsewhere != [ ])
      "Declarations refused by something other than this module's own guards: ${lib.concatStringsSep ", " refusedElsewhere}"}
  ''
