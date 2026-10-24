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
  # Role mapping mirrors luca-trifilio's Catppuccin skin (filled crumb pills and
  # dialog panel, full accent spread) ported onto this repo's Mocha palette.
  # Body/table/log backgrounds stay 'default' so they inherit the terminal bg.
  mkSkin = production: ''
    k9s:
      body:
        fgColor: '${p.text}'
        bgColor: 'default'
        logoColor: '${p.mauve}'
      prompt:
        fgColor: '${p.text}'
        bgColor: 'default'
        suggestColor: '${p.blue}'
      help:
        fgColor: '${p.text}'
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
          fgColor: '${if production then p.red else p.mauve}'
          focusColor: '${if production then p.red else p.lavender}'
        menu:
          fgColor: '${p.text}'
          keyColor: '${p.blue}'
          numKeyColor: '${p.maroon}'
        crumbs:
          fgColor: '${p.base}'
          bgColor: '${if production then p.red else p.maroon}'
          activeColor: '${p.flamingo}'
        status:
          newColor: '${p.blue}'
          modifyColor: '${p.lavender}'
          addColor: '${p.green}'
          pendingColor: '${p.peach}'
          errorColor: '${p.red}'
          highlightColor: '${p.sky}'
          killColor: '${p.mauve}'
          completedColor: '${p.overlay0}'
      info:
        fgColor: '${p.peach}'
        sectionColor: '${p.text}'
      views:
        table:
          fgColor: '${p.text}'
          bgColor: 'default'
          cursorFgColor: '${p.surface0}'
          cursorBgColor: '${p.surface1}'
          markColor: '${p.rosewater}'
          header:
            fgColor: '${p.yellow}'
            bgColor: 'default'
            sorterColor: '${p.sky}'
        xray:
          fgColor: '${p.text}'
          bgColor: 'default'
          cursorColor: '${p.surface1}'
          cursorTextColor: '${p.base}'
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
              - '${p.mauve}'
              - '${p.blue}'
            mem:
              - '${p.yellow}'
              - '${p.peach}'
        yaml:
          keyColor: '${p.blue}'
          valueColor: '${p.text}'
          colonColor: '${p.subtext0}'
        logs:
          fgColor: '${p.text}'
          bgColor: 'default'
          indicator:
            fgColor: '${p.lavender}'
            bgColor: 'default'
            toggleOnColor: '${p.green}'
            toggleOffColor: '${p.subtext0}'
      dialog:
        fgColor: '${p.yellow}'
        bgColor: '${p.overlay2}'
        buttonFgColor: '${p.base}'
        buttonBgColor: '${p.overlay1}'
        buttonFocusFgColor: '${p.base}'
        buttonFocusBgColor: '${p.pink}'
        labelFgColor: '${p.rosewater}'
        fieldFgColor: '${p.text}'
  '';
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
        "${logsCommand} --tail=500 | fblog${lib.optionalString expanded " -d"}"
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

  programs.zsh.initContent = ''
    ks() {
      local contexts context
      contexts=$(kubectl config get-contexts -o name) || return
      context=$(print -r -- "$contexts" | \
        fzf --prompt='Kubernetes context > ' --height=50% --border) || return
      [[ -n "$context" ]] || return 0
      # Contexts authenticate through their kubeconfig AWS_PROFILE; inherited
      # awsp credentials would take precedence, so drop them for k9s only.
      env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY \
        -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN \
        k9s --context "$context" "$@"
    }

    ksr() {
      ks --readonly "$@"
    }
  '';

  programs.k9s = {
    enable = true;
    skins."${k9sSkin}-production" = pkgs.writeText "${k9sSkin}-production.yaml" (mkSkin true);
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
        confirm = true;
        dangerous = true;
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

  home.file."${k9sConfigDir}/skins/${k9sSkin}.yaml".text = mkSkin false;
}
