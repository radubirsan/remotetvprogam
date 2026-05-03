import Foundation
import TVScheduel

// MARK: - Defaults

/// Default Romanian XMLTV source.
///
/// `epgshare01.online` hosts daily-regenerated XMLTV cuts per country. The `RO1` cut
/// covers ~360 Romanian channels including every Digi service (Digi 24, Digi Sport 1–4,
/// Digi Animal World, Digi Life, Digi World, Digi 4K), Pro TV, Antena 1/3, TVR, and
/// many cable channels. Ships gzipped (~13 MB on the wire).
///
/// Override with `TVEPG_SOURCE_URL` or the `--source` flag.
let defaultSourceURL = URL(string: "https://epgshare01.online/epgshare01/epg_ripper_RO1.xml.gz")!

// MARK: - Argument parsing

struct Options {
    enum Command {
        case channels
        case today(channelQuery: String)
        case dump
        case help
    }

    var command: Command = .help
    var sourceURL: URL = defaultSourceURL
    var forceRefresh = false
    /// When set, read pre-fetched (and pre-decompressed) XML from this path instead of
    /// going to the network. Use `-` to read from stdin. Designed for CI pipelines that
    /// `curl … | gunzip | tvepg dump --input -` on Linux runners where Apple's
    /// Compression framework isn't available.
    var inputPath: String?
}

func parseOptions(from args: [String]) -> Options {
    var options = Options()
    var positional: [String] = []

    if let envURL = ProcessInfo.processInfo.environment["TVEPG_SOURCE_URL"],
       let url = URL(string: envURL) {
        options.sourceURL = url
    }

    var i = 1
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--source", "-s":
            if i + 1 < args.count, let url = URL(string: args[i + 1]) {
                options.sourceURL = url
                i += 2
                continue
            }
        case "--refresh", "-r":
            options.forceRefresh = true
        case "--input", "-i":
            if i + 1 < args.count {
                options.inputPath = args[i + 1]
                i += 2
                continue
            }
        case "--help", "-h":
            options.command = .help
            return options
        default:
            positional.append(arg)
        }
        i += 1
    }

    guard let verb = positional.first else {
        return options
    }
    let rest = Array(positional.dropFirst())

    switch verb {
    case "channels":
        options.command = .channels
    case "today":
        options.command = .today(channelQuery: rest.joined(separator: " "))
    case "dump":
        options.command = .dump
    default:
        options.command = .help
    }
    return options
}

func printHelp() {
    let help = """
    tvepg — Romanian XMLTV grabber for the RemoteTV project

    Usage:
      tvepg channels                  List every channel in the feed.
      tvepg today <channel query>     Print today's schedule for the channel whose
                                       name contains <channel query> (case insensitive).
      tvepg dump                      Print the full guide as JSON to stdout.

    Options:
      --source, -s <url>              XMLTV source URL.
      --input,  -i <path>             Read XML from a local file (or `-` for stdin)
                                       instead of the network. Useful in CI:
                                       `curl … | gunzip | tvepg dump --input -`
      --refresh, -r                   Ignore the 24h cache.
      --help, -h                      Show this help.

    Environment:
      TVEPG_SOURCE_URL                Default source URL (overridden by --source).

    Examples:
      tvepg channels
      tvepg today "Digi 24"
      tvepg dump > ro-guide.json
      tvepg today "Pro TV" --refresh
      curl -sL <gz-url> | gunzip | tvepg dump --input - > guide.json
    """
    print(help)
}

// MARK: - Output helpers

func formatTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

func formatDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Reads XML bytes from a path. `-` reads from standard input until EOF.
func loadInputXML(from path: String) throws -> Data {
    if path == "-" {
        return FileHandle.standardInput.readDataToEndOfFile()
    }
    let url = URL(fileURLWithPath: path)
    return try Data(contentsOf: url)
}

// MARK: - Commands

func runChannels(guide: Guide) {
    let sorted = guide.channels.sorted { $0.primaryName.localizedStandardCompare($1.primaryName) == .orderedAscending }
    print("Channels (\(sorted.count)):")
    for channel in sorted {
        print("  \(channel.id)  —  \(channel.primaryName)")
    }
}

func runToday(query: String, guide: Guide) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        writeError("Provide a channel name, e.g. `tvepg today \"Digi 24\"`")
        exit(2)
    }

    let matches = guide.channels.filter { channel in
        channel.primaryName.localizedStandardContains(trimmed) ||
        channel.id.localizedStandardContains(trimmed) ||
        channel.displayNames.contains { $0.localizedStandardContains(trimmed) }
    }

    guard let channel = matches.first else {
        writeError("No channel matched \"\(trimmed)\". Try `tvepg channels` to list available channels.")
        exit(1)
    }

    if matches.count > 1 {
        writeError("Multiple channels matched — using \"\(channel.primaryName)\". Other matches:")
        for other in matches.dropFirst() {
            writeError("  \(other.id) — \(other.primaryName)")
        }
    }

    let today = Calendar.current.startOfDay(for: .now)
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    let todays = guide.programmes(for: channel.id)
        .filter { $0.start < tomorrow && $0.stop > today }

    print("\(channel.primaryName)  (\(channel.id))")
    print("Schedule for \(today.formatted(date: .complete, time: .omitted)):")
    if todays.isEmpty {
        print("  (no programmes in the feed for today)")
        return
    }
    for programme in todays {
        let line = "  \(formatTime(programme.start))–\(formatTime(programme.stop))  \(programme.title)"
        print(line)
        if let subtitle = programme.subtitle, !subtitle.isEmpty {
            print("      \(subtitle)")
        }
    }
}

func runDump(guide: Guide) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(guide)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// MARK: - Entrypoint

@main
struct TVEPG {
    static func main() async {
        let options = parseOptions(from: CommandLine.arguments)

        if case .help = options.command {
            printHelp()
            return
        }

        do {
            let guide: Guide
            if let inputPath = options.inputPath {
                let xml = try loadInputXML(from: inputPath)
                writeError("Parsing \(xml.count) bytes from \(inputPath == "-" ? "stdin" : inputPath)…")
                guide = try XMLTVParser.parse(xml)
            } else {
                let fetcher = XMLTVFetcher(
                    configuration: .init(sourceURL: options.sourceURL)
                )
                writeError("Fetching \(options.sourceURL.absoluteString)…")
                guide = try await fetcher.fetchGuide(forceRefresh: options.forceRefresh)
            }
            writeError("Loaded \(guide.channels.count) channels, \(guide.programmes.count) programmes.")

            switch options.command {
            case .channels:
                runChannels(guide: guide)
            case .today(let query):
                runToday(query: query, guide: guide)
            case .dump:
                try runDump(guide: guide)
            case .help:
                printHelp()
            }
        } catch {
            writeError("Error: \(error)")
            exit(1)
        }
    }
}
