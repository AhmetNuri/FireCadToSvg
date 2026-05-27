/// <summary>
/// CADViewer.Parsers.IGES.Parser
/// IGES (ASCII) dosyalarını ayrıştıran parser.
/// IDxfParser arayüzünü implement ederek DXF ile ortak mimari sağlar.
/// </summary>
unit CADViewer.Parsers.IGES.Parser;

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
  TIgesDirectoryEntry = record
    SequenceNo: Integer;      // D satırı sıra numarası (73-80)
    EntityType: Integer;      // Örn: 110=LINE, 100=ARC
    ParamPointer: Integer;    // İlgili P satırı başlangıç sıra numarası
    FormNumber: Integer;
    Level: Integer;
    ColorNumber: Integer;
  end;

  TIgesEntity = record
    Dir: TIgesDirectoryEntry;
    RawParams: string;
    Params: TArray<string>;
  end;

  TIgesParser = class(TInterfacedObject, IDxfParser)
  private
    FDocument: TDxfDocument;
    FWarnings: TArray<string>;
    FParamDelim: Char;
    FRecordDelim: Char;
    FEntitiesBySeq: TDictionary<Integer, TIgesEntity>;
    FEntityOrder: TList<Integer>;
    FAddedRefs: TDictionary<Integer, Boolean>;

    class function ParseIntField(const S: string): Integer; static;
    class function ParseIgesFloat(const S: string; out V: Double): Boolean; static;
    class function SplitTopLevel(const S: string; ADelim: Char): TArray<string>; static;
    class function DecodeIgesString(const S: string): string; static;
    class function NormalizeToken(const S: string): string; static;

    procedure AddWarning(const AMsg: string);
    function MakeDefaultStyle: TDrawStyle;
    procedure AddShape(AShape: TDrawShape);

    procedure DetectGlobalDelimiters(const GLines: TArray<string>);
    function ParseDirectoryEntries(const DLines: TArray<string>): TArray<TIgesDirectoryEntry>;
    function BuildParameterMap(const PLines: TArray<string>): TDictionary<Integer, string>;
    procedure ParseSections(const AContent: string;
      out GLines, DLines, PLines: TArray<string>);
    procedure BuildEntities(const GLines, DLines, PLines: TArray<string>);

    function GetEntity(ASeq: Integer; out AEntity: TIgesEntity): Boolean;
    function TryParseNumberParam(const AParams: TArray<string>; AIndex: Integer; out AValue: Double): Boolean;
    function TryParseRef(const S: string; out ARefSeq: Integer): Boolean;
    function IsCurveEntity(AEntityType: Integer): Boolean;

    function BuildLine(const AEntity: TIgesEntity): TDrawShape;
    function BuildArc(const AEntity: TIgesEntity): TDrawShape;
    function BuildCircle(const AEntity: TIgesEntity): TDrawShape;
    function BuildPolyline(const AEntity: TIgesEntity): TDrawShape;
    function BuildBsplineApprox(const AEntity: TIgesEntity): TDrawShape;
    function BuildSurfaceApprox(const AEntity: TIgesEntity): TDrawShape;
    function BuildPoint(const AEntity: TIgesEntity): TDrawShape;
    function BuildParametricSpline(const AEntity: TIgesEntity): TDrawShape;

    procedure CollectReferencedGeometry(ASeq: Integer;
      AVisited: TDictionary<Integer, Boolean>);
    procedure ResolveGeometry;

  public
    constructor Create;
    destructor Destroy; override;

    function ParseFile(const AFilePath: string): TDxfDocument;
    function ParseContent(const AContent: string): TDxfDocument;
    function GetWarnings: TArray<string>;
  end;

implementation

const
  IGES_DEFAULT_LAYER = '0';

{ TIgesParser }

constructor TIgesParser.Create;
begin
  inherited Create;
  FEntitiesBySeq := TDictionary<Integer, TIgesEntity>.Create;
  FEntityOrder := TList<Integer>.Create;
  FAddedRefs := TDictionary<Integer, Boolean>.Create;
end;

destructor TIgesParser.Destroy;
begin
  FAddedRefs.Free;
  FEntityOrder.Free;
  FEntitiesBySeq.Free;
  inherited Destroy;
end;

class function TIgesParser.ParseIntField(const S: string): Integer;
begin
  Result := StrToIntDef(Trim(S), 0);
end;

class function TIgesParser.ParseIgesFloat(const S: string; out V: Double): Boolean;
var
  L: string;
begin
  L := Trim(S);
  if L = '' then
    Exit(False);

  L := StringReplace(L, 'D', 'E', [rfReplaceAll, rfIgnoreCase]);
  L := StringReplace(L, ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(L, V, TFormatSettings.Invariant);
end;

class function TIgesParser.DecodeIgesString(const S: string): string;
var
  L: string;
  I, N, LenVal: Integer;
  LLenText: string;
begin
  L := Trim(S);
  if L = '' then
    Exit('');

  I := 1;
  N := Length(L);
  while (I <= N) and (L[I] in ['0'..'9']) do
    Inc(I);

  if (I > 1) and (I <= N) and ((L[I] = 'H') or (L[I] = 'h')) then
  begin
    LLenText := Copy(L, 1, I - 1);
    LenVal := StrToIntDef(LLenText, -1);
    if LenVal >= 0 then
    begin
      Result := Copy(L, I + 1, LenVal);
      Exit;
    end;
  end;

  Result := L;
end;

class function TIgesParser.NormalizeToken(const S: string): string;
begin
  Result := Trim(DecodeIgesString(S));
end;

class function TIgesParser.SplitTopLevel(const S: string; ADelim: Char): TArray<string>;
var
  LItems: TList<string>;
  I, N, StartPos, HollLen, J: Integer;
  C: Char;
  LNumber: string;
begin
  LItems := TList<string>.Create;
  try
    N := Length(S);
    StartPos := 1;
    I := 1;
    while I <= N do
    begin
      C := S[I];
      if C = ADelim then
      begin
        LItems.Add(Trim(Copy(S, StartPos, I - StartPos)));
        StartPos := I + 1;
        Inc(I);
        Continue;
      end;

      if C in ['0'..'9'] then
      begin
        J := I;
        LNumber := '';
        while (J <= N) and (S[J] in ['0'..'9']) do
        begin
          LNumber := LNumber + S[J];
          Inc(J);
        end;

        if (J <= N) and ((S[J] = 'H') or (S[J] = 'h')) then
        begin
          HollLen := StrToIntDef(LNumber, 0);
          I := J + 1 + HollLen;
          Continue;
        end;
      end;

      Inc(I);
    end;

    if StartPos <= N + 1 then
      LItems.Add(Trim(Copy(S, StartPos, N - StartPos + 1)));

    Result := LItems.ToArray;
  finally
    LItems.Free;
  end;
end;

procedure TIgesParser.AddWarning(const AMsg: string);
var
  L: Integer;
begin
  L := Length(FWarnings);
  SetLength(FWarnings, L + 1);
  FWarnings[L] := AMsg;
  if FDocument <> nil then
    FDocument.ParseWarnings.Add(AMsg);
end;

function TIgesParser.MakeDefaultStyle: TDrawStyle;
begin
  Result := TDrawStyle.Default;
  Result.StrokeColor := TAlphaColors.White;
  Result.StrokeWidth := 1.0;
end;

procedure TIgesParser.AddShape(AShape: TDrawShape);
begin
  if AShape = nil then
    Exit;
  AShape.LayerName := IGES_DEFAULT_LAYER;
  FDocument.AddShape(AShape);
  FDocument.IncrementEntityCount;
end;

procedure TIgesParser.ParseSections(const AContent: string;
  out GLines, DLines, PLines: TArray<string>);
var
  I, LCount: Integer;
  LLine: string;
  LSec: Char;
begin
  GLines := [];
  DLines := [];
  PLines := [];

  var LListG := TList<string>.Create;
  var LListD := TList<string>.Create;
  var LListP := TList<string>.Create;
  try
    var LText := StringReplace(
      StringReplace(AContent, #13#10, #10, [rfReplaceAll]),
      #13, #10, [rfReplaceAll]);
    var LAll := LText.Split([#10]);
    LCount := Length(LAll);
    for I := 0 to LCount - 1 do
    begin
      LLine := LAll[I];
      if Trim(LLine) = '' then
        Continue;

      if Length(LLine) < 73 then
        Continue;

      if Length(LLine) < 80 then
        LLine := LLine + StringOfChar(' ', 80 - Length(LLine));

      LSec := UpCase(LLine[73]);
      case LSec of
        'G': LListG.Add(LLine);
        'D': LListD.Add(LLine);
        'P': LListP.Add(LLine);
      end;
    end;

    GLines := LListG.ToArray;
    DLines := LListD.ToArray;
    PLines := LListP.ToArray;
  finally
    LListG.Free;
    LListD.Free;
    LListP.Free;
  end;
end;

procedure TIgesParser.DetectGlobalDelimiters(const GLines: TArray<string>);
var
  LGlobal: string;
  I, MatchCount, HollLen, J: Integer;
  C: Char;
  LNumText: string;
begin
  FParamDelim := ',';
  FRecordDelim := ';';

  LGlobal := '';
  for var L in GLines do
    LGlobal := LGlobal + Copy(L, 1, 72);

  MatchCount := 0;
  I := 1;
  while I <= Length(LGlobal) do
  begin
    if not (LGlobal[I] in ['0'..'9']) then
    begin
      Inc(I);
      Continue;
    end;

    J := I;
    LNumText := '';
    while (J <= Length(LGlobal)) and (LGlobal[J] in ['0'..'9']) do
    begin
      LNumText := LNumText + LGlobal[J];
      Inc(J);
    end;

    if (J <= Length(LGlobal)) and ((LGlobal[J] = 'H') or (LGlobal[J] = 'h')) then
    begin
      HollLen := StrToIntDef(LNumText, -1);
      if (HollLen = 1) and (J + 1 <= Length(LGlobal)) then
      begin
        C := LGlobal[J + 1];
        Inc(MatchCount);
        if MatchCount = 1 then
          FParamDelim := C
        else if MatchCount = 2 then
        begin
          FRecordDelim := C;
          Exit;
        end;
      end;

      I := J + 1 + Max(HollLen, 0);
      Continue;
    end;

    Inc(I);
  end;
end;

function TIgesParser.ParseDirectoryEntries(
  const DLines: TArray<string>): TArray<TIgesDirectoryEntry>;
var
  I: Integer;
  LLine1, LLine2: string;
  LEntry: TIgesDirectoryEntry;
  LItems: TList<TIgesDirectoryEntry>;
begin
  LItems := TList<TIgesDirectoryEntry>.Create;
  try
    I := 0;
    while I + 1 < Length(DLines) do
    begin
      LLine1 := DLines[I];
      LLine2 := DLines[I + 1];

      LEntry.SequenceNo := ParseIntField(Copy(LLine1, 73, 8));
      if LEntry.SequenceNo = 0 then
        LEntry.SequenceNo := (I * 2) + 1;
      LEntry.EntityType := ParseIntField(Copy(LLine1, 1, 8));
      LEntry.ParamPointer := ParseIntField(Copy(LLine1, 9, 8));
      LEntry.Level := ParseIntField(Copy(LLine1, 33, 8));
      LEntry.ColorNumber := ParseIntField(Copy(LLine2, 17, 8));
      LEntry.FormNumber := ParseIntField(Copy(LLine2, 33, 8));

      if (LEntry.EntityType > 0) and (LEntry.ParamPointer > 0) then
        LItems.Add(LEntry);

      Inc(I, 2);
    end;

    Result := LItems.ToArray;
  finally
    LItems.Free;
  end;
end;

function TIgesParser.BuildParameterMap(
  const PLines: TArray<string>): TDictionary<Integer, string>;
var
  I, LSeq: Integer;
  LData: string;
begin
  Result := TDictionary<Integer, string>.Create;
  for I := 0 to High(PLines) do
  begin
    LData := Copy(PLines[I], 1, 64);
    LSeq := ParseIntField(Copy(PLines[I], 73, 8));
    if LSeq = 0 then
      LSeq := I + 1;
    Result.AddOrSetValue(LSeq, LData);
  end;
end;

procedure TIgesParser.BuildEntities(const GLines, DLines, PLines: TArray<string>);
var
  LDirs: TArray<TIgesDirectoryEntry>;
  LParamMap: TDictionary<Integer, string>;
  LDir: TIgesDirectoryEntry;
  LRaw, LChunk: string;
  LPSeq: Integer;
  LEntity: TIgesEntity;
begin
  FEntitiesBySeq.Clear;
  FEntityOrder.Clear;
  FAddedRefs.Clear;

  DetectGlobalDelimiters(GLines);
  LDirs := ParseDirectoryEntries(DLines);
  LParamMap := BuildParameterMap(PLines);
  try
    for LDir in LDirs do
    begin
      LRaw := '';
      LPSeq := LDir.ParamPointer;
      while LParamMap.TryGetValue(LPSeq, LChunk) do
      begin
        LRaw := LRaw + TrimRight(LChunk);
        if Pos(string(FRecordDelim), LChunk) > 0 then
          Break;
        Inc(LPSeq);
      end;

      if LRaw = '' then
      begin
        AddWarning(Format('IGES entity parametresi bulunamadı (D seq=%d, type=%d).',
          [LDir.SequenceNo, LDir.EntityType]));
        Continue;
      end;

      var LPosRec := Pos(string(FRecordDelim), LRaw);
      if LPosRec > 0 then
        LRaw := Copy(LRaw, 1, LPosRec - 1);

      LEntity.Dir := LDir;
      LEntity.RawParams := LRaw;
      LEntity.Params := SplitTopLevel(LRaw, FParamDelim);
      FEntitiesBySeq.AddOrSetValue(LDir.SequenceNo, LEntity);
      FEntityOrder.Add(LDir.SequenceNo);
    end;
  finally
    LParamMap.Free;
  end;
end;

function TIgesParser.GetEntity(ASeq: Integer; out AEntity: TIgesEntity): Boolean;
begin
  Result := FEntitiesBySeq.TryGetValue(ASeq, AEntity);
end;

function TIgesParser.TryParseNumberParam(const AParams: TArray<string>;
  AIndex: Integer; out AValue: Double): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(AParams)) and
            ParseIgesFloat(NormalizeToken(AParams[AIndex]), AValue);
end;

function TIgesParser.TryParseRef(const S: string; out ARefSeq: Integer): Boolean;
var
  L: string;
begin
  L := NormalizeToken(S);
  ARefSeq := StrToIntDef(L, 0);
  Result := ARefSeq > 0;
end;

function TIgesParser.IsCurveEntity(AEntityType: Integer): Boolean;
begin
  Result := AEntityType in [100, 106, 110, 112, 114, 116, 126];
end;

function TIgesParser.BuildLine(const AEntity: TIgesEntity): TDrawShape;
var
  X1, Y1, X2, Y2: Double;
  LOffset: Integer;
  LShape: TDrawLine;
begin
  Result := nil;
  if Length(AEntity.Params) < 6 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 110 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset + 0, X1) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 1, Y1) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 3, X2) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 4, Y2) then Exit;

  LShape := TDrawLine.Create;
  LShape.StartPoint := TPoint2D.Create(X1, Y1);
  LShape.EndPoint := TPoint2D.Create(X2, Y2);
  LShape.Style := MakeDefaultStyle;
  Result := LShape;
end;

function TIgesParser.BuildArc(const AEntity: TIgesEntity): TDrawShape;
var
  XC, YC, XS, YS, XE, YE: Double;
  LRadius, LStartDeg, LEndDeg: Double;
  LOffset: Integer;
  LArc: TDrawArc;
begin
  Result := nil;
  if Length(AEntity.Params) < 7 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 100 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset + 1, XC) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 2, YC) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 3, XS) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 4, YS) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 5, XE) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 6, YE) then Exit;

  LRadius := Hypot(XS - XC, YS - YC);
  if LRadius < 1e-9 then
    Exit;

  LStartDeg := RadToDeg(ArcTan2(YS - YC, XS - XC));
  LEndDeg := RadToDeg(ArcTan2(YE - YC, XE - XC));

  LArc := TDrawArc.Create;
  LArc.Center := TPoint2D.Create(XC, YC);
  LArc.Radius := LRadius;
  LArc.StartAngleDeg := LStartDeg;
  LArc.EndAngleDeg := LEndDeg;
  LArc.Style := MakeDefaultStyle;
  Result := LArc;
end;

function TIgesParser.BuildCircle(const AEntity: TIgesEntity): TDrawShape;
var
  LArcShape: TDrawShape;
  LArc: TDrawArc;
  LCircle: TDrawCircle;
  LSweep: Double;
begin
  Result := nil;
  LArcShape := BuildArc(AEntity);
  if not (LArcShape is TDrawArc) then
  begin
    LArcShape.Free;
    Exit;
  end;

  LArc := TDrawArc(LArcShape);
  LSweep := LArc.EndAngleDeg - LArc.StartAngleDeg;
  while LSweep < 0 do
    LSweep := LSweep + 360.0;
  while LSweep >= 360.0 do
    LSweep := LSweep - 360.0;

  if Abs(LSweep) < 1e-6 then
  begin
    LCircle := TDrawCircle.Create;
    LCircle.Center := LArc.Center;
    LCircle.Radius := LArc.Radius;
    LCircle.Style := LArc.Style;
    Result := LCircle;
    LArc.Free;
  end
  else
    Result := LArc;
end;

function TIgesParser.BuildPolyline(const AEntity: TIgesEntity): TDrawShape;
var
  LNums: TList<Double>;
  I, LOffset, LIP, LN, LDataStart: Integer;
  V: Double;
  LPL: TDrawPolyline;
begin
  Result := nil;

  // Entity 106 (Copious Data) format:
  // params[0] = entity type (106) -- optional
  // params[offset+0] = IP (interpretation flag: 1=XY, 2=XYZ, 3=XYZ vectors)
  // params[offset+1] = N (number of data points)
  // params[offset+2..] = coordinate data

  if Length(AEntity.Params) < 4 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 106 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset, V) then Exit;
  LIP := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 1, V) then Exit;
  LN := Round(V);

  if LN < 2 then
    Exit;

  LDataStart := LOffset + 2;

  LNums := TList<Double>.Create;
  try
    for I := LDataStart to High(AEntity.Params) do
      if ParseIgesFloat(NormalizeToken(AEntity.Params[I]), V) then
        LNums.Add(V);

    if LNums.Count < 4 then
      Exit;

    LPL := TDrawPolyline.Create;
    LPL.Style := MakeDefaultStyle;

    // IP=1: 2D points (X,Y pairs)
    // IP=2: 3D points (X,Y,Z triplets)
    // IP=3: 3D with direction vectors (X,Y,Z,i,j,k) -- use only position
    case LIP of
      1:
        begin
          I := 0;
          while I + 1 < LNums.Count do
          begin
            LPL.AddPoint(TPoint2D.Create(LNums[I], LNums[I + 1]));
            Inc(I, 2);
          end;
        end;
      2:
        begin
          I := 0;
          while I + 2 < LNums.Count do
          begin
            LPL.AddPoint(TPoint2D.Create(LNums[I], LNums[I + 1]));
            Inc(I, 3);
          end;
        end;
      3:
        begin
          I := 0;
          while I + 5 < LNums.Count do
          begin
            LPL.AddPoint(TPoint2D.Create(LNums[I], LNums[I + 1]));
            Inc(I, 6);
          end;
        end;
    else
      // Default: try 3D triplets
      I := 0;
      while I + 2 < LNums.Count do
      begin
        LPL.AddPoint(TPoint2D.Create(LNums[I], LNums[I + 1]));
        Inc(I, 3);
      end;
    end;

    if LPL.PointCount >= 2 then
      Result := LPL
    else
      LPL.Free;
  finally
    LNums.Free;
  end;
end;

function TIgesParser.BuildBsplineApprox(const AEntity: TIgesEntity): TDrawShape;
var
  I, LOffset, K, M, LKnotCount, LWeightCount, LCtrlStart: Integer;
  V: Double;
  LPath: TDrawPath;
begin
  Result := nil;

  // Entity 126 (Rational B-Spline Curve) format:
  // params[offset+0] = K (upper index of sum, number of control points = K+1)
  // params[offset+1] = M (degree of basis functions)
  // params[offset+2] = PROP1 (planar/non-planar)
  // params[offset+3] = PROP2 (open/closed)
  // params[offset+4] = PROP3 (rational/polynomial)
  // params[offset+5] = PROP4 (periodic/non-periodic)
  // Then: K+M+2 knot values
  // Then: K+1 weight values
  // Then: (K+1) control points as X,Y,Z triplets
  // Then: V(0), V(1) parameter range

  if Length(AEntity.Params) < 7 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 126 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset + 0, V) then Exit;
  K := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 1, V) then Exit;
  M := Round(V);

  if (K < 1) or (M < 1) then
    Exit;

  // Calculate offsets
  LKnotCount := K + M + 2;
  LWeightCount := K + 1;
  // Control points start after: 6 header fields + knots + weights
  LCtrlStart := LOffset + 6 + LKnotCount + LWeightCount;

  // We need at least (K+1) control points * 3 coordinates
  if LCtrlStart + (K + 1) * 3 > Length(AEntity.Params) then
  begin
    // Fallback: try reading as raw coordinate triplets from all data
    // (backward compatibility for malformed files)
    var LNums := TList<Double>.Create;
    try
      for I := LOffset + 6 + LKnotCount + LWeightCount to High(AEntity.Params) do
        if ParseIgesFloat(NormalizeToken(AEntity.Params[I]), V) then
          LNums.Add(V);

      if LNums.Count < 6 then
        Exit;

      LPath := TDrawPath.Create;
      LPath.Style := MakeDefaultStyle;
      I := 0;
      while I + 2 < LNums.Count do
      begin
        LPath.AddPoint(TPoint2D.Create(LNums[I], LNums[I + 1]));
        Inc(I, 3);
      end;

      if LPath.PointCount >= 2 then
        Result := LPath
      else
        LPath.Free;
    finally
      LNums.Free;
    end;
    Exit;
  end;

  LPath := TDrawPath.Create;
  LPath.Style := MakeDefaultStyle;

  for I := 0 to K do
  begin
    var XIdx := LCtrlStart + I * 3;
    var YIdx := LCtrlStart + I * 3 + 1;
    var LX: Double;
    var LY: Double;
    if TryParseNumberParam(AEntity.Params, XIdx, LX) and
       TryParseNumberParam(AEntity.Params, YIdx, LY) then
      LPath.AddPoint(TPoint2D.Create(LX, LY));
  end;

  if LPath.PointCount >= 2 then
    Result := LPath
  else
    LPath.Free;
end;

function TIgesParser.BuildSurfaceApprox(const AEntity: TIgesEntity): TDrawShape;
var
  I, LOffset, K1, K2, M1, M2: Integer;
  LKnot1Count, LKnot2Count, LWeightCount, LCtrlStart, LCtrlCount: Integer;
  V, X, Y: Double;
  LHasPoint: Boolean;
  LMinX, LMinY, LMaxX, LMaxY: Double;
  LPL: TDrawPolyline;
begin
  Result := nil;

  // Entity 128 (Rational B-Spline Surface) format:
  // params[offset+0] = K1 (upper index in first direction)
  // params[offset+1] = K2 (upper index in second direction)
  // params[offset+2] = M1 (degree in first direction)
  // params[offset+3] = M2 (degree in second direction)
  // params[offset+4..8] = PROP1-5
  // Then: (K1+M1+2) + (K2+M2+2) knot values
  // Then: (K1+1)*(K2+1) weight values
  // Then: (K1+1)*(K2+1) control points as X,Y,Z

  if Length(AEntity.Params) < 10 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 128 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset + 0, V) then Exit;
  K1 := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 1, V) then Exit;
  K2 := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 2, V) then Exit;
  M1 := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 3, V) then Exit;
  M2 := Round(V);

  if (K1 < 1) or (K2 < 1) or (M1 < 1) or (M2 < 1) then
    Exit;

  LKnot1Count := K1 + M1 + 2;
  LKnot2Count := K2 + M2 + 2;
  LCtrlCount := (K1 + 1) * (K2 + 1);
  LWeightCount := LCtrlCount;
  // 9 header fields (K1,K2,M1,M2,PROP1..PROP5)
  LCtrlStart := LOffset + 9 + LKnot1Count + LKnot2Count + LWeightCount;

  // Extract bounding box from control points
  LHasPoint := False;
  LMinX := 0; LMaxX := 0; LMinY := 0; LMaxY := 0;

  for I := 0 to LCtrlCount - 1 do
  begin
    var XIdx := LCtrlStart + I * 3;
    var YIdx := LCtrlStart + I * 3 + 1;
    if TryParseNumberParam(AEntity.Params, XIdx, X) and
       TryParseNumberParam(AEntity.Params, YIdx, Y) then
    begin
      if not LHasPoint then
      begin
        LMinX := X; LMaxX := X; LMinY := Y; LMaxY := Y;
        LHasPoint := True;
      end
      else
      begin
        LMinX := Min(LMinX, X);
        LMaxX := Max(LMaxX, X);
        LMinY := Min(LMinY, Y);
        LMaxY := Max(LMaxY, Y);
      end;
    end;
  end;

  // Fallback: if structured parsing didn't find points, try raw scan
  if not LHasPoint then
  begin
    var LNums := TList<Double>.Create;
    try
      for I := 1 to High(AEntity.Params) do
        if ParseIgesFloat(NormalizeToken(AEntity.Params[I]), V) then
          LNums.Add(V);

      if LNums.Count < 6 then
        Exit;

      I := 0;
      while I + 2 < LNums.Count do
      begin
        X := LNums[I];
        Y := LNums[I + 1];
        if not LHasPoint then
        begin
          LMinX := X; LMaxX := X; LMinY := Y; LMaxY := Y;
          LHasPoint := True;
        end
        else
        begin
          LMinX := Min(LMinX, X);
          LMaxX := Max(LMaxX, X);
          LMinY := Min(LMinY, Y);
          LMaxY := Max(LMaxY, Y);
        end;
        Inc(I, 3);
      end;
    finally
      LNums.Free;
    end;
  end;

  if not LHasPoint then
    Exit;

  LPL := TDrawPolyline.Create;
  LPL.Style := MakeDefaultStyle;
  LPL.IsClosed := True;
  LPL.AddPoint(TPoint2D.Create(LMinX, LMinY));
  LPL.AddPoint(TPoint2D.Create(LMaxX, LMinY));
  LPL.AddPoint(TPoint2D.Create(LMaxX, LMaxY));
  LPL.AddPoint(TPoint2D.Create(LMinX, LMaxY));
  Result := LPL;
end;

function TIgesParser.BuildPoint(const AEntity: TIgesEntity): TDrawShape;
var
  LOffset: Integer;
  X, Y: Double;
  LPoint: TDrawPoint;
begin
  Result := nil;

  // Entity 116 (Point) format:
  // params[offset+0] = X
  // params[offset+1] = Y
  // params[offset+2] = Z
  // params[offset+3] = display symbol pointer (optional)

  if Length(AEntity.Params) < 3 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 116 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset + 0, X) then Exit;
  if not TryParseNumberParam(AEntity.Params, LOffset + 1, Y) then Exit;

  LPoint := TDrawPoint.Create;
  LPoint.Position := TPoint2D.Create(X, Y);
  LPoint.Style := MakeDefaultStyle;
  Result := LPoint;
end;

function TIgesParser.BuildParametricSpline(const AEntity: TIgesEntity): TDrawShape;
var
  I, LOffset, CTYPE, H, NDIM, N, LDataStart: Integer;
  V, T0, T1, AX, BX, CX, DX, AY, BY, CY, DY: Double;
  LPath: TDrawPath;
  LSegments, LSteps: Integer;
  S, DS: Double;
begin
  Result := nil;

  // Entity 114 (Parametric Spline Curve) format:
  // params[offset+0] = CTYPE (spline type: 1=linear, 2=quadratic, 3=cubic)
  // params[offset+1] = H (degree of continuity)
  // params[offset+2] = NDIM (number of dimensions, 2 or 3)
  // params[offset+3] = N (number of segments)
  // params[offset+4..offset+4+N] = break points T(0)..T(N)
  // Then for each segment: polynomial coefficients
  //   For NDIM=2: AX,BX,CX,DX, AY,BY,CY,DY (8 values per segment)
  //   For NDIM=3: AX,BX,CX,DX, AY,BY,CY,DY, AZ,BZ,CZ,DZ (12 values per segment)

  if Length(AEntity.Params) < 5 then
    Exit;

  LOffset := 0;
  if ParseIntField(NormalizeToken(AEntity.Params[0])) = 114 then
    LOffset := 1;

  if not TryParseNumberParam(AEntity.Params, LOffset + 0, V) then Exit;
  CTYPE := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 1, V) then Exit;
  H := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 2, V) then Exit;
  NDIM := Round(V);
  if not TryParseNumberParam(AEntity.Params, LOffset + 3, V) then Exit;
  N := Round(V);

  if (N < 1) or (NDIM < 2) then
    Exit;

  // Break points start at offset+4, count = N+1
  LDataStart := LOffset + 4 + (N + 1);

  // Coefficients per segment: 4 values per dimension (A,B,C,D)
  LSegments := N;

  LPath := TDrawPath.Create;
  LPath.Style := MakeDefaultStyle;

  LSteps := 8; // tessellation steps per segment

  for I := 0 to LSegments - 1 do
  begin
    var LCoeffStart := LDataStart + I * (NDIM * 4);

    // Read X coefficients: AX, BX, CX, DX
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 0, AX) then Continue;
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 1, BX) then Continue;
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 2, CX) then Continue;
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 3, DX) then Continue;

    // Read Y coefficients: AY, BY, CY, DY
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 4, AY) then Continue;
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 5, BY) then Continue;
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 6, CY) then Continue;
    if not TryParseNumberParam(AEntity.Params, LCoeffStart + 7, DY) then Continue;

    // Get break point values for this segment
    if not TryParseNumberParam(AEntity.Params, LOffset + 4 + I, T0) then Continue;
    if not TryParseNumberParam(AEntity.Params, LOffset + 4 + I + 1, T1) then Continue;

    DS := (T1 - T0) / LSteps;
    var J: Integer;
    for J := 0 to LSteps do
    begin
      S := J * DS;
      var PX := AX + BX * S + CX * S * S + DX * S * S * S;
      var PY := AY + BY * S + CY * S * S + DY * S * S * S;
      LPath.AddPoint(TPoint2D.Create(PX, PY));
    end;
  end;

  if LPath.PointCount >= 2 then
    Result := LPath
  else
    LPath.Free;
end;

procedure TIgesParser.CollectReferencedGeometry(ASeq: Integer;
  AVisited: TDictionary<Integer, Boolean>);
var
  LEntity: TIgesEntity;
  LRefSeq: Integer;
  LShape: TDrawShape;
begin
  if AVisited.ContainsKey(ASeq) then
    Exit;
  AVisited.AddOrSetValue(ASeq, True);

  if not GetEntity(ASeq, LEntity) then
    Exit;

  // Skip if already added in the first pass
  if not FAddedRefs.ContainsKey(ASeq) then
  begin
    LShape := nil;
    case LEntity.Dir.EntityType of
      110: LShape := BuildLine(LEntity);
      100: LShape := BuildCircle(LEntity);
      106: LShape := BuildPolyline(LEntity);
      112, 114: LShape := BuildParametricSpline(LEntity);
      116: LShape := BuildPoint(LEntity);
      126: LShape := BuildBsplineApprox(LEntity);
      128: LShape := BuildSurfaceApprox(LEntity);
    end;

    if LShape <> nil then
    begin
      AddShape(LShape);
      FAddedRefs.AddOrSetValue(ASeq, True);
    end;
  end;

  for var P in LEntity.Params do
  begin
    if TryParseRef(P, LRefSeq) and FEntitiesBySeq.ContainsKey(LRefSeq) then
      CollectReferencedGeometry(LRefSeq, AVisited);
  end;
end;

procedure TIgesParser.ResolveGeometry;
var
  LSeq: Integer;
  LEntity: TIgesEntity;
  LShape: TDrawShape;
begin
  for LSeq in FEntityOrder do
  begin
    if not GetEntity(LSeq, LEntity) then
      Continue;

    LShape := nil;
    case LEntity.Dir.EntityType of
      110: LShape := BuildLine(LEntity);
      100: LShape := BuildCircle(LEntity);
      106: LShape := BuildPolyline(LEntity);
      112, 114: LShape := BuildParametricSpline(LEntity);
      116: LShape := BuildPoint(LEntity);
      126: LShape := BuildBsplineApprox(LEntity);
      128: LShape := BuildSurfaceApprox(LEntity);
    end;

    if LShape <> nil then
    begin
      AddShape(LShape);
      FAddedRefs.AddOrSetValue(LSeq, True);
    end;
  end;

  // Second pass: process composite/structural entities and their references
  for LSeq in FEntityOrder do
  begin
    if not GetEntity(LSeq, LEntity) then
      Continue;

    if LEntity.Dir.EntityType in [102, 141, 142, 143, 144, 504, 508, 510] then
    begin
      if FAddedRefs.ContainsKey(LSeq) then
        Continue;
      FAddedRefs.AddOrSetValue(LSeq, True);
      var LVisited := TDictionary<Integer, Boolean>.Create;
      try
        CollectReferencedGeometry(LSeq, LVisited);
      finally
        LVisited.Free;
      end;
    end;
  end;

  if FDocument.Shapes.Count = 0 then
    AddWarning('IGES içinde desteklenen geometri bulunamadı.');
end;

function TIgesParser.ParseFile(const AFilePath: string): TDxfDocument;
var
  LContent: string;
begin
  try
    LContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
  except
    LContent := TFile.ReadAllText(AFilePath, TEncoding.GetEncoding(1252));
  end;

  Result := ParseContent(LContent);
  Result.FilePath := AFilePath;
  Result.FileName := TPath.GetFileName(AFilePath);
end;

function TIgesParser.ParseContent(const AContent: string): TDxfDocument;
var
  GLines, DLines, PLines: TArray<string>;
begin
  FWarnings := [];
  ParseSections(AContent, GLines, DLines, PLines);

  if Length(DLines) = 0 then
    raise EIgesParseError.Create('IGES DIRECTORY (D) bölümü bulunamadı.');
  if Length(PLines) = 0 then
    raise EIgesParseError.Create('IGES PARAMETER DATA (P) bölümü bulunamadı.');

  FDocument := TDxfDocument.Create;
  FDocument.EnsureLayer(IGES_DEFAULT_LAYER);
  try
    BuildEntities(GLines, DLines, PLines);
    ResolveGeometry;

    Result := FDocument;
    FDocument := nil;
  except
    FDocument.Free;
    FDocument := nil;
    raise;
  end;
end;

function TIgesParser.GetWarnings: TArray<string>;
begin
  Result := FWarnings;
end;

end.
