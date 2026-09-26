// memoedit.h - QPlainTextEdit subclass with Ctrl+wheel zoom, keyboard zoom
// shortcuts and a rich context menu (Cut/Copy/Paste/Select All/Clear plus
// zoom controls), mirroring the Delphi memo behaviour.
//
// Uses QPlainTextEdit instead of QTextEdit: QPlainTextDocumentLayout wraps
// and shapes ONLY the visible lines in the viewport, keeping RAM flat during
// window resize of large (1.5M+ char) documents.
#pragma once

#include <QPlainTextEdit>

class MemoEdit : public QPlainTextEdit
{
    Q_OBJECT

public:
    explicit MemoEdit(QWidget* parent = nullptr);

    void setBaseFont(const QFont& f);
    QFont baseFont() const { return m_baseFont; }

    void zoomIn(int steps = 1);
    void zoomOut(int steps = 1);
    void resetZoom();
    int zoomPercent() const { return m_zoomPercent; }

    void clear();

    // Configure the hint drawn in paintEvent() - both editors use this instead
    // of Qt's native placeholder text.
    //
    // The hint is ALWAYS rendered in `hintFont`, whatever the widget's own font,
    // size or zoom is: a native placeholder is drawn in the editor's current
    // font, so the Unicode box's hint swung between tiny and huge as the Unicode
    // font/size changed (and its Bengali font would also garble an English hint
    // on the ANSI side).  Both boxes are given the same font, so the two hints
    // can never differ.
    void setCustomPlaceholder(const QString& text, const QFont& hintFont);
    QString customPlaceholderText() const { return m_customPlaceholderText; }
    QFont customPlaceholderFont() const { return m_customPlaceholderFont; }

signals:
    void zoomLevelChanged(int percent);
    void textEmptied();
    void scrollActivity();

protected:
    void paintEvent(QPaintEvent* e) override;
    void wheelEvent(QWheelEvent* e) override;
    void keyPressEvent(QKeyEvent* e) override;
    void contextMenuEvent(QContextMenuEvent* e) override;
    void changeEvent(QEvent* e) override;

private:
    void applyZoom();

    QFont m_baseFont;
    int m_zoomPercent = 100;
    bool m_wasEmpty = true;

    // Hint painted instead of Qt's native placeholder text (both editors)
    QString m_customPlaceholderText;
    QFont m_customPlaceholderFont;
};
