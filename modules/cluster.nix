#
# nixhome's surface: declare what the household runs, and render every enabled declaration through
# the shared nixk3s consumer factory. The factory owns the universal app translation; this module
# keeps only household knowledge: the two public roots, domain placement, legacy state and Secret
# vocabulary, companion interlocks, and the reports that existing consumers read.
#
# Import the app grammar alongside this module. nixk3s.apps is declared there, not here.
{ catalogue, mkConsumerModule }:
{ config, lib, ... }:
let
  cfg = config.nixhome;
  platform = cfg.homePlatform;

  domains = lib.unique (lib.mapAttrsToList (_: entry: entry.domain) catalogue.trackers);
  catalogueNames = lib.attrNames catalogue.trackers ++ lib.attrNames catalogue.companions;

  # Factory contexts are grouped by root name. Preserve the legacy tracker-then-companion order for
  # reports and diagnostics whose list order is visible.
  orderedWorkloads = workloads:
    lib.filter (x: x.root == "trackers") workloads
    ++ lib.filter (x: x.root == "companions") workloads;

  domainOf = x:
    if x.root == "trackers"
    then x.entry.domain
    else catalogue.trackers.${x.entry.serves}.domain;

  namespaceOf = x:
    if x.w.namespace != null
    then x.w.namespace
    else x.platform.namespaces.${domainOf x};

  sharedStateKeys = entry: w:
    lib.filter (key: entry.state ? ${key}) (lib.attrNames w.state);

  # The legacy state shape has only claim and hostPath. It is deliberately redeclared after the
  # common factory state option is disabled, then translated here.
  stateOf = entry: w:
    lib.mapAttrs
      (key: backing: {
        mountPath = entry.state.${key};
        inherit (backing) claim hostPath hostPathType readOnly;
      })
      (lib.getAttrs (sharedStateKeys entry w) w.state);

  varsFromSecret = w: secret:
    lib.mapAttrs (_: ref: ref.key)
      (lib.filterAttrs (_: ref: ref.secret == secret) w.secretEnv);

  secretNamesOf = w:
    lib.unique (w.envFromSecrets ++ lib.mapAttrsToList (_: ref: ref.secret) w.secretEnv);

  secretsOf = w:
    lib.listToAttrs (map
      (secret: lib.nameValuePair secret (
        { inherit secret; }
        // lib.optionalAttrs (lib.elem secret w.envFromSecrets) { envFrom = true; }
        // lib.optionalAttrs (varsFromSecret w secret != { }) { env = varsFromSecret w secret; }
      ))
      (secretNamesOf w));

  extendApp = { entry, w, app, ... }:
    app // {
      state = stateOf entry w;
      secrets = secretsOf w;
    };

  backingType = lib.types.submodule {
    options = {
      claim = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Name of an existing PersistentVolumeClaim backing this directory. Nothing here creates it.
        '';
      };
      hostPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path on the node backing this directory instead of a claim. It pins the workload to the
          node that holds the path.
        '';
      };
      hostPathType = lib.mkOption {
        type = lib.types.enum [ "Directory" "DirectoryOrCreate" ];
        default = "Directory";
        description = ''
          Whether a missing node path is an error or is created empty. Directory is deliberately
          the default: every application here can initialise an empty store and look healthy.
        '';
      };
      readOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Mount this directory read-only.";
      };
    };
  };

  secretRefType = lib.types.submodule {
    options = {
      secret = lib.mkOption {
        type = lib.types.str;
        description = "Name of an existing Secret. A name, never a value.";
      };
      key = lib.mkOption {
        type = lib.types.str;
        description = "Which key inside that Secret carries this variable.";
      };
    };
  };

  # These declarations overlay enabled common options to retain nixhome's existing contract, and
  # redeclare namespace/state after those incompatible common shapes are structurally disabled.
  legacyOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to render this workload. Declaring the attribute declares the workload, so this
        defaults to true; set false to park a declaration without rendering it.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      example = "1.2.3";
      description = ''
        Which version this workload runs, used as the image tag. It is required and has no default:
        two applications here migrate their schema on start.
      '';
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Whole image reference, replacing the catalogue repository plus version. Null builds the
        reference from those two halves.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Namespace override. Null takes nixhome.homePlatform.namespaces for this workload's domain.
      '';
    };

    createNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this workload anchors its namespace. At most one workload may anchor a namespace.
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
      description = "Position this workload claims in the fleet's ordered identity space.";
    };

    exposure = lib.mkOption {
      type = lib.types.enum [ "internal" "nb" "public" ];
      default = "internal";
      description = "Who can reach this workload, as a class and never an address.";
    };

    scaling = lib.mkOption {
      type = lib.types.enum [ "always" "scale-to-zero" ];
      default = "always";
      description = "Whether the workload always runs or may idle at zero replicas.";
    };

    state = lib.mkOption {
      type = lib.types.attrsOf backingType;
      default = { };
      description = ''
        What backs each directory this application writes, keyed by the catalogue's own name for it.
        Every catalogue directory must appear.
      '';
    };

    secretEnv = lib.mkOption {
      type = lib.types.attrsOf secretRefType;
      default = { };
      example = lib.literalExpression ''
        { EXAMPLE_APPLICATION_PIN = { secret = "example-secret"; key = "pin"; }; }
      '';
      description = ''
        Environment variables sourced from individual Secret keys. No secret value passes through
        Nix or the rendered tree.
      '';
    };

    envFromSecrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Names of existing Secrets loaded wholesale into the environment.";
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra plain environment, merged over the catalogue environment.";
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra entrypoint arguments, appended to the catalogue arguments.";
    };
  };

  companionOptions = {
    serves = lib.mkOption {
      type = lib.types.str;
      description = ''
        Declaration in nixhome.trackers this companion feeds. It must exist and run the catalogue
        tracker this companion actually speaks to.
      '';
    };

    reaches = lib.mkOption {
      type = lib.types.enum [ "in-cluster" "front" ];
      default = "in-cluster";
      description = ''
        How the companion reaches its tracker. A companion cannot use the in-cluster Service when
        that tracker scales to zero, because that path does not pass through the wake front.
      '';
    };
  };

  disabledOptions = [
    "manifests"
    "companionImages"
    "companionResources"
    "initImages"
    "objectName"
    "replicas"
    "image"
    "namespace"
    "wake"
    "adopt"
    "harden"
    "state"
    "probes"
    "resources"
    "credentials"
    "requires"
    "publicUrl"
    "identity"
  ];

  # image is deliberately in both sets: its legacy shape is compatible with imageOf, while marking
  # the common option disabled keeps the factory's newer whole-reference warning out of nixhome's
  # established warning contract. namespace and state are the two incompatible legacy shapes whose
  # translation and guards are owned above.

  showList = list: lib.concatMapStringsSep ", " (name: "`${name}`") list;

  coversWholesale = w: w.envFromSecrets != [ ];
  namedVars = w: lib.attrNames w.secretEnv;
  uncovered = x:
    if coversWholesale x.w
    then [ ]
    else lib.subtractLists (namedVars x.w) x.entry.requiredSecretEnv;

  trackerWorkloads = workloads: lib.filter (x: x.root == "trackers") workloads;
  companionWorkloads = workloads: lib.filter (x: x.root == "companions") workloads;
  servedBy = workloads: x:
    lib.filter (tracker: tracker.name == x.w.serves) (trackerWorkloads workloads);

  stateAssertions = workloads: lib.concatMap
    (x:
      let
        inherit (x) name w entry;
      in
      [
        {
          assertion = lib.attrNames w.state == lib.attrNames entry.state;
          message =
            "nixhome: `${name}` must back every directory it writes, and backs "
            + (if w.state == { } then "none" else showList (lib.attrNames w.state))
            + ". It writes: "
            + lib.concatStringsSep ", " (lib.mapAttrsToList (key: path: "`${key}` at ${path}") entry.state)
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
          assertion = uncovered x == [ ];
          message =
            "nixhome: `${name}` cannot be correct without " + showList entry.requiredSecretEnv
            + " in its environment, and nothing here supplies " + showList (uncovered x)
            + ". Name the variable in `secretEnv` (a Secret and a key, never a value), or load a whole "
            + "Secret with `envFromSecrets`. See that entry's own note in lib/trackers.nix for what the "
            + "variable is and what goes wrong when it is absent or changes.";
        }
      ])
    workloads;

  companionAssertions = workloads: lib.concatMap
    (x:
      let
        inherit (x) name w entry;
        served = servedBy workloads x;
        declaredTrackers = map (tracker: tracker.name) (trackerWorkloads workloads);
      in
      [
        {
          assertion = served != [ ];
          message =
            "nixhome: companion `${name}` serves `${w.serves}`, which is not a tracker declared in "
            + "`nixhome.trackers` (declared: "
            + (if declaredTrackers == [ ] then "none" else showList declaredTrackers)
            + "). A companion keeps no record of its own -- every action it takes lands in the tracker's "
            + "database -- so one deployed beside nothing writes to nothing.";
        }
        {
          assertion = served == [ ] || (lib.head served).w.tracker == entry.serves;
          message =
            "nixhome: companion `${name}` serves declaration `${w.serves}`, which runs "
            + "`${lib.concatMapStringsSep "" (tracker: tracker.w.tracker) served}` -- but this companion "
            + "feeds `${entry.serves}` and speaks nothing else. Point it at a declaration of that application.";
        }
        {
          assertion =
            served == [ ]
            || w.reaches == "front"
            || (lib.head served).w.scaling != "scale-to-zero";
          message =
            "nixhome: companion `${name}` reaches `${w.serves}` in-cluster, and "
            + "`${w.serves}` is declared `scale-to-zero`. A wake front stands in front of the address "
            + "the outside world uses, not in front of the Service -- so this request arrives at a "
            + "Deployment with no pods, nothing wakes it, and the write is lost while both workloads "
            + "report healthy. Either set `reaches = \"front\"` and configure the companion with the "
            + "same address everything else uses (which lets BOTH of them idle at zero), or take "
            + "`${w.serves}` off scale-to-zero.";
        }
      ])
    (companionWorkloads workloads);

  householdAssertions = workloads:
    let
      ordered = orderedWorkloads workloads;
      usedNamespaces = lib.unique (map namespaceOf ordered);
      declaredDomains = lib.unique (map domainOf ordered);
      domainsIn = namespace:
        lib.filter
          (domain: lib.any (x: domainOf x == domain && namespaceOf x == namespace) ordered)
          declaredDomains;
    in
    lib.concatMap
      (namespace: [
        {
          assertion = !(lib.elem namespace catalogueNames);
          message =
            "nixhome: namespace `${namespace}` is the name of an application this catalogue holds. "
            + "A namespace named after one of the things inside it reads as though that thing defined "
            + "the group, and the next application filed there gets filed by resemblance rather than "
            + "by the rule. The domains are " + showList domains
            + " -- name the namespace for what the group IS.";
        }
        {
          assertion = lib.length (domainsIn namespace) <= 1;
          message =
            "nixhome: namespace `${namespace}` holds workloads from more than one domain: "
            + showList (domainsIn namespace)
            + ". The domains are what separates the record of WHAT YOU KEEP from the record of what "
            + "runs out and what comes round, and one namespace holding both is the split written down "
            + "and not acted on. Give each domain its own namespace in "
            + "`nixhome.homePlatform.namespaces`.";
        }
      ])
      usedNamespaces;

  legacyAssertions = workloads:
    let ordered = orderedWorkloads workloads;
    in stateAssertions ordered ++ companionAssertions ordered ++ householdAssertions ordered;

  legacyWarnings = workloads:
    let
      ordered = orderedWorkloads workloads;
      creatorsOf = namespace:
        map (x: x.name)
          (lib.filter (x: x.w.createNamespace && namespaceOf x == namespace) ordered);
      usedNamespaces = lib.unique (map namespaceOf ordered);
    in
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
      ordered
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
      ordered
    ++ map
      (namespace: {
        when = creatorsOf namespace == [ ];
        message =
          "nixhome: nothing declared here anchors namespace `${namespace}`, so it must already "
          + "exist or be created by the tenancy layer. That is a perfectly good arrangement -- it is "
          + "the better one for a namespace that outlives every workload in it -- but a render into a "
          + "namespace nobody created fails at sync rather than at eval, which is a long way from the cause.";
      })
      usedNamespaces;

  reportsOf = workloads:
    let
      ordered = orderedWorkloads workloads;
      declaredDomains = lib.unique (map domainOf ordered);
    in
    {
      nixhome = {
        slots = lib.listToAttrs
          (map
            (x: lib.nameValuePair x.name x.w.slot)
            (lib.filter (x: x.w.slot != null) ordered));
        domains = lib.listToAttrs
          (map (x: lib.nameValuePair x.name (domainOf x)) ordered);
        namespaces = lib.listToAttrs
          (map
            (domain:
              lib.nameValuePair domain
                (namespaceOf (lib.head (lib.filter (x: domainOf x == domain) ordered))))
            declaredDomains);
        dormantWhileAsleep = map (x: x.name)
          (lib.filter
            (x: x.entry.background != null && x.w.scaling == "scale-to-zero")
            ordered);
      };
    };

  reportOptions = {
    slots = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      readOnly = true;
      description = "Workload to the fleet slot it claims.";
    };
    domains = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Workload to its catalogue domain.";
    };
    namespaces = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Declared domain to the namespace it resolved to.";
    };
    dormantWhileAsleep = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Sleeping workloads whose background work stops while they are at zero.";
    };
  };

  factoryModule = mkConsumerModule {
    namespace = "nixhome";
    platformOption = "homePlatform";

    extraPlatformOptions.namespaces = lib.mkOption {
      description = ''
        Namespace for each catalogue domain. Each domain option has no default, so a workload forces
        the consumer to choose where that domain lands.
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

    extraNamespaceOptions = reportOptions;

    roots = {
      trackers = {
        catalogue = catalogue.trackers;
        selector = "tracker";
        inherit disabledOptions;
        extraOptions = legacyOptions;
        inherit namespaceOf;
        extend = extendApp;
        description = ''
          The household's authoritative records, keyed by a declaration name. The selected tracker's
          catalogue domain decides its namespace.
        '';
      };

      companions = {
        catalogue = catalogue.companions;
        selector = "companion";
        inherit disabledOptions;
        extraOptions = legacyOptions // companionOptions;
        inherit namespaceOf;
        extend = extendApp;
        description = ''
          Workloads that feed a declared tracker and keep no authoritative household record of their
          own. They inherit the domain of the tracker their catalogue entry serves.
        '';
      };
    };

    extraAssertions = legacyAssertions;
    extraWarnings = legacyWarnings;
    extraConfig = reportsOf;
  };
in
{
  imports = [ factoryModule ];

  # Preserve nixhome's resolved project default. The pending factory API owns this built-in option,
  # so this is a module default rather than duplicate option-declaration metadata.
  config.nixhome.homePlatform.project = lib.mkOptionDefault "default";
}
