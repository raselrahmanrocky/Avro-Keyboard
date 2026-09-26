// main.cpp - Avro Text Converter (Qt port of the Delphi VCL application).
#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>
#include <QTimer>

#ifdef Q_OS_WIN
#  include <windows.h>
#endif

#include "ui/fontpicker.h"
#include "ui/mainwindow.h"

#ifdef Q_OS_WIN
// Single instance: the first process holds this mutex for its whole lifetime;
// a second launch only sees ERROR_ALREADY_EXISTS and restores the window.
static const wchar_t* const kInstanceMutex =
    L"Global\\AvroTextConverterSingleInstance";
// The exact title MainWindow sets (MainWindow::setWindowTitle) - that is how
// the second instance finds the window of the first.
static const wchar_t* const kWindowTitle = L"Avro Text Converter";

// Brings the running instance's window back in front of the user.  The window
// can be minimised (SW_RESTORE) or hidden to the notification area: a hidden
// window is still found by its title, but SW_RESTORE alone leaves it
// invisible, so the hidden-to-tray case needs SW_SHOW.
static void restoreRunningInstance(HWND hwnd)
{
    ShowWindow(hwnd, SW_RESTORE);
    if (!IsWindowVisible(hwnd))
        ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
}
#endif

int main(int argc, char* argv[])
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    QApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
#endif

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Avro Text Converter"));
    app.setApplicationVersion(QStringLiteral("1.0.0"));
    app.setOrganizationName(QStringLiteral("OmicronLab"));
    app.setOrganizationDomain(QStringLiteral("omicronlab.com"));
    app.setStyle(QStringLiteral("Fusion"));

    // Every switch this app knows is registered here, so parsing never runs
    // into an unknown argument.  parse() (not process()): a malformed switch is
    // reported and the window still comes up.
    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Bengali text converter (Unicode <-> ANSI Bijoy)"));
    parser.addHelpOption();
    parser.addVersionOption();
    const QCommandLineOption mappingDirOption(
        QStringLiteral("mapping-dir"),
        QStringLiteral("Read the ANSI mapping containers from <dir> instead of "
                       "the installed Avro Keyboard (portable deployments)."),
        QStringLiteral("dir"));
    parser.addOption(mappingDirOption);
    // Dev helper: `AvroTextConverter --screenshot out.png [--wait ms]` renders
    // the main window into a PNG and exits - used for visual verification.
    // --wait (default 900 ms) lets a test change files on disk while the window
    // is live, e.g. to watch a mapping folder refresh itself.
    const QCommandLineOption screenshotOption(
        QStringLiteral("screenshot"),
        QStringLiteral("Render the window into <file> and exit (development)."),
        QStringLiteral("file"));
    const QCommandLineOption waitOption(
        QStringLiteral("wait"),
        QStringLiteral("Delay before --screenshot, in ms (default 900)."),
        QStringLiteral("ms"));
    parser.addOption(screenshotOption);
    parser.addOption(waitOption);
    if (!parser.parse(app.arguments()))
        qWarning("%s", qPrintable(parser.errorText()));
    // parse() - unlike process() - does not act on --help/--version itself.
    if (parser.isSet(QStringLiteral("help")))
        parser.showHelp(0);        // prints the help and exits
    if (parser.isSet(QStringLiteral("version")))
        parser.showVersion();      // prints the version and exits

    // The mapping directory has to be in place before the first window exists:
    // the runtime reads AVRO_MAPPING_DIR when it resolves the mapping folder.
    const QString mappingDir = parser.value(mappingDirOption);
    if (!mappingDir.isEmpty())
        qputenv("AVRO_MAPPING_DIR", mappingDir.toLocal8Bit());

    const QString shotPath = parser.value(screenshotOption);
    int waitMs = parser.value(waitOption).toInt();
    if (waitMs <= 0)
        waitMs = 900;

    // A second copy only restores the window of the running instance and
    // exits.  The screenshot run is exempt, so visual verification can work
    // next to a live copy.
#ifdef Q_OS_WIN
    if (shotPath.isEmpty()) {
        HANDLE mutex = CreateMutexW(nullptr, FALSE, kInstanceMutex);
        if (mutex && GetLastError() == ERROR_ALREADY_EXISTS) {
            // No-op while the first instance has not shown its window yet.
            if (HWND hwnd = FindWindowW(nullptr, kWindowTitle))
                restoreRunningInstance(hwnd);
            return 0;
        }
        // The handle is deliberately not released: the mutex only has to exist
        // for as long as this process lives.
    }
#endif

    MainWindow w;
    w.show();

    if (!shotPath.isEmpty()) {
        QTimer::singleShot(waitMs, [&w, shotPath]() {
            // Capture whatever the run put in front of the user: the settings
            // dialog (AVRO_OPEN_SETTINGS=1) or the gear menu (=menu), else the
            // main window itself.
            QWidget* target = QApplication::activeModalWidget();
            if (!target)
                target = QApplication::activePopupWidget();
            (target ? target : static_cast<QWidget*>(&w))->grab().save(shotPath);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}
