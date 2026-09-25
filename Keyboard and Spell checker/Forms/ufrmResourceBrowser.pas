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
    Url:          string;
    FileName:     string;
    ResourceType: string;
    Sha256:       string;
    Name:         string;
    ItemIndex:    Integer;
    IsOnlyJob:    Boolean;
  end;

  TfrmResourceBrowser = class(TForm)
    lblHint:         TLabel;
    lstCategories:   TListBox;
    lvItems:         TListView;
    lblItemDesc:     TLabel;
    lblStatus:       TLabel;
    pbProgress:      TProgressBar;
    btnDownload:     TButton;
    btnDownloadAll:  TButton;
    btnClose:        TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure lstCategoriesClick(Sender: TObject);
    procedure lvItemsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnDownloadClick(Sender: TObject);
    procedure btnDownloadAllClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    private
      FCatalog:      TResourceCatalog;
      FBusy:         Boolean;
      FDownloadQueue: TArray<TResourceDownloadJob>;
      FQueuePos:     Integer;
      FLastTarget:   string;
      FFailedCount:  Integer;
      FLastError:    string;

      procedure SetBusy(const ACaption: string);
      procedure LoadCatalog;
      procedure PopulateCategories;
      procedure PopulateItems;
      procedure ShowItemDescription(const AIndex: Integer);
      procedure UpdateItemStatus(const AIndex: Integer; const AInstalled: Boolean);
      function  SelectedItemIndex: Integer;

      procedure StartDownload(const AIndexes: TArray<Integer>);
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
  race a freed form. }
procedure ShowResourceBrowser;

implementation

{$R *.dfm}

uses
  System.Threading,
  uWindowHandlers,
  uFileFolderHandling,
  uResourceInstaller,
  DebugLog;

procedure ShowResourceBrowser;
begin
  CheckCreateForm(TfrmResourceBrowser, frmResourceBrowser, 'frmResourceBrowser');
  if frmResourceBrowser = nil then
    Exit;
  frmResourceBrowser.Show;
  frmResourceBrowser.BringToFront;
end;

{ ---------------------------------------------------------------------------- }
{ Lifecycle                                                                    }
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
end;

procedure TfrmResourceBrowser.FormShow(Sender: TObject);
begin
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
{ Catalog                                                                      }
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
      Ok:  Boolean;
    begin
      Ok  := False;
      Err := '';
      try
        Ok := Catalog.Fetch(Err);
      except
        // A raised exception must still reach the queued completion below -
        // otherwise FBusy stays True and the form is dead for the session.
        on E: Exception do
        begin
          Ok  := False;
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
            lblStatus.Caption := IntToStr(Length(Catalog.Categories)) + ' categories loaded.';
          end;
          SetBusy(lblStatus.Caption);
        end);
    end);
end;

procedure TfrmResourceBrowser.SetBusy(const ACaption: string);
begin
  lblStatus.Caption      := ACaption;
  btnDownload.Enabled    := not FBusy;
  btnDownloadAll.Enabled := not FBusy;
  lstCategories.Enabled  := not FBusy;
end;

procedure TfrmResourceBrowser.PopulateCategories;
var
  I: Integer;
begin
  lstCategories.Items.Clear;
  lvItems.Items.Clear;
  lblItemDesc.Caption := '';
  for I := 0 to High(FCatalog.Categories) do
    lstCategories.Items.Add(FCatalog.Categories[I].Title);
  if lstCategories.Items.Count > 0 then
  begin
    lstCategories.ItemIndex := 0;
    PopulateItems;
  end;
end;

procedure TfrmResourceBrowser.PopulateItems;
var
  Cat:     TResourceCategory;
  Item:    TResourceItem;
  Row:     TListItem;
  I:       Integer;
  SizeText: string;
begin
  lvItems.Items.BeginUpdate;
  try
    lvItems.Items.Clear;
    lblItemDesc.Caption := '';
    if (FCatalog = nil) or not FCatalog.Loaded then
      Exit;
    if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > High(FCatalog.Categories)) then
      Exit;

    Cat := FCatalog.Categories[lstCategories.ItemIndex];
    for I := 0 to High(Cat.Items) do
    begin
      Item := Cat.Items[I];
      Row  := lvItems.Items.Add;
      Row.Caption := Item.Name;
      Row.SubItems.Add(Item.Version);
      if Item.Size >= 1024 * 1024 then
        SizeText := Format('%.1f MB', [Item.Size / (1024 * 1024)])
      else if Item.Size >= 1024 then
        SizeText := Format('%d KB', [Item.Size div 1024])
      else
        SizeText := IntToStr(Item.Size) + ' B';
      Row.SubItems.Add(SizeText);
      if IsResourceInstalled(Item.ResourceType, Item.FileName) then
        Row.SubItems.Add('Installed')
      else
        Row.SubItems.Add('');
    end;
  finally
    lvItems.Items.EndUpdate;
  end;
end;

procedure TfrmResourceBrowser.lstCategoriesClick(Sender: TObject);
begin
  PopulateItems;
end;

function TfrmResourceBrowser.SelectedItemIndex: Integer;
begin
  Result := -1;
  if (lvItems.Selected <> nil) then
    Result := lvItems.Selected.Index;
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
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > High(FCatalog.Categories)) then
    Exit;
  Cat := FCatalog.Categories[lstCategories.ItemIndex];
  if (AIndex < 0) or (AIndex > High(Cat.Items)) then
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
  if lvItems.Items[AIndex].SubItems.Count < 3 then
    Exit;
  if AInstalled then
    lvItems.Items[AIndex].SubItems[2] := 'Installed'
  else
    lvItems.Items[AIndex].SubItems[2] := '';
end;

{ ---------------------------------------------------------------------------- }
{ Download                                                                     }
{ ---------------------------------------------------------------------------- }

procedure TfrmResourceBrowser.btnDownloadClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedItemIndex;
  if Index < 0 then
  begin
    lblStatus.Caption := 'Select a file first.';
    Exit;
  end;
  StartDownload([Index]);
end;

procedure TfrmResourceBrowser.btnDownloadAllClick(Sender: TObject);
var
  Cat:   TResourceCategory;
  Indexes: TArray<Integer>;
  I:     Integer;
begin
  if (FCatalog = nil) or not FCatalog.Loaded then
    Exit;
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > High(FCatalog.Categories)) then
    Exit;
  Cat := FCatalog.Categories[lstCategories.ItemIndex];
  if Length(Cat.Items) = 0 then
    Exit;
  SetLength(Indexes, Length(Cat.Items));
  for I := 0 to High(Cat.Items) do
    Indexes[I] := I;
  StartDownload(Indexes);
end;

procedure TfrmResourceBrowser.StartDownload(const AIndexes: TArray<Integer>);
var
  Cat:  TResourceCategory;
  Item: TResourceItem;
  Job:  TResourceDownloadJob;
  I:    Integer;
begin
  if FBusy then
    Exit;
  if (FCatalog = nil) or not FCatalog.Loaded then
  begin
    lblStatus.Caption := 'The resource catalog is not loaded yet - try again in a moment.';
    Exit;
  end;
  if (lstCategories.ItemIndex < 0) or (lstCategories.ItemIndex > High(FCatalog.Categories)) then
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
  for I := 0 to High(AIndexes) do
  begin
    if (AIndexes[I] < 0) or (AIndexes[I] > High(Cat.Items)) then
    begin
      FDownloadQueue := nil;
      lblStatus.Caption := 'Invalid selection.';
      Exit;
    end;
    Item := Cat.Items[AIndexes[I]];
    Job.Url          := FCatalog.FileUrl(Item);
    Job.FileName     := Item.FileName;
    Job.ResourceType := Item.ResourceType;
    Job.Sha256       := Item.Sha256;
    Job.Name         := Item.Name;
    Job.ItemIndex    := AIndexes[I];
    Job.IsOnlyJob    := Length(AIndexes) = 1;
    FDownloadQueue[I] := Job;
  end;

  FQueuePos  := 0;
  FLastTarget := '';
  FFailedCount := 0;
  FLastError   := '';
  RunNextJob;
end;

procedure TfrmResourceBrowser.RunNextJob;
var
  Job:        TResourceDownloadJob;
  LastPercent: Integer;
begin
  if FQueuePos > High(FDownloadQueue) then
  begin
    FinishQueue;
    Exit;
  end;

  Job := FDownloadQueue[FQueuePos];
  FBusy := True;
  SetBusy(Format('Downloading %s (%d of %d)...', [Job.Name, FQueuePos + 1, Length(FDownloadQueue)]));
  pbProgress.Position := 0;
  LastPercent := -1;

  TTask.Run(
    procedure
    var
      Err:    string;
      Target: string;
      Ok:     Boolean;
    begin
      Ok     := False;
      Err    := '';
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
                pbProgress.Max      := 100;
                pbProgress.Position := Percent;
              end);
          end,
          Err, Target);
      except
        // The completion below must run no matter what - otherwise FBusy
        // stays True and every later click silently does nothing.
        on E: Exception do
        begin
          Ok     := False;
          Err    := 'Unexpected error: ' + E.Message;
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
begin
  FBusy := False;
  pbProgress.Position := 0;
  if FFailedCount > 0 then
  begin
    // Keep the detailed reason visible - a SHA mismatch or HTTP error is
    // the only clue the user gets about why a download did not land.
    if Length(FDownloadQueue) = 1 then
      SetBusy('Failed: ' + FLastError)
    else
    begin
      InstalledCount := Length(FDownloadQueue) - FFailedCount;
      if InstalledCount = 0 then
        SetBusy(Format('All %d download(s) failed. Last: %s', [FFailedCount, FLastError]))
      else
        SetBusy(Format('Done - %d installed, %d failed. Last: %s',
          [InstalledCount, FFailedCount, FLastError]));
    end;
  end
  else if Length(FDownloadQueue) > 1 then
    SetBusy(Format('Done - %d file(s) installed.', [Length(FDownloadQueue)]))
  else if FLastTarget <> '' then
    SetBusy('Installed: ' + ExtractFileName(FLastTarget))
  else
    SetBusy('');
  FFailedCount   := 0;
  FLastError     := '';
  FDownloadQueue := nil;
  FQueuePos      := 0;
  // The catalog is unchanged by an install - refresh the installed markers.
  PopulateItems;
end;

end.
