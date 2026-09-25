{
  pkgs,
  lib,
  config,
  ...
}:
let
  k9sSkin = config.dotfiles.theme.current.k9sSkin;
  p = config.dotfiles.theme.current.palette;
  k9sConfigDir =
    if pkgs.stdenv.hostPlatform.isDarwin then "Library/Application Support/k9s" else ".config/k9s";
  mkFblogPlugin =
    {
      scope,
      logsCommand,
      expanded ? false,
    }:
    {
      shortCut = if expanded then "Shift-K" else "Shift-L";
      confirm = false;
      description = if expanded then "Follow logs expanded" else "Follow logs";
      scopes = [ scope ];
      command = "sh";
      background = false;
      args = [
        "-c"
        "${logsCommand} | fblog${lib.optionalString expanded " -d"}"
      ];
    };
in
lib.mkIf config.dotfiles.kubernetes.enable {
  home.activation.installKrewPlugins = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _krew="${pkgs.krew}/bin/krew"
      if ! "$_krew" list 2>/dev/null | grep -q "^modify-secret$"; then
        verboseEcho "[k9s] installing krew plugin: modify-secret"
        run "$_krew" update 2>/dev/null || true
        run "$_krew" install modify-secret 2>/dev/null || \
          echo "[k9s] krew install modify-secret failed — run manually when online" >&2
      fi
      unset _krew
    ''
  );

  programs.zsh.shellAliases = {
    ks = "k9s";
    ksr = "k9s --readonly";
  };

  programs.k9s = {
    enable = true;
    settings.k9s = {
      ui = {
        headless = false;
        logoless = true;
        noIcons = false;
        skin = k9sSkin;
      };
      skipLatestRevCheck = true;
    };

    hotKeys = lib.listToAttrs (
      lib.imap1
        (i: r: {
          name = "f${toString i}";
          value = {
            shortCut = "F${toString i}";
            inherit (r) description command;
          };
        })
        [
          {
            description = "Pods";
            command = "pods";
          }
          {
            description = "Deployments";
            command = "deployments";
          }
          {
            description = "Services";
            command = "services";
          }
          {
            description = "Ingresses";
            command = "ingresses";
          }
          {
            description = "Secrets";
            command = "secrets";
          }
          {
            description = "Namespaces";
            command = "namespaces";
          }
          {
            description = "Contexts";
            command = "contexts";
          }
        ]
    );

    plugins = {
      fblog-pod = mkFblogPlugin {
        scope = "pods";
        logsCommand = "kubectl logs --follow --context \"$CONTEXT\" -n \"$NAMESPACE\" \"$NAME\"";
      };

      fblog-container = mkFblogPlugin {
        scope = "containers";
        logsCommand = "kubectl logs --follow --context \"$CONTEXT\" -n \"$NAMESPACE\" \"$POD\" -c \"$NAME\"";
      };

      fblog-pod-all = mkFblogPlugin {
        scope = "pods";
        logsCommand = "kubectl logs --follow --context \"$CONTEXT\" -n \"$NAMESPACE\" \"$NAME\"";
        expanded = true;
      };

      fblog-container-all = mkFblogPlugin {
        scope = "containers";
        logsCommand = "kubectl logs --follow --context \"$CONTEXT\" -n \"$NAMESPACE\" \"$POD\" -c \"$NAME\"";
        expanded = true;
      };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      modify-secret = {
        shortCut = "Ctrl-X";
        description = "Edit Decoded Secret";
        confirm = false;
        scopes = [ "secrets" ];
        command = "kubectl";
        background = false;
        args = [
          "modify-secret"
          "--context"
          "$CONTEXT"
          "--namespace"
          "$NAMESPACE"
          "$NAME"
        ];
      };
    };
  };

  # Role mapping mirrors luca-trifilio's Catppuccin skin (filled crumb pills and
  # dialog panel, full accent spread) ported onto this repo's Mocha palette.
  # Body/table/log backgrounds stay 'default' so they inherit the terminal bg.
  home.file."${k9sConfigDir}/skins/${k9sSkin}.yaml".text = ''
    k9s:
      body:
        fgColor: '${p.foreground}'
        bgColor: 'default'
        logoColor: '${p.purple}'
      prompt:
        fgColor: '${p.foreground}'
        bgColor: 'default'
        suggestColor: '${p.blue}'
      help:
        fgColor: '${p.foreground}'
        bgColor: 'default'
        sectionColor: '${p.green}'
        keyColor: '${p.blue}'
        numKeyColor: '${p.maroon}'
      frame:
        title:
          fgColor: '${p.teal}'
          bgColor: 'default'
          highlightColor: '${p.pink}'
          counterColor: '${p.yellow}'
          filterColor: '${p.green}'
        border:
          fgColor: '${p.purple}'
          focusColor: '${p.lavender}'
        menu:
          fgColor: '${p.foreground}'
          keyColor: '${p.blue}'
          numKeyColor: '${p.maroon}'
        crumbs:
          fgColor: '${p.background}'
          bgColor: '${p.maroon}'
          activeColor: '${p.flamingo}'
        status:
          newColor: '${p.blue}'
          modifyColor: '${p.lavender}'
          addColor: '${p.green}'
          pendingColor: '${p.orange}'
          errorColor: '${p.red}'
          highlightColor: '${p.cyan}'
          killColor: '${p.purple}'
          completedColor: '${p.comment}'
      info:
        fgColor: '${p.orange}'
        sectionColor: '${p.foreground}'
      views:
        table:
          fgColor: '${p.foreground}'
          bgColor: 'default'
          cursorFgColor: '${p.currentline}'
          cursorBgColor: '${p.surface}'
          markColor: '${p.rosewater}'
          header:
            fgColor: '${p.yellow}'
            bgColor: 'default'
            sorterColor: '${p.cyan}'
        xray:
          fgColor: '${p.foreground}'
          bgColor: 'default'
          cursorColor: '${p.surface}'
          cursorTextColor: '${p.background}'
          graphicColor: '${p.pink}'
        charts:
          bgColor: 'default'
          chartBgColor: 'default'
          dialBgColor: 'default'
          defaultDialColors:
            - '${p.green}'
            - '${p.red}'
          defaultChartColors:
            - '${p.green}'
            - '${p.red}'
          resourceColors:
            cpu:
              - '${p.purple}'
              - '${p.blue}'
            mem:
              - '${p.yellow}'
              - '${p.orange}'
        yaml:
          keyColor: '${p.blue}'
          valueColor: '${p.foreground}'
          colonColor: '${p.subtext0}'
        logs:
          fgColor: '${p.foreground}'
          bgColor: 'default'
          indicator:
            fgColor: '${p.lavender}'
            bgColor: 'default'
            toggleOnColor: '${p.green}'
            toggleOffColor: '${p.subtext0}'
      dialog:
        fgColor: '${p.yellow}'
        bgColor: '${p.overlay2}'
        buttonFgColor: '${p.background}'
        buttonBgColor: '${p.overlay1}'
        buttonFocusFgColor: '${p.background}'
        buttonFocusBgColor: '${p.pink}'
        labelFgColor: '${p.rosewater}'
        fieldFgColor: '${p.foreground}'
  '';
}
