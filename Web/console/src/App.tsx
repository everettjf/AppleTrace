import { Activity, Download, Play, RotateCcw, ScanLine, Settings2, Square } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AppleTraceAPI, type AgentStatus, type Artifact } from "./api";
import { Badge, Button, Card, Metric } from "./components";
import { formatBytes } from "./lib";

type View = "overview" | "traces" | "settings";

export default function App() {
  const api = useMemo(() => new AppleTraceAPI(), []);
  const [view, setView] = useState<View>("overview");
  const [status, setStatus] = useState<AgentStatus>();
  const [artifacts, setArtifacts] = useState<Artifact[]>([]);
  const [allow, setAllow] = useState("");
  const [deny, setDeny] = useState("");
  const [error, setError] = useState("");

  const refresh = useCallback(async () => {
    try {
      const [nextStatus, nextArtifacts] = await Promise.all([api.status(), api.artifacts()]);
      setStatus(nextStatus);
      setArtifacts(nextArtifacts);
      setError("");
    } catch (caught) {
      console.debug("AppleTrace refresh failed", caught);
      setError("Disconnected");
    }
  }, [api]);

  useEffect(() => {
    void refresh();
    let stream: WebSocket | undefined;
    let reconnectTimer: number | undefined;
    let disposed = false;

    const connect = () => {
      stream = api.statusStream();
      stream.onopen = () => setError("");
      stream.onmessage = (event) => {
        try {
          setStatus(JSON.parse(String(event.data)) as AgentStatus);
          setError("");
        } catch (caught) {
          console.debug("AppleTrace stream payload failed", caught);
        }
      };
      stream.onerror = () => setError("Disconnected");
      stream.onclose = () => {
        if (!disposed) {
          setError("Disconnected");
          reconnectTimer = window.setTimeout(connect, 1500);
        }
      };
    };
    connect();

    const artifactTimer = window.setInterval(async () => {
      try { setArtifacts(await api.artifacts()); }
      catch { /* status stream owns the connection indicator */ }
    }, 5000);
    return () => {
      disposed = true;
      stream?.close();
      if (reconnectTimer !== undefined) window.clearTimeout(reconnectTimer);
      window.clearInterval(artifactTimer);
    };
  }, [refresh]);

  async function command(action: "start" | "stop") {
    try {
      setStatus(action === "start" ? await api.start() : await api.stop());
      await refresh();
    } catch (caught) {
      console.debug("AppleTrace command failed", caught);
      setError("Disconnected");
    }
  }

  async function saveFilters() {
    const split = (value: string) => value.split(",").map((item) => item.trim()).filter(Boolean);
    await api.setFilters({ allowClassPrefixes: split(allow), denyClassPrefixes: split(deny) });
  }

  const recording = status?.captureState === "recording";

  return <div className="shell">
    <aside>
      <div className="brand"><ScanLine size={18} /><span>AppleTrace</span></div>
      <nav>
        <button className={view === "overview" ? "active" : ""} onClick={() => setView("overview")}><Activity />Overview</button>
        <button className={view === "traces" ? "active" : ""} onClick={() => setView("traces")}><Download />Traces</button>
        <button className={view === "settings" ? "active" : ""} onClick={() => setView("settings")}><Settings2 />Settings</button>
      </nav>
      <div className="sidebar-foot">Protocol v{status?.protocolVersion ?? 1}</div>
    </aside>

    <main>
      <header>
        <div><h1>{status?.processName ?? "Waiting for agent"}</h1><p>{status?.bundleIdentifier ?? "Local control session"}</p></div>
        <Badge tone={error ? "warn" : "good"}>{error || "Connected"}</Badge>
      </header>

      {view === "overview" && <>
        <section className="hero card">
          <div><span className="eyebrow">Capture</span><h2>{recording ? "Recording" : "Idle"}</h2><p>{status?.architecture ?? "—"} · PID {status?.processId ?? "—"} · objc hook {status?.objcHookInstalled ? "active" : "inactive"}</p></div>
          <Button onClick={() => void command(recording ? "stop" : "start")} className={recording ? "danger" : "primary"}>
            {recording ? <Square /> : <Play />}{recording ? "Stop capture" : "Start capture"}
          </Button>
        </section>
        <section className="metrics">
          <Metric label="Accepted events" value={(status?.metrics.acceptedEvents ?? 0).toLocaleString()} />
          <Metric label="Pending" value={formatBytes(status?.metrics.pendingBytes ?? 0)} />
          <Metric label="Write failures" value={(status?.metrics.writeFailures ?? 0).toLocaleString()} />
          <Metric label="Artifacts" value={String(artifacts.length)} />
        </section>
      </>}

      {view === "traces" && <Card>
        <div className="section-title"><div><h2>Trace artifacts</h2><p>Download and open in Perfetto.</p></div><Button onClick={() => void refresh()}><RotateCcw />Refresh</Button></div>
        <div className="table">
          {artifacts.length === 0 && <div className="empty">No trace artifacts yet.</div>}
          {artifacts.map((artifact) => <div className="row" key={artifact.name}>
            <div><strong>{artifact.name}</strong><span>{new Date(artifact.modifiedAt).toLocaleString()}</span></div>
            <span>{formatBytes(artifact.size)}</span>
            <Button onClick={() => void api.download(artifact.name)}><Download />Download</Button>
          </div>)}
        </div>
      </Card>}

      {view === "settings" && <Card className="settings">
        <div className="section-title"><div><h2>Class filters</h2><p>Comma-separated Objective-C class prefixes.</p></div></div>
        <label>Allow prefixes<input value={allow} onChange={(event) => setAllow(event.target.value)} placeholder="MyApp, Checkout" /></label>
        <label>Deny prefixes<input value={deny} onChange={(event) => setDeny(event.target.value)} placeholder="UIKit, SwiftUI" /></label>
        <Button className="primary" onClick={() => void saveFilters()}>Save filters</Button>
        <div className="path"><span>Trace directory</span><code>{status?.traceDirectory ?? "—"}</code></div>
      </Card>}
    </main>
  </div>;
}
