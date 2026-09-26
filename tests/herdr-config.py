import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

assert config == {
    "onboarding": False,
    "theme": {"name": "catppuccin"},
    "keys": {"prefix": "ctrl+a"},
    "ui": {
        "sidebar": {
            "agents": {
                "rows": [
                    ["state_icon", "workspace", "tab"],
                    ["agent", "state_text"],
                ]
            }
        }
    },
}
