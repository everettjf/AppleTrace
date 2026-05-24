//
//  ContentView.swift
//  Guided UI: tap "Generate Trace" to run the Swift showcase, then follow the
//  on-screen steps to merge and open the trace in Perfetto on your Mac.
//

import SwiftUI
import AppleTrace

struct ContentView: View {
    @State private var status = "Ready."
    @State private var statusColor: Color = .secondary
    @State private var traceDir = traceDirectory
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AppleTrace 🍎")
                    .font(.largeTitle.bold())
                Text("Swift demo — macros (`@Traced` / `@TraceAll` / `withSpan`) everywhere, plus the optional SwiftTrace auto-hook (Simulator / macOS only).")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(action: generate) {
                    Text(isRunning ? "Generating…" : "▶︎  Generate Trace")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)

                card(title: "Trace directory on this build") {
                    Text(traceDir).textSelection(.enabled)
                }

                card(title: "Next steps on your Mac") {
                    Text(guidance).textSelection(.enabled)
                }
            }
            .padding(20)
        }
        .onAppear {
            // Convenience for automation (smoke tests / CI): run once without a
            // tap if APPLETRACE_AUTORUN is set. Normal use is the button.
            if ProcessInfo.processInfo.environment["APPLETRACE_AUTORUN"] != nil {
                generate()
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.96)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.85)))
        }
    }

    private func generate() {
        isRunning = true
        status = "Generating trace…"
        statusColor = .secondary
        DispatchQueue.global(qos: .userInitiated).async {
            let dir = SwiftShowcase.run()
            DispatchQueue.main.async {
                traceDir = dir
                status = "✅ Trace generated across multiple threads. Follow the steps below."
                statusColor = .green
                isRunning = false
            }
        }
    }

    private var guidance: String {
        let dir = traceDir
        #if targetEnvironment(simulator)
        return """
        Running in the Simulator, so the trace is already on this Mac.

        1. Tap “Generate Trace” above.
        2. In the AppleTrace repo, merge the fragments:
             python3 merge.py -d "\(dir)"
           (or:  sh go.sh "\(dir)" )
        3. Open https://ui.perfetto.dev and drag in:
             \(dir)/trace.json
        """
        #else
        return """
        Running on a device, so copy the trace to your Mac first.

        1. Tap “Generate Trace” above.
        2. Pull the app’s container, either:
           • Xcode ▸ Window ▸ Devices and Simulators ▸
             select this app ▸ ⚙ ▸ Download Container, or
           • xcrun devicectl device copy from --device <id> \\
               --domain-type appDataContainer \\
               --domain-identifier com.everettjf.AppleTraceSwiftDemo \\
               --source Library/appletracedata --destination ./trace
        3. Merge and open in Perfetto:
             python3 merge.py -d <pulled>/Library/appletracedata
           then drag trace.json into https://ui.perfetto.dev
        """
        #endif
    }
}

#Preview {
    ContentView()
}
