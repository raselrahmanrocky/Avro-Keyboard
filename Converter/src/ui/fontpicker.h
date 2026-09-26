// fontpicker.h - editable, type-to-search font picker.
// Mirrors the Delphi cbFontPicker (csDropDown combo): typing filters the
// list live and Enter commits the highlighted font.
//
// Implementation: the picker is an editable QComboBox whose line edit is
// wired to a QCompleter in PopupCompletion mode.  PopupCompletion shows
// the matching fonts in the completer's popup WITHOUT rewriting the text
// in the edit box (InlineCompletion is what used to auto-complete), and
// it keeps keyboard focus on the line edit so typing never drops focus.
#pragma once

#include "downwardcombo.h"
#include <QColor>
#include <QString>
#include <QStringList>

class QCompleter;
class QEvent;
class QKeyEvent;
class QStringListModel;
class QStyledItemDelegate;

namespace detail {
// Item delegate used on the completer popup: renders every row in the
// standard application UI font, highlights the typed query substring in
// the accent colour, and draws a divider after the pinned group.  Defined
// in fontpicker.cpp; only FontPicker uses it.
class FontHighlightDelegate;
}  // namespace detail

class FontPicker : public DownwardCombo
{
    Q_OBJECT

public:
    explicit FontPicker(QWidget* parent = nullptr);

    QString activeFont() const { return m_activeFont; }
    void setActiveFont(const QString& f);

    void populateFonts();

    // Drops focus from the edit box and clears any text selection.  Called
    // by MainWindow when a conversion starts/finishes so the search box
    // never keeps an orange focus ring or a highlighted font name after a
    // toolbar button is clicked (focus is deliberately mouse-only here).
    void clearSearchFocus();

    // The current type-to-search query (used by the delegate to highlight
    // matching substrings).  Kept in sync from the textEdited handler.
    QString highlightText() const { return m_highlightText; }

    // Every registered font family with a pure-Latin (ASCII) name, so the list
    // always reads in English even when the OS registers a localized (e.g.
    // Bengali) spelling for a font.
    //
    // Cached: the walk behind it (QFontDatabase::families() plus the per-name
    // filtering) costs a few hundred milliseconds on the first call, and the
    // picker is instantiated more than once (toolbar and the Settings dialog),
    // so rebuilding the list per widget would make opening a dialog slow.
    static const QStringList& englishFamilyNames();
    // Drops the cache so the next call re-enumerates - used after bundled font
    // files were registered at runtime (see MainWindow::loadBundledFonts).
    static void invalidateFamilyCache();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;
    void keyPressEvent(QKeyEvent* e) override;
    // Opens the combo's own arrow-dropdown and pre-selects + scrolls to the
    // currently active font (Bug 2).  Chains DownwardCombo::showPopup so the
    // list still always drops downward.
    void showPopup() override;

signals:
    // Emitted whenever a font is actually picked - either by clicking an
    // item in the completer (filter) popup or in the combo's own list.
    // MainWindow connects this to apply the font to the ANSI memo AND to
    // persist it (registry) - the "committed" state.
    void fontPicked(const QString& font);
    // Emitted while browsing (arrow keys / hover) BEFORE any commit: lets
    // MainWindow preview the font live in the ANSI memo.  A preview is
    // never persisted and never becomes the picker's active font.
    void fontPreviewed(const QString& font);
    // Emitted when a preview is abandoned (Escape, or the popup closes
    // without a commit): MainWindow restores the last committed font.
    void fontPreviewCanceled();

private slots:
    void onCompleterActivated(const QString& text);
    void onActivated(int index);

private:
    void setEditTextSuppressed(const QString& text);
    bool handleNavKey(QKeyEvent* e);

    // Emits fontPreviewed() for the currently highlighted completion row.
    void emitCurrentPreview();
    // Cancels an active preview exactly once (guards double signals when
    // Escape hides the popup and the Hide event also arrives).
    void cancelPreviewIfActive();

    // Returns the font name at the popup's currently highlighted index, or
    // the first visible row when nothing is selected (graceful fallback).
    // Reads DisplayRole from the popup view directly - NOT
    // m_completer->currentCompletion(), which can drift from the view's
    // current index during arrow navigation with MatchContains filtering
    // (Bug 1).
    QString highlightedFontName() const;

    // Pre-selects + scrolls the completer (type-to-search) popup to the
    // currently active font whenever it opens.  Called right after
    // m_completer->complete() on the hidden->visible transition.
    void preselectActiveFont();
    // Same for the combo's own arrow-dropdown (see showPopup()).
    void preselectActiveFontInComboView();

    // The actual enumeration behind englishFamilyNames(), kept separate so the
    // public accessor can cache it.
    static QStringList enumerateEnglishFamilyNames();

    // True for legacy Bijoy ANSI fonts (Sutonny*, Bijoy*, Tonny*, Kalpurush
    // ANSI, ...).  These map the ASCII code points to Bengali GLYPH SHAPES.
    // No longer gates any row FontRole (the list renders in the standard UI
    // font); still used by englishFamilyNames() to accept reverse-Bijoy
    // decoded names for these families.
    static bool isLegacyBijoyFont(const QString& name);

    // Best-effort transliteration of a Bijoy-keyboard-encoded Bengali name
    // back to its Latin letters (e.g. "\u099D\u0982\u09A1\u09B9\u09B9\u09CD"
    // -> "Sutonn").  Fallback for the rare machine where the OS registers
    // such fonts with their legacy glyph names.  Characters outside the
    // verified table are left untouched so the strict ASCII filter below
    // still drops the entry.
    static QString bijoyToLatin(const QString& name);

    // Fonts that belong to the popular Bengali ANSI/Unicode group; they are
    // pinned to the top of the list (see populateFonts).
    static bool isPinnedFont(const QString& name);

    QStringListModel* m_model = nullptr;
    QCompleter* m_completer = nullptr;
    detail::FontHighlightDelegate* m_delegate = nullptr;
    QStringList m_allFonts;
    QString m_activeFont;
    QString m_highlightText;      // live query, drives delegate highlighting
    int m_pinnedCount = 0;        // how many leading rows are the pinned group
    bool m_suppressFilter = false;
    bool m_previewActive = false; // a live preview is awaiting commit/cancel
    QString m_lastPreviewed;      // last font we previewed (dedup guard)
};
