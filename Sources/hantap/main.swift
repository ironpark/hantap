import AppKit
import Carbon

let usage = """
usage: hantap <command> [options]

commands:
  run               agent: CapsLock tap toggles Korean/Latin (used by the LaunchAgent)
  toggle            switch once to the other source, like a CapsLock tap
  switch <ko|en|ID> switch once to the given source
  current           print the current input source ID
  list              list enabled input sources
  restore-keys      remove the CapsLock -> F18 mapping (if the agent died with it set)

options:
  --korean ID       Korean source (default com.apple.inputmethod.Korean.2SetKorean)
  --latin ID        Latin source (default com.apple.keylayout.ABC)
  --hold-ms N       hold CapsLock N ms to revert and toggle CapsLock instead (default 500, 0 = off)
  --fallback MODE   when the app can't be asked directly: panel (default), activate, none
  --nudge-ms N      how long the fallback holds key focus (default 60)
"""

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()

/// One-shot commands still need a window server connection, and the fallback
/// nudge needs the run loop for a moment before exiting.
func oneShot(_ body: (Switcher) -> Void) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var rest = args
    if command == "switch" { rest.removeFirst() }
    let switcher = Switcher(config: Config.parse(rest))
    body(switcher)
    RunLoop.main.run(until: Date().addingTimeInterval(Double(switcher.config.nudgeMs + 100) / 1000))
    print(InputSources.currentID())
    exit(0)
}

switch command {
case "run":
    Agent(config: Config.parse(args)).run()

case "toggle":
    oneShot { s in s.select(s.toggleTarget(), reason: "toggle") }

case "switch":
    guard let target = args.first else { fail("switch needs ko, en or an input source ID") }
    oneShot { s in
        let source: TISInputSource
        switch target {
        case "ko": source = s.korean
        case "en": source = s.latin
        default:
            guard let found = InputSources.find(target) else { fail("\(target) is not an enabled input source") }
            source = found
        }
        s.select(source, reason: "switch")
    }

case "current":
    print(InputSources.currentID())

case "list":
    let current = InputSources.currentID()
    for s in InputSources.enabled() {
        let id = InputSources.id(s)
        print("\(id == current ? "*" : " ") \(id)  [\(InputSources.languages(s).prefix(3).joined(separator: ","))]")
    }

case "restore-keys":
    do {
        try KeyRemap.remove()
        print("CapsLock mapping removed")
    } catch {
        fail("\(error)")
    }

case "help", "-h", "--help":
    print(usage)

default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
