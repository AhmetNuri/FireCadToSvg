/// <summary>
/// CADViewer.Core.Models.DxfDocument
/// DXF belge modeli. Layer tablosu, blok tanımları, tüm varlıklar ve
/// header değişkenlerini bir arada tutar.
/// Parser bu nesneyi doldurur; Renderer bu nesneden okur.
/// </summary>
unit CADViewer.Core.Models.DxfDocument;

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  CADViewer.Core.Types,
  CADViewer.Core.Entities,
  CADViewer.Core.Models.DrawShapes;

type

  // =========================================================================
  // TDxfLayerInfo — Katman (Layer) bilgisi
  // =========================================================================

  /// <summary>
  /// Bir DXF katmanının çözümlenmiş bilgileri.
  /// Renderer katman görünürlüğü ve rengini buradan okur.
  /// </summary>
  TDxfLayerInfo = class
  private
    FName: string;
    FColor: TDxfColor;
    FLineTypeName: string;
    FLineWeight: Integer;
    FIsOff: Boolean;
    FFrozen: Boolean;
    FLocked: Boolean;
    FPlottable: Boolean;
    FVisible: Boolean;   // Kullanıcı tarafından kapatılabilir (UI toggle)
  public
    constructor Create(const AName: string);

    property Name: string read FName;
    property Color: TDxfColor read FColor write FColor;
    property LineTypeName: string read FLineTypeName write FLineTypeName;
    property LineWeight: Integer read FLineWeight write FLineWeight;
    property IsOff: Boolean read FIsOff write FIsOff;
    property Frozen: Boolean read FFrozen write FFrozen;
    property Locked: Boolean read FLocked write FLocked;
    property Plottable: Boolean read FPlottable write FPlottable;
    property Visible: Boolean read FVisible write FVisible;

    /// <summary>Katmanın efektif görünür durumu: Off/Frozen değilse ve
    /// kullanıcı tarafından kapatılmamışsa görünür.</summary>
    function IsEffectivelyVisible: Boolean;
  end;

  // =========================================================================
  // TDxfLineTypeInfo — Çizgi tipi tanımı
  // =========================================================================

  /// <summary>
  /// DXF LTYPE tablosundan okunan çizgi tipi tanımı.
  /// Nokta-çizgi şablonu (pattern) burada saklanır.
  /// </summary>
  TDxfLineTypeInfo = class
  private
    FName: string;
    FDescription: string;
    FPattern: TArray<Double>; // + = çizgi, - = boşluk, 0 = nokta (mm)
    FTotalLength: Double;
  public
    constructor Create(const AName: string);

    property Name: string read FName;
    property Description: string read FDescription write FDescription;
    property Pattern: TArray<Double> read FPattern write FPattern;
    property TotalLength: Double read FTotalLength write FTotalLength;

    /// <summary>Delphi TArray formatında çizgi şablonu döndürür.</summary>
    function GetDashPattern: TArray<Single>;
  end;

  // =========================================================================
  // TDxfBlock — Blok tanımı + şekil listesi
  // =========================================================================

  /// <summary>
  /// Bir DXF bloğunun tanımı ve içindeki çizim şekilleri.
  /// INSERT varlıkları bu bloklara referans verir.
  /// </summary>
  TDxfBlock = class
  private
    FName: string;
    FBasePoint: TPoint2D;
    FDescription: string;
    FShapes: TDrawShapeList;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;

    property Name: string read FName;
    property BasePoint: TPoint2D read FBasePoint write FBasePoint;
    property Description: string read FDescription write FDescription;
    property Shapes: TDrawShapeList read FShapes;
  end;

  // =========================================================================
  // TDxfDocument — Ana Belge Modeli
  // =========================================================================

  /// <summary>
  /// DXF belgesinin tüm içeriğini tutan model sınıfı.
  /// Single Responsibility: Sadece veri tutar; parsing veya rendering yapmaz.
  /// </summary>
  TDxfDocument = class
  private
    FFilePath: string;
    FFileName: string;
    FHeaderVars: TDxfHeaderVars;
    FLayers: TObjectDictionary<string, TDxfLayerInfo>;
    FLineTypes: TObjectDictionary<string, TDxfLineTypeInfo>;
    FBlocks: TObjectDictionary<string, TDxfBlock>;
    FShapes: TDrawShapeList;           // Model space şekilleri
    FPaperSpaceShapes: TDrawShapeList; // Paper space şekilleri
    FBoundsCache: TBoundingBox;
    FBoundsDirty: Boolean;
    FEntityCount: Integer;
    FParseWarnings: TStringList;

    function GetLayerByName(const AName: string): TDxfLayerInfo;
  public
    constructor Create;
    destructor Destroy; override;

    // -----------------------------------------------------------------
    // Temel bilgiler
    // -----------------------------------------------------------------
    property FilePath: string read FFilePath write FFilePath;
    property FileName: string read FFileName write FFileName;
    property HeaderVars: TDxfHeaderVars read FHeaderVars write FHeaderVars;
    property EntityCount: Integer read FEntityCount;
    property ParseWarnings: TStringList read FParseWarnings;

    // -----------------------------------------------------------------
    // Koleksiyonlar
    // -----------------------------------------------------------------
    property Layers: TObjectDictionary<string, TDxfLayerInfo> read FLayers;
    property LineTypes: TObjectDictionary<string, TDxfLineTypeInfo> read FLineTypes;
    property Blocks: TObjectDictionary<string, TDxfBlock> read FBlocks;

    /// <summary>Model space (görüntüleme için asıl şekil listesi).</summary>
    property Shapes: TDrawShapeList read FShapes;
    property PaperSpaceShapes: TDrawShapeList read FPaperSpaceShapes;

    // -----------------------------------------------------------------
    // Layer yönetimi
    // -----------------------------------------------------------------

    /// <summary>Yeni katman ekler veya mevcut katmanı döndürür.</summary>
    function EnsureLayer(const AName: string): TDxfLayerInfo;

    /// <summary>Katman bulunur; bulunamazsa nil döner.</summary>
    function FindLayer(const AName: string): TDxfLayerInfo;

    /// <summary>Tüm katman adlarını döndürür.</summary>
    function GetLayerNames: TArray<string>;

    // -----------------------------------------------------------------
    // LineType yönetimi
    // -----------------------------------------------------------------
    function EnsureLineType(const AName: string): TDxfLineTypeInfo;
    function FindLineType(const AName: string): TDxfLineTypeInfo;

    // -----------------------------------------------------------------
    // Block yönetimi
    // -----------------------------------------------------------------
    function EnsureBlock(const AName: string): TDxfBlock;
    function FindBlock(const AName: string): TDxfBlock;

    // -----------------------------------------------------------------
    // Şekil ekleme
    // -----------------------------------------------------------------

    /// <summary>Model space'e şekil ekler (sahipliği belgeye geçer).</summary>
    procedure AddShape(AShape: TDrawShape);

    /// <summary>Paper space'e şekil ekler.</summary>
    procedure AddPaperSpaceShape(AShape: TDrawShape);

    /// <summary>Entity sayısını artırır (iç kullanım: parser tarafından).</summary>
    procedure IncrementEntityCount;

    // -----------------------------------------------------------------
    // Bounding Box
    // -----------------------------------------------------------------

    /// <summary>
    /// Tüm model space şekillerinin kapsayan dikdörtgenini döndürür.
    /// Header'daki EXTMIN/EXTMAX varsa öncelikle onu kullanır.
    /// </summary>
    function GetBounds: TBoundingBox;

    /// <summary>Bounds önbelleğini geçersiz kılar.</summary>
    procedure InvalidateBounds;

    // -----------------------------------------------------------------
    // Yardımcılar
    // -----------------------------------------------------------------

    /// <summary>Belgeyi temizler (yeni yükleme için).</summary>
    procedure Clear;

    /// <summary>Özet bilgisi döndürür (debug/log için).</summary>
    function GetSummary: string;
  end;

implementation

uses
  System.IOUtils;

{ TDxfLayerInfo }

constructor TDxfLayerInfo.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FColor := TDxfColor.ByLayer;
  FPlottable := True;
  FVisible := True;
end;

function TDxfLayerInfo.IsEffectivelyVisible: Boolean;
begin
  Result := FVisible and not FIsOff and not FFrozen;
end;

{ TDxfLineTypeInfo }

constructor TDxfLineTypeInfo.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FTotalLength := 0;
end;

function TDxfLineTypeInfo.GetDashPattern: TArray<Single>;
var
  I: Integer;
begin
  SetLength(Result, Length(FPattern));
  for I := 0 to High(FPattern) do
    Result[I] := Abs(FPattern[I]); // Skia absolute değer alır
end;

{ TDxfBlock }

constructor TDxfBlock.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FShapes := TDrawShapeList.Create(True);
end;

destructor TDxfBlock.Destroy;
begin
  FShapes.Free;
  inherited Destroy;
end;

{ TDxfDocument }

constructor TDxfDocument.Create;
begin
  inherited Create;
  FLayers := TObjectDictionary<string, TDxfLayerInfo>.Create([doOwnsValues]);
  FLineTypes := TObjectDictionary<string, TDxfLineTypeInfo>.Create([doOwnsValues]);
  FBlocks := TObjectDictionary<string, TDxfBlock>.Create([doOwnsValues]);
  FShapes := TDrawShapeList.Create(True);
  FPaperSpaceShapes := TDrawShapeList.Create(True);
  FParseWarnings := TStringList.Create;
  FBoundsDirty := True;
  FEntityCount := 0;

  // Varsayılan "0" katmanını ekle (DXF standardı)
  EnsureLayer('0');

  // Varsayılan CONTINUOUS linetype
  with EnsureLineType('CONTINUOUS') do
    Description := 'Solid line';
end;

destructor TDxfDocument.Destroy;
begin
  FParseWarnings.Free;
  FPaperSpaceShapes.Free;
  FShapes.Free;
  FBlocks.Free;
  FLineTypes.Free;
  FLayers.Free;
  inherited Destroy;
end;

function TDxfDocument.GetLayerByName(const AName: string): TDxfLayerInfo;
begin
  if not FLayers.TryGetValue(AName, Result) then
    Result := nil;
end;

function TDxfDocument.EnsureLayer(const AName: string): TDxfLayerInfo;
var
  Key: string;
begin
  Key := UpperCase(AName);
  if not FLayers.TryGetValue(Key, Result) then
  begin
    Result := TDxfLayerInfo.Create(AName);
    FLayers.Add(Key, Result);
  end;
end;

function TDxfDocument.FindLayer(const AName: string): TDxfLayerInfo;
begin
  if not FLayers.TryGetValue(UpperCase(AName), Result) then
    Result := nil;
end;

function TDxfDocument.GetLayerNames: TArray<string>;
var
  Layer: TDxfLayerInfo;
  I: Integer;
begin
  SetLength(Result, FLayers.Count);
  I := 0;
  for Layer in FLayers.Values do
  begin
    Result[I] := Layer.Name;
    Inc(I);
  end;
end;

function TDxfDocument.EnsureLineType(const AName: string): TDxfLineTypeInfo;
var
  Key: string;
begin
  Key := UpperCase(AName);
  if not FLineTypes.TryGetValue(Key, Result) then
  begin
    Result := TDxfLineTypeInfo.Create(AName);
    FLineTypes.Add(Key, Result);
  end;
end;

function TDxfDocument.FindLineType(const AName: string): TDxfLineTypeInfo;
begin
  if not FLineTypes.TryGetValue(UpperCase(AName), Result) then
    Result := nil;
end;

function TDxfDocument.EnsureBlock(const AName: string): TDxfBlock;
begin
  if not FBlocks.TryGetValue(AName, Result) then
  begin
    Result := TDxfBlock.Create(AName);
    FBlocks.Add(AName, Result);
  end;
end;

function TDxfDocument.FindBlock(const AName: string): TDxfBlock;
begin
  if not FBlocks.TryGetValue(AName, Result) then
    Result := nil;
end;

procedure TDxfDocument.AddShape(AShape: TDrawShape);
begin
  FShapes.Add(AShape);
  FBoundsDirty := True;
end;

procedure TDxfDocument.AddPaperSpaceShape(AShape: TDrawShape);
begin
  FPaperSpaceShapes.Add(AShape);
end;

procedure TDxfDocument.IncrementEntityCount;
begin
  Inc(FEntityCount);
end;

function TDxfDocument.GetBounds: TBoundingBox;
var
  Shape: TDrawShape;
begin
  if not FBoundsDirty then
  begin
    Result := FBoundsCache;
    Exit;
  end;

  // Header'dan EXTMIN/EXTMAX bilgisi varsa onu kullan
  if FHeaderVars.HasExtents then
  begin
    FBoundsCache := TBoundingBox.Empty;
    FBoundsCache.Expand(FHeaderVars.ExtMin.X, FHeaderVars.ExtMin.Y);
    FBoundsCache.Expand(FHeaderVars.ExtMax.X, FHeaderVars.ExtMax.Y);
  end
  else
  begin
    // Şekillerden hesapla
    FBoundsCache := TBoundingBox.Empty;
    for Shape in FShapes do
    begin
      if Shape.Visible then
        FBoundsCache.Merge(Shape.GetBounds);
    end;
  end;

  FBoundsDirty := False;
  Result := FBoundsCache;
end;

procedure TDxfDocument.InvalidateBounds;
begin
  FBoundsDirty := True;
end;

procedure TDxfDocument.Clear;
begin
  FShapes.Clear;
  FPaperSpaceShapes.Clear;
  FBlocks.Clear;
  FLayers.Clear;
  FLineTypes.Clear;
  FParseWarnings.Clear;
  FEntityCount := 0;
  FBoundsDirty := True;
  FFilePath := '';
  FFileName := '';
  FillChar(FHeaderVars, SizeOf(FHeaderVars), 0);

  // Varsayılanları yeniden oluştur
  EnsureLayer('0');
  with EnsureLineType('CONTINUOUS') do
    Description := 'Solid line';
end;

function TDxfDocument.GetSummary: string;
begin
  Result := Format(
    'Dosya: %s' + sLineBreak +
    'Varlık Sayısı: %d' + sLineBreak +
    'Katman Sayısı: %d' + sLineBreak +
    'Blok Sayısı: %d' + sLineBreak +
    'Uyarı Sayısı: %d' + sLineBreak +
    'Versiyon: %s',
    [FFileName, FEntityCount, FLayers.Count, FBlocks.Count,
     FParseWarnings.Count, FHeaderVars.AcadVersion]);
end;

end.
