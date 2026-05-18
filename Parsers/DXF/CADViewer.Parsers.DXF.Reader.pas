/// <summary>
/// CADViewer.Parsers.DXF.Reader
/// Düşük seviye DXF grup kodu okuyucu.
/// DXF dosyasını (group code, value) çiftleri (token) olarak okur.
/// Encoding tespiti ve BOM desteği bu sınıfta yer alır.
/// Single Responsibility: Sadece ham token okur; hiç yorumlamaz.
/// </summary>
unit CADViewer.Parsers.DXF.Reader;

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  CADViewer.Core.Interfaces,
  CADViewer.Utils;

type

  /// <summary>
  /// Bir DXF okuma tokenı: group code ve değer çifti.
  /// </summary>
  TDxfToken = record
    GroupCode: Integer;
    Value: string;
    LineNumber: Integer;
  end;

  /// <summary>
  /// IDxfReader arayüzünü implement eden somut okuyucu sınıfı.
  /// Dosya veya string içeriğinden satır satır okur.
  /// Otomatik encoding tespiti (BOM, ANSI, UTF-8) yapar.
  /// Peek/pushback mekanizması ile parser'a kolaylık sağlar.
  /// </summary>
  TDxfReader = class(TInterfacedObject, IDxfReader)
  private
    FLines: TArray<string>;   // Tüm satırlar belleğe alınır (DXF dosyaları çoğunlukla sığar)
    FCurrentIndex: Integer;   // Sonraki okunacak satır indeksi
    FLineNumber: Integer;     // Kullanıcıya gösterilen satır numarası
    FPushedBack: Boolean;     // Geri itilmiş token var mı?
    FPushedToken: TDxfToken;  // Geri itilmiş token

    function ReadRawLine(out ALine: string): Boolean;
    procedure LoadLines(const AContent: string);
    function DetectEncoding(const AFilePath: string): TEncoding;
    function TrimDxfLine(const ALine: string): string; inline;
  public
    constructor Create;
    destructor Destroy; override;

    // IDxfReader implementasyonu
    procedure OpenFile(const AFilePath: string);
    procedure OpenContent(const AContent: string);
    procedure Close;
    function ReadNext(out AGroupCode: Integer; out AValue: string): Boolean;
    function IsEof: Boolean;
    function CurrentLine: Integer;

    /// <summary>Son okunan tokeni geri iter (tek seviye look-ahead).</summary>
    procedure PushBack(const AToken: TDxfToken);

    /// <summary>Bir sonraki tokeni peek eder (tüketmez).</summary>
    function PeekNext(out AToken: TDxfToken): Boolean;
  end;

implementation

{ TDxfReader }

constructor TDxfReader.Create;
begin
  inherited Create;
  FCurrentIndex := 0;
  FLineNumber   := 0;
  FPushedBack   := False;
end;

destructor TDxfReader.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TDxfReader.TrimDxfLine(const ALine: string): string;
begin
  // DXF satırlarında baştaki/sondaki boşluk ve CR/LF karakterleri temizlenir
  Result := Trim(ALine);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
  Result := StringReplace(Result, #0,  '', [rfReplaceAll]);
end;

function TDxfReader.DetectEncoding(const AFilePath: string): TEncoding;
var
  LBytes: TBytes;
  LBomEncoding: TEncoding;
  LStream: TFileStream;
  LHeaderSize: Integer;
  LIsUtf8: Boolean;
  I: Integer;
  B: Byte;
begin
  // İlk 4096 baytı oku
  LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    LHeaderSize := Min(4096, LStream.Size);
    SetLength(LBytes, LHeaderSize);
    LStream.ReadBuffer(LBytes[0], LHeaderSize);
  finally
    LStream.Free;
  end;

  // BOM kontrolü
  LBomEncoding := TDxfStringUtils.DetectBomEncoding(LBytes);
  if LBomEncoding <> nil then
    Exit(LBomEncoding);

  // DXF dosyalarında "$ACADVER" veya "0\nSECTION" gibi ASCII içerik var
  // UTF-8 geçerlilik kontrolü: 0x80 üzeri baytlar varsa UTF-8 mi ANSI mi?
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
    // Multi-byte UTF-8 dizisi beklentisi
    if (B >= $C2) and (B <= $DF) then
    begin
      // 2-byte: 10xxxxxx
      if (I + 1 >= Length(LBytes)) or ((LBytes[I+1] and $C0) <> $80) then
      begin
        LIsUtf8 := False;
        Break;
      end;
      Inc(I, 2);
    end
    else if (B >= $E0) and (B <= $EF) then
    begin
      // 3-byte
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
    // Windows-1252 (Latin-1 üst seti) en yaygın DXF encoding'i
    Result := TEncoding.GetEncoding(1252);
end;

procedure TDxfReader.LoadLines(const AContent: string);
begin
  // Satırlara böl (CR+LF, LF veya CR)
  FLines := AContent.Split([#13#10, #10, #13]);
  FCurrentIndex := 0;
  FLineNumber   := 0;
  FPushedBack   := False;
end;

procedure TDxfReader.OpenFile(const AFilePath: string);
var
  LEncoding: TEncoding;
  LContent: string;
  LBytes: TBytes;
  LBom: Integer;
begin
  if not TFile.Exists(AFilePath) then
    raise EFileServiceError.CreateFmt('Dosya bulunamadı: %s', [AFilePath]);

  LEncoding := DetectEncoding(AFilePath);
  try
    // BOM varsa TFile.ReadAllText zaten yönetir
    if LEncoding = TEncoding.UTF8 then
      LContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8)
    else
    begin
      LBytes := TFile.ReadAllBytes(AFilePath);
      // BOM baytlarını atla
      LBom := 0;
      if (Length(LBytes) >= 3) and
         (LBytes[0] = $EF) and (LBytes[1] = $BB) and (LBytes[2] = $BF) then
        LBom := 3
      else if (Length(LBytes) >= 2) and
              (LBytes[0] = $FF) and (LBytes[1] = $FE) then
        LBom := 2;
      if LBom > 0 then
        LContent := LEncoding.GetString(LBytes, LBom, Length(LBytes) - LBom)
      else
        LContent := LEncoding.GetString(LBytes);
    end;
  finally
    // GetEncoding ile oluşturulan encoding serbest bırakılır
    if (LEncoding <> TEncoding.UTF8) and
       (LEncoding <> TEncoding.Unicode) and
       (LEncoding <> TEncoding.BigEndianUnicode) then
      LEncoding.Free;
  end;

  LoadLines(LContent);
end;

procedure TDxfReader.OpenContent(const AContent: string);
begin
  LoadLines(AContent);
end;

procedure TDxfReader.Close;
begin
  FLines := nil;
  FCurrentIndex := 0;
  FLineNumber   := 0;
  FPushedBack   := False;
end;

function TDxfReader.ReadRawLine(out ALine: string): Boolean;
begin
  if FCurrentIndex >= Length(FLines) then
  begin
    ALine := '';
    Result := False;
    Exit;
  end;
  ALine := FLines[FCurrentIndex];
  Inc(FCurrentIndex);
  Inc(FLineNumber);
  Result := True;
end;

function TDxfReader.ReadNext(out AGroupCode: Integer;
  out AValue: string): Boolean;
var
  LCodeStr: string;
  LLine1, LLine2: string;
begin
  // Geri itilmiş token kontrolü
  if FPushedBack then
  begin
    AGroupCode := FPushedToken.GroupCode;
    AValue     := FPushedToken.Value;
    FPushedBack := False;
    Result := True;
    Exit;
  end;

  // Boş satırları atla, sonra ilk satır = group code
  repeat
    if not ReadRawLine(LLine1) then
    begin
      AGroupCode := -1;
      AValue := '';
      Result := False;
      Exit;
    end;
    LLine1 := TrimDxfLine(LLine1);
  until LLine1 <> '';

  // Group code satırını integer'a çevir
  if not TryStrToInt(LLine1, AGroupCode) then
  begin
    // Geçersiz group code: dosya bozuk olabilir, yine de devam et
    AGroupCode := -1;
    AValue := LLine1;
    Result := True;
    Exit;
  end;

  // Değer satırını oku (boş değerler geçerlidir)
  if not ReadRawLine(LLine2) then
  begin
    AValue := '';
    Result := True; // Son token group code'u zaten okundu
    Exit;
  end;
  AValue := TrimDxfLine(LLine2);
  Result := True;
end;

function TDxfReader.IsEof: Boolean;
begin
  Result := (not FPushedBack) and (FCurrentIndex >= Length(FLines));
end;

function TDxfReader.CurrentLine: Integer;
begin
  Result := FLineNumber;
end;

procedure TDxfReader.PushBack(const AToken: TDxfToken);
begin
  FPushedToken := AToken;
  FPushedBack  := True;
end;

function TDxfReader.PeekNext(out AToken: TDxfToken): Boolean;
var
  LCode: Integer;
  LValue: string;
begin
  Result := ReadNext(LCode, LValue);
  if Result then
  begin
    AToken.GroupCode   := LCode;
    AToken.Value       := LValue;
    AToken.LineNumber  := FLineNumber;
    PushBack(AToken);
  end;
end;

end.
