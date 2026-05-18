/// <summary>
/// CADViewer.Core.Models.DrawShapes
/// TDrawShape soyut hiyerarşisi ve tüm somut çizim şekilleri.
/// Parser tarafından oluşturulan DXF entity'leri bu shape nesnelerine
/// dönüştürülür. Renderer yalnızca bu nesneleri bilir; DXF detayları
/// bu katmanda soyutlanmış olur. (SVG mantığına yakın yapı)
/// </summary>
unit CADViewer.Core.Models.DrawShapes;

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.UITypes,
  System.Math,
  CADViewer.Core.Types;

type

  // =========================================================================
  // Temel Çizim Stili
  // =========================================================================

  /// <summary>
  /// Bir şeklin görsel özelliklerini içeren kayıt.
  /// Renderer bu kayıttaki değerleri kullanır.
  /// </summary>
  TDrawStyle = record
    StrokeColor: TAlphaColor;   // Çizgi/kenar rengi
    FillColor: TAlphaColor;     // Dolgu rengi (TAlphaColors.Null = dolgu yok)
    StrokeWidth: Single;        // Çizgi kalınlığı (piksel cinsinden)
    LineType: TDxfLineType;     // Çizgi tipi
    LtScale: Single;            // Çizgi tipi tekrar ölçeği
    Opacity: Single;            // Saydamlık (0.0–1.0, 1.0 = tam opak)
    HasFill: Boolean;           // Dolgu var mı?

    class function Default: TDrawStyle; static;
  end;

  // =========================================================================
  // TDrawShape — Soyut temel sınıf
  // =========================================================================

  /// <summary>
  /// Tüm çizim şekilleri için soyut temel sınıf.
  /// Renderer bu interface üzerinden tüm şekil türlerine polimorfik davranır.
  /// Template Method Pattern: CalcBounds alt sınıflarda override edilir.
  /// </summary>
  TDrawShape = class abstract
  private
    FStyle: TDrawStyle;
    FLayerName: string;
    FHandle: string;
    FVisible: Boolean;
    FBoundsDirty: Boolean;
    FCachedBounds: TBoundingBox;
  protected
    /// <summary>
    /// Alt sınıflar bu metodu override ederek kendi bounding box hesabını yapar.
    /// </summary>
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); virtual; abstract;
  public
    constructor Create;

    property Style: TDrawStyle read FStyle write FStyle;
    property LayerName: string read FLayerName write FLayerName;
    property Handle: string read FHandle write FHandle;
    property Visible: Boolean read FVisible write FVisible;

    /// <summary>Şeklin kaplayan dikdörtgen alanı. Lazy hesaplanır.</summary>
    function GetBounds: TBoundingBox;

    /// <summary>Bounds önbelleğini geçersiz kılar (şekil değişince çağrılır).</summary>
    procedure InvalidateBounds;
  end;

  // =========================================================================
  // TDrawLine — LINE
  // =========================================================================

  /// <summary>
  /// Başlangıç–bitiş arası düz çizgi.
  /// </summary>
  TDrawLine = class(TDrawShape)
  private
    FStartPoint: TPoint2D;
    FEndPoint: TPoint2D;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property StartPoint: TPoint2D read FStartPoint write FStartPoint;
    property EndPoint: TPoint2D read FEndPoint write FEndPoint;
  end;

  // =========================================================================
  // TDrawCircle — CIRCLE
  // =========================================================================

  /// <summary>
  /// Tam daire.
  /// </summary>
  TDrawCircle = class(TDrawShape)
  private
    FCenter: TPoint2D;
    FRadius: Double;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property Center: TPoint2D read FCenter write FCenter;
    property Radius: Double read FRadius write FRadius;
  end;

  // =========================================================================
  // TDrawArc — ARC
  // =========================================================================

  /// <summary>
  /// Daire yayı. Açılar derece cinsinden, CCW pozitif.
  /// </summary>
  TDrawArc = class(TDrawShape)
  private
    FCenter: TPoint2D;
    FRadius: Double;
    FStartAngleDeg: Double;
    FEndAngleDeg: Double;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property Center: TPoint2D read FCenter write FCenter;
    property Radius: Double read FRadius write FRadius;

    /// <summary>Başlangıç açısı (derece, CCW).</summary>
    property StartAngleDeg: Double read FStartAngleDeg write FStartAngleDeg;

    /// <summary>Bitiş açısı (derece, CCW).</summary>
    property EndAngleDeg: Double read FEndAngleDeg write FEndAngleDeg;
  end;

  // =========================================================================
  // TDrawEllipse — ELLIPSE
  // =========================================================================

  /// <summary>
  /// Tam veya kısmi elips.
  /// </summary>
  TDrawEllipse = class(TDrawShape)
  private
    FCenter: TPoint2D;
    FMajorAxisEnd: TPoint2D;   // Merkeze göre relatif
    FMinorToMajorRatio: Double;
    FStartParam: Double;       // Radyan
    FEndParam: Double;         // Radyan
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property Center: TPoint2D read FCenter write FCenter;
    property MajorAxisEnd: TPoint2D read FMajorAxisEnd write FMajorAxisEnd;
    property MinorToMajorRatio: Double read FMinorToMajorRatio write FMinorToMajorRatio;
    property StartParam: Double read FStartParam write FStartParam;
    property EndParam: Double read FEndParam write FEndParam;

    /// <summary>Büyük eksen uzunluğunu döndürür.</summary>
    function MajorRadius: Double;

    /// <summary>Büyük eksenin yatay ile açısını derece cinsinden döndürür.</summary>
    function RotationAngleDeg: Double;

    /// <summary>Tam elips mi (parametre 0→2π)?</summary>
    function IsFullEllipse: Boolean;
  end;

  // =========================================================================
  // TDrawPolyline — POLYLINE / LWPOLYLINE
  // =========================================================================

  /// <summary>
  /// Çoklu çizgi parçaları (polyline). Bulge değerleri ile yay kesimlerini destekler.
  /// </summary>
  TPolylinePoint = record
    Position: TPoint2D;
    Bulge: Double;   // 0 = düz segment; ≠0 = yaylı segment
  end;

  TDrawPolyline = class(TDrawShape)
  private
    FPoints: TArray<TPolylinePoint>;
    FIsClosed: Boolean;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property Points: TArray<TPolylinePoint> read FPoints write FPoints;
    property IsClosed: Boolean read FIsClosed write FIsClosed;

    procedure AddPoint(const APos: TPoint2D; ABulge: Double = 0.0);
    function PointCount: Integer; inline;
  end;

  // =========================================================================
  // TDrawText — TEXT / MTEXT
  // =========================================================================

  /// <summary>
  /// Metin çizim şekli. Tek satır veya çok satırlı metin.
  /// </summary>
  TDrawText = class(TDrawShape)
  private
    FPosition: TPoint2D;
    FContent: string;
    FFontHeight: Double;     // Dünya birimi cinsinden
    FRotationDeg: Double;    // Derece
    FHAlign: TDxfTextHAlign;
    FVAlign: TDxfTextVAlign;
    FWidthFactor: Double;
    FObliqueAngle: Double;
    FFontName: string;
    FIsMText: Boolean;
    FRectWidth: Double;      // MText için kutu genişliği (0 = sınırsız)
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    constructor Create;

    property Position: TPoint2D read FPosition write FPosition;
    property Content: string read FContent write FContent;
    property FontHeight: Double read FFontHeight write FFontHeight;
    property RotationDeg: Double read FRotationDeg write FRotationDeg;
    property HAlign: TDxfTextHAlign read FHAlign write FHAlign;
    property VAlign: TDxfTextVAlign read FVAlign write FVAlign;
    property WidthFactor: Double read FWidthFactor write FWidthFactor;
    property ObliqueAngle: Double read FObliqueAngle write FObliqueAngle;
    property FontName: string read FFontName write FFontName;
    property IsMText: Boolean read FIsMText write FIsMText;
    property RectWidth: Double read FRectWidth write FRectWidth;
  end;

  // =========================================================================
  // TDrawPath — SPLINE ve diğer eğri bazlı şekiller
  // =========================================================================

  /// <summary>
  /// Bezier/spline yaklaşımı için çizgi segmentlerinden oluşan path.
  /// Spline'lar yaklaşık çizgi segmentlerine dönüştürülür.
  /// </summary>
  TDrawPath = class(TDrawShape)
  private
    FPoints: TArray<TPoint2D>;
    FIsClosed: Boolean;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property Points: TArray<TPoint2D> read FPoints write FPoints;
    property IsClosed: Boolean read FIsClosed write FIsClosed;

    procedure AddPoint(const P: TPoint2D);
    function PointCount: Integer; inline;
  end;

  // =========================================================================
  // TDrawPoint — POINT
  // =========================================================================

  /// <summary>
  /// Tek nokta. Küçük çapraz veya nokta olarak render edilir.
  /// </summary>
  TDrawPoint = class(TDrawShape)
  private
    FPosition: TPoint2D;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    property Position: TPoint2D read FPosition write FPosition;
  end;

  // =========================================================================
  // TDrawComposite — INSERT (Block Reference)
  // =========================================================================

  /// <summary>
  /// Blok referansı: içinde başka TDrawShape nesneleri barındıran bileşik şekil.
  /// Composite Pattern uygulaması.
  /// </summary>
  TDrawComposite = class(TDrawShape)
  private
    FChildren: TObjectList<TDrawShape>;
    FInsertionPoint: TPoint2D;
    FScaleX, FScaleY: Double;
    FRotationDeg: Double;
    FBlockName: string;
  protected
    procedure CalcBoundsInternal(var ABounds: TBoundingBox); override;
  public
    constructor Create;
    destructor Destroy; override;

    property Children: TObjectList<TDrawShape> read FChildren;
    property InsertionPoint: TPoint2D read FInsertionPoint write FInsertionPoint;
    property ScaleX: Double read FScaleX write FScaleX;
    property ScaleY: Double read FScaleY write FScaleY;
    property RotationDeg: Double read FRotationDeg write FRotationDeg;
    property BlockName: string read FBlockName write FBlockName;

    procedure AddChild(AShape: TDrawShape);
  end;

  // =========================================================================
  // TDrawShapeList — Koleksiyon
  // =========================================================================

  /// <summary>
  /// TDrawShape nesnelerini sahiplenerek tutan liste.
  /// </summary>
  TDrawShapeList = TObjectList<TDrawShape>;

implementation

{ TDrawStyle }

class function TDrawStyle.Default: TDrawStyle;
begin
  Result.StrokeColor := TAlphaColors.White;
  Result.FillColor   := TAlphaColors.Null;
  Result.StrokeWidth := 1.0;
  Result.LineType    := TDxfLineType.ltContinuous;
  Result.LtScale     := 1.0;
  Result.Opacity     := 1.0;
  Result.HasFill     := False;
end;

{ TDrawShape }

constructor TDrawShape.Create;
begin
  inherited Create;
  FStyle     := TDrawStyle.Default;
  FVisible   := True;
  FBoundsDirty := True;
  FCachedBounds := TBoundingBox.Empty;
end;

function TDrawShape.GetBounds: TBoundingBox;
begin
  if FBoundsDirty then
  begin
    FCachedBounds := TBoundingBox.Empty;
    CalcBoundsInternal(FCachedBounds);
    FBoundsDirty := False;
  end;
  Result := FCachedBounds;
end;

procedure TDrawShape.InvalidateBounds;
begin
  FBoundsDirty := True;
end;

{ TDrawLine }

procedure TDrawLine.CalcBoundsInternal(var ABounds: TBoundingBox);
begin
  ABounds.Expand(FStartPoint);
  ABounds.Expand(FEndPoint);
end;

{ TDrawCircle }

procedure TDrawCircle.CalcBoundsInternal(var ABounds: TBoundingBox);
begin
  ABounds.Expand(FCenter.X - FRadius, FCenter.Y - FRadius);
  ABounds.Expand(FCenter.X + FRadius, FCenter.Y + FRadius);
end;

{ TDrawArc }

procedure TDrawArc.CalcBoundsInternal(var ABounds: TBoundingBox);
var
  StartRad, EndRad: Double;
  Angle: Double;
begin
  // Başlangıç ve bitiş noktaları her zaman dahil
  StartRad := DegToRad(FStartAngleDeg);
  EndRad   := DegToRad(FEndAngleDeg);

  ABounds.Expand(FCenter.X + FRadius * Cos(StartRad),
                 FCenter.Y + FRadius * Sin(StartRad));
  ABounds.Expand(FCenter.X + FRadius * Cos(EndRad),
                 FCenter.Y + FRadius * Sin(EndRad));

  // Yayın kapsadığı 0°, 90°, 180°, 270° gibi eksen noktaları varsa dahil et
  Angle := FStartAngleDeg;
  while Angle < FEndAngleDeg do
  begin
    ABounds.Expand(FCenter.X + FRadius * Cos(DegToRad(Angle)),
                   FCenter.Y + FRadius * Sin(DegToRad(Angle)));
    Angle := Angle + 90.0;
    if (Angle > FEndAngleDeg) and (Angle < FEndAngleDeg + 90.0) then
      Angle := FEndAngleDeg; // son noktayı ekle
  end;
end;

{ TDrawEllipse }

function TDrawEllipse.MajorRadius: Double;
begin
  Result := FMajorAxisEnd.DistanceTo(TPoint2D.Zero);
end;

function TDrawEllipse.RotationAngleDeg: Double;
begin
  Result := RadToDeg(ArcTan2(FMajorAxisEnd.Y, FMajorAxisEnd.X));
end;

function TDrawEllipse.IsFullEllipse: Boolean;
begin
  Result := (Abs(FStartParam) < 1e-8) and (Abs(FEndParam - 2 * Pi) < 1e-8);
end;

procedure TDrawEllipse.CalcBoundsInternal(var ABounds: TBoundingBox);
var
  MajR, MinR, RotAngle: Double;
  P: TPoint2D;
  I: Integer;
  T: Double;
  CosRot, SinRot: Double;
begin
  MajR    := MajorRadius;
  MinR    := MajR * FMinorToMajorRatio;
  RotAngle := DegToRad(RotationAngleDeg);
  SinCos(RotAngle, SinRot, CosRot);

  // 36 nokta örnekleyerek yeterli hassasiyette bounds hesapla
  for I := 0 to 35 do
  begin
    T := FStartParam + (FEndParam - FStartParam) * I / 35;
    P.X := FCenter.X + MajR * Cos(T) * CosRot - MinR * Sin(T) * SinRot;
    P.Y := FCenter.Y + MajR * Cos(T) * SinRot + MinR * Sin(T) * CosRot;
    ABounds.Expand(P);
  end;
end;

{ TDrawPolyline }

procedure TDrawPolyline.CalcBoundsInternal(var ABounds: TBoundingBox);
var
  I: Integer;
begin
  for I := 0 to High(FPoints) do
    ABounds.Expand(FPoints[I].Position);
end;

procedure TDrawPolyline.AddPoint(const APos: TPoint2D; ABulge: Double);
var
  NewLen: Integer;
begin
  NewLen := Length(FPoints) + 1;
  SetLength(FPoints, NewLen);
  FPoints[NewLen - 1].Position := APos;
  FPoints[NewLen - 1].Bulge    := ABulge;
  InvalidateBounds;
end;

function TDrawPolyline.PointCount: Integer;
begin
  Result := Length(FPoints);
end;

{ TDrawText }

constructor TDrawText.Create;
begin
  inherited Create;
  FWidthFactor := 1.0;
  FHAlign := TDxfTextHAlign.haLeft;
  FVAlign := TDxfTextVAlign.vaBaseline;
end;

procedure TDrawText.CalcBoundsInternal(var ABounds: TBoundingBox);
begin
  // Basit yaklaşım: insertion noktası ve tahmini genişlik/yükseklik
  ABounds.Expand(FPosition);
  ABounds.Expand(FPosition.X + Length(FContent) * FFontHeight * 0.6 * FWidthFactor,
                 FPosition.Y + FFontHeight);
end;

{ TDrawPath }

procedure TDrawPath.CalcBoundsInternal(var ABounds: TBoundingBox);
var
  P: TPoint2D;
begin
  for P in FPoints do
    ABounds.Expand(P);
end;

procedure TDrawPath.AddPoint(const P: TPoint2D);
var
  NewLen: Integer;
begin
  NewLen := Length(FPoints) + 1;
  SetLength(FPoints, NewLen);
  FPoints[NewLen - 1] := P;
  InvalidateBounds;
end;

function TDrawPath.PointCount: Integer;
begin
  Result := Length(FPoints);
end;

{ TDrawPoint }

procedure TDrawPoint.CalcBoundsInternal(var ABounds: TBoundingBox);
begin
  ABounds.Expand(FPosition);
  // Küçük delta ekle ki degenerate bounds olmasın
  ABounds.Expand(FPosition.X + 1e-6, FPosition.Y + 1e-6);
end;

{ TDrawComposite }

constructor TDrawComposite.Create;
begin
  inherited Create;
  FChildren := TObjectList<TDrawShape>.Create(True);
  FScaleX := 1.0;
  FScaleY := 1.0;
end;

destructor TDrawComposite.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

procedure TDrawComposite.AddChild(AShape: TDrawShape);
begin
  FChildren.Add(AShape);
  InvalidateBounds;
end;

procedure TDrawComposite.CalcBoundsInternal(var ABounds: TBoundingBox);
var
  Child: TDrawShape;
  ChildBounds: TBoundingBox;
begin
  for Child in FChildren do
  begin
    ChildBounds := Child.GetBounds;
    ABounds.Merge(ChildBounds);
  end;
end;

end.
