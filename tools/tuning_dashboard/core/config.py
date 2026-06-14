import os
import tempfile
import yaml
from dotenv import load_dotenv
from pathlib import Path

_DASHBOARD_DIR = Path(__file__).parent.parent
_CONFIG_PATH = _DASHBOARD_DIR / "routing_config.yaml"

load_dotenv(_DASHBOARD_DIR / ".env")


def load_config() -> dict:
    with open(_CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def save_config(cfg: dict) -> None:
    tmp = _CONFIG_PATH.with_suffix(".yaml.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        yaml.dump(cfg, f, allow_unicode=True, sort_keys=False)
    os.replace(tmp, _CONFIG_PATH)
    print(f"[config] saved → {_CONFIG_PATH}")
