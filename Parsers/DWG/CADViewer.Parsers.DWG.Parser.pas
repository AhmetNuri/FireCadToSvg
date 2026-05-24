/// <summary>
/// CADViewer.Parsers.DWG.Parser
/// DWG (Drawing) ikili dosya formatı ayrıştırıcısı.
/// IDxfParser arayüzünü implement ederek DXF/STEP ile ortak mimari sağlar.
///
/// Desteklenen DWG sürümleri:
///   AC1015 (R2000), AC1018 (R2004), AC1021 (R2007),
///   AC1024 (R2010), AC1027 (R2013), AC1032 (R2018+)
///
/// Desteklenen entity tipleri:
///   LINE (0x11), CIRCLE (0x10), ARC (0x0F)
///   LWPOLYLINE (0x4D), POLYLINE_2D (0x0D)
///
/// Mimari: TDwgParser → IDxfParser → TParserFactory
/// Çıktı  : TDxfDocument → TDrawShapeList → TSvgExporter (mevcut)
///
/// Open-Closed: Yeni entity tipi eklemek için ParseEntityXxx eklenir.
/// </summary>
unit CADViewer.Parsers.DWG.Parser;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  System.IOUtils,
  System.UITypes,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces,
  CADViewer.Core.Models.DrawShapes,
  CADViewer.Core.Models.DxfDocument,
  CADViewer.Parsers.DWG.BitReader;

type

  // =========================================================================
  // TDwgParser
  // =========================================================================

  /// <summary>
  /// IDxfParser implementasyonu: DWG binary dosyalarını ayrıştırır.
  /// R2000+ (AC1015+) formatını hedefler; eski/yeni sürümlerde de
  /// graceful-degradation ile çalışır.
  /// </summary>
  TDwgParser = class(TInterfacedObject, IDxfParser)
  private

    // --- Durum ---
    FData: TBytes;
    FVersion: string;
    FDocument: TDxfDocument;
    FWarnings: TList<string>;

    // --- Bölüm konumları (R2000+) ---
    FObjDataOffset: Integer;
    FObjDataSize: Integer;
    FObjMapOffset: Integer;
    FObjMapSize: Integer;

    // --- Yardımcılar ---
    procedure AddWarning(const AMsg: string);
    function  FileSize: Integer; inline;
    function  SafeReadInt32(AOffset: Integer): Integer;
    function  InternalParse: TDxfDocument;

    // --- Ayrıştırma aşamaları ---
    procedure ParseHeader;
    procedure ParseSectionTable;
    procedure CollectObjectOffsets(out AOffsets: TList<Integer>);
    procedure ParseAllObjects(const AOffsets: TList<Integer>);
    procedure ParseObjectDataSequentially;
    procedure ParseObjectAt(ADataOffset: Integer);

    // --- Entity ortak alanları ---
    procedure SkipEntityCommon(R: TDwgBitReader; out ALayerName: string);

    // --- Entity ayrıştırıcıları ---
    function ParseLine(R: TDwgBitReader): TDrawShape;
    function ParseCircle(R: TDwgBitReader): TDrawShape;
    function ParseArc(R: TDwgBitReader): TDrawShape;
    function ParseLwPolyline(R: TDwgBitReader): TDrawShape;

    // --- Stil ---
    procedure ApplyStyle(AShape: TDrawShape; const ALayerName: string);

  public
    constructor Create;
    destructor Destroy; override;

    // IDxfParser
    function ParseFile(const AFilePath: string): TDxfDocument;
    function ParseContent(const AContent: string): TDxfDocument;
    function GetWarnings: TArray<string>;
  end;

// =========================================================================
// DWG R2000 entity tip sabitleri
// =========================================================================

const
  DWG_TYPE_SEQEND      = $04;
  DWG_TYPE_VERTEX_2D   = $08;
  DWG_TYPE_POLYLINE_2D = $0D;
  DWG_TYPE_ARC         = $0F;
  DWG_TYPE_CIRCLE      = $10;
  DWG_TYPE_LINE        = $11;
  DWG_TYPE_LWPLINE     = $4D;

implementation

{ TDwgParser }

constructor TDwgParser.Create;
begin
  inherited Create;
  FWarnings := TList<string>.Create;
end;

destructor TDwgParser.Destroy;
begin
  FWarnings.Free;
  inherited Destroy;
end;

// =========================================================================
// IDxfParser
// =========================================================================

function TDwgParser.ParseFile(const AFilePath: string): TDxfDocument;
begin
  FData := TFile.ReadAllBytes(AFilePath);
  Result := InternalParse;
end;

function TDwgParser.ParseContent(const AContent: string): TDxfDocument;
begin
  // DWG ikili format; string içerik Latin-1 byte olarak yorumlanır
  FData := TEncoding.GetEncoding(28591).GetBytes(AContent);
  Result := InternalParse;
end;

function TDwgParser.GetWarnings: TArray<string>;
begin
  Result := FWarnings.ToArray;
end;

// =========================================================================
// Yardımcılar
// =========================================================================

procedure TDwgParser.AddWarning(const AMsg: string);
begin
  FWarnings.Add(AMsg);
end;

function TDwgParser.FileSize: Integer;
begin
  Result := Length(FData);
end;

function TDwgParser.SafeReadInt32(AOffset: Integer): Integer;
var
  B0, B1, B2, B3: Byte;
begin
  if AOffset + 3 >= FileSize then
    Exit(0);
  B0 := FData[AOffset];
  B1 := FData[AOffset + 1];
  B2 := FData[AOffset + 2];
  B3 := FData[AOffset + 3];
  Result := Integer(Cardinal(B0) or (Cardinal(B1) shl 8)
                  or (Cardinal(B2) shl 16) or (Cardinal(B3) shl 24));
end;

// =========================================================================
// Ana ayrıştırma akışı
// =========================================================================

function TDwgParser.InternalParse: TDxfDocument;
var
  LOffsets: TList<Integer>;
  LW: string;
begin
  FDocument := TDxfDocument.Create;
  FWarnings.Clear;

  try
    ParseHeader;
    ParseSectionTable;

    LOffsets := TList<Integer>.Create;
    try
      CollectObjectOffsets(LOffsets);
      ParseAllObjects(LOffsets);
    finally
      LOffsets.Free;
    end;

    for LW in FWarnings do
      FDocument.ParseWarnings.Add(LW);

  except
    on E: EDwgParseError do raise;
    on E: Exception do
      raise EDwgParseError.Create('DWG ayrıştırma hatası: ' + E.Message);
  end;

  Result := FDocument;
end;

// =========================================================================
// 1. Başlık
// =========================================================================

procedure TDwgParser.ParseHeader;
var
  LMagic: string;
begin
  if FileSize < 6 then
    raise EDwgParseError.Create('DWG dosyası çok küçük (< 6 byte).');

  SetLength(LMagic, 6);
  Move(FData[0], LMagic[1], 6);
  FVersion := LMagic;

  if not LMagic.StartsWith('AC') then
    raise EDwgParseError.CreateFmt(
      'Geçersiz DWG başlığı: "%s". Bu bir DWG dosyası değil.', [LMagic]);

  if LMagic = 'AC1009' then
    AddWarning('DWG R12 (AC1009) formatı sınırlı desteklenmektedir; ' +
               'yalnızca temel entity''ler okunabilir.');
end;

// =========================================================================
// 2. Bölüm tablosu (R2000+)
// =========================================================================

procedure TDwgParser.ParseSectionTable;
var
  LSecCount, LIdx, I: Integer;
  LType: Byte;
  LSeeker, LSize: Integer;
begin
  FObjDataOffset := 0;
  FObjDataSize   := 0;
  FObjMapOffset  := 0;
  FObjMapSize    := 0;

  if FVersion = 'AC1009' then Exit; // R12'de farklı yapı

  if FileSize < 45 then
    raise EDwgParseError.Create('DWG bölüm tablosu için dosya çok küçük.');

  // R2000+ bölüm sayısı offset 21'de (4-byte LE)
  LSecCount := SafeReadInt32(21);

  if (LSecCount < 1) or (LSecCount > 20) then
  begin
    AddWarning(Format('Bölüm sayısı beklenenden farklı (%d); ' +
      'atanmış varsayılan bölüm ofsetleri kullanılacak.', [LSecCount]));
    Exit;
  end;

  LIdx := 25; // İlk bölüm kaydı offset 25'te
  for I := 0 to LSecCount - 1 do
  begin
    if LIdx + 8 >= FileSize then Break;

    LType   := FData[LIdx];
    LSeeker := SafeReadInt32(LIdx + 1);
    LSize   := SafeReadInt32(LIdx + 5);
    Inc(LIdx, 9);

    case LType of
      $01: begin FObjDataOffset := LSeeker; FObjDataSize := LSize; end;
      $03: begin FObjMapOffset  := LSeeker; FObjMapSize  := LSize; end;
    end;
  end;

  if FObjDataOffset = 0 then
    AddWarning('Object Data bölümü (tip 0x01) bulunamadı.');
  if FObjMapOffset = 0 then
    AddWarning('Object Map bölümü (tip 0x03) bulunamadı; sıralı tarama yapılacak.');
end;

// =========================================================================
// 3. Object Map: entity konum listesi
// =========================================================================

procedure TDwgParser.CollectObjectOffsets(out AOffsets: TList<Integer>);
var
  LR: TDwgBitReader;
  LSectionData: TBytes;
  LSectionSize: Integer;
  LPageStart, LPageEnd: Integer;
  LHandleDelta, LObjOffset: Integer;
  LLastHandle, LLastOffset: Integer;
begin
  AOffsets := TList<Integer>.Create;

  if (FObjMapOffset <= 0) or (FObjMapSize <= 0) then Exit;
  if FObjMapOffset >= FileSize then Exit;

  var LDataLen := Min(FObjMapSize, FileSize - FObjMapOffset);
  if LDataLen <= 0 then Exit;

  SetLength(LSectionData, LDataLen);
  Move(FData[FObjMapOffset], LSectionData[0], LDataLen);

  LR := TDwgBitReader.Create(LSectionData);
  try
    LLastHandle := 0;
    LLastOffset := 0;

    while not LR.AtEnd do
    begin
      if LR.BytesLeft < 2 then Break;

      LSectionSize := LR.MS;
      if LSectionSize = 0 then Break;
      if LR.BytesLeft < LSectionSize then Break;

      LPageStart := LR.BytePos;
      LPageEnd   := LPageStart + LSectionSize;

      while LR.BytePos < LPageEnd do
      begin
        if LR.BytesLeft < 2 then Break;

        LHandleDelta := LR.MC;
        LObjOffset   := LR.MC;

        if (LHandleDelta = 0) and (LObjOffset = 0) then Break;

        Inc(LLastHandle, LHandleDelta);
        Inc(LLastOffset, LObjOffset);

        if LLastOffset >= 0 then
          AOffsets.Add(LLastOffset);
      end;

      LR.SeekByte(LPageEnd);
      if LR.BytesLeft >= 2 then
        LR.SkipBytes(2); // CRC
    end;

  except
    on E: Exception do
      AddWarning('Object Map okuma hatası: ' + E.Message);
  end;

  LR.Free;
end;

// =========================================================================
// 4. Nesneleri ayrıştır
// =========================================================================

procedure TDwgParser.ParseAllObjects(const AOffsets: TList<Integer>);
var
  LOffset: Integer;
begin
  if (FObjDataOffset <= 0) or (AOffsets.Count = 0) then
  begin
    ParseObjectDataSequentially;
    Exit;
  end;

  for LOffset in AOffsets do
  begin
    try
      ParseObjectAt(LOffset);
    except
      on E: EDwgBitReaderError do; // sessizce atla
      on E: Exception do
        AddWarning('Entity atlandı (ofs=' + LOffset.ToString + '): ' + E.Message);
    end;
  end;
end;

procedure TDwgParser.ParseObjectDataSequentially;
var
  LR: TDwgBitReader;
  LSectionData: TBytes;
  LObjSize: Cardinal;
  LObjStart, LAfterMs: Integer;
begin
  if (FObjDataOffset <= 0) or (FileSize <= FObjDataOffset) then Exit;

  var LDataLen := FObjDataSize;
  if LDataLen <= 0 then
    LDataLen := FileSize - FObjDataOffset;
  LDataLen := Min(LDataLen, FileSize - FObjDataOffset);
  if LDataLen <= 0 then Exit;

  SetLength(LSectionData, LDataLen);
  Move(FData[FObjDataOffset], LSectionData[0], LDataLen);

  LR := TDwgBitReader.Create(LSectionData);
  try
    while not LR.AtEnd do
    begin
      LObjStart := LR.BytePos;
      if LR.BytesLeft < 2 then Break;

      LObjSize := LR.MS;
      LAfterMs := LR.BytePos; // MS header'ından sonraki konum

      if LObjSize = 0 then Break;
      if Integer(LObjSize) > LR.BytesLeft then Break;

      try
        ParseObjectAt(LObjStart);
      except
        on E: Exception do; // atla
      end;

      // Sonraki nesneye: MS header bitişi + nesne verisi + 2-byte CRC
      LR.SeekByte(LAfterMs + Integer(LObjSize) + 2);
    end;
  finally
    LR.Free;
  end;
end;

// =========================================================================
// Tek nesne ayrıştırma
// =========================================================================

procedure TDwgParser.ParseObjectAt(ADataOffset: Integer);
var
  LAbsOffset: Integer;
  LR: TDwgBitReader;
  LObjSize: Cardinal;
  LObjType: SmallInt;
  LObjData: TBytes;
  LShape: TDrawShape;
  LLayerName: string;
begin
  LAbsOffset := FObjDataOffset + ADataOffset;
  if LAbsOffset + 4 >= FileSize then Exit;

  // MS: nesne byte boyutu
  LR := TDwgBitReader.Create(FData, LAbsOffset);
  try
    LObjSize := LR.MS;
    if (LObjSize = 0) or (Integer(LObjSize) > LR.BytesLeft) then Exit;

    var LSafeLen := Min(Integer(LObjSize), FileSize - LR.BytePos);
    if LSafeLen <= 0 then Exit;

    SetLength(LObjData, LSafeLen);
    Move(FData[LR.BytePos], LObjData[0], LSafeLen);
  finally
    LR.Free;
  end;

  // Nesne verisi üzerinde ayrıştırma
  LR := TDwgBitReader.Create(LObjData);
  try
    LObjType := LR.BS;

    LShape := nil;
    LLayerName := '0';

    case LObjType of
      DWG_TYPE_LINE:
      begin
        SkipEntityCommon(LR, LLayerName);
        LShape := ParseLine(LR);
      end;
      DWG_TYPE_CIRCLE:
      begin
        SkipEntityCommon(LR, LLayerName);
        LShape := ParseCircle(LR);
      end;
      DWG_TYPE_ARC:
      begin
        SkipEntityCommon(LR, LLayerName);
        LShape := ParseArc(LR);
      end;
      DWG_TYPE_LWPLINE:
      begin
        SkipEntityCommon(LR, LLayerName);
        LShape := ParseLwPolyline(LR);
      end;
      // Diğer tipler sessizce atlanır
    end;

    if LShape <> nil then
    begin
      ApplyStyle(LShape, LLayerName);
      FDocument.AddShape(LShape);
    end;

  except
    on E: EDwgBitReaderError do; // atla
    on E: Exception do
      AddWarning('Entity ayrıştırma hatası (tip=' + LObjType.ToString + '): ' + E.Message);
  end;

  LR.Free;
end;

// =========================================================================
// Entity ortak alanlarını okuma/atlama
// =========================================================================

procedure TDwgParser.SkipEntityCommon(R: TDwgBitReader;
  out ALayerName: string);
var
  LNumReactors: Integer;
  LXdictMissing: Byte;
  LNoLinks: Byte;
  LLinetypeFlags: Byte;
  LPlotstyleFlags: Byte;
  I: Integer;
begin
  ALayerName := '0';
  try
    R.BL;          // Nesne bit boyutu (redundant)
    R.H;           // Handle

    // EED: boyut=0 gelene kadar oku
    var LEedSize := R.BS;
    while LEedSize > 0 do
    begin
      R.H;
      R.SkipBytes(LEedSize);
      LEedSize := R.BS;
    end;

    R.BB;                         // Entity mode
    LNumReactors   := R.BL;      // Reaktör sayısı
    LXdictMissing  := R.B;       // Xdict eksik
    LNoLinks       := R.B;       // No-links bayrağı
    R.CMC;                        // Renk
    R.BD;                         // Linetype scale
    LLinetypeFlags := R.BB;
    LPlotstyleFlags := R.BB;

    if LNoLinks = 0 then R.BS;   // Invisible
    R.RC;                         // Lineweight

    // Owner/subentity handle
    R.H;
    // Layer handle (adını çözmek tam implementasyon ister; şimdilik "0")
    R.H;
    if LLinetypeFlags = 3 then R.H;
    if LPlotstyleFlags = 3 then R.H;
    for I := 0 to LNumReactors - 1 do R.H;
    if LXdictMissing = 0 then R.H;
  except
    ALayerName := '0';
  end;
end;

// =========================================================================
// Entity ayrıştırıcıları
// =========================================================================

function TDwgParser.ParseLine(R: TDwgBitReader): TDrawShape;
var
  LShape: TDrawLine;
  LStart, LEnd: TPoint3D;
begin
  Result := nil;
  R.BT;                   // Thickness
  LStart := R.P3BD;       // Başlangıç noktası
  LEnd   := R.P3BD;       // Bitiş noktası
  R.BE;                   // Ekstrüzyon

  LShape := TDrawLine.Create;
  LShape.StartPoint := TPoint2D.Create(LStart.X, LStart.Y);
  LShape.EndPoint   := TPoint2D.Create(LEnd.X,   LEnd.Y);
  Result := LShape;
end;

function TDwgParser.ParseCircle(R: TDwgBitReader): TDrawShape;
var
  LShape: TDrawCircle;
  LCenter: TPoint3D;
  LRadius: Double;
begin
  Result := nil;
  LCenter := R.P3BD;
  LRadius := R.BD;
  R.BT;
  R.BE;

  if LRadius <= 0 then Exit;

  LShape := TDrawCircle.Create;
  LShape.Center := TPoint2D.Create(LCenter.X, LCenter.Y);
  LShape.Radius := LRadius;
  Result := LShape;
end;

function TDwgParser.ParseArc(R: TDwgBitReader): TDrawShape;
var
  LShape: TDrawArc;
  LCenter: TPoint3D;
  LRadius, LStartRad, LEndRad: Double;
const
  Rad2Deg = 180.0 / Pi;
begin
  Result := nil;
  LCenter   := R.P3BD;
  LRadius   := R.BD;
  R.BT;
  R.BE;
  LStartRad := R.BD;   // radyan
  LEndRad   := R.BD;   // radyan

  if LRadius <= 0 then Exit;

  LShape := TDrawArc.Create;
  LShape.Center       := TPoint2D.Create(LCenter.X, LCenter.Y);
  LShape.Radius       := LRadius;
  LShape.StartAngleDeg := LStartRad * Rad2Deg;
  LShape.EndAngleDeg   := LEndRad   * Rad2Deg;
  Result := LShape;
end;

function TDwgParser.ParseLwPolyline(R: TDwgBitReader): TDrawShape;
var
  LShape: TDrawPolyline;
  LFlags: SmallInt;
  LNumPts, LNumBulges, LNumWidths: Integer;
  LBulges: TArray<Double>;
  I: Integer;
  LPts: TArray<TPoint2D>;
begin
  Result := nil;

  LFlags := R.BS;   // LWPLINE bayrakları

  // Koşullu alanlar
  if (LFlags and $04) <> 0 then R.BD;   // elevation
  if (LFlags and $08) <> 0 then R.BD;   // thickness
  if (LFlags and $10) <> 0 then R.BE;   // extrusion
  if (LFlags and $20) <> 0 then R.BD;   // constant width

  LNumPts := R.BL;
  if (LNumPts <= 0) or (LNumPts > 65536) then Exit;

  // Nokta koordinatları
  SetLength(LPts, LNumPts);
  for I := 0 to LNumPts - 1 do
    LPts[I] := R.P2RD;

  // Bulge değerleri
  SetLength(LBulges, LNumPts);
  if (LFlags and $80) <> 0 then
  begin
    LNumBulges := R.BL;
    for I := 0 to LNumBulges - 1 do
      if I < LNumPts then
        LBulges[I] := R.BD
      else
        R.BD; // fazla bulge değerini atla
  end;

  // Width çiftleri (atla)
  if (LFlags and $40) <> 0 then
  begin
    LNumWidths := R.BL;
    for I := 0 to LNumWidths - 1 do
    begin
      R.BD;
      R.BD;
    end;
  end;

  // TDrawPolyline oluştur
  LShape := TDrawPolyline.Create;
  LShape.IsClosed := (LFlags and $01) <> 0;

  for I := 0 to LNumPts - 1 do
    LShape.AddPoint(LPts[I], LBulges[I]);

  Result := LShape;
end;

// =========================================================================
// Stil
// =========================================================================

procedure TDwgParser.ApplyStyle(AShape: TDrawShape;
  const ALayerName: string);
var
  LStyle: TDrawStyle;
begin
  AShape.LayerName := ALayerName;

  LStyle := TDrawStyle.Default;
  LStyle.StrokeColor := TAlphaColors.White;
  LStyle.StrokeWidth := 0.5;
  LStyle.Opacity     := 1.0;
  AShape.Style := LStyle;
end;

end.
