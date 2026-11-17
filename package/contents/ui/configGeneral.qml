import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showCurrentOnly: currentOnlyCheck.checked
    property alias cfg_animate: animateCheck.checked
    property alias cfg_animationStyle: styleCombo.currentIndex
    property alias cfg_animationDuration: durationSpin.value
    property alias cfg_contextLines: contextSpin.value
    property alias cfg_fontSize: fontSpin.value
    property alias cfg_offsetMs: offsetSpin.value
    property alias cfg_showTrackInfo: trackInfoCheck.checked
    property alias cfg_playerName: playerField.text
    property alias cfg_lyricsSource: sourceCombo.currentIndex

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Lyrics")
        }
        QQC2.ComboBox {
            id: sourceCombo
            Kirigami.FormData.label: i18n("Default source:")
            model: [
                i18n("LRCLib (synced)"),
                i18n("YouTube Music"),
                i18n("Genius")
            ]
        }
        QQC2.Label {
            text: i18n("If no lyrics are found, the other sources are tried automatically.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Display")
        }
        QQC2.CheckBox {
            id: currentOnlyCheck
            text: i18n("Show only the current lyric line")
        }
        QQC2.SpinBox {
            id: contextSpin
            Kirigami.FormData.label: i18n("Lines above/below:")
            from: 1
            to: 6
            enabled: !currentOnlyCheck.checked
        }
        QQC2.CheckBox {
            id: trackInfoCheck
            text: i18n("Show artist and title")
        }
        QQC2.SpinBox {
            id: fontSpin
            Kirigami.FormData.label: i18n("Font size (px):")
            from: 10
            to: 96
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Animation")
        }
        QQC2.CheckBox {
            id: animateCheck
            text: i18n("Animate between lines")
        }
        QQC2.ComboBox {
            id: styleCombo
            Kirigami.FormData.label: i18n("Style (current line only):")
            model: [i18n("Fade"), i18n("Fade and slide up")]
            enabled: animateCheck.checked && currentOnlyCheck.checked
        }
        QQC2.SpinBox {
            id: durationSpin
            Kirigami.FormData.label: i18n("Duration (ms):")
            from: 100
            to: 1500
            stepSize: 50
            enabled: animateCheck.checked
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Player")
        }
        QQC2.SpinBox {
            id: offsetSpin
            Kirigami.FormData.label: i18n("Timing offset (ms):")
            from: -5000
            to: 5000
            stepSize: 100
            editable: true
        }
        QQC2.Label {
            text: i18n("Positive values show lyrics earlier, negative later.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.TextField {
            id: playerField
            Kirigami.FormData.label: i18n("Player name:")
            placeholderText: i18n("Empty = any player (see `playerctl -l`)")
        }
    }
}
