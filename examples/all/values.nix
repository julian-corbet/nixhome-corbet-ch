# Placeholder values for the cluster module — the file that makes the render check real.
# `nix flake check` renders the whole household from here, so a module that stops evaluating, or
# that grows a required value nobody supplies, fails in CI rather than in somebody's cluster.
#
# NOTHING HERE IS REAL. Every namespace, path, name, number, identity and image is invented for this
# file, and no credential appears in any form — only the NAMES of Secrets that would hold them.
#
# The declarations are chosen to cover the paths that differ in what gets RENDERED or GOVERNED
# rather than merely in what evaluates:
#
#   - both domains, in two namespaces, each anchored by exactly one workload;
#   - an application that must run as root and takes its whole access model from one named Secret
#     key, beside one that runs as a supplied UID and needs a named key of a very different kind;
#   - an application that reads its identity numbers from POLICY environment the catalogue refuses
#     to supply, and whose probe is a TCP connect because it has no cheap health endpoint;
#   - an application with TWO state directories, one nested inside the other in the layout its image
#     ships, and a scheduler that stops while it sleeps;
#   - a COMPANION that keeps no record of its own, serving a tracker that idles at zero — so it has
#     to arrive through the same front everything else uses, which is the one arrangement that lets
#     both of them sleep.
{
  # Required by the nixidy environment itself, not by any module here.
  nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
  nixidy.target.branch = "main";

  # A cluster fact the app grammar refuses to guess: which node holds the directories that node-path
  # state lives on. Set once here instead of on every workload.
  nixk3s.appPlatform.hostPathNodeSelector = { "kubernetes.io/hostname" = "example-node"; };

  # The band model, with the layout a consumer would supply. Every value is invented: the model
  # ships no band, no base and no binding, because which category owns which run of the number space
  # is the shape of somebody's fleet.
  nixk3s.addressing = {
    enable = true;
    bands.example-personal = {
      base = 64;
      size = 16;
      description = "the applications a person runs for themselves";
    };
    bindings.nixhome = "example-personal";
  };

  nixhome.homePlatform = {
    # ONE NAMESPACE PER DOMAIN. Two domains sharing one is refused, and a namespace named after an
    # application inside it is refused — a household that likes the domain names may simply reuse
    # them, which is not what this file does only because everything in it is deliberately invented.
    namespaces = {
      belongings = "example-belongings";
      housekeeping = "example-housekeeping";
    };
    project = "example-home";
    # Hands every workload's slot to the band model above. Null (the default) everywhere that model
    # is not part of the render.
    origin = "nixhome";
  };

  nixhome.trackers = {
    # ── belongings: one row per thing you own ──────────────────────────────────────────────────
    #
    # The asset tracker. Anchors its domain's namespace, and takes its whole access model from a
    # single named key: there are no accounts here, so this Secret is the door.
    example-assets = {
      tracker = "dumbassets";
      version = "0.0.0";
      slot = 64;
      exposure = "public";
      createNamespace = true;
      state.data.hostPath = "/example/state/assets";
      secretEnv.DUMBASSETS_PIN = { secret = "example-assets"; key = "pin"; };
    };

    # The home inventory, beside it and deliberately so: same domain, same question, a different
    # answer to it. Pinned by digest, which is what the grammar asks for and what the workloads
    # below deliberately do not do.
    example-inventory = {
      tracker = "homebox";
      version = "0.0.0";
      image = "registry.example.com/example-org/example-inventory:0.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000";
      slot = 65;
      exposure = "public";
      state.data.hostPath = "/example/state/inventory";
      # Named rather than loaded wholesale, so its absence is caught here instead of in a startup
      # log. A different value invalidates every session and every API key while leaving the
      # inventory itself untouched — see the catalogue entry.
      secretEnv.HBOX_AUTH_API_KEY_PEPPER = { secret = "example-inventory"; key = "pepper"; };
    };

    # ── housekeeping: what runs out, and what comes round ──────────────────────────────────────
    #
    # The household ERP. Anchors the second namespace, idles at zero (everything it computes is
    # computed in answer to a request, so there is nothing to miss), and reads its identity numbers
    # from environment the catalogue refuses to supply, because a UID is a value.
    example-groceries = {
      tracker = "grocy";
      version = "0.0.0";
      slot = 66;
      exposure = "public";
      scaling = "scale-to-zero";
      createNamespace = true;
      state.config.hostPath = "/example/state/groceries";
      env = {
        PUID = "1234";
        PGID = "1234";
        TZ = "UTC";
      };
    };

    # The chore tracker. TWO directories — the configuration file it reads at startup and the
    # database it writes forever — and the second is nested inside the first in the layout its image
    # ships, which is exactly the arrangement that invites backing only the outer one.
    #
    # Declared scale-to-zero ON PURPOSE here, so the render exercises the warning: this is the one
    # workload in the catalogue with a scheduler, and at zero it is not evaluating what is due.
    example-chores = {
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

  # A companion: no record of its own, every scan a stock movement in the ERP's database. It serves
  # a tracker that idles at zero, so `reaches = "front"` is not a preference — the in-cluster route
  # is refused at eval, because a request to a Deployment with no pods wakes nothing and the write
  # is simply lost.
  nixhome.companions.example-scanner = {
    companion = "barcodebuddy";
    serves = "example-groceries";
    version = "0.0.0";
    slot = 68;
    exposure = "public";
    scaling = "scale-to-zero";
    reaches = "front";
    state.config.hostPath = "/example/state/groceries/scanner";
  };
}
