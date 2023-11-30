pkgs: test:
let
  inherit (pkgs.lib) mapAttrsToList concatStringsSep genAttrs;
  inherit (builtins) attrNames;

  interactiveConfig = {
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
  };

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
  rebuildScript = pkgs.writeShellScript "rebuild-test.sh" ''
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

  # NOTE: This is awkward because we're using attrsets and // for something that
  # should really use a module system. Alas, there's no multi-machine modules in
  # nixos. We really just want to add "interactiveConfig" to all modules.
  rebuildableTest = pkgs.nixosTest (test // {
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
  # TODO: put rebuildScript and sshConfig in driverInteractive
in
rebuildableTest

