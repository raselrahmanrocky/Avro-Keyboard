{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit clsResourceCatalog;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient;

type
  { One downloadable file listed in the resource repository's index.json. }
  TResourceItem = record
    FileName:      string; // repo-relative path, e.g. 'AnsiMapping/Ansi V1.AvroEnco'
    Name:          string;
    ResourceType:  string; // ansimapping | layout | font | skin | doc
    Version:       string;
    Description:   string;
    DescriptionBn: string;
    Size:          Int64;
    Sha256:        string;
  end;

  TResourceCategory = record
    Id:      string;
    Title:   string;
    TitleBn: string;
    Items:   TArray<TResourceItem>;
  end;

  { Fetches and parses index.json from the Avro-Keyboard-Resource repository.

    Fetch is synchronous on purpose: callers run it inside a TTask and marshal
    the result back to the UI thread themselves - the same shape as
    TUpdateCheck.Check (clsUpdateInfoDownloader). }
  TResourceCatalog = class
    private
      FCategories: TArray<TResourceCategory>;
      FBaseUrl:    string;
      FGenerated:  string;
      FLoaded:     Boolean;

      function ParseCatalog(const AJson: string; out AError: string): Boolean;
    public
      function Fetch(out AError: string): Boolean;
      procedure Clear;

      { Absolute download URL for one item (base URL + percent-encoded path). }
      function FileUrl(const AItem: TResourceItem): string;
      class function DefaultIndexUrl: string;

      property Loaded: Boolean read FLoaded;
      property Generated: string read FGenerated;
      property BaseUrl: string read FBaseUrl;
      property Categories: TArray<TResourceCategory> read FCategories;
  end;

implementation

const
  RESOURCE_INDEX_URL = 'https://raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard-Resource/main/index.json';
  RESOURCE_RAW_ROOT  = 'https://raw.githubusercontent.com/';

{ ---------------------------------------------------------------------------- }
{ Helpers                                                                      }
{ ---------------------------------------------------------------------------- }

class function TResourceCatalog.DefaultIndexUrl: string;
begin
  Result := RESOURCE_INDEX_URL;
end;

function JsonStr(const AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if AObj = nil then
    Exit;
  V := AObj.Values[AName];
  if V = nil then
    Exit;
  if V is TJSONString then
    Result := TJSONString(V).Value
  else if not (V is TJSONNull) then
    Result := V.Value;
end;

{ Percent-encode spaces so file names like 'Ansi V1.AvroEnco' survive the URL.
  Everything else in the catalog paths is already URL-safe. }
function EncodeUrlPath(const APath: string): string;
begin
  Result := StringReplace(APath, ' ', '%20', [rfReplaceAll]);
end;

{ ---------------------------------------------------------------------------- }
{ TResourceCatalog                                                             }
{ ---------------------------------------------------------------------------- }

procedure TResourceCatalog.Clear;
begin
  FCategories := nil;
  FBaseUrl    := '';
  FGenerated  := '';
  FLoaded     := False;
end;

function TResourceCatalog.Fetch(out AError: string): Boolean;
var
  Http:      TNetHTTPClient;
  Response:  IHTTPResponse;
begin
  Result  := False;
  AError  := '';

  Http := TNetHTTPClient.Create(nil);
  try
    Http.UserAgent          := 'Avro Keyboard';
    Http.AllowCookies       := False;
    Http.ConnectionTimeout  := 8000;
    Http.ResponseTimeout    := 15000;
    try
      Response := Http.Get(RESOURCE_INDEX_URL);
    except
      on E: Exception do
      begin
        AError := 'Could not download the resource catalog: ' + E.Message;
        Exit;
      end;
    end;

    if Response.StatusCode <> 200 then
    begin
      AError := 'Resource catalog is unavailable (HTTP ' + IntToStr(Response.StatusCode) + ').';
      Exit;
    end;

    Result := ParseCatalog(Response.ContentAsString, AError);
  finally
    Http.Free;
  end;
end;

function TResourceCatalog.ParseCatalog(const AJson: string; out AError: string): Boolean;
var
  Text:      string;
  Root:      TJSONValue;
  RootObj:   TJSONObject;
  Cats:      TJSONValue;
  CatArray:  TJSONArray;
  Repo:      string;
  Branch:    string;
  Base:      string;
  CatList:   TList<TResourceCategory>;
  ItemList:  TList<TResourceItem>;
  CatObj:    TJSONObject;
  ItemObj:   TJSONObject;
  ItemArray: TJSONArray;
  Cat:       TResourceCategory;
  Item:      TResourceItem;
  SizeValue: TJSONValue;
  I, J:      Integer;
begin
  Result  := False;
  AError  := '';
  Clear;

  Text := AJson;
  // A surviving UTF-8 BOM arrives decoded as U+FEFF - strip it before parsing.
  if (Length(Text) >= 1) and (Text[1] = #$FEFF) then
    Delete(Text, 1, 1);
  if Trim(Text) = '' then
  begin
    AError := 'The resource catalog is empty.';
    Exit;
  end;

  Root := TJSONObject.ParseJSONValue(Text);
  if Root = nil then
  begin
    AError := 'The resource catalog is not valid JSON.';
    Exit;
  end;
  try
    if not (Root is TJSONObject) then
    begin
      AError := 'The resource catalog has an unexpected shape.';
      Exit;
    end;
    RootObj := TJSONObject(Root);

    if StrToIntDef(JsonStr(RootObj, 'schema'), 0) < 1 then
    begin
      AError := 'Unsupported resource catalog version.';
      Exit;
    end;

    // File URLs: explicit baseUrl wins, otherwise raw.githubusercontent.com
    // is assembled from repo + branch so a renamed/branded fork just works.
    Base   := JsonStr(RootObj, 'baseUrl');
    Repo   := JsonStr(RootObj, 'repo');
    Branch := JsonStr(RootObj, 'branch');
    if Base = '' then
    begin
      if (Repo = '') or (Branch = '') then
      begin
        AError := 'The resource catalog does not say where files live (repo/branch).';
        Exit;
      end;
      Base := RESOURCE_RAW_ROOT + Repo + '/' + Branch + '/';
    end;
    FBaseUrl   := Base;
    FGenerated := JsonStr(RootObj, 'generated');

    Cats := RootObj.Values['categories'];
    if not (Cats is TJSONArray) then
    begin
      AError := 'The resource catalog has no categories.';
      Exit;
    end;
    CatArray := TJSONArray(Cats);

    CatList := TList<TResourceCategory>.Create;
    try
      for I := 0 to CatArray.Count - 1 do
      begin
        if not (CatArray.Items[I] is TJSONObject) then
          Continue;
        CatObj := TJSONObject(CatArray.Items[I]);

        Cat.Id      := JsonStr(CatObj, 'id');
        Cat.Title   := JsonStr(CatObj, 'title');
        Cat.TitleBn := JsonStr(CatObj, 'titleBn');
        if Cat.Id = '' then
          Continue;

        ItemList := TList<TResourceItem>.Create;
        try
          if CatObj.Values['items'] is TJSONArray then
          begin
            ItemArray := TJSONArray(CatObj.Values['items']);
            for J := 0 to ItemArray.Count - 1 do
            begin
              if not (ItemArray.Items[J] is TJSONObject) then
                Continue;
              ItemObj := TJSONObject(ItemArray.Items[J]);

              Item.FileName      := JsonStr(ItemObj, 'file');
              Item.Name          := JsonStr(ItemObj, 'name');
              Item.ResourceType  := JsonStr(ItemObj, 'type');
              Item.Version       := JsonStr(ItemObj, 'version');
              Item.Description   := JsonStr(ItemObj, 'description');
              Item.DescriptionBn := JsonStr(ItemObj, 'descriptionBn');
              Item.Sha256        := JsonStr(ItemObj, 'sha256');

              Item.Size := 0;
              SizeValue := ItemObj.Values['size'];
              if SizeValue is TJSONNumber then
                Item.Size := TJSONNumber(SizeValue).AsInt64
              else if SizeValue <> nil then
                Item.Size := StrToInt64Def(SizeValue.Value, 0);

              if (Item.FileName = '') or (Item.Name = '') then
                Continue;
              ItemList.Add(Item);
            end;
          end;
          Cat.Items := ItemList.ToArray;
        finally
          ItemList.Free;
        end;

        CatList.Add(Cat);
      end;

      FCategories := CatList.ToArray;
    finally
      CatList.Free;
    end;

    if Length(FCategories) = 0 then
    begin
      AError := 'The resource catalog contains no usable categories.';
      Exit;
    end;

    FLoaded := True;
    Result  := True;
  finally
    Root.Free;
  end;
end;

function TResourceCatalog.FileUrl(const AItem: TResourceItem): string;
begin
  Result := FBaseUrl + EncodeUrlPath(AItem.FileName);
end;

end.
