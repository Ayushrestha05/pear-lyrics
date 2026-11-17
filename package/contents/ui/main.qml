import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // ---- settings (see the widget's Configure dialog) ----
    readonly property string playerName: Plasmoid.configuration.playerName
    readonly property real offsetSec: Plasmoid.configuration.offsetMs / 1000
    readonly property int contextLines: Plasmoid.configuration.contextLines
    readonly property int baseFontPx: Plasmoid.configuration.fontSize
    readonly property bool showCurrentOnly: Plasmoid.configuration.showCurrentOnly
    readonly property bool showTrackInfo: Plasmoid.configuration.showTrackInfo
    readonly property bool animate: Plasmoid.configuration.animate
    readonly property int animStyle: Plasmoid.configuration.animationStyle   // 0 fade, 1 fade + slide
    readonly property int animMs: animate ? Plasmoid.configuration.animationDuration : 0
    readonly property int lyricsSource: Plasmoid.configuration.lyricsSource   // 0 LRCLib, 1 YouTube Music, 2 Genius

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ---- state ----
    property string status: "Stopped"
    property string artist: ""
    property string title: ""
    property real lengthSec: 0
    property real basePosSec: 0
    property double baseTimeMs: 0
    property real nowSec: 0
    property var lyrics: []
    property bool synced: true
    property string lyricsSourceName: ""
    property string message: "Waiting for player…"
    property int fetchToken: 0
    property string trackKey: ""

    property int currentIndex: {
        if (!synced) return -1
        var t = nowSec + offsetSec
        var idx = -1
        for (var i = 0; i < lyrics.length; i++) {
            if (lyrics[i].t <= t) idx = i
            else break
        }
        return idx
    }

    readonly property string currentText: {
        if (lyrics.length === 0 || currentIndex < 0) return ""
        var s = lyrics[currentIndex].text
        return s === "" ? "♪" : s
    }

    readonly property string pollCmd: "playerctl "
        + (playerName ? "-p '" + playerName.replace(/'/g, "'\\''") + "' " : "")
        + "metadata --format '{{status}} ::: {{artist}} ::: {{title}} ::: {{mpris:length}} ::: {{position}}' 2>/dev/null"

    // ---- helpers ----
    function cleanTitle(s) {
        return s.replace(/\s*[\(\[][^\)\]]*(official|video|audio|lyrics?|visualizer|remaster|hd|hq|mv)[^\)\]]*[\)\]]/gi, "").trim()
    }
    function cleanArtist(s) {
        return s.replace(/\s*-\s*Topic$/i, "").trim()
    }
    function firstArtist(s) {
        return s.split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i)[0]
    }

    function handlePoll(out) {
        var p = out.split(" ::: ")
        if (p.length < 5) {
            status = "Stopped"
            if (lyrics.length === 0)
                message = "No player found (is Pear running? check `playerctl -l`)"
            return
        }
        status = p[0]
        var a = cleanArtist(p[1])
        var t = cleanTitle(p[2])
        lengthSec = (parseInt(p[3]) || 0) / 1e6
        basePosSec = (parseInt(p[4]) || 0) / 1e6
        baseTimeMs = Date.now()
        var key = a + "|" + t
        if (key !== trackKey) {
            trackKey = key
            artist = a
            title = t
            lyrics = []
            message = "Searching lyrics…"
            fetchLyrics(a, t, lengthSec)
        }
    }

    // ---- network helpers ----
    readonly property string browserUa: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    readonly property string ytMusicKey: "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    function getText(url, cb, accept) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            cb(xhr.status === 200 ? xhr.responseText : null)
        }
        xhr.open("GET", url)
        xhr.setRequestHeader("User-Agent", browserUa)
        if (accept) xhr.setRequestHeader("Accept", accept)
        xhr.send()
    }

    function getJson(url, cb) {
        getText(url, function (body) {
            if (!body) { cb(null); return }
            try { cb(JSON.parse(body)) } catch (e) { cb(null) }
        }, "application/json, text/plain, */*")
    }

    function postJson(url, body, cb) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) { cb(null); return }
            try { cb(JSON.parse(xhr.responseText)) } catch (e) { cb(null) }
        }
        xhr.open("POST", url)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("User-Agent", browserUa)
        xhr.send(JSON.stringify(body))
    }

    // ---- lyrics sources ----
    function sourceKey(index) {
        return index === 1 ? "ytmusic" : index === 2 ? "genius" : "lrclib"
    }
    function sourceLabel(key) {
        return key === "ytmusic" ? "YouTube Music" : key === "genius" ? "Genius" : "LRCLib"
    }
    function sourceOrder() {
        var all = ["lrclib", "ytmusic", "genius"]
        var chosen = sourceKey(lyricsSource)
        var order = [chosen]
        for (var i = 0; i < all.length; i++)
            if (all[i] !== chosen) order.push(all[i])
        return order
    }

    function fetchLyrics(a, t, dur) {
        var token = ++fetchToken
        lyrics = []
        synced = true
        lyricsSourceName = ""
        trySource(sourceOrder(), 0, token, a, t, dur, null)
    }

    onLyricsSourceChanged: {
        if (trackKey !== "" && title !== "")
            fetchLyrics(artist, title, lengthSec)
    }

    function trySource(order, i, token, a, t, dur, fallback) {
        if (token !== fetchToken) return
        if (i >= order.length) {
            lyrics = []
            if (fallback) {
                lyricsSourceName = sourceLabel(fallback.source)
                applyLines(fallback.lines, false)
            } else {
                synced = true
                lyricsSourceName = ""
                message = "No lyrics found"
            }
            return
        }
        var src = order[i]
        message = "Searching " + sourceLabel(src) + "…"
        var cb = function (lines, isSynced) {
            if (token !== fetchToken) return
            if (!lines || !lines.length) {
                trySource(order, i + 1, token, a, t, dur, fallback)
                return
            }
            if (isSynced) {
                lyricsSourceName = sourceLabel(src)
                applyLines(lines, true)
            } else {
                // Remember plain lyrics but keep looking for a synced version.
                trySource(order, i + 1, token, a, t, dur, { lines: lines, source: src })
            }
        }
        if (src === "ytmusic") fetchYtMusic(a, t, cb)
        else if (src === "genius") fetchGenius(a, t, cb)
        else fetchLrclib(a, t, dur, cb)
    }

    function applyLines(lines, isSynced) {
        if (isSynced) lines.sort(function (x, y) { return x.t - y.t })
        lyrics = lines
        synced = isSynced
        message = lines.length ? "" : "No lyrics found"
    }

    function plainToLines(text) {
        var out = []
        if (!text) return out
        var raw = String(text).replace(/\r/g, "").split("\n")
        for (var i = 0; i < raw.length; i++) {
            var s = raw[i].replace(/^\s+|\s+$/g, "")
            if (s !== "") out.push({ t: 0, text: s })
        }
        return out
    }

    function parseLrc(lrc) {
        var out = []
        if (!lrc) return out
        var lines = String(lrc).replace(/\r/g, "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^((?:\[\d+:\d+(?:\.\d+)?\])+)\s*(.*)$/)
            if (!m) continue
            var re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
            var tm
            while ((tm = re.exec(m[1])) !== null)
                out.push({ t: parseInt(tm[1]) * 60 + parseFloat(tm[2]), text: m[2] })
        }
        return out
    }

    // ---- LRCLib ----
    function fetchLrclib(a, t, dur, cb) {
        var q = "artist_name=" + encodeURIComponent(a) + "&track_name=" + encodeURIComponent(t)
        getJson("https://lrclib.net/api/get?" + q + "&duration=" + Math.round(dur), function (r) {
            if (r && r.syncedLyrics) {
                var syncedLines = parseLrc(r.syncedLyrics)
                if (syncedLines.length) { cb(syncedLines, true); return }
            }
            if (r && r.plainLyrics) {
                var plainLines = plainToLines(r.plainLyrics)
                if (plainLines.length) { cb(plainLines, false); return }
            }
            var q2 = "artist_name=" + encodeURIComponent(firstArtist(a)) + "&track_name=" + encodeURIComponent(t)
            getJson("https://lrclib.net/api/search?" + q2, function (list) {
                var best = null
                var bestPlain = null
                if (list) {
                    for (var i = 0; i < list.length; i++) {
                        var item = list[i]
                        if (dur > 0 && Math.abs((item.duration || 0) - dur) >= 10) continue
                        if (item.syncedLyrics) {
                            if (!best || dur <= 0 || Math.abs(item.duration - dur) < Math.abs(best.duration - dur))
                                best = item
                        } else if (item.plainLyrics) {
                            if (!bestPlain || dur <= 0 || Math.abs(item.duration - dur) < Math.abs(bestPlain.duration - dur))
                                bestPlain = item
                        }
                    }
                }
                if (best) {
                    var sl = parseLrc(best.syncedLyrics)
                    if (sl.length) { cb(sl, true); return }
                }
                if (bestPlain) {
                    var pl = plainToLines(bestPlain.plainLyrics)
                    if (pl.length) { cb(pl, false); return }
                }
                cb(null)
            })
        })
    }

    // ---- YouTube Music (InnerTube) ----
    function findValue(obj, key) {
        if (!obj || typeof obj !== "object") return null
        if (Array.isArray(obj)) {
            for (var i = 0; i < obj.length; i++) {
                var r = findValue(obj[i], key)
                if (r !== null && r !== undefined) return r
            }
            return null
        }
        if (obj[key] !== undefined) return obj[key]
        for (var k in obj) {
            var v = findValue(obj[k], key)
            if (v !== null && v !== undefined) return v
        }
        return null
    }

    function ytCandidates(obj, out) {
        if (!obj || typeof obj !== "object") return
        if (Array.isArray(obj)) {
            for (var i = 0; i < obj.length; i++) ytCandidates(obj[i], out)
            return
        }
        if (obj.musicResponsiveListItemRenderer) {
            var r = obj.musicResponsiveListItemRenderer
            var vid = findValue(r, "videoId")
            if (!vid) return
            var cols = []
            if (r.flexColumns) {
                for (var c = 0; c < r.flexColumns.length; c++) {
                    var col = r.flexColumns[c].musicResponsiveListItemFlexColumnRenderer
                    var text = ""
                    if (col && col.text) {
                        if (col.text.simpleText) text = col.text.simpleText
                        else if (col.text.runs) {
                            for (var k = 0; k < col.text.runs.length; k++)
                                text += (col.text.runs[k].text || "")
                        }
                    }
                    cols.push(text)
                }
            }
            out.push({ id: vid, title: cols[0] || "", artist: (cols[1] || "").split("•")[0] })
            return
        }
        for (var key in obj) ytCandidates(obj[key], out)
    }

    function ytRankCandidates(candidates, a, t) {
        var wantArtist = normalize(firstArtist(a))
        var wantTitle = normalize(t)
        var ranked = []
        for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i]
            if (/originally performed|karaoke|tribute|parody|made famous|instrumental/i.test(c.title)) continue
            var title = normalize(c.title)
            var artist = normalize(c.artist)
            var titleMatch = wantTitle && (title === wantTitle
                || title.indexOf(wantTitle) >= 0 || wantTitle.indexOf(title) >= 0)
            var artistMatch = !wantArtist || artist.indexOf(wantArtist) >= 0
            if (!titleMatch || !artistMatch) continue
            var score = (title === wantTitle) ? 2 : 1
            if (artistMatch && wantArtist) score += 2
            ranked.push({ id: c.id, score: score })
        }
        ranked.sort(function (x, y) { return y.score - x.score })
        return ranked
    }

    function ytRequest(endpoint, body, cb) {
        postJson("https://music.youtube.com/youtubei/v1/" + endpoint
                 + "?alt=json&key=" + ytMusicKey, body, cb)
    }

    function fetchYtMusic(a, t, cb) {
        ytRequest("search", {
            context: { client: { clientName: "WEB_REMIX", clientVersion: "1.20240101.01.00" } },
            query: a + " " + t,
            params: "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        }, function (res) {
            var candidates = []
            ytCandidates(res, candidates)
            var ranked = ytRankCandidates(candidates, a, t)
            var ids = []
            for (var i = 0; i < ranked.length && i < 3; i++) ids.push(ranked[i].id)
            ytTryVideoIds(ids, 0, cb)
        })
    }

    function ytTryVideoIds(ids, i, cb) {
        if (i >= ids.length) { cb(null); return }
        ytRequest("next", {
            context: { client: { clientName: "WEB_REMIX", clientVersion: "1.20240101.01.00" } },
            videoId: ids[i]
        }, function (res) {
            var browseId = ytLyricsBrowseId(res)
            if (!browseId) { ytTryVideoIds(ids, i + 1, cb); return }
            ytFetchLyrics(browseId, function (lines, isSynced) {
                if (lines && lines.length) cb(lines, isSynced)
                else ytTryVideoIds(ids, i + 1, cb)
            })
        })
    }

    function ytLyricsBrowseId(res) {
        var watch = findValue(res, "watchNextTabbedResultsRenderer")
        if (!watch || !watch.tabs) return null
        for (var i = 0; i < watch.tabs.length; i++) {
            var tab = watch.tabs[i].tabRenderer
            var endpoint = tab && tab.endpoint && tab.endpoint.browseEndpoint
            var configs = endpoint && endpoint.browseEndpointContextSupportedConfigs
            var music = configs && configs.browseEndpointContextMusicConfig
            if (music && music.pageType === "MUSIC_PAGE_TYPE_TRACK_LYRICS")
                return endpoint.browseId
        }
        return null
    }

    function ytFetchLyrics(browseId, cb) {
        ytRequest("browse", {
            context: { client: { clientName: "ANDROID_MUSIC", clientVersion: "7.21.50" } },
            browseId: browseId
        }, function (res) {
            var timed = findValue(res, "timedLyricsData")
            if (timed && timed.length) {
                var lines = []
                var allTimed = true
                for (var i = 0; i < timed.length; i++) {
                    var cue = timed[i].cueRange
                    var text = timed[i].lyricLine
                    if (!cue || cue.startTimeMilliseconds === undefined) { allTimed = false; continue }
                    var ms = parseFloat(cue.startTimeMilliseconds)
                    lines.push({ t: isNaN(ms) ? 0 : ms / 1000, text: text || "" })
                }
                if (lines.length && allTimed) { cb(lines, true); return }
                if (lines.length) {
                    var plain = []
                    for (var j = 0; j < timed.length; j++)
                        if (timed[j].lyricLine) plain.push(timed[j].lyricLine)
                    if (plain.length) { cb(plainToLines(plain.join("\n")), false); return }
                }
            }
            var desc = ytDescription(res)
            if (desc) { cb(plainToLines(desc), false); return }
            // Some tracks expose plain lyrics only to the web client.
            ytRequest("browse", {
                context: { client: { clientName: "WEB_REMIX", clientVersion: "1.20240101.01.00" } },
                browseId: browseId
            }, function (res2) {
                var d2 = ytDescription(res2)
                cb(d2 ? plainToLines(d2) : null, false)
            })
        })
    }

    function ytDescription(res) {
        var shelf = findValue(res, "musicDescriptionShelfRenderer")
        if (!shelf || !shelf.description) return null
        var d = shelf.description
        var text = d.simpleText || ""
        if (!text && d.runs) {
            for (var i = 0; i < d.runs.length; i++) text += (d.runs[i].text || "")
        }
        text = text.replace(/\s*Source:\s*[^\n]*\s*$/i, "").replace(/^\s+|\s+$/g, "")
        return text || null
    }

    // ---- Genius ----
    function normalize(s) {
        return String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, " ")
            .replace(/^\s+|\s+$/g, "")
    }

    function pickGeniusSong(data, a, t) {
        if (!data || !data.response || !data.response.sections) return null
        var sections = data.response.sections
        var wantArtist = normalize(firstArtist(a))
        var wantTitle = normalize(t)
        var bestUrl = null
        var bestScore = -1
        for (var i = 0; i < sections.length; i++) {
            var hits = sections[i].hits || []
            for (var j = 0; j < hits.length; j++) {
                var r = hits[j].result
                if (!r || r._type !== "song" || !r.url) continue
                if (/translation|romanization|übersetzung/i.test(r.full_title || "")) continue
                var artist = normalize(r.primary_artist_names)
                var title = normalize(r.title)
                var full = normalize(r.full_title)
                var titleMatch = wantTitle && (title === wantTitle
                    || title.indexOf(wantTitle) >= 0 || wantTitle.indexOf(title) >= 0
                    || full.indexOf(wantTitle) >= 0)
                var artistMatch = wantArtist && artist.indexOf(wantArtist) >= 0
                if (!titleMatch) continue
                var score = 1 + (artistMatch ? 3 : 0) + (title === wantTitle ? 2 : 0)
                if (score > bestScore) { bestScore = score; bestUrl = r.url }
            }
        }
        return bestUrl
    }

    function decodeEntities(s) {
        return s.replace(/&#x([0-9a-fA-F]+);/g, function (m, h) { return String.fromCharCode(parseInt(h, 16)) })
            .replace(/&#(\d+);/g, function (m, d) { return String.fromCharCode(parseInt(d, 10)) })
            .replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&nbsp;/g, " ")
            .replace(/&amp;/g, "&")
    }

    // Return the inner HTML of every balanced <div> that contains `needle`.
    function divBlocks(html, needle) {
        var out = []
        var tagRe = /<(\/?)div\b/gi
        var pos = 0
        while (true) {
            var at = html.indexOf(needle, pos)
            if (at < 0) break
            var openStart = html.lastIndexOf("<", at)
            var openEnd = html.indexOf(">", at)
            if (openStart < 0 || openEnd < 0) break
            var depth = 1
            var k = openEnd + 1
            var lastStart = openEnd
            while (depth > 0) {
                tagRe.lastIndex = k
                var m = tagRe.exec(html)
                if (!m) { lastStart = html.length; break }
                lastStart = m.index
                depth += m[1] === "/" ? -1 : 1
                k = tagRe.lastIndex
            }
            out.push(html.substring(openEnd + 1, lastStart))
            var closeEnd = html.indexOf(">", lastStart)
            pos = closeEnd < 0 ? html.length : closeEnd + 1
        }
        return out
    }

    function removeDivBlocks(html, needle) {
        var result = ""
        var tagRe = /<(\/?)div\b/gi
        var pos = 0
        while (true) {
            var at = html.indexOf(needle, pos)
            if (at < 0) break
            var openStart = html.lastIndexOf("<", at)
            var openEnd = html.indexOf(">", at)
            if (openStart < 0 || openEnd < 0) break
            var depth = 1
            var k = openEnd + 1
            var lastStart = openEnd
            while (depth > 0) {
                tagRe.lastIndex = k
                var m = tagRe.exec(html)
                if (!m) { lastStart = html.length; break }
                lastStart = m.index
                depth += m[1] === "/" ? -1 : 1
                k = tagRe.lastIndex
            }
            var closeEnd = html.indexOf(">", lastStart)
            result += html.substring(pos, openStart)
            pos = closeEnd < 0 ? html.length : closeEnd + 1
        }
        return result + html.substring(pos)
    }

    function extractGeniusLyrics(html) {
        var blocks = divBlocks(html, "data-lyrics-container=\"true\"")
        var parts = []
        for (var i = 0; i < blocks.length; i++) {
            var block = removeDivBlocks(blocks[i], "data-exclude-from-selection=\"true\"")
            block = block.replace(/<br\s*\/?>/gi, "\n")
            block = block.replace(/<[^>]*>/g, "")
            block = decodeEntities(block)
            var lines = block.replace(/\r/g, "").split("\n")
            var kept = []
            for (var j = 0; j < lines.length; j++) {
                var line = lines[j].replace(/^\s+|\s+$/g, "")
                if (line !== "") kept.push(line)
            }
            if (kept.length) parts.push(kept.join("\n"))
        }
        return parts.join("\n")
    }

    function fetchGenius(a, t, cb) {
        var q = encodeURIComponent(a + " " + t)
        getText("https://genius.com/api/search/multi?q=" + q, function (body) {
            if (!body) { cb(null); return }
            var data
            try { data = JSON.parse(body) } catch (e) { cb(null); return }
            var url = pickGeniusSong(data, a, t)
            if (!url) { cb(null); return }
            getText(url, function (html) {
                if (!html) { cb(null); return }
                var text = extractGeniusLyrics(html)
                cb(text ? plainToLines(text) : null, false)
            }, "text/html,application/xhtml+xml")
        }, "application/json, text/plain, */*")
    }

    // ---- data source: playerctl via the executable engine ----
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            root.handlePoll((data["stdout"] || "").trim())
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.pollCmd)
    }

    // smooth position between polls
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: root.nowSec = root.status === "Playing"
            ? root.basePosSec + (Date.now() - root.baseTimeMs) / 1000
            : root.basePosSec
    }

    // ---- UI ----
    fullRepresentation: Item {
        Layout.minimumWidth: 300
        Layout.minimumHeight: 160
        Layout.preferredWidth: 560
        Layout.preferredHeight: 280

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // message while there are no lyrics
            Text {
                visible: root.lyrics.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: root.message
                color: "white"
                style: Text.Outline
                styleColor: "#cc000000"
                font.pixelSize: root.baseFontPx
                opacity: 0.8
            }

            // mode 1: scrolling list with context lines
            ListView {
                id: list
                visible: root.lyrics.length > 0 && (!root.showCurrentOnly || !root.synced)
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                interactive: !root.synced
                cacheBuffer: 20000
                model: root.lyrics
                header: Item { width: list.width; height: root.synced ? list.height / 2 : 0 }
                footer: Item { width: list.width; height: list.height / 2 }

                function scrollToCurrent(instant) {
                    if (root.lyrics.length === 0) return
                    if (!root.synced) {
                        list.contentY = 0
                        return
                    }
                    var idx = Math.max(0, root.currentIndex)
                    var it = list.itemAtIndex(idx)
                    if (!it) {
                        list.positionViewAtIndex(idx, ListView.Center)
                        return
                    }
                    var target = it.y + it.height / 2 - list.height / 2
                    scrollAnim.stop()
                    if (instant || root.animMs <= 0) {
                        list.contentY = target
                    } else {
                        scrollAnim.to = target
                        scrollAnim.start()
                    }
                }

                NumberAnimation {
                    id: scrollAnim
                    target: list
                    property: "contentY"
                    duration: root.animMs
                    easing.type: Easing.InOutCubic
                }

                Connections {
                    target: root
                    function onCurrentIndexChanged() { list.scrollToCurrent(false) }
                    function onLyricsChanged() { Qt.callLater(list.scrollToCurrent, true) }
                    function onShowCurrentOnlyChanged() { Qt.callLater(list.scrollToCurrent, true) }
                }
                onHeightChanged: Qt.callLater(scrollToCurrent, true)
                Component.onCompleted: Qt.callLater(scrollToCurrent, true)

                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property bool isCur: root.synced && index === root.currentIndex
                    readonly property int dist: Math.abs(index - root.currentIndex)

                    width: list.width
                    height: lineText.implicitHeight + 10
                    opacity: !root.synced ? 0.9
                           : dist > root.contextLines ? 0
                           : (isCur ? 1.0 : Math.max(0.2, 0.6 - 0.15 * (dist - 1)))
                    Behavior on opacity {
                        NumberAnimation { duration: root.animMs; easing.type: Easing.OutQuad }
                    }

                    Text {
                        id: lineText
                        width: parent.width * 0.86
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: row.modelData.text !== "" ? row.modelData.text : (row.isCur ? "♪" : " ")
                        color: "white"
                        style: Text.Outline
                        styleColor: "#cc000000"
                        font.pixelSize: root.baseFontPx
                        transformOrigin: Item.Center
                        scale: row.isCur ? 1.15 : 1.0
                        Behavior on scale {
                            NumberAnimation { duration: root.animMs; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }

            // mode 2: current line only, animated swap
            Item {
                id: single
                visible: root.showCurrentOnly && root.synced && root.lyrics.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                property string target: root.currentText
                property string shown: ""
                property real slide: 0

                Component.onCompleted: shown = target
                onTargetChanged: {
                    if (root.animMs <= 0) {
                        swapAnim.stop()
                        shown = target
                        curText.opacity = 1
                        slide = 0
                    } else {
                        swapAnim.restart()
                    }
                }

                SequentialAnimation {
                    id: swapAnim
                    ParallelAnimation {
                        NumberAnimation {
                            target: curText; property: "opacity"; to: 0
                            duration: root.animMs / 2; easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: single; property: "slide"
                            to: root.animStyle === 1 ? -single.height * 0.12 : 0
                            duration: root.animMs / 2; easing.type: Easing.InQuad
                        }
                    }
                    ScriptAction {
                        script: {
                            single.shown = single.target
                            single.slide = root.animStyle === 1 ? single.height * 0.12 : 0
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: curText; property: "opacity"; to: 1
                            duration: root.animMs / 2; easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: single; property: "slide"; to: 0
                            duration: root.animMs / 2; easing.type: Easing.OutQuad
                        }
                    }
                }

                Text {
                    id: curText
                    width: parent.width * 0.9
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: single.slide
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: single.shown
                    color: "white"
                    style: Text.Outline
                    styleColor: "#cc000000"
                    font.pixelSize: Math.round(root.baseFontPx * 1.4)
                    font.bold: true
                }
            }

            Text {
                visible: root.showTrackInfo && root.title !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.artist + " — " + root.title
                      + (root.lyricsSourceName ? "  ·  " + root.lyricsSourceName : "")
                color: "white"
                style: Text.Outline
                styleColor: "#cc000000"
                font.pixelSize: Math.round(root.baseFontPx * 0.6)
                opacity: 0.6
            }
        }
    }
}
