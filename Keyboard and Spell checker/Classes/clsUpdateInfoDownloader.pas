{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit clsUpdateInfoDownloader;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Net.HttpClientComponent,
  Xml.XMLIntf,
  Xml.XMLDoc,
  System.Variants,
  Vcl.Forms,
  Windows,
  Winapi.WinInet;

type
  TUpdateCheck = class
    private
      HttpClient:       TNetHTTPClient;
      HttpRequest:      TNetHTTPRequest;
      Xml:              IXMLDocument;
      StillDownloading: Boolean;
      Verbose:          Boolean;

      function IsUpdate(const Major, Minor, Release, Build: Integer): Boolean;
      function DownloadUrlAvailable(const Url: string): Boolean;
      procedure ProcessResponse(const Response: string);
    public
      function IsConnected: Boolean;
      procedure Check;
      procedure CheckSilent;
      constructor Create;
      destructor Destroy; override;
  end;

var
  Updater: TUpdateCheck;

implementation

uses
  clsFileVersion,
  ufrmUpdateNotify,
  uWindowHandlers,
  uRegistrySettings,
  System.Threading,
  DebugLog;

{ Returns the update feed URL for the channel the user selected in Options
  (CheckBetaUpdates). The files live on the main branch of the
  Avro-Keyboard-Releases repository; pushing a new XML is enough to publish. }
function GetUpdateInfoURL: string;
const
  URL_STABLE = 'https://raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard-Releases/main/versioninfo.xml';
  URL_BETA   = 'https://raw.githubusercontent.com/raselrahmanrocky/Avro-Keyboard-Releases/main/versioninfo_beta.xml';
begin
  if CheckBetaUpdates = 'YES' then
    Result := URL_BETA
  else
    Result := URL_STABLE;
end;

{ TUpdateCheck }
{ =============================================================================== }
procedure TUpdateCheck.Check;
begin
  if StillDownloading then
    Exit;

  Verbose := True;
  StillDownloading := True;

  TTask.Run(
      procedure
    var
      Response: string;
    begin
      try
        Response := HttpClient.Get(GetUpdateInfoURL).ContentAsString();
        TThread.Queue(nil,
            procedure
          begin
            ProcessResponse(Response);
          end);
      except
        on E: Exception do
        begin
          StillDownloading := False;
          if Verbose then
            Application.MessageBox('There was an error checking for updates. Please try again later.', 'Error', MB_OK or MB_ICONHAND or MB_DEFBUTTON1 or
              MB_SYSTEMMODAL);
        end;
      end;
    end);
end;

{ =============================================================================== }

procedure TUpdateCheck.CheckSilent;
begin
  if StillDownloading then
    Exit;

  Verbose := False;
  StillDownloading := True;

  TTask.Run(
    procedure
    var
      Response: string;
    begin
      try
        Response := HttpClient.Get(GetUpdateInfoURL).ContentAsString();
        TThread.Queue(nil,
            procedure
          begin
            ProcessResponse(Response);
          end);
      except
        on E: Exception do
          StillDownloading := False;
      end;
    end);
end;

constructor TUpdateCheck.Create;
begin
  inherited;
  HttpClient := TNetHTTPClient.Create(nil);
  HttpRequest := TNetHTTPRequest.Create(nil);
  HttpRequest.Client := HttpClient;
  HttpClient.UserAgent := 'Avro Keyboard';
  HttpClient.AllowCookies := True;
  StillDownloading := False;
end;

{ =============================================================================== }

destructor TUpdateCheck.Destroy;
begin
  HttpRequest.Free;
  HttpClient.Free;
  inherited;
end;

{ =============================================================================== }

procedure TUpdateCheck.ProcessResponse(const Response: string);
var
  Major, Minor, Release, Build:                           Integer;
  changelogurl, downloadurl, productpageurl, releasedate: string;
  OfferUpdate:                                            Boolean;
begin
  StillDownloading := False;

  try
    Xml := TXMLDocument.Create(nil);
    Xml.LoadFromXML(Response);
    Xml.Active := True;

    // Extracting update information
    Major := Xml.DocumentElement.ChildNodes['versionmajor'].NodeValue;
    Minor := Xml.DocumentElement.ChildNodes['versionminor'].NodeValue;
    Release := Xml.DocumentElement.ChildNodes['versionrevision'].NodeValue;
    if Assigned(Xml.DocumentElement.ChildNodes.FindNode('versionbuild')) then
      Build := Xml.DocumentElement.ChildNodes['versionbuild'].NodeValue
    else
      Build := 0; // Default for Avro 4.x compatibility

    changelogurl := Xml.DocumentElement.ChildNodes['changelogurl'].NodeValue;
    downloadurl := Xml.DocumentElement.ChildNodes['downloadurl'].NodeValue;
    productpageurl := Xml.DocumentElement.ChildNodes['productpageurl'].NodeValue;
    releasedate := Xml.DocumentElement.ChildNodes['releasedate'].NodeValue;

    // Prefer the installer matching this executable's architecture when the
    // feed provides per-arch URLs. Feeds without these nodes (legacy) keep
    // using downloadurl unchanged. Portable builds additionally prefer the
    // portable ZIP nodes, so portable users receive a portable ZIP instead
    // of a setup installer; missing portable nodes fall through to the
    // regular per-arch (then generic) resolution below.
    {$IFDEF PortableOn}
    if (SizeOf(Pointer) = 8) and Assigned(Xml.DocumentElement.ChildNodes.FindNode('downloadurlportable64')) then
      downloadurl := Xml.DocumentElement.ChildNodes['downloadurlportable64'].NodeValue
    else if (SizeOf(Pointer) = 4) and Assigned(Xml.DocumentElement.ChildNodes.FindNode('downloadurlportable32')) then
      downloadurl := Xml.DocumentElement.ChildNodes['downloadurlportable32'].NodeValue
    else
    {$ENDIF}
    if (SizeOf(Pointer) = 8) and Assigned(Xml.DocumentElement.ChildNodes.FindNode('downloadurl64')) then
      downloadurl := Xml.DocumentElement.ChildNodes['downloadurl64'].NodeValue
    else if (SizeOf(Pointer) = 4) and Assigned(Xml.DocumentElement.ChildNodes.FindNode('downloadurl32')) then
      downloadurl := Xml.DocumentElement.ChildNodes['downloadurl32'].NodeValue;

    // Only when the server reports a newer version: confirm the offered
    // download link actually exists (HEAD request), so a stale manifest can
    // never send the user to a 404. Dead link = treat as no update.
    OfferUpdate := IsUpdate(Major, Minor, Release, Build);
    if OfferUpdate and (not DownloadUrlAvailable(downloadurl)) then
    begin
      Log('Update ' + Format('%d.%d.%d.%d', [Major, Minor, Release, Build]) + ' suppressed, download URL unavailable: ' + downloadurl);
      OfferUpdate := False;
    end;

    if OfferUpdate then
    begin
      CheckCreateForm(TfrmUpdateNotify, frmUpdateNotify, 'frmUpdateNotify');
      frmUpdateNotify.SetupAndShow(Format('%d.%d.%d.%d', [Major, Minor, Release, Build]), releasedate, changelogurl, downloadurl);
    end
    else if Verbose then
    begin
      Application.MessageBox('You are using the latest version of Avro Keyboard.' + #10 + 'No update is available at this moment.', 'Avro Keyboard',
        MB_OK or MB_ICONEXCLAMATION or MB_DEFBUTTON1 or MB_SYSTEMMODAL);
    end;

  except
    on E: Exception do
    begin
      if Verbose then
        Application.MessageBox('There was an error processing update information. Please try again later.', 'Error', MB_OK or MB_ICONHAND or MB_DEFBUTTON1 or
          MB_SYSTEMMODAL);
    end;
  end;
end;

{ =============================================================================== }

function TUpdateCheck.IsConnected: Boolean;
var
  dwConnectionTypes: DWORD;
begin
  Result := False;
  dwConnectionTypes := INTERNET_CONNECTION_MODEM + INTERNET_CONNECTION_LAN + INTERNET_CONNECTION_PROXY;

  Result := InternetGetConnectedState(@dwConnectionTypes, 0);
end;

{ =============================================================================== }

function TUpdateCheck.IsUpdate(const Major, Minor, Release, Build: Integer): Boolean;
var
  Version: TFileVersion;
begin
  Version := TFileVersion.Create;
  Log('IsUpdate check (Remote) Major:' + IntToStr(Major) + ' Minor:' + IntToStr(Minor) + ' Release:' + IntToStr(Release) + ' Build:' + IntToStr(Build));
  Log('IsUpdate check (Own) Major:' + IntToStr(Version.VerMajor) + ' Minor:' + IntToStr(Version.VerMinor) + ' Release:' + IntToStr(Version.VerRelease) +
    ' Build:' + IntToStr(Version.VerBuild));
  try
    Result := (Major > Version.VerMajor) or ((Major = Version.VerMajor) and (Minor > Version.VerMinor)) or
      ((Major = Version.VerMajor) and (Minor = Version.VerMinor) and (Release > Version.VerRelease)) or
      ((Major = Version.VerMajor) and (Minor = Version.VerMinor) and (Release = Version.VerRelease) and (Build > Version.VerBuild));
  finally
    Version.Free;
  end;
end;

{ =============================================================================== }

{ True when the URL answers a HEAD request with a success status (redirects
  are followed by TNetHTTPClient). Network errors and 404s count as
  unavailable, which suppresses the update offer until the next check. }
function TUpdateCheck.DownloadUrlAvailable(const Url: string): Boolean;
var
  Resp: IHTTPResponse;
begin
  Result := False;
  try
    Resp := HttpClient.Head(Url);
    Result := (Resp.StatusCode >= 200) and (Resp.StatusCode <= 399);
  except
    Result := False;
  end;
end;

end.
