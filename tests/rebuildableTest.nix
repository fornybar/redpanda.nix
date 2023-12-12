pkgs: test:
let
  inherit (pkgs.lib) mapAttrsToList concatStringsSep genAttrs mkIf;
  inherit (builtins) attrNames;

  interactiveConfig = ({ config, ... }: {
    # so we can run `nix shell nixpkgs#foo` on the machines
    nix.extraOptions = ''
      extra-experimental-features = nix-command flakes
    '';

    # so we can ssh in and rebuild them
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        PermitEmptyPasswords = "yes";
        UsePAM = "no";
      };
    };

    virtualisation = mkIf (config.networking.hostName == "jumphost") {
      forwardPorts = [{
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }];
    };
  });

  sshConfig = pkgs.writeText "ssh-config" ''
    Host *
      User root
      StrictHostKeyChecking no
      BatchMode yes
      ConnectTimeout 20
      UserKnownHostsFile=/dev/null
      LogLevel Error # no "added to known hosts"
    Host jumphost
      Port 2222
      HostName localhost
    Host * !jumphost
      ProxyJump jumphost
  '';

  # one should first start up the interactive test driver, then start the
  # machines, then update the config, and then redeploy with the `rebuildScript`
  # associated with the new config.
  rebuildScript = pkgs.writeShellScriptBin "rebuild" ''
    # create an association array from machine names to the path to their
    # configuration in the nix store
    declare -A configPaths=(${
      concatStringsSep " "
        (mapAttrsToList
          (n: v: ''["${n}"]="${v.system.build.toplevel}"'')
          rebuildableTest.driverInteractive.nodes)
    })

    rebuild_one() {
      machine="$1"
      echo "pushing new config to $machine"

      if [ -z ''${configPaths[$machine]+x} ]; then
        echo 'No machine '"$machine"' in this test.'
        exit 1
      fi

      if ! ssh -F ${sshConfig} $machine true; then
        echo 'Couldn'"'"'t connect to '"$machine"'. Make sure you'"'"'ve started it with `'"$machine"'.start()` in the test interactive driver.'
        exit 1
      fi

      # taken from nixos-rebuild (we only want to do the activate part)
       cmd=(
          "systemd-run"
          "-E" "LOCALE_ARCHIVE"
          "--collect"
          "--no-ask-password"
          "--pty"
          "--quiet"
          "--same-dir"
          "--service-type=exec"
          "--unit=nixos-rebuild-switch-to-configuration"
          "--wait"
          "''${configPaths[$machine]}/bin/switch-to-configuration"
          "test"
      )


      if ! ssh -F ${sshConfig} $machine "''${cmd[@]}"; then
          echo "warning: error(s) occurred while switching to the new configuration"
          exit 1
      fi
    }

    if ! ssh -F ${sshConfig} jumphost true; then
      echo 'Couldn'"'"'t connect to jump host. Make sure you are running driverInteractive, and that you'"'"'ve run `jumphost.start()` and `jumphost.forward_port(2222,22)`'
      exit 1
    fi

    if [ -n "$1" ]; then
      rebuild_one "$1"
    else
      for machine in ${concatStringsSep " " (attrNames rebuildableTest.driverInteractive.nodes)}; do
        rebuild_one $machine
      done
    fi
  '';

  # NOTE: This is awkward because NixOS does not expose the module interface
  # that is used to build tests. When we upstream this, we can build it into the
  # system more naturally (and expose more of the interface to end users while
  # we're at it)
  rebuildableTest =
    let
      preOverride = pkgs.nixosTest (test // {
        interactive = (test.interactive or { }) // {
          # no need to // with test.interactive.nodes here, since we are iterating
          # over all of them, and adding back in the config via `imports`
          nodes = genAttrs
            (
              attrNames test.nodes or { } ++
                attrNames test.interactive.nodes or { } ++
                [ "jumphost" ]
            )
            (n: {
              imports = [
                (test.interactive.${n} or { })
                interactiveConfig
              ];
            });
        };
        # override with test.passthru in case someone wants to overwrite us.
        passthru = { inherit rebuildScript sshConfig; } // (test.passthru or { });
      });
    in
    preOverride // {
      driverInteractive = preOverride.driverInteractive.overrideAttrs (old: {
        # this comes from runCommand, not mkDerivation, so this is the only
        # hook we have to override
        buildCommand = old.buildCommand + ''
          ln -s ${sshConfig} $out/ssh-config
          ln -s ${rebuildScript}/bin/rebuild $out/bin/rebuild
        '';
      });
    };
in
rebuildableTest

