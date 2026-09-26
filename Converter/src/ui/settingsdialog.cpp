#include "ui/settingsdialog.h"

#include "ui/fontpicker.h"

#include <QDialogButtonBox>
#include <QFrame>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QPushButton>
#include <QScrollArea>
#include <QSpinBox>
#include <QTimer>
#include <QVBoxLayout>

namespace {

// The row list hugs the rows it holds - the sheet stays a tidy, fixed size -
// and only turns into a scrolling box once a mapping folder offers more
// mappings than fit in the band between these two heights.
constexpr int kMinRowAreaHeight = 120;
constexpr int kMaxRowAreaHeight = 320;

// The family a picker should report: the committed one, else the first offer.
QString pickerFamily(const FontPicker* picker)
{
    const QString active = picker->activeFont();
    return active.isEmpty() ? picker->currentText() : active;
}

// Puts the committed family back into a picker whose browse was abandoned
// (Escape, or the popup closed without a commit).  FontPicker leaves whatever
// was typed in its edit box - its owner decides what to do about it - and here
// the box must not keep showing a query that neither the row nor Apply would
// ever use.
void restoreCommittedFamily(FontPicker* picker)
{
    const QString committed = picker->activeFont();
    if (!committed.isEmpty())
        picker->setActiveFont(committed);
}

}  // namespace

// ---------------------------------------------------------------------------
// ToggleSwitch
// ---------------------------------------------------------------------------

ToggleSwitch::ToggleSwitch(QWidget* parent)
    : QAbstractButton(parent)
{
    setCheckable(true);
    setCursor(Qt::PointingHandCursor);
    setFocusPolicy(Qt::StrongFocus);
    setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
}

QSize ToggleSwitch::sizeHint() const
{
    // 2:1 pill; the knob is inset 2px on either side (see paintEvent).
    return QSize(34, 18);
}

void ToggleSwitch::paintEvent(QPaintEvent*)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing, true);

    const QPalette& pal = palette();
    const QRect track = rect().adjusted(0, 0, -1, -1);
    const qreal radius = track.height() / 2.0;

    painter.setPen(Qt::NoPen);
    painter.setBrush(isEnabled() ? (isChecked() ? pal.color(QPalette::Highlight)
                                                : pal.color(QPalette::Mid))
                                 : pal.color(QPalette::Disabled, QPalette::Mid));
    painter.drawRoundedRect(track, radius, radius);

    const int knob = track.height() - 4;
    const QRect knobRect(isChecked() ? track.right() - knob - 1
                                     : track.left() + 2,
                         track.top() + 2, knob, knob);
    painter.setBrush(isChecked() ? QColor(Qt::white) : pal.color(QPalette::Base));
    painter.drawEllipse(knobRect);

    // A pill cannot show the platform's focus rect, so keyboard focus gets a
    // hairline ring of its own.
    if (hasFocus()) {
        QPen pen(pal.color(QPalette::Highlight));
        pen.setWidth(1);
        painter.setPen(pen);
        painter.setBrush(Qt::NoBrush);
        painter.drawRoundedRect(track, radius, radius);
    }
}

// ---------------------------------------------------------------------------
// MappingFontRow
// ---------------------------------------------------------------------------

MappingFontRow::MappingFontRow(const QString& version, QWidget* parent)
    : QWidget(parent)
    , m_version(version)
{
    setObjectName(QStringLiteral("MappingFontRow"));

    m_switch = new ToggleSwitch(this);
    m_switch->setObjectName(QStringLiteral("MappingRowSwitch"));
    m_switch->setAccessibleName(
        QStringLiteral("Give \u201c%1\u201d a font of its own").arg(version));

    m_name = new QLabel(version, this);
    m_name->setObjectName(QStringLiteral("MappingRowName"));

    // The picker sits right next to the name: the mapping's font is edited on
    // the row that carries it, without selecting the row first.
    m_picker = new FontPicker(this);
    m_picker->setObjectName(QStringLiteral("MappingRowFont"));
    m_picker->setMinimumWidth(200);
    m_picker->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);

    auto* layout = new QHBoxLayout(this);
    layout->setContentsMargins(10, 7, 10, 7);
    layout->setSpacing(10);
    layout->addWidget(m_switch);
    layout->addWidget(m_name);
    layout->addWidget(m_picker, 1);

    connect(m_switch, &QAbstractButton::toggled, this, &MappingFontRow::onToggled);
    connect(m_picker, &FontPicker::fontPicked, this, &MappingFontRow::onFontPicked);
    // An abandoned browse (Escape, or the popup closed without a commit) only
    // ever touched the picker's text: put the family back that this row
    // actually renders with.
    connect(m_picker, &FontPicker::fontPreviewCanceled, this,
            &MappingFontRow::refreshPicker);

    refreshPicker();
    refreshToolTip();
}

bool MappingFontRow::isEnabled() const
{
    return m_switch->isChecked();
}

QString MappingFontRow::displayFont() const
{
    // Never conditioned on the switch: what the row shows is what the user
    // selected, so flipping the switch cannot look like the font was reset.
    return hasCustomFont() ? m_custom : m_fallback;
}

QString MappingFontRow::renderedFont() const
{
    return isEnabled() ? displayFont() : m_fallback;
}

void MappingFontRow::setMappingFont(const QString& family, bool enabled)
{
    m_custom = family;
    // A row cannot be switched on with nothing to use: without a family of its
    // own it follows the ANSI box font either way.
    setSwitchChecked(enabled && hasCustomFont());
    refreshPicker();
    refreshToolTip();
}

void MappingFontRow::setFallbackFont(const QString& family)
{
    m_fallback = family;
    // Rows with a family of their own keep showing it; the rest show - and
    // follow - the ANSI box font, so their pickers move along.
    if (!hasCustomFont())
        refreshPicker();
    refreshToolTip();
}

void MappingFontRow::setSwitchOn(bool on)
{
    if (isEnabled() == on)
        return;
    // Switching a row on needs a family to use: a row that never had one of its
    // own starts from the ANSI box font it was rendering with anyway - the same
    // rule the switch itself follows (see onToggled), so the bulk action and a
    // user flip cannot leave a row on with nothing to render with.
    if (on && !hasCustomFont())
        m_custom = m_fallback;
    setSwitchChecked(on && hasCustomFont());
    refreshPicker();
    refreshToolTip();
    emit fontChanged();
}

void MappingFontRow::setSwitchChecked(bool on)
{
    QSignalBlocker blocker(m_switch);
    m_switch->setChecked(on);
}

int MappingFontRow::nameColumnWidth() const
{
    return m_name->sizeHint().width();
}

void MappingFontRow::setFixedNameWidth(int width)
{
    m_name->setFixedWidth(qMax(width, m_name->sizeHint().width()));
}

void MappingFontRow::onToggled(bool on)
{
    // The switch only decides whether the row's family is used; it never
    // rewrites it.  The one exception is a row that never had a family of its
    // own: switching it on gives it the ANSI box font it was showing anyway, so
    // the row has something of its own to fall back to.
    if (on && !hasCustomFont())
        m_custom = m_fallback;
    refreshPicker();
    refreshToolTip();
    emit fontChanged();
}

void MappingFontRow::onFontPicked(const QString& family)
{
    if (family.isEmpty())
        return;
    // Picking a family is an implicit "yes, this mapping gets its own font",
    // so the switch follows the picker instead of silently dropping the pick.
    m_custom = family;
    if (!isEnabled())
        setSwitchChecked(true);
    refreshPicker();
    refreshToolTip();
    emit fontChanged();
}

void MappingFontRow::refreshPicker()
{
    const QString family = displayFont();
    if (family.isEmpty())
        return;
    QSignalBlocker blocker(m_picker);
    m_picker->setActiveFont(family);
}

void MappingFontRow::refreshToolTip()
{
    const QString shown = displayFont();
    if (!hasCustomFont()) {
        m_picker->setToolTip(
            QStringLiteral("\u201c%1\u201d follows the ANSI box font (%2).  Pick a "
                           "family to give it its own.")
                .arg(m_version, shown));
        m_switch->setToolTip(
            QStringLiteral("Turn on to give \u201c%1\u201d a font of its own, "
                           "starting from the ANSI box font")
                .arg(m_version));
    } else if (isEnabled()) {
        m_picker->setToolTip(QStringLiteral("\u201c%1\u201d renders with %2")
                                 .arg(m_version, shown));
        m_switch->setToolTip(
            QStringLiteral("Turn off to render \u201c%1\u201d with the ANSI box "
                           "font instead; %2 stays selected here")
                .arg(m_version, shown));
    } else {
        m_picker->setToolTip(
            QStringLiteral("\u201c%1\u201d is switched off, so it renders with "
                           "the ANSI box font (%2) for now; switching it on "
                           "uses %3")
                .arg(m_version, m_fallback, m_custom));
        m_switch->setToolTip(
            QStringLiteral("Turn on to render \u201c%1\u201d with %2 again")
                .arg(m_version, m_custom));
    }
}

// ---------------------------------------------------------------------------
// SettingsDialog
// ---------------------------------------------------------------------------

SettingsDialog::SettingsDialog(const EditorFontSettings& initial,
                               const EditorFontSettings& defaults,
                               const QStringList& mappingVersions,
                               QWidget* parent)
    : QDialog(parent)
    , m_initial(initial)
    , m_defaults(defaults)
{
    setWindowTitle(QStringLiteral("Settings"));
    setModal(true);
    // The sheet hugs what it shows: this floor is only narrow/short enough to
    // keep the widest row (switch + name + its picker) and the footer usable, so
    // opening Settings never spreads the page over mostly empty window.  The
    // layout's own minimum still keeps every control reachable when the user
    // makes the sheet smaller.
    setMinimumSize(480, 360);

    auto* root = new QVBoxLayout(this);
    root->setContentsMargins(14, 14, 14, 14);
    root->setSpacing(12);

    root->addWidget(buildFontGroup(QStringLiteral("Unicode box"),
                                   QStringLiteral("SettingsUnicodeFont"),
                                   QStringLiteral("SettingsUnicodeSize"),
                                   &m_unicodeFont, &m_unicodeSize));
    root->addWidget(buildFontGroup(QStringLiteral("ANSI box"),
                                   QStringLiteral("SettingsAnsiFont"),
                                   QStringLiteral("SettingsAnsiSize"),
                                   &m_ansiFont, &m_ansiSize));
    root->addWidget(buildMappingSection(mappingVersions), 1);

    auto* buttons = new QDialogButtonBox(this);
    auto* reset = buttons->addButton(QStringLiteral("Reset to Defaults"),
                                     QDialogButtonBox::ResetRole);
    reset->setObjectName(QStringLiteral("SettingsReset"));
    reset->setAutoDefault(false);
    // OK is routed through accept() below, so the staged values reach the
    // window before the sheet disappears.
    auto* ok = buttons->addButton(QStringLiteral("OK"),
                                  QDialogButtonBox::AcceptRole);
    ok->setObjectName(QStringLiteral("SettingsOk"));
    auto* cancel = buttons->addButton(QStringLiteral("Cancel"),
                                      QDialogButtonBox::RejectRole);
    cancel->setObjectName(QStringLiteral("SettingsCancel"));
    cancel->setAutoDefault(false);
    auto* apply = buttons->addButton(QStringLiteral("Apply"),
                                     QDialogButtonBox::ApplyRole);
    apply->setObjectName(QStringLiteral("SettingsApply"));
    apply->setAutoDefault(false);
    connect(reset, &QPushButton::clicked, this, [this]() {
        // Staged, not saved: the user still has to press Apply.
        loadIntoWidgets(defaultsForReset());
    });
    // The box does not wire accept() up on its own (Qt's own dialogs connect
    // it explicitly), and going through the dialog's accept() is what makes OK
    // apply the staged values before the sheet closes.
    connect(buttons, &QDialogButtonBox::accepted, this, &SettingsDialog::accept);
    connect(apply, &QPushButton::clicked, this, &SettingsDialog::applyStaged);
    connect(cancel, &QPushButton::clicked, this, &QDialog::reject);
    root->addWidget(buttons);

    connectSignals();
    loadIntoWidgets(m_initial);
}

QGroupBox* SettingsDialog::buildFontGroup(const QString& title,
                                          const QString& pickerName,
                                          const QString& sizeName,
                                          FontPicker** picker,
                                          QSpinBox** spin)
{
    auto* group = new QGroupBox(title, this);
    auto* row = new QHBoxLayout(group);
    row->setContentsMargins(12, 10, 12, 10);
    row->setSpacing(8);

    row->addWidget(new QLabel(QStringLiteral("Font:"), group));
    auto* family = new FontPicker(group);
    family->setObjectName(pickerName);
    family->setMinimumWidth(280);
    row->addWidget(family, 1);
    row->addSpacing(16);
    row->addWidget(new QLabel(QStringLiteral("Size:"), group));
    auto* size = new QSpinBox(group);
    size->setObjectName(sizeName);
    size->setRange(editorFont::kMinSize, editorFont::kMaxSize);
    size->setSuffix(QStringLiteral(" pt"));
    row->addWidget(size);

    *picker = family;
    *spin = size;
    return group;
}

QWidget* SettingsDialog::buildMappingSection(const QStringList& mappingVersions)
{
    auto* section = new QWidget(this);
    auto* layout = new QVBoxLayout(section);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(8);

    m_versions = mappingVersions;

    // One row of real widgets per mapping - its switch, its name and its own
    // font picker on a single line.  A painted list item cannot carry a picker,
    // and a mapping folder holds a handful of files, so one widget per file
    // stays cheap; the scroll area is what keeps the page usable when a folder
    // offers more mappings than fit.  Rows are inserted before the trailing
    // stretch so they stay top-aligned.
    m_mappingScroll = new QScrollArea(section);
    m_mappingScroll->setObjectName(QStringLiteral("MappingScroll"));
    m_mappingScroll->setWidgetResizable(true);
    m_mappingScroll->setFrameShape(QFrame::StyledPanel);
    m_mappingScroll->setFixedHeight(kMinRowAreaHeight);
    m_mappingRows = new QWidget(m_mappingScroll);
    m_mappingRows->setObjectName(QStringLiteral("MappingRows"));
    m_mappingRowsLayout = new QVBoxLayout(m_mappingRows);
    m_mappingRowsLayout->setContentsMargins(6, 6, 6, 6);
    m_mappingRowsLayout->setSpacing(3);
    m_mappingRowsLayout->addStretch(1);
    m_mappingScroll->setWidget(m_mappingRows);
    // No stretch on the list: its height is fitted to the rows, so the page's
    // spare room belongs under the footer action below.
    layout->addWidget(m_mappingScroll);

    m_mappingEmpty = new QLabel(
        QStringLiteral("No .AvroEnco or .json mappings were found in the "
                       "mapping folder."),
        section);
    m_mappingEmpty->setWordWrap(true);
    m_mappingEmpty->setVisible(mappingVersions.isEmpty());
    layout->addWidget(m_mappingEmpty);

    // The one bulk action, aligned under the rows like a page footer.  Its label
    // and tooltip are kept in sync with the rows (see
    // updateUseBoxFontAction()): it toggles, so it has to say which way the next
    // press goes.
    auto* footer = new QHBoxLayout();
    footer->addStretch(1);
    m_useBoxFont = new QPushButton(section);
    m_useBoxFont->setObjectName(QStringLiteral("MappingUseBoxFont"));
    m_useBoxFont->setAutoDefault(false);
    footer->addWidget(m_useBoxFont);
    layout->addLayout(footer);
    // Taken after the footer, so a resized sheet collects its spare room here
    // and everything above stays top-aligned.
    layout->addStretch(1);

    return section;
}

void SettingsDialog::connectSignals()
{
    // A browse that never committed must not leave a query in the edit box:
    // what the box shows is what Apply would save.
    connect(m_unicodeFont, &FontPicker::fontPreviewCanceled, this,
            [this]() { restoreCommittedFamily(m_unicodeFont); });
    connect(m_ansiFont, &FontPicker::fontPreviewCanceled, this,
            [this]() { restoreCommittedFamily(m_ansiFont); });

    // Every mapping without a font of its own renders with the ANSI box font,
    // so the rows have to follow when that family changes.
    connect(m_ansiFont, &FontPicker::fontPicked, this,
            &SettingsDialog::setFallbackFont);

    connect(m_useBoxFont, &QPushButton::clicked, this,
            &SettingsDialog::toggleAnsiBoxFontForEveryMapping);
}

EditorFontSettings SettingsDialog::defaultsForReset() const
{
    EditorFontSettings target = m_defaults;

    // Every mapping gets the reset's own ANSI family as its own font, switched
    // on, instead of being left empty.  A row with no family of its own *follows*
    // the ANSI box font by design, so leaving them empty made a later edit of the
    // box font rewrite all four mapping rows at once - and a reset must leave
    // rows that hold what it gave them while the box font goes on changing on
    // its own.  A row is handed back to the box font deliberately, either by
    // switching that row off or with "Toggle OFF Every Mapping".
    if (!target.ansiFont.isEmpty()) {
        for (const QString& version : m_versions)
            target.mappingFonts.insert(version, target.ansiFont);
    }
    return target;
}

void SettingsDialog::loadIntoWidgets(const EditorFontSettings& values)
{
    if (!values.unicodeFont.isEmpty())
        m_unicodeFont->setActiveFont(values.unicodeFont);
    m_unicodeSize->setValue(
        qBound(editorFont::kMinSize, values.unicodeSize, editorFont::kMaxSize));

    if (!values.ansiFont.isEmpty())
        m_ansiFont->setActiveFont(values.ansiFont);
    m_ansiSize->setValue(
        qBound(editorFont::kMinSize, values.ansiSize, editorFont::kMaxSize));

    // Only the fonts are rewritten: the row list stays the folder's own list,
    // which is what makes "Reset to Defaults" a pure font reset.
    rebuildMappingRows(m_versions, values.mappingFonts, values.mappingFontsOff,
                       pickerFamily(m_ansiFont));
}

void SettingsDialog::rebuildMappingRows(const QStringList& versions,
                                       const QHash<QString, QString>& remembered,
                                       const QSet<QString>& off,
                                       const QString& fallback)
{
    m_versions = versions;

    // Pulled out of the layout before deleting, so a queued relayout cannot
    // touch a destroyed widget.  Deleted outright (not deleteLater()): nothing
    // here runs from a row's own signal, and a detached row would briefly be a
    // stray top-level window.
    for (MappingFontRow* row : m_rows) {
        m_mappingRowsLayout->removeWidget(row);
        delete row;
    }
    m_rows.clear();

    for (const QString& version : versions) {
        auto* row = new MappingFontRow(version, m_mappingRows);
        row->setFallbackFont(fallback);
        row->setMappingFont(remembered.value(version), !off.contains(version));
        // The bulk action's caption follows the switches, so it keeps saying
        // which way the next press goes.
        connect(row, &MappingFontRow::fontChanged, this,
                &SettingsDialog::updateUseBoxFontAction);
        // Before the trailing stretch, so the rows stay top-aligned.
        m_mappingRowsLayout->insertWidget(m_mappingRowsLayout->count() - 1, row);
        m_rows.push_back(row);
    }

    alignNameColumn();
    // The name column was re-widened above; force the row layout now so a page
    // that has not been shown yet is still consistent (no picker sitting on
    // top of a name label until the next relayout).
    m_mappingRowsLayout->activate();
    fitRowAreaHeight();
    lockMinimumToContent();
    // A row is only measured once the style has sized the widgets inside it, so
    // repeat the fit after the pending layout work has been delivered.  The
    // zero-timer fires before the next paint, so no wrong band is ever shown.
    QTimer::singleShot(0, this, [this]() {
        fitRowAreaHeight();
        lockMinimumToContent();
    });
    // The bulk action describes the freshly loaded rows, and a folder with no
    // mappings leaves it with nothing to toggle.
    updateUseBoxFontAction();
    if (m_mappingEmpty)
        m_mappingEmpty->setVisible(versions.isEmpty());
}

void SettingsDialog::fitRowAreaHeight()
{
    // The rows widget's own size is the rows themselves (the trailing stretch
    // contributes nothing), so the list can be exactly as tall as what it
    // shows: five mappings give a five-row box, a folder with thirty gives the
    // capped band and a scrollbar.
    //
    // The height is measured from the rows, never from the rows widget's own
    // size hint: right after a rebuild that hint still describes the layout as
    // it was *while the previous rows were being dropped* (it comes back as
    // little as the bare margins - the stale value is only replaced after the
    // next layout pass).  Fitting the band to that number is what made "Reset
    // to Defaults" look broken: the band collapsed to its minimum, the rebuilt
    // rows no longer fitted in it, and the sheet came back with a squeezed,
    // scrolling list and the footer pulled up the page.
    const int spacing = m_mappingRowsLayout->spacing();
    const QMargins margins = m_mappingRowsLayout->contentsMargins();
    int rowsHeight = 0;
    for (MappingFontRow* row : m_rows) {
        // The height a row is laid out with, using the same rule as the layout
        // item behind it (a row never shrinks below its minimum size hint).
        rowsHeight += qMax(row->sizeHint().height(),
                           row->minimumSizeHint().height())
                      + spacing;
    }
    // Only the gaps *between* the rows count - the one after the last row is
    // what the trailing stretch absorbs.
    if (!m_rows.isEmpty())
        rowsHeight -= spacing;

    const int needed = margins.top() + margins.bottom() + rowsHeight
                       + 2 * m_mappingScroll->frameWidth();
    m_mappingScroll->setFixedHeight(
        qBound(kMinRowAreaHeight, needed, kMaxRowAreaHeight));
}

void SettingsDialog::lockMinimumToContent()
{
    // Never smaller than the size it opens with: the minimum is the page the
    // rows ask for, so a resize can only hand the sheet *more* room - the spare
    // room collects under the footer (see buildMappingSection) and the rows keep
    // their own height instead of being squeezed into a shorter band.
    setMinimumSize(qMax(480, sizeHint().width()),
                   qMax(360, sizeHint().height()));
}

void SettingsDialog::alignNameColumn()
{
    int width = 0;
    for (MappingFontRow* row : m_rows)
        width = qMax(width, row->nameColumnWidth());
    for (MappingFontRow* row : m_rows)
        row->setFixedNameWidth(width);
}

void SettingsDialog::setFallbackFont(const QString& family)
{
    for (MappingFontRow* row : m_rows)
        row->setFallbackFont(family);
}

QHash<QString, QString> SettingsDialog::mappingFonts() const
{
    QHash<QString, QString> result;
    for (MappingFontRow* row : m_rows) {
        if (row->hasCustomFont())
            result.insert(row->version(), row->customFont());
    }
    return result;
}

QSet<QString> SettingsDialog::mappingsOff() const
{
    QSet<QString> result;
    for (MappingFontRow* row : m_rows) {
        // Only a row that remembers a family can be switched off in a way that
        // matters: without one it follows the ANSI box font either way, and
        // recording that would only put noise in the settings file.
        if (!row->isEnabled() && row->hasCustomFont())
            result.insert(row->version());
    }
    return result;
}

void SettingsDialog::toggleAnsiBoxFontForEveryMapping()
{
    // A master toggle, not a one-way action: with every row on, one press hands
    // them all to the ANSI box font; with any row already off, one press puts
    // them all back on the family each row carries (the rows keep their families
    // either way - only the switches move, see MappingFontRow).
    bool everyRowOn = true;
    for (MappingFontRow* row : m_rows) {
        if (!row->isEnabled())
            everyRowOn = false;
    }
    for (MappingFontRow* row : m_rows)
        row->setSwitchOn(!everyRowOn);
    updateUseBoxFontAction();
}

void SettingsDialog::updateUseBoxFontAction()
{
    // Nothing to toggle in a folder with no mappings.
    m_useBoxFont->setEnabled(!m_rows.isEmpty());

    // The caption follows the rows, so the button always says what pressing it
    // would do next (a toggle with only one caption reads like a one-way action).
    bool anyRowOn = false;
    for (MappingFontRow* row : m_rows) {
        if (row->isEnabled())
            anyRowOn = true;
    }

    if (anyRowOn) {
        m_useBoxFont->setText(
            QStringLiteral("Disable All Mappings"));
        m_useBoxFont->setToolTip(
            QStringLiteral("Use the default ANSI box font for all mappings."
                       "Custom fonts are saved and restored when re-enabled."));
    } else {
        m_useBoxFont->setText(
            QStringLiteral("Enable All Mappings"));
        m_useBoxFont->setToolTip(
            QStringLiteral("Use each mapping's specific custom font."
                       "Click again to revert to the default ANSI box font."));
    }
}

void SettingsDialog::applyStaged()
{
    // Re-baseline: what is being handed over is written to disk by
    // MainWindow, so a later Cancel has nothing further to roll back.
    m_initial = settings();
    emit settingsApplied(m_initial);
}

void SettingsDialog::accept()
{
    // "OK" is Apply plus close: the window is updated first, so it is already
    // showing the new fonts when the sheet disappears.
    applyStaged();
    QDialog::accept();
}

EditorFontSettings SettingsDialog::settings() const
{
    EditorFontSettings result;
    result.unicodeFont = pickerFamily(m_unicodeFont);
    result.unicodeSize = m_unicodeSize->value();
    result.ansiFont = pickerFamily(m_ansiFont);
    result.ansiSize = m_ansiSize->value();
    // Both halves are rebuilt from the rows: a mapping whose switch is off
    // keeps its family here (that is what survives a restart) but is listed in
    // mappingFontsOff, while a row that never had a family of its own
    // disappears from the map entirely.
    result.mappingFonts = mappingFonts();
    result.mappingFontsOff = mappingsOff();
    return result;
}
