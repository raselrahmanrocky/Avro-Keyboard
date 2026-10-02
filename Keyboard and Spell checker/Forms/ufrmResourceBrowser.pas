{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit ufrmResourceBrowser;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls,
  ComCtrls,
  ExtCtrls,
  clsResourceCatalog;

type
  { One entry of the download queue. Jobs run sequentially in a single TTask;
    the record is captured by the per-run closure, so each run owns its copy. }
  TResourceDownloadJob = record
    Url: string;
    FileName: string;
    ResourceType: string;
    Sha256: string;
    Name: string;
    ItemIndex: Integer;
    IsOnlyJob: Boolean;
  end;

  TfrmResourceBrowser = class(TForm)
    lblHint: TLabel;
    lblDestination: TLabel;
    lstCategories: TListBox;
    lvItems: TListView;
    lblItemDesc: TLabel;
    lblStatus: TLabel;
    pbProgress: TProgressBar;
    btnDownload: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure lstCategoriesClick(Sender: TObject);
    procedure lvItemsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvItemsMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure lvItemsColumnClick(Sender: TObject; Column: TListColumn);
    procedure lvItemsItemChecked(Sender: TObject; Item: TListItem);
    procedure btnDownloadClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    private
      FCatalog:       TResourceCatalog;
      FBusy:          Boolean;
      FDownloadQueue: TArray<TResourceDownloadJob>;
      FQueuePos:      Integer;
      FLastTarget:    string;
      FFailedCount:   Integer;
      FLastError:     string;
      { How many requested items were left out of the queue because they are
        already installed - reported by FinishQueue so a bulk download of a
        fully installed selection never claims it re-downloaded anything. }
      FSkipCount:     Integer;
      { Category the caller asked for ('' = default). The catalog arrives
        asynchronously, so the selection is applied after the fetch, not at
        Show time - see SelectCategoryById. }
      FPendingCategory: string;
      { The select-all box floated over the header's first cell is a real
        TCheckBox (created in EnsureSelAllCheckBox) - no code in this unit
        paints it. It is a CHILD OF THE FORM, not of the list: the native
        header lives inside the list's window tree, so anything parented
        inside the list can be buried when Windows re-creates that header,
        while a form-level sibling always paints above the whole list. The
        flag breaks the SetChecked -> Click -> toggle -> SetChecked cycle
        while the box and the rows mirror each other. }
      FSelAll: TCheckBox;
      FUpdatingSelAll: Boolean;

      procedure SetBusy(const ACaption: string);
      procedure LoadCatalog;
      procedure PopulateCategories;
      procedure SelectCategoryById(const AId: string);
      procedure PopulateItems;
      procedure ShowItemDescription(const AIndex: Integer);
      procedure UpdateItemStatus(const AIndex: Integer; const AInstalled: Boolean);
      procedure UpdateDestinationLabel;
      function SelectedItemIndex: Integer;
      function CheckedItemIndexes: TArray<Integer>;
      function ColumnAtX(X: Integer): Integer;
      function AllItemsChecked: Boolean;
      procedure ToggleAllChecked;
      procedure EnsureSelAllCheckBox;
      procedure SyncSelAllCheckBox;
      procedure SelAllClick(Sender: TObject);

      procedure StartDownload(const AIndexes: TArray<Integer>);
      procedure StartDelete(const AIndexes: TArray<Integer>);
      procedure RunNextJob;
      procedure FinishQueue;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
  end;

var
  frmResourceBrowser: TfrmResourceBrowser;

  { Creates the dialog on first use, reuses it afterwards. The instance stays
    alive for the whole session (hide on close), so a download task can never
    race a freed form.

    ACategoryId opens the dialog on that catalog category - 'dictionary' from
    the missing-auto-correct-dictionary balloon and from the auto-correct
    editor's download button. '' (or an id the catalog does not have) shows
    the first category. }
procedure ShowResourceBrowser(const ACategoryId: string = '');

implementation

{$R *.dfm}

uses
  System.Threading,
  uWindowHandlers,
  uFileFolderHandling,
  uResourceInstaller,
  uAutoCorrect,
  uForm1,
  DebugLog;

procedure ShowResourceBrowser(const ACategoryId: string);
begin
  CheckCreateForm(TfrmResourceBrowser, frmResourceBrowser, 'frmResourceBrowser');
  if frmResourceBrowser = nil then
    Exit;
  frmResourceBrowser.FPendingCategory := ACategoryId;
  frmResourceBrowser.Show;
  frmResourceBrowser.BringToFront;
end;

{ ---------------------------------------------------------------------------- }
{ Lifecycle }
{ ---------------------------------------------------------------------------- }

constructor TfrmResourceBrowser.Create(AOwner: TComponent);
begin
  inherited;
  FCatalog := TResourceCatalog.Create;
end;

destructor TfrmResourceBrowser.Destroy;
begin
  FCatalog.Free;
  inherited;
end;

procedure TfrmResourceBrowser.FormCreate(Sender: TObject);
begin
  TOPMOST(Handle);
  lblStatus.Caption := '';
  lblItemDesc.Caption := '';
  UpdateDestinationLabel;
end;

procedure TfrmResourceBrowser.FormShow(Sender: TObject);
begin
  // The select-all box is a real TCheckBox floated over the header's first
  // cell, parented to the form so the native header can never cover it -
  // Ensure creates it on first show and re-raises/heals it on every show.
  EnsureSelAllCheckBox;
  // Every show refreshes the catalog (it is one small HTTPS GET); a running
  // download keeps priority - reopening during a transfer must not restart it.
  if not FBusy then
    LoadCatalog;
end;

procedure TfrmResourceBrowser.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Keep the instance: in-flight TTasks queue onto it, and the next open
  // simply re-fetches the catalog (see FormShow).
  Action := caHide;
end;

procedure TfrmResourceBrowser.btnCloseClick(Sender: TObject);
begin
  Close;
end;

{ ---------------------------------------------------------------------------- }
{ Catalog }
{ ---------------------------------------------------------------------------- }

procedure TfrmResourceBrowser.LoadCatalog;
var
  Catalog: TResourceCatalog;
begin
  FBusy := True;
  SetBusy('Loading resource catalog...');
  Catalog := FCatalog;
  TTask.Run(
      procedure
    var
      Err: string;
      Ok: Boolean;
    begin
      Ok := False;
      Err := '';
      try
        Ok := Catalog.Fetch(Err);
      except
        // A raised exception must still reach the queued completion below -
        // otherwise FBusy stays True and the form is dead for the session.
        on E: Exception do
        begin
          Ok := False;
          Err := 'Catalog error: ' + E.Message;
        end;
      end;
      TThread.Queue(nil,
          procedure
        begin
          FBusy := False;
          if not Ok then
          begin
            lstCategories.Items.Clear;
            lvItems.Items.Clear;
            lblItemDesc.Caption := '';
            lblStatus.Caption := Err;
            Log('Resource catalog fetch failed: ' + Err);
          end
          else
          begin
            PopulateCategories;
            SelectCategoryById(FPendingCategory);
            FPendingCategory := '';
            lblStatus.Caption := IntToStr(Length(Catalog.Categories)) + ' categories loaded.';
          end;
          SetBusy(lblStatus.Caption);
        end);
    end);
end;

procedure TfrmResourceBrowser.SetBusy(const ACaption: string);
begin
  lblStatus.Caption := ACaption;
  btnDownload.Enabled := not FBusy;
  lstCategories.Enabled := not FBusy;
end;

procedure TfrmResourceBrowser.PopulateCategories;
var
  I: Integer;
begin
  lstCategories.Items.Clear;
  lvItems.Items.Clear;
  lblItemDesc.Caption := '';
  for I := 0 to high(FCatalog.Categories) do
    lstCategories.Items.Add(FCatalog.Categories[I].Title);
  if lstCategories.Items.Count > 0 then
  begin
    lstCategories.ItemIndex := 0;
    PopulateItems;
    UpdateDestinationLabel;
  end;
end;

{ Applies the category the caller named in ShowResourceBrowser, now that the
  catalog is in. An id the catalog does not carry (the dictionary category
  only exists once the resource repository has published it) keeps the
  default first category instead of leaving the list empty. }
procedure TfrmResourceBrowser.SelectCategoryById(const AId: string);
var
  I: Integer;
begin
  if AId = '' then
    Exit;
  if (FCatalog = nil) or not FCatalog.Loaded then
    Exit;
  for I := 0 to high(FCatalog.Categories) do
    if SameText(FCatalog.Categories[I].Id, AId) then
    begin
      if lstCategories.ItemIndex <> I then
      begin
        lstCategories.ItemIndex := I;
        PopulateItems;
        UpdateDestinationLabel;
      end;
      Exit;
    end;
  Log('Resource category not in catalog: ' + AId);
end;

procedure TfrmResourceBrowser.PopulateItems;
var
  Cat:        TResourceCategory;
  Item:       TResourceItem;
  Row:        TListItem;
  I:          Integer;
  SizeText:   string;
  IsInstalled: Boolean;
begin
  lvItems.Items.BeginUpdate;
  try
    lvItems.Items.Clear;
    lblItemDesc.Caption := '';
    if (FCatalog = nil) or not FCatalog.Loaded then
      Exit;
    if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > high(FCatalog.Categories)) then
      Exit;

    Cat := FCatalog.Categories[lstCategories.ItemIndex];
    for I := 0 to high(Cat.Items) do
    begin
      Item := Cat.Items[I];
      Row := lvItems.Items.Add;
      // Column 0 is the dedicated checkbox column and stays caption-less; the
      // name starts at SubItems[0], one slot per column to its right.
      Row.Caption := '';
      Row.SubItems.Add(Item.Name);
      Row.SubItems.Add(Item.Version);
      if Item.Size >= 1024 * 1024 then
        SizeText := Format('%.1f MB', [Item.Size / (1024 * 1024)])
      else if Item.Size >= 1024 then
        SizeText := Format('%d KB', [Item.Size div 1024])
      else
        SizeText := IntToStr(Item.Size) + ' B';
      Row.SubItems.Add(SizeText);
      IsInstalled := IsResourceInstalled(Item.ResourceType, Item.FileName);
      if IsInstalled then
        Row.SubItems.Add('Installed')
      else
        Row.SubItems.Add('');
      // The Delete cell carries its label only while the row is installed -
      // lvItemsMouseUp keys its hit test off this same text.
      if IsInstalled then
        Row.SubItems.Add('Delete')
      else
        Row.SubItems.Add('');
    end;
    finally
      lvItems.Items.EndUpdate;
      // Covers every exit above: a rebuilt or emptied list leaves the header's
      // select-all box in step with the rows (unchecked by default). Calling
      // Ensure - not just Sync - also rebuilds the box if it was ever lost to
      // a list-window recycle, and re-raises it above the header.
      EnsureSelAllCheckBox;
    end;
end;

procedure TfrmResourceBrowser.lstCategoriesClick(Sender: TObject);
begin
  PopulateItems;
  UpdateDestinationLabel;
end;

function TfrmResourceBrowser.SelectedItemIndex: Integer;
begin
  Result := -1;
  if (lvItems.Selected <> nil) then
    Result := lvItems.Selected.Index;
end;

{ Every ticked row of the current category, in list order - the input of both
  the Download button (when anything is ticked) and the bulk delete. }
function TfrmResourceBrowser.CheckedItemIndexes: TArray<Integer>;
var
  Cat:   TResourceCategory;
  Count: Integer;
  I:     Integer;
begin
  Result := nil;
  if (FCatalog = nil) or not FCatalog.Loaded then
    Exit;
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > high(FCatalog.Categories)) then
    Exit;
  Cat := FCatalog.Categories[lstCategories.ItemIndex];
  Count := 0;
  SetLength(Result, lvItems.Items.Count);
  for I := 0 to lvItems.Items.Count - 1 do
    if lvItems.Items[I].Checked and (I <= high(Cat.Items)) then
    begin
      Result[Count] := I;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

{ Which column owns client coordinate X. In vsReport mode the boundaries are
  exactly the running sum of the column widths, which is what turns a plain
  MouseUp into "the Delete cell of this row was hit" - TListView reports no
  per-cell click event on its own. }
function TfrmResourceBrowser.ColumnAtX(X: Integer): Integer;
var
  I:    Integer;
  Edge: Integer;
begin
  Result := -1;
  Edge := 0;
  for I := 0 to lvItems.Columns.Count - 1 do
  begin
    Inc(Edge, lvItems.Columns[I].Width);
    if X < Edge then
      Exit(I);
  end;
end;

{ Drives the header's select-all box: it reads as checked only when every row
  is ticked (an empty list reads as unchecked). }
function TfrmResourceBrowser.AllItemsChecked: Boolean;
var
  I: Integer;
begin
  Result := False;
  if lvItems.Items.Count = 0 then
    Exit;
  for I := 0 to lvItems.Items.Count - 1 do
    if not lvItems.Items[I].Checked then
      Exit;
  Result := True;
end;

procedure TfrmResourceBrowser.ToggleAllChecked;
var
  NewState: Boolean;
  I:        Integer;
begin
  NewState := not AllItemsChecked;
  for I := 0 to lvItems.Items.Count - 1 do
    lvItems.Items[I].Checked := NewState;
  // Rows just moved together - bring the header box in line too (the guard
  // keeps its own SetChecked -> Click path from feeding back).
  SyncSelAllCheckBox;
end;

{ Creates (or heals) the select-all box: a real TCheckBox living as a direct
  child of the FORM, floating over the header's first cell. Parenting it to
  the form - not to the list - keeps it strictly above the list's entire
  window tree, so the native header (which sits inside that tree and may be
  re-created on theme/style changes) can never be raised on top of it. Every
  call also re-centers the box and brings it to the front, so even a lost or
  displaced box heals itself on the next show or list refresh. This unit
  holds no drawing code at all. }
procedure TfrmResourceBrowser.EnsureSelAllCheckBox;
var
  Header:    HWND;
  HeaderR:   TRect;
  HeaderH:   Integer;
  BoxL, BoxT: Integer;
begin
  Header := GetDlgItem(lvItems.Handle, 0);
  HeaderH := 21;
  if Header <> 0 then
    if GetWindowRect(Header, HeaderR) then
      HeaderH := HeaderR.Bottom - HeaderR.Top;

  // If a list-window recycle took the box's HWND with it, drop the dead
  // shell so the block below rebuilds it fresh.
  if (FSelAll <> nil) and not IsWindow(FSelAll.Handle) then
    FreeAndNil(FSelAll);

  if FSelAll = nil then
  begin
    if Header = 0 then
      Exit; // no native header yet - PopulateItems/FormShow will retry
    FSelAll := TCheckBox.Create(Self);
    FSelAll.Caption := '';
    FSelAll.Width := 16;
    FSelAll.Height := 16;
    FSelAll.TabStop := False;
    FSelAll.OnClick := SelAllClick;
    FSelAll.Parent := Self; // form child: always above lvItems and its header
  end;

  // Reposition and raise on every call - cheap, and it heals any drift or
  // burial. Coordinates are mapped from lvItems because the box now lives in
  // the form's client space, not the list's.
  if lvItems.Columns.Count > 0 then
    BoxL := (lvItems.Columns[0].Width - FSelAll.Width) div 2
  else
    BoxL := 2;
  if BoxL < 2 then
    BoxL := 2;
  BoxT := (HeaderH - FSelAll.Height) div 2;
  if BoxT < 2 then
    BoxT := 2;
  FSelAll.SetBounds(lvItems.Left + BoxL, lvItems.Top + BoxT, 16, 16);
  FSelAll.BringToFront;
  SyncSelAllCheckBox;
end;

procedure TfrmResourceBrowser.SyncSelAllCheckBox;
begin
  if FSelAll = nil then
    Exit;
  FUpdatingSelAll := True;
  try
    FSelAll.Checked := AllItemsChecked;
  finally
    FUpdatingSelAll := False;
  end;
end;

procedure TfrmResourceBrowser.SelAllClick(Sender: TObject);
begin
  // Re-entrant while SyncSelAllCheckBox mirrors state into the box; the real
  // user click toggles every row and the sync at the end of that toggle
  // settles the box on the matching state.
  if FUpdatingSelAll then
    Exit;
  ToggleAllChecked;
end;

procedure TfrmResourceBrowser.lvItemsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
    ShowItemDescription(Item.Index);
end;

procedure TfrmResourceBrowser.ShowItemDescription(const AIndex: Integer);
var
  Cat:  TResourceCategory;
  Item: TResourceItem;
begin
  lblItemDesc.Caption := '';
  if (FCatalog = nil) or not FCatalog.Loaded then
    Exit;
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > high(FCatalog.Categories)) then
    Exit;
  Cat := FCatalog.Categories[lstCategories.ItemIndex];
  if (AIndex < 0) or (AIndex > high(Cat.Items)) then
    Exit;

  Item := Cat.Items[AIndex];
  lblItemDesc.Caption := Item.Description;
  if Item.DescriptionBn <> '' then
    lblItemDesc.Caption := lblItemDesc.Caption + sLineBreak + Item.DescriptionBn;
end;

procedure TfrmResourceBrowser.UpdateItemStatus(const AIndex: Integer; const AInstalled: Boolean);
begin
  if (AIndex < 0) or (AIndex >= lvItems.Items.Count) then
    Exit;
  if lvItems.Items[AIndex].SubItems.Count < 5 then
    Exit;
  // SubItems: [0]=Name [1]=Version [2]=Size [3]=Status [4]=Delete. Both
  // trailing cells move together so the Delete label only exists while the
  // row reads Installed.
  if AInstalled then
  begin
    lvItems.Items[AIndex].SubItems[3] := 'Installed';
    lvItems.Items[AIndex].SubItems[4] := 'Delete';
  end
  else
  begin
    lvItems.Items[AIndex].SubItems[3] := '';
    lvItems.Items[AIndex].SubItems[4] := '';
  end;
end;

{ States the running edition and where the selected category will actually
  install - the folders differ between the portable and the setup build, and
  the font store differs again (exe's fonts\ vs the per-user store). }
procedure TfrmResourceBrowser.UpdateDestinationLabel;
var
  Folder:  string;
  Edition: string;
begin
  {$IFDEF PortableOn}
  Edition := 'Portable edition';
  {$ELSE}
  Edition := 'Setup edition';
  {$ENDIF}
  Folder := '';
  if (FCatalog <> nil) and FCatalog.Loaded and (lstCategories.ItemIndex >= 0) and (lstCategories.ItemIndex <= high(FCatalog.Categories)) and
    (Length(FCatalog.Categories[lstCategories.ItemIndex].Items) > 0) then
    Folder := ResourceTargetFolder(FCatalog.Categories[lstCategories.ItemIndex].Items[0].ResourceType);

  if Folder = '' then
    lblDestination.Caption := Edition + '.'
  else
    lblDestination.Caption := Edition + ' - files are installed into: ' + Folder;
end;

{ ---------------------------------------------------------------------------- }
{ Download }
{ ---------------------------------------------------------------------------- }

procedure TfrmResourceBrowser.btnDownloadClick(Sender: TObject);
var
  Indexes: TArray<Integer>;
  Index:   Integer;
begin
  // Ticked rows win; with nothing ticked the plain selection still works, so
  // a quick "click a row + Download" behaves exactly like it used to.
  Indexes := CheckedItemIndexes;
  if Length(Indexes) = 0 then
  begin
    Index := SelectedItemIndex;
    if Index < 0 then
    begin
      lblStatus.Caption := 'Select a file first.';
      Exit;
    end;
    SetLength(Indexes, 1);
    Indexes[0] := Index;
  end;
  StartDownload(Indexes);
end;

{ 1-click delete: the trailing Delete cell removes that row's file right away -
  no selecting first and then reaching for a button below. When two or more
  rows are ticked the same click wipes every ticked row instead (confirmed
  first), which is the bulk path. }
procedure TfrmResourceBrowser.lvItemsMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Item:    TListItem;
  Checked: TArray<Integer>;
begin
  if Button <> mbLeft then
    Exit;
  if FBusy then
    Exit; // a running download or catalog fetch owns the list
  if (FCatalog = nil) or not FCatalog.Loaded then
    Exit;

  Item := lvItems.GetItemAt(X, Y);
  if Item = nil then
    Exit;
  if ColumnAtX(X) <> lvItems.Columns.Count - 1 then
    Exit; // only the trailing Delete cell acts
  if (Item.SubItems.Count < 5) or (Item.SubItems[4] <> 'Delete') then
    Exit; // no Delete label on this row - nothing installed to remove

  Checked := CheckedItemIndexes;
  if Length(Checked) >= 2 then
  begin
    // Same confirmation style the auto-correct editor uses before wiping
    // entries; 'No' is the default button - a bulk delete must not fire on
    // an accidental Enter.
    if Application.MessageBox(PChar(Format('Delete %d selected file(s)?', [Length(Checked)])), 'Avro Keyboard',
      MB_YESNO + MB_ICONQUESTION + MB_DEFBUTTON2) <> IDYES then
      Exit;
    StartDelete(Checked);
  end
  else
    StartDelete([Item.Index]);
end;

{ The narrow first header cell doubles as select-all: one click ticks every
  row, or clears them again when they are all ticked. Clicks landing on the
  floating checkbox itself never reach the header - that child window swallows
  them - so the two paths cannot double-toggle. }
procedure TfrmResourceBrowser.lvItemsColumnClick(Sender: TObject; Column: TListColumn);
begin
  if Column.Index <> 0 then
    Exit;
  if (FCatalog = nil) or not FCatalog.Loaded then
    Exit;
  if lvItems.Items.Count = 0 then
    Exit;
  ToggleAllChecked;
end;

procedure TfrmResourceBrowser.lvItemsItemChecked(Sender: TObject; Item: TListItem);
begin
  // Any row tick change - mouse or space bar - has to be reflected in the
  // header's select-all box.
  SyncSelAllCheckBox;
end;

procedure TfrmResourceBrowser.StartDownload(const AIndexes: TArray<Integer>);
var
  Cat:        TResourceCategory;
  Item:       TResourceItem;
  Job:        TResourceDownloadJob;
  I:          Integer;
  QueueCount: Integer;
begin
  if FBusy then
    Exit;
  if (FCatalog = nil) or not FCatalog.Loaded then
  begin
    lblStatus.Caption := 'The resource catalog is not loaded yet - try again in a moment.';
    Exit;
  end;
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > high(FCatalog.Categories)) then
  begin
    lblStatus.Caption := 'Select a category first.';
    Exit;
  end;
  if Length(AIndexes) = 0 then
  begin
    lblStatus.Caption := 'Nothing to download in this category.';
    Exit;
  end;

  Cat := FCatalog.Categories[lstCategories.ItemIndex];
  SetLength(FDownloadQueue, Length(AIndexes));
  FSkipCount := 0;
  QueueCount := 0;
  for I := 0 to high(AIndexes) do
  begin
    if (AIndexes[I] < 0) or (AIndexes[I] > high(Cat.Items)) then
    begin
      FDownloadQueue := nil;
      FSkipCount := 0;
      lblStatus.Caption := 'Invalid selection.';
      Exit;
    end;
    Item := Cat.Items[AIndexes[I]];
    // Already-installed files never enter the queue: a bulk download on a
    // fully installed selection must not re-download and overwrite what is
    // there.
    if IsResourceInstalled(Item.ResourceType, Item.FileName) then
    begin
      Inc(FSkipCount);
      Continue;
    end;
    Job.Url := FCatalog.FileUrl(Item);
    Job.FileName := Item.FileName;
    Job.ResourceType := Item.ResourceType;
    Job.Sha256 := Item.Sha256;
    Job.Name := Item.Name;
    Job.ItemIndex := AIndexes[I];
    Job.IsOnlyJob := False; // set below, once the filtered queue size is known
    FDownloadQueue[QueueCount] := Job;
    Inc(QueueCount);
  end;
  SetLength(FDownloadQueue, QueueCount);
  if QueueCount > 0 then
    for I := 0 to high(FDownloadQueue) do
      FDownloadQueue[I].IsOnlyJob := QueueCount = 1;

  if QueueCount = 0 then
  begin
    // Nothing was queued - every requested file is already installed. Say so
    // instead of showing an empty progress run.
    if Length(AIndexes) = 1 then
      lblStatus.Caption := 'Already installed.'
    else
      lblStatus.Caption := Format('All %d file(s) are already installed.', [FSkipCount]);
    FDownloadQueue := nil;
    FSkipCount := 0;
    Exit;
  end;

  FQueuePos := 0;
  FLastTarget := '';
  FFailedCount := 0;
  FLastError := '';
  RunNextJob;
end;

{ Deletes the given rows synchronously - the work is a local file removal, so
  a worker thread would only complicate the UI state. The post-delete hooks
  mirror the install side of RunNextJob: whatever was loaded out of a removed
  file must be dropped or refreshed. }
procedure TfrmResourceBrowser.StartDelete(const AIndexes: TArray<Integer>);
var
  Cat:           TResourceCategory;
  Item:          TResourceItem;
  Err:           string;
  LastError:     string;
  I:             Integer;
  DeletedCount:  Integer;
  FailedCount:   Integer;
  SkipCount:     Integer;
  TouchedDict:   Boolean;
  TouchedLayout: Boolean;
begin
  if FBusy then
    Exit;
  if (FCatalog = nil) or not FCatalog.Loaded then
  begin
    lblStatus.Caption := 'The resource catalog is not loaded yet - try again in a moment.';
    Exit;
  end;
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > high(FCatalog.Categories)) then
  begin
    lblStatus.Caption := 'Select a category first.';
    Exit;
  end;
  if Length(AIndexes) = 0 then
    Exit;

  Cat := FCatalog.Categories[lstCategories.ItemIndex];
  DeletedCount := 0;
  FailedCount := 0;
  SkipCount := 0;
  LastError := '';
  TouchedDict := False;
  TouchedLayout := False;

  for I := 0 to high(AIndexes) do
  begin
    if (AIndexes[I] < 0) or (AIndexes[I] > high(Cat.Items)) then
      Continue;
    Item := Cat.Items[AIndexes[I]];
    // The tick may have been put on a row that is not installed - nothing to
    // delete there, and it must not be counted as a failure either.
    if not IsResourceInstalled(Item.ResourceType, Item.FileName) then
    begin
      Inc(SkipCount);
      Continue;
    end;
    Err := '';
    if DeleteInstalledResource(Item.ResourceType, Item.FileName, Err) then
    begin
      Inc(DeletedCount);
      if SameText(Item.ResourceType, 'dict') then
        TouchedDict := True;
      if SameText(Item.ResourceType, 'layout') then
        TouchedLayout := True;
    end
    else
    begin
      Inc(FailedCount);
      LastError := Item.Name + ' - ' + Err;
      Log('Resource delete failed: ' + Item.FileName + ' - ' + Err);
    end;
  end;

  // Same reloads the download completion runs: the auto-correct dictionary
  // and the word database are read lazily / eagerly from these files, and a
  // layout needs its menu rebuilt (the folder poll would get there too, just
  // one tick later).
  if TouchedDict then
  begin
    uAutoCorrect.ResetDictLoadState;
    AvroMainForm1.ReloadWordDatabaseIfUsed;
  end;
  if TouchedLayout then
    AvroMainForm1.RefreshLayoutList;

  // Rebuild the rows: Status loses 'Installed', the Delete cell disappears
  // with it, and every tick is cleared again.
  PopulateItems;

  if FailedCount = 0 then
  begin
    lblStatus.Caption := Format('Deleted %d file(s).', [DeletedCount]);
    if SkipCount > 0 then
      lblStatus.Caption := lblStatus.Caption + Format(' %d not installed.', [SkipCount]);
  end
  else
  begin
    lblStatus.Caption := Format('Deleted %d, failed %d.', [DeletedCount, FailedCount]);
    if SkipCount > 0 then
      lblStatus.Caption := lblStatus.Caption + Format(' %d not installed.', [SkipCount]);
    lblStatus.Caption := lblStatus.Caption + ' Last: ' + LastError;
  end;
end;

procedure TfrmResourceBrowser.RunNextJob;
var
  Job:         TResourceDownloadJob;
  LastPercent: Integer;
begin
  if FQueuePos > high(FDownloadQueue) then
  begin
    FinishQueue;
    Exit;
  end;

  Job := FDownloadQueue[FQueuePos];
  FBusy := True;
  SetBusy(Format('Downloading %s (%d of %d)...', [Job.Name, FQueuePos + 1, Length(FDownloadQueue)]));
  pbProgress.Position := 0;
  // Progress exists only while a download actually runs - it stays hidden
  // through loading, browsing and every idle moment (see also FinishQueue).
  pbProgress.Visible := True;
  LastPercent := -1;

  TTask.Run(
    procedure
    var
      Err: string;
      Target: string;
      Ok: Boolean;
    begin
      Ok := False;
      Err := '';
      Target := '';
      try
        Ok := DownloadAndInstallResource(Job.Url, Job.FileName, Job.ResourceType, Job.Sha256,
            procedure(const AContentLength, AReadCount: Int64)
          var
            Percent: Integer;
          begin
            if AContentLength <= 0 then
              Exit;
            Percent := Round(AReadCount * 100 / AContentLength);
            if Percent > 100 then
              Percent := 100;
            // One queued closure per percent step (not per network chunk):
            // hundreds of TThread.Queue entries per download lag the UI.
            if Percent = LastPercent then
              Exit;
            LastPercent := Percent;
            TThread.Queue(nil,
                procedure
              begin
                pbProgress.Max := 100;
                pbProgress.Position := Percent;
              end);
          end, Err, Target);
      except
        // The completion below must run no matter what - otherwise FBusy
        // stays True and every later click silently does nothing.
        on E: Exception do
        begin
          Ok := False;
          Err := 'Unexpected error: ' + E.Message;
          Target := '';
        end;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Ok then
          begin
            UpdateItemStatus(Job.ItemIndex, True);
            FLastTarget := Target;
            // The dictionary is read lazily by the typing path, and a load
            // that already failed is never retried in the same session -
            // drop that state now so the next keystroke parses the file
            // just installed instead of waiting for a restart. Database.db3
            // shares the 'dict' type, so the word database - loaded eagerly
            // at startup, and silent when the file is gone (uDBase) - is
            // retried here too: RefreshSettings is the only other caller and
            // it does not run on an install.
            if SameText(Job.ResourceType, 'dict') then
            begin
              uAutoCorrect.ResetDictLoadState;
              AvroMainForm1.ReloadWordDatabaseIfUsed;
            end;

            // The layouts folder is the one resource folder with NO directory
            // watcher (FDirectoryWatcher covers AnsiMappingDir only), so a
            // downloaded layout has to be pushed into the menus explicitly -
            // otherwise it reaches them only after the next restart.
            // RefreshLayoutList is a no-op when nothing really changed.
            if SameText(Job.ResourceType, 'layout') then
              AvroMainForm1.RefreshLayoutList;

            // A document is meant to be read right away; anything else just
            // appears in its list/folder (ANSI mappings are picked up by the
            // directory watcher automatically).
            if Job.IsOnlyJob and SameText(Job.ResourceType, 'doc') then
            begin
              FinishQueue;
              lblStatus.Caption := 'Downloaded: ' + Job.Name;
              Execute_Something(Target);
            end
            else
            begin
              Inc(FQueuePos);
              RunNextJob;
            end;
          end
          else
          begin
            UpdateItemStatus(Job.ItemIndex, False);
            Inc(FFailedCount);
            FLastError := Job.Name + ' - ' + Err;
            Log('Resource download failed: ' + Job.FileName + ' - ' + Err);
            // One broken file must not abandon the rest of the queue -
            // keep going; FinishQueue reports the totals.
            Inc(FQueuePos);
            RunNextJob;
          end;
        end);
    end);
end;

procedure TfrmResourceBrowser.FinishQueue;
var
  InstalledCount: Integer;
  Message:        string;
  Parts:          string;
begin
  FBusy := False;
  pbProgress.Position := 0;
  pbProgress.Visible := False;
  InstalledCount := Length(FDownloadQueue) - FFailedCount;
  Message := '';
  if (FSkipCount = 0) and (Length(FDownloadQueue) = 1) then
  begin
    // One file, nothing skipped - keep the detailed per-case wording.
    // Keep the detailed reason visible - a SHA mismatch or HTTP error is
    // the only clue the user gets about why a download did not land.
    if FFailedCount > 0 then
      Message := 'Failed: ' + FLastError
    else if FLastTarget <> '' then
      // Full path, not just the file name: the folders differ per edition and
      // per category, this is where the user can confirm exactly where the
      // file landed.
      Message := 'Installed: ' + FLastTarget;
  end
  else
  begin
    // Parts after the dash: installed / failed / already installed.
    Parts := '';
    if InstalledCount > 0 then
      Parts := Format('%d installed', [InstalledCount]);
    if FFailedCount > 0 then
    begin
      if Parts <> '' then
        Parts := Parts + ', ';
      Parts := Parts + Format('%d failed', [FFailedCount]);
    end;
    if FSkipCount > 0 then
    begin
      if Parts <> '' then
        Parts := Parts + ', ';
      Parts := Parts + Format('%d already installed', [FSkipCount]);
    end;

    if InstalledCount = 0 then
    begin
      Message := Format('All %d download(s) failed', [FFailedCount]);
      if FSkipCount > 0 then
        Message := Message + Format(', %d already installed', [FSkipCount]);
    end
    else
      Message := 'Done - ' + Parts + '.';
    if FFailedCount > 0 then
      Message := Message + ' Last: ' + FLastError;
    if Message = '' then
      // Nothing was ever queued - every requested file was already installed.
      Message := Format('All %d file(s) are already installed.', [FSkipCount]);
  end;

  SetBusy(Message);
  FFailedCount := 0;
  FLastError := '';
  FSkipCount := 0;
  FDownloadQueue := nil;
  FQueuePos := 0;
  // The catalog is unchanged by an install - refresh the installed markers.
  PopulateItems;
end;

end.
