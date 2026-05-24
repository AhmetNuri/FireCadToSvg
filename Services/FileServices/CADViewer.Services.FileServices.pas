/// <summary>
/// CADViewer.Services.FileServices
/// Dosya yükleme, encoding tespiti ve doğrulama servisi.
/// IDxfParser ile birlikte çalışarak dosyayı yükler ve parse eder.
/// </summary>
unit CADViewer.Services.FileServices;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Math,
  System.Classes,

  CADViewer.Core.Interfaces,
  CADViewer.Core.Types;

type

  /// <summary>
  /// IFileService arayüzünü implement eden dosya servisi.
  /// Dosya okuma, encoding tespiti ve format doğrulama işlemlerini yapar.
  /// </summary>
  TFileService = class(TInterfacedObject, IFileService)
  private
    class function GetFileBytes(const AFilePath: string;
      AMaxBytes: Integer = 4096): TBytes; static;
    class function IsValidDxfContent(const AContent: string): Boolean; static;
  public
    function ValidateFile(const AFilePath: string): Boolean;
    function DetectEncoding(const AFilePath: string): TEncoding;
    function LoadFileContent(const AFilePath: string): string;
    function GetSupportedExtensions: TArray<string>;
    function GetFileSize(const AFilePath: string): Int64;
  end;

implementation

uses
  CADViewer.Utils;

{ TFileService }

class function TFileService.GetFileBytes(const AFilePath: string;
  AMaxBytes: Integer): TBytes;
var
  LStream: TFileStream;
  LSize: Integer;
begin
  LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    LSize := Min(AMaxBytes, LStream.Size);
    SetLength(Result, LSize);
    if LSize > 0 then
      LStream.ReadBuffer(Result[0], LSize);
  finally
    LStream.Free;
  end;
end;

class function TFileService.IsValidDxfContent(
  const AContent: string): Boolean;
var
  LUpper: string;
begin
  // DXF dosyasının ilk 200 karakterinde "SECTION" veya "0" group kodu beklenir
  LUpper := UpperCase(Copy(AContent, 1, 200));
  Result := (Pos('SECTION', LUpper) > 0) or
            (Pos('0'#13#10, AContent) > 0) or
            (Pos('0'#10, AContent) > 0);
end;

function TFileService.ValidateFile(const AFilePath: string): Boolean;
begin
  Result := False;

  if not TFile.Exists(AFilePath) then
    raise EFileServiceError.CreateFmt(
      'Dosya bulunamadı: "%s"', [AFilePath]);

  var LExt := LowerCase(TPath.GetExtension(AFilePath));
  if LExt = '' then
    raise EFileServiceError.CreateFmt(
      'Dosya uzantısı tanınamadı: "%s"', [AFilePath]);

  var LSupportedExts := GetSupportedExtensions;
  var LSupported := False;
  for var Ext in LSupportedExts do
    if Ext = LExt then
    begin
      LSupported := True;
      Break;
    end;

  if not LSupported then
    raise EUnsupportedFormatError.CreateFmt(
      'Desteklenmeyen dosya formatı: "%s". Desteklenen formatlar: %s',
      [LExt, string.Join(', ', LSupportedExts)]);

  if GetFileSize(AFilePath) = 0 then
    raise EFileServiceError.CreateFmt(
      'Dosya boş: "%s"', [AFilePath]);

  Result := True;
end;

function TFileService.DetectEncoding(const AFilePath: string): TEncoding;
var
  LBytes: TBytes;
  LBomEncoding: TEncoding;
  I: Integer;
  B: Byte;
  LIsUtf8: Boolean;
begin
  LBytes := GetFileBytes(AFilePath, 8192);

  // BOM kontrolü
  LBomEncoding := TDxfStringUtils.DetectBomEncoding(LBytes);
  if LBomEncoding <> nil then
    Exit(LBomEncoding);

  // DXF'te bazı yeni dosyalar "$ACADVER  1  AC1032" ile başlar
  // UTF-8 geçerlilik testi
  LIsUtf8 := True;
  I := 0;
  while I < Length(LBytes) do
  begin
    B := LBytes[I];
    if B < $80 then
    begin
      Inc(I);
      Continue;
    end;
    if (B >= $C2) and (B <= $DF) then
    begin
      if (I + 1 >= Length(LBytes)) or ((LBytes[I+1] and $C0) <> $80) then
      begin
        LIsUtf8 := False;
        Break;
      end;
      Inc(I, 2);
    end
    else if (B >= $E0) and (B <= $EF) then
    begin
      if (I + 2 >= Length(LBytes)) or
         ((LBytes[I+1] and $C0) <> $80) or
         ((LBytes[I+2] and $C0) <> $80) then
      begin
        LIsUtf8 := False;
        Break;
      end;
      Inc(I, 3);
    end
    else
    begin
      LIsUtf8 := False;
      Break;
    end;
  end;

  if LIsUtf8 then
    Result := TEncoding.UTF8
  else
    // Windows-1252 en yaygın DXF encoding
    Result := TEncoding.GetEncoding(1252);
end;

function TFileService.LoadFileContent(const AFilePath: string): string;
var
  LEncoding: TEncoding;
  LBytes: TBytes;
  LBomSize: Integer;
  LIsSystemEncoding: Boolean;
begin
  LEncoding := DetectEncoding(AFilePath);
  LIsSystemEncoding := (LEncoding <> TEncoding.UTF8) and
                       (LEncoding <> TEncoding.Unicode) and
                       (LEncoding <> TEncoding.BigEndianUnicode) and
                       (LEncoding <> TEncoding.ASCII);
  try
    if LEncoding = TEncoding.UTF8 then
    begin
      Result := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    end
    else if LEncoding = TEncoding.Unicode then
    begin
      Result := TFile.ReadAllText(AFilePath, TEncoding.Unicode);
    end
    else
    begin
      // Windows-1252 veya diğer sistemler için byte by byte oku
      LBytes := TFile.ReadAllBytes(AFilePath);
      // BOM boyutunu atla
      LBomSize := 0;
      if (Length(LBytes) >= 3) and
         (LBytes[0] = $EF) and (LBytes[1] = $BB) and (LBytes[2] = $BF) then
        LBomSize := 3
      else if (Length(LBytes) >= 2) and
              (LBytes[0] = $FF) and (LBytes[1] = $FE) then
        LBomSize := 2
      else if (Length(LBytes) >= 2) and
              (LBytes[0] = $FE) and (LBytes[1] = $FF) then
        LBomSize := 2;

      if LBomSize > 0 then
        Result := LEncoding.GetString(LBytes, LBomSize, Length(LBytes) - LBomSize)
      else
        Result := LEncoding.GetString(LBytes);
    end;
  finally
    if LIsSystemEncoding then
      LEncoding.Free;
  end;
end;

function TFileService.GetSupportedExtensions: TArray<string>;
begin
  Result := ['.dxf', '.DXF', '.step', '.STEP', '.stp', '.STP',
             '.igs', '.IGS', '.iges', '.IGES'];
end;

function TFileService.GetFileSize(const AFilePath: string): Int64;
begin
  var LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    Result := LStream.Size;
  finally
    LStream.Free;
  end;
end;

end.
