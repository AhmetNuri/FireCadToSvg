/// <summary>
/// CADViewer.Parsers.DXF.Parser
/// Yüksek seviye DXF ayrıştırıcı (parser).
/// IDxfReader üzerinden okunan group code/value çiftlerini
/// TDxfDocument modeline dönüştürür.
/// Desteklenen entity'ler: LINE, CIRCLE, ARC, ELLIPSE, LWPOLYLINE,
/// POLYLINE/VERTEX, TEXT, MTEXT, INSERT, DIMENSION, SPLINE, POINT.
/// Open-Closed Principle: Yeni entity tipi eklemek için
/// ParseEntityXxx metodu eklenip ParseEntities içine kayıt yeterlidir.
/// </summary>
unit CADViewer.Parsers.DXF.Parser;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces,
  CADViewer.Core.Entities,
  CADViewer.Core.Models.DrawShapes,
  CADViewer.Core.Models.DxfDocument,
  CADViewer.Parsers.DXF.Reader,
  CADViewer.Utils;

type

  /// <summary>
  /// IDxfParser arayüzünü implement eden DXF ayrıştırıcı.
  /// Template Method Pattern: ParseDocument → ParseSection → ParseXxx
  /// </summary>
  TDxfParser = class(TInterfacedObject, IDxfParser)
  private
    FReader: TDxfReader;
    FDocument: TDxfDocument;
    FWarnings: TArray<string>;
    FCurrentBlockName: string;
    FCurrentBlock: TDxfBlock;
    FInPaperSpace: Boolean;

    // --- Yardımcı okuma metodları ---

    /// <summary>Sonraki group code ve değeri okur; EOF'da False döner.</summary>
    function ReadToken(out ACode: Integer; out AValue: string): Boolean;

    /// <summary>Grup 0 = başlangıç tokenına kadar atlar (entity başını bulur).</summary>
    procedure SkipToNextEntity;

    /// <summary>Uyarı ekler.</summary>
    procedure AddWarning(const AMsg: string);

    /// <summary>DXF renk kodundan TDxfColor döndürür.</summary>
    function ParseColor(ACode: Integer; const AValue: string;
      var AColor: TDxfColor): Boolean;

    // --- Bölüm ayrıştırıcıları ---

    procedure ParseDocument;
    procedure ParseHeader;
    procedure ParseTablesSection;
    procedure ParseLayerTable;
    procedure ParseLineTypeTable;
    procedure ParseBlocksSection;
    procedure ParseEntitiesSection;

    // --- Tablo girdisi ayrıştırıcıları ---
    procedure ParseLayerEntry;
    procedure ParseLineTypeEntry;

    // --- Blok ayrıştırıcıları ---
    procedure ParseBlock;

    // --- Entity ayrıştırıcıları ---
    /// <summary>Geçerli konumdaki entity'yi ayrıştırır ve belgeye ekler.
    /// AEntityType: daha önce okunmuş entity tipi (örn: "LINE").</summary>
    procedure ParseEntity(const AEntityType: string);

    procedure ParseCommonAttribs(out ACommon: TDxfEntityCommon);
    function ParseLineEntity: TDrawShape;
    function ParseCircleEntity: TDrawShape;
    function ParseArcEntity: TDrawShape;
    function ParseEllipseEntity: TDrawShape;
    function ParseLwPolylineEntity: TDrawShape;
    function ParsePolylineEntity: TDrawShape;
    function ParseTextEntity: TDrawShape;
    function ParseMTextEntity: TDrawShape;
    function ParseInsertEntity: TDrawShape;
    function ParseDimensionEntity: TDrawShape;
    function ParseSplineEntity: TDrawShape;
    function ParsePointEntity: TDrawShape;

    // --- Dönüştürücüler (Entity → DrawShape) ---
    function BuildStyle(const ACommon: TDxfEntityCommon): TDrawStyle;
    procedure ApplyCommonToShape(AShape: TDrawShape;
      const ACommon: TDxfEntityCommon);

    // --- Blok çözümleyici ---
    /// <summary>INSERT entity'sini TDrawComposite'e dönüştürür
    /// (blok içeriğini kopyalayarak).</summary>
    function ResolveInsert(const AInsert: TDxfInsertEntity): TDrawComposite;

    // --- Yardımcılar ---
    function GetLayerEffectiveColor(const ALayerName: string): TAlphaColor;

  public
    constructor Create;
    destructor Destroy; override;

    // IDxfParser
    function ParseFile(const AFilePath: string): TDxfDocument;
    function ParseContent(const AContent: string): TDxfDocument;
    function GetWarnings: TArray<string>;
  end;

  // =========================================================================
  // TParserFactory — Factory: IDxfParser oluşturur
  // =========================================================================

  /// <summary>
  /// IParserFactory implementasyonu.
  /// Dosya uzantısına göre uygun parser'ı döndürür.
  /// Yeni format desteği için sadece bu sınıfa kayıt eklenir.
  /// </summary>
  TParserFactory = class(TInterfacedObject, IParserFactory)
  public
    function CreateParser(const AFilePath: string): IDxfParser;
    function CreateParserForFormat(AFormat: TCadFileFormat): IDxfParser;
    function DetectFormat(const AFilePath: string): TCadFileFormat;
  end;

implementation

uses
  System.IOUtils,

  CADViewer.Parsers.STEP.Parser;

// =========================================================================
// TParserFactory
// =========================================================================

function TParserFactory.DetectFormat(const AFilePath: string): TCadFileFormat;
var
  LExt: string;
begin
  LExt := LowerCase(TPath.GetExtension(AFilePath));
  if LExt = '.dxf' then Result := TCadFileFormat.ffDxf
  else if LExt = '.dwg' then Result := TCadFileFormat.ffDwg
  else if (LExt = '.igs') or (LExt = '.iges') then Result := TCadFileFormat.ffIges
  else if (LExt = '.stp') or (LExt = '.step') then Result := TCadFileFormat.ffStep
  else Result := TCadFileFormat.ffUnknown;
end;

function TParserFactory.CreateParser(const AFilePath: string): IDxfParser;
begin
  Result := CreateParserForFormat(DetectFormat(AFilePath));
end;

function TParserFactory.CreateParserForFormat(
  AFormat: TCadFileFormat): IDxfParser;
begin
  case AFormat of
    TCadFileFormat.ffDxf:
      Result := TDxfParser.Create;
    TCadFileFormat.ffDwg:
      raise EUnsupportedFormatError.Create(
        'DWG format desteği henüz eklenmemiştir.');
    TCadFileFormat.ffIges:
      raise EUnsupportedFormatError.Create(
        'IGES format desteği henüz eklenmemiştir.');
    TCadFileFormat.ffStep:
      Result := TStepParser.Create;
    else
      raise EUnsupportedFormatError.Create(
        'Bilinmeyen veya desteklenmeyen dosya formatı.');
  end;
end;

// =========================================================================
// TDxfParser
// =========================================================================

constructor TDxfParser.Create;
begin
  inherited Create;
  FReader := TDxfReader.Create;
end;

destructor TDxfParser.Destroy;
begin
  FReader.Free;
  // FDocument dışarıya döndürüldüğünden burada serbest bırakılmaz
  inherited Destroy;
end;

function TDxfParser.ParseFile(const AFilePath: string): TDxfDocument;
begin
  FReader.OpenFile(AFilePath);
  try
    FDocument := TDxfDocument.Create;
    FDocument.FilePath := AFilePath;
    FDocument.FileName := TPath.GetFileName(AFilePath);
    try
      ParseDocument;
    except
      FDocument.Free;
      FDocument := nil;
      raise;
    end;
    Result := FDocument;
    FDocument := nil; // Sahipliği caller'a bırak
  finally
    FReader.Close;
  end;
end;

function TDxfParser.ParseContent(const AContent: string): TDxfDocument;
begin
  FReader.OpenContent(AContent);
  try
    FDocument := TDxfDocument.Create;
    FDocument.FileName := 'İçerik';
    try
      ParseDocument;
    except
      FDocument.Free;
      FDocument := nil;
      raise;
    end;
    Result := FDocument;
    FDocument := nil;
  finally
    FReader.Close;
  end;
end;

function TDxfParser.GetWarnings: TArray<string>;
begin
  Result := FWarnings;
end;

function TDxfParser.ReadToken(out ACode: Integer;
  out AValue: string): Boolean;
begin
  Result := FReader.ReadNext(ACode, AValue);
end;

procedure TDxfParser.AddWarning(const AMsg: string);
var
  L: Integer;
begin
  L := Length(FWarnings);
  SetLength(FWarnings, L + 1);
  FWarnings[L] := Format('[Satır %d] %s', [FReader.CurrentLine, AMsg]);
  if FDocument <> nil then
    FDocument.ParseWarnings.Add(FWarnings[L]);
end;

procedure TDxfParser.SkipToNextEntity;
var
  Code: Integer;
  Value: string;
begin
  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      // Geri it; ParseEntity bunu okuyacak
      var Token: TDxfToken;
      Token.GroupCode := 0;
      Token.Value := Value;
      FReader.PushBack(Token);
      Exit;
    end;
  end;
end;

function TDxfParser.ParseColor(ACode: Integer; const AValue: string;
  var AColor: TDxfColor): Boolean;
begin
  Result := True;
  case ACode of
    62: // ACI renk kodu
    begin
      var N := TDxfStringUtils.TryParseInt(AValue, 256);
      if N = 256 then AColor := TDxfColor.ByLayer
      else if N = 0 then AColor := TDxfColor.ByBlock
      else AColor := TDxfColor.FromAci(N);
    end;
    420: // TrueColor (0xRRGGBB)
    begin
      var N := TDxfStringUtils.TryParseInt(AValue, 0);
      AColor := TDxfColor.FromRgb(
        (N shr 16) and $FF,
        (N shr 8)  and $FF,
        N and $FF);
    end;
    else Result := False;
  end;
end;

// -------------------------------------------------------------------------
// Ana ayrıştırma akışı
// -------------------------------------------------------------------------

procedure TDxfParser.ParseDocument;
var
  Code: Integer;
  Value: string;
begin
  while ReadToken(Code, Value) do
  begin
    if (Code = 0) and (Value = 'SECTION') then
    begin
      // Bölüm adını oku
      if ReadToken(Code, Value) and (Code = 2) then
      begin
        if Value = 'HEADER' then
          ParseHeader
        else if Value = 'TABLES' then
          ParseTablesSection
        else if Value = 'BLOCKS' then
          ParseBlocksSection
        else if Value = 'ENTITIES' then
          ParseEntitiesSection
        // CLASSES ve OBJECTS bölümleri şimdilik atlanır
      end;
    end
    else if (Code = 0) and (Value = 'EOF') then
      Break;
  end;
end;

// -------------------------------------------------------------------------
// HEADER bölümü
// -------------------------------------------------------------------------

procedure TDxfParser.ParseHeader;
var
  Code: Integer;
  Value: string;
  LVarName: string;
  LVars: TDxfHeaderVars;
begin
  LVars := FDocument.HeaderVars;

  while ReadToken(Code, Value) do
  begin
    // Bölüm sonu
    if (Code = 0) and (Value = 'ENDSEC') then Break;

    // Değişken adı
    if Code = 9 then
    begin
      LVarName := Value;
      Continue;
    end;

    // Değişken değerlerini ata
    if LVarName = '$ACADVER' then
    begin
      if Code = 1 then LVars.AcadVersion := Value;
    end
    else if LVarName = '$INSUNITS' then
    begin
      if Code = 70 then LVars.InsUnits := TDxfStringUtils.TryParseInt(Value);
    end
    else if LVarName = '$EXTMIN' then
    begin
      case Code of
        10: LVars.ExtMin.X := TDxfStringUtils.TryParseDouble(Value);
        20: LVars.ExtMin.Y := TDxfStringUtils.TryParseDouble(Value);
        30: LVars.ExtMin.Z := TDxfStringUtils.TryParseDouble(Value);
      end;
      LVars.HasExtents := True;
    end
    else if LVarName = '$EXTMAX' then
    begin
      case Code of
        10: LVars.ExtMax.X := TDxfStringUtils.TryParseDouble(Value);
        20: LVars.ExtMax.Y := TDxfStringUtils.TryParseDouble(Value);
        30: LVars.ExtMax.Z := TDxfStringUtils.TryParseDouble(Value);
      end;
      LVars.HasExtents := True;
    end
    else if LVarName = '$LIMMIN' then
    begin
      case Code of
        10: LVars.LimMin.X := TDxfStringUtils.TryParseDouble(Value);
        20: LVars.LimMin.Y := TDxfStringUtils.TryParseDouble(Value);
      end;
    end
    else if LVarName = '$LIMMAX' then
    begin
      case Code of
        10: LVars.LimMax.X := TDxfStringUtils.TryParseDouble(Value);
        20: LVars.LimMax.Y := TDxfStringUtils.TryParseDouble(Value);
      end;
    end
    else if LVarName = '$CLAYER' then
    begin
      if Code = 8 then LVars.CurrentLayer := Value;
    end
    else if LVarName = '$TEXTSIZE' then
    begin
      if Code = 40 then LVars.TextSize := TDxfStringUtils.TryParseDouble(Value);
    end
    else if LVarName = '$LTSCALE' then
    begin
      if Code = 40 then LVars.LtScale := TDxfStringUtils.TryParseDouble(Value, 1.0);
    end;
  end;

  FDocument.HeaderVars := LVars;
end;

// -------------------------------------------------------------------------
// TABLES bölümü
// -------------------------------------------------------------------------

procedure TDxfParser.ParseTablesSection;
var
  Code: Integer;
  Value: string;
begin
  while ReadToken(Code, Value) do
  begin
    if (Code = 0) and (Value = 'ENDSEC') then Break;

    if (Code = 0) and (Value = 'TABLE') then
    begin
      // Tablo tipini oku
      if ReadToken(Code, Value) and (Code = 2) then
      begin
        if Value = 'LAYER' then ParseLayerTable
        else if Value = 'LTYPE' then ParseLineTypeTable;
        // STYLE, DIMSTYLE vb. atlanır
      end;
    end;
  end;
end;

procedure TDxfParser.ParseLayerTable;
var
  Code: Integer;
  Value: string;
begin
  while ReadToken(Code, Value) do
  begin
    if (Code = 0) and (Value = 'ENDTAB') then Break;
    if (Code = 0) and (Value = 'LAYER') then ParseLayerEntry;
  end;
end;

procedure TDxfParser.ParseLayerEntry;
var
  Code: Integer;
  Value: string;
  LName: string;
  LColor: TDxfColor;
  LLType: string;
  LFlags: Integer;
  LIsOffFromColor: Boolean;
  LLineWeight: Integer;
  LLayer: TDxfLayerInfo;
begin
  LName := '';
  LColor := TDxfColor.ByLayer;
  LLType := 'CONTINUOUS';
  LFlags := 0;
  LIsOffFromColor := False;
  LLineWeight := TDxfLineWeight.Default;

  while ReadToken(Code, Value) do
  begin
    // Bir sonraki tablo girişi başladıysa geri it
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0;
      Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;

    case Code of
      2:  LName := TDxfStringUtils.CleanDxfString(Value);
      62:
      begin
        var N := TDxfStringUtils.TryParseInt(Value, 7);
        if N < 0 then
        begin
          LIsOffFromColor := True;
          N := Abs(N);
        end;
        LColor := TDxfColor.FromAci(N);
      end;
      6:  LLType := TDxfStringUtils.CleanDxfString(Value);
      70: LFlags := TDxfStringUtils.TryParseInt(Value);
      370: LLineWeight := TDxfStringUtils.TryParseInt(Value, TDxfLineWeight.Default);
    end;
  end;

  if LName = '' then Exit;

  LLayer := FDocument.EnsureLayer(LName);
  LLayer.Color := LColor;
  LLayer.LineTypeName := LLType;
  LLayer.LineWeight := LLineWeight;
  LLayer.IsOff := LIsOffFromColor or ((LFlags and 1) <> 0);
  LLayer.Frozen := (LFlags and 4) <> 0;
  LLayer.Locked := (LFlags and 16) <> 0;
  LLayer.Plottable := (LFlags and 512) = 0;
end;

procedure TDxfParser.ParseLineTypeTable;
var
  Code: Integer;
  Value: string;
begin
  while ReadToken(Code, Value) do
  begin
    if (Code = 0) and (Value = 'ENDTAB') then Break;
    if (Code = 0) and (Value = 'LTYPE') then ParseLineTypeEntry;
  end;
end;

procedure TDxfParser.ParseLineTypeEntry;
var
  Code: Integer;
  Value: string;
  LName, LDesc: string;
  LPatternCount: Integer;
  LPattern: TArray<Double>;
  LPIdx: Integer;
  LLType: TDxfLineTypeInfo;
begin
  LName := '';
  LDesc := '';
  LPatternCount := 0;
  LPIdx := 0;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0;
      Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;

    case Code of
      2:  LName := TDxfStringUtils.CleanDxfString(Value);
      3:  LDesc := Value;
      73:
      begin
        LPatternCount := TDxfStringUtils.TryParseInt(Value);
        SetLength(LPattern, LPatternCount);
        LPIdx := 0;
      end;
      49: // Pattern element (+ = çizgi, - = boşluk, 0 = nokta)
      begin
        if LPIdx < LPatternCount then
        begin
          LPattern[LPIdx] := TDxfStringUtils.TryParseDouble(Value);
          Inc(LPIdx);
        end;
      end;
    end;
  end;

  if LName = '' then Exit;

  LLType := FDocument.EnsureLineType(LName);
  LLType.Description := LDesc;
  LLType.Pattern := LPattern;
end;

// -------------------------------------------------------------------------
// BLOCKS bölümü
// -------------------------------------------------------------------------

procedure TDxfParser.ParseBlocksSection;
var
  Code: Integer;
  Value: string;
begin
  while ReadToken(Code, Value) do
  begin
    if (Code = 0) and (Value = 'ENDSEC') then Break;
    if (Code = 0) and (Value = 'BLOCK') then ParseBlock;
  end;
end;

procedure TDxfParser.ParseBlock;
var
  Code: Integer;
  Value: string;
  LName: string;
  LBase: TPoint3D;
  LBlock: TDxfBlock;
begin
  LName := '';
  LBase := TPoint3D.Zero;
  FCurrentBlock := nil;

  // Blok başlık özelliklerini oku (BLOCK entity'si)
  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0;
      Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      2:  LName := TDxfStringUtils.CleanDxfString(Value);
      10: LBase.X := TDxfStringUtils.TryParseDouble(Value);
      20: LBase.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LBase.Z := TDxfStringUtils.TryParseDouble(Value);
    end;
  end;

  if LName = '' then LName := '_UNNAMED';

  // Paper space bloğunu atla (*Paper_Space vb.)
  FInPaperSpace := Pos('PAPER_SPACE', UpperCase(LName)) > 0;

  LBlock := FDocument.EnsureBlock(LName);
  LBlock.BasePoint := LBase.To2D;
  FCurrentBlock := LBlock;
  FCurrentBlockName := LName;

  // Blok içindeki entity'leri oku
  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      if Value = 'ENDBLK' then
      begin
        // ENDBLK entity'sini tüket
        while ReadToken(Code, Value) do
          if Code = 0 then
          begin
            var Token: TDxfToken;
            Token.GroupCode := 0;
            Token.Value := Value;
            FReader.PushBack(Token);
            Break;
          end;
        Break;
      end;
      ParseEntity(Value);
    end;
  end;

  FCurrentBlock := nil;
  FCurrentBlockName := '';
  FInPaperSpace := False;
end;

// -------------------------------------------------------------------------
// ENTITIES bölümü
// -------------------------------------------------------------------------

procedure TDxfParser.ParseEntitiesSection;
var
  Code: Integer;
  Value: string;
begin
  FCurrentBlock := nil;
  FCurrentBlockName := '';
  FInPaperSpace := False;

  while ReadToken(Code, Value) do
  begin
    if (Code = 0) and (Value = 'ENDSEC') then Break;
    if Code = 0 then
      ParseEntity(Value);
  end;
end;

// -------------------------------------------------------------------------
// Entity ayrıştırma dispatcher
// -------------------------------------------------------------------------

procedure TDxfParser.ParseEntity(const AEntityType: string);
var
  LShape: TDrawShape;
begin
  LShape := nil;
  try
    if      AEntityType = 'LINE'       then LShape := ParseLineEntity
    else if AEntityType = 'CIRCLE'     then LShape := ParseCircleEntity
    else if AEntityType = 'ARC'        then LShape := ParseArcEntity
    else if AEntityType = 'ELLIPSE'    then LShape := ParseEllipseEntity
    else if AEntityType = 'LWPOLYLINE' then LShape := ParseLwPolylineEntity
    else if AEntityType = 'POLYLINE'   then LShape := ParsePolylineEntity
    else if AEntityType = 'TEXT'       then LShape := ParseTextEntity
    else if AEntityType = 'MTEXT'      then LShape := ParseMTextEntity
    else if AEntityType = 'INSERT'     then LShape := ParseInsertEntity
    else if AEntityType = 'DIMENSION'  then LShape := ParseDimensionEntity
    else if AEntityType = 'SPLINE'     then LShape := ParseSplineEntity
    else if AEntityType = 'POINT'      then LShape := ParsePointEntity
    else
    begin
      // Bilinmeyen entity: sonraki entity başına kadar atla
      SkipToNextEntity;
      Exit;
    end;

    if LShape = nil then Exit;

    FDocument.IncrementEntityCount;

    if FCurrentBlock <> nil then
      FCurrentBlock.Shapes.Add(LShape)
    else if FInPaperSpace then
      FDocument.AddPaperSpaceShape(LShape)
    else
      FDocument.AddShape(LShape);

  except
    on E: Exception do
    begin
      AddWarning(Format('%s entity ayrıştırma hatası: %s',
        [AEntityType, E.Message]));
      LShape.Free; // Hata durumunda serbest bırak
      SkipToNextEntity;
    end;
  end;
end;

// -------------------------------------------------------------------------
// Ortak özellik okuyucu
// -------------------------------------------------------------------------

procedure TDxfParser.ParseCommonAttribs(out ACommon: TDxfEntityCommon);
begin
  // Çağrılmadan önce ortak alanları sıfırla
  FillChar(ACommon, SizeOf(ACommon), 0);
  ACommon.ColorNumber := 256; // ByLayer varsayılan
  ACommon.Visible := True;
  ACommon.LtScale := 1.0;
end;

function TDxfParser.BuildStyle(const ACommon: TDxfEntityCommon): TDrawStyle;
var
  LLayerColor: TAlphaColor;
begin
  Result := TDrawStyle.Default;
  LLayerColor := GetLayerEffectiveColor(ACommon.LayerName);

  // TrueColor (420) varsa öncelikli
  if ACommon.TrueColorRgb <> 0 then
    Result.StrokeColor := TDxfColor.FromRgb(
      (ACommon.TrueColorRgb shr 16) and $FF,
      (ACommon.TrueColorRgb shr 8)  and $FF,
       ACommon.TrueColorRgb         and $FF).RgbValue
  else
    Result.StrokeColor := TAciColorTable.ResolveColor(
      TDxfColor.FromAci(ACommon.ColorNumber), LLayerColor);

  // Çizgi kalınlığı (mils → ekran pikseli yaklaşımı)
  if ACommon.LineWeight > 0 then
    Result.StrokeWidth := Max(1.0, ACommon.LineWeight / 100.0)
  else
    Result.StrokeWidth := 1.0;

  Result.Opacity := 1.0 - ACommon.Transparency;
  if Result.Opacity < 0 then Result.Opacity := 1.0;

  // Çizgi tipi
  var LLType := ACommon.LineTypeName;
  if LLType = '' then LLType := 'CONTINUOUS';
  if SameText(LLType, 'DASHED') or SameText(LLType, 'DASHED2') then
    Result.LineType := TDxfLineType.ltDashed
  else if SameText(LLType, 'DOTTED') then
    Result.LineType := TDxfLineType.ltDotted
  else if SameText(LLType, 'DASHDOT') or SameText(LLType, 'DASHDOT2') then
    Result.LineType := TDxfLineType.ltDashDot
  else if SameText(LLType, 'CENTER') or SameText(LLType, 'CENTER2') then
    Result.LineType := TDxfLineType.ltCenter
  else if SameText(LLType, 'HIDDEN') or SameText(LLType, 'HIDDEN2') then
    Result.LineType := TDxfLineType.ltHidden
  else if SameText(LLType, 'PHANTOM') then
    Result.LineType := TDxfLineType.ltPhantom
  else
    Result.LineType := TDxfLineType.ltContinuous;

  Result.LtScale := ACommon.LtScale;
end;

procedure TDxfParser.ApplyCommonToShape(AShape: TDrawShape;
  const ACommon: TDxfEntityCommon);
begin
  AShape.LayerName := ACommon.LayerName;
  AShape.Handle    := ACommon.Handle;
  AShape.Visible   := ACommon.Visible and (ACommon.SpaceFlag = 0);
  AShape.Style     := BuildStyle(ACommon);
end;

function TDxfParser.GetLayerEffectiveColor(
  const ALayerName: string): TAlphaColor;
var
  LLayer: TDxfLayerInfo;
begin
  LLayer := FDocument.FindLayer(ALayerName);
  if LLayer <> nil then
    Result := TAciColorTable.GetColor(LLayer.Color.AciIndex)
  else
    Result := TAlphaColors.White;
end;

// -------------------------------------------------------------------------
// LINE
// -------------------------------------------------------------------------

function TDxfParser.ParseLineEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LP1, LP2: TPoint3D;
  LShape: TDrawLine;
begin
  ParseCommonAttribs(LCommon);
  LP1 := TPoint3D.Zero;
  LP2 := TPoint3D.Zero;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      370:LCommon.LineWeight := TDxfStringUtils.TryParseInt(Value);
      48: LCommon.LtScale := TDxfStringUtils.TryParseDouble(Value, 1.0);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LP1.X := TDxfStringUtils.TryParseDouble(Value);
      20: LP1.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LP1.Z := TDxfStringUtils.TryParseDouble(Value);
      11: LP2.X := TDxfStringUtils.TryParseDouble(Value);
      21: LP2.Y := TDxfStringUtils.TryParseDouble(Value);
      31: LP2.Z := TDxfStringUtils.TryParseDouble(Value);
    end;
  end;

  LShape := TDrawLine.Create;
  LShape.StartPoint := LP1.To2D;
  LShape.EndPoint   := LP2.To2D;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// CIRCLE
// -------------------------------------------------------------------------

function TDxfParser.ParseCircleEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LCenter: TPoint3D;
  LRadius: Double;
  LShape: TDrawCircle;
begin
  ParseCommonAttribs(LCommon);
  LCenter := TPoint3D.Zero;
  LRadius := 0;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      370:LCommon.LineWeight := TDxfStringUtils.TryParseInt(Value);
      48: LCommon.LtScale := TDxfStringUtils.TryParseDouble(Value, 1.0);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LCenter.X := TDxfStringUtils.TryParseDouble(Value);
      20: LCenter.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LCenter.Z := TDxfStringUtils.TryParseDouble(Value);
      40: LRadius := TDxfStringUtils.TryParseDouble(Value);
    end;
  end;

  LShape := TDrawCircle.Create;
  LShape.Center := LCenter.To2D;
  LShape.Radius := LRadius;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// ARC
// -------------------------------------------------------------------------

function TDxfParser.ParseArcEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LCenter: TPoint3D;
  LRadius, LStartAng, LEndAng: Double;
  LShape: TDrawArc;
begin
  ParseCommonAttribs(LCommon);
  LCenter := TPoint3D.Zero;
  LRadius := 0; LStartAng := 0; LEndAng := 360;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      370:LCommon.LineWeight := TDxfStringUtils.TryParseInt(Value);
      48: LCommon.LtScale := TDxfStringUtils.TryParseDouble(Value, 1.0);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LCenter.X := TDxfStringUtils.TryParseDouble(Value);
      20: LCenter.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LCenter.Z := TDxfStringUtils.TryParseDouble(Value);
      40: LRadius := TDxfStringUtils.TryParseDouble(Value);
      50: LStartAng := TDxfStringUtils.TryParseDouble(Value);
      51: LEndAng := TDxfStringUtils.TryParseDouble(Value);
    end;
  end;

  LShape := TDrawArc.Create;
  LShape.Center        := LCenter.To2D;
  LShape.Radius        := LRadius;
  LShape.StartAngleDeg := LStartAng;
  LShape.EndAngleDeg   := LEndAng;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// ELLIPSE
// -------------------------------------------------------------------------

function TDxfParser.ParseEllipseEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LCenter, LMajorEnd: TPoint3D;
  LRatio, LStartP, LEndP: Double;
  LShape: TDrawEllipse;
begin
  ParseCommonAttribs(LCommon);
  LCenter := TPoint3D.Zero;
  LMajorEnd := TPoint3D.Zero;
  LRatio := 1.0;
  LStartP := 0.0;
  LEndP := 2 * Pi;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      370:LCommon.LineWeight := TDxfStringUtils.TryParseInt(Value);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LCenter.X := TDxfStringUtils.TryParseDouble(Value);
      20: LCenter.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LCenter.Z := TDxfStringUtils.TryParseDouble(Value);
      11: LMajorEnd.X := TDxfStringUtils.TryParseDouble(Value);
      21: LMajorEnd.Y := TDxfStringUtils.TryParseDouble(Value);
      31: LMajorEnd.Z := TDxfStringUtils.TryParseDouble(Value);
      40: LRatio := TDxfStringUtils.TryParseDouble(Value, 1.0);
      41: LStartP := TDxfStringUtils.TryParseDouble(Value);
      42: LEndP := TDxfStringUtils.TryParseDouble(Value, 2 * Pi);
    end;
  end;

  LShape := TDrawEllipse.Create;
  LShape.Center := LCenter.To2D;
  LShape.MajorAxisEnd := LMajorEnd.To2D;
  LShape.MinorToMajorRatio := LRatio;
  LShape.StartParam := LStartP;
  LShape.EndParam := LEndP;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// LWPOLYLINE
// -------------------------------------------------------------------------

function TDxfParser.ParseLwPolylineEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LFlags, LVertexCount: Integer;
  LCurrentX: Double;
  LHasX: Boolean;
  LBulge: Double;
  LShape: TDrawPolyline;
begin
  ParseCommonAttribs(LCommon);
  LFlags := 0;
  LVertexCount := 0;
  LCurrentX := 0;
  LHasX := False;
  LBulge := 0;

  LShape := TDrawPolyline.Create;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      370:LCommon.LineWeight := TDxfStringUtils.TryParseInt(Value);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      70: LFlags := TDxfStringUtils.TryParseInt(Value);
      90: LVertexCount := TDxfStringUtils.TryParseInt(Value);
      10: // X koordinatı: yeni vertex başlıyor
      begin
        if LHasX then
        begin
          // Önceki X için Y gelmediyse son eklenen vertex'in X'i güncelle
        end;
        LCurrentX := TDxfStringUtils.TryParseDouble(Value);
        LHasX := True;
        LBulge := 0; // Her vertex için bulge sıfırlanır
      end;
      20: // Y koordinatı: vertex tamamlandı
      begin
        if LHasX then
        begin
          LShape.AddPoint(
            TPoint2D.Create(LCurrentX, TDxfStringUtils.TryParseDouble(Value)),
            LBulge);
          LHasX := False;
        end;
      end;
      42: // Bulge: bir sonraki segment için (X'ten önce veya sonra gelebilir)
      begin
        LBulge := TDxfStringUtils.TryParseDouble(Value);
        // Eğer zaten point eklendiyse son noktanın bulge'ını güncelle
        if LShape.PointCount > 0 then
        begin
          var LPoints := LShape.Points;
          LPoints[High(LPoints)].Bulge := LBulge;
          LShape.Points := LPoints;
        end;
      end;
    end;
  end;

  LShape.IsClosed := (LFlags and 1) <> 0;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// POLYLINE (eski format) + VERTEX entity'leri
// -------------------------------------------------------------------------

function TDxfParser.ParsePolylineEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LFlags: Integer;
  LShape: TDrawPolyline;
  LVertX, LVertY: Double;
  LBulge: Double;
  LHaveVertex: Boolean;
begin
  ParseCommonAttribs(LCommon);
  LFlags := 0;

  // POLYLINE header özelliklerini oku
  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      70: LFlags := TDxfStringUtils.TryParseInt(Value);
    end;
  end;

  LShape := TDrawPolyline.Create;
  LShape.IsClosed := (LFlags and 1) <> 0;

  // VERTEX entity'lerini oku
  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      if Value = 'SEQEND' then
      begin
        // SEQEND entity'sini tüket
        while ReadToken(Code, Value) do
          if Code = 0 then
          begin
            var Token: TDxfToken;
            Token.GroupCode := 0; Token.Value := Value;
            FReader.PushBack(Token);
            Break;
          end;
        Break;
      end
      else if Value = 'VERTEX' then
      begin
        LVertX := 0; LVertY := 0; LBulge := 0;
        LHaveVertex := False;
        // VERTEX entity'sini oku
        while ReadToken(Code, Value) do
        begin
          if Code = 0 then
          begin
            var Token: TDxfToken;
            Token.GroupCode := 0; Token.Value := Value;
            FReader.PushBack(Token);
            Break;
          end;
          case Code of
            10: begin LVertX := TDxfStringUtils.TryParseDouble(Value); LHaveVertex := True; end;
            20: LVertY := TDxfStringUtils.TryParseDouble(Value);
            42: LBulge := TDxfStringUtils.TryParseDouble(Value);
          end;
        end;
        if LHaveVertex then
          LShape.AddPoint(TPoint2D.Create(LVertX, LVertY), LBulge);
      end
      else
      begin
        var Token: TDxfToken;
        Token.GroupCode := 0; Token.Value := Value;
        FReader.PushBack(Token);
        Break;
      end;
    end;
  end;

  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// TEXT
// -------------------------------------------------------------------------

function TDxfParser.ParseTextEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LInsert: TPoint3D;
  LHeight, LRotation, LWidthFactor, LObliqueAngle: Double;
  LContent, LStyleName: string;
  LHAlign, LVAlign, LFlags: Integer;
  LShape: TDrawText;
begin
  ParseCommonAttribs(LCommon);
  LInsert := TPoint3D.Zero;
  LHeight := 0; LRotation := 0; LWidthFactor := 1.0; LObliqueAngle := 0;
  LHAlign := 0; LVAlign := 0; LFlags := 0;
  LContent := ''; LStyleName := 'STANDARD';

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LInsert.X := TDxfStringUtils.TryParseDouble(Value);
      20: LInsert.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LInsert.Z := TDxfStringUtils.TryParseDouble(Value);
      40: LHeight := TDxfStringUtils.TryParseDouble(Value);
      1:  LContent := TDxfStringUtils.CleanDxfString(Value);
      50: LRotation := TDxfStringUtils.TryParseDouble(Value);
      41: LWidthFactor := TDxfStringUtils.TryParseDouble(Value, 1.0);
      51: LObliqueAngle := TDxfStringUtils.TryParseDouble(Value);
      7:  LStyleName := Value;
      72: LHAlign := TDxfStringUtils.TryParseInt(Value);
      73: LVAlign := TDxfStringUtils.TryParseInt(Value);
      71: LFlags := TDxfStringUtils.TryParseInt(Value);
    end;
  end;

  LShape := TDrawText.Create;
  LShape.Position     := LInsert.To2D;
  LShape.Content      := TDxfMathUtils.DecodeDxfText(LContent);
  LShape.FontHeight   := Max(0.001, LHeight);
  LShape.RotationDeg  := LRotation;
  LShape.WidthFactor  := Max(0.01, LWidthFactor);
  LShape.ObliqueAngle := LObliqueAngle;
  LShape.FontName     := LStyleName;
  LShape.IsMText      := False;
  case LHAlign of
    0: LShape.HAlign := TDxfTextHAlign.haLeft;
    1: LShape.HAlign := TDxfTextHAlign.haCenter;
    2: LShape.HAlign := TDxfTextHAlign.haRight;
    3: LShape.HAlign := TDxfTextHAlign.haAligned;
    4: LShape.HAlign := TDxfTextHAlign.haMiddle;
    5: LShape.HAlign := TDxfTextHAlign.haFit;
  end;
  case LVAlign of
    0: LShape.VAlign := TDxfTextVAlign.vaBaseline;
    1: LShape.VAlign := TDxfTextVAlign.vaBottom;
    2: LShape.VAlign := TDxfTextVAlign.vaMiddle;
    3: LShape.VAlign := TDxfTextVAlign.vaTop;
  end;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// MTEXT
// -------------------------------------------------------------------------

function TDxfParser.ParseMTextEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LInsert: TPoint3D;
  LHeight, LRectWidth, LRotation: Double;
  LContent: string;
  LStyleName: string;
  LAttach: Integer;
  LShape: TDrawText;
begin
  ParseCommonAttribs(LCommon);
  LInsert := TPoint3D.Zero;
  LHeight := 0; LRectWidth := 0; LRotation := 0;
  LContent := ''; LStyleName := 'STANDARD'; LAttach := 1;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LInsert.X := TDxfStringUtils.TryParseDouble(Value);
      20: LInsert.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LInsert.Z := TDxfStringUtils.TryParseDouble(Value);
      40: LHeight := TDxfStringUtils.TryParseDouble(Value);
      41: LRectWidth := TDxfStringUtils.TryParseDouble(Value);
      50: LRotation := TDxfStringUtils.TryParseDouble(Value);
      1, 3: LContent := LContent + Value; // 3 = ek metin parçaları
      7:  LStyleName := Value;
      71: LAttach := TDxfStringUtils.TryParseInt(Value, 1);
    end;
  end;

  LShape := TDrawText.Create;
  LShape.Position   := LInsert.To2D;
  LShape.Content    := TDxfMathUtils.CleanMText(LContent);
  LShape.FontHeight := Max(0.001, LHeight);
  LShape.RotationDeg := LRotation;
  LShape.FontName   := LStyleName;
  LShape.IsMText    := True;
  LShape.RectWidth  := LRectWidth;
  // Hizalama (attachment point 1-9)
  case LAttach of
    1, 2, 3: LShape.VAlign := TDxfTextVAlign.vaTop;
    4, 5, 6: LShape.VAlign := TDxfTextVAlign.vaMiddle;
    7, 8, 9: LShape.VAlign := TDxfTextVAlign.vaBottom;
  end;
  case ((LAttach - 1) mod 3) of
    0: LShape.HAlign := TDxfTextHAlign.haLeft;
    1: LShape.HAlign := TDxfTextHAlign.haCenter;
    2: LShape.HAlign := TDxfTextHAlign.haRight;
  end;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// INSERT
// -------------------------------------------------------------------------

function TDxfParser.ParseInsertEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LBlockName: string;
  LInsert: TPoint3D;
  LScaleX, LScaleY, LScaleZ, LRotation: Double;
  LComposite: TDrawComposite;
begin
  ParseCommonAttribs(LCommon);
  LBlockName := '';
  LInsert := TPoint3D.Zero;
  LScaleX := 1.0; LScaleY := 1.0; LScaleZ := 1.0;
  LRotation := 0;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      420:LCommon.TrueColorRgb := TDxfStringUtils.TryParseInt(Value);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      2:  LBlockName := TDxfStringUtils.CleanDxfString(Value);
      10: LInsert.X := TDxfStringUtils.TryParseDouble(Value);
      20: LInsert.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LInsert.Z := TDxfStringUtils.TryParseDouble(Value);
      41: LScaleX := TDxfStringUtils.TryParseDouble(Value, 1.0);
      42: LScaleY := TDxfStringUtils.TryParseDouble(Value, 1.0);
      43: LScaleZ := TDxfStringUtils.TryParseDouble(Value, 1.0);
      50: LRotation := TDxfStringUtils.TryParseDouble(Value);
    end;
  end;

  // Blok referansını çözümle ve TDrawComposite oluştur
  var LInsertRec: TDxfInsertEntity;
  LInsertRec.Common := LCommon;
  LInsertRec.BlockName := LBlockName;
  LInsertRec.InsertionPoint := LInsert;
  LInsertRec.ScaleX := LScaleX;
  LInsertRec.ScaleY := LScaleY;
  LInsertRec.ScaleZ := LScaleZ;
  LInsertRec.Rotation := LRotation;

  LComposite := ResolveInsert(LInsertRec);
  ApplyCommonToShape(LComposite, LCommon);
  Result := LComposite;
end;

function TDxfParser.ResolveInsert(
  const AInsert: TDxfInsertEntity): TDrawComposite;
var
  LBlock: TDxfBlock;
  LComposite: TDrawComposite;
begin
  LComposite := TDrawComposite.Create;
  LComposite.InsertionPoint := AInsert.InsertionPoint.To2D;
  LComposite.ScaleX := AInsert.ScaleX;
  LComposite.ScaleY := AInsert.ScaleY;
  LComposite.RotationDeg := AInsert.Rotation;
  LComposite.BlockName := AInsert.BlockName;

  // Blok tanımı varsa çocuk şekilleri referans olarak ekle
  // NOT: Gerçek uygulamada klonlama gerekir; basitlik için referans kullanılır.
  // Büyük projeler için blok şekilleri runtime'da transform ile render edilmeli.
  LBlock := FDocument.FindBlock(AInsert.BlockName);
  if LBlock <> nil then
  begin
    // Blok şekillerini direkt composite'e eklemeyiz (ownership sorunu).
    // Bunun yerine renderer, composite'in BlockName'ini okuyarak
    // FDocument.Blocks'tan çeker ve transform uygular.
  end
  else
    AddWarning(Format('Blok bulunamadı: %s', [AInsert.BlockName]));

  Result := LComposite;
end;

// -------------------------------------------------------------------------
// DIMENSION
// -------------------------------------------------------------------------

function TDxfParser.ParseDimensionEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LBlockName: string;
  LComposite: TDrawComposite;
begin
  ParseCommonAttribs(LCommon);
  LBlockName := '';

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      2:  LBlockName := TDxfStringUtils.CleanDxfString(Value); // Çizim bloğu
    end;
  end;

  // DIMENSION genellikle anonim bir blok referansı içerir (*Dxxx)
  // Bu bloğu INSERT gibi çöz
  var LInsertRec: TDxfInsertEntity;
  FillChar(LInsertRec, SizeOf(LInsertRec), 0);
  LInsertRec.Common := LCommon;
  LInsertRec.BlockName := LBlockName;
  LInsertRec.ScaleX := 1.0;
  LInsertRec.ScaleY := 1.0;
  LInsertRec.ScaleZ := 1.0;

  LComposite := ResolveInsert(LInsertRec);
  ApplyCommonToShape(LComposite, LCommon);
  Result := LComposite;
end;

// -------------------------------------------------------------------------
// SPLINE
// -------------------------------------------------------------------------

function TDxfParser.ParseSplineEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LDegree, LKnotCount, LCtrlCount: Integer;
  LFlags: Integer;
  LKnots: TArray<Double>;
  LCtrlPoints: TArray<TPoint3D>;
  LKnotIdx, LCtrlIdx: Integer;
  LCurrentX, LCurrentY, LCurrentZ: Double;
  LHaveX: Boolean;
  LApprox: TArray<TPoint2D>;
  LCtrl2D: TArray<TPoint2D>;
  LShape: TDrawPath;
  I: Integer;
begin
  ParseCommonAttribs(LCommon);
  LDegree := 3; LKnotCount := 0; LCtrlCount := 0; LFlags := 0;
  LKnotIdx := 0; LCtrlIdx := 0;
  LCurrentX := 0; LCurrentY := 0; LCurrentZ := 0;
  LHaveX := False;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      if LHaveX and (LCtrlIdx < LCtrlCount) then
      begin
        LCtrlPoints[LCtrlIdx].X := LCurrentX;
        LCtrlPoints[LCtrlIdx].Y := LCurrentY;
        LCtrlPoints[LCtrlIdx].Z := LCurrentZ;
        Inc(LCtrlIdx);
        LHaveX := False;
      end;

      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      6:  LCommon.LineTypeName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      70: LFlags := TDxfStringUtils.TryParseInt(Value);
      71: LDegree := Max(1, TDxfStringUtils.TryParseInt(Value, 3));
      72:
      begin
        LKnotCount := TDxfStringUtils.TryParseInt(Value);
        SetLength(LKnots, LKnotCount);
      end;
      73:
      begin
        LCtrlCount := TDxfStringUtils.TryParseInt(Value);
        SetLength(LCtrlPoints, LCtrlCount);
      end;
      40: // Knot değeri
      begin
        if LKnotIdx < LKnotCount then
        begin
          LKnots[LKnotIdx] := TDxfStringUtils.TryParseDouble(Value);
          Inc(LKnotIdx);
        end;
      end;
      10:
      begin
        if LHaveX and (LCtrlIdx < LCtrlCount) then
        begin
          LCtrlPoints[LCtrlIdx].X := LCurrentX;
          LCtrlPoints[LCtrlIdx].Y := LCurrentY;
          LCtrlPoints[LCtrlIdx].Z := LCurrentZ;
          Inc(LCtrlIdx);
        end;
        LCurrentX := TDxfStringUtils.TryParseDouble(Value);
        LCurrentY := 0; LCurrentZ := 0;
        LHaveX := True;
      end;
      20: LCurrentY := TDxfStringUtils.TryParseDouble(Value);
      30:
      begin
        LCurrentZ := TDxfStringUtils.TryParseDouble(Value);
        if LHaveX and (LCtrlIdx < LCtrlCount) then
        begin
          LCtrlPoints[LCtrlIdx].X := LCurrentX;
          LCtrlPoints[LCtrlIdx].Y := LCurrentY;
          LCtrlPoints[LCtrlIdx].Z := LCurrentZ;
          Inc(LCtrlIdx);
          LHaveX := False;
        end;
      end;
    end;
  end;

  if LHaveX and (LCtrlIdx < LCtrlCount) then
  begin
    LCtrlPoints[LCtrlIdx].X := LCurrentX;
    LCtrlPoints[LCtrlIdx].Y := LCurrentY;
    LCtrlPoints[LCtrlIdx].Z := LCurrentZ;
    Inc(LCtrlIdx);
  end;

  // Kontrol noktalarını 2D'ye çevir
  SetLength(LCtrl2D, LCtrlIdx);
  for I := 0 to LCtrlIdx - 1 do
    LCtrl2D[I] := LCtrlPoints[I].To2D;

  // B-spline yaklaşımı
  var LSampleCount := Max(10, LCtrlIdx * 10);
  LApprox := TDxfMathUtils.ApproximateSpline(LCtrl2D, LKnots, LDegree,
    LSampleCount);

  LShape := TDrawPath.Create;
  LShape.Points := LApprox;
  LShape.IsClosed := (LFlags and 1) <> 0;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

// -------------------------------------------------------------------------
// POINT
// -------------------------------------------------------------------------

function TDxfParser.ParsePointEntity: TDrawShape;
var
  Code: Integer;
  Value: string;
  LCommon: TDxfEntityCommon;
  LPos: TPoint3D;
  LShape: TDrawPoint;
begin
  ParseCommonAttribs(LCommon);
  LPos := TPoint3D.Zero;

  while ReadToken(Code, Value) do
  begin
    if Code = 0 then
    begin
      var Token: TDxfToken;
      Token.GroupCode := 0; Token.Value := Value;
      FReader.PushBack(Token);
      Break;
    end;
    case Code of
      5:  LCommon.Handle := Value;
      8:  LCommon.LayerName := Value;
      62: LCommon.ColorNumber := TDxfStringUtils.TryParseInt(Value, 256);
      60: LCommon.Visible := TDxfStringUtils.TryParseInt(Value) = 0;
      67: LCommon.SpaceFlag := TDxfStringUtils.TryParseInt(Value);
      10: LPos.X := TDxfStringUtils.TryParseDouble(Value);
      20: LPos.Y := TDxfStringUtils.TryParseDouble(Value);
      30: LPos.Z := TDxfStringUtils.TryParseDouble(Value);
    end;
  end;

  LShape := TDrawPoint.Create;
  LShape.Position := LPos.To2D;
  ApplyCommonToShape(LShape, LCommon);
  Result := LShape;
end;

end.
