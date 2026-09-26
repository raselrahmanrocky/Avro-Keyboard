// main.cpp - Avro Text Converter (Qt port of the Delphi VCL application).
#include <QApplication>
#include <QTimer>

#include "ui/fontpicker.h"
#include "ui/mainwindow.h"

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

    MainWindow w;
    w.show();

    // Dev helper: `AvroTextConverter --screenshot out.png [--wait ms]` renders
    // the main window into a PNG and exits - used for visual verification.
    // --wait (default 900 ms) lets a test change files on disk while the window
    // is live, e.g. to watch a mapping folder refresh itself.
    QString shotPath;
    int waitMs = 900;
    for (int i = 1; i < argc - 1; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QStringLiteral("--screenshot"))
            shotPath = QString::fromLocal8Bit(argv[i + 1]);
        else if (arg == QStringLiteral("--wait"))
            waitMs = QString::fromLocal8Bit(argv[i + 1]).toInt();
    }
    if (waitMs <= 0)
        waitMs = 900;
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
