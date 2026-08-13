"""Owns the simu process and the --pipe steering channel: boots the
already-built simu.exe (-DWIDGET_STUDIO=ON, see plan Sec 8/10), dismisses
the one-time first-boot alerts, and drives capture/key commands. Reuses the
engine hooks proven in the Widget Studio Phase 1 spike
(myplans/widget-visual-emulator-plan.md Sec 9a) -- no firmware changes in
this tool.

Model switching is a full process restart (run.py's per-batch loops call
stop() then start(model_marker=...)), not an in-place reset. That is a
deliberate choice, not the obvious one, so it is worth recording once here:
an earlier in-place design -- keep one process running, overwrite
MODELS/model1.yml (or patch RADIO/radio.yml's currModelFilename) for the
next batch, then send a `reset` pipe command -- lost to a confirmed
regression from two directions at once:

  1. The firmware periodically autosaves the CURRENTLY LOADED model and
     general settings back to their files on its own timer, independent of
     anything this driver does. If that autosave landed between this
     driver's write and the firmware processing `reset`, it clobbered the
     freshly written file with a re-save of whatever was already loaded.
     Confirmed directly: simu.log showed model names loading wildly out of
     the order this driver issued them in, with most of ~28 intended
     reloads never appearing at all.
  2. Editing RADIO/radio.yml at all (even just currModelFilename) without
     also setting `manuallyEdited: 1` made the FILE ITSELF fail the
     firmware's checksum check on the next read ("radio settings: Reading
     failed... File is corrupted"), triggering a full storageEraseAll() and
     silently regenerating fresh defaults.

A fresh process reads whatever is on disk at STARTUP with no live
in-memory state left to autosave-clobber it, which is exactly the pattern
every isolated single-model repro in this session rendered correctly on
the first try. The cost is real (~5-10s per restart vs. an in-place
reset), paid deliberately for correctness. See run.py's set_current_model()
for the `manuallyEdited` / `currModelFilename` mechanics, and
_run_track1()/_run_track2()/_run_theme_subset() for the stop-write-start
sequencing this module expects callers to follow.
"""

import os
import re
import subprocess
import time

KEY_ENTER = 2
KEY_PAGEDN = 4

PULSE_SETTLE_FRAMES = 11   # dev/scenes.lua's own critical-pulse-crest rule
PULSE_FRAME_MS = 50


class CaptureTimeout(RuntimeError):
    pass


class SimuDriver:
    def __init__(self, simu_exe, storage_dir, pipe_path, log_path,
                 width=None, height=None):
        self.simu_exe = simu_exe
        self.storage_dir = storage_dir
        self.pipe_path = pipe_path
        self.log_path = log_path
        self.width = width
        self.height = height
        self.proc = None
        self._log_fh = None
        self._telemetry_generation = 0

    # ------------------------------------------------------------- lifecycle --

    def _fresh_settings(self):
        return not os.path.exists(os.path.join(self.storage_dir, "RADIO", "radio.yml"))

    def start(self, model_marker=None, timeout_s=25.0):
        """Boot a fresh simu process. If `model_marker` is given (the
        header.name of the model that should already be on disk and
        selected via currModelFilename before this call -- see
        run.py's set_current_model), waits for the firmware's own log
        confirmation instead of guessing a delay, same rationale as
        reset()'s marker wait."""
        if not os.path.exists(self.pipe_path):
            open(self.pipe_path, "wb").close()
        else:
            # Start every session from an empty pipe file: pollPipeCommands()
            # tracks a read offset across the file's lifetime, but a brand
            # new simu process starts that offset at 0, so any bytes already
            # in the file from a previous run would replay immediately.
            open(self.pipe_path, "wb").close()

        env = dict(os.environ)
        env["SDL_VIDEODRIVER"] = "dummy"
        env["SDL_RENDER_DRIVER"] = "software"
        env["SDL_AUDIODRIVER"] = "dummy"

        args = [self.simu_exe, "--storage", self.storage_dir,
                "--settings", self.storage_dir, "--pipe", self.pipe_path]
        if self.width:
            args += ["--width", str(self.width)]
        if self.height:
            args += ["--height", str(self.height)]

        fresh = self._fresh_settings()
        start_pos = self._current_log_size()
        self._log_fh = open(self.log_path, "ab")
        self.proc = subprocess.Popen(args, stdout=self._log_fh,
                                      stderr=subprocess.STDOUT, env=env)
        if fresh:
            self._dismiss_first_boot_alerts()
            start_pos = self._current_log_size()

        if model_marker:
            marker = "<%s/0>" % model_marker
            if not self._wait_for_marker_from(marker, start_pos, timeout_s):
                raise CaptureTimeout(
                    "start: model marker %r not seen within %.1fs"
                    % (marker, timeout_s))
            # The marker fires when WidgetFactory::create() runs, well
            # before the boot splash screen actually clears -- confirmed
            # directly: a capture taken shortly after only the marker (this
            # sleep was 1.0s) still came back as the EdgeTX splash logo, not
            # Gauge Pro. A full process restart is heavier than the in-place
            # reset this module used to do (see module docstring), so give
            # it real margin.
            time.sleep(5.0)
        else:
            time.sleep(1.5)

    def _dismiss_first_boot_alerts(self):
        # Matches the sequence confirmed in the Widget Studio Phase 1 spike:
        # "Missing or bad radio data" then "Storage preparation", both
        # dismissed by clicking the dialog's default action button
        # (KEY_ENTER). Timing is generous since this only happens once per
        # fresh settings dir.
        time.sleep(4.5)
        self._key_tap(KEY_ENTER)
        time.sleep(2.0)
        self._key_tap(KEY_ENTER)
        time.sleep(2.0)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self._send("exit")
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
        if self._log_fh:
            self._log_fh.close()
            self._log_fh = None

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    # --------------------------------------------------------------- pipe --

    def _send(self, line):
        with open(self.pipe_path, "a", encoding="utf-8", newline="\n") as f:
            f.write(line + "\n")

    def _key_tap(self, code, hold_s=0.3):
        self._send("key %d 1" % code)
        time.sleep(hold_s)
        self._send("key %d 0" % code)

    def page_down(self):
        self._key_tap(KEY_PAGEDN, hold_s=0.2)
        time.sleep(0.3)

    def enter(self, settle_s=0.35):
        self._key_tap(KEY_ENTER, hold_s=0.2)
        time.sleep(settle_s)

    def long_enter(self, hold_s=1.25, settle_s=0.5):
        self._key_tap(KEY_ENTER, hold_s=hold_s)
        time.sleep(settle_s)

    def swipe(self, x1, y1, x2, y2, steps=8, step_s=0.04,
              settle_s=0.35):
        """Drive a real touchscreen drag through the simulator pipe."""
        if steps < 1:
            raise ValueError("swipe steps must be >= 1")
        for index in range(steps + 1):
            t = index / float(steps)
            x = round(x1 + (x2 - x1) * t)
            y = round(y1 + (y2 - y1) * t)
            self._send("touch %d %d" % (x, y))
            time.sleep(step_s)
        self._send("touchup")
        time.sleep(settle_s)

    def tap(self, x, y, hold_s=0.12, settle_s=0.35):
        self._send("touch %d %d" % (x, y))
        time.sleep(hold_s)
        self._send("touchup")
        time.sleep(settle_s)

    def set_telemetry(self, sensors, link=True, feed=True, rssi=90):
        """Atomically publish values consumed by the TeleInject topbar.

        Sensor identity must also be declared in model YAML; this method owns
        only changing values and transport/currentness. Removing the cached
        bytecode is intentional: loadScript otherwise keeps executing a stale
        generated data chunk after an in-process update.
        """
        self._telemetry_generation += 1
        rows = []
        for sensor in sensors:
            name = str(sensor["name"])
            if not re.match(r"^[A-Za-z0-9]{1,4}$", name):
                raise ValueError("telemetry name must be 1..4 alphanumerics")
            value = sensor["value"]
            if not isinstance(value, int):
                raise ValueError("setTelemetryValue probe requires integer values")
            rows.append(
                "{ id=%d, subId=%d, instance=%d, value=%d, unit=%d, "
                "prec=%d, name=\"%s\" }" %
                (int(sensor["id"]), int(sensor.get("subId", 0)),
                 int(sensor.get("instance", 0)), value,
                 int(sensor.get("unit", 0)), int(sensor.get("prec", 0)), name))
        body = (
            "return { generation=%d, link=%s, feed=%s, rssi=%d, sensors={%s} }\n"
            % (self._telemetry_generation, "true" if link else "false",
               "true" if feed else "false", max(0, min(99, int(rssi))),
               ",".join(rows)))
        path = os.path.join(self.storage_dir, "SCRIPTS", "gpvk_telemetry.lua")
        bytecode = os.path.splitext(path)[0] + ".luac"
        tmp = path + ".tmp"
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(bytecode):
            os.remove(bytecode)
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        os.replace(tmp, path)

    def inject_telemetry(self, sensors):
        """Apply live scalar steps without recreating the Lua widget.

        The Widget Studio pipe command calls the same native
        setTelemetryValue(PROTOCOL_TELEMETRY_LUA, ...) path as Lua's public
        API. Identity must already be present in model telemetrySensors[].
        """
        for sensor in sensors:
            value = sensor["value"]
            if not isinstance(value, int):
                raise ValueError("live telemetry injection requires integer values")
            cmd = "telemetry %d %d %d %d %d %d" % (
                int(sensor["id"]), int(sensor.get("subId", 0)),
                int(sensor.get("instance", 0)), value,
                int(sensor.get("unit", 0)), int(sensor.get("prec", 0)))
            # A predeclared sensor updates on the first call. The duplicate is
            # harmless and also preserves the public Lua helper's just-added
            # fallback if a future probe deliberately allows auto-discovery.
            self._send(cmd)
            self._send(cmd)
        time.sleep(0.05)

    def _current_log_size(self):
        try:
            return os.path.getsize(self.log_path)
        except OSError:
            return 0

    def _wait_for_marker_from(self, marker, start_pos, timeout_s, poll_s=0.2):
        # Re-reads the whole [start_pos, EOF) span each poll rather than
        # advancing a cursor forward -- the log is small per-batch, and this
        # sidesteps missing a marker split across two chunk boundaries.
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            if not self.alive():
                raise CaptureTimeout(
                    "simu process exited while waiting for %r" % marker)
            try:
                with open(self.log_path, "r", encoding="utf-8",
                          errors="replace") as f:
                    f.seek(start_pos)
                    chunk = f.read()
            except OSError:
                chunk = ""
            if marker in chunk:
                return True
            time.sleep(poll_s)
        return False

    # ------------------------------------------------------------ capture --

    def capture(self, out_path, settle_s=0.4, timeout_s=6.0,
                resend_every_s=2.0, pulse_settle=False):
        """Arm+wait for one deterministic capture. Returns True on success.

        Resends the `capture` command if the file hasn't appeared after
        `resend_every_s` -- same unreliable-pipe rationale as reset()'s
        resend loop; `simuCaptureArm` is idempotent (re-arming the same
        path is a no-op if already armed), so this is safe."""
        if os.path.exists(out_path):
            os.remove(out_path)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        time.sleep(settle_s)
        if pulse_settle:
            time.sleep(PULSE_SETTLE_FRAMES * PULSE_FRAME_MS / 1000.0)
        cmd = "capture %s" % out_path.replace("\\", "/")
        self._send(cmd)

        deadline = time.time() + timeout_s
        last_size = -1
        stable_since = None
        last_send = time.time()
        while time.time() < deadline:
            if not self.alive():
                raise CaptureTimeout("simu process exited while capturing %s" % out_path)
            if os.path.exists(out_path):
                size = os.path.getsize(out_path)
                if size > 0:
                    if size == last_size:
                        if stable_since is None:
                            stable_since = time.time()
                        elif time.time() - stable_since > 0.1:
                            return True
                    else:
                        stable_since = None
                    last_size = size
            elif time.time() - last_send > resend_every_s:
                self._send(cmd)
                last_send = time.time()
            time.sleep(0.05)
        return False
