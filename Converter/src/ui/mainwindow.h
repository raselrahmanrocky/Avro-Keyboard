// mainwindow.h - main window of the Qt Avro Text Converter.
// Faithful port of Unit1.pas/Unit1.dfm: toolbar with convert buttons,
// ANSI-version picker and searchable font picker, two memo panels split by
// a splitter, and a footer with a context tip + progress bar.
#pragma once

#include <QMainWindow>
#include <QColor>
#include <QFutureWatcher>
#include <QIcon>
#include <QQueue>
#include <QString>
#include <QStringList>

#include "core/ansi_registry.h"
#include "ui/settingsdialog.h"

#include <memory>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

class QAction;
class QComboBox;
class QFileSystemWatcher;
class QIcon;
class QLabel;
class QProgressBar;
class QPushButton;
class QSplitter;
class QSystemTrayIcon;
class QToolButton;
class QMenu;
class QTimer;
class FontPicker;
class MemoEdit;

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget* parent = nullptr);
    ~MainWindow() override;

    enum class ThemeMode { System, Light, Dark };

protected:
    void closeEvent(QCloseEvent* e) override;
    void showEvent(QShowEvent* e) override;
    void keyPressEvent(QKeyEvent* e) override;
#ifdef Q_OS_WIN
    // SetWindowSubclass callback — runs before Qt's WndProc so we intercept
    // WM_NCLBUTTONDOWN / WM_NCLBUTTONDBLCLK before Qt's QPA swallows them.
    static LRESULT CALLBACK rawWndProc(HWND hwnd, UINT msg,
                                       WPARAM wParam, LPARAM lParam,
                                       UINT_PTR subclassId,
                                       DWORD_PTR refData);
    LRESULT processMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    bool isWindowMaximized() const;
    // Asks Windows to flush pages the process is not actively touching out
    // of the working set.  Called once after startup settles and after each
    // conversion (memory the run touched is trimmed back to the pagefile).
    void trimWorkingSet();
#endif
    void changeEvent(QEvent* e) override;

private slots:
    void onUnicodeToAnsi();
    void onAnsiToUnicode();
    void onAnsiVersionChanged(const QString& version);
    void onFontPicked(const QString& font);
    void onFontPreviewed(const QString& font);
    void onFontPreviewCanceled();
    void onThemeTriggered(QAction* action);
    void onMemoTextChanged();
    void onConversionProgress(int percent, const QString& stage);
    // A memo just became empty (Clear / last character deleted): its
    // document + undo buffers are already purged, so trim the working set.
    void onMemoEmptied();
    // The gear menu's "Settings..." entry.  A slot (not just a private
    // helper) so a scripted run can open the sheet - see the
    // AVRO_OPEN_SETTINGS dev hook.
    void openSettingsDialog();

private:
    void buildUi();
    void buildSettingsMenu();
    void connectSignals();
    void toggleMaximizeRestore();

    // Notification-area icon: same logo as the window/taskbar icon, with a
    // Show/Hide + Exit menu.  No-op when the platform has no tray.
    void createTrayIcon();
    void toggleWindowVisibility();

    // Memo that zoom shortcuts should target: the focused memo, else the
    // ANSI memo.  Used by both the Qt keyPressEvent fallback and the
    // native WM_KEYDOWN handler in processMessage().
    MemoEdit* zoomTarget() const;

    // Conversion flow (mirrors StartConversion / CompleteConversion).
    void startConversion(bool unicodeToAnsi);
    void completeConversion(bool unicodeToAnsi, const QString& outText,
                            const QString& errMsg);
    void loadMemoText(MemoEdit* edit, const QString& text,
                      const QString& fontName, int restoreCaret = -1);

    // Theme handling (mirrors HandleThemes).
    void applyTheme(ThemeMode mode);
    void applyPalette(bool dark);
    void updateThemeCheck();
    QString buildStyleSheet(bool dark) const;
    bool isSystemDark() const;
    ThemeMode readThemeMode() const;
    void saveThemeMode(ThemeMode mode) const;
    QString readAnsiVersion() const;
    void saveAnsiVersion(const QString& v) const;
    QString readConverterFont() const;
    void saveConverterFont(const QString& f) const;

    // Builds and runs the sheet (the single Settings page, see SettingsDialog).
    void showSettingsDialog();

    // Editor fonts.  Each box keeps its own family and point size, and a
    // mapping version may use a family of its own (see SettingsDialog): the
    // shared ANSI font is the fallback for every mapping that does not.
    QString unicodeFontFamily() const;
    int unicodeFontSize() const;
    int ansiFontSize() const;
    // The family a mapping remembers as its own, whether or not its switch is
    // on (an empty result means it never had one).  Read-only here: per-mapping
    // fonts are written by the Settings sheet alone (see persistEditorFontSettings),
    // never by the toolbar picker.
    QString mappingFont(const QString& version) const;
    // Whether that mapping actually uses its own family: the switch on the
    // row in the Settings sheet.
    bool mappingFontEnabled(const QString& version) const;
    // Font the ANSI box uses for `version`: its own while the switch is on,
    // else the shared ANSI font (empty when neither is set).
    QString effectiveAnsiFont(const QString& version) const;
    // Pushes the stored fonts into both memos and into the toolbar picker.
    void applyEditorFonts();
    // The fonts the window is showing right now, and the built-in first-run
    // values.  Both go to SettingsDialog, which cannot resolve the bundled or
    // system family names on its own (the "Reset to Defaults" target needs
    // real families, not empty strings).
    EditorFontSettings currentEditorFontSettings() const;
    EditorFontSettings defaultEditorFontSettings() const;
    // Writes EditorFontSettings out and re-fonts the editors.  Wired to
    // SettingsDialog::settingsApplied, so Apply takes effect immediately.
    void persistEditorFontSettings(const EditorFontSettings& chosen);

    // Working-set trimming: restart the shared debounced trim timer with the
    // given delay (400 ms for zoom/scroll bursts, 1.5 s after typing).
    void scheduleWorkingSetTrim(int delayMs);

    // Mapping files (mirrors PopulateAnsiVersionsCombo).
    void populateAnsiVersions();
    QString locateAnsiMappingDir() const;
    // The versions the mapping folder offers, sorted naturally and without
    // duplicates.
    QStringList mappingVersionNames() const;

    // Live mapping refresh: Avro Keyboard (or a user) can add, rewrite or
    // remove a mapping while this window is open, so the folder and the file
    // behind the active version are watched and re-read instead of requiring a
    // restart.  watchAnsiMappingDir() (re-)arms the watched paths,
    // onMappingFilesChanged() is the debounced handler, and reloadActiveMapping
    // is what asks for the active version to be read again.
    //
    // Loading is asynchronous: decrypting a container (AES + zlib) and parsing
    // its JSON is the slow part of a mapping change, so it runs on a worker
    // thread against a private AnsiRegistry (requestMappingLoad /
    // startQueuedMappingLoad) and only the finished registry is installed on
    // the UI thread (installMapping).  A slow - or briefly unwritable - mapping
    // folder therefore never stalls the window.
    void watchAnsiMappingDir();
    void onMappingFilesChanged();
    void reloadActiveMapping(const QString& note = QString());

    // One mapping load request.  The newest request wins: a result that a newer
    // request has already replaced is dropped instead of briefly installing a
    // mapping the user has moved on from.
    struct MappingRequest {
        quint64 seq = 0;
        QString version;
        QString note;               // footer message to show once it lands
        int retries = 0;
        bool persist = false;       // remember the version once it loaded
        bool warnOnFailure = false; // combo pick -> dialog, folder event -> footer
    };
    // What the worker produced: its own registry, or the reason it failed.
    struct MappingLoadResult {
        quint64 seq = 0;
        bool ok = false;
        QString error;
        std::shared_ptr<avro::AnsiRegistry> registry;
    };

    // Queue a load of `version` and, when no load is running, start it.
    void requestMappingLoad(const QString& version, const QString& note,
                            bool persist, bool warnOnFailure, int retries = 0);
    void startQueuedMappingLoad();
    void onMappingLoadFinished();
    // Publish a finished load: swap the worker's registry into the shared one,
    // remember the file state and report the outcome.
    void installMapping(const MappingLoadResult& load, const MappingRequest& req);
    // Install a load that landed while a conversion was reading the registry.
    void applyDeferredMappingInstall();
    // True while a load is running, queued or waiting to be installed: a
    // conversion started now would run against the mapping being replaced.
    bool mappingLoadBusy() const;
    // Start the conversion that mappingLoadBusy() had deferred, if any.
    void maybeRunDeferredConversion();

    // Version name -> the file the registry would open for it (the encrypted
    // container wins over a same-named readable .json).
    QString mappingFilePath(const QString& version) const;

    // Fingerprint of the file behind a version, so a folder event only counts
    // as "the active mapping changed" when that file really did.
    struct MappingSnapshot {
        QString path;
        qint64 modified = -1;
        qint64 size = -1;
    };
    MappingSnapshot mappingSnapshot(const QString& version) const;

    // Fonts: load bundled .ttf files so Bengali renders even when the
    // required fonts are not installed system-wide.
    void loadBundledFonts();
    QString pickFont(const QStringList& preferred) const;

    // Footer tip / counters.
    void updateFooterTip();
    void updateCountLabel();

    // Font preview state: m_committedAnsiFont is the last font actually picked
    // from the toolbar (persisted as the shared ANSI font); onFontPreviewed
    // applies a temporary font without persisting, and onFontPreviewCanceled
    // restores the committed one.
    QString m_committedAnsiFont;

    // Dev/test hook: when AVRO_AUTOTEST_IN/OUT are set, run one conversion
    // on startup, write the result to OUT and quit (no UI interaction).
    void runAutotestIfRequested();

    QIcon makeGearIcon(const QColor& color) const;
    QIcon makeAppIcon() const;

    // UI members
    QPushButton* m_btnUniToAnsi = nullptr;
    QPushButton* m_btnAnsiToUni = nullptr;
    QComboBox* m_cbAnsiVersion = nullptr;
    FontPicker* m_cbFontPicker = nullptr;
    QToolButton* m_btnSettings = nullptr;
    QSplitter* m_splitter = nullptr;
    MemoEdit* m_memo1 = nullptr;
    MemoEdit* m_memo2 = nullptr;
    QLabel* m_lblFooter = nullptr;
    QLabel* m_lblCount = nullptr;
    QProgressBar* m_progress = nullptr;
    QMenu* m_themeMenu = nullptr;
    QAction* m_themeSys = nullptr;
    QAction* m_themeLight = nullptr;
    QAction* m_themeDark = nullptr;
    QTimer* m_countDebounce = nullptr;
    QTimer* m_trimTimer = nullptr;  // single debounced working-set trim
    QSystemTrayIcon* m_tray = nullptr;

    // Mapping folder watching (see watchAnsiMappingDir).
    QFileSystemWatcher* m_mappingWatcher = nullptr;
    QTimer* m_mappingDebounce = nullptr;
    MappingSnapshot m_activeMappingSnapshot;

    // Background mapping loading (see requestMappingLoad).  The loader is the
    // only bridge to the worker; everything else here is UI-thread state.
    QFutureWatcher<MappingLoadResult>* m_mappingLoader = nullptr;
    QQueue<MappingRequest> m_mappingQueue;
    MappingRequest m_mappingRunning; // request the in-flight load belongs to
    quint64 m_mappingRequestSeq = 0;
    quint64 m_mappingLiveSeq = 0;    // only this request's result is installed
    bool m_mappingLoadRunning = false;
    // Loaded on the worker, not installed yet: a conversion was reading the
    // registry when the load landed, so it waits for the conversion to finish.
    MappingLoadResult m_mappingDeferredInstall;
    MappingRequest m_mappingDeferredRequest;
    bool m_hasDeferredInstall = false;
    // A conversion requested while a mapping load was still in flight (or an
    // install was still pending) runs as soon as the load settles.
    bool m_deferredConversion = false;
    bool m_deferredConversionForward = true;

    // Custom title bar (frameless window)
    QWidget*    m_titleBar  = nullptr;
    QLabel*     m_lblTitle  = nullptr;
    QPushButton* m_btnMin   = nullptr;
    QPushButton* m_btnMax   = nullptr;
    QPushButton* m_btnClose = nullptr;
    // Window-button glyphs are painted instead of typeset and re-tinted by
    // applyPalette (see makeCaptionIcon: the Windows icon fonts that carry
    // these glyphs are not installed everywhere, and asking Qt for a missing
    // family costs a full font-collection fallback search on the first paint).
    QIcon m_iconCaptionMinimize, m_iconCaptionMaximize, m_iconCaptionRestore,
        m_iconCaptionClose;

    // Worker state
    bool m_converting = false;
    ThemeMode m_themeMode = ThemeMode::System;

    // Autotest hook state
    QString m_autotestIn;
    QString m_autotestOut;
    bool m_autotestRev = false;
};
