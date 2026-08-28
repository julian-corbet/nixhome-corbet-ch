{
  description = "nixhome — the self-hosted applications that run a household: what you own, what you have to restock, and what has to get done";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The renderer this module defines into. A real input rather than a name in a comment: without
    # it there is no module system to evaluate against, and `nix flake check` would pass by checking
    # nothing.
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # THE APP GRAMMAR AND ITS CONSUMER FACTORY. Consumers still import the app module alongside
    # nixhome; the exported nixhome module is now built from the same factory that translates the
    # rest of the catalogue family.
    nixk3s = {
      url = "github:julian-corbet/nixk3s-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixidy.follows = "nixidy";
    };
  };

  outputs = { self, nixpkgs, nixidy, nixk3s }:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # The one plane this repository has. Composed into a nixidy environment ALONGSIDE the app
      # grammar, which declares the options this module defines into -- see modules/cluster.nix's
      # own header.
      nixidyModules.nixhome = import ./modules/cluster.nix {
        catalogue = self.lib.trackers;
        mkConsumerModule = nixk3s.lib.mkConsumerModule;
      };
      nixidyModules.default = self.nixidyModules.nixhome;

      # NO `nixosModules` AND NO `systemManagerModules`, and that is a statement rather than a gap.
      # A household's record lives in a cluster and is read through a browser; there is no command
      # line to install on a workstation, so there is no host plane to declare and no package this
      # repository claims from any host's catalogue.

      # The module and the raw catalogue, for a consumer that wants to inspect either without
      # re-reading the files.
      lib.cluster = self.nixidyModules.nixhome;
      lib.trackers = import ./lib/trackers.nix { };

      # `nix flake check` evaluates none of the module outputs on its own, so a green check on this
      # repository without these three files would cover nothing but flake syntax.
      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          # This module, rendered through the real grammar and the real renderer, from the
          # placeholder values in examples/. Building the environment package forces the whole
          # manifest tree.
          env = nixidy.lib.mkEnv {
            inherit pkgs;
            modules = [
              nixk3s.nixidyModules.apps
              nixk3s.nixidyModules.addressing
              self.nixidyModules.nixhome
              ./examples/all/values.nix
            ];
          };
        in
        {
          # 1. The catalogue's own integrity, and the naming rule made mechanical.
          catalogue-eval = import ./checks/catalogue-eval.nix { inherit pkgs lib; };

          # 2. The module's resolution and every guard it makes, in BOTH directions: an empty
          # household renders nothing at all, a declared one resolves, and each refusal gets a
          # declaration that must be refused.
          cluster-eval = import ./checks/cluster-eval.nix {
            inherit pkgs lib nixidy;
            catalogue = self.lib.trackers;
            appsModule = nixk3s.nixidyModules.apps;
            addressingModule = nixk3s.nixidyModules.addressing;
            clusterModule = self.nixidyModules.nixhome;
          };

          # 3. The manifests it actually PRODUCED, parsed and asserted field by field. A module that
          # type-checks can still render an application whose Service targets a port nothing listens
          # on, or whose store is mounted somewhere the application does not write -- none of that
          # is an eval error, and the second one presents an empty inventory as the truth.
          cluster-render = import ./checks/cluster-render.nix { inherit pkgs lib env; };
        });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
