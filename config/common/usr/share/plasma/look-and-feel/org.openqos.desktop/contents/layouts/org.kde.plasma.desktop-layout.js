// OpenQOS default panel layout.
//
// A look-and-feel package installs this as the layout a new Plasma user gets, so
// this is the single place that defines the shipped panel. Plasma runs it once,
// when a user's session is created.
//
// This is a deliberate derivation of KDE's own default panel
// (org.kde.plasma.desktop.defaultPanel in plasma-workspace, LGPL-2.0-or-later):
// the widget identifiers and the sizing arithmetic are KDE's, because they track
// Plasma's internal API, and guessing at them fails silently at session start
// rather than at build time.
//
// A typo in a widget name below is NOT a build error. It produces a panel with a
// missing widget, which only shows up when someone looks at a real session.

var panel = new Panel
var panelScreen = panel.screen

// No need to set panel.location: ShellCorona::addPanel picks an available edge.

// Sized for an icons-only task manager. Rounded up to the next even number
// because the panel size widget only displays even values.
panel.height = 2 * Math.ceil(gridUnit * 2.5 / 2)

// On very wide displays, centre the panel rather than stretching it edge to edge.
const maximumAspectRatio = 21 / 9;
if (panel.formFactor === "horizontal") {
    const geo = screenGeometry(panelScreen);
    const maximumWidth = Math.ceil(geo.height * maximumAspectRatio);

    if (geo.width > maximumWidth) {
        panel.alignment = "center";
        panel.minimumLength = maximumWidth;
        panel.maximumLength = maximumWidth;
    }
}

panel.addWidget("org.kde.plasma.kickoff")
panel.addWidget("org.kde.plasma.pager")
panel.addWidget("org.kde.plasma.icontasks")
panel.addWidget("org.kde.plasma.marginsseparator")

// Add the input-method panel widget only for locales likely to have an input
// method configured, rather than cluttering every user's panel with it. The list
// is KDE's: removing an entry is harmless, but adding one with no IME backend
// would put a dead widget in the panel.
var imeLanguageIds = ["as", "bn", "bo", "brx", "doi", "gu", "hi", "ja", "kn",
                      "ko", "kok", "ks", "lep", "mai", "ml", "mni", "mr", "ne",
                      "or", "pa", "sa", "sat", "sd", "si", "ta", "te", "th",
                      "ur", "vi", "zh_CN", "zh_TW"]

if (imeLanguageIds.indexOf(languageId) !== -1) {
    panel.addWidget("org.kde.plasma.kimpanel")
}

panel.addWidget("org.kde.plasma.systemtray")
panel.addWidget("org.kde.plasma.digitalclock")
panel.addWidget("org.kde.plasma.showdesktop")
