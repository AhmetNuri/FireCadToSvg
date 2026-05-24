/// <summary>
/// CADViewer.Parsers.STEP.Parser
/// STEP (ISO 10303-21) dosyalarını ayrıştıran parser.
/// IDxfParser arayüzünü implement ederek DXF ile ortak mimari sağlar.
///
/// Desteklenen entity tipleri:
///   - CARTESIAN_POINT, DIRECTION, VECTOR
///   - AXIS2_PLACEMENT_2D, AXIS2_PLACEMENT_3D
///   - LINE, CIRCLE, ELLIPSE
///   - TRIMMED_CURVE  (LINE/CIRCLE/ELLIPSE üzerinde yay/segment)
///   - B_SPLINE_CURVE_WITH_KNOTS ve türevleri (yaklaşık polyline)
///   - POLYLINE
///   - EDGE_CURVE, VERTEX_POINT
///   - GEOMETRIC_CURVE_SET
///   - GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION
///
/// Koordinat sistemi: 3D noktalar XY düzlemine yansıtılır.
/// Open-Closed Principle: Yeni entity tipini desteklemek için
/// ilgili Build* metodu eklenir; mevcut kod değiştirilmez.
/// </summary>
unit CADViewer.Parsers.STEP.Parser;

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
  CADViewer.Core.Models.DxfDocument;

type

  /// <summary>
  /// STEP placement (koordinat sistemi) tanımı.
  /// AXIS2_PLACEMENT_2D ve AXIS2_PLACEMENT_3D entity'lerinden üretilir.
  /// </summary>
  TStepPlacement = record
    Location: TPoint3D;  // Orijin noktası
    ZAxis: TPoint3D;     // Normal vektörü (default 0,0,1)
    XAxis: TPoint3D;     // Referans X yönü (default 1,0,0)
  end;

  /// <summary>
  /// STEP (ISO 10303-21) dosyalarını ayrıştıran parser.
  /// IDxfParser arayüzünü implement ederek DXF ile ortak mimari sağlar.
  /// </summary>
  TStepParser = class(TInterfacedObject, IDxfParser)
  private type
    /// <summary>
    /// DATA bölümünden okunan ham entity verisi.
    /// TypeName: büyük harf entity adı (örn. 'CIRCLE').
    /// RawParams: dış parantezler arasındaki ham içerik.
    /// </summary>
    TEntityData = record
      TypeName: string;
      RawParams: string;
    end;

  private
    FEntities: TDictionary<Integer, TEntityData>;
    FDocument: TDxfDocument;
    FWarnings: TArray<string>;
    FConverted: TDictionary<Integer, Boolean>;

    // -----------------------------------------------------------------------
    // Faz 1: Ham entity tarama
    // -----------------------------------------------------------------------

    /// <summary>STEP DATA bölümünü tarar ve FEntities sözlüğünü doldurur.</summary>
    procedure ScanDataSection(const AContent: string);

    // -----------------------------------------------------------------------
    // Parametre yardımcı metotları
    // -----------------------------------------------------------------------

    /// <summary>
    /// Üst seviye virgüllerden böler (iç içe parantez ve string gözetilir).
    /// Örnek: "a, (b,c), 'd'" → ["a", "(b,c)", "'d'"]
    /// </summary>
    class function SplitTopLevel(const AStr: string): TArray<string>; static;

    /// <summary>"#123" → 123; geçerli değilse -1 döner.</summary>
    class function ParseRef(const S: string): Integer; static;

    /// <summary>"3.14" veya "-2E-5" → Double; başarısızsa False döner.</summary>
    class function ParseNum(const S: string; out V: Double): Boolean; static;

    /// <summary>"(a, b, c)" → ["a", "b", "c"]; geçersiz listede [] döner.</summary>
    class function UnwrapList(const S: string): TArray<string>; static;

    /// <summary>".T." / ".TRUE." → True; diğerleri → False.</summary>
    class function ParseBool(const S: string): Boolean; static;

    // -----------------------------------------------------------------------
    // Entity veri erişimi
    // -----------------------------------------------------------------------

    function GetEntityData(AId: Integer; out AData: TEntityData): Boolean; inline;
    function GetEntityParams(AId: Integer; out ATypeName: string;
      out AParams: TArray<string>): Boolean;

    // -----------------------------------------------------------------------
    // Geometri çözücüler
    // -----------------------------------------------------------------------

    /// <summary>CARTESIAN_POINT entity'sini TPoint3D'ye çevirir.</summary>
    function GetPoint(AId: Integer): TPoint3D;

    /// <summary>DIRECTION entity'sini birim vektöre çevirir.</summary>
    function GetDirection(AId: Integer): TPoint3D;

    /// <summary>AXIS2_PLACEMENT_2D veya AXIS2_PLACEMENT_3D'yi TStepPlacement'a çevirir.</summary>
    function GetPlacement(AId: Integer): TStepPlacement;

    /// <summary>VERTEX_POINT entity'sinden TPoint3D döndürür.</summary>
    function GetVertexPoint(AId: Integer): TPoint3D;

    // -----------------------------------------------------------------------
    // Şekil oluşturucular
    // -----------------------------------------------------------------------

    /// <summary>EDGE_CURVE entity'sini TDrawShape'e dönüştürür.</summary>
    function BuildEdgeCurve(AId: Integer): TDrawShape;

    /// <summary>
    /// Verilen eğri entity'sini başlangıç/bitiş köşe noktalarıyla sınırlı
    /// TDrawShape'e dönüştürür.
    /// </summary>
    function BuildCurveSegment(ACurveId: Integer;
      const AP1, AP2: TPoint3D; AHasVertices: Boolean): TDrawShape;

    /// <summary>TRIMMED_CURVE entity'sini TDrawShape'e dönüştürür.</summary>
    function BuildTrimmedCurve(AId: Integer): TDrawShape;

    /// <summary>POLYLINE entity'sini TDrawPolyline'a dönüştürür.</summary>
    function BuildPolyline(AId: Integer): TDrawShape;

    /// <summary>
    /// B_SPLINE_CURVE (ve türevleri) entity'sini kontrol noktalarını
    /// kullanan yaklaşık TDrawPath'e dönüştürür.
    /// </summary>
    function BuildBSplineCurve(AId: Integer): TDrawShape;

    /// <summary>Bağımsız bir CIRCLE entity'sini dönüştürür.</summary>
    function BuildStandaloneCircle(AId: Integer): TDrawShape;

    /// <summary>Placement ve yarıçaptan TDrawCircle oluşturur.</summary>
    function BuildCircleShape(const APlacement: TStepPlacement;
      ARadius: Double): TDrawShape;

    /// <summary>
    /// Elips parametrelerinden TDrawEllipse oluşturur.
    /// AStartParam, AEndParam: radyan cinsinden parametre değerleri.
    /// </summary>
    function BuildEllipticArc(const APlacement: TStepPlacement;
      ASemiAxis1, ASemiAxis2: Double;
      AStartParam, AEndParam: Double): TDrawShape;

    /// <summary>
    /// Merkez, yarıçap ve açılardan TDrawArc veya TDrawCircle oluşturur.
    /// AZAxis: placement normali; negatif Z için açılar yansıtılır.
    /// </summary>
    function BuildArcOrCircle(const ACenter: TPoint3D;
      ARadius: Double; AStartDeg, AEndDeg: Double;
      const AZAxis: TPoint3D): TDrawShape;

    // -----------------------------------------------------------------------
    // Üst seviye traversal
    // -----------------------------------------------------------------------

    /// <summary>
    /// GEOMETRIC_CURVE_SET veya GBWSR entity'sindeki eğrileri
    /// gezerek şekillere dönüştürür. Başarılıysa True döner.
    /// </summary>
    function TryResolveSetOrWireframe(AId: Integer): Boolean;

    /// <summary>
    /// Faz 2: Tüm entity'leri gezerek geometriyi belgeye ekler.
    /// Önce kök küme/wireframe entity'lerini dener; bulamazsa
    /// EDGE_CURVE ve primitiflere geri düşer.
    /// </summary>
    procedure ResolveGeometry;

    // -----------------------------------------------------------------------
    // Yardımcılar
    // -----------------------------------------------------------------------

    function MakeDefaultStyle: TDrawStyle;
    procedure AddShape(AShape: TDrawShape);
    procedure AddWarning(const AMsg: string);

  public
    constructor Create;
    destructor Destroy; override;

    // IDxfParser
    function ParseFile(const AFilePath: string): TDxfDocument;
    function ParseContent(const AContent: string): TDxfDocument;
    function GetWarnings: TArray<string>;
  end;

implementation

const
  STEP_DEFAULT_LAYER = '0';

// ===========================================================================
// Constructor / Destructor
// ===========================================================================

constructor TStepParser.Create;
begin
  inherited Create;
  FEntities  := TDictionary<Integer, TEntityData>.Create;
  FConverted := TDictionary<Integer, Boolean>.Create;
end;

destructor TStepParser.Destroy;
begin
  FConverted.Free;
  FEntities.Free;
  // FDocument çağırana döndürüldüğünden burada serbest bırakılmaz
  inherited Destroy;
end;

// ===========================================================================
// IDxfParser implementasyonu
// ===========================================================================

function TStepParser.ParseFile(const AFilePath: string): TDxfDocument;
var
  LContent: string;
begin
  // UTF-8 tercih edilir; başarısız olursa Windows-1252 dene
  try
    LContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
  except
    LContent := TFile.ReadAllText(AFilePath, TEncoding.GetEncoding(1252));
  end;
  Result := ParseContent(LContent);
  Result.FilePath := AFilePath;
  Result.FileName := TPath.GetFileName(AFilePath);
end;

function TStepParser.ParseContent(const AContent: string): TDxfDocument;
begin
  FEntities.Clear;
  FConverted.Clear;
  FWarnings := [];

  FDocument := TDxfDocument.Create;
  FDocument.EnsureLayer(STEP_DEFAULT_LAYER);

  ScanDataSection(AContent);
  ResolveGeometry;

  Result    := FDocument;
  FDocument := nil; // sahiplik çağırana geçiyor
end;

function TStepParser.GetWarnings: TArray<string>;
begin
  Result := FWarnings;
end;

// ===========================================================================
// Faz 1: DATA bölümü tarama
// ===========================================================================

procedure TStepParser.ScanDataSection(const AContent: string);
var
  I, N: Integer;
  C: Char;
  EntityId: Integer;
  TypeName, ParamsStr, IdStr: string;
  DepthParen: Integer;
  InString: Boolean;
  Data: TEntityData;
  DataPos: Integer;
begin
  N := Length(AContent);

  // DATA; bölümünü bul
  DataPos := Pos('DATA;', AContent);
  if DataPos = 0 then DataPos := Pos('DATA ;', AContent);
  if DataPos = 0 then
  begin
    AddWarning('STEP DATA bölümü bulunamadı.');
    Exit;
  end;
  I := DataPos + 5; // 'DATA;' geçtik

  while I <= N do
  begin
    C := AContent[I];

    // Beyaz boşlukları atla
    if C in [' ', #9, #13, #10] then
    begin
      Inc(I);
      Continue;
    end;

    // /* ... */ yorumlarını atla
    if (C = '/') and (I < N) and (AContent[I + 1] = '*') then
    begin
      Inc(I, 2);
      while I < N do
      begin
        if (AContent[I] = '*') and (AContent[I + 1] = '/') then
        begin
          Inc(I, 2);
          Break;
        end;
        Inc(I);
      end;
      Continue;
    end;

    // ENDSEC kontrolü
    if (I + 5 <= N) and
       (AContent[I]   = 'E') and (AContent[I+1] = 'N') and
       (AContent[I+2] = 'D') and (AContent[I+3] = 'S') and
       (AContent[I+4] = 'E') and (AContent[I+5] = 'C') then
      Break;

    // Entity bildirimi: #ID = TYPE_NAME(params);
    if C = '#' then
    begin
      Inc(I);

      // ID oku
      IdStr := '';
      while (I <= N) and (AContent[I] in ['0'..'9']) do
      begin
        IdStr := IdStr + AContent[I];
        Inc(I);
      end;
      if IdStr = '' then Continue;
      if not TryStrToInt(IdStr, EntityId) then Continue;

      // '=' geç
      while (I <= N) and (AContent[I] in [' ', #9, #13, #10]) do Inc(I);
      if (I <= N) and (AContent[I] = '=') then Inc(I);
      while (I <= N) and (AContent[I] in [' ', #9, #13, #10]) do Inc(I);

      // Tip adı oku (harfler, rakamlar, alt çizgi)
      TypeName := '';
      while (I <= N) and (AContent[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      begin
        TypeName := TypeName + AContent[I];
        Inc(I);
      end;
      TypeName := UpperCase(TypeName);

      // Beyaz boşluğu geç, '(' bekle
      while (I <= N) and (AContent[I] in [' ', #9, #13, #10]) do Inc(I);

      if (I > N) or (AContent[I] <> '(') then
      begin
        // Geçersiz bildirim; ';' a kadar atla
        while (I <= N) and (AContent[I] <> ';') do Inc(I);
        if I <= N then Inc(I);
        Continue;
      end;
      Inc(I); // '(' geç

      // Parametre içeriğini oku (iç içe parantez ve stringleri izle)
      ParamsStr   := '';
      DepthParen  := 1;
      InString    := False;

      while (I <= N) and (DepthParen > 0) do
      begin
        C := AContent[I];

        if InString then
        begin
          if C = '''' then
          begin
            // Escaped single quote?
            if (I < N) and (AContent[I + 1] = '''') then
            begin
              ParamsStr := ParamsStr + '''';
              Inc(I, 2);
              Continue;
            end;
            InString := False;
          end;
          ParamsStr := ParamsStr + C;
          Inc(I);
          Continue;
        end;

        case C of
          '''': begin InString := True;    ParamsStr := ParamsStr + C; end;
          '(':  begin Inc(DepthParen);     ParamsStr := ParamsStr + C; end;
          ')':  begin
            Dec(DepthParen);
            if DepthParen > 0 then ParamsStr := ParamsStr + C;
          end;
          else  ParamsStr := ParamsStr + C;
        end;
        Inc(I);
      end;

      // ';' a kadar atla
      while (I <= N) and (AContent[I] <> ';') do Inc(I);
      if I <= N then Inc(I);

      if TypeName <> '' then
      begin
        Data.TypeName  := TypeName;
        Data.RawParams := Trim(ParamsStr);
        FEntities.AddOrSetValue(EntityId, Data);
      end;
    end
    else
      Inc(I);
  end;
end;

// ===========================================================================
// Parametre yardımcı metotları
// ===========================================================================

class function TStepParser.SplitTopLevel(const AStr: string): TArray<string>;
var
  Items: TList<string>;
  I, N, StartPos, Depth: Integer;
  C: Char;
  InStr: Boolean;
begin
  Items := TList<string>.Create;
  try
    N        := Length(AStr);
    I        := 1;
    StartPos := 1;
    Depth    := 0;
    InStr    := False;

    while I <= N do
    begin
      C := AStr[I];

      if InStr then
      begin
        if C = '''' then
        begin
          if (I < N) and (AStr[I + 1] = '''') then
          begin
            Inc(I, 2);
            Continue;
          end;
          InStr := False;
        end;
        Inc(I);
        Continue;
      end;

      case C of
        '''': InStr := True;
        '(':  Inc(Depth);
        ')':  Dec(Depth);
        ',':
          if Depth = 0 then
          begin
            Items.Add(Trim(Copy(AStr, StartPos, I - StartPos)));
            StartPos := I + 1;
          end;
      end;
      Inc(I);
    end;

    var LLast := Trim(Copy(AStr, StartPos, N - StartPos + 1));
    if LLast <> '' then
      Items.Add(LLast);

    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

class function TStepParser.ParseRef(const S: string): Integer;
var
  T: string;
begin
  T := Trim(S);
  if (Length(T) >= 2) and (T[1] = '#') then
  begin
    if not TryStrToInt(Copy(T, 2, MaxInt), Result) then
      Result := -1;
  end
  else
    Result := -1;
end;

class function TStepParser.ParseNum(const S: string; out V: Double): Boolean;
begin
  Result := TryStrToFloat(Trim(S), V, TFormatSettings.Invariant);
end;

class function TStepParser.UnwrapList(const S: string): TArray<string>;
var
  T: string;
begin
  T := Trim(S);
  if (Length(T) >= 2) and (T[1] = '(') and (T[Length(T)] = ')') then
    Result := SplitTopLevel(Copy(T, 2, Length(T) - 2))
  else
    Result := [];
end;

class function TStepParser.ParseBool(const S: string): Boolean;
var
  U: string;
begin
  U := UpperCase(Trim(S));
  Result := (U = '.T.') or (U = '.TRUE.');
end;

function TStepParser.GetEntityData(AId: Integer; out AData: TEntityData): Boolean;
begin
  Result := FEntities.TryGetValue(AId, AData);
end;

function TStepParser.GetEntityParams(AId: Integer; out ATypeName: string;
  out AParams: TArray<string>): Boolean;
var
  LData: TEntityData;
begin
  Result := FEntities.TryGetValue(AId, LData);
  if Result then
  begin
    ATypeName := LData.TypeName;
    AParams   := SplitTopLevel(LData.RawParams);
  end;
end;

// ===========================================================================
// Geometri çözücüler
// ===========================================================================

function TStepParser.GetPoint(AId: Integer): TPoint3D;
var
  LTypeName: string;
  LParams, LCoords: TArray<string>;
  V: Double;
begin
  Result := TPoint3D.Zero;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if (LTypeName <> 'CARTESIAN_POINT') and (LTypeName <> 'POINT') then Exit;
  if Length(LParams) < 2 then Exit;

  // CARTESIAN_POINT('name', (x [, y [, z]]))
  LCoords := UnwrapList(LParams[1]);
  if (Length(LCoords) >= 1) and ParseNum(LCoords[0], V) then Result.X := V;
  if (Length(LCoords) >= 2) and ParseNum(LCoords[1], V) then Result.Y := V;
  if (Length(LCoords) >= 3) and ParseNum(LCoords[2], V) then Result.Z := V;
end;

function TStepParser.GetDirection(AId: Integer): TPoint3D;
var
  LTypeName: string;
  LParams, LCoords: TArray<string>;
  V: Double;
begin
  Result.X := 0; Result.Y := 0; Result.Z := 1; // varsayılan
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if LTypeName <> 'DIRECTION' then Exit;
  if Length(LParams) < 2 then Exit;

  // DIRECTION('name', (dx, dy [, dz]))
  LCoords := UnwrapList(LParams[1]);
  Result.X := 0; Result.Y := 0; Result.Z := 0;
  if (Length(LCoords) >= 1) and ParseNum(LCoords[0], V) then Result.X := V;
  if (Length(LCoords) >= 2) and ParseNum(LCoords[1], V) then Result.Y := V;
  if (Length(LCoords) >= 3) and ParseNum(LCoords[2], V) then Result.Z := V;
end;

function TStepParser.GetPlacement(AId: Integer): TStepPlacement;
var
  LTypeName: string;
  LParams: TArray<string>;
  LRefId: Integer;
begin
  // Varsayılan değerler
  Result.Location := TPoint3D.Zero;
  Result.ZAxis.X  := 0; Result.ZAxis.Y := 0; Result.ZAxis.Z := 1;
  Result.XAxis.X  := 1; Result.XAxis.Y := 0; Result.XAxis.Z := 0;

  if not GetEntityParams(AId, LTypeName, LParams) then Exit;

  if LTypeName = 'AXIS2_PLACEMENT_3D' then
  begin
    // AXIS2_PLACEMENT_3D('name', #location, #z_axis_dir, #ref_x_dir)
    // z_axis ve x_axis $ (unset) olabilir
    if Length(LParams) >= 2 then
    begin
      LRefId := ParseRef(LParams[1]);
      if LRefId > 0 then Result.Location := GetPoint(LRefId);
    end;
    if Length(LParams) >= 3 then
    begin
      LRefId := ParseRef(LParams[2]);
      if LRefId > 0 then Result.ZAxis := GetDirection(LRefId);
    end;
    if Length(LParams) >= 4 then
    begin
      LRefId := ParseRef(LParams[3]);
      if LRefId > 0 then Result.XAxis := GetDirection(LRefId);
    end;
  end
  else if LTypeName = 'AXIS2_PLACEMENT_2D' then
  begin
    // AXIS2_PLACEMENT_2D('name', #location, #ref_x_dir)
    if Length(LParams) >= 2 then
    begin
      LRefId := ParseRef(LParams[1]);
      if LRefId > 0 then Result.Location := GetPoint(LRefId);
    end;
    if Length(LParams) >= 3 then
    begin
      LRefId := ParseRef(LParams[2]);
      if LRefId > 0 then Result.XAxis := GetDirection(LRefId);
    end;
    // Z ekseni varsayılan (0,0,1)
  end
  else if LTypeName = 'AXIS1_PLACEMENT' then
  begin
    if Length(LParams) >= 2 then
    begin
      LRefId := ParseRef(LParams[1]);
      if LRefId > 0 then Result.Location := GetPoint(LRefId);
    end;
  end;
end;

function TStepParser.GetVertexPoint(AId: Integer): TPoint3D;
var
  LTypeName: string;
  LParams: TArray<string>;
  LRefId: Integer;
begin
  Result := TPoint3D.Zero;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if LTypeName <> 'VERTEX_POINT' then Exit;
  if Length(LParams) < 2 then Exit;

  // VERTEX_POINT('name', #cartesian_point)
  LRefId := ParseRef(LParams[1]);
  if LRefId > 0 then Result := GetPoint(LRefId);
end;

// ===========================================================================
// Şekil oluşturucular
// ===========================================================================

function TStepParser.MakeDefaultStyle: TDrawStyle;
begin
  Result             := TDrawStyle.Default;
  Result.StrokeColor := TAlphaColors.White;
  Result.StrokeWidth := 1.0;
end;

procedure TStepParser.AddShape(AShape: TDrawShape);
begin
  if AShape = nil then Exit;
  AShape.LayerName := STEP_DEFAULT_LAYER;
  FDocument.AddShape(AShape);
  FDocument.IncrementEntityCount;
end;

procedure TStepParser.AddWarning(const AMsg: string);
var
  N: Integer;
begin
  N := Length(FWarnings);
  SetLength(FWarnings, N + 1);
  FWarnings[N] := AMsg;
  if FDocument <> nil then
    FDocument.ParseWarnings.Add(AMsg);
end;

function TStepParser.BuildEdgeCurve(AId: Integer): TDrawShape;
var
  LTypeName: string;
  LParams: TArray<string>;
  LV1Id, LV2Id, LCurveId: Integer;
  LP1, LP2: TPoint3D;
begin
  Result := nil;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if LTypeName <> 'EDGE_CURVE' then Exit;
  if Length(LParams) < 4 then Exit;

  // EDGE_CURVE('name', #start_vertex, #end_vertex, #curve, same_sense)
  LV1Id    := ParseRef(LParams[1]);
  LV2Id    := ParseRef(LParams[2]);
  LCurveId := ParseRef(LParams[3]);

  if (LV1Id <= 0) or (LV2Id <= 0) or (LCurveId <= 0) then Exit;

  LP1 := GetVertexPoint(LV1Id);
  LP2 := GetVertexPoint(LV2Id);

  Result := BuildCurveSegment(LCurveId, LP1, LP2, True);
  if Result <> nil then
  begin
    FConverted.AddOrSetValue(AId, True);
    FConverted.AddOrSetValue(LCurveId, True);
  end;
end;

function TStepParser.BuildCurveSegment(ACurveId: Integer;
  const AP1, AP2: TPoint3D; AHasVertices: Boolean): TDrawShape;
var
  LTypeName: string;
  LParams: TArray<string>;
  LPlaceRef: Integer;
  LRadiusVal, LSemiAxis1, LSemiAxis2: Double;
  LPlacement: TStepPlacement;
begin
  Result := nil;
  if not GetEntityParams(ACurveId, LTypeName, LParams) then Exit;

  if LTypeName = 'LINE' then
  begin
    // Sınırlı segment için köşe noktalarını kullan
    if AHasVertices and (AP1.To2D.DistanceTo(AP2.To2D) > 1e-10) then
    begin
      var LShape := TDrawLine.Create;
      LShape.StartPoint := AP1.To2D;
      LShape.EndPoint   := AP2.To2D;
      LShape.Style      := MakeDefaultStyle;
      Result := LShape;
    end;
  end

  else if LTypeName = 'CIRCLE' then
  begin
    if Length(LParams) < 3 then Exit;
    LPlaceRef := ParseRef(LParams[1]);
    if (LPlaceRef <= 0) or not ParseNum(LParams[2], LRadiusVal) then Exit;
    LPlacement := GetPlacement(LPlaceRef);

    // P1 ≈ P2 → tam daire; aksi halde yay
    if (not AHasVertices) or (AP1.To2D.DistanceTo(AP2.To2D) < 1e-8) then
      Result := BuildCircleShape(LPlacement, LRadiusVal)
    else
      Result := BuildArcOrCircle(
        LPlacement.Location, LRadiusVal,
        RadToDeg(ArcTan2(AP1.Y - LPlacement.Location.Y,
                         AP1.X - LPlacement.Location.X)),
        RadToDeg(ArcTan2(AP2.Y - LPlacement.Location.Y,
                         AP2.X - LPlacement.Location.X)),
        LPlacement.ZAxis);
  end

  else if LTypeName = 'ELLIPSE' then
  begin
    if Length(LParams) < 4 then Exit;
    LPlaceRef := ParseRef(LParams[1]);
    if LPlaceRef <= 0 then Exit;
    if not ParseNum(LParams[2], LSemiAxis1) then Exit;
    if not ParseNum(LParams[3], LSemiAxis2) then Exit;
    LPlacement := GetPlacement(LPlaceRef);
    Result := BuildEllipticArc(LPlacement, LSemiAxis1, LSemiAxis2, 0, 2 * Pi);
  end

  else if (LTypeName = 'B_SPLINE_CURVE_WITH_KNOTS') or
          (LTypeName = 'RATIONAL_B_SPLINE_CURVE')   or
          (LTypeName = 'UNIFORM_CURVE')              or
          (LTypeName = 'QUASI_UNIFORM_CURVE')        or
          (LTypeName = 'BEZIER_CURVE')               or
          (LTypeName = 'B_SPLINE_CURVE') then
  begin
    Result := BuildBSplineCurve(ACurveId);
    // B-spline başarısız olursa düz çizgiye geri dön
    if (Result = nil) and AHasVertices and
       (AP1.To2D.DistanceTo(AP2.To2D) > 1e-10) then
    begin
      var LShape := TDrawLine.Create;
      LShape.StartPoint := AP1.To2D;
      LShape.EndPoint   := AP2.To2D;
      LShape.Style      := MakeDefaultStyle;
      Result := LShape;
    end;
  end

  else if LTypeName = 'TRIMMED_CURVE' then
    Result := BuildTrimmedCurve(ACurveId)

  else if LTypeName = 'COMPOSITE_CURVE' then
  begin
    // Yaklaşım: başlangıç-bitiş arası düz çizgi
    if AHasVertices and (AP1.To2D.DistanceTo(AP2.To2D) > 1e-10) then
    begin
      var LShape := TDrawLine.Create;
      LShape.StartPoint := AP1.To2D;
      LShape.EndPoint   := AP2.To2D;
      LShape.Style      := MakeDefaultStyle;
      Result := LShape;
    end;
  end;
end;

function TStepParser.BuildArcOrCircle(const ACenter: TPoint3D;
  ARadius: Double; AStartDeg, AEndDeg: Double;
  const AZAxis: TPoint3D): TDrawShape;
var
  LStartDeg, LEndDeg: Double;
begin
  // Negatif Z normali: açıları yansıt (CW → CCW)
  if AZAxis.Z < -1e-6 then
  begin
    LStartDeg := -AStartDeg;
    LEndDeg   := -AEndDeg;
  end
  else
  begin
    LStartDeg := AStartDeg;
    LEndDeg   := AEndDeg;
  end;

  // Tam daire mi kontrol et
  var LSweep := Abs(LEndDeg - LStartDeg);
  if (LSweep < 1e-4) or (Abs(LSweep - 360.0) < 1e-4) then
  begin
    var LCircle := TDrawCircle.Create;
    LCircle.Center := TPoint2D.Create(ACenter.X, ACenter.Y);
    LCircle.Radius := ARadius;
    LCircle.Style  := MakeDefaultStyle;
    Result := LCircle;
  end
  else
  begin
    var LArc := TDrawArc.Create;
    LArc.Center       := TPoint2D.Create(ACenter.X, ACenter.Y);
    LArc.Radius       := ARadius;
    LArc.StartAngleDeg := LStartDeg;
    LArc.EndAngleDeg   := LEndDeg;
    LArc.Style         := MakeDefaultStyle;
    Result := LArc;
  end;
end;

function TStepParser.BuildCircleShape(const APlacement: TStepPlacement;
  ARadius: Double): TDrawShape;
var
  LShape: TDrawCircle;
begin
  LShape         := TDrawCircle.Create;
  LShape.Center  := TPoint2D.Create(APlacement.Location.X, APlacement.Location.Y);
  LShape.Radius  := ARadius;
  LShape.Style   := MakeDefaultStyle;
  Result := LShape;
end;

function TStepParser.BuildEllipticArc(const APlacement: TStepPlacement;
  ASemiAxis1, ASemiAxis2: Double;
  AStartParam, AEndParam: Double): TDrawShape;
var
  LShape: TDrawEllipse;
  LXAxisAngle: Double;
begin
  LShape     := TDrawEllipse.Create;
  LXAxisAngle := ArcTan2(APlacement.XAxis.Y, APlacement.XAxis.X);

  LShape.Center     := TPoint2D.Create(APlacement.Location.X, APlacement.Location.Y);
  // MajorAxisEnd: merkeze göre relatif, XAxis yönünde
  LShape.MajorAxisEnd := TPoint2D.Create(
    ASemiAxis1 * Cos(LXAxisAngle),
    ASemiAxis1 * Sin(LXAxisAngle));

  if ASemiAxis1 > 1e-10 then
    LShape.MinorToMajorRatio := ASemiAxis2 / ASemiAxis1
  else
    LShape.MinorToMajorRatio := 1.0;

  LShape.StartParam := AStartParam;
  LShape.EndParam   := AEndParam;
  LShape.Style      := MakeDefaultStyle;
  Result := LShape;
end;

function TStepParser.BuildTrimmedCurve(AId: Integer): TDrawShape;
var
  LTypeName, LBaseName: string;
  LParams, LBaseParams: TArray<string>;
  LBaseCurveId, LRefId, LPlaceRef: Integer;
  LTrim1Items, LTrim2Items: TArray<string>;
  LTrim1Num, LTrim2Num: Double;
  LHasTrim1Num, LHasTrim2Num: Boolean;
  LTrim1Ref, LTrim2Ref: Integer;
  LPlacement: TStepPlacement;
  LRadius, LSemiAxis1, LSemiAxis2: Double;
  LCenter: TPoint3D;
  LStartAngle, LEndAngle, LXAxisAngleDeg: Double;
  LStartParam, LEndParam: Double;
begin
  Result := nil;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if LTypeName <> 'TRIMMED_CURVE' then Exit;
  // TRIMMED_CURVE('name', #basis_curve, (trim1...), (trim2...), sense, preference)
  if Length(LParams) < 4 then Exit;

  LBaseCurveId := ParseRef(LParams[1]);
  if LBaseCurveId <= 0 then Exit;
  if not GetEntityParams(LBaseCurveId, LBaseName, LBaseParams) then Exit;

  // Trim değerlerini ayrıştır: PARAMETER_VALUE (sayı) veya CARTESIAN_POINT (#ref)
  LTrim1Items := UnwrapList(LParams[2]);
  LTrim2Items := UnwrapList(LParams[3]);

  LHasTrim1Num := False; LHasTrim2Num := False;
  LTrim1Num := 0;        LTrim2Num := 0;
  LTrim1Ref := -1;       LTrim2Ref := -1;

  for var LS1 in LTrim1Items do
    if ParseNum(LS1, LTrim1Num) then LHasTrim1Num := True
    else begin LRefId := ParseRef(LS1); if LRefId > 0 then LTrim1Ref := LRefId; end;

  for var LS2 in LTrim2Items do
    if ParseNum(LS2, LTrim2Num) then LHasTrim2Num := True
    else begin LRefId := ParseRef(LS2); if LRefId > 0 then LTrim2Ref := LRefId; end;

  // -----------------------------------------------------------------------
  // Temel eğri: CIRCLE
  // -----------------------------------------------------------------------
  if LBaseName = 'CIRCLE' then
  begin
    if Length(LBaseParams) < 3 then Exit;
    LPlaceRef := ParseRef(LBaseParams[1]);
    if not ParseNum(LBaseParams[2], LRadius) then Exit;
    LPlacement   := GetPlacement(LPlaceRef);
    LCenter      := LPlacement.Location;
    LXAxisAngleDeg := RadToDeg(ArcTan2(LPlacement.XAxis.Y, LPlacement.XAxis.X));

    // Başlangıç açısı
    if LHasTrim1Num then
      LStartAngle := RadToDeg(LTrim1Num) + LXAxisAngleDeg
    else if LTrim1Ref > 0 then
    begin
      var LPt := GetPoint(LTrim1Ref);
      LStartAngle := RadToDeg(ArcTan2(LPt.Y - LCenter.Y, LPt.X - LCenter.X));
    end
    else
      LStartAngle := LXAxisAngleDeg;

    // Bitiş açısı
    if LHasTrim2Num then
      LEndAngle := RadToDeg(LTrim2Num) + LXAxisAngleDeg
    else if LTrim2Ref > 0 then
    begin
      var LPt := GetPoint(LTrim2Ref);
      LEndAngle := RadToDeg(ArcTan2(LPt.Y - LCenter.Y, LPt.X - LCenter.X));
    end
    else
      LEndAngle := LStartAngle + 360.0;

    Result := BuildArcOrCircle(LCenter, LRadius,
      LStartAngle, LEndAngle, LPlacement.ZAxis);
    FConverted.AddOrSetValue(LBaseCurveId, True);
  end

  // -----------------------------------------------------------------------
  // Temel eğri: LINE
  // -----------------------------------------------------------------------
  else if LBaseName = 'LINE' then
  begin
    var LP1, LP2: TPoint3D;
    LP1 := TPoint3D.Zero; LP2 := TPoint3D.Zero;

    if LTrim1Ref > 0 then
      LP1 := GetPoint(LTrim1Ref)
    else if Length(LBaseParams) >= 2 then
    begin
      var LStartRef := ParseRef(LBaseParams[1]);
      if LStartRef > 0 then LP1 := GetPoint(LStartRef);
    end;

    if LTrim2Ref > 0 then
      LP2 := GetPoint(LTrim2Ref)
    else if (Length(LBaseParams) >= 3) and LHasTrim1Num and LHasTrim2Num then
    begin
      // Parametre değerleri ile VECTOR'dan hesapla
      var LVecRef := ParseRef(LBaseParams[2]);
      if LVecRef > 0 then
      begin
        var LVecTypeName: string; var LVecParams: TArray<string>;
        if GetEntityParams(LVecRef, LVecTypeName, LVecParams) and
           (LVecTypeName = 'VECTOR') and (Length(LVecParams) >= 3) then
        begin
          var LDirRef := ParseRef(LVecParams[1]);
          var LMag: Double;
          if (LDirRef > 0) and ParseNum(LVecParams[2], LMag) then
          begin
            var LDir := GetDirection(LDirRef);
            var LDelta := LTrim2Num - LTrim1Num;
            LP2.X := LP1.X + LDir.X * LDelta * LMag;
            LP2.Y := LP1.Y + LDir.Y * LDelta * LMag;
            LP2.Z := LP1.Z + LDir.Z * LDelta * LMag;
          end;
        end;
      end;
    end;

    if LP1.To2D.DistanceTo(LP2.To2D) > 1e-10 then
    begin
      var LShape := TDrawLine.Create;
      LShape.StartPoint := LP1.To2D;
      LShape.EndPoint   := LP2.To2D;
      LShape.Style      := MakeDefaultStyle;
      Result := LShape;
    end;
    FConverted.AddOrSetValue(LBaseCurveId, True);
  end

  // -----------------------------------------------------------------------
  // Temel eğri: ELLIPSE
  // -----------------------------------------------------------------------
  else if LBaseName = 'ELLIPSE' then
  begin
    if Length(LBaseParams) < 4 then Exit;
    LPlaceRef := ParseRef(LBaseParams[1]);
    if not ParseNum(LBaseParams[2], LSemiAxis1) then Exit;
    if not ParseNum(LBaseParams[3], LSemiAxis2) then Exit;
    LPlacement := GetPlacement(LPlaceRef);

    if LHasTrim1Num then LStartParam := LTrim1Num else LStartParam := 0;
    if LHasTrim2Num then LEndParam   := LTrim2Num else LEndParam   := 2 * Pi;

    Result := BuildEllipticArc(LPlacement, LSemiAxis1, LSemiAxis2,
      LStartParam, LEndParam);
    FConverted.AddOrSetValue(LBaseCurveId, True);
  end;
end;

function TStepParser.BuildPolyline(AId: Integer): TDrawShape;
var
  LTypeName: string;
  LParams, LPointList: TArray<string>;
  LRefId: Integer;
  LPt: TPoint3D;
  LShape: TDrawPolyline;
begin
  Result := nil;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if LTypeName <> 'POLYLINE' then Exit;
  if Length(LParams) < 2 then Exit;

  // POLYLINE('name', (#p1, #p2, ...))
  LPointList := UnwrapList(LParams[1]);
  if Length(LPointList) < 2 then Exit;

  LShape       := TDrawPolyline.Create;
  LShape.Style := MakeDefaultStyle;

  for var LPStr in LPointList do
  begin
    LRefId := ParseRef(LPStr);
    if LRefId > 0 then
    begin
      LPt := GetPoint(LRefId);
      LShape.AddPoint(LPt.To2D);
    end;
  end;

  if LShape.PointCount < 2 then
  begin
    LShape.Free;
    Exit;
  end;

  FConverted.AddOrSetValue(AId, True);
  Result := LShape;
end;

function TStepParser.BuildBSplineCurve(AId: Integer): TDrawShape;
var
  LTypeName: string;
  LParams, LCtrlPts: TArray<string>;
  LRefId: Integer;
  LPt: TPoint3D;
  LShape: TDrawPath;
begin
  Result := nil;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;

  // B_SPLINE_CURVE_WITH_KNOTS / B_SPLINE_CURVE:
  //   ('name', degree, (#cp1,#cp2,...), curve_form, closed_curve, self_intersect, ...)
  // Kontrol noktaları params[2]'de
  if Length(LParams) < 3 then Exit;

  LCtrlPts := UnwrapList(LParams[2]);
  if Length(LCtrlPts) < 2 then Exit;

  LShape       := TDrawPath.Create;
  LShape.Style := MakeDefaultStyle;

  for var LPStr in LCtrlPts do
  begin
    LRefId := ParseRef(LPStr);
    if LRefId > 0 then
    begin
      LPt := GetPoint(LRefId);
      LShape.AddPoint(LPt.To2D);
    end;
  end;

  if LShape.PointCount < 2 then
  begin
    LShape.Free;
    Exit;
  end;

  // Kapalı eğri kontrolü (params[4])
  if Length(LParams) >= 5 then
    LShape.IsClosed := ParseBool(LParams[4]);

  FConverted.AddOrSetValue(AId, True);
  Result := LShape;
end;

function TStepParser.BuildStandaloneCircle(AId: Integer): TDrawShape;
var
  LTypeName: string;
  LParams: TArray<string>;
  LPlaceRef: Integer;
  LRadius: Double;
begin
  Result := nil;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;
  if LTypeName <> 'CIRCLE' then Exit;
  if Length(LParams) < 3 then Exit;

  // CIRCLE('name', #placement, radius)
  LPlaceRef := ParseRef(LParams[1]);
  if LPlaceRef <= 0 then Exit;
  if not ParseNum(LParams[2], LRadius) then Exit;

  var LPlacement := GetPlacement(LPlaceRef);
  Result := BuildCircleShape(LPlacement, LRadius);
  FConverted.AddOrSetValue(AId, True);
end;

// ===========================================================================
// Üst seviye traversal
// ===========================================================================

function TStepParser.TryResolveSetOrWireframe(AId: Integer): Boolean;
var
  LTypeName, LCurveTypeName: string;
  LParams, LCurveParams, LCurveList: TArray<string>;
  LRefId: Integer;
  LShape: TDrawShape;
  LCurveListParam: string;
begin
  Result := False;
  if not GetEntityParams(AId, LTypeName, LParams) then Exit;

  LCurveListParam := '';
  if (LTypeName = 'GEOMETRIC_CURVE_SET')                          or
     (LTypeName = 'COMPOSITE_CURVE_ON_SURFACE')                   or
     (LTypeName = 'GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION') or
     (LTypeName = 'GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION') then
  begin
    if Length(LParams) >= 2 then
      LCurveListParam := LParams[1];
  end
  else
    Exit;

  LCurveList := UnwrapList(LCurveListParam);
  if Length(LCurveList) = 0 then Exit;

  for var LCStr in LCurveList do
  begin
    LRefId := ParseRef(LCStr);
    if (LRefId <= 0) or FConverted.ContainsKey(LRefId) then Continue;
    if not GetEntityParams(LRefId, LCurveTypeName, LCurveParams) then Continue;

    LShape := nil;

    if LCurveTypeName = 'EDGE_CURVE' then
      LShape := BuildEdgeCurve(LRefId)
    else if LCurveTypeName = 'TRIMMED_CURVE' then
    begin
      LShape := BuildTrimmedCurve(LRefId);
      FConverted.AddOrSetValue(LRefId, True);
    end
    else if LCurveTypeName = 'CIRCLE' then
      LShape := BuildStandaloneCircle(LRefId)
    else if LCurveTypeName = 'ELLIPSE' then
    begin
      if Length(LCurveParams) >= 4 then
      begin
        var LPlaceRef := ParseRef(LCurveParams[1]);
        var LSA1, LSA2: Double;
        if (LPlaceRef > 0) and ParseNum(LCurveParams[2], LSA1) and
           ParseNum(LCurveParams[3], LSA2) then
        begin
          var LP := GetPlacement(LPlaceRef);
          LShape := BuildEllipticArc(LP, LSA1, LSA2, 0, 2 * Pi);
          FConverted.AddOrSetValue(LRefId, True);
        end;
      end;
    end
    else if LCurveTypeName = 'POLYLINE' then
      LShape := BuildPolyline(LRefId)
    else if (LCurveTypeName = 'B_SPLINE_CURVE_WITH_KNOTS') or
            (LCurveTypeName = 'B_SPLINE_CURVE') then
      LShape := BuildBSplineCurve(LRefId)
    else if (LCurveTypeName = 'GEOMETRIC_CURVE_SET')                           or
            (LCurveTypeName = 'GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION') then
    begin
      // Özyinelemeli
      if TryResolveSetOrWireframe(LRefId) then
        Result := True;
      FConverted.AddOrSetValue(LRefId, True);
    end;

    if LShape <> nil then
    begin
      AddShape(LShape);
      Result := True;
    end;
  end;
end;

procedure TStepParser.ResolveGeometry;
var
  LPair: TPair<Integer, TEntityData>;
  LShape: TDrawShape;
  LFoundRoot: Boolean;
begin
  LFoundRoot := False;

  // -----------------------------------------------------------------------
  // Adım 1: Kök eğri kümeleri / wireframe'leri çözümle
  // -----------------------------------------------------------------------
  for LPair in FEntities do
  begin
    if (LPair.Value.TypeName = 'GEOMETRIC_CURVE_SET')                           or
       (LPair.Value.TypeName = 'GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION') or
       (LPair.Value.TypeName = 'GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION') then
    begin
      if TryResolveSetOrWireframe(LPair.Key) then
      begin
        FConverted.AddOrSetValue(LPair.Key, True);
        LFoundRoot := True;
      end;
    end;
  end;

  // -----------------------------------------------------------------------
  // Adım 2: Kök bulunamazsa tüm EDGE_CURVE entity'lerini topla
  // -----------------------------------------------------------------------
  if not LFoundRoot then
  begin
    for LPair in FEntities do
    begin
      if (LPair.Value.TypeName = 'EDGE_CURVE') and
         not FConverted.ContainsKey(LPair.Key) then
      begin
        LShape := BuildEdgeCurve(LPair.Key);
        if LShape <> nil then
        begin
          AddShape(LShape);
          LFoundRoot := True;
        end;
      end;
    end;
  end;

  // -----------------------------------------------------------------------
  // Adım 3: POLYLINE entity'lerini topla (tüm durumlarda)
  // -----------------------------------------------------------------------
  for LPair in FEntities do
  begin
    if (LPair.Value.TypeName = 'POLYLINE') and
       not FConverted.ContainsKey(LPair.Key) then
    begin
      LShape := BuildPolyline(LPair.Key);
      if LShape <> nil then
        AddShape(LShape);
    end;
  end;

  // -----------------------------------------------------------------------
  // Adım 4: Hâlâ hiç şekil yoksa geometrik primitifleri doğrudan topla
  // -----------------------------------------------------------------------
  if FDocument.Shapes.Count = 0 then
  begin
    for LPair in FEntities do
    begin
      if FConverted.ContainsKey(LPair.Key) then Continue;

      var LTN := LPair.Value.TypeName;
      LShape := nil;

      if LTN = 'CIRCLE' then
        LShape := BuildStandaloneCircle(LPair.Key)

      else if LTN = 'TRIMMED_CURVE' then
      begin
        LShape := BuildTrimmedCurve(LPair.Key);
        FConverted.AddOrSetValue(LPair.Key, True);
      end

      else if LTN = 'ELLIPSE' then
      begin
        var LEParams: TArray<string>; var LET: string;
        if GetEntityParams(LPair.Key, LET, LEParams) and (Length(LEParams) >= 4) then
        begin
          var LPlaceRef := ParseRef(LEParams[1]);
          var LSA1, LSA2: Double;
          if (LPlaceRef > 0) and ParseNum(LEParams[2], LSA1) and
             ParseNum(LEParams[3], LSA2) then
          begin
            var LP := GetPlacement(LPlaceRef);
            LShape := BuildEllipticArc(LP, LSA1, LSA2, 0, 2 * Pi);
            FConverted.AddOrSetValue(LPair.Key, True);
          end;
        end;
      end

      else if (LTN = 'B_SPLINE_CURVE_WITH_KNOTS') or (LTN = 'B_SPLINE_CURVE') then
        LShape := BuildBSplineCurve(LPair.Key);

      if LShape <> nil then
        AddShape(LShape);
    end;
  end;

  if FDocument.Shapes.Count = 0 then
    AddWarning('Desteklenen geometrik entity bulunamadı.');
end;

end.
