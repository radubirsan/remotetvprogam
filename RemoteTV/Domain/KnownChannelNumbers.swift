import Foundation

/// Maps EPG channel ids (as published in the daily Romanian XMLTV dump on the
/// `epg-data` branch) to the corresponding channel numbers on the user's TV.
///
/// The numbers below match a Digi cable lineup as captured from a printed channel
/// guide (positions 1–169, TV channels only — radio at 1001+ is intentionally
/// omitted). **Lineups vary by package tier and region**, and the user can also
/// reorder channels on the box itself, so treat the mapping as a sensible default
/// rather than ground truth. The right way to verify any specific channel is to
/// hit `INFO` on the remote while watching it, or to glance at the on-screen
/// banner when pressing `CH+`.
///
/// Notes on the channel id format:
///
/// - Ids follow the `<channel>.<qualifier>.ro` pattern used by the project's own
///   XMLTV grabber. They are *not* iptv-org/epg ids — if the EPG source changes,
///   ids must be remapped (a one-pass find/replace).
/// - HD and SD variants are listed as separate keys so each has its own number.
///   The HD variant is preferred by the player when both are tunable.
/// - A handful of names in the source guide had OCR-style typos (e.g. "Reaitatea",
///   "Magyar Slaer TV"); these are silently corrected to the canonical channel
///   names below.
///
/// Mapping is intentionally a flat `[String: Int]` rather than a richer type so
/// adding or correcting a row is a one-line edit. Anything not in the table simply
/// has no "Tune to" macro available — the channel still appears in the EPG list,
/// it just can't be auto-tuned.
enum KnownChannelNumbers {

    /// EPG channel id → TV channel number.
    ///
    static let mapping: [String: Int] = [
     
        "Digi.Sport.1.ro":               1,
        "Digi.Sport.1.HD.ro":            2,
        "Digi.Sport.2.HD.ro":            3,
        "Digi.Sport.2.ro":               4,
        "Digi.Sport.3.HD.ro":            5,
        "Digi.Sport.3.ro":               6,
        "Digi.Sport.4.HD.ro":            7,
        "Eurosport.1.HD.ro":             8,    // listed as "Eurosport HD"
        "Eurosport.1.ro":                9,    // listed as "Eurosport RO"
        "Eurosport.2.HD.ro":            10,
        "Eurosport.2.ro":               11,
        "PRIMA.SPORT.1.ro":             12,
        "PRO.X.HD.ro":                  19,    // rebranded as "PRO ARENA HD"
        "PRO.X.ro":                     20,    // rebranded as "PRO ARENA"
        "TVR.HD.ro":                    22,    // TVR 1 HD
        "TVR.1.ro":                     23,
        "TVR.2.ro":                     25,
        "TVR.3.ro":                     26,
        "PRO.TV.HD.ro":                 27,
        "PRO.TV.ro":                    28,
        "Antena.1.HD.ro":               29,
        "Antena.1.ro":                  30,
        "Kanal.D.HD.ro":                31,
        "Kanal.D.ro":                   32,
        "Prima.TV.ro":                  34,
        "Happy.Channel.HD.ro":          35,
        "Happy.Channel.ro":             36,
        "Antena.Stars.HD.ro":           37,
        "Antena.Stars.ro":              38,
        "National.TV.ro":               39,
        "National.24.Plus.ro":          40,
        "Etno.TV.ro":                   43,
        "Inedit.TV.ro":                 47,    // HD variant
        "Favorit.TV.ro":                49,
        "Travel.Mix.ro":                50,    // only HD variant on grid
        "PRO.2.HD.ro":                  51,    // rebranded as "Acasa HD"
        "PRO.2.ro":                     52,    // rebranded as "Acasa"
        "B1.TV.ro":                     56,
        "Romania.TV.ro":                58,
        "Digi.24.HD.ro":                59,
        "Digi.24.ro":                   60,
        "Antena.3.CNN.HD.ro":           61,    // listed as "Antena 3 HD" on grila
        "Antena.3.CNN.ro":              62,
        "Realitatea.Plus.ro":           64,
        "CNN.International.us":          69,
        "BBC.World.News.uk":            71,
        "Pro.Gold.ro":                  79,    // rebranded as "Acasa Gold"
        "Film.Now.HD.ro":               80,
        "Film.Now.ro":                  81,
        "Pro.Cinema.ro":                83,
        "Diva.ro":                      85,
        "AXN.HD.ro":                    89,
        "AXN.ro":                       90,
        "AXN.White.ro":                 91,
        "AXN.Black.ro":                 92,
        "AXN.Spin.ro":                  93,
        "Epic.Drama.ro":                95,
        "Film.Cafe.ro":                 99,
        "Comedy.Central.ro":           100,
        "HBO.HD.ro":                   103,
        "HBO.ro":                       104,
        "HBO.2.HD.ro":                 105,
        "HBO.2.ro":                     106,
        "HBO.3.HD.ro":                 107,
        "HBO.3.ro":                     108,
        "Cinemax.HD.ro":               109,
        "Cinemax.ro":                   110,
        "Cinemax.2.ro":                 111,   // HD only on grid
        "Bollywood.TV.ro":             115,    // listed as "Bollywood Clasic"
        "Nickelodeon.ro":              120,
        "Minimax.ro":                  121,
        "Cartoon.Network.ro":          122,
        "Disney.Channel.ro":           123,
        "Disney.Junior.ro":            124,
        "Duck.TV.ro":                  126,
        "Nick.Jr.ro":                  129,
        "DaVinci.Learning.ro":         131,
        "Digi.World.HD.ro":            133,
        "Digi.World.ro":               134,
        "Digi.Life.HD.ro":             135,
        "Digi.Life.ro":                136,
        "Digi.Animal.World.HD.ro":     137,
        "Digi.Animal.World.ro":        138,
        "Discovery.Channel.ro":        140,
        "TLC.ro":                      141,
        "History.HD.ro":               142,
        "History.ro":                  143,
        "National.Geographic.HD.ro":   144,
        "National.Geographic.ro":      145,
        "Viasat.Nature.History.HD.ro": 146,    // "Viasat Nature HD" on grila
        "Viasat.Nature.ro":            147,
        "TV.Paprika.ro":               148,
        "BBC.Earth.ro":                152,
        "Nat.Geo.Wild.HD.ro":          153,
        "Nat.Geo.Wild.ro":             154,
        "Viasat.Explore.ro":           156,
        "Viasat.History.ro":           158,
        "Fashion.TV.fr":               162,
        "E.Entertainment.HD.ro":       163,
        "E.Entertainment.ro":          164,
        "Trinitas.TV.ro":              166,
        "Credo.TV.ro":                 169,    // HD only
        "Alfa.Omega.TV.ro":            170,    // HD only
        "Speranta.TV.ro":              172,
        "U.TV.HD.ro":                  174,
        "U.TV.ro":                     175,    // "U Televiziune Interactiva"
        "Kiss.TV.ro":                  176,
        "Hit.Music.Channel.ro":        177,
        "Music.Channel.ro":            179,
        "ZU.TV.HD.ro":                 180,
        "ZU.TV.ro":                    181,
        "Mezzo.ro":                    183,
        "Hora.TV.ro":                  189,    // only HD variant on digital
        "Taraf.TV.ro":                 192,
        "Nasul.TV.ro":                 193,
        "Agro.TV.ro":                  194,
        "Fishing.and.Hunting.ro":      195,
        "TV5.Monde.fr":                197,
        "Super.RTL.de":                198,
        "RTL.Television.de":           199,
        "Rai.1.it":                    200,
        "M1.Europa.hu":                206,    // listed simply as "M1"
        "SuperOne.HD.ro":              212,
        "SuperOne.ro":                 213
    ]
    
    static let mappingCategory: [String: Int] = [
        
        // MARK: - General / News
        "TVR.1.ro":                  23,
        "TVR.2.ro":                  25,
        "TVR.HD.ro":                 22,    // TVR 1 HD
        "PRO.TV.ro":                 28,
        "PRO.TV.HD.ro":              27,
        "Antena.1.ro":               30,
        "Antena.1.HD.ro":            29,
        "Kanal.D.ro":                32,
        "Kanal.D.HD.ro":             31,
        "Prima.TV.ro":               34,
        "National.TV.ro":            39,
        "Digi.24.ro":                60,
        "Digi.24.HD.ro":             59,
        "Realitatea.Plus.ro":        64,
        "Antena.3.CNN.ro":           62,
        "Antena.3.CNN.HD.ro":        61,    // listed as "Antena 3 HD" on grila
        "Romania.TV.ro":             58,
        "B1.TV.ro":                  56,

        // MARK: - Sport
        "Digi.Sport.1.ro":            1,
        "Digi.Sport.1.HD.ro":         2,
        "Digi.Sport.2.ro":            4,
        "Digi.Sport.2.HD.ro":         3,
        "Digi.Sport.3.ro":            6,
        "Digi.Sport.3.HD.ro":         5,
        // "Digi.Sport.4.ro":         //  not on digital (satelit pos 6 only)
        "Digi.Sport.4.HD.ro":         7,
        "PRO.X.ro":                  20,    // rebranded as "PRO ARENA"
        "PRO.X.HD.ro":               19,    // rebranded as "PRO ARENA HD"
        "Eurosport.1.ro":             9,    // listed as "Eurosport RO"
        "Eurosport.1.HD.ro":          8,    // listed as "Eurosport HD"
        "Eurosport.2.ro":            11,
        "Eurosport.2.HD.ro":         10,

        // MARK: - Home / Entertainment
        "PRO.2.ro":                  52,    // rebranded as "Acasa"
        "PRO.2.HD.ro":               51,    // rebranded as "Acasa HD"
        "Pro.Gold.ro":               79,    // rebranded as "Acasa Gold"
        "Happy.Channel.ro":          36,
        "Happy.Channel.HD.ro":       35,
        "Antena.Stars.ro":           38,
        "Antena.Stars.HD.ro":        37,
        "TV.Paprika.ro":            148,

        // MARK: - Science / Documentary
        "Digi.World.ro":            134,
        "Digi.World.HD.ro":         133,
        "Digi.Life.ro":             136,
        "Digi.Life.HD.ro":          135,
        "Digi.Animal.World.ro":     138,
        "Digi.Animal.World.HD.ro":  137,
        "Discovery.Channel.ro":     140,
        "TLC.ro":                   141,
        "History.ro":               143,
        "History.HD.ro":            142,
        "National.Geographic.ro":          145,
        "National.Geographic.HD.ro":       144,
        "Viasat.Nature.ro":         147,
        "Viasat.Nature.History.HD.ro":     146,    // "Viasat Nature HD" on grila
        // "Travel.Channel.ro":     //  no longer carried
        // "Travel.Channel.HD.ro":  //  no longer carried (Travel Mix HD = 50)
        "BBC.Earth.ro":             152,
        "Nat.Geo.Wild.ro":          154,
        "Nat.Geo.Wild.HD.ro":       153,
        "Viasat.Explore.ro":        156,
        "Viasat.History.ro":        158,
        // "DOQ.ro":                //  no longer carried
        "Travel.Mix.ro":             50,    // only HD variant on grid

        // MARK: - Film
        "Film.Now.ro":               81,
        "Film.Now.HD.ro":            80,
        "Pro.Cinema.ro":             83,
        "Diva.ro":                   85,
        // "TV1000.ro":             //  no longer carried
        // "Paramount.Channel.ro":  //  no longer carried
        "AXN.ro":                    90,
        "AXN.HD.ro":                 89,
        "AXN.White.ro":              91,
        "AXN.Black.ro":              92,
        "AXN.Spin.ro":               93,
        // "TNT.ro":                //  rebranded as "Warner TV" (= 94)
        "Epic.Drama.ro":             95,
        "Bollywood.TV.ro":          115,    // listed as "Bollywood Clasic"
        "E.Entertainment.ro":       164,
        "E.Entertainment.HD.ro":    163,
        "Film.Cafe.ro":              99,
        "Comedy.Central.ro":        100,

        // MARK: - Cartoon / Kids
        "Nickelodeon.ro":           120,
        "Minimax.ro":               121,
        "Cartoon.Network.ro":       122,
        "Disney.Channel.ro":        123,
        "Disney.Junior.ro":         124,
        // "Boomerang.ro":          //  rebranded as "Cartoonito" (= 125)
        "Duck.TV.ro":               126,
        // "Megamax.ro":            //  no longer carried
        "Nick.Jr.ro":               129,
        "DaVinci.Learning.ro":      131,

        // MARK: - Music
        "U.TV.ro":                  175,    // "U Televiziune Interactiva"
        "U.TV.HD.ro":               174,
        "Kiss.TV.ro":               176,
        "Hit.Music.Channel.ro":     177,
        // "VH1.ro":                //  no longer carried
        "Mezzo.ro":                 183,
        "Music.Channel.ro":         179,
        // "Music.Channel.International.ro": // no longer carried
        "ZU.TV.ro":                 181,
        "ZU.TV.HD.ro":              180,

        // MARK: - Romanian folk / traditional
        "Favorit.TV.ro":             49,
        "Etno.TV.ro":                43,
        "Hora.TV.ro":               189,    // only HD variant on digital
        "Taraf.TV.ro":              192,

        // MARK: - Mix / Regional
        "Agro.TV.ro":               194,
        // "Digi.24.Cluj.ro":       //  no longer carried (regional)
        // "Profit.TV.ro":          //  no longer carried
        // "Look.Sport.ro":         //  rebranded as Prima Sport (1=13, 2=15, 3=17)
        // "Look.Plus.ro":          //  no longer carried
        // "TV.Neptun.ro":          //  no longer carried
        // "Estrada.TV.ro":         //  no longer carried
        // "Erdely.TV.ro":          //  no longer carried
        // "Tarnava.TV.ro":         //  no longer carried
        // "TTM.ro":                //  no longer carried
        // "Ardeal.TV.ro":          //  no longer carried
        "Nasul.TV.ro":              193,
        // "TV.H.ro":               //  no longer carried
        // "TV.Sud.Est.ro":         //  no longer carried
        "Inedit.TV.ro":              47,    // HD variant
        "CNN.International.us":      69,
        "TVR.3.ro":                  26,
        "National.24.Plus.ro":       40,
        // "Telestar.1.ro":         //  no longer carried

        // MARK: - Magyar / Hungarian (most are satelit-only on the new grid; commented out where no digital position exists)
        // "Minimax.hu":            //  satelit 122 only
        // "Duna.TV.hu":            //  satelit 117 only
        // "Echo.TV.hu":            //  no longer carried
        "M1.Europa.hu":             206,    // listed simply as "M1"
        // "M2.Europa.hu":          //  satelit 103 only
        // "RTL.Klub.hu":           //  rebranded "RTL HU", satelit 106 only
        // "RTL.2.hu":              //  rebranded "RTL Ketto", satelit 109 only
        // "Film.Plus.hu":          //  satelit 110 only
        // "Cool.TV.hu":            //  satelit 111 only
        // "Comedy.Central.Family.hu": // no longer carried
        // "RTL.Plus.hu":           //  rebranded "RTL HAROM", satelit 112 only
        // "Film.4.hu":             //  satelit 113 only
        // "Comedy.Central.hu":     //  same channel as Comedy.Central.ro (= 100)
        // "Viasat.3.hu":           //  no longer carried
        // "ATV.hu":                //  satelit 114 only
        // "Slager.TV.hu":          //  satelit 119 only
        // "TV.4.hu":                //  satelit 120 only
        // "Sorozat.Plus.hu":       //  satelit 121 only
        // "M4.Sport.Europa.hu":    //  no longer carried
        // "M5.hu":                 //  satelit 104 only

        // MARK: - Faith / international / premium
        "Trinitas.TV.ro":           166,
        "Speranta.TV.ro":           172,
        "Alfa.Omega.TV.ro":         170,    // HD only
        "Credo.TV.ro":              169,    // HD only
        "Fishing.and.Hunting.ro":   195,
        "TV5.Monde.fr":             197,
        // "STV.1.sk":              //  no longer carried
        // "RTS.Satelit.rs":        //  no longer carried
        "Rai.1.it":                 200,
        "RTL.Television.de":        199,
        "BBC.World.News.uk":         71,
        "Fashion.TV.fr":            162,
        "Super.RTL.de":             198,
        // "CGTN.cn":               //  no longer carried
        "SuperOne.ro":              213,
        "SuperOne.HD.ro":           212,
        "HBO.ro":                   104,
        "HBO.HD.ro":                103,
        "HBO.2.ro":                 106,
        "HBO.2.HD.ro":              105,
        "HBO.3.ro":                 108,
        "HBO.3.HD.ro":              107,
        "Cinemax.ro":               110,
        "Cinemax.HD.ro":            109,
        "Cinemax.2.ro":             111     // HD only on grid
    ]

    /// Lookup the TV channel number for an EPG channel id. Nil when the id isn't in
    /// the table — the UI hides the Tune button in that case rather than guessing.
    static func number(for channelID: String) -> Int? {
        mapping[channelID]
    }

    /// TV channel number → EPG channel id — the inverse of ``mapping``, built once. Lets the
    /// remote turn a tuned channel *number* (all it can know from the digits it sent) back
    /// into a channel id so the "Now on TV" pill can show what's playing. Numbers are unique
    /// in the table, so the inverse is unambiguous; the `uniquingKeysWith` is belt-and-braces.
    static let idByNumber: [Int: String] = Dictionary(
        mapping.map { ($0.value, $0.key) },
        uniquingKeysWith: { existing, _ in existing }
    )

    /// The EPG channel id at TV channel `number`, or nil when that number isn't in the
    /// lineup — in which case the caller shows nothing rather than guessing a wrong channel.
    static func channelID(forNumber number: Int) -> String? {
        idByNumber[number]
    }

    /// All ids that are known and tunable. Used by the EPG list to show a small
    /// channel-number badge next to known channels.
    static var knownIDs: Set<String> { Set(mapping.keys) }

    /// Every id in ``mapping``, ordered by TV channel number ascending — i.e. the
    /// order the mapping is written in. This is the canonical display order for the
    /// EPG channel list, which shows the user's whole lineup regardless of what the
    /// daily feed happens to include.
    static var orderedIDs: [String] {
        mapping.sorted { $0.value < $1.value }.map(\.key)
    }

    /// Best-effort human-readable name derived from an EPG channel id, for channels
    /// that are in ``mapping`` but absent from today's feed (so we have no
    /// `<display-name>` to show). Drops a trailing two-letter country code and turns
    /// dots into spaces: `"Antena.3.CNN.HD.ro"` → `"Antena 3 CNN HD"`.
    static func displayName(for channelID: String) -> String {
        var parts = channelID.split(separator: ".").map(String.init)
        if let last = parts.last, last.count == 2,
           last.allSatisfy({ $0.isLetter && $0.isLowercase }) {
            parts.removeLast()
        }
        return parts.isEmpty ? channelID : parts.joined(separator: " ")
    }
}
