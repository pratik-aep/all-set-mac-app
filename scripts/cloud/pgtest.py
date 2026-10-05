"""A throwaway local Postgres for the server-script tests (Homebrew's
postgresql@17). Never touches a real database."""
import os
import shutil
import socket
import subprocess
import tempfile

BIN = "/opt/homebrew/opt/postgresql@17/bin"
# The same version as the server binaries (postgresql@17 is keg-only, so not on PATH in CI).
PSQL = f"{BIN}/psql" if os.path.exists(f"{BIN}/psql") else "psql"
HERE = os.path.dirname(os.path.abspath(__file__))
AVAILABLE = os.path.exists(os.path.join(BIN, "initdb"))


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Postgres:
    """Started with the catalog schema loaded; `url` connects to it."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="allset-pg-test-")
        self.data = os.path.join(self.tmp, "pg")
        self.port = free_port()
        subprocess.run([f"{BIN}/initdb", "-D", self.data, "-U", "allset", "--auth=trust"], check=True, capture_output=True)
        subprocess.run([f"{BIN}/pg_ctl", "-D", self.data, "-o", f"-p {self.port} -c listen_addresses=127.0.0.1 -k {self.tmp}",
                        "-l", os.path.join(self.tmp, "log"), "-w", "start"], check=True, capture_output=True)
        self.url = f"postgres://allset@127.0.0.1:{self.port}/postgres"
        with open(os.path.join(HERE, "schema.sql")) as schema:
            self.sql(schema.read())

    def sql(self, statement):
        out = subprocess.run([PSQL, self.url, "-v", "ON_ERROR_STOP=1", "-At", "-c", statement],
                             capture_output=True, text=True)
        if out.returncode != 0:
            raise AssertionError(out.stderr)
        return out.stdout.strip()

    def stop(self):
        subprocess.run([f"{BIN}/pg_ctl", "-D", self.data, "-m", "immediate", "stop"], capture_output=True)
        shutil.rmtree(self.tmp, ignore_errors=True)
