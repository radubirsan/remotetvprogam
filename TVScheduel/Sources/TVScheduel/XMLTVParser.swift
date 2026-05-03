import Foundation

/// Parses an XMLTV document (https://github.com/XMLTV/xmltv) into a `Guide`.
///
/// XMLTV is a long-standing community format. The bits we read:
///
/// ```xml
/// <tv>
///   <channel id="digi24.ro">
///     <display-name lang="ro">Digi 24</display-name>
///     <icon src="https://..." />
///   </channel>
///   <programme start="20260503060000 +0200" stop="20260503070000 +0200" channel="digi24.ro">
///     <title lang="ro">Știrile Digi 24</title>
///     <sub-title lang="ro">Ediție matinală</sub-title>
///     <desc lang="ro">...</desc>
///     <category lang="ro">Știri</category>
///   </programme>
/// </tv>
/// ```
///
/// Many feeds ship hundreds of MB; we parse with `XMLParser` (SAX) so peak memory stays low.
public enum XMLTVParser {

    public enum ParseError: Error, CustomStringConvertible {
        case xmlError(any Error)
        case missingRoot

        public var description: String {
            switch self {
            case .xmlError(let error):
                "XML parse error: \(error.localizedDescription)"
            case .missingRoot:
                "XMLTV document had no <tv> root"
            }
        }
    }

    /// Parses the given XMLTV data.
    public static func parse(_ data: Data) throws -> Guide {
        let parser = XMLParser(data: data)
        let delegate = XMLTVDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            if let error = parser.parserError {
                throw ParseError.xmlError(error)
            }
            throw ParseError.missingRoot
        }
        return Guide(
            channels: delegate.channels,
            programmes: delegate.programmes
        )
    }
}

/// SAX delegate that builds up channels and programmes as the document streams in.
///
/// This is intentionally a class — `XMLParserDelegate` requires reference semantics — and
/// is consumed on a single call site, so it doesn't need actor isolation.
private final class XMLTVDelegate: NSObject, XMLParserDelegate {

    var channels: [Channel] = []
    var programmes: [Programme] = []

    // Per-element scratch state. Cleared on each open tag.
    private var currentElement = ""
    private var characterBuffer = ""

    // In-flight channel
    private var channelID: String?
    private var channelDisplayNames: [String] = []
    private var channelIconURL: URL?

    // In-flight programme
    private var programmeChannelID: String?
    private var programmeStart: Date?
    private var programmeStop: Date?
    private var programmeTitle: String?
    private var programmeSubtitle: String?
    private var programmeDescription: String?
    private var programmeCategories: [String] = []

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        characterBuffer = ""

        switch elementName {
        case "channel":
            channelID = attributeDict["id"]
            channelDisplayNames = []
            channelIconURL = nil

        case "programme":
            programmeChannelID = attributeDict["channel"]
            programmeStart = attributeDict["start"].flatMap(XMLTVDate.parse)
            programmeStop = attributeDict["stop"].flatMap(XMLTVDate.parse)
            programmeTitle = nil
            programmeSubtitle = nil
            programmeDescription = nil
            programmeCategories = []

        case "icon":
            // Inside <channel>, capture the icon src.
            if let src = attributeDict["src"], let url = URL(string: src), channelID != nil {
                channelIconURL = url
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            characterBuffer += text
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "display-name":
            if !value.isEmpty {
                channelDisplayNames.append(value)
            }

        case "channel":
            if let id = channelID {
                channels.append(
                    Channel(
                        id: id,
                        displayNames: channelDisplayNames,
                        iconURL: channelIconURL
                    )
                )
            }
            channelID = nil
            channelDisplayNames = []
            channelIconURL = nil

        case "title":
            if programmeChannelID != nil { programmeTitle = value }

        case "sub-title":
            if programmeChannelID != nil { programmeSubtitle = value }

        case "desc":
            if programmeChannelID != nil { programmeDescription = value }

        case "category":
            if programmeChannelID != nil, !value.isEmpty {
                programmeCategories.append(value)
            }

        case "programme":
            if let channel = programmeChannelID,
               let start = programmeStart,
               let stop = programmeStop,
               let title = programmeTitle, !title.isEmpty {
                programmes.append(
                    Programme(
                        channelID: channel,
                        title: title,
                        subtitle: programmeSubtitle,
                        description: programmeDescription,
                        start: start,
                        stop: stop,
                        categories: programmeCategories
                    )
                )
            }
            programmeChannelID = nil
            programmeStart = nil
            programmeStop = nil
            programmeTitle = nil
            programmeSubtitle = nil
            programmeDescription = nil
            programmeCategories = []

        default:
            break
        }

        characterBuffer = ""
    }
}
