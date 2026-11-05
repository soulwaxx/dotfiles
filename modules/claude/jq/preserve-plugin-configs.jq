# Input: checked-in settings; $live[0]: current user settings.
# Runtime plugin preferences survive activation unless the repo overrides them.
if type != "object" or ($live[0] | type) != "object" then
  error("Claude settings must be JSON objects")
else
  (.pluginConfigs // {}) as $declared
  | ($live[0].pluginConfigs // {}) as $runtime
  | if ($declared | type) != "object" or ($runtime | type) != "object" then
      error("Claude pluginConfigs must be JSON objects")
    else
      .pluginConfigs = ($runtime * $declared)
    end
end
