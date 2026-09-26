// downwardcombo.cpp - force the popup list to open below the combo box,
// and paint hover / selection backgrounds via a lightweight delegate.
#include "downwardcombo.h"

#include <QApplication>
#include <QAbstractItemView>
#include <QFontMetrics>
#include <QItemSelectionModel>
#include <QPainter>
#include <QPen>
#include <QScreen>
#include <QStyle>
#include <QStyleOption>

// ---------------------------------------------------------------------------
// ComboArrowStyle
// ---------------------------------------------------------------------------
// Draws a clean, antialiased chevron arrow in the drop-down button area.
// Uses QPalette::Text for color so it auto-adapts to light/dark themes.
class ComboArrowStyle : public QProxyStyle
{
public:
    using QProxyStyle::QProxyStyle;

    void drawPrimitive(PrimitiveElement pe, const QStyleOption* opt,
                       QPainter* p, const QWidget* w) const override
    {
        if (pe == PE_IndicatorArrowDown) {
            p->save();
            p->setRenderHint(QPainter::Antialiasing);
            const QColor color = opt->palette.color(QPalette::Text);
            p->setPen(QPen(color, 1.8, Qt::SolidLine,
                           Qt::RoundCap, Qt::RoundJoin));
            const QRect r = opt->rect;
            const int cx = r.center().x();
            const int cy = r.center().y();
            QPolygonF poly;
            poly << QPointF(cx - 4, cy - 2)
                 << QPointF(cx, cy + 2)
                 << QPointF(cx + 4, cy - 2);
            p->drawPolyline(poly);
            p->restore();
            return;
        }
        QProxyStyle::drawPrimitive(pe, opt, p, w);
    }

    // Defense-in-depth: also paint the chevron via drawComplexControl so
    // the arrow is drawn even on platforms where PE_IndicatorArrowDown is
    // not called (e.g. when QSS defines a ::drop-down subcontrol).
    void drawComplexControl(ComplexControl cc, const QStyleOptionComplex* opt,
                           QPainter* p, const QWidget* w) const override
    {
        if (cc == CC_ComboBox) {
            // Let the base class paint everything except the arrow area.
            QProxyStyle::drawComplexControl(cc, opt, p, w);
            // Now paint our chevron in the SC_ComboBoxArrow sub-control rect.
            const QStyleOptionComboBox* comboOpt =
                qstyleoption_cast<const QStyleOptionComboBox*>(opt);
            if (comboOpt) {
                const QRect arrowRect =
                    subControlRect(CC_ComboBox, opt, SC_ComboBoxArrow, w);
                if (!arrowRect.isNull()) {
                    p->save();
                    p->setRenderHint(QPainter::Antialiasing);
                    const QColor color = opt->palette.color(QPalette::Text);
                    p->setPen(QPen(color, 1.6, Qt::SolidLine,
                                   Qt::RoundCap, Qt::RoundJoin));
                    const int cx = arrowRect.center().x();
                    const int cy = arrowRect.center().y();
                    QPolygonF poly;
                    poly << QPointF(cx - 4, cy - 2)
                         << QPointF(cx, cy + 2)
                         << QPointF(cx + 4, cy - 2);
                    p->drawPolyline(poly);
                    p->restore();
                    return;  // skip the base-class arrow painting
                }
            }
            return;
        }
        QProxyStyle::drawComplexControl(cc, opt, p, w);
    }
};

// ---------------------------------------------------------------------------
// ComboItemDelegate
// ---------------------------------------------------------------------------
// Minimal delegate matching FontPicker's delegate behavior:
// Paints Accent color for Selected item and subtle AlternateBase for Hover.
class DownwardCombo::ComboItemDelegate : public QStyledItemDelegate
{
public:
    explicit ComboItemDelegate(QObject* parent = nullptr)
        : QStyledItemDelegate(parent)
    {
    }

    void paint(QPainter* painter, const QStyleOptionViewItem& opt,
               const QModelIndex& index) const override
    {
        painter->save();
        const QPalette& pal = opt.palette;
        const bool selected = opt.state & QStyle::State_Selected;
        const bool hovered = opt.state & QStyle::State_MouseOver;

        // Background: accent for selection, subtle tint for hover (mirrors FontPicker)
        QColor bg = pal.color(QPalette::Base);
        if (selected)
            bg = pal.color(QPalette::Highlight);
        else if (hovered)
            bg = pal.color(QPalette::AlternateBase);
        painter->fillRect(opt.rect, bg);

        const QColor textColor = selected ? pal.color(QPalette::HighlightedText)
                                          : pal.color(QPalette::Text);

        const QString display = index.data(Qt::DisplayRole).toString();
        const QFontMetrics fm(opt.font);
        const int vpad = 5;
        const QRect r = opt.rect.adjusted(8, vpad, -8, -vpad);
        const QString line =
            fm.elidedText(display, Qt::ElideRight, qMax(0, r.width()));
        const int baseline =
            r.top() + (r.height() - fm.height()) / 2 + fm.ascent();

        painter->setFont(opt.font);
        painter->setPen(textColor);
        painter->drawText(r.left(), baseline, line);

        painter->restore();
    }

    QSize sizeHint(const QStyleOptionViewItem& opt,
                   const QModelIndex& index) const override
    {
        const QFontMetrics fm(opt.font);
        const QString display = index.data(Qt::DisplayRole).toString();
        return QSize(fm.horizontalAdvance(display) + 32, fm.height() + 10);
    }
};

// ---------------------------------------------------------------------------
// DownwardCombo
// ---------------------------------------------------------------------------

DownwardCombo::DownwardCombo(QWidget* parent)
    : QComboBox(parent)
{
    // NOTE: ComboArrowStyle is installed globally via installComboArrowStyle()
    // so that the application QSS cascade reaches the child QLineEdit of
    // editable combos.  A per-widget setStyle() would cache the old theme
    // and block dynamic stylesheet updates.
    view()->setMouseTracking(true);
    view()->viewport()->setMouseTracking(true);
    view()->setItemDelegate(new ComboItemDelegate(view()));
}

void installComboArrowStyle()
{
    // Install once as the application-wide style.  ComboArrowStyle is a
    // QProxyStyle that only overrides PE_IndicatorArrowDown (the chevron
    // arrow in drop-down buttons), delegating everything else to the
    // platform default.  Setting it globally means every QComboBox gets
    // the clean arrow without any per-widget setStyle() that would break
    // the QSS cascade for child widgets like QLineEdit.
    static bool installed = false;
    if (installed)
        return;
    installed = true;
    qApp->setStyle(new ComboArrowStyle(qApp->style()));
}

void DownwardCombo::paintEvent(QPaintEvent* e)
{
    QComboBox::paintEvent(e);

    // Second defense layer: if the QProxyStyle arrow didn't fire on this
    // platform, paint the chevron ourselves in the rightmost 20 px of
    // the widget (the drop-down button area).
    if (!isEnabled())
        return;

    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    const QColor color = palette().color(QPalette::Text);
    p.setPen(QPen(color, 1.6, Qt::SolidLine,
                   Qt::RoundCap, Qt::RoundJoin));
    // Fixed right-side rectangle matching the drop-down button area.
    const int arrowW = 20;
    const QRect arrowRect(width() - arrowW, 0, arrowW, height());
    const int cx = arrowRect.center().x();
    const int cy = arrowRect.center().y();
    QPolygonF poly;
    poly << QPointF(cx - 4, cy - 2)
         << QPointF(cx, cy + 2)
         << QPointF(cx + 4, cy - 2);
    p.drawPolyline(poly);
}

void DownwardCombo::showPopup()
{
    QComboBox::showPopup();

    QWidget* v = view();
    if (!v)
        return;

    // 1. Popup reposition downward
    QWidget* popup = v->window();
    if (popup && popup != this) {
        QRect target = popup->geometry();
        target.moveTop(mapToGlobal(QPoint(0, height())).y());

        if (QScreen* scr = screen()) {
            const QRect avail = scr->availableGeometry();
            if (target.bottom() > avail.bottom())
                target.moveBottom(avail.bottom());
            if (target.top() < avail.top())
                target.moveTop(avail.top());
        }
        popup->move(target.topLeft());
    }

    // 2. Preselect & scroll to the currently active item (FontPicker-এর মতো)
    const int cur = currentIndex();
    if (cur >= 0 && model() && cur < model()->rowCount()) {
        auto* itemView = qobject_cast<QAbstractItemView*>(v);
        const QModelIndex idx = model()->index(cur, 0);
        if (idx.isValid() && itemView) {
            itemView->setCurrentIndex(idx);
            if (itemView->selectionModel()) {
                itemView->selectionModel()->setCurrentIndex(
                    idx, QItemSelectionModel::ClearAndSelect | QItemSelectionModel::Rows);
            }
            itemView->scrollTo(idx, QAbstractItemView::PositionAtCenter);
            itemView->viewport()->update();
        }
    }
}
