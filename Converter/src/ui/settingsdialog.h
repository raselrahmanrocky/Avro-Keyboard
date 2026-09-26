// settingsdialog.h - the main Settings dialog (gear menu -> Settings...).
//
// Shape
// -----
// A single page, top to bottom, and nothing else:
//
//   Unicode box    the top memo's family and point size
//   ANSI box       the bottom memo's family and point size
//   ANSI mappings  one row per mapping found in the mapping folder: its name,
//                  the font the user selected for it, right there next to the
//                  name, and a switch that only says whether that font is in
//                  use (off = "follow the ANSI box font for now"), plus the
//                  one bulk action underneath, which toggles every switch at
//                  once (all on -> hand them all to the box font, any off ->
//                  put them all back on their own)
//
// Deliberately flat: no tabs, no preview panes and no filter box, so every
// setting is on one screen and a font is edited on the row that carries it
// instead of in a separate "selected mapping" panel.  Only the row list
// scrolls, and only when the folder offers more mappings than fit.
//
// The theme stays in the gear menu (the three entries and their check marks),
// so there is no Appearance page here - switching a theme is a one-click
// action, not a settings form.
//
// Persistence contract
// --------------------
// The dialog persists nothing itself.  "Apply" (and "OK", which is Apply plus
// close) emits settingsApplied() and MainWindow writes the values, so the
// window updates live while the sheet stays open; "Cancel" discards everything
// that was not applied (the rollback path) and "Reset to Defaults" only stages
// the built-in defaults, which still need an Apply.
//
// The reset also hands every mapping the reset's own ANSI family as its own
// font (switched on).  Fonts it left empty would follow the box font, and a
// later edit of that box font would then rewrite all mapping rows at once -
// which is what the reset has to leave behind: mappings that hold what the reset
// gave them, with the box font free to change on its own.
//
// A mapping's family and its switch are two independent things, and the switch
// only ever meant "use it".  Turning a switch off leaves the family selected
// and on screen - it must never look like the font was reset - and the family
// is stored either way, which is why EditorFontSettings carries a family per
// mapping *and* the set of mappings that are switched off (see
// MappingFontRow).
#pragma once

#include <QAbstractButton>
#include <QDialog>
#include <QFont>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QWidget>

class QGroupBox;
class QLabel;
class QPushButton;
class QScrollArea;
class QSpinBox;
class QVBoxLayout;
class FontPicker;

// Point-size range shared with MainWindow (it clamps stored values).
namespace editorFont {
constexpr int kMinSize = 6;
constexpr int kMaxSize = 72;
constexpr int kDefaultSize = 13;
}  // namespace editorFont

// Everything the dialog shows and hands back.
struct EditorFontSettings {
    QString unicodeFont;
    int unicodeSize = editorFont::kDefaultSize;
    QString ansiFont;
    int ansiSize = editorFont::kDefaultSize;
    // Mapping version -> the family that version keeps as its own.  A version
    // that is missing here never had a font of its own and simply follows the
    // ANSI box font.
    QHash<QString, QString> mappingFonts;
    // The versions whose switch is off: they render with the ANSI box font
    // even though mappingFonts remembers a family for them.  A version that is
    // missing here is switched on.
    QSet<QString> mappingFontsOff;
};

// ---------------------------------------------------------------------------
// ToggleSwitch - the drawn on/off pill on every mapping row.
// ---------------------------------------------------------------------------
// A checkable QAbstractButton that paints itself.  On a row the switch is a
// state indicator first and a control second, so it is *drawn* (accent pill,
// light knob) instead of being a QCheckBox the platform style would paint its
// own way.  Extending QAbstractButton keeps the whole pill as the click target
// and keyboard toggling (Space) for free.
class ToggleSwitch : public QAbstractButton
{
    Q_OBJECT

public:
    explicit ToggleSwitch(QWidget* parent = nullptr);

    QSize sizeHint() const override;

protected:
    void paintEvent(QPaintEvent* event) override;
};

// ---------------------------------------------------------------------------
// MappingFontRow - one mapping: switch, name, and its own font selector.
// ---------------------------------------------------------------------------
// The row owns both halves of the setting and keeps them strictly apart:
//
//   * the family the picker next to the name shows (`m_custom`, else the ANSI
//     box font for a row that never got one), and
//   * the switch, which only says whether that family is *used*.
//
// Flipping the switch therefore never changes what the row shows: the font the
// user selected stays selected and stays on screen, on or off.  Off just means
// the mapping renders with the ANSI box font for now (renderedFont()), and it
// is stored with the switch off so a restart restores the same picture.  A row
// that is switched on before it ever had a family of its own starts from the
// ANSI box font, which is what it was rendering with anyway.
class MappingFontRow : public QWidget
{
    Q_OBJECT

public:
    explicit MappingFontRow(const QString& version, QWidget* parent = nullptr);

    QString version() const { return m_version; }
    // The family the row remembers as its own; empty when it never had one.
    QString customFont() const { return m_custom; }
    bool hasCustomFont() const { return !m_custom.isEmpty(); }
    bool isEnabled() const;
    // What the picker shows: the family the row has, else the ANSI box font.
    // Independent of the switch - that is the point of the row.
    QString displayFont() const;
    // The family this mapping actually renders with: displayFont() while the
    // switch is on, the ANSI box font while it is off.
    QString renderedFont() const;

    // Programmatic setters (initial load, Reset, "every mapping"): silent, so a
    // rebuild never looks like a user edit to the dialog.
    void setMappingFont(const QString& family, bool enabled);
    void setFallbackFont(const QString& family);
    // Flips the switch without touching the remembered family.
    void setSwitchOn(bool on);

    FontPicker* fontPicker() const { return m_picker; }
    ToggleSwitch* toggleSwitch() const { return m_switch; }
    QLabel* nameLabel() const { return m_name; }
    // Width of the name column, so the dialog can align the pickers of every
    // row on one vertical line.
    int nameColumnWidth() const;
    void setFixedNameWidth(int width);

signals:
    // The row's switch or font changed through the UI.
    void fontChanged();

private:
    void onToggled(bool on);
    void onFontPicked(const QString& family);
    // Moves the switch without emitting anything, so a programmatic change
    // never looks like a user edit (which is what onToggled() handles).
    void setSwitchChecked(bool on);
    // Puts the family the row renders with into the picker without emitting.
    void refreshPicker();
    void refreshToolTip();

    QString m_version;
    QString m_fallback;  // the ANSI box font
    QString m_custom;    // the family this row keeps as its own
    ToggleSwitch* m_switch = nullptr;
    QLabel* m_name = nullptr;
    FontPicker* m_picker = nullptr;
};

// ---------------------------------------------------------------------------
// SettingsDialog
// ---------------------------------------------------------------------------
class SettingsDialog : public QDialog
{
    Q_OBJECT

public:
    // `initial` is what the window shows right now, `defaults` the built-in
    // first-run values behind "Reset to Defaults" (MainWindow resolves the
    // bundled/system family names, the dialog cannot guess them).
    // `mappingVersions` get one row each, in this order.
    SettingsDialog(const EditorFontSettings& initial,
                   const EditorFontSettings& defaults,
                   const QStringList& mappingVersions,
                   QWidget* parent = nullptr);

    // The staged values - what Apply commits right now.
    EditorFontSettings settings() const;

public slots:
    // The OK button: hand the staged values over, then close.  Both halves run
    // here (not through the button box's own accept()) so nothing can close the
    // sheet without the window having been updated first.
    void accept() override;

signals:
    // Emitted by Apply (and by OK, before it closes).  MainWindow persists the
    // values and applies them to the editor; after Apply the dialog stays open
    // so more settings can be visited.
    void settingsApplied(const EditorFontSettings& settings);

private:
    // One labelled group with the family picker and the point size of a box.
    QGroupBox* buildFontGroup(const QString& title, const QString& pickerName,
                              const QString& sizeName, FontPicker** picker,
                              QSpinBox** spin);
    // The mapping rows plus the bulk action under them.
    QWidget* buildMappingSection(const QStringList& mappingVersions);

    void connectSignals();
    // Writes `values` into every widget without emitting anything.
    void loadIntoWidgets(const EditorFontSettings& values);

    // What "Reset to Defaults" stages: the built-in first-run values, with every
    // mapping holding that same ANSI family as its own (see the definition).
    EditorFontSettings defaultsForReset() const;

    // Rebuilds the mapping rows from scratch: the folder's versions, the
    // families the settings remember, the switches that are off, and the
    // fallback every switched-off row renders with.
    void rebuildMappingRows(const QStringList& versions,
                            const QHash<QString, QString>& remembered,
                            const QSet<QString>& off, const QString& fallback);
    // One shared name column width, so the pickers line up.
    void alignNameColumn();
    // Sizes the row list to the rows it holds, so the sheet stays a tidy box
    // (and only scrolls when a folder offers more mappings than fit).
    void fitRowAreaHeight();
    // Pins the smallest size the sheet may be resized to at the page it opens
    // with, so no corner drag can ever squeeze the rows or the footer.
    void lockMinimumToContent();
    // A new ANSI box font moves every row that is not using a font of its own.
    void setFallbackFont(const QString& family);
    // The families the rows remember, and the rows whose switch is off.
    QHash<QString, QString> mappingFonts() const;
    QSet<QString> mappingsOff() const;

    // The one bulk action under the rows: a master toggle.  With every row on it
    // hands them all to the ANSI box font, with any row off it puts them all back
    // on the family each row carries.
    void toggleAnsiBoxFontForEveryMapping();
    // Keeps that action - its label and its tooltip - saying what the next press
    // would do, so the toggle is never a one-way caption.
    void updateUseBoxFontAction();

    void applyStaged();

    EditorFontSettings m_initial;   // what the window shows right now
    EditorFontSettings m_defaults;  // built-in values for "Reset to Defaults"
    // The mappings the folder offers, in the order the version combo uses.
    QStringList m_versions;

    FontPicker* m_unicodeFont = nullptr;
    QSpinBox* m_unicodeSize = nullptr;

    FontPicker* m_ansiFont = nullptr;
    QSpinBox* m_ansiSize = nullptr;

    QScrollArea* m_mappingScroll = nullptr;
    QWidget* m_mappingRows = nullptr;
    QVBoxLayout* m_mappingRowsLayout = nullptr;
    QVector<MappingFontRow*> m_rows;
    QLabel* m_mappingEmpty = nullptr;
    QPushButton* m_useBoxFont = nullptr;
};
