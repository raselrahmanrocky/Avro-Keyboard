// mainwindow.cpp - implementation of the Qt Avro Text Converter main window.
#include "mainwindow.h"

#include "core/bijoy_to_unicode.h"
#include "core/unicode_to_bijoy.h"
#include "ui/downwardcombo.h"
#include "ui/fontpicker.h"
#include "ui/memoedit.h"
#include "ui/settingsdialog.h"

#include <QAbstractItemView>
#include <QAction>
#include <QActionGroup>
#include <QApplication>
#include <QCloseEvent>
#include <QComboBox>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QFontDatabase>
#include <QFutureWatcher>
#include <QHBoxLayout>
#include <QIcon>
#include <QImageReader>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QMessageBox>
#include <QPainter>
#include <QPointer>
#include <QProgressBar>
#include <QPushButton>
#include <QSettings>
#include <QScrollBar>
#include <QSet>
#include <QStandardPaths>
#include <QSignalBlocker>
#include <QShortcut>
#include <QSplitter>
#include <QStyle>
#include <QSystemTrayIcon>
#include <QTextCursor>
#include <QTextDocument>
#include <QPlainTextEdit>
#include <QTextOption>
#include <QThread>
#include <QTimer>
#include <QToolButton>
#include <QVBoxLayout>
#include <QtConcurrent>

#include <atomic>
#include <chrono>
#include <memory>

#ifdef Q_OS_WIN
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>
#include <commctrl.h>
#include <psapi.h>
#endif

namespace {

const QColor kAccent(0xE6, 0x7E, 0x22);      // #E67E22
const QColor kAccentHover(0xF3, 0x9C, 0x12); // #F39C12
const QColor kAccentPress(0xD3, 0x54, 0x00); // #D35400
const QColor kDarkBg(0x1F, 0x1F, 0x1F);       // #1f1f1f

// A mapping file that is being rewritten (AvroEncoBuilder shipping an update,
// or the user replacing it) stays unreadable for a moment.  A failed
// background load retries a few times before giving up and keeping the
// mapping that is already loaded (see MainWindow::onMappingLoadFinished).
constexpr int kMappingLoadRetries = 4;
constexpr int kMappingLoadRetryDelayMs = 500;

// Portable settings: keep the INI next to the executable whenever that folder
// is writable, so a portable deployment leaves no trace in the Windows
// registry.  An installation under Program Files is not writable for normal
// users, so there the settings move to the per-user application config folder
// (QStandardPaths::AppConfigLocation, i.e. %LOCALAPPDATA%\OmicronLab\
// Avro Text Converter\) instead.
QString portableSettingsPath()
{
    const QString exeDir = QCoreApplication::applicationDirPath();
    const QString nextToExe = exeDir + QStringLiteral("/AvroTextConverter.ini");
    if (QFileInfo(exeDir).isWritable())
        return nextToExe;

    const QString configDir =
        QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    if (!configDir.isEmpty()) {
        QDir().mkpath(configDir);
        return configDir + QStringLiteral("/AvroTextConverter.ini");
    }

    return nextToExe;   // no usable config location - keep the portable path
}

QSettings appRegistry()
{
    return QSettings(portableSettingsPath(), QSettings::IniFormat);
}

// QFontDatabase::families() walks the whole GDI/DirectWrite font set
// (~50-300 ms on Windows), so enumerate exactly once.  UI thread only.
// fontFamiliesCache().clear() forces the next call to rebuild the list,
// which loadBundledFonts uses after registering bundled faces so the
// cached list includes them.
QStringList& fontFamiliesCache()
{
    static QStringList cache;
    return cache;
}

const QStringList& allFontFamilies()
{
    QStringList& cache = fontFamiliesCache();
    if (cache.isEmpty())
        cache = QFontDatabase::families();
    return cache;
}

// Window-button glyphs (minimize / maximize / restore / close) are DRAWN
// instead of typeset.  The Windows glyphs live in an icon font that is not
// installed everywhere (Windows 11 has "Segoe Fluent Icons", Windows 10 only
// "Segoe MDL2 Assets", U+E921/U+E922/U+E923/U+E8BB), and asking Qt for a family
// that is missing makes it search the entire font collection for a fallback
// for those private-use code points - that search alone cost ~0.4 s on the
// first paint of the title bar.  Painting the few strokes ourselves keeps the
// title bar independent of the installed fonts (and of the locale, since a
// localized font registration hides the family anyway), and re-tinting on a
// theme switch is a two-line call (see applyPalette).
enum class CaptionIcon { Minimize, Maximize, Restore, Close };

QIcon makeCaptionIcon(CaptionIcon kind, const QColor& color)
{
    constexpr int kSide = 16;    // pixmap; the glyph itself is ~10 px
    constexpr qreal kGlyph = 10.0;
    QPixmap pm(kSide, kSide);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(QPen(color, 1.4, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    const QRectF box((kSide - kGlyph) / 2.0, (kSide - kGlyph) / 2.0, kGlyph,
                     kGlyph);
    switch (kind) {
    case CaptionIcon::Minimize:
        p.drawLine(QPointF(box.left(), box.center().y()),
                   QPointF(box.right(), box.center().y()));
        break;
    case CaptionIcon::Maximize:
        p.drawRect(box);
        break;
    case CaptionIcon::Restore: {
        // Two overlapping squares, the front one drawn on top of the back.
        const QRectF front = box.translated(2.0, -2.0);
        const QRectF back = box.translated(-2.0, 2.0);
        p.drawLine(back.topLeft(), QPointF(front.left(), back.top()));
        p.drawLine(back.topLeft(), QPointF(back.left(), front.bottom()));
        p.drawLine(QPointF(back.left(), front.bottom()),
                   QPointF(front.left(), front.bottom()));
        p.drawRect(front);
        break;
    }
    case CaptionIcon::Close:
        p.drawLine(box.topLeft(), box.bottomRight());
        p.drawLine(box.bottomLeft(), box.topRight());
        break;
    }
    p.end();
    return QIcon(pm);
}

// The window, taskbar, Alt-Tab and notification-area icons all come from the
// bundled .ico shipped next to the executable (assets/icon/Converter.ico),
// with the same source-tree fallback walk as loadBundledFonts().
QString locateAppIconFile()
{
    QStringList roots;
    roots << QCoreApplication::applicationDirPath();
    QString cwd = QDir::currentPath();
    for (int i = 0; i < 4; ++i) {
        if (!roots.contains(cwd))
            roots << cwd;
        cwd = QDir(cwd).absoluteFilePath(QStringLiteral(".."));
    }
    for (const QString& root : roots) {
        const QString file =
            root + QStringLiteral("/assets/icon/Converter.ico");
        if (QFile::exists(file))
            return file;
    }
    return QString();
}

// A multi-resolution .ico is stored as one bitmap per size, and each of them
// is registered here as its own pixmap: the notification area (16px at 100%
// DPI, 20/24px at 125/150%), the taskbar and the title bar then pick the exact
// bitmap instead of rescaling the 128px master, which is what keeps the small
// sizes sharp.  Single-image files still work - QIcon scales those itself.
QIcon loadBundledAppIcon()
{
    const QString file = locateAppIconFile();
    if (file.isEmpty())
        return QIcon();
    QImageReader reader(file);
    reader.setFormat("ico");
    QIcon icon;
    const int count = reader.imageCount();
    for (int i = 0; i < count; ++i) {
        if (!reader.jumpToImage(i))
            continue;
        const QImage image = reader.read();
        if (!image.isNull())
            icon.addPixmap(QPixmap::fromImage(image));
    }
    // Reader could not enumerate the file: let Qt load it as a whole.
    return icon.isNull() ? QIcon(file) : icon;
}

// Decoded once - every consumer shares the same QIcon (and a null icon means
// "no bundled logo", so callers fall back to the drawn accent tile).
const QIcon& bundledAppIcon()
{
    static const QIcon icon = loadBundledAppIcon();
    return icon;
}

} // namespace

// ---------------------------------------------------------------------------
// Construction / UI
// ---------------------------------------------------------------------------

MainWindow::MainWindow(QWidget* parent)
    : QMainWindow(parent)
{
    setObjectName(QStringLiteral("MainWindow"));
    setWindowTitle(QStringLiteral("Avro Text Converter"));
    setWindowFlags(Qt::Window | Qt::FramelessWindowHint
                       | Qt::WindowMinMaxButtonsHint);
    resize(900, 600);
    // Minimum width must accommodate the full toolbar row: both convert
    // buttons (~118px each), ANSI-version combo (~150px), FontPicker (~190px),
    // settings gear (30px), plus margins/spacing (~56px) = ~662px.
    setMinimumSize(680, 380);

    // The Delphi app opens centred on the work area; centre ourselves too
    // (a top-left default would also make the popups flip direction).
    if (QScreen* scr = QGuiApplication::primaryScreen()) {
        const QRect avail = scr->availableGeometry();
        move(avail.center() - QPoint(width() / 2, height() / 2));
    }

    // Bundle the Bengali fonts shipped with the repo so the app renders
    // correctly even when the fonts are not installed system-wide.
    loadBundledFonts();
    setWindowIcon(makeAppIcon());

    // The Delphi app defaults to the ANSI mapping "Default" and restores the
    // last picked version / font from the registry.
    avro::g_registry.init();
    // The registry concatenates the version name onto this path, so it must
    // end with a separator (the Delphi app's AnsiMappingDir does the same).
    std::wstring mapDir = locateAnsiMappingDir().toStdWString();
    if (!mapDir.empty() && mapDir.back() != L'/' && mapDir.back() != L'\\')
        mapDir.push_back(L'/');
    avro::g_registry.ansiMappingDir = mapDir;
    avro::g_registry.resetToDefaults();

    // The mapping loader must exist before the first load request - the
    // restored version picked below issues one - so that the initial decrypt
    // never runs on the UI thread.
    m_mappingLoader = new QFutureWatcher<MappingLoadResult>(this);
    connect(m_mappingLoader, &QFutureWatcher<MappingLoadResult>::finished,
            this, &MainWindow::onMappingLoadFinished);

    // Install the global combo-arrow chevron style ONCE before any
    // DownwardCombo/FontPicker widgets are created.  This must happen
    // before buildUi() so the application style is already in place when
    // the combos first render.
    installComboArrowStyle();

    buildUi();
    connectSignals();
    createTrayIcon();

    // Read the persisted ANSI version BEFORE populating the combo (mirrors the
    // Delphi startup order): populating must not overwrite the saved value.
    const QString savedVersion = readAnsiVersion();
    {
        QSignalBlocker blocker(m_cbAnsiVersion);
        populateAnsiVersions();
    }
    m_themeMode = readThemeMode();
    applyTheme(m_themeMode);

    // Restore the persisted choice.  The combo only offers what the mapping
    // folder provides, so an unavailable saved version falls back to the first
    // offered mapping, and a folder that has nothing yet leaves it empty.
    if (m_cbAnsiVersion->count() > 0) {
        int versionIdx = 0;
        if (!savedVersion.isEmpty()) {
            const int idx = m_cbAnsiVersion->findText(savedVersion);
            if (idx >= 0)
                versionIdx = idx;
        }
        {
            QSignalBlocker blocker(m_cbAnsiVersion);
            m_cbAnsiVersion->setCurrentIndex(versionIdx);
        }
        // The restore ran with the signal blocked, so the mapping the combo
        // now shows has to be loaded explicitly - there is no built-in
        // "Default" entry the registry could fall back to any more.
        requestMappingLoad(m_cbAnsiVersion->currentText(), QString(),
                           /*persist=*/false, /*warnOnFailure=*/false);
    }

    // Editor fonts (families, point sizes and the optional per-mapping font)
    // and the toolbar picker, which has to show the font the active version
    // uses - buildUi only set the built-in defaults.
    applyEditorFonts();

    // Dev hook: AVRO_OPEN_SETTINGS=1 opens the Settings sheet right after the
    // window appears, and =menu pops the gear menu instead - all so one
    // screenshot run can capture either (`--screenshot` grabs whatever is in
    // front).  Any other value opens the sheet as well ("=mapping" was the
    // name of its old per-page form and is still accepted).
    const QString openSettings = qEnvironmentVariable("AVRO_OPEN_SETTINGS");
    if (!openSettings.isEmpty()) {
        QTimer::singleShot(300, this, [this, openSettings]() {
            if (openSettings.compare(QStringLiteral("menu"),
                                     Qt::CaseInsensitive) == 0)
                m_btnSettings->showMenu();
            else
                openSettingsDialog();
        });
    }

    // Live mapping refresh: Avro Keyboard (or the user) may add, update or
    // remove a mapping while this window is open, so the folder and the file
    // behind the active version are watched and re-read on any change instead
    // of requiring a restart.  Events arrive in bursts (a copy plus a rename,
    // editors writing temp files), hence the debounce timer.
    m_activeMappingSnapshot = mappingSnapshot(m_cbAnsiVersion->currentText());
    m_mappingWatcher = new QFileSystemWatcher(this);
    m_mappingDebounce = new QTimer(this);
    m_mappingDebounce->setSingleShot(true);
    m_mappingDebounce->setInterval(300);
    connect(m_mappingDebounce, &QTimer::timeout, this,
            &MainWindow::onMappingFilesChanged);
    connect(m_mappingWatcher, &QFileSystemWatcher::directoryChanged, this,
            [this](const QString&) { m_mappingDebounce->start(); });
    connect(m_mappingWatcher, &QFileSystemWatcher::fileChanged, this,
            [this](const QString&) { m_mappingDebounce->start(); });
    watchAnsiMappingDir();

    updateFooterTip();
    runAutotestIfRequested();

#ifdef Q_OS_WIN
    // Once startup has settled (font enumeration, QPA init, first paint),
    // ask Windows to flush pages we are not touching back to the pagefile.
    QTimer::singleShot(500, this, &MainWindow::trimWorkingSet);
#endif
}

void MainWindow::runAutotestIfRequested()
{
    m_autotestIn = qEnvironmentVariable("AVRO_AUTOTEST_IN");
    m_autotestOut = qEnvironmentVariable("AVRO_AUTOTEST_OUT");
    if (m_autotestIn.isEmpty() || m_autotestOut.isEmpty())
        return;
    QFile inFile(m_autotestIn);
    if (!inFile.open(QIODevice::ReadOnly))
        return;
    const QString src = QString::fromUtf8(inFile.readAll());
    m_autotestRev = qEnvironmentVariableIntValue("AVRO_AUTOTEST_REV") != 0;
    if (m_autotestRev)
        m_memo2->setPlainText(src);
    else
        m_memo1->setPlainText(src);
    // AVRO_AUTOTEST_DELAY postpones the run, so a test can change files (e.g.
    // a mapping folder) while the window is live and then convert against
    // whatever the app picked up.
    const int delayMs = qEnvironmentVariableIntValue("AVRO_AUTOTEST_DELAY");
    QTimer::singleShot(delayMs > 0 ? delayMs : 400, this, [this]() {
        if (m_autotestRev)
            onAnsiToUnicode();
        else
            onUnicodeToAnsi();
    });
}

MainWindow::~MainWindow()
{
#ifdef Q_OS_WIN
    if (HWND hwnd = reinterpret_cast<HWND>(winId()))
        RemoveWindowSubclass(hwnd, rawWndProc, 0);
#endif
}

void MainWindow::buildUi()
{
    auto* central = new QWidget(this);
    central->setObjectName(QStringLiteral("CentralRoot"));
    auto* root = new QVBoxLayout(central);
    root->setContentsMargins(0, 0, 0, 0);
    root->setSpacing(0);

    // ── custom title bar ──────────────────────────────────────────────
    m_titleBar = new QWidget(central);
    m_titleBar->setObjectName(QStringLiteral("TitleBar"));
    m_titleBar->setFixedHeight(36);
    m_titleBar->setCursor(Qt::ArrowCursor);
    auto* titleLayout = new QHBoxLayout(m_titleBar);
    titleLayout->setContentsMargins(0, 0, 0, 0);
    titleLayout->setSpacing(0);

    auto* iconLabel = new QLabel(m_titleBar);
    iconLabel->setPixmap(makeAppIcon().pixmap(18, 18));
    iconLabel->setFixedSize(24, 24);
    iconLabel->setAlignment(Qt::AlignCenter);
    iconLabel->setCursor(Qt::ArrowCursor);
    titleLayout->addSpacing(10);
    titleLayout->addWidget(iconLabel);

    m_lblTitle = new QLabel(QStringLiteral("Avro Text Converter"), m_titleBar);
    m_lblTitle->setObjectName(QStringLiteral("LblTitle"));
    m_lblTitle->setCursor(Qt::ArrowCursor);
    titleLayout->addSpacing(8);
    titleLayout->addWidget(m_lblTitle);
    titleLayout->addStretch(1);

    // Window buttons: the glyphs are painted, not typeset (see
    // makeCaptionIcon); the icons themselves are handed to the buttons by
    // applyPalette, which knows the theme's text colour.
    const QSize captionIconSize(16, 16);

    m_btnMin = new QPushButton(m_titleBar);
    m_btnMin->setObjectName(QStringLiteral("BtnMin"));
    m_btnMin->setCursor(Qt::ArrowCursor);
    m_btnMin->setToolTip(QStringLiteral("Minimize"));
    m_btnMin->setIconSize(captionIconSize);
    titleLayout->addWidget(m_btnMin);

    m_btnMax = new QPushButton(m_titleBar);
    m_btnMax->setObjectName(QStringLiteral("BtnMax"));
    m_btnMax->setCursor(Qt::ArrowCursor);
    m_btnMax->setToolTip(QStringLiteral("Maximize"));
    m_btnMax->setIconSize(captionIconSize);
    titleLayout->addWidget(m_btnMax);

    m_btnClose = new QPushButton(m_titleBar);
    m_btnClose->setObjectName(QStringLiteral("BtnClose"));
    m_btnClose->setCursor(Qt::ArrowCursor);
    m_btnClose->setToolTip(QStringLiteral("Close"));
    m_btnClose->setIconSize(captionIconSize);
    titleLayout->addWidget(m_btnClose);

    root->addWidget(m_titleBar);

    // ---------------------------------------------------------------- toolbar
    auto* toolbar = new QWidget(central);
    toolbar->setObjectName(QStringLiteral("PanelButton"));
    toolbar->setFixedHeight(48);
    auto* tbLayout = new QHBoxLayout(toolbar);
    tbLayout->setContentsMargins(12, 8, 12, 8);
    tbLayout->setSpacing(8);

    m_btnUniToAnsi = new QPushButton(QStringLiteral("Unicode to ANSI"), toolbar);
    m_btnUniToAnsi->setObjectName(QStringLiteral("BtnPrimary"));
    m_btnUniToAnsi->setMinimumWidth(110);
    m_btnUniToAnsi->setMaximumWidth(125);
    m_btnUniToAnsi->setFixedHeight(30);
    m_btnUniToAnsi->setCursor(Qt::PointingHandCursor);
    // Pure mouse-target toolbar button: no default-button role and no
    // keyboard focus.  When a focused button is disabled, Qt hands focus
    // to the next widget in tab order and repaints it (the neighbor
    // button "blinking" flash), so keep these buttons out of the focus
    // engine entirely.
    m_btnUniToAnsi->setAutoDefault(false);
    m_btnUniToAnsi->setDefault(false);
    m_btnUniToAnsi->setFocusPolicy(Qt::NoFocus);
    m_btnUniToAnsi->setToolTip(QStringLiteral(
        "Convert the Unicode (Bengali) text above to ANSI (Bijoy)"));
    tbLayout->addWidget(m_btnUniToAnsi);

    m_cbAnsiVersion = new DownwardCombo(toolbar);
    m_cbAnsiVersion->setObjectName(QStringLiteral("CbAnsiVersion"));
    m_cbAnsiVersion->setMinimumWidth(120);
    m_cbAnsiVersion->setMaximumWidth(150);
    m_cbAnsiVersion->setFixedHeight(30);
    m_cbAnsiVersion->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Fixed);
    m_cbAnsiVersion->setMaxVisibleItems(12);
    m_cbAnsiVersion->setCursor(Qt::PointingHandCursor);
    m_cbAnsiVersion->setToolTip(QStringLiteral(
        "Choose the ANSI encoding used for the converted text"));
    tbLayout->addWidget(m_cbAnsiVersion);

    m_btnAnsiToUni = new QPushButton(QStringLiteral("ANSI to Unicode"), toolbar);
    m_btnAnsiToUni->setObjectName(QStringLiteral("BtnSecondary"));
    m_btnAnsiToUni->setMinimumWidth(110);
    m_btnAnsiToUni->setMaximumWidth(125);
    m_btnAnsiToUni->setFixedHeight(30);
    m_btnAnsiToUni->setCursor(Qt::PointingHandCursor);
    // Same focus treatment as the primary button above (see note there).
    m_btnAnsiToUni->setAutoDefault(false);
    m_btnAnsiToUni->setDefault(false);
    m_btnAnsiToUni->setFocusPolicy(Qt::NoFocus);
    m_btnAnsiToUni->setToolTip(QStringLiteral(
        "Convert the ANSI (Bijoy) text below back to Unicode"));
    tbLayout->addWidget(m_btnAnsiToUni);

    m_cbFontPicker = new FontPicker(toolbar);
    m_cbFontPicker->setObjectName(QStringLiteral("CbAnsiVersion"));
    m_cbFontPicker->setMinimumWidth(140);
    m_cbFontPicker->setMaximumWidth(200);
    m_cbFontPicker->setFixedHeight(30);
    m_cbFontPicker->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    m_cbFontPicker->setCursor(Qt::PointingHandCursor);
    m_cbFontPicker->setToolTip(QStringLiteral(
        "Type to search installed fonts for the ANSI preview"));
    tbLayout->addWidget(m_cbFontPicker);

    tbLayout->addStretch(1);

    m_btnSettings = new QToolButton(toolbar);
    m_btnSettings->setObjectName(QStringLiteral("BtnSettings"));
    m_btnSettings->setFixedSize(30, 30);
    m_btnSettings->setAutoRaise(true);
    m_btnSettings->setCursor(Qt::PointingHandCursor);
    m_btnSettings->setToolTip(QStringLiteral("Settings"));
    tbLayout->addWidget(m_btnSettings);

    root->addWidget(toolbar);

    // --------------------------------------------------- memo1 + memo2 panels
    auto* memo1Panel = new QWidget(central);
    auto* m1 = new QVBoxLayout(memo1Panel);
    m1->setContentsMargins(12, 10, 12, 5);
    m1->setSpacing(0);
    m_memo1 = new MemoEdit(memo1Panel);
    m_memo1->setObjectName(QStringLiteral("Memo"));
    m_memo1->setLineWrapMode(QPlainTextEdit::WidgetWidth);
    // The built-in first-run fonts (also what "Reset to Defaults" restores).
    const EditorFontSettings defaults = defaultEditorFontSettings();
    const QFont memo1Font(defaults.unicodeFont, defaults.unicodeSize);
    m_memo1->setBaseFont(memo1Font);
    // The hint is *painted* by MemoEdit in this one fixed font (see
    // setCustomPlaceholder), never Qt's native placeholder text: a native hint
    // is drawn in whatever the editor font/size/zoom currently is, which made
    // the Unicode box's hint swing between tiny and huge with the settings.
    // Both boxes paint this same font, so the two hints always match.
    m_memo1->setCustomPlaceholder(
        QStringLiteral("Paste Unicode Bengali text here and press "
                       "\"Unicode to ANSI\"."),
        memo1Font);
    m1->addWidget(m_memo1);

    auto* memo2Panel = new QWidget(central);
    auto* m2 = new QVBoxLayout(memo2Panel);
    m2->setContentsMargins(12, 5, 12, 10);
    m2->setSpacing(0);
    m_memo2 = new MemoEdit(memo2Panel);
    m_memo2->setObjectName(QStringLiteral("Memo"));
    m_memo2->setLineWrapMode(QPlainTextEdit::WidgetWidth);
    // Same painted hint, in the very same font as the Unicode box's - and for a
    // second reason here: the ANSI font (Kalpurush ANSI, SutonnyMJ) maps ASCII
    // to Bengali glyphs, so a native placeholder would render the English hint
    // as glyph soup.  paintEvent draws it directly, bypassing the widget's font.
    m_memo2->setCustomPlaceholder(
        QStringLiteral("Paste ANSI Bengali text here and press "
                       "\"ANSI to Unicode\"."),
        memo1Font);
    m_memo2->setBaseFont(QFont(defaults.ansiFont, defaults.ansiSize));
    // Initial committed font for the preview revert path (later updates
    // happen in onFontPicked / setActiveFont).
    m_committedAnsiFont = m_memo2->baseFont().family();
    m2->addWidget(m_memo2);

    m_splitter = new QSplitter(Qt::Vertical, central);
    m_splitter->setHandleWidth(8);
    m_splitter->setChildrenCollapsible(false);
    m_splitter->addWidget(memo1Panel);
    m_splitter->addWidget(memo2Panel);
    m_splitter->setSizes({278, 258});
    root->addWidget(m_splitter, 1);

    // ---------------------------------------------------------------- footer
    auto* footer = new QWidget(central);
    footer->setObjectName(QStringLiteral("PanelFooter"));
    footer->setFixedHeight(30);
    auto* footerLayout = new QHBoxLayout(footer);
    footerLayout->setContentsMargins(12, 4, 12, 4);
    footerLayout->setSpacing(10);

    m_lblFooter = new QLabel(footer);
    m_lblFooter->setObjectName(QStringLiteral("LblFooter"));
    m_lblFooter->setAlignment(Qt::AlignVCenter | Qt::AlignLeft);
    footerLayout->addWidget(m_lblFooter, 1);

    m_progress = new QProgressBar(footer);
    m_progress->setObjectName(QStringLiteral("ProgBar"));
    m_progress->setRange(0, 100);
    m_progress->setValue(0);
    m_progress->setTextVisible(false);
    m_progress->setFixedHeight(8);
    m_progress->setVisible(false);
    footerLayout->addWidget(m_progress, 1);

    m_lblCount = new QLabel(footer);
    m_lblCount->setObjectName(QStringLiteral("LblCount"));
    m_lblCount->setAlignment(Qt::AlignVCenter | Qt::AlignRight);
    footerLayout->addWidget(m_lblCount);

    root->addWidget(footer);

    setCentralWidget(central);
    buildSettingsMenu();
}

void MainWindow::buildSettingsMenu()
{
    m_themeMenu = new QMenu(this);

    // Theme actions live in an exclusive, checkable QActionGroup.  Besides
    // visually marking the active theme, this isolates theme handling from
    // the rest of the menu: the group's triggered() fires only for these
    // three actions, so "About" (added below, no theme data) can never be
    // forwarded to onThemeTriggered and accidentally flip the theme.
    m_themeSys = m_themeMenu->addAction(QStringLiteral("System Default"));
    m_themeLight = m_themeMenu->addAction(QStringLiteral("Light Theme"));
    m_themeDark = m_themeMenu->addAction(QStringLiteral("Dark Theme"));
    auto* themeGroup = new QActionGroup(this);
    themeGroup->setExclusive(true);
    m_themeSys->setCheckable(true);
    m_themeSys->setData(static_cast<int>(ThemeMode::System));
    m_themeLight->setCheckable(true);
    m_themeLight->setData(static_cast<int>(ThemeMode::Light));
    m_themeDark->setCheckable(true);
    m_themeDark->setData(static_cast<int>(ThemeMode::Dark));
    themeGroup->addAction(m_themeSys);
    themeGroup->addAction(m_themeLight);
    themeGroup->addAction(m_themeDark);
    m_themeMenu->addSeparator();
    m_themeMenu->addAction(QStringLiteral("Settings\u2026"), this,
                           [this]() { openSettingsDialog(); });
    m_themeMenu->addAction(QStringLiteral("About Avro Text Converter"), this,
                           [this]() {
                               QMessageBox::about(
                                   this, QStringLiteral("About"),
                                   QStringLiteral(
                                       "<h3>Avro Text Converter</h3>"
                                       "<p>Unicode &harr; ANSI Bengali "
                                       "text converter.</p>"
                                       "<p>Version %1</p>")
                                       .arg(QCoreApplication::applicationVersion()));
                           });
    m_btnSettings->setMenu(m_themeMenu);
    m_btnSettings->setPopupMode(QToolButton::InstantPopup);
}

void MainWindow::connectSignals()
{
    connect(m_btnUniToAnsi, &QPushButton::clicked,
            this, &MainWindow::onUnicodeToAnsi);
    connect(m_btnAnsiToUni, &QPushButton::clicked,
            this, &MainWindow::onAnsiToUnicode);
    connect(m_cbAnsiVersion, &QComboBox::currentTextChanged,
            this, &MainWindow::onAnsiVersionChanged);
    // Both the combo's own list and the completer (filter) popup funnel
    // through FontPicker::fontPicked, so clicking a font in either list
    // applies it to the ANSI memo immediately.
    connect(m_cbFontPicker, &FontPicker::fontPicked,
            this, &MainWindow::onFontPicked);
    // Live preview while browsing (arrow keys / hover): apply the font
    // temporarily; a cancel (Escape / popup close) reverts to the last
    // committed font - no undo-stack artifact, no registry write.
    connect(m_cbFontPicker, &FontPicker::fontPreviewed,
            this, &MainWindow::onFontPreviewed);
    connect(m_cbFontPicker, &FontPicker::fontPreviewCanceled,
            this, &MainWindow::onFontPreviewCanceled);
    // Route theme changes through the group's triggered signal only - the
    // About action (no data) is not part of the group, so it never reaches
    // onThemeTriggered.  Individual triggered connections are still guarded
    // by onThemeTriggered's data check for extra safety.
    for (QAction* a : {m_themeSys, m_themeLight, m_themeDark})
        connect(a, &QAction::triggered, this,
                [this, a](bool) { onThemeTriggered(a); });

    // Caption buttons (frameless title bar)
    connect(m_btnMin, &QPushButton::clicked,
            this, &MainWindow::showMinimized);
    connect(m_btnMax, &QPushButton::clicked,
            this, &MainWindow::toggleMaximizeRestore);
    connect(m_btnClose, &QPushButton::clicked,
            this, &MainWindow::close);

    // Footer tip follows the active memo; counters debounced via a timer so
    // typing in a multi-megabyte document never recomputes per keystroke.
    connect(m_memo1, &QPlainTextEdit::selectionChanged,
            this, &MainWindow::updateFooterTip);
    connect(m_memo2, &QPlainTextEdit::selectionChanged,
            this, &MainWindow::updateFooterTip);
    connect(qApp, &QApplication::focusChanged,
            this, [this](QWidget*, QWidget*) { updateFooterTip(); });

    m_countDebounce = new QTimer(this);
    m_countDebounce->setSingleShot(true);
    m_countDebounce->setInterval(400);
    connect(m_countDebounce, &QTimer::timeout,
            this, &MainWindow::updateCountLabel);
    connect(m_memo1, &QPlainTextEdit::textChanged,
            this, &MainWindow::onMemoTextChanged);
    connect(m_memo2, &QPlainTextEdit::textChanged,
            this, &MainWindow::onMemoTextChanged);

    // Single debounced working-set trimmer.  Zoom and scroll bursts
    // (DirectWrite glyph caches, lazily committed layout pages) debounce at
    // 400 ms; typing idles at 1.5 s.  All sources restart the same timer, so
    // the latest activity wins and the working set is trimmed once after the
    // user stops - no overlapping timers, no duplicate trims.
    m_trimTimer = new QTimer(this);
    m_trimTimer->setSingleShot(true);
    connect(m_trimTimer, &QTimer::timeout, this, [this]() {
#ifdef Q_OS_WIN
        trimWorkingSet();
#endif
    });
    auto scheduleZoomTrim = [this]() { scheduleWorkingSetTrim(400); };
    auto scheduleIdleTrim = [this]() { scheduleWorkingSetTrim(1500); };
    connect(m_memo1, &MemoEdit::zoomLevelChanged, this, scheduleZoomTrim);
    connect(m_memo2, &MemoEdit::zoomLevelChanged, this, scheduleZoomTrim);
    connect(m_memo1, &QPlainTextEdit::textChanged, this, scheduleIdleTrim);
    connect(m_memo2, &QPlainTextEdit::textChanged, this, scheduleIdleTrim);
    connect(m_memo1->verticalScrollBar(), &QScrollBar::valueChanged,
            this, scheduleZoomTrim);
    connect(m_memo2->verticalScrollBar(), &QScrollBar::valueChanged,
            this, scheduleZoomTrim);
    connect(m_memo1, &MemoEdit::scrollActivity, this, scheduleZoomTrim);
    connect(m_memo2, &MemoEdit::scrollActivity, this, scheduleZoomTrim);

    // Instant reclaim when a memo is emptied: the document and its undo
    // buffers are already gone, so trim the working set with zero delay.
    connect(m_memo1, &MemoEdit::textEmptied,
            this, &MainWindow::onMemoEmptied);
    connect(m_memo2, &MemoEdit::textEmptied,
            this, &MainWindow::onMemoEmptied);

    // Zoom shortcuts are handled in keyPressEvent() below — that fires
    // regardless of which child widget holds focus.
}

// ---------------------------------------------------------------------------
// Global keyboard shortcuts (zoom)
// ---------------------------------------------------------------------------

MemoEdit* MainWindow::zoomTarget() const
{
    QWidget* fw = focusWidget();
    if (fw == m_memo1) return m_memo1;
    if (fw == m_memo2) return m_memo2;
    return m_memo2; // default to ANSI memo
}

void MainWindow::keyPressEvent(QKeyEvent* e)
{
    // Note: on Windows the zoom shortcuts are handled natively in
    // processMessage() (raw WM_KEYDOWN + VK codes) before Qt ever sees
    // the event, so this path is a fallback for non-Windows builds.
    if (e->modifiers() & Qt::ControlModifier) {
        MemoEdit* target = zoomTarget();
        switch (e->key()) {
        case Qt::Key_Plus:
        case Qt::Key_Equal: // Ctrl+= is the unshifted '+' key
            target->zoomIn();
            return;
        case Qt::Key_Minus:
            target->zoomOut();
            return;
        case Qt::Key_0:
            target->resetZoom();
            return;
        default:
            break;
        }
    }
    QMainWindow::keyPressEvent(e);
}

// ---------------------------------------------------------------------------
// Fonts / ANSI versions
// ---------------------------------------------------------------------------

void MainWindow::loadBundledFonts()
{
    // Prefer fonts shipped next to the executable (CMake copies assets/),
    // then the source tree when running from a build directory.
    QStringList roots;
    const QString exeFonts =
        QCoreApplication::applicationDirPath() + QStringLiteral("/assets/fonts");
    if (QDir(exeFonts).exists())
        roots << exeFonts;
    QString cwd = QDir::currentPath();
    for (int i = 0; i < 4; ++i) {
        const QString cand = cwd + QStringLiteral("/assets/fonts");
        if (QDir(cand).exists() && !roots.contains(cand))
            roots << cand;
        cwd = QDir(cwd).absoluteFilePath(QStringLiteral(".."));
    }

    // QFontDatabase keeps the raw file data resident for the app lifetime
    // (~1 MB for the four bundled fonts), so only register a bundled font
    // when its family is missing system-wide.  The Bengali Unicode fonts
    // ship with Windows (Nirmala UI / Vrinda), so on a stock Windows 10/11
    // install only the rare ANSI faces (Kalpurush ANSI, Siyam Rupali ANSI)
    // are actually loaded.
    struct BundledFont { const char* file; const char* family; };
    static const BundledFont bundled[] = {
        {"Siyamrupali.ttf", "Siyam Rupali"},
        {"kalpurush.ttf", "Kalpurush"},
        {"kalpurush ANSI.ttf", "Kalpurush ANSI"},
        {"Siyam Rupali ANSI.ttf", "Siyam Rupali ANSI"},
    };

    const QStringList& installed = allFontFamilies();
    QFontDatabase db;
    for (const QString& dir : roots) {
        for (const BundledFont& f : bundled) {
            const QString family = QString::fromLatin1(f.family);
            if (installed.contains(family))
                continue;  // system already provides it - skip
            const QString path = dir + QLatin1Char('/')
                                 + QString::fromLatin1(f.file);
            if (QFile::exists(path))
                db.addApplicationFont(path);
        }
    }
    // The cached family lists were snapshotted before the bundled faces were
    // registered; rebuild them on the next access so pickFont/makeAppIcon and
    // the font pickers see them.
    fontFamiliesCache().clear();
    FontPicker::invalidateFamilyCache();
}

QString MainWindow::pickFont(const QStringList& preferred) const
{
    const QStringList& installed = allFontFamilies();
    for (const QString& fam : preferred) {
        if (installed.contains(fam))
            return fam;
    }
    return preferred.isEmpty() ? QString() : preferred.last();
}

QString MainWindow::locateAnsiMappingDir() const
{
    // AVRO_MAPPING_DIR points the app at a different mapping folder - for a
    // portable deployment, and for testing a mapping change without touching
    // the installed Avro Keyboard.
    const QString override = qEnvironmentVariable("AVRO_MAPPING_DIR");
    if (!override.isEmpty())
        return override;

    // The mappings are never bundled with the converter: they come from the
    // installed Avro Keyboard, which ships them under ProgramData as encrypted
    // '.AvroEnco' containers (see avroenco_reader.h) - and, in older installs,
    // as readable '.json' files.  A missing installation is left for the
    // caller to report rather than papered over with a stale local table.
    const QString programData =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    const QString installed =
        programData + QStringLiteral("/Avro Keyboard/AnsiMapping");
    if (QDir(installed).exists())
        return installed;
    return QStringLiteral("C:/ProgramData/Avro Keyboard/AnsiMapping");
}

QStringList MainWindow::mappingVersionNames() const
{
    QStringList names;
    QDir dir(QString::fromStdWString(avro::g_registry.ansiMappingDir));
    if (!dir.exists())
        return names;

    // Encrypted containers first: a version ships either as '.AvroEnco' or as
    // a plain '.json', and the container wins when both are present (same
    // preference the loader applies when it resolves the file to open).
    QStringList files;
    for (const QString& pattern :
         {QStringLiteral("*.AvroEnco"), QStringLiteral("*.json")}) {
        files += dir.entryList({pattern}, QDir::Files, QDir::Unsorted);
    }

    names.reserve(files.size());
    QSet<QString> seen;
    for (const QString& f : files) {
        QString name = f;
        const int dot = name.lastIndexOf(QLatin1Char('.'));
        if (dot > 0)
            name.truncate(dot);
        const QString lower = name.toLower();
        if (seen.contains(lower))
            continue;
        seen.insert(lower);
        names << name;
    }

    // Natural numeric sorting (e.g. "V2" before "V10").
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(names.begin(), names.end(),
              [&collator](const QString& a, const QString& b) {
                  return collator.compare(a, b) < 0;
              });
    return names;
}

void MainWindow::populateAnsiVersions()
{
    // Also runs when the mapping folder changes, so the current pick has to
    // survive the rebuild: it is restored by name when it is still offered.
    const QString keep = m_cbAnsiVersion->currentText();
    const QSignalBlocker blocker(m_cbAnsiVersion);

    // The combo only offers what the mapping folder provides - there is no
    // built-in "Default" entry any more, so an empty folder leaves it empty.
    m_cbAnsiVersion->clear();
    for (const QString& name : mappingVersionNames())
        m_cbAnsiVersion->addItem(name);

    if (m_cbAnsiVersion->count() == 0)
        return;
    const int keepIdx = keep.isEmpty() ? -1 : m_cbAnsiVersion->findText(keep);
    m_cbAnsiVersion->setCurrentIndex(keepIdx >= 0 ? keepIdx : 0);
}

QString MainWindow::mappingFilePath(const QString& version) const
{
    const QString dir = QString::fromStdWString(avro::g_registry.ansiMappingDir);
    if (dir.isEmpty() || version.isEmpty())
        return QString();
    // Same preference the registry applies when it opens the file.
    const QString container = dir + version + QStringLiteral(".AvroEnco");
    if (QFileInfo::exists(container))
        return container;
    return dir + version + QStringLiteral(".json");
}

MainWindow::MappingSnapshot
MainWindow::mappingSnapshot(const QString& version) const
{
    MappingSnapshot snap;
    const QFileInfo info(mappingFilePath(version));
    if (!info.isFile())
        return snap;  // absent: an empty path never matches a real file
    snap.path = info.absoluteFilePath();
    snap.modified = info.lastModified().toMSecsSinceEpoch();
    snap.size = info.size();
    return snap;
}

void MainWindow::watchAnsiMappingDir()
{
    if (!m_mappingWatcher)
        return;
    // Re-add from scratch on every pass: paths are dropped by the watcher once
    // they stop existing (and a folder that did not exist yet was never
    // watched), so the set has to be rebuilt to keep reporting updates.
    const QStringList previous =
        m_mappingWatcher->files() + m_mappingWatcher->directories();
    if (!previous.isEmpty())
        m_mappingWatcher->removePaths(previous);

    const QString dir = locateAnsiMappingDir();
    if (QFileInfo(dir).isDir()) {
        m_mappingWatcher->addPath(dir);
    } else {
        // Avro Keyboard is not installed (yet): watch the parent folder too, so
        // its appearance counts as a change instead of being missed.
        const QDir parent = QFileInfo(dir).dir();
        if (parent.exists())
            m_mappingWatcher->addPath(parent.absolutePath());
    }

    // The file behind the active version as well: rewriting a container in
    // place is not always reported as a folder change.
    const QString active = mappingFilePath(m_cbAnsiVersion->currentText());
    if (!active.isEmpty() && QFileInfo(active).isFile())
        m_mappingWatcher->addPath(active);
}

void MainWindow::onMappingFilesChanged()
{
    // Never rebuild the list under an open popup: clearing the model while the
    // user is browsing it would pull the selection out from under them.
    if (m_cbAnsiVersion->view() && m_cbAnsiVersion->view()->isVisible()) {
        m_mappingDebounce->start();
        return;
    }

    const QString previousVersion = m_cbAnsiVersion->currentText();
    const MappingSnapshot previous = m_activeMappingSnapshot;

    populateAnsiVersions();  // keeps the pick when that version still exists
    watchAnsiMappingDir();   // re-arm the (now possibly stale) watched paths

    // The remembered version wins again when it becomes available: a mapping
    // that was missing at startup (or was just restored) is picked back up
    // instead of staying on whatever the rebuild fell back to.  An explicit
    // pick is remembered as such, so the combo already holding it is never
    // overridden here.
    bool autoSelected = false;
    const QString remembered = readAnsiVersion();
    if (!remembered.isEmpty() &&
        m_cbAnsiVersion->currentText() != remembered) {
        const int rememberedIdx = m_cbAnsiVersion->findText(remembered);
        if (rememberedIdx >= 0) {
            // Select with the signal blocked: this folder event issues its own
            // load request below (carrying the "available again" note), so
            // letting onAnsiVersionChanged fire here would only queue a second,
            // generic request for the same file.
            const QSignalBlocker blocker(m_cbAnsiVersion);
            m_cbAnsiVersion->setCurrentIndex(rememberedIdx);
            autoSelected = true;
        }
    }

    const QString version = m_cbAnsiVersion->currentText();
    const MappingSnapshot now = mappingSnapshot(version);
    m_activeMappingSnapshot = now;

    if (autoSelected) {
        // The mapping that was missing is back: load it (persisting it as the
        // active version again) and say so when it has landed.
        requestMappingLoad(version,
                           QStringLiteral("\u201c%1\u201d is available again - "
                                          "switching back to it.")
                               .arg(version),
                           /*persist=*/true, /*warnOnFailure=*/false);
        return;
    }

    const bool versionChanged = version != previousVersion;
    const bool fileChanged = now.path != previous.path ||
                             now.modified != previous.modified ||
                             now.size != previous.size;
    if (!versionChanged && !fileChanged)
        return;

    QString note;
    if (versionChanged) {
        // The picked version was removed, so the combo fell back to the first
        // mapping the folder offers.  An empty previous version means the
        // folder only just appeared - that is a first offer, not a loss.
        note = previousVersion.isEmpty()
                   ? QStringLiteral("\u201c%1\u201d is available - using it.")
                         .arg(version)
                   : QStringLiteral("\u201c%1\u201d is no longer available - "
                                    "using \u201c%2\u201d instead.")
                         .arg(previousVersion, version);
    }
    reloadActiveMapping(note);
}

void MainWindow::reloadActiveMapping(const QString& note)
{
    // A folder event (or a deferred one): re-read whatever the combo holds.
    // The outcome is reported in the footer - the dialog is reserved for an
    // explicit pick, which the user is waiting on.
    requestMappingLoad(m_cbAnsiVersion->currentText(), note,
                       /*persist=*/false, /*warnOnFailure=*/false);
}

void MainWindow::requestMappingLoad(const QString& version, const QString& note,
                                    bool persist, bool warnOnFailure, int retries)
{
    if (version.isEmpty())
        return;

    MappingRequest req;
    req.seq = ++m_mappingRequestSeq;
    req.version = version;
    req.note = note;
    req.retries = retries;
    req.persist = persist;
    req.warnOnFailure = warnOnFailure;
    // Newest request wins: whatever an older request produced is dropped
    // instead of briefly installing a mapping that is already out of date.
    m_mappingLiveSeq = req.seq;
    m_mappingQueue.enqueue(req);
    startQueuedMappingLoad();
}

void MainWindow::startQueuedMappingLoad()
{
    if (m_mappingLoadRunning || m_mappingQueue.isEmpty())
        return;

    m_mappingRunning = m_mappingQueue.dequeue();
    m_mappingLoadRunning = true;
    m_lblFooter->setText(
        QStringLiteral("Loading ANSI mapping \u201c%1\u201d\u2026")
            .arg(m_mappingRunning.version));

    // The worker decodes into a registry of its own, so the shared g_registry
    // is only ever touched from the UI thread.  The lambda captures copies
    // only, so it stays valid even when the window is closed mid-load.
    const MappingRequest req = m_mappingRunning;
    const std::wstring dir = avro::g_registry.ansiMappingDir;
    // Dev/test hook: AVRO_MAPPING_LOAD_DELAY_MS makes the decode artificially
    // slow, so the background path can be exercised on a fast local folder.
    const int artificialDelayMs =
        qEnvironmentVariableIntValue("AVRO_MAPPING_LOAD_DELAY_MS");
    m_mappingLoader->setFuture(QtConcurrent::run([req, dir, artificialDelayMs]() {
        if (artificialDelayMs > 0)
            QThread::msleep(static_cast<unsigned long>(artificialDelayMs));
        MappingLoadResult load;
        load.seq = req.seq;
        load.registry = std::make_shared<avro::AnsiRegistry>();
        load.registry->ansiMappingDir = dir;
        std::wstring err;
        load.ok =
            load.registry->trySetAnsiVersion(req.version.toStdWString(), err);
        load.error = QString::fromStdWString(err);
        return load;
    }));
}

void MainWindow::onMappingLoadFinished()
{
    m_mappingLoadRunning = false;
    const MappingRequest req = m_mappingRunning;
    const MappingLoadResult load = m_mappingLoader->result();

    // Superseded while it ran (a newer pick, a newer folder event): drop the
    // result - the newer request is already on its way.
    if (load.seq != m_mappingLiveSeq) {
        startQueuedMappingLoad();
        maybeRunDeferredConversion();
        return;
    }

    if (!load.ok) {
        // A file that is being written right now is not readable yet: retry
        // briefly, then keep the mapping that is already loaded rather than
        // leaving the user without one.
        if (req.retries < kMappingLoadRetries) {
            QTimer::singleShot(kMappingLoadRetryDelayMs, this, [this, req]() {
                // Only retry while this request is still the newest one: a
                // pick (or another folder event) that arrived in the meantime
                // must not be overwritten by a retry of the old version.
                if (req.seq != m_mappingLiveSeq)
                    return;
                requestMappingLoad(req.version, req.note, req.persist,
                                   req.warnOnFailure, req.retries + 1);
            });
            // A retry must not hold up a conversion that was waiting for this
            // load: converting against the mapping we still have beats waiting
            // for a file that may never become readable.
            maybeRunDeferredConversion();
            return;
        }
        m_activeMappingSnapshot = mappingSnapshot(req.version);
        if (req.warnOnFailure) {
            m_lblFooter->setText(
                QStringLiteral("Failed to load ANSI mapping \u201c%1\u201d: %2")
                    .arg(req.version, load.error));
            QMessageBox::warning(
                this, QStringLiteral("Avro Text Converter"),
                QStringLiteral("Failed to load ANSI mapping: %1")
                    .arg(load.error));
        } else {
            m_lblFooter->setText(
                QStringLiteral("Could not reload ANSI mapping \u201c%1\u201d: %2 "
                               "- keeping the previous one.")
                    .arg(req.version, load.error));
        }
        maybeRunDeferredConversion();
        return;
    }

    if (m_converting) {
        // The conversion worker reads g_registry while it runs; hold the fresh
        // mapping until completeConversion() reports that it is done.
        m_mappingDeferredInstall = load;
        m_mappingDeferredRequest = req;
        m_hasDeferredInstall = true;
    } else {
        installMapping(load, req);
    }
    maybeRunDeferredConversion();
}

void MainWindow::installMapping(const MappingLoadResult& load,
                                const MappingRequest& req)
{
    // Publishing is a move on the UI thread: the decrypt and the JSON parse
    // already happened on the worker, so this never waits on the disk.
    avro::g_registry = std::move(*load.registry);
    m_activeMappingSnapshot = mappingSnapshot(req.version);
    if (req.persist)
        saveAnsiVersion(req.version);
    if (!req.note.isEmpty())
        m_lblFooter->setText(req.note);
    else if (req.warnOnFailure)
        m_lblFooter->setText(QStringLiteral("Loaded ANSI mapping \u201c%1\u201d.")
                                 .arg(req.version));
    else
        m_lblFooter->setText(
            QStringLiteral("Reloaded ANSI mapping \u201c%1\u201d (the file "
                           "changed on disk).")
                .arg(req.version));

    // The version that just became active may carry its own font, so the ANSI
    // box has to follow the mapping (see SettingsDialog).
    applyEditorFonts();
}

void MainWindow::applyDeferredMappingInstall()
{
    if (!m_hasDeferredInstall)
        return;
    const MappingLoadResult load = m_mappingDeferredInstall;
    const MappingRequest req = m_mappingDeferredRequest;
    m_mappingDeferredInstall = MappingLoadResult{};
    m_mappingDeferredRequest = MappingRequest{};
    m_hasDeferredInstall = false;
    // A newer request may have replaced it while the conversion was running.
    if (load.seq != m_mappingLiveSeq)
        return;
    installMapping(load, req);
}

bool MainWindow::mappingLoadBusy() const
{
    // A pending retry timer is deliberately not part of this: a mapping file
    // that stays unreadable must not stall a conversion for seconds.
    return m_mappingLoadRunning || !m_mappingQueue.isEmpty() ||
           m_hasDeferredInstall;
}

void MainWindow::maybeRunDeferredConversion()
{
    if (!m_deferredConversion || m_converting || mappingLoadBusy())
        return;
    const bool forward = m_deferredConversionForward;
    m_deferredConversion = false;
    startConversion(forward);
}

// ---------------------------------------------------------------------------
// Conversion flow
// ---------------------------------------------------------------------------

void MainWindow::onUnicodeToAnsi()
{
    startConversion(true);
}

void MainWindow::onAnsiToUnicode()
{
    startConversion(false);
}

void MainWindow::startConversion(bool unicodeToAnsi)
{
    if (m_converting)
        return;

    const QString src = unicodeToAnsi ? m_memo1->toPlainText()
                                      : m_memo2->toPlainText();
    if (src.isEmpty())
        return;

    // A mapping load is still in flight (startup pick, folder change): a
    // conversion started now would build its tables from the mapping that is
    // about to be replaced, so wait for the load to settle and start then.
    if (mappingLoadBusy()) {
        m_deferredConversion = true;
        m_deferredConversionForward = unicodeToAnsi;
        m_lblFooter->setText(
            QStringLiteral("Waiting for ANSI mapping \u201c%1\u201d to load "
                           "before converting\u2026")
                .arg(m_cbAnsiVersion->currentText()));
        return;
    }

    m_converting = true;
    setCursor(Qt::WaitCursor);

    // Anchor focus on the source memo BEFORE disabling anything.  If the
    // clicked button still held focus when setEnabled(false) ran, Qt's
    // focus engine would hand focus to the next widget in tab order and
    // repaint it - the neighbor button briefly "blinking" into a
    // focused/default state.  With focus already on the memo, disabling is
    // a pure state change with no focus handoff.  (The FontPicker is
    // ClickFocus-only, and clearSearchFocus() is belt-and-braces against a
    // stray selection/focus ring there.)
    m_cbFontPicker->clearSearchFocus();
    (unicodeToAnsi ? m_memo1 : m_memo2)->setFocus();
    // Disable ONLY the clicked button (plus the ANSI-version combo, which
    // must not change mid-conversion because it mutates the shared mapping
    // registry).  The other convert button is deliberately left untouched:
    // its enabled state never changes during the conversion, so it never
    // repaints and cannot flash/blink.  Re-entry is already blocked by the
    // m_converting guard above.
    if (unicodeToAnsi)
        m_btnUniToAnsi->setEnabled(false);
    else
        m_btnAnsiToUni->setEnabled(false);
    // Do NOT disable m_cbAnsiVersion here: toggling its enabled state
    // forces a chevron-arrow repaint that causes visible flicker/blink.
    // Thread safety is ensured by the m_converting guard in
    // onAnsiVersionChanged instead.

    m_lblFooter->setVisible(false);
    m_lblCount->setVisible(false);
    m_progress->setValue(0);
    m_progress->setVisible(true);
    m_lblFooter->setText(QStringLiteral("Converting\u2026"));
    m_lblFooter->setVisible(true);

    // The conversion core is pure C++ with no Qt dependencies, so it runs on
    // a worker thread and the UI thread never blocks.  A fresh pair of
    // converter instances is created per run so per-instance toggle state
    // never leaks between conversions.  `self` guards against the window
    // being closed while the worker is still running.
    QPointer<MainWindow> self(this);
    QtConcurrent::run([self, unicodeToAnsi, src]() {
        if (!self)
            return;

        auto throttle = [self](int percent, const std::wstring& stage) {
            if (!self)
                return;
            // Throttle progress: at most one UI update every ~80 ms so the
            // message queue is not flooded on fast conversions.
            static std::atomic<qint64> last{0};
            const qint64 now = QDateTime::currentMSecsSinceEpoch();
            qint64 prev = last.load(std::memory_order_relaxed);
            if (now - prev < 80 && percent < 100)
                return;
            last.store(now, std::memory_order_relaxed);
            const QString stageStr = QString::fromStdWString(stage);
            QMetaObject::invokeMethod(
                self, [self, percent, stageStr]() {
                    if (self)
                        self->onConversionProgress(percent, stageStr);
                },
                Qt::QueuedConnection);
        };

        QString result;
        QString error;
        {
            // Inner scope: converters and their large internal tables
            // (SweepTable, lookup arrays) are destroyed as soon as this
            // block ends — BEFORE result is handed to the UI thread — so
            // peak RSS drops immediately instead of waiting for the outer
            // lambda to unwind.
            avro::UnicodeToBijoy fwdConv;
            avro::BijoyToUnicode revConv;
            try {
                // Pass the captured QString's own UTF-16 buffer straight to
                // the core via std::wstring_view (wchar_t is 16-bit on
                // Windows, same layout as QChar) - no toStdWString()
                // intermediate copy.  The buffer stays alive for the whole
                // worker run, so the view is valid for the synchronous
                // convert() call.  The core then takes exactly one owned
                // copy per working buffer.
                const std::wstring_view wideView(
                    reinterpret_cast<const wchar_t*>(src.utf16()),
                    src.size());
                if (unicodeToAnsi) {
                    fwdConv.onProgress = throttle;
                    result = QString::fromStdWString(
                        fwdConv.convert(wideView));
                } else {
                    revConv.onProgress = throttle;
                    result = QString::fromStdWString(
                        revConv.convert(wideView));
                }
            } catch (const std::exception& e) {
                error = QString::fromUtf8(e.what());
            } catch (...) {
                error = QStringLiteral("Unknown conversion error");
            }
        } // fwdConv, revConv + their tables destroyed here

        QMetaObject::invokeMethod(
            self, [self, unicodeToAnsi, result = std::move(result),
                   error = std::move(error)]() {
                if (self)
                    self->completeConversion(unicodeToAnsi, result, error);
            },
            Qt::QueuedConnection);
    });
}

void MainWindow::onConversionProgress(int percent, const QString& stage)
{
    if (!m_converting)
        return;
    m_progress->setValue(percent);
    if (!stage.isEmpty())
        m_lblFooter->setText(QStringLiteral("Converting\u2026 %1  (%2%)")
                                 .arg(stage)
                                 .arg(percent));
    else
        m_lblFooter->setText(QStringLiteral("Converting\u2026  (%1%)")
                                 .arg(percent));
}

void MainWindow::completeConversion(bool unicodeToAnsi, const QString& outText,
                                    const QString& errMsg)
{
    setCursor(Qt::ArrowCursor);
    m_progress->setVisible(false);
    m_lblCount->setVisible(true);
    m_converting = false;

    // Anchor focus on the memo that just received the converted text BEFORE
    // re-enabling the buttons, so the enable transition cannot trigger any
    // focus handoff/repaint on the toolbar.  The FontPicker cleanup is
    // belt-and-braces against a stray selection/focus ring.
    m_cbFontPicker->clearSearchFocus();
    (unicodeToAnsi ? m_memo2 : m_memo1)->setFocus();
    // Re-enable only what startConversion disabled (the other button was
    // never touched, so it has nothing to repaint here either).
    if (unicodeToAnsi)
        m_btnUniToAnsi->setEnabled(true);
    else
        m_btnAnsiToUni->setEnabled(true);

    if (!errMsg.isEmpty()) {
        m_lblFooter->setText(QStringLiteral("Conversion failed: %1").arg(errMsg));
        QMessageBox::critical(this, QStringLiteral("Avro Text Converter"),
                              QStringLiteral("Conversion failed: %1")
                                  .arg(errMsg));
        return;
    }

    if (unicodeToAnsi) {
        QString activeFont = m_cbFontPicker->activeFont();
        if (activeFont.isEmpty())
            activeFont = m_cbFontPicker->currentText();
        if (activeFont.isEmpty())
            activeFont = m_memo2->font().family();
        const int caret = m_memo2->textCursor().position();
        loadMemoText(m_memo2, outText, activeFont, caret);
        saveConverterFont(activeFont);
    } else {
        const int caret = m_memo1->textCursor().position();
        loadMemoText(m_memo1, outText, m_memo1->baseFont().family(), caret);
    }
    updateFooterTip();
    updateCountLabel();

    // A mapping that finished loading while the worker held the registry was
    // held back; the tables are rebuilt per conversion, so it can be installed
    // now - after the footer was refreshed, so the status stays visible.
    applyDeferredMappingInstall();
    // A conversion that was waiting for a mapping load starts here too (it did
    // not run above precisely because this install was still pending).
    maybeRunDeferredConversion();

#ifdef Q_OS_WIN
    // The conversion touched memo documents, worker buffers and the progress
    // bar; trim those pages back out of the working set right away.
    trimWorkingSet();
#endif

    // Autotest hook: dump the result, optionally grab a screenshot, and exit.
    if (!m_autotestOut.isEmpty()) {
        QFile outFile(m_autotestOut);
        if (outFile.open(QIODevice::WriteOnly)) {
            const QString result = m_autotestRev ? m_memo1->toPlainText()
                                                 : m_memo2->toPlainText();
            outFile.write(result.toUtf8());
            outFile.close();
        }
        const QString shot = qEnvironmentVariable("AVRO_AUTOTEST_SHOT");
        QTimer::singleShot(150, this, [this, shot]() {
            if (!shot.isEmpty())
                grab().save(shot);
            QApplication::quit();
        });
    }
}

void MainWindow::loadMemoText(MemoEdit* edit, const QString& text,
                              const QString& fontName, int restoreCaret)
{
    // Update the base font (family may change for ANSI preview).
    QFont font = edit->baseFont();
    if (!fontName.isEmpty())
        font.setFamily(fontName);
    edit->setBaseFont(font);

    // Set text directly on the existing document.  QPlainTextEdit uses
    // QPlainTextDocumentLayout which wraps/shapes ONLY the visible lines,
    // so even multi-megabyte loads are instant and keep RAM flat.
    // Disable undo while populating to avoid duplicating the entire
    // document into the undo stack as the initial snapshot.
    QTextDocument* doc = edit->document();
    doc->setUndoRedoEnabled(false);
    doc->setPlainText(text);

    // Re-enable undo with a clean stack.
    doc->clearUndoRedoStacks();
    doc->setUndoRedoEnabled(true);

    // Restore the caret to its pre-conversion position, clamped to the
    // new document length; a collapsed selection also clears any highlight.
    if (restoreCaret >= 0) {
        const int maxPos = doc->characterCount() - 1;
        QTextCursor caret(doc);
        caret.setPosition(qBound(0, restoreCaret, maxPos));
        edit->setTextCursor(caret);
    }
    edit->ensureCursorVisible();
    edit->viewport()->update();

#ifdef Q_OS_WIN
    // Trim the working set after loading a new document.
    trimWorkingSet();
#endif
}


// ---------------------------------------------------------------------------
// ANSI version / font pickers
// ---------------------------------------------------------------------------

void MainWindow::onAnsiVersionChanged(const QString& version)
{
    if (version.isEmpty())
        return;
    // The mapping is decrypted and parsed on a worker thread, so a slow - or
    // briefly unreadable - mapping folder cannot stall the picker.  Only the
    // finished registry is installed, and never while a conversion is reading
    // it (see onMappingLoadFinished / completeConversion); the combo is
    // deliberately left enabled, which used to swallow the pick entirely.
    //
    // Each conversion creates fresh converter instances (startConversion), so
    // their lookup tables are always built from the current mapping - no
    // cached instance to invalidate here.
    requestMappingLoad(version, QString(), /*persist=*/true,
                       /*warnOnFailure=*/true);
}

void MainWindow::onFontPicked(const QString& font)
{
    if (font.isEmpty())
        return;
    // Remember the committed font so a cancelled preview can restore it.
    m_committedAnsiFont = font;
    QFont f = m_memo2->baseFont();
    f.setFamily(font);
    m_memo2->setBaseFont(f);

    // The toolbar picker edits the shared ANSI box font - the one every
    // mapping follows unless it has a font of its own - and nothing else.  A
    // mapping's own font belongs to the Settings sheet and is never written
    // from here: with a mapping selected, picking a font in the toolbar used to
    // rewrite that mapping's row, so the sheet appeared to change itself (and
    // the pick silently became a permanent per-mapping font).
    saveConverterFont(font);
}

void MainWindow::onFontPreviewed(const QString& font)
{
    // Temporary live preview while browsing the font list: apply the font
    // to the ANSI memo but do NOT persist it or change the picker's active
    // font - a cancel (Escape / popup close) reverts to the committed one.
    if (font.isEmpty())
        return;
    QFont f = m_memo2->baseFont();
    if (f.family() == font)
        return;
    f.setFamily(font);
    m_memo2->setBaseFont(f);
}

void MainWindow::onFontPreviewCanceled()
{
    // The user browsed the list and abandoned the pick (Escape or the
    // popup closed without a commit): restore the last committed font.
    if (m_committedAnsiFont.isEmpty())
        return;
    QFont f = m_memo2->baseFont();
    if (f.family() == m_committedAnsiFont)
        return;
    f.setFamily(m_committedAnsiFont);
    m_memo2->setBaseFont(f);
}

// ---------------------------------------------------------------------------
// Theme handling
// ---------------------------------------------------------------------------

void MainWindow::onThemeTriggered(QAction* action)
{
    // Only the three theme actions carry theme data.  "About" and any other
    // non-theme action have an invalid/null data() - without this guard,
    // data().toInt() returns 0 == ThemeMode::System and would yank the app
    // into whatever the OS theme is (the reported bug: clicking About in
    // Light mode flipped the app to Dark).  The QActionGroup in
    // buildSettingsMenu already keeps non-theme actions out of this slot;
    // this check is the final line of defence.
    if (!action || !action->data().isValid()
        || !action->data().canConvert<int>())
        return;
    const ThemeMode mode = static_cast<ThemeMode>(action->data().toInt());
    if (mode < ThemeMode::System || mode > ThemeMode::Dark)
        return;
    m_themeMode = mode;
    applyTheme(mode);
    saveThemeMode(mode);
}

void MainWindow::updateThemeCheck()
{
    // Keep the menu in sync with the actual theme - a check mark beside the
    // active entry (System / Light / Dark).  Safe against null members so
    // it can also be called before buildSettingsMenu() runs.
    if (!m_themeSys || !m_themeLight || !m_themeDark)
        return;
    m_themeSys->setChecked(m_themeMode == ThemeMode::System);
    m_themeLight->setChecked(m_themeMode == ThemeMode::Light);
    m_themeDark->setChecked(m_themeMode == ThemeMode::Dark);
}

MainWindow::ThemeMode MainWindow::readThemeMode() const
{
    QSettings s = appRegistry();
    const QString mode = s.value(QStringLiteral("ThemeMode"),
                                 QStringLiteral("System")).toString();
    if (mode.compare(QStringLiteral("Dark"), Qt::CaseInsensitive) == 0)
        return ThemeMode::Dark;
    if (mode.compare(QStringLiteral("Light"), Qt::CaseInsensitive) == 0)
        return ThemeMode::Light;
    return ThemeMode::System;
}

void MainWindow::saveThemeMode(ThemeMode mode) const
{
    QSettings s = appRegistry();
    const char* names[] = {"System", "Light", "Dark"};
    s.setValue(QStringLiteral("ThemeMode"),
               QString::fromLatin1(names[static_cast<int>(mode)]));
}

bool MainWindow::isSystemDark() const
{
#ifdef Q_OS_WIN
    QSettings s(QStringLiteral(
        "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\"
        "Themes\\Personalize"),
        QSettings::NativeFormat);
    return !s.value(QStringLiteral("AppsUseLightTheme"), 1).toBool();
#else
    const QColor win = QApplication::palette().color(QPalette::Window);
    return win.lightness() < 128;
#endif
}

void MainWindow::applyTheme(ThemeMode mode)
{
    bool dark = (mode == ThemeMode::Dark);
    if (mode == ThemeMode::System)
        dark = isSystemDark();
    applyPalette(dark);
    updateThemeCheck();
}

void MainWindow::applyPalette(bool dark)
{
    const QColor text = dark ? QColor(0xE6, 0xE6, 0xE6) : QColor(0x23, 0x27, 0x2E);
    QPalette pal;
    pal.setColor(QPalette::Window, dark ? kDarkBg : QColor(0xF3, 0xF4, 0xF6));
    pal.setColor(QPalette::WindowText, text);
    pal.setColor(QPalette::Base, dark ? QColor(0x1C, 0x1C, 0x21)
                                      : QColor(0xFF, 0xFF, 0xFF));
    pal.setColor(QPalette::AlternateBase, dark ? QColor(0x2A, 0x2A, 0x2A)
                                               : QColor(0xF7, 0xF7, 0xF7));
    pal.setColor(QPalette::Text, text);
    pal.setColor(QPalette::Button, dark ? QColor(0x2C, 0x2C, 0x31)
                                        : QColor(0xFF, 0xFF, 0xFF));
    pal.setColor(QPalette::ButtonText, text);
    pal.setColor(QPalette::Highlight, kAccent);
    pal.setColor(QPalette::HighlightedText, Qt::white);
    pal.setColor(QPalette::ToolTipBase, dark ? QColor(0x2C, 0x2C, 0x31)
                                             : QColor(0xFF, 0xFF, 0xFF));
    pal.setColor(QPalette::ToolTipText, text);
    pal.setColor(QPalette::PlaceholderText, dark ? QColor(0x88, 0x88, 0x88)
                                                 : QColor(0x99, 0x99, 0x99));
    QApplication::setPalette(pal);

    // Apply the stylesheet app-wide (not just to this window) so that
    // separate top-level popups - e.g. the font picker's completer list -
    // also pick up the themed styling and matching row heights.
    qApp->setStyleSheet(buildStyleSheet(dark));

    // Re-polish all styled widgets so the QSS engine re-evaluates cached
    // rules.  Without this, the internal QLineEdit of editable combos and
    // any widget with a custom QProxyStyle retains stale cached visuals
    // from the previous theme.
    for (QWidget* w : {static_cast<QWidget*>(m_cbAnsiVersion),
                       static_cast<QWidget*>(m_cbFontPicker)}) {
        w->style()->unpolish(w);
        w->style()->polish(w);
        w->update();
    }
    if (m_cbFontPicker && m_cbFontPicker->lineEdit()) {
        QWidget* le = m_cbFontPicker->lineEdit();
        le->style()->unpolish(le);
        le->style()->polish(le);
        le->update();
    }

    m_btnSettings->setIcon(makeGearIcon(text));

    // The caption glyphs are painted (see makeCaptionIcon), so they are
    // re-tinted with the theme's text colour along with the gear.
    m_iconCaptionMinimize = makeCaptionIcon(CaptionIcon::Minimize, text);
    m_iconCaptionMaximize = makeCaptionIcon(CaptionIcon::Maximize, text);
    m_iconCaptionRestore = makeCaptionIcon(CaptionIcon::Restore, text);
    m_iconCaptionClose = makeCaptionIcon(CaptionIcon::Close, text);
    m_btnMin->setIcon(m_iconCaptionMinimize);
    m_btnClose->setIcon(m_iconCaptionClose);
    m_btnMax->setIcon(isMaximized() ? m_iconCaptionRestore
                                   : m_iconCaptionMaximize);

    // After the stylesheet re-polish, Qt may have reset widget fonts to
    // style defaults.  MemoEdit::changeEvent handles the memo widgets
    // (reasserting m_baseFont via applyZoom()), but the FontPicker's
    // displayed text and the memo base-font families need an explicit
    // restore here so the user's choices survive the theme switch.
    {
        QSignalBlocker blocker(m_cbFontPicker);
        if (!m_committedAnsiFont.isEmpty())
            m_cbFontPicker->setActiveFont(m_committedAnsiFont);
    }
    // Reassert memo base fonts (family may have been reset by the polish).
    // applyZoom() in each MemoEdit's changeEvent handles the zoomed size,
    // but the base font family must be explicitly restored here.
    m_memo1->setBaseFont(m_memo1->baseFont());
    m_memo2->setBaseFont(m_memo2->baseFont());
}

void MainWindow::showEvent(QShowEvent* e)
{
    QMainWindow::showEvent(e);
#ifdef Q_OS_WIN
    if (HWND hwnd = reinterpret_cast<HWND>(winId())) {
        // Re-add WS_THICKFRAME so DefWindowProc can initiate the resize loop
        // when processMessage returns HTLEFT/HTRIGHT/HTTOP/HTBOTTOM.
        const LONG style = GetWindowLongW(hwnd, GWL_STYLE);
        SetWindowLongW(hwnd, GWL_STYLE, style | WS_THICKFRAME);

        // Extend the DWM frame into the entire client area (-1, -1, -1, -1).
        // This restores the native window drop shadow that FramelessWindowHint
        // removes.  The same technique used by Windows Terminal, Chrome, and
        // every other polished frameless app on Windows 10/11.
        const MARGINS m = {1, 1, 1, 1};
        DwmExtendFrameIntoClientArea(hwnd, &m);

        // Install a Win32 subclass so our WndProc runs BEFORE Qt's QPA
        // WndProc.  This lets us handle WM_NCLBUTTONDOWN (HTMAXBUTTON)
        // and WM_NCLBUTTONDBLCLK (HTCAPTION) before Qt intercepts them.
        SetWindowSubclass(hwnd, rawWndProc, 0,
                          reinterpret_cast<DWORD_PTR>(this));
    }
#endif

}

void MainWindow::onMemoEmptied()
{
#ifdef Q_OS_WIN
    // The memo just released its document + undo buffers; reclaim the pages
    // immediately instead of waiting for the idle auto-trim.
    trimWorkingSet();
#endif
}

void MainWindow::scheduleWorkingSetTrim(int delayMs)
{
    // Shared debounce for all trim sources: restarting a running single-shot
    // timer simply reschedules it, so bursts collapse into one trim.
    m_trimTimer->setInterval(delayMs);
    m_trimTimer->start();
}

#ifdef Q_OS_WIN
// ---------------------------------------------------------------------------
// Working set trimming
// ---------------------------------------------------------------------------
void MainWindow::trimWorkingSet()
{
    // Force the CRT / Windows Heap allocator to consolidate and release
    // freed virtual pages back to the OS BEFORE trimming the working set.
    // HeapCompact merges adjacent free blocks so their backing pages become
    // eligible for release; SetProcessWorkingSetSize then flushes them out
    // of physical RAM into the pagefile.
    HeapCompact(GetProcessHeap(), 0);
    // Flush pages the OS considers unused back to the pagefile (they are
    // demand-paged back in if touched again, so this is always safe).
    SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1),
                             static_cast<SIZE_T>(-1));
}

// ---------------------------------------------------------------------------
// Win32 HWND subclass — runs before Qt's QPA WndProc so we intercept
// WM_NCLBUTTONDOWN (HTMAXBUTTON) and WM_NCLBUTTONDBLCLK (HTCAPTION)
// before Qt swallows them.
// ---------------------------------------------------------------------------

LRESULT CALLBACK MainWindow::rawWndProc(HWND hwnd, UINT msg,
                                       WPARAM wParam, LPARAM lParam,
                                       UINT_PTR subclassId,
                                       DWORD_PTR refData)
{
    Q_UNUSED(subclassId);
    auto* self = reinterpret_cast<MainWindow*>(refData);
    if (!self)
        return DefSubclassProc(hwnd, msg, wParam, lParam);
    return self->processMessage(hwnd, msg, wParam, lParam);
}

bool MainWindow::isWindowMaximized() const
{
#ifdef Q_OS_WIN
    if (HWND hwnd = reinterpret_cast<HWND>(
            const_cast<MainWindow*>(this)->winId())) {
        if (IsZoomed(hwnd))
            return true;
    }
#endif
    return isMaximized();
}

void MainWindow::toggleMaximizeRestore()
{
#ifdef Q_OS_WIN
    if (HWND hwnd = reinterpret_cast<HWND>(winId())) {
        if (isWindowMaximized())
            ShowWindow(hwnd, SW_RESTORE);
        else
            ShowWindow(hwnd, SW_MAXIMIZE);
        return;
    }
#endif
    isMaximized() ? showNormal() : showMaximized();
}

LRESULT MainWindow::processMessage(HWND hwnd, UINT msg,
                                   WPARAM wParam, LPARAM lParam)
{
    switch (msg) {

    // ── WM_GETMINMAXINFO ──────────────────────────────────────────
    case WM_GETMINMAXINFO: {
        auto* mmi = reinterpret_cast<MINMAXINFO*>(lParam);
        mmi->ptMinTrackSize.x = minimumWidth();
        mmi->ptMinTrackSize.y = minimumHeight();
        if (HMONITOR hmon = MonitorFromWindow(
                hwnd, MONITOR_DEFAULTTONEAREST)) {
            MONITORINFO mi = {sizeof(mi)};
            GetMonitorInfoW(hmon, &mi);
            const RECT work = mi.rcWork;
            mmi->ptMaxPosition.x = work.left - mi.rcMonitor.left;
            mmi->ptMaxPosition.y = work.top - mi.rcMonitor.top;
            mmi->ptMaxSize.x = work.right - work.left;
            mmi->ptMaxSize.y = work.bottom - work.top;
        }
        return 0;
    }

    // ── WM_NCACTIVATE ─────────────────────────────────────────────
    case WM_NCACTIVATE:
        return TRUE;

    // ── WM_NCHITTEST ──────────────────────────────────────────────
    case WM_NCHITTEST: {
        const POINT screenPt = {GET_X_LPARAM(lParam),
                                GET_Y_LPARAM(lParam)};
        RECT rc;
        GetWindowRect(hwnd, &rc);
        const int x = screenPt.x - rc.left;
        const int y = screenPt.y - rc.top;
        const int w = rc.right - rc.left;
        const int h = rc.bottom - rc.top;
        constexpr int bw = 6;

        // Title bar region (checked for both normal and maximized states
        // so double-click-to-restore works via HTCAPTION + DefSubclassProc).
        if (m_titleBar && y < m_titleBar->height()) {
            const QPoint local = m_titleBar->mapFromGlobal(
                QPoint(screenPt.x, screenPt.y));
            if (QWidget* child = m_titleBar->childAt(local)) {
                // All three caption buttons return HTCLIENT so Qt delivers
                // a normal WM_LBUTTONDOWN → clicked() signal with no
                // Win32 non-client interference.
                if (child == m_btnMin || child == m_btnMax || child == m_btnClose)
                    return HTCLIENT;
            }
            // Empty title bar area: HTCAPTION enables native drag, Aero
            // Snap, and double-click maximize/restore via DefSubclassProc.
            return HTCAPTION;
        }

        // Resize borders (only in normal state; maximized windows have no
        // resize handles — the early title-bar check above already handles
        // the maximized case).
        if (!isWindowMaximized()) {
            if (y < bw) {
                if (x < bw)     return HTTOPLEFT;
                if (x > w - bw) return HTTOPRIGHT;
                return HTTOP;
            }
            if (y > h - bw) {
                if (x < bw)     return HTBOTTOMLEFT;
                if (x > w - bw) return HTBOTTOMRIGHT;
                return HTBOTTOM;
            }
            if (x < bw)         return HTLEFT;
            if (x > w - bw)     return HTRIGHT;
        }

        return HTCLIENT;
    }

    // ── WM_KEYDOWN ──────────────────────────────────────────────────
    // Zoom shortcuts handled here, on raw VK codes, so they work
    // regardless of NumLock state, focus widget, window-activation
    // state, keyboard layout or IME — every Qt-level shortcut layer is
    // bypassed.  The key is swallowed (return 0) so Qt never sees it.
    case WM_KEYDOWN:
        if (GetKeyState(VK_CONTROL) & 0x8000) {
            MemoEdit* target = zoomTarget();
            switch (wParam) {
            case VK_ADD:      // numpad +
            case VK_OEM_PLUS: // main row +/=
                target->zoomIn();
                return 0;
            case VK_SUBTRACT:  // numpad -
            case VK_OEM_MINUS: // main row -
                target->zoomOut();
                return 0;
            case VK_NUMPAD0: // numpad 0, NumLock on
            case 0x30:       // main row 0 (VK_0, not defined by MinGW)
                target->resetZoom();
                return 0;
            case VK_INSERT:
                // Numpad 0 with NumLock OFF arrives as VK_INSERT: scan
                // code 0x52 with the extended bit (bit 24) clear — the
                // real Insert key is extended and stays untouched.
                if (!(lParam & 0x01000000)
                    && ((lParam >> 16) & 0xFF) == 0x52) {
                    target->resetZoom();
                    return 0;
                }
                break;
            default:
                break;
            }
        }
        break;

    // ── WM_SIZE ─────────────────────────────────────────────────────
    // Keep the maximize/restore button icon in sync when the OS changes
    // the window state externally (Aero Snap, taskbar menu, etc.).
    case WM_SIZE: {
        if (m_btnMax) {
            const bool zoomed = (wParam == SIZE_MAXIMIZED)
                                || isWindowMaximized();
            m_btnMax->setIcon(zoomed ? m_iconCaptionRestore
                                     : m_iconCaptionMaximize);
            m_btnMax->setToolTip(zoomed
                ? QStringLiteral("Restore")
                : QStringLiteral("Maximize"));
        }
        break;
    }

    default:
        break;
    }

    return DefSubclassProc(hwnd, msg, wParam, lParam);
}
#endif // Q_OS_WIN

void MainWindow::changeEvent(QEvent* e)
{
    QMainWindow::changeEvent(e);
    if (e->type() == QEvent::WindowStateChange && m_btnMax) {
        const bool maximized = isMaximized();
        // Restore-down: two overlapping squares; maximize: single outline.
        m_btnMax->setIcon(maximized ? m_iconCaptionRestore
                                    : m_iconCaptionMaximize);
        m_btnMax->setToolTip(maximized
            ? QStringLiteral("Restore")
            : QStringLiteral("Maximize"));
    }
}

QString MainWindow::buildStyleSheet(bool dark) const
{
    const QString bg      = dark ? QStringLiteral("#1f1f1f")
                                 : QStringLiteral("#f3f4f6");
    const QString panel   = dark ? QStringLiteral("#26262b")
                                 : QStringLiteral("#ffffff");
    const QString memo    = dark ? QStringLiteral("#1c1c21")
                                 : QStringLiteral("#ffffff");
    const QString border  = dark ? QStringLiteral("#3c3c41")
                                 : QStringLiteral("#e2e5ea");
    const QString text    = dark ? QStringLiteral("#e6e6e6")
                                 : QStringLiteral("#23272e");
    const QString sub     = dark ? QStringLiteral("#9a9aa2")
                                 : QStringLiteral("#7a828e");
    const QString btn2Bg  = dark ? QStringLiteral("#2c2c31")
                                 : QStringLiteral("#ffffff");
    const QString btn2Br  = dark ? QStringLiteral("#4a4a52")
                                 : QStringLiteral("#cfd4da");
    const QString hover   = dark ? QStringLiteral("#2f2f35")
                                 : QStringLiteral("#f6f7f9");
    const QString accent  = QStringLiteral("#E67E22");
    const QString accentHi = QStringLiteral("#F39C12");
    const QString accentLo = QStringLiteral("#D35400");
    const QString disabled = dark ? QStringLiteral("#5a5a62")
                                  : QStringLiteral("#c3c8cf");

    QString qss = QStringLiteral(
               "QWidget#CentralRoot { background-color: @@BG@@; }\n"
               "QWidget#PanelButton { background-color: @@PANEL@@; "
               "border-bottom: 1px solid @@BORDER@@; }\n"
               "QWidget#PanelFooter { background-color: @@PANEL@@; "
               "border-top: 1px solid @@BORDER@@; }\n"
               "QLabel { color: @@TEXT@@; background: transparent; }\n"
               "QLabel#LblCount { color: @@SUB@@; font-size: 11px; }\n"
               "QLabel#LblFooter { font-size: 11px; }\n"
               "\n"
               "QPushButton#BtnPrimary {\n"
               "  background: qlineargradient(x1:0, y1:0, x2:0, y2:1, "
               "stop:0 @@ACCENT_HI@@, stop:1 @@ACCENT@@);\n"
               "  color: #ffffff; border: none; border-radius: 6px;\n"
               "  font-weight: bold; padding: 0 12px;\n"
               "}\n"
               "QPushButton#BtnPrimary:hover { background: @@ACCENT_HI@@; }\n"
               "QPushButton#BtnPrimary:pressed { background: @@ACCENT_LO@@; }\n"
               "QPushButton#BtnPrimary:disabled { background: @@DISABLED@@; "
               "color: @@SUB@@; }\n"
               "QPushButton#BtnPrimary:focus { outline: none; }\n"
               "\n"
               "QPushButton#BtnSecondary {\n"
               "  background: @@BTN2_BG@@; color: @@TEXT@@; border: 1px solid @@BTN2_BR@@;\n"
               "  border-radius: 6px; font-weight: bold; padding: 0 12px;\n"
               "}\n"
               "QPushButton#BtnSecondary:hover { background: @@HOVER@@; }\n"
               "QPushButton#BtnSecondary:pressed { background: @@BTN2_BR@@; }\n"
               "QPushButton#BtnSecondary:disabled { background: @@DISABLED@@; "
               "color: @@SUB@@; }\n"
               "QPushButton#BtnSecondary:focus { outline: none; }\n"
               "\n"
               "QComboBox#CbAnsiVersion {\n"
               "  background: @@BTN2_BG@@; color: @@TEXT@@; border: 1px solid @@BTN2_BR@@;\n"
               "  border-radius: 6px; padding-left: 10px; padding-right: 28px;\n"
               "  min-height: 28px;\n"
               "}\n"
               "QComboBox#CbAnsiVersion:hover { border-color: @@ACCENT@@; }\n"
               "QComboBox#CbAnsiVersion:focus { border: 1px solid @@ACCENT@@; }\n"
               "QComboBox#CbAnsiVersion:editable { background: @@BTN2_BG@@; }\n"
               "QComboBox#CbAnsiVersion:editable:hover { background: @@HOVER@@; border-color: @@ACCENT@@; }\n"
               "QComboBox#CbAnsiVersion:editable:focus { border: 1px solid @@ACCENT@@; }\n"
               "\n"
               "/* Dropdown Button Area */\n"
               "QComboBox#CbAnsiVersion::drop-down {\n"
               "  subcontrol-origin: padding;\n"
               "  subcontrol-position: center right;\n"
               "  width: 26px;\n"
               "  border: none;\n"
               "  background: transparent;\n"
               "}\n"
               "\n"
               "/* LineEdit inside editable combo (FontPicker) */\n"
               "QComboBox#CbAnsiVersion QLineEdit {\n"
               "  background: transparent;\n"
               "  color: @@TEXT@@;\n"
               "  border: none;\n"
               "  padding: 0;\n"
               "  selection-background-color: @@ACCENT@@;\n"
               "  selection-color: #ffffff;\n"
               "}\n"
               "\n"
               "QComboBox QAbstractItemView {\n"
               "  background: @@BTN2_BG@@; color: @@TEXT@@; border: 1px solid @@BTN2_BR@@;\n"
               "  border-radius: 6px; selection-background-color: @@ACCENT_HI@@;\n"
               "  selection-color: #ffffff; outline: none; padding: 2px;\n"
               "}\n"
               "QComboBox QAbstractItemView::item { padding: 5px 8px; "
               "border-radius: 4px; }\n"
               "QComboBox QAbstractItemView::item:hover "
               "{ background: @@HOVER@@; color: @@TEXT@@; }\n"
               "QComboBox QAbstractItemView::item:selected "
               "{ background: @@ACCENT_HI@@; color: #ffffff; }\n"
               "QComboBox QAbstractItemView::item:selected:hover "
               "{ background: @@ACCENT_HI@@; color: #ffffff; }\n"
               "\n"
               "QAbstractItemView#CbFontPickerPopup {\n"
               "  background: @@BTN2_BG@@; color: @@TEXT@@; border: 1px solid @@BTN2_BR@@;\n"
               "  border-radius: 6px; selection-background-color: @@ACCENT_HI@@;\n"
               "  selection-color: #ffffff; outline: none; padding: 2px;\n"
               "}\n"
               "QAbstractItemView#CbFontPickerPopup::item { padding: 5px 8px; "
               "border-radius: 4px; }\n"
               "QAbstractItemView#CbFontPickerPopup::item:hover "
               "{ background: @@HOVER@@; color: @@TEXT@@; }\n"
               "QAbstractItemView#CbFontPickerPopup::item:selected "
               "{ background: @@ACCENT_HI@@; color: #ffffff; }\n"
               "QAbstractItemView#CbFontPickerPopup::item:selected:hover "
               "{ background: @@ACCENT_HI@@; color: #ffffff; }\n"
               "\n"
               "QToolButton#BtnSettings {\n"
               "  background: transparent; border: none; border-radius: 6px;\n"
               "}\n"
               "QToolButton#BtnSettings:hover { background: @@HOVER@@; }\n"
               "QToolButton#BtnSettings:pressed { background: @@BTN2_BR@@; }\n"
               "QToolButton#BtnSettings::menu-indicator { image: none; }\n"
               "\n"
               "QPlainTextEdit#Memo {\n"
               "  background-color: @@MEMO@@; border: 1px solid @@BORDER@@;\n"
               "  border-radius: 8px; padding: 6px; color: @@TEXT@@;\n"
               "  selection-background-color: @@ACCENT@@; selection-color: #ffffff;\n"
               "}\n"
               "QPlainTextEdit#Memo:hover { border-color: @@BTN2_BR@@; }\n"
               "QPlainTextEdit#Memo:focus { border: 1px solid @@ACCENT@@; }\n"
               "\n"
               "QSplitter::handle { background-color: transparent; }\n"
               "QSplitter::handle:hover { background-color: @@ACCENT@@; }\n"
               "\n"
               "QProgressBar#ProgBar {\n"
               "  background-color: @@BTN2_BR@@; border: none; border-radius: 4px;\n"
               "}\n"
               "QProgressBar#ProgBar::chunk {\n"
               "  background-color: @@ACCENT@@; border-radius: 4px;\n"
               "}\n"
               "\n"
               "QMenu { background-color: @@BTN2_BG@@; color: @@TEXT@@; border: 1px solid @@BTN2_BR@@; "
               "border-radius: 6px; padding: 4px; }\n"
               "QMenu::item { padding: 6px 26px 6px 12px; border-radius: 4px; }\n"
               "QMenu::item:selected { background-color: @@ACCENT@@; color: #ffffff; }\n"
               "QMenu::item:disabled { color: @@SUB@@; }\n"
               "QMenu::separator { height: 1px; background: @@BTN2_BR@@; "
               "margin: 4px 8px; }\n"
               "\n"
               "QToolTip {\n"
               "  background-color: @@BTN2_BG@@; color: @@TEXT@@;\n"
               "  border: 1px solid @@BORDER@@; padding: 2px 4px;\n"
               "  font-size: 11px; font-weight: normal;\n"
               "}\n"
               "\n"
               "QScrollBar:vertical { background: transparent; width: 12px; "
               "margin: 2px; }\n"
               "QScrollBar::handle:vertical { background: @@BTN2_BR@@; "
               "border-radius: 5px; min-height: 30px; }\n"
               "QScrollBar::handle:vertical:hover { background: @@ACCENT@@; }\n"
               "QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical "
               "{ height: 0; }\n"
               "QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical "
               "{ background: transparent; }\n"
               "QScrollBar:horizontal { background: transparent; height: 12px; "
               "margin: 2px; }\n"
               "QScrollBar::handle:horizontal { background: @@BTN2_BR@@; "
               "border-radius: 5px; min-width: 30px; }\n"
               "QScrollBar::handle:horizontal:hover { background: @@ACCENT@@; }\n"
               "QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal "
               "{ width: 0; }\n"
               "QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal "
               "{ background: transparent; }\n"
               "\n"
               "QWidget#TitleBar {\n"
               "  background-color: @@BG@@; border-bottom: 1px solid @@BORDER@@;\n"
               "}\n"
               "QLabel#LblTitle {\n"
               "  color: @@TEXT@@; font-size: 13px; font-weight: 500;\n"
               "  background: transparent;\n"
               "}\n"
               "QPushButton#BtnMin, QPushButton#BtnMax, QPushButton#BtnClose {\n"
               "  background: transparent; border: none;\n"
               "  min-width: 46px; max-width: 46px;\n"
               "  min-height: 36px; max-height: 36px;\n"
               "}\n"
               "QPushButton#BtnMin:hover, QPushButton#BtnMax:hover {\n"
               "  background-color: @@HOVER@@;\n"
               "}\n"
               "QPushButton#BtnMin:pressed, QPushButton#BtnMax:pressed {\n"
               "  background-color: @@BTN2_BR@@;\n"
               "}\n"
               "QPushButton#BtnClose:hover {\n"
               "  background-color: #E81123; color: #ffffff;\n"
               "}\n"
               "QPushButton#BtnClose:pressed {\n"
               "  background-color: #C42B1C; color: #ffffff;\n"
               "}\n");

    qss.replace("@@BG@@", bg)
       .replace("@@PANEL@@", panel)
       .replace("@@BORDER@@", border)
       .replace("@@TEXT@@", text)
       .replace("@@SUB@@", sub)
       .replace("@@ACCENT@@", accent)
       .replace("@@ACCENT_HI@@", accentHi)
       .replace("@@ACCENT_LO@@", accentLo)
       .replace("@@DISABLED@@", disabled)
       .replace("@@BTN2_BG@@", btn2Bg)
       .replace("@@BTN2_BR@@", btn2Br)
       .replace("@@HOVER@@", hover)
       .replace("@@MEMO@@", memo);

    return qss;
}

// ---------------------------------------------------------------------------
// Footer / counters / icons
// ---------------------------------------------------------------------------

void MainWindow::updateFooterTip()
{
    if (m_converting)
        return;
    const bool m1 = m_memo1->hasFocus();
    const bool m2 = m_memo2->hasFocus();
    if (m2 && !m1) {
        m_lblFooter->setText(QStringLiteral(
            "ANSI preview - pick a font above, or press \"ANSI to Unicode\" "
            "to convert back."));
    } else {
        m_lblFooter->setText(QStringLiteral(
            "Unicode input - type or paste Bengali text, then press "
            "\"Unicode to ANSI\"."));
    }
}

void MainWindow::onMemoTextChanged()
{
    m_countDebounce->start();
}

void MainWindow::updateCountLabel()
{
    // characterCount() includes the trailing paragraph separator, so
    // subtract 1 — matches toPlainText().size() but allocates nothing
    // (toPlainText() copies the whole document on every debounce tick).
    const int inChars = m_memo1->document()->characterCount() - 1;
    const int outChars = m_memo2->document()->characterCount() - 1;
    m_lblCount->setText(QStringLiteral("In: %1  \u00b7  Out: %2")
                            .arg(inChars)
                            .arg(outChars));
}

QIcon MainWindow::makeGearIcon(const QColor& color) const
{
    QPixmap pm(20, 20);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(QPen(color, 2.1));
    p.setBrush(Qt::NoBrush);
    const QPointF c(10.0, 10.0);
    p.save();
    for (int i = 0; i < 8; ++i) {
        p.save();
        p.translate(c);
        p.rotate(i * 45.0);
        p.drawLine(QPointF(0.0, -9.2), QPointF(0.0, -6.3));
        p.restore();
    }
    p.restore();
    p.drawEllipse(c, 5.6, 5.6);
    p.setPen(Qt::NoPen);
    p.setBrush(color);
    p.drawEllipse(c, 1.5, 1.5);
    p.end();
    return QIcon(pm);
}

QIcon MainWindow::makeAppIcon() const
{
    // Prefer the bundled logo (assets/icon/Converter.ico) so the title bar,
    // taskbar, Alt-Tab and tray all show the same artwork; the drawn accent
    // tile below is only the fallback for a build without the asset.
    const QIcon& bundled = bundledAppIcon();
    if (!bundled.isNull())
        return bundled;

    QPixmap pm(64, 64);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);
    p.setBrush(kAccent);
    p.drawRoundedRect(2, 2, 60, 60, 14, 14);
    QFont f(QStringLiteral("Bornomala"), 34, QFont::Bold);
    if (!allFontFamilies().contains(QStringLiteral("Bornomala")))
        f = QFont(QStringLiteral("Nirmala UI"), 34, QFont::Bold);
    p.setFont(f);
    p.setPen(Qt::white);
    p.drawText(pm.rect(), Qt::AlignCenter, QStringLiteral("\u0985"));
    p.end();
    return QIcon(pm);
}

void MainWindow::createTrayIcon()
{
    // Desktop shells without a notification area (rare on Windows, common in
    // remote/CI sessions) simply get no tray icon.
    if (!QSystemTrayIcon::isSystemTrayAvailable())
        return;

    m_tray = new QSystemTrayIcon(makeAppIcon(), this);
    m_tray->setToolTip(QStringLiteral("Avro Text Converter"));

    auto* menu = new QMenu(this);
    QAction* actToggle = menu->addAction(QStringLiteral("Show / Hide window"));
    connect(actToggle, &QAction::triggered, this,
            &MainWindow::toggleWindowVisibility);
    menu->addSeparator();
    QAction* actQuit = menu->addAction(QStringLiteral("Exit"));
    connect(actQuit, &QAction::triggered, this, [this]() {
        // Same path as the title-bar close button; the explicit quit() covers
        // the case where the window was hidden via the tray (a hidden window
        // is not a "last visible window", so closing it may not end the app).
        close();
        QCoreApplication::quit();
    });
    m_tray->setContextMenu(menu);

    connect(m_tray, &QSystemTrayIcon::activated, this,
            [this](QSystemTrayIcon::ActivationReason reason) {
                if (reason == QSystemTrayIcon::Trigger
                    || reason == QSystemTrayIcon::DoubleClick)
                    toggleWindowVisibility();
            });
    m_tray->show();
}

void MainWindow::toggleWindowVisibility()
{
    if (isVisible() && !isMinimized()) {
        hide();
        return;
    }
    showNormal();
    raise();
    activateWindow();
}

void MainWindow::closeEvent(QCloseEvent* e)
{
    QMainWindow::closeEvent(e);
}

// ---------------------------------------------------------------------------
// Settings persistence (same registry keys as the Delphi app)
// ---------------------------------------------------------------------------

QString MainWindow::readAnsiVersion() const
{
    QSettings s = appRegistry();
    return s.value(QStringLiteral("AnsiVersion")).toString();
}

void MainWindow::saveAnsiVersion(const QString& v) const
{
    QSettings s = appRegistry();
    s.setValue(QStringLiteral("AnsiVersion"), v);
}

QString MainWindow::readConverterFont() const
{
    QSettings s = appRegistry();
    return s.value(QStringLiteral("ConverterAnsiFont")).toString();
}

void MainWindow::saveConverterFont(const QString& f) const
{
    if (f.isEmpty())
        return;
    QSettings s = appRegistry();
    s.setValue(QStringLiteral("ConverterAnsiFont"), f);
}

// ---------------------------------------------------------------------------
// Editor fonts (see SettingsDialog)
// ---------------------------------------------------------------------------

QString MainWindow::unicodeFontFamily() const
{
    // Empty means "whatever buildUi picked" (a bundled or system Bengali
    // font), so a fresh install never has to store a default.
    QSettings s = appRegistry();
    return s.value(QStringLiteral("UnicodeFont")).toString();
}

int MainWindow::unicodeFontSize() const
{
    QSettings s = appRegistry();
    return qBound(editorFont::kMinSize,
                  s.value(QStringLiteral("UnicodeFontSize"),
                          editorFont::kDefaultSize).toInt(),
                  editorFont::kMaxSize);
}

int MainWindow::ansiFontSize() const
{
    QSettings s = appRegistry();
    return qBound(editorFont::kMinSize,
                  s.value(QStringLiteral("AnsiFontSize"),
                          editorFont::kDefaultSize).toInt(),
                  editorFont::kMaxSize);
}

QString MainWindow::mappingFont(const QString& version) const
{
    if (version.isEmpty())
        return QString();
    QSettings s = appRegistry();
    s.beginGroup(QStringLiteral("MappingFonts"));
    const QString family = s.value(version).toString();
    s.endGroup();
    return family;
}

bool MainWindow::mappingFontEnabled(const QString& version) const
{
    if (version.isEmpty())
        return true;
    QSettings s = appRegistry();
    s.beginGroup(QStringLiteral("MappingSwitches"));
    // Only the switched-off mappings are recorded, so a missing key means "on"
    // - including a settings file written before this group existed, where a
    // stored mapping font could only ever mean a mapping using its own font.
    const bool on = s.value(version, true).toBool();
    s.endGroup();
    return on;
}

QString MainWindow::effectiveAnsiFont(const QString& version) const
{
    const QString own = mappingFont(version);
    // A switched-off mapping keeps its family in the settings - that is what
    // makes switching it back on restore the font it had - but renders with
    // the shared ANSI font, which is what the switch means.
    if (own.isEmpty() || !mappingFontEnabled(version))
        return readConverterFont();
    return own;
}

void MainWindow::applyEditorFonts()
{
    const QString version = m_cbAnsiVersion ? m_cbAnsiVersion->currentText()
                                            : QString();

    QFont uni = m_memo1->baseFont();
    const QString uniFamily = unicodeFontFamily();
    if (!uniFamily.isEmpty())
        uni.setFamily(uniFamily);
    uni.setPointSize(unicodeFontSize());
    m_memo1->setBaseFont(uni);

    QFont ansi = m_memo2->baseFont();
    const QString ansiFamily = effectiveAnsiFont(version);
    if (!ansiFamily.isEmpty())
        ansi.setFamily(ansiFamily);
    ansi.setPointSize(ansiFontSize());
    m_memo2->setBaseFont(ansi);

    // The toolbar picker edits whatever the active version uses, so it has to
    // show that font - and a cancelled preview reverts to it.
    m_committedAnsiFont = ansi.family();
    if (m_cbFontPicker) {
        QSignalBlocker blocker(m_cbFontPicker);
        m_cbFontPicker->setActiveFont(ansi.family());
    }
}

EditorFontSettings MainWindow::currentEditorFontSettings() const
{
    EditorFontSettings current;
    current.unicodeFont = unicodeFontFamily().isEmpty()
                              ? m_memo1->baseFont().family()
                              : unicodeFontFamily();
    current.unicodeSize = unicodeFontSize();
    // The ANSI box shows the active version's font; the dialog edits the shared
    // ANSI font, so offer that one (falling back to what is on screen when
    // nothing is stored yet).
    current.ansiFont = readConverterFont().isEmpty()
                           ? m_memo2->baseFont().family()
                           : readConverterFont();
    current.ansiSize = ansiFontSize();
    for (const QString& version : mappingVersionNames()) {
        const QString family = mappingFont(version);
        if (family.isEmpty())
            continue;
        // A switched-off mapping travels with its remembered family too, so
        // the sheet can switch it back on without losing the font.
        current.mappingFonts.insert(version, family);
        if (!mappingFontEnabled(version))
            current.mappingFontsOff.insert(version);
    }
    return current;
}

EditorFontSettings MainWindow::defaultEditorFontSettings() const
{
    // The same preference lists buildUi uses for a fresh install, so "Reset to
    // Defaults" restores exactly what the first run picked.  The mapping half
    // (one family per mapping) is filled in by SettingsDialog itself - it is the
    // only one that knows the folder's mappings - see
    // SettingsDialog::defaultsForReset().
    EditorFontSettings defaults;
    defaults.unicodeFont = pickFont({QStringLiteral("Bornomala"),
                                     QStringLiteral("Vrinda"),
                                     QStringLiteral("Nirmala UI"),
                                     QStringLiteral("Kalpurush"),
                                     QStringLiteral("Segoe UI")});
    defaults.ansiFont = pickFont({QStringLiteral("Kalpurush ANSI"),
                                  QStringLiteral("Siyam Rupali ANSI"),
                                  QStringLiteral("Kalpurush"),
                                  QStringLiteral("SutonnyMJ")});
    defaults.unicodeSize = editorFont::kDefaultSize;
    defaults.ansiSize = editorFont::kDefaultSize;
    return defaults;
}

void MainWindow::openSettingsDialog()
{
    showSettingsDialog();
}

void MainWindow::showSettingsDialog()
{
    const QStringList versions = mappingVersionNames();
    SettingsDialog dialog(currentEditorFontSettings(),
                          defaultEditorFontSettings(), versions, this);

    // Apply is wired live: the sheet stays open so more settings can be
    // visited, and the window follows every Apply.  Cancel never reaches this
    // slot, which is what makes it the rollback path (the dialog stages its
    // edits and only hands them over here).
    connect(&dialog, &SettingsDialog::settingsApplied, this,
            [this](const EditorFontSettings& chosen) {
                persistEditorFontSettings(chosen);
            });

    dialog.exec();
}

void MainWindow::persistEditorFontSettings(const EditorFontSettings& chosen)
{
    {
        QSettings s = appRegistry();
        s.setValue(QStringLiteral("UnicodeFont"), chosen.unicodeFont);
        s.setValue(QStringLiteral("UnicodeFontSize"), chosen.unicodeSize);
        s.setValue(QStringLiteral("AnsiFontSize"), chosen.ansiSize);
        // Both mapping groups are rewritten from scratch: a mapping that is no
        // longer in the folder must lose its entries instead of keeping the
        // stored ones.  A switched-off mapping still stores its family here
        // (that is what makes the switch reversible), while its switch lives
        // in the sibling group below.
        s.remove(QStringLiteral("MappingFonts"));
        s.beginGroup(QStringLiteral("MappingFonts"));
        for (auto it = chosen.mappingFonts.cbegin();
             it != chosen.mappingFonts.cend(); ++it)
            s.setValue(it.key(), it.value());
        s.endGroup();
        // Only the switched-off mappings are recorded: an absent key means the
        // switch is on, which is also how settings written before this group
        // existed are read (see mappingFontEnabled).
        s.remove(QStringLiteral("MappingSwitches"));
        s.beginGroup(QStringLiteral("MappingSwitches"));
        for (const QString& version : chosen.mappingFontsOff)
            s.setValue(version, false);
        s.endGroup();
    }
    saveConverterFont(chosen.ansiFont);

    // The theme is not part of this dialog: it has its own gear-menu entries
    // and is saved by onThemeTriggered().
    applyEditorFonts();
    m_lblFooter->setText(QStringLiteral("Settings applied."));
}
