// fontpicker.cpp - implementation of the searchable font picker.
//
// Feature map
// -----------
// * Clean-English name pipeline (englishFamilyNames):
//     QFontDatabase::families() -> pure-ASCII pass-through, best-effort
//     reverse-Bijoy decode for legacy glyph names, QFontInfo resolution,
//     small localized-name map, strict ASCII-only filter + case-insensitive
//     dedup.  No non-English glyph ever reaches the list.
// * Natural ordering + pinned group (populateFonts): QCollator numeric sort;
//     popular Bengali fonts (ANSI / MJ / Kalpurush / Siyam Rupali ...) are
//     pinned to the top, separated by a divider drawn by the delegate.
// * Type-to-search: QCompleter (PopupCompletion) driven exclusively by
//     QLineEdit::textEdited so programmatic updates never re-trigger the
//     filter.  A custom QStyledItemDelegate highlights the typed substring
//     in the theme accent and renders every row in the standard UI font.
// * Live preview: arrow keys / hover emit fontPreviewed() (temporary),
//     Enter / click commits fontPicked(), Escape / popup-close without a
//     commit emits fontPreviewCanceled() so MainWindow can revert.
#include "fontpicker.h"

#include <QAbstractItemView>
#include <QAbstractProxyModel>
#include <QCompleter>
#include <QCollator>
#include <QFocusEvent>
#include <QFontDatabase>
#include <QFontMetrics>
#include <QHash>
#include <QKeyEvent>
#include <QLineEdit>
#include <QPainter>
#include <QSet>
#include <QStringListModel>
#include <QStyle>
#include <QStyledItemDelegate>
#include <QTimer>

namespace detail {

// ---------------------------------------------------------------------------
// FontHighlightDelegate
// ---------------------------------------------------------------------------
// Paints completer-popup rows:
//   * background/text honour the theme palette (accent for selection),
//   * every row renders in the standard application UI font (uniform,
//     clean - no per-family font faces),
//   * the typed query substring is drawn bold in the accent colour,
//   * a divider separates the pinned Bengali group from the rest (only
//     shown while no filter is active, so filtering never looks broken).
class FontHighlightDelegate : public QStyledItemDelegate
{
public:
    explicit FontHighlightDelegate(QObject* parent = nullptr)
        : QStyledItemDelegate(parent)
    {
    }

    void setHighlightText(const QString& t) { m_highlight = t; }
    void setPinnedCount(int n) { m_pinned = n; }

    void paint(QPainter* painter, const QStyleOptionViewItem& opt,
               const QModelIndex& index) const override
    {
        painter->save();
        const QPalette& pal = opt.palette;
        const bool selected = opt.state & QStyle::State_Selected;
        const bool hovered = opt.state & QStyle::State_MouseOver;

        // Background: accent for selection, subtle tint for hover, else the
        // popup base colour (mirrors the stylesheet's item rules).
        QColor bg = pal.color(QPalette::Base);
        if (selected)
            bg = pal.color(QPalette::Highlight);
        else if (hovered)
            bg = pal.color(QPalette::AlternateBase);
        painter->fillRect(opt.rect, bg);

        const QColor textColor = selected ? pal.color(QPalette::HighlightedText)
                                          : pal.color(QPalette::Text);
        const QColor accent = pal.color(QPalette::Highlight);

        // No QTextDocument per row: direct QPainter::drawText with
        // QFontMetrics keeps every repaint allocation-free.  The row font
        // is the standard application UI font for every row.
        const QString display = index.data(Qt::DisplayRole).toString();
        const QFontMetrics fm(opt.font);
        const int vpad = 5;  // 5px top/bottom padding, like the item QSS
        const QRect r = opt.rect.adjusted(8, vpad, -8, -vpad);
        // Elide to the row width (the old QTextDocument wrapped and clipped
        // to the same single-line rect).
        const QString line =
            fm.elidedText(display, Qt::ElideRight, qMax(0, r.width()));
        const int baseline =
            r.top() + (r.height() - fm.height()) / 2 + fm.ascent();

        if (m_highlight.isEmpty()) {
            painter->setFont(opt.font);
            painter->setPen(textColor);
            painter->drawText(r.left(), baseline, line);
        } else {
            // Bold-accent highlight runs, normal text everywhere else.
            // Match colour falls back to the text colour on a selected row
            // (accent on accent would be invisible) - mirrors the old HTML
            // delegate.
            const QColor matchColor = selected ? textColor : accent;
            QFont boldFont = opt.font;
            boldFont.setBold(true);
            const QFontMetrics boldFm(boldFont);
            const QString lowerLine = line.toLower();
            const QString lowerQ = m_highlight.toLower();

            int x = r.left();
            int pos = 0;
            int found = lowerLine.indexOf(lowerQ, pos);
            while (found >= 0) {
                const QString pre = line.mid(pos, found - pos);
                if (!pre.isEmpty()) {
                    painter->setFont(opt.font);
                    painter->setPen(textColor);
                    painter->drawText(x, baseline, pre);
                    x += fm.horizontalAdvance(pre);
                }
                const QString match = line.mid(found, m_highlight.size());
                painter->setFont(boldFont);
                painter->setPen(matchColor);
                painter->drawText(x, baseline, match);
                x += boldFm.horizontalAdvance(match);
                pos = found + m_highlight.size();
                found = lowerLine.indexOf(lowerQ, pos);
            }
            const QString rest = line.mid(pos);
            if (!rest.isEmpty()) {
                painter->setFont(opt.font);
                painter->setPen(textColor);
                painter->drawText(x, baseline, rest);
            }
        }
        painter->restore();

        // Divider under the last pinned row - only when the list is
        // unfiltered so the group boundary stays meaningful.  Works for both
        // the combo's own view (model is the source model directly) and the
        // completer popup (model is a completion proxy).
        if (m_pinned > 0 && m_highlight.isEmpty()) {
            QModelIndex src = index;
            if (const auto* proxy =
                    qobject_cast<const QAbstractProxyModel*>(index.model()))
                src = proxy->mapToSource(index);
            if (src.isValid() && src.row() == m_pinned - 1) {
                painter->save();
                painter->setPen(QPen(pal.color(QPalette::Mid), 1));
                painter->drawLine(opt.rect.left() + 8, opt.rect.bottom() - 1,
                                  opt.rect.right() - 8, opt.rect.bottom() - 1);
                painter->restore();
            }
        }
    }

    QSize sizeHint(const QStyleOptionViewItem& opt,
                   const QModelIndex& index) const override
    {
        // Uniform metrics from the standard application UI font.
        const QFontMetrics fm(opt.font);
        const QString display = index.data(Qt::DisplayRole).toString();
        return QSize(fm.horizontalAdvance(display) + 32, fm.height() + 10);
    }

private:
    QString m_highlight;
    int m_pinned = 0;
};

}  // namespace detail

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

FontPicker::FontPicker(QWidget* parent)
    : DownwardCombo(parent)
{
    setEditable(true);
    setInsertPolicy(QComboBox::NoInsert);
    setMaxVisibleItems(14);

    // Focus is mouse-only (ClickFocus).  With the default StrongFocus, Qt's
    // focus engine automatically moves keyboard focus to the next focusable
    // widget in tab order when a focused control is disabled - and the
    // convert buttons sit right next to this picker.  So clicking
    // "Unicode to ANSI" disabled the button and dumped focus + a full-text
    // selection + the orange focus border into the search box.  ClickFocus
    // keeps the widget clickable/typeable, but Tab and programmatic focus
    // handoffs skip it.  MainWindow::startConversion also calls
    // clearSearchFocus() as a belt-and-braces cleanup.
    setFocusPolicy(Qt::ClickFocus);
    lineEdit()->setFocusPolicy(Qt::ClickFocus);
    lineEdit()->setAutoFillBackground(false);

    // One shared source model for both the combo and the completer.
    // QStringListModel: one QStringList under the hood instead of hundreds
    // of QStandardItem heap objects - the per-font allocation cost for the
    // whole list drops to a few bytes per row.
    m_model = new QStringListModel(this);
    setModel(m_model);

    // Type-to-search via QCompleter in PopupCompletion mode: the popup
    // lists matching fonts as the user types, but the edit box text is
    // never rewritten and keyboard focus stays in the line edit (no
    // focus-out, no auto-complete - unlike InlineCompletion).
    m_completer = new QCompleter(this);
    m_completer->setModel(m_model);
    m_completer->setCaseSensitivity(Qt::CaseInsensitive);
    m_completer->setCompletionMode(QCompleter::PopupCompletion);
    m_completer->setFilterMode(Qt::MatchContains);
    m_completer->setMaxVisibleItems(14);
    // Name the completer popup so the app stylesheet can style it with the
    // same item height/padding as the normal drop-down list (a completer
    // popup is a separate top-level window, so the generic
    // "QComboBox QAbstractItemView" rule never reaches it).
    m_completer->popup()->setObjectName(QStringLiteral("CbFontPickerPopup"));
    // Attach the completer to the combo box so it owns a fully set-up
    // popup; we still steer the popup ourselves from the event filter
    // below (typing opens it, arrows step it, Enter commits).
    setCompleter(m_completer);

    // Custom delegate: substring highlight + pinned-group divider, with all
    // rows in the standard UI font.  It replaces the stylesheet's item
    // painting, so selection / hover colours come from the theme palette
    // (set by MainWindow).  Installed on BOTH the type-to-search popup and
    // the combo's own
    // arrow-dropdown (QComboBox::view()), so the pinned group + divider look
    // consistent everywhere.
    m_delegate = new detail::FontHighlightDelegate(m_completer->popup());
    m_completer->popup()->setItemDelegate(m_delegate);
    view()->setItemDelegate(m_delegate);

    // Hover tracking: lets us emit fontPreviewed() while the mouse moves
    // over the list without a click (QAbstractItemView::entered needs it).
    m_completer->popup()->setMouseTracking(true);
    m_completer->popup()->viewport()->setMouseTracking(true);

    // Bug 2 guard: the line edit drives the completer itself on every text
    // edit (QLineEdit::connectCompleter), so setCompletionPrefix() is called
    // again AFTER our textEdited handler runs.  Each call re-filters the
    // completion model, and the resulting modelReset wipes the popup's
    // current index back to -1 - silently undoing the preselect below.
    // Re-apply the preselect on the next event-loop turn, after the filter
    // has settled.  Zero-timer fires before the next paint, so there is no
    // visible flicker; arrow navigation never re-fires it (no text edit).
    connect(m_completer->completionModel(), &QAbstractItemModel::modelReset,
            this, [this]() {
                QTimer::singleShot(0, this, [this]() {
                    if (!m_completer || m_suppressFilter)
                        return;
                    if (m_completer->popup()->isVisible())
                        preselectActiveFont();
                });
            });

    // Watch the edit box so Up/Down/Enter navigate the filtered completer
    // popup instead of being grabbed by the combo's own drop-down, and the
    // popup itself so an abandoned preview is cancelled when it closes.
    lineEdit()->installEventFilter(this);
    m_completer->popup()->installEventFilter(this);

    populateFonts();

    connect(m_completer, QOverload<const QString&>::of(&QCompleter::activated),
            this, &FontPicker::onCompleterActivated);
    connect(this, QOverload<int>::of(&QComboBox::activated),
            this, &FontPicker::onActivated);

    // Hovering an item previews it live (no commit).
    connect(m_completer->popup(), &QAbstractItemView::entered, this,
            [this](const QModelIndex& idx) {
                const QString fam = idx.data(Qt::DisplayRole).toString();
                if (fam.isEmpty() || fam == m_lastPreviewed)
                    return;
                m_lastPreviewed = fam;
                m_previewActive = true;
                emit fontPreviewed(fam);
            });

    // Drive the completer from USER typing only.  textEdited (not
    // textChanged) fires exclusively on manual edits, so programmatic
    // updates - restoring the typed query after arrow navigation, or
    // setCurrentText() when a font is committed - never re-trigger the
    // filter.  This is the key that keeps arrow browsing from shrinking
    // the list.  The query also drives the delegate's substring highlight.
    connect(lineEdit(), &QLineEdit::textEdited, this, [this](const QString& t) {
        if (m_suppressFilter)
            return;
        m_highlightText = t;
        m_delegate->setHighlightText(t);
        m_completer->setCompletionPrefix(t);
        if (t.isEmpty() || m_completer->completionCount() == 0) {
            m_completer->popup()->hide();
        } else {
            m_completer->complete();
            // Bug 2: select + scroll to the currently active font instead of
            // always starting at row 0.  Called on EVERY completion update:
            // the completer resets the popup's current index on each
            // re-completion (verified: it returns to -1 on the 2nd/3rd
            // keystroke), so gating on the hidden->visible transition alone
            // leaves the highlight stuck off-row.  Re-running is harmless
            // while typing (arrow navigation never edits the text, so it
            // never re-fires here).
            preselectActiveFont();
        }
        m_completer->popup()->viewport()->update();
    });
    // NOTE: no explicit returnPressed connect here - Return/Enter inside the
    // edit box is handled by handleNavKey() (event filter), which commits the
    // COMPLETER's highlighted row exactly once and consumes the event.  When
    // the filter popup is closed, QComboBox's own Return handling takes over
    // (activates its current index), which keeps commits single.
}

// ---------------------------------------------------------------------------
// Model population
// ---------------------------------------------------------------------------

void FontPicker::populateFonts()
{
    // Clean-English, deduplicated names (see englishFamilyNames).
    m_allFonts = englishFamilyNames();

    // Natural, case-insensitive ordering ("V2" before "V10").
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);

    // Split into the pinned "popular Bengali fonts" group and the rest,
    // sorting each group with the collator; pinned fonts come first and a
    // divider (drawn by the delegate) separates the two groups.
    QStringList pinned;
    QStringList rest;
    pinned.reserve(m_allFonts.size());
    for (const QString& fam : m_allFonts)
        (isPinnedFont(fam) ? pinned : rest) << fam;
    auto byCollator = [&collator](const QString& a, const QString& b) {
        return collator.compare(a, b) < 0;
    };
    std::sort(pinned.begin(), pinned.end(), byCollator);
    std::sort(rest.begin(), rest.end(), byCollator);
    m_allFonts = pinned + rest;
    m_pinnedCount = pinned.size();

    // One lightweight assignment: QStringListModel stores a single
    // QStringList (implicitly shared with m_allFonts), so no per-row
    // allocation happens at all.  Rows carry only DisplayRole - the
    // delegate renders everything in the standard UI font, so no
    // Qt::FontRole is needed.
    m_model->setStringList(m_allFonts);

    if (m_delegate)
        m_delegate->setPinnedCount(m_pinnedCount);
}

namespace {
// True when every character is Latin/ASCII (U+0000..U+007F).
bool isPureAscii(const QString& s)
{
    for (const QChar c : s)
        if (c.unicode() > 0x7F)
            return false;
    return true;
}
}  // namespace

namespace {
// Enumerating the font collection costs a few hundred milliseconds on the
// first call and the answer cannot change while the process runs, except when
// loadBundledFonts() registers bundled faces - that path invalidates the
// cache.  Shared by every picker (toolbar and Settings dialog) so the walk
// happens once per process instead of once per widget.
QStringList& familyNameCache()
{
    static QStringList cache;
    return cache;
}
}  // namespace

const QStringList& FontPicker::englishFamilyNames()
{
    QStringList& cache = familyNameCache();
    if (cache.isEmpty())
        cache = enumerateEnglishFamilyNames();
    return cache;
}

void FontPicker::invalidateFamilyCache()
{
    familyNameCache().clear();
}

QStringList FontPicker::enumerateEnglishFamilyNames()
{
    // QFontDatabase::families() is the Qt-blessed way to enumerate every
    // font Windows knows about - it wraps EnumFontFamiliesEx internally,
    // so no platform API is needed here.  The returned names are usually
    // already the Latin face names, but two kinds of exceptions exist:
    //   a) fonts registered under a localized (Bengali) spelling (Vrinda,
    //      Siyam Rupali, ...) depending on the system locale, and
    //   b) legacy Bijoy ANSI fonts whose registered name is the raw
    //      Bijoy-keyboard byte string interpreted as Bengali glyphs
    //      ("\u099D\u0982\u09A1\u09B9\u09B9\u09CD..." = "Sutonn...").
    // Resolution order per name:
    //   1. pure ASCII -> keep;
    //   2. reverse-Bijoy decode, accepted only when it yields a real
    //      registered family or a known legacy family name;
    //   3. known localized->English map (no QFont/QFontInfo allocation);
    //   4. drop (strict ASCII-only policy - no non-English glyphs ever).
    //   The English twin of a localized registration is almost always
    //   registered separately, so nothing usable is lost.
    static const QHash<QString, QString> kLocalizedToEnglish{
        {QStringLiteral("\u09AC\u09C3\u09A8\u09CD\u09A6\u09BE"),
         QStringLiteral("Vrinda")},  // "বৃন্দা"
        {QStringLiteral("\u0995\u09B2\u09AA\u09C1\u09B0\u09C1\u09B7"),
         QStringLiteral("Kalpurush")},  // "কলপুরুষ"
        {QStringLiteral("\u09B8\u09BF\u09AF\u09BC\u09BE\u09AE \u09B0\u09C1\u09AA\u09BE\u09B2\u09BF"),
         QStringLiteral("Siyam Rupali")},  // "সিয়াম রুপালি"
        {QStringLiteral("\u09AE\u09BF\u09A4\u09CD\u09B0\u09BE"),
         QStringLiteral("Mitra")},  // "মিত্রা"
        {QStringLiteral("\u09AC\u09BE\u0982\u09B2\u09BE"),
         QStringLiteral("Bangla")},  // "বাংলা"
    };

    const QStringList registered = QFontDatabase::families();
    QStringList result;
    result.reserve(registered.size());
    QSet<QString> seen;
    for (const QString& fam : registered) {
        QString english;
        if (isPureAscii(fam)) {
            english = fam;
        } else {
            // 2) Best-effort reverse-Bijoy decode.  Accept the result only
            // when it is a pure-Latin name that either matches a registered
            // family (the clean twin of the garbled registration) or is a
            // known legacy family - a wrong decode is never trusted.
            const QString decoded = bijoyToLatin(fam);
            if (isPureAscii(decoded)
                && (registered.contains(decoded, Qt::CaseInsensitive)
                    || isLegacyBijoyFont(decoded))) {
                english = decoded;
            } else {
                // 3) Known localized->English map (no QFont/QFontInfo
                // allocation — those load font tables into DirectWrite
                // glyph caches and spike RAM for hundreds of families).
                const auto it = kLocalizedToEnglish.constFind(fam);
                if (it != kLocalizedToEnglish.cend()) {
                    english = it.value();
                }
                // 4) No Latin name found: drop so the list stays strictly
                // English (the English twin is almost always registered
                // too, so nothing usable is lost).
            }
        }
        if (english.isEmpty() || !isPureAscii(english))
            continue;
        // De-duplicate case-insensitively: several localized spellings can
        // resolve to the same Latin family.
        const QString key = english.toLower();
        if (seen.contains(key))
            continue;
        seen.insert(key);
        result << english;
    }
    return result;
}

QString FontPicker::bijoyToLatin(const QString& name)
{
    // Legacy Bijoy fonts place a Bengali glyph at every ASCII key position,
    // so a legacy family name is just the Latin name re-typed through the
    // fixed Bijoy keyboard.  Decoding maps each Bengali glyph back to the
    // key that produced it.  The table below is the verified subset used by
    // the legacy font families - anchors confirmed by decoding
    // "Sutonny..." -> "\u099D\u0982\u09A1\u09B9\u09B9\u09CD" (\u099D=S,
    // \u0982=u, \u09A1\u09BC=t, \u09B9=o, \u09B9\u09CD=n) and the
    // kivabe.com Bijoy typing guide.  It is deliberately small: unmapped
    // characters stay non-ASCII, so the strict filter in englishFamilyNames
    // drops the entry rather than ever showing garbled text.
    static const QHash<QString, QString> kMap{
        // Vowels / kars
        {QStringLiteral("\u0985"), QStringLiteral("a")},  // অ
        {QStringLiteral("\u0986"), QStringLiteral("a")},  // আ
        {QStringLiteral("\u09BE"), QStringLiteral("a")},  // া
        {QStringLiteral("\u0987"), QStringLiteral("i")},  // ই
        {QStringLiteral("\u0988"), QStringLiteral("i")},  // ঈ
        {QStringLiteral("\u09BF"), QStringLiteral("i")},  // ি
        {QStringLiteral("\u09C0"), QStringLiteral("i")},  // ী
        {QStringLiteral("\u098F"), QStringLiteral("e")},  // এ
        {QStringLiteral("\u09C7"), QStringLiteral("e")},  // ে
        {QStringLiteral("\u0989"), QStringLiteral("u")},  // উ
        {QStringLiteral("\u09C1"), QStringLiteral("u")},  // ু
        {QStringLiteral("\u0993"), QStringLiteral("o")},  // ও
        {QStringLiteral("\u09CB"), QStringLiteral("o")},  // ো
        {QStringLiteral("\u0982"), QStringLiteral("u")},  // ং (anushar)
        {QStringLiteral("\u0981"), QStringLiteral("~")},  // ঁ (chandrabindu)
        {QStringLiteral("\u0983"), QStringLiteral(":")},  // ঃ (bisharga)
        // Consonants
        {QStringLiteral("\u0995"), QStringLiteral("k")},  // ক
        {QStringLiteral("\u0996"), QStringLiteral("K")},  // খ
        {QStringLiteral("\u0997"), QStringLiteral("g")},  // গ
        {QStringLiteral("\u0998"), QStringLiteral("G")},  // ঘ
        {QStringLiteral("\u0999"), QStringLiteral("q")},  // ঙ
        {QStringLiteral("\u099A"), QStringLiteral("c")},  // চ
        {QStringLiteral("\u099B"), QStringLiteral("C")},  // ছ
        {QStringLiteral("\u099C"), QStringLiteral("j")},  // জ
        {QStringLiteral("\u099D"), QStringLiteral("S")},  // ঝ
        {QStringLiteral("\u099E"), QStringLiteral("O")},  // ঞ
        {QStringLiteral("\u09A1\u09BC"), QStringLiteral("t")},  // ড়
        {QStringLiteral("\u09A8"), QStringLiteral("n")},  // ন
        {QStringLiteral("\u09AA"), QStringLiteral("p")},  // প
        {QStringLiteral("\u09AB"), QStringLiteral("f")},  // ফ
        {QStringLiteral("\u09AC"), QStringLiteral("b")},  // ব
        {QStringLiteral("\u09AD"), QStringLiteral("v")},  // ভ
        {QStringLiteral("\u09AE"), QStringLiteral("m")},  // ম
        {QStringLiteral("\u09AF"), QStringLiteral("y")},  // য
        {QStringLiteral("\u09B0"), QStringLiteral("r")},  // র
        {QStringLiteral("\u09B2"), QStringLiteral("l")},  // ল
        {QStringLiteral("\u09B8"), QStringLiteral("s")},  // স
        {QStringLiteral("\u09B9"), QStringLiteral("o")},  // হ
        // হ্ - the legacy 'n' key produces the হ glyph with a virama
        {QStringLiteral("\u09B9\u09CD"), QStringLiteral("n")},
        // Virama itself (standalone) is dropped.
        {QStringLiteral("\u09CD"), QString()},  // ্
    };

    QString out;
    out.reserve(name.size());
    int i = 0;
    while (i < name.size()) {
        // Two-code-unit digraphs first: ড় / হ্
        if (i + 1 < name.size()) {
            const QString two = name.mid(i, 2);
            const auto it2 = kMap.constFind(two);
            if (it2 != kMap.cend()) {
                out += it2.value();
                i += 2;
                continue;
            }
        }
        const QChar c = name.at(i);
        const auto it = kMap.constFind(QString(c));
        if (it != kMap.cend())
            out += it.value();
        else
            out += c;  // unmapped: stays non-ASCII -> dropped downstream
        ++i;
    }
    return out;
}

bool FontPicker::isLegacyBijoyFont(const QString& name)
{
    // Legacy Bijoy ANSI fonts (SutonnyMJ, BijoyMJ, TonnyBanglaMJ, RinkiyMJ,
    // Kalpurush ANSI, Siyam Rupali ANSI, ...) store Bengali glyphs at the
    // ASCII code points, so their cmap maps 'A'..'z' to Bengali SHAPES.
    // The clean English name rendered in such a font therefore displays as
    // garbled Bengali.  There is no reliable automatic discriminator (the
    // cmap glyph IDs, glyph names and OS/2 metrics are indistinguishable
    // from normal fonts - verified against the installed font files), so
    // detection is a curated pass over the finite legacy ecosystem:
    //   1. "ANSI" in the family name (Kalpurush ANSI, Kalpurush ANSI V2,
    //      Siyam Rupali ANSI, Li Shadhinata 2.0 ANSI V1/V2, Munir ANSI, ...)
    //   2. Classic legacy family suffixes (MJ / SreeMJ / SushreeMJ / OMR)
    //   3. Known legacy family roots.
    // No longer gates any row FontRole (the list renders in the standard
    // UI font).  Still used by englishFamilyNames() to accept the
    // reverse-Bijoy decode of a garbled registered name as a real family.
    // Over-classifying is harmless (the decoded name is still a registered
    // family); under-classifying would drop the legacy font from the list,
    // so err on the side of matching.
    const QString n = name.toLower();
    if (n.contains(QLatin1String("ansi")))
        return true;
    static const QStringList kLegacySuffixes{
        QStringLiteral("mj"),       // SutonnyMJ, BijoyMJ, TonnyBanglaMJ ...
        QStringLiteral("sreemj"),   // RinkiySreeMJ, RabeyaSreeMJ ...
        QStringLiteral("sushreemj"),
        QStringLiteral("omj"),      // SutonnyOMJ, SutonnySushreeOMJ, RaselOMJ ...
        QStringLiteral("omr"),      // NesarulOMR
        QStringLiteral("nt43"),     // Soumili-NT43
    };
    for (const QString& suf : kLegacySuffixes)
        if (n.endsWith(suf))
            return true;
    static const QStringList kLegacyRoots{
        QStringLiteral("sutonny"),  QStringLiteral("bijoy"),
        QStringLiteral("tonny"),    QStringLiteral("rinkiy"),
        QStringLiteral("khooai"),   QStringLiteral("sumeshwari"),
        QStringLiteral("jajadi"),   QStringLiteral("iraboti"),
        QStringLiteral("dholeshwari"), QStringLiteral("buriganga"),
        QStringLiteral("matamuhuri"), QStringLiteral("muhuri"),
        QStringLiteral("tangon"),   QStringLiteral("sonkho"),
        QStringLiteral("urmee"),    QStringLiteral("chandrabati"),
        QStringLiteral("ganga"),    QStringLiteral("parash"),
        QStringLiteral("rabeya"),   QStringLiteral("nesarul"),
        QStringLiteral("rasel"),    QStringLiteral("dhakarchithi"),
        QStringLiteral("soumili"),  QStringLiteral("samit"),
        QStringLiteral("banglapedia"), QStringLiteral("adarshalipi"),
        QStringLiteral("satyajit"), QStringLiteral("prothoma"),
        QStringLiteral("bd pratidin"), QStringLiteral("stm-"),
    };
    for (const QString& root : kLegacyRoots)
        if (n.contains(root))
            return true;
    return false;
}

bool FontPicker::isPinnedFont(const QString& name)
{
    // The popular Bengali group pinned to the top of the list.  Matches the
    // families the conversion workflow actually uses (the Delphi app ships
    // exactly this set as its ANSI/Unicode fonts).
    const QString n = name.toLower();
    static const QStringList kPinnedMarkers{
        QStringLiteral("ansi"),     QStringLiteral("mj"),
        QStringLiteral("omj"),      QStringLiteral("kalpurush"),
        QStringLiteral("siyam rupali"), QStringLiteral("vrinda"),
        QStringLiteral("sutonny"),  QStringLiteral("nirmala"),
        QStringLiteral("bornomala"),
    };
    for (const QString& marker : kPinnedMarkers)
        if (n.contains(marker))
            return true;
    return false;
}

// ---------------------------------------------------------------------------
// Selection / commit
// ---------------------------------------------------------------------------

void FontPicker::clearSearchFocus()
{
    // Used by MainWindow after a conversion: the search box must never hold
    // focus or a text selection when the user is not actively typing in it.
    // deselect() alone is not enough - the widget would still show the
    // orange focus border - so also clear focus.  Only act when the line
    // edit actually has focus/selection to avoid pointless focus churn.
    QLineEdit* le = lineEdit();
    if (!le)
        return;
    le->deselect();
    if (le->hasFocus())
        le->clearFocus();
}

void FontPicker::setActiveFont(const QString& f)
{
    if (f.isEmpty())
        return;
    m_activeFont = f;
    setEditTextSuppressed(f);
    // Note: the combo keeps the application's UI font so the picked font
    // name stays readable in the edit box; the font itself is applied to
    // the ANSI memo (see MainWindow::onFontPicked).
}

void FontPicker::setEditTextSuppressed(const QString& text)
{
    // Put text into the edit box without triggering the type-to-search
    // filter (so a picked font does not re-open the popup as a filter).
    m_suppressFilter = true;
    QSignalBlocker b(this);
    setCurrentText(text);
    m_completer->popup()->hide();
    m_suppressFilter = false;
}

void FontPicker::onCompleterActivated(const QString& text)
{
    if (text.isEmpty())
        return;
    // Commit: end any pending preview FIRST so the popup's Hide event
    // (fired by setEditTextSuppressed) does not emit a spurious cancel.
    m_previewActive = false;
    m_lastPreviewed.clear();
    m_activeFont = text;
    setEditTextSuppressed(text);
    emit fontPicked(text);
}

void FontPicker::onActivated(int index)
{
    const QString text = itemText(index);
    if (text.isEmpty())
        return;
    m_previewActive = false;
    m_lastPreviewed.clear();
    m_activeFont = text;
    setEditTextSuppressed(text);
    emit fontPicked(text);
}

// ---------------------------------------------------------------------------
// Live preview
// ---------------------------------------------------------------------------

void FontPicker::emitCurrentPreview()
{
    if (!m_completer || !m_completer->popup()->isVisible())
        return;
    const QString fam = m_completer->currentCompletion();
    if (fam.isEmpty() || fam == m_lastPreviewed)
        return;
    m_lastPreviewed = fam;
    m_previewActive = true;
    emit fontPreviewed(fam);
}

void FontPicker::cancelPreviewIfActive()
{
    if (!m_previewActive)
        return;
    m_previewActive = false;
    m_lastPreviewed.clear();
    emit fontPreviewCanceled();
}

QString FontPicker::highlightedFontName() const
{
    if (!m_completer)
        return QString();
    QAbstractItemView* popup = m_completer->popup();
    const QAbstractItemModel* pm = popup->model();
    if (!pm || pm->rowCount() == 0)
        return QString();
    QModelIndex cur = popup->currentIndex();
    if (!cur.isValid())
        cur = pm->index(0, 0);  // graceful fallback: first visible row
    return cur.data(Qt::DisplayRole).toString();
}

void FontPicker::preselectActiveFont()
{
    // Type-to-search popup: when it opens, highlight + scroll to the
    // currently active font (if it is in the filtered results) instead of
    // always starting at row 0.  The user's typed query is preserved -
    // setCurrentRow can make QComboBox rewrite the edit text, so restore it.
    if (!m_completer || m_activeFont.isEmpty())
        return;
    QAbstractItemView* popup = m_completer->popup();
    if (!popup->isVisible())
        return;
    const QAbstractItemModel* pm = popup->model();
    if (!pm)
        return;
    const QString typed = lineEdit() ? lineEdit()->text() : QString();
    const int rows = pm->rowCount();
    for (int r = 0; r < rows; ++r) {
        const QModelIndex idx = pm->index(r, 0);
        const QString rowText = idx.data(Qt::DisplayRole).toString();
        if (rowText.compare(m_activeFont, Qt::CaseInsensitive) != 0)
            continue;
        m_suppressFilter = true;  // stop the combo from re-filtering
        m_completer->setCurrentRow(r);
        popup->setCurrentIndex(idx);
        if (popup->selectionModel())
            popup->selectionModel()->setCurrentIndex(
                idx, QItemSelectionModel::ClearAndSelect
                         | QItemSelectionModel::Rows);
        popup->scrollTo(idx, QAbstractItemView::PositionAtCenter);
        if (lineEdit() && lineEdit()->text() != typed)
            lineEdit()->setText(typed);  // keep the user's query intact
        m_suppressFilter = false;
        // Repaint now: a stale mouse-hover position must never override the
        // freshly selected active font (selected rows paint on top of hover
        // in the delegate, and this update clears any stale hover state).
        popup->viewport()->update();
        break;
    }
}

void FontPicker::preselectActiveFontInComboView()
{
    // Combo's own arrow-dropdown: same idea - select + scroll to the active
    // font so the user always sees where they currently are in the list.
    if (m_activeFont.isEmpty())
        return;
    QAbstractItemView* v = view();
    if (!v)
        return;
    const QAbstractItemModel* m = v->model();
    if (!m)
        return;
    const int rows = m->rowCount();
    for (int r = 0; r < rows; ++r) {
        const QModelIndex idx = m->index(r, 0);
        if (idx.data(Qt::DisplayRole)
                .toString()
                .compare(m_activeFont, Qt::CaseInsensitive) != 0)
            continue;
        v->setCurrentIndex(idx);
        if (v->selectionModel())
            v->selectionModel()->setCurrentIndex(
                idx, QItemSelectionModel::ClearAndSelect
                         | QItemSelectionModel::Rows);
        v->scrollTo(idx, QAbstractItemView::PositionAtCenter);
        break;
    }
}

void FontPicker::showPopup()
{
    DownwardCombo::showPopup();  // keeps the list dropping downward
    preselectActiveFontInComboView();
}

// ---------------------------------------------------------------------------
// Keyboard / event handling
// ---------------------------------------------------------------------------

bool FontPicker::eventFilter(QObject* watched, QEvent* event)
{
    // Intercept arrow/Enter keys on the line edit BEFORE the combo and the
    // completer's own key handling get them, and navigate the FILTERED
    // completer popup.  The base QComboBox would otherwise open its own
    // (unfiltered) drop-down and rewrite the edit text.
    // Defensive: if focus ever lands on the edit box without a mouse click
    // (programmatic handoff), drop any auto-selected text so the font name
    // never shows as highlighted.  Mouse focus keeps normal caret behaviour.
    if (watched == lineEdit() && event->type() == QEvent::FocusIn) {
        auto* fe = static_cast<QFocusEvent*>(event);
        if (fe->reason() != Qt::MouseFocusReason)
            lineEdit()->deselect();
        return false;
    }

    if (watched == lineEdit() && event->type() == QEvent::KeyPress) {
        auto* ke = static_cast<QKeyEvent*>(event);
        if (handleNavKey(ke))
            return true;
    }
    // A popup that closes without a commit abandons the pending preview.
    // (On a real commit m_previewActive is already cleared, so nothing is
    // emitted and MainWindow keeps the committed font.)
    if (m_completer && watched == m_completer->popup()
        && event->type() == QEvent::Hide) {
        cancelPreviewIfActive();
    }
    return DownwardCombo::eventFilter(watched, event);
}

bool FontPicker::handleNavKey(QKeyEvent* e)
{
    if (!m_completer)
        return false;
    QAbstractItemView* popup = m_completer->popup();
    const QString t = lineEdit() ? lineEdit()->text() : QString();
    const bool popupVisible = popup->isVisible();

    switch (e->key()) {
    case Qt::Key_Down:
    case Qt::Key_Up:
        if (t.isEmpty())
            return false;  // nothing to filter: let the combo do its thing
        // Make sure the filtered popup is open.
        if (!popupVisible) {
            m_completer->setCompletionPrefix(t);
            m_completer->complete();
            // Bug 2: an arrow key that opens the popup starts browsing from
            // the active font (when it is in the filtered results).
            if (m_completer->popup()->isVisible())
                preselectActiveFont();
        }
        if (!m_completer->popup()->isVisible())
            return false;
        {
            QModelIndex cur = popup->currentIndex();
            int row = cur.isValid() ? cur.row() : -1;
            const int count = m_completer->completionCount();
            const int next = (e->key() == Qt::Key_Down)
                                 ? qMin(row + 1, count - 1)
                                 : qMax(row - 1, 0);
            // While the user navigates, stop the combo from rewriting the
            // edit text (which would re-trigger the filter).  We restore
            // the typed text below with the filter suppressed.
            m_suppressFilter = true;
            // Move both the completer's current row and the popup view's
            // selection/highlight so the user sees the row step down.
            m_completer->setCurrentRow(next);
            const QAbstractItemModel* pm = popup->model();
            const QModelIndex idx =
                pm ? pm->index(next, 0) : QModelIndex();
            if (idx.isValid()) {
                popup->setCurrentIndex(idx);
                popup->selectionModel()->setCurrentIndex(
                    idx, QItemSelectionModel::Current);
                popup->selectionModel()->select(
                    idx, QItemSelectionModel::ClearAndSelect);
                popup->scrollTo(idx);
            }
            // Put the user's typed text back (the combo/completer may have
            // rewritten it with the highlighted row) without filtering.
            if (lineEdit() && lineEdit()->text() != t)
                lineEdit()->setText(t);
            m_suppressFilter = false;
            // Live preview of the newly highlighted font (arrow browsing).
            emitCurrentPreview();
            return true;
        }
    case Qt::Key_Return:
    case Qt::Key_Enter:
        // Commit the font at the popup's ACTUAL highlighted index.  Using
        // m_completer->currentCompletion() here is unreliable: with
        // Qt::MatchContains filtering it can drift from popup->currentIndex()
        // after manual arrow navigation, committing a different row (Bug 1).
        // Falls back to the first visible row when nothing is highlighted.
        if (popupVisible) {
            const QString sel = highlightedFontName();
            if (!sel.isEmpty()) {
                onCompleterActivated(sel);
                return true;  // consume: nothing else double-handles it
            }
        }
        break;
    case Qt::Key_Tab:
        // Tab commits the highlighted completion AND keeps its standard
        // role of advancing focus - so do not consume the event.
        if (popupVisible) {
            const QString sel = highlightedFontName();
            if (!sel.isEmpty())
                onCompleterActivated(sel);
        }
        return false;
    case Qt::Key_Escape:
        // Close the filtered popup, keep the user's typed query intact and
        // cancel any live preview (no commit, no rewrite, no crash when
        // there is no selection to give up).
        cancelPreviewIfActive();
        popup->hide();
        return true;
    default:
        break;
    }
    return false;
}

void FontPicker::keyPressEvent(QKeyEvent* e)
{
    if (handleNavKey(e)) {
        e->accept();
        return;
    }
    DownwardCombo::keyPressEvent(e);
}
