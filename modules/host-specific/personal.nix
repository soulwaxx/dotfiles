{
  config,
  ...
}:
{
  imports = [ ../ssh-allowed-signers.nix ];

  ssh.allowedSigners = [
    {
      emailConfigFile = "${config.home.homeDirectory}/.gitconfig.personal";
      keyFile = "${config.home.homeDirectory}/.ssh/git_personal.pub";
    }
  ];

  programs.zsh.shellAliases = {
    probook = "ssh -i ~/.ssh/probook soulwaxx@probook";
    tnas-f2-424 = "ssh -i ~/.ssh/omv omv@tnas-f2-424";
    prd-oci-vm1-arm = "ssh -i ~/.ssh/oci ubuntu@prd-oci-vm1-arm";
  };

  # Personal git identity
  programs.git = {
    includes = [ { path = "~/.gitconfig.personal"; } ];
    settings = {
      "gpg \"ssh\"".allowedSignersFile = "~/.ssh/allowed_signers";
    };
    signing = {
      key = "~/.ssh/git_personal.pub";
      format = "ssh";
      signByDefault = true;
    };
  };
}
