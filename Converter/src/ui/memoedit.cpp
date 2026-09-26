// memoedit.cpp - implementation of MemoEdit (zoom + context menu).
#include "memoedit.h"

#include <QAction>
#include <QContextMenuEvent>
#include <QKeyEvent>
#include <QMenu>
#include <QPainter>
#include <QShortcut>
#include <QTextOption>
#include <QWheelEvent>

namespace {
const int kMinZoom = 20;
const int kMaxZoom = 500;
const int kZoomStep = 10;
const int kUndoLimit = 15;
} // namespace

MemoEdit::MemoEdit(QWidget* parent)
    : QPlainTextEdit(parent)
    , m_baseFont(font())
{
    QTextOption opt = document()->defaultTextOption();
    opt.setAlignment(Qt::AlignJustify);
    document()->setDefaultTextOption(opt);

    auto* zoomInSc = new QShortcut(QKeySequence::ZoomIn, this);
    connect(zoomInSc, &QShortcut::activated, this, [this]() { zoomIn(); });
    auto* zoomOutSc = new QShortcut(QKeySequence::ZoomOut, this);
    connect(zoomOutSc, &QShortcut::activated, this, [this]() { zoomOut(); });
    auto* resetSc = new QShortcut(QKeySequence(QStringLiteral("Ctrl+0")), this);
    connect(resetSc, &QShortcut::activated, this, [this]() { resetZoom(); });

    connect(this, &QPlainTextEdit::textChanged, this, [this]() {
        if (document()->isEmpty()) {
            if (m_wasEmpty)
                return;
            m_wasEmpty = true;
            document()->setModified(false);
            emit textEmptied();
        } else {
            m_wasEmpty = false;
            if (document()->availableUndoSteps() > kUndoLimit)
                document()->clearUndoRedoStacks();
        }
        viewport()->update();
    });
}

void MemoEdit::setBaseFont(const QFont& f)
{
    m_baseFont = f;
    if (font() != f)
        QPlainTextEdit::setFont(f);
    applyZoom();
}

void MemoEdit::zoomIn(int steps)
{
    const int target = qMin(kMaxZoom, m_zoomPercent + kZoomStep * steps);
    if (target == m_zoomPercent)
        return;
    m_zoomPercent = target;
    applyZoom();
}

void MemoEdit::zoomOut(int steps)
{
    const int target = qMax(kMinZoom, m_zoomPercent - kZoomStep * steps);
    if (target == m_zoomPercent)
        return;
    m_zoomPercent = target;
    applyZoom();
}

void MemoEdit::resetZoom()
{
    if (m_zoomPercent == 100)
        return;
    m_zoomPercent = 100;
    applyZoom();
}

void MemoEdit::clear()
{
    QPlainTextEdit::clear();
    document()->clearUndoRedoStacks();
    document()->setModified(false);
    if (!m_wasEmpty) {
        m_wasEmpty = true;
        emit textEmptied();
    }
}

void MemoEdit::setCustomPlaceholder(const QString& text, const QFont& hintFont)
{
    m_customPlaceholderText = text;
    m_customPlaceholderFont = hintFont;
    viewport()->update();
}

void MemoEdit::paintEvent(QPaintEvent* e)
{
    QPlainTextEdit::paintEvent(e);

    if (document()->isEmpty() && !m_customPlaceholderText.isEmpty()) {
        QPainter p(viewport());
        p.setFont(m_customPlaceholderFont);
        p.setPen(palette().color(QPalette::PlaceholderText));
        const int margin = qRound(document()->documentMargin());
        const QRect r = viewport()->rect().adjusted(
            margin + 1, margin + 1, -margin - 1, -margin - 1);
        QTextOption opt = document()->defaultTextOption();
        p.drawText(r, Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap,
                   m_customPlaceholderText);
    }
}

void MemoEdit::applyZoom()
{
    const qreal basePt = m_baseFont.pointSizeF();
    if (basePt > 0) {
        const qreal targetPt = basePt * m_zoomPercent / 100.0;
        QFont f = m_baseFont;
        f.setPointSizeF(targetPt);
        if (font().pointSizeF() != targetPt || font().family() != f.family())
            QPlainTextEdit::setFont(f);
        if (document()) {
            QFont docFont = document()->defaultFont();
            if (docFont.pointSizeF() != targetPt || docFont.family() != f.family())
                document()->setDefaultFont(f);
        }
    } else if (m_baseFont.pixelSize() > 0) {
        const int targetPx = qRound(m_baseFont.pixelSize() * m_zoomPercent / 100.0);
        QFont f = m_baseFont;
        f.setPixelSize(targetPx);
        if (font().pixelSize() != targetPx || font().family() != f.family())
            QPlainTextEdit::setFont(f);
        if (document())
            document()->setDefaultFont(f);
    }
    emit zoomLevelChanged(m_zoomPercent);
}

void MemoEdit::keyPressEvent(QKeyEvent* e)
{
    if (e->modifiers() & Qt::ControlModifier) {
        switch (e->key()) {
        case Qt::Key_Plus:
        case Qt::Key_Equal:
            zoomIn();
            return;
        case Qt::Key_Minus:
            zoomOut();
            return;
        case Qt::Key_0:
            resetZoom();
            return;
        default:
            break;
        }
    }
    QPlainTextEdit::keyPressEvent(e);
}

void MemoEdit::wheelEvent(QWheelEvent* e)
{
    if (e->modifiers() & Qt::ControlModifier) {
        const int steps = e->angleDelta().y() / 120;
        if (steps > 0)
            zoomIn(steps);
        else if (steps < 0)
            zoomOut(-steps);
        e->accept();
        return;
    }
    emit scrollActivity();
    QPlainTextEdit::wheelEvent(e);
}

void MemoEdit::contextMenuEvent(QContextMenuEvent* e)
{
    QMenu menu(this);

    QAction* actCut = menu.addAction(tr("Cut"), this, [this]() { cut(); });
    actCut->setShortcut(QKeySequence::Cut);
    QAction* actCopy = menu.addAction(tr("Copy"), this, [this]() { copy(); });
    actCopy->setShortcut(QKeySequence::Copy);
    QAction* actPaste =
        menu.addAction(tr("Paste"), this, [this]() { paste(); });
    actPaste->setShortcut(QKeySequence::Paste);

    menu.addSeparator();

    QAction* actSelectAll = menu.addAction(
        tr("Select All"), this, [this]() { selectAll(); });
    actSelectAll->setShortcut(QKeySequence::SelectAll);
    QAction* actClear =
        menu.addAction(tr("Clear"), this, [this]() { clear(); });

    menu.addSeparator();

    QAction* zoomInAct =
        menu.addAction(tr("Zoom In"), this, [this]() { zoomIn(); });
    zoomInAct->setShortcut(QKeySequence::ZoomIn);
    QAction* zoomOutAct =
        menu.addAction(tr("Zoom Out"), this, [this]() { zoomOut(); });
    zoomOutAct->setShortcut(QKeySequence::ZoomOut);
    QAction* resetAct = menu.addAction(
        tr("Reset Zoom (100%)"), this, [this]() { resetZoom(); });

    const bool hasSelection = !textCursor().selectedText().isEmpty();
    const bool hasText = !toPlainText().isEmpty();
    actCut->setEnabled(hasSelection);
    actCopy->setEnabled(hasSelection);
    actSelectAll->setEnabled(hasText);
    actClear->setEnabled(hasText);
    zoomInAct->setEnabled(m_zoomPercent < kMaxZoom);
    zoomOutAct->setEnabled(m_zoomPercent > kMinZoom);
    resetAct->setEnabled(m_zoomPercent != 100);

    menu.exec(e->globalPos());
}

void MemoEdit::changeEvent(QEvent* e)
{
    QPlainTextEdit::changeEvent(e);

    // When the application stylesheet or palette changes (theme switch),
    // Qt's styling engine resets the widget font and document()->defaultFont()
    // back to style defaults, discarding the user's chosen font family
    // (e.g. SutonnyMJ on m_memo2) and zoom level.  Reassert m_baseFont
    // immediately so the font family and zoomed size survive the re-polish.
    // applyZoom() is cheap (one QFont comparison + setFont) and avoids a
    // full document relayout that would freeze the GUI on large texts.
    if (e->type() == QEvent::StyleChange || e->type() == QEvent::FontChange) {
        applyZoom();
    } else if (e->type() == QEvent::PaletteChange) {
        // PaletteChange only alters widget colors � the document font and
        // its layout are untouched.  A viewport repaint is sufficient.
        viewport()->update();
    }
}
