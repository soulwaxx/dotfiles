{
  config,
  lib,
  ...
}:
let
  dotfilesPathExpr = config.dotfiles.pathShellExpr;
in
{
  imports = [
    ../ssh-allowed-signers.nix
  ];

  ssh.allowedSigners = [
    {
      # Work email comes from user.email in ~/.gitconfig.local.
      keyFile = "${config.home.homeDirectory}/.ssh/git.pub";
    }
    {
      emailConfigFile = "${config.home.homeDirectory}/.gitconfig.personal";
      keyFile = "${config.home.homeDirectory}/.ssh/git_personal.pub";
    }
  ];

  programs = {
    zsh.initContent = ''
      # Work-specific shell functions — guarded so missing dotfiles checkout doesn't break shell.
      _work_functions_dir="${dotfilesPathExpr}/modules/host-specific/work-functions"
      if [[ -d "$_work_functions_dir" ]]; then
        for _work_functions_file in "$_work_functions_dir"/*.zsh(N); do
          if [[ -r "$_work_functions_file" ]]; then
            source "$_work_functions_file"
          fi
        done
        unset _work_functions_file
      else
        echo "work: work-functions directory not readable at $_work_functions_dir; shell functions unavailable" >&2
      fi
      unset _work_functions_dir
    '';

    git = {
      # Override identity for repos cloned through the personal GitHub SSH alias.
      # Work identity (user.name, user.email, user.username) lives in untracked
      # ~/.gitconfig.local, personal identity in untracked ~/.gitconfig.personal.
      # Listed first so the personal overrides below win.
      includes = [
        { path = "~/.gitconfig.local"; }
        {
          condition = "hasconfig:remote.*.url:git@github.com-personal:*/**";
          path = "~/.gitconfig.personal";
        }
        {
          condition = "hasconfig:remote.*.url:git@github.com-personal:*/**";
          contents.user.signingkey = "~/.ssh/git_personal.pub";
        }
      ];

      # SSH commit signing
      settings = {
        "gpg \"ssh\"".allowedSignersFile = "~/.ssh/allowed_signers";
      };
      signing = {
        key = "~/.ssh/git.pub";
        format = "ssh";
        signByDefault = true;
      };
    };

    # SSH config — managed declaratively so fresh bootstraps get the right keys
    ssh = {
      matchBlocks = {
        # Work GitHub (default identity)
        "github.com" = lib.hm.dag.entryBefore [ "i-* mi-*" ] {
          user = "git";
          identitiesOnly = true;
          addKeysToAgent = "yes";
          identityFile = "~/.ssh/git";
          extraOptions.UseKeychain = "yes";
        };

        # Personal GitHub — use a remote alias:
        #   git clone git@github.com-personal:user/repo.git
        "github.com-personal" = lib.hm.dag.entryBefore [ "i-* mi-*" ] {
          hostname = "github.com";
          user = "git";
          identitiesOnly = true;
          addKeysToAgent = "yes";
          identityFile = "~/.ssh/git_personal";
          extraOptions.UseKeychain = "yes";
        };

        # SSH over AWS SSM Session Manager.
        # StrictHostKeyChecking=no + UserKnownHostsFile=/dev/null are safe here:
        # SSM authenticates the target instance at the tunnel layer (IAM + SSM
        # agent), so the SSH host key offers no additional trust. Skipping the
        # known_hosts dance also avoids churn from instance-ID-based hostnames.
        "i-* mi-*" = {
          user = "ec2-user";
          identitiesOnly = true;
          identityFile = "~/.ssh/git";
          proxyCommand = "sh -c \"aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\"";
          extraOptions = {
            StrictHostKeyChecking = "no";
            UserKnownHostsFile = "/dev/null";
          };
        };
      };
    };
  };
}
