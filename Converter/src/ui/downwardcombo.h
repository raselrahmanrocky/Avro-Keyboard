// downwardcombo.h - QComboBox variant that always drops its popup list
// below the control and resets selection to the active item on open.
#pragma once

#include <QComboBox>
#include <QProxyStyle>
#include <QStyledItemDelegate>

class DownwardCombo : public QComboBox
{
    Q_OBJECT

public:
    explicit DownwardCombo(QWidget* parent = nullptr);

protected:
    void showPopup() override;
    void paintEvent(QPaintEvent* e) override;

private:
    class ComboItemDelegate;
};

// Call once during app startup to install the clean chevron-arrow
// QProxyStyle as the APPLICATION-LEVEL style (not per-widget).  This
// avoids the widget-local setStyle() that used to block Qt's dynamic
// QSS cascade for child QLineEdits inside editable combos.
void installComboArrowStyle();
