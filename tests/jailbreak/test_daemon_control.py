#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def request(base, token, path, method="GET", payload=None, expected=200):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            assert response.status == expected, (response.status, expected)
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        assert error.code == expected, (error.code, expected, error.read())
        return json.loads(error.read())


def wait_until(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("timed out waiting for daemon state")


def download(base, token, path):
    req = urllib.request.Request(base + path, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=3) as response:
        assert response.status == 200
        assert response.headers.get_content_type() == "application/octet-stream"
        return response.read()


def main():
    daemon_binary, agent_binary, console_path = sys.argv[1:]
    token = "host-control-test-token"
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]

    with tempfile.TemporaryDirectory() as directory:
        socket_path = os.path.join(directory, "appletraced.sock")
        daemon_log_path = os.path.join(directory, "daemon.log")
        with open(daemon_log_path, "wb") as daemon_log:
            environment = os.environ | {
                "APPLETRACE_DAEMON_SOCKET": socket_path,
                "APPLETRACE_CONTROL_PORT": str(port),
                "APPLETRACE_CONTROL_TOKEN": token,
                "APPLETRACE_CONSOLE_PATH": console_path,
            }
            daemon = subprocess.Popen([daemon_binary], env=environment, stdout=daemon_log, stderr=subprocess.STDOUT)
            agents = []
            try:
                base = f"http://127.0.0.1:{port}"

                def server_ready():
                    try:
                        with urllib.request.urlopen(base + "/", timeout=0.2) as response:
                            return response.status == 200 and b"AppleTrace" in response.read()
                    except Exception:
                        return False

                wait_until(server_ready)
                request(base, "wrong-token", "/api/v1/agents", expected=401)

                for index in range(2):
                    trace_directory = os.path.join(directory, f"trace-{index}")
                    os.makedirs(trace_directory)
                    trace_bytes = f"trace-agent-{index}".encode()
                    with open(os.path.join(trace_directory, "trace.appletrace"), "wb") as trace_file:
                        trace_file.write(trace_bytes)
                    agent_environment = os.environ | {
                        "APPLETRACE_DAEMON_SOCKET": socket_path,
                        "APPLETRACE_TEST_BUNDLE_ID": f"com.example.agent{index}",
                        "APPLETRACE_TEST_PROCESS_NAME": f"Agent {index}",
                        "APPLETRACE_TEST_TRACE_DIR": trace_directory,
                    }
                    agents.append(subprocess.Popen([agent_binary], env=agent_environment))

                def two_agents():
                    payload = request(base, token, "/api/v1/agents")
                    return payload if len(payload["agents"]) == 2 else None

                listing = wait_until(two_agents)
                assert listing["protocolVersion"] == 1
                assert {agent["bundleIdentifier"] for agent in listing["agents"]} == {
                    "com.example.agent0", "com.example.agent1"
                }
                assert all(agent["architecture"] in {"arm64", "arm64e", "x86_64"}
                           for agent in listing["agents"])
                assert all(agent["objcHookInstalled"] is True for agent in listing["agents"])

                for agent in listing["agents"]:
                    identifier = agent["id"]
                    detail = request(base, token, f"/api/v1/agents/{identifier}")
                    assert detail["connected"] is True, detail
                    artifacts = request(base, token, f"/api/v1/agents/{identifier}/artifacts")
                    assert len(artifacts) == 1
                    assert artifacts[0]["name"] == "trace.appletrace"
                    expected_trace = f"trace-agent-{detail['bundleIdentifier'][-1]}".encode()
                    assert download(base, token, f"/api/v1/agents/{identifier}/artifacts/trace.appletrace") == expected_trace
                    for action in ("start", "filters", "flush", "stop"):
                        payload = ({"allowClassPrefixes": ["APTAllowed"], "denyClassPrefixes": ["APTDeny"]}
                                   if action == "filters" else None)
                        accepted = request(base, token, f"/api/v1/agents/{identifier}/{action}",
                                           method="POST", payload=payload, expected=202)
                        assert accepted == {"accepted": True, "agentId": identifier}

                for agent in agents:
                    assert agent.wait(timeout=8) == 0
                agents.clear()
                wait_until(lambda: len(request(base, token, "/api/v1/agents")["agents"]) == 0)
                request(base, token, "/api/v1/agents/missing", expected=404)
            finally:
                for agent in agents:
                    agent.terminate()
                    agent.wait(timeout=3)
                daemon.terminate()
                daemon.wait(timeout=3)

    print("jailbreak multi-Agent control server test passed")


if __name__ == "__main__":
    main()
