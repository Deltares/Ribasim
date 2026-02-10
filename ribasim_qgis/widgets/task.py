"""QgsTask for running Ribasim simulations in the background."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

from PyQt5.QtCore import pyqtSignal
from qgis.core import Qgis, QgsMessageLog, QgsTask


class RibasimTask(QgsTask):
    """QgsTask for running Ribasim simulations in the background.

    This task runs the Ribasim CLI subprocess, parses progress from stdout,
    and emits signals to update the UI on the main thread.

    https://docs.qgis.org/3.40/en/docs/pyqgis_developer_cookbook/tasks.html
    """

    # Signals must be defined on a QObject, QgsTask inherits from QObject
    output_received = pyqtSignal(str, bool)  # (line, replace)
    task_completed = pyqtSignal(bool)  # success

    def __init__(self, cli: str, toml_path: str):
        model_path = Path(toml_path)
        # "path/to/basic/ribasim.toml" -> "basic/ribasim"
        model_name = f"{model_path.parent.stem}/{model_path.stem}"
        super().__init__(
            f"Ribasim simulation - {model_name}",
            QgsTask.CanCancel,  # type: ignore[attr-defined]
        )
        self.cli = cli
        self.toml_path = toml_path
        self.exit_code: int | None = None
        self.process: subprocess.Popen[str] | None = None
        self.was_canceled = False

    def run(self) -> bool:
        """Run the Ribasim CLI subprocess (executes in background thread)."""
        try:
            # Hide console window on Windows
            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

            with subprocess.Popen(
                [self.cli, self.toml_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                bufsize=1,
                creationflags=creationflags,
            ) as proc:
                self.process = proc
                first_simulating_seen = False
                if proc.stdout:
                    for line in proc.stdout:
                        if self.isCanceled():
                            proc.terminate()
                            self.was_canceled = True
                            return False
                        line = line.rstrip()

                        # Parse progress percentage from lines like:
                        # "Simulating ━━━━━━━━━━  42% 0:01:23"
                        is_simulating = line.startswith("Simulating")
                        replace = is_simulating and first_simulating_seen
                        if is_simulating:
                            first_simulating_seen = True
                            match = re.search(r"(\d+)%", line)
                            if match:
                                self.setProgress(int(match.group(1)))

                        # Emit signal to update UI (will be received on main thread)
                        self.output_received.emit(line, replace)

                proc.wait()
                self.exit_code = proc.returncode
                return proc.returncode == 0

        except Exception as e:
            QgsMessageLog.logMessage(
                f"Error running Ribasim: {e}", "Ribasim", Qgis.MessageLevel.Critical
            )
            self.exit_code = -1
            return False

    def finished(self, result: bool) -> None:
        """Emit completion signal on the main thread."""
        self.task_completed.emit(result)
