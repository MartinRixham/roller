#!/usr/bin/env python3
"""Drive the exported binary headless over its remote-input socket and check
that every roll reports one value per die, for every dice count and input.

    python3 godot/tests/export_test.py build/dice-sim.x86_64

The game side is scripts/remote_input.gd. Timeouts are counted in game
frames (via `wait`), so the result does not depend on how fast the machine is.
"""

import json
import re
import socket
import subprocess
import sys
import tempfile

MAX_DICE = 5
ROUNDS = 3            # rolls per dice count
TIMEOUT_FRAMES = 1200  # per roll, at 60 Hz physics
QUIET_FRAMES = 120     # after a roll, watch for stray results
SOCKET_TIMEOUT = 30    # wall-clock seconds for any single reply


class Failure(Exception):
    pass


class Game:
    def __init__(self, sock):
        self._lines = sock.makefile("r", encoding="utf-8")
        self._sock = sock
        self.signals = []

    def send(self, command):
        """Run one command and return its reply, stashing pushed signals."""
        self._sock.sendall((command + "\n").encode())
        while True:
            line = self._lines.readline()
            if not line:
                raise Failure(f"game closed the connection during: {command}")
            line = line.rstrip("\n")
            if line.startswith("signal "):
                _, name, args = line.split(" ", 2)
                self.signals.append((name, json.loads(args)))
                continue
            if line.startswith("error "):
                raise Failure(f"{command}: {line}")
            return json.loads(line[6:]) if line.startswith("value ") else None

    def next_signal(self, name, frames):
        """Advance the game until `name` fires, at most `frames` frames."""
        waited = 0
        while not any(n == name for n, _ in self.signals) and waited < frames:
            self.send("wait 10")
            waited += 10
        for i, (n, args) in enumerate(self.signals):
            if n == name:
                del self.signals[i]
                return args
        return None


def expect_roll(game, count, label):
    args = game.next_signal("rolled", TIMEOUT_FRAMES)
    if args is None:
        raise Failure(f"{label}: no result after {TIMEOUT_FRAMES} frames")
    results = args[0]
    if len(results) != count:
        raise Failure(f"{label}: expected {count} values, got {results}")
    if not all(1 <= v <= 6 for v in results):
        raise Failure(f"{label}: value out of range in {results}")

    readout = game.send("get %Readout text")
    numbers = [int(n) for n in re.findall(r"\d+", readout)]
    expected_numbers = count if count == 1 else count + 1
    if len(numbers) != expected_numbers or numbers[-1] != sum(results):
        raise Failure(f"{label}: readout {readout!r} does not match {results}")

    dice_count = game.send("get . dice_count")
    if dice_count != count:
        raise Failure(f"{label}: game reports dice_count {dice_count}, expected {count}")

    # A die left over from an earlier roll would report late.
    game.send(f"wait {QUIET_FRAMES}")
    if game.signals:
        raise Failure(f"{label}: extra result {game.signals} after the roll finished")

    print(f"  ok  {label:<28} {readout}")


def run(game):
    game.send("watch rolled")
    start_count = game.send("get . dice_count")
    game.send("resume")

    # main.gd throws its default dice as soon as it starts.
    expect_roll(game, start_count, "startup roll")

    for n in range(1, MAX_DICE + 1):
        game.send(f"key {n}")
        expect_roll(game, n, f"key {n}")
        for i in range(ROUNDS - 1):
            game.send("key Space")
            expect_roll(game, n, f"{n} dice, space reroll {i + 1}")

    game.send("click")
    expect_roll(game, MAX_DICE, "mouse click reroll")

    # Change the count while dice are still in the air: the old dice must
    # not leak results into the new roll.
    game.send("key 5")
    game.send("wait 20")
    game.send("key 2")
    expect_roll(game, 2, "switch 5 -> 2 mid-roll")


def main():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} path/to/dice-sim.x86_64")

    with socket.create_server(("127.0.0.1", 0)) as server, \
            tempfile.TemporaryFile("w+") as log:
        server.settimeout(SOCKET_TIMEOUT)
        port = server.getsockname()[1]
        proc = subprocess.Popen(
            [sys.argv[1], "--headless", "--fixed-fps", "60",
             "--", f"--remote-input=127.0.0.1:{port}"],
            stdout=log, stderr=subprocess.STDOUT)
        try:
            try:
                sock, _ = server.accept()
            except TimeoutError:
                raise Failure("game never connected (started without the RemoteInput autoload?)")
            sock.settimeout(SOCKET_TIMEOUT)
            with sock:
                game = Game(sock)
                run(game)
                game.send("quit")
            proc.wait(timeout=SOCKET_TIMEOUT)
        except (Failure, TimeoutError, subprocess.TimeoutExpired) as err:
            proc.kill()
            proc.wait()
            log.seek(0)
            sys.stderr.write(log.read())
            sys.exit(f"FAIL  {err}")
        finally:
            if proc.poll() is None:
                proc.kill()

        if proc.returncode != 0:
            log.seek(0)
            sys.stderr.write(log.read())
            sys.exit(f"FAIL  game exited {proc.returncode}")
        log.seek(0)
        errors = [l for l in log if "ERROR" in l]
        if errors:
            sys.exit("FAIL  engine errors:\n" + "".join(errors))

    print("OK: exported build passed")


if __name__ == "__main__":
    main()
