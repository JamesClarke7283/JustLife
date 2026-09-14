"""Backwards-compatible Linux entry point for the desktop release exporter."""

from pathlib import Path
from export_game import run as export_game


def run():
    export_game(
        default_platform="linux",
        default_output=Path(__file__).resolve().parents[1] / "dist/JustLife",
    )


if __name__ == "__main__":
    run()
