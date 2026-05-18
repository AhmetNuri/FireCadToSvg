/// <summary>
/// CADViewer.Core.Types
/// Temel veri tipleri, kayıtlar (records) ve numaralandırmalar (enumerations).
/// Tüm katmanlar tarafından kullanılan ortak veri yapıları burada tanımlanır.
/// </summary>
unit CADViewer.Core.Types;

{$SCOPEDENUMS ON}

interface

uses
  System.Types,
  System.UITypes,
  System.Math;

type

  // =========================================================================
  // Numaralandırmalar (Enumerations)
  // =========================================================================

  /// <summary>
  /// DXF varlık türleri. Yeni format eklendikçe buraya tür eklenebilir.
  /// </summary>
  TDxfEntityType = (
    etUnknown,
    etLine,
    etCircle,
    etArc,
    etEllipse,
    etPolyline,
    etLwPolyline,
    etText,
    etMText,
    etInsert,
    etDimension,
    etSpline,
    etHatch,
    etSolid,
    etPoint,
    etXLine,
    etRay,
    etLeader,
    etViewport
  );

  /// <summary>
  /// DXF çizgi tipi (linetype).
  /// </summary>
  TDxfLineType = (
    ltContinuous,
    ltDashed,
    ltDotted,
    ltDashDot,
    ltCenter,
    ltHidden,
    ltPhantom,
    ltCustom
  );

  /// <summary>
  /// Metin yatay hizalaması.
  /// </summary>
  TDxfTextHAlign = (
    haLeft,
    haCenter,
    haRight,
    haAligned,
    haMiddle,
    haFit
  );

  /// <summary>
  /// Metin dikey hizalaması.
  /// </summary>
  TDxfTextVAlign = (
    vaBaseline,
    vaBottom,
    vaMiddle,
    vaTop
  );

  /// <summary>
  /// CAD dosya biçimi. Factory pattern için kullanılır.
  /// </summary>
  TCadFileFormat = (
    ffUnknown,
    ffDxf,
    ffDwg,    // Gelecek destek
    ffIges,   // Gelecek destek
    ffStep    // Gelecek destek
  );

  // =========================================================================
  // Temel Geometri Kayıtları
  // =========================================================================

  /// <summary>
  /// 2 boyutlu nokta (DXF dünya koordinatları).
  /// </summary>
  TPoint2D = record
    X, Y: Double;

    constructor Create(AX, AY: Double);

    /// <summary>FMX TPointF'e dönüştürür.</summary>
    function ToPointF: TPointF;

    /// <summary>İki nokta arasındaki mesafeyi hesaplar.</summary>
    function DistanceTo(const Other: TPoint2D): Double;

    /// <summary>Vektör toplamı.</summary>
    class operator Add(const A, B: TPoint2D): TPoint2D;

    /// <summary>Vektör farkı.</summary>
    class operator Subtract(const A, B: TPoint2D): TPoint2D;

    /// <summary>Skaler çarpma.</summary>
    class operator Multiply(const A: TPoint2D; Scalar: Double): TPoint2D;

    class function Zero: TPoint2D; static; inline;
  end;

  /// <summary>
  /// 3 boyutlu nokta.
  /// </summary>
  TPoint3D = record
    X, Y, Z: Double;

    constructor Create(AX, AY, AZ: Double);

    /// <summary>Z koordinatını düşürerek 2D'ye çevirir.</summary>
    function To2D: TPoint2D;

    class function Zero: TPoint3D; static; inline;
  end;

  // =========================================================================
  // DXF Renk Sistemi
  // =========================================================================

  /// <summary>
  /// DXF renk bilgisi. AutoCAD Color Index (ACI) veya gerçek RGB değeri
  /// taşıyabilir. ByLayer/ByBlock durumlarını da yönetir.
  /// </summary>
  TDxfColor = record
  private
    FAciIndex: Integer;      // ACI indeksi (0=ByBlock, 256=ByLayer)
    FRgbValue: TAlphaColor;  // Gerçek renk değeri (çözümlenmiş)
    FIsByLayer: Boolean;
    FIsByBlock: Boolean;
    FIsRgb: Boolean;         // True: doğrudan RGB, False: ACI
  public
    property AciIndex: Integer read FAciIndex;
    property RgbValue: TAlphaColor read FRgbValue;
    property IsByLayer: Boolean read FIsByLayer;
    property IsByBlock: Boolean read FIsByBlock;
    property IsRgb: Boolean read FIsRgb;

    /// <summary>Layer rengini kullanan varsayılan renk oluşturur.</summary>
    class function ByLayer: TDxfColor; static;

    /// <summary>Block rengini kullanan renk oluşturur.</summary>
    class function ByBlock: TDxfColor; static;

    /// <summary>ACI indeksinden renk oluşturur.</summary>
    class function FromAci(AIndex: Integer): TDxfColor; static;

    /// <summary>Doğrudan RGB değerinden renk oluşturur (TrueColor).</summary>
    class function FromRgb(R, G, B: Byte): TDxfColor; static;

    /// <summary>TAlphaColor'dan renk oluşturur.</summary>
    class function FromAlphaColor(AColor: TAlphaColor): TDxfColor; static;
  end;

  // =========================================================================
  // Sınırlayıcı Kutu (Bounding Box)
  // =========================================================================

  /// <summary>
  /// Bir çizim öğesinin veya tüm belgenin kapladığı dikdörtgen alan.
  /// Visible entity optimizasyonu ve Fit-to-Screen için kullanılır.
  /// </summary>
  TBoundingBox = record
  private
    FMinX, FMinY, FMaxX, FMaxY: Double;
    FIsEmpty: Boolean;
  public
    property MinX: Double read FMinX;
    property MinY: Double read FMinY;
    property MaxX: Double read FMaxX;
    property MaxY: Double read FMaxY;
    property IsEmpty: Boolean read FIsEmpty;

    /// <summary>Boş (geçersiz) bir bounding box döndürür.</summary>
    class function Empty: TBoundingBox; static;

    /// <summary>Verilen koordinatı kapsayacak şekilde kutuyu genişletir.</summary>
    procedure Expand(AX, AY: Double); overload;
    procedure Expand(const P: TPoint2D); overload;

    /// <summary>Başka bir kutuyu bu kutuya birleştirir.</summary>
    procedure Merge(const Other: TBoundingBox);

    function Width: Double; inline;
    function Height: Double; inline;
    function Center: TPoint2D;
    function ToRectF: TRectF;

    /// <summary>Verilen nokta kutunun içinde mi?</summary>
    function Contains(const P: TPoint2D): Boolean; overload;
    function Contains(AX, AY: Double): Boolean; overload;

    /// <summary>İki kutu kesişiyor mu?</summary>
    function Intersects(const Other: TBoundingBox): Boolean;
  end;

  // =========================================================================
  // Viewport (Görünüm Portu)
  // =========================================================================

  /// <summary>
  /// Dünya koordinatlarından ekran koordinatlarına dönüşüm için viewport.
  /// Pan ve Zoom durumunu saklar.
  /// Not: DXF koordinat sistemi Y-up, ekran Y-down olduğu için
  /// Y ekseni çevrilmektedir.
  /// </summary>
  TViewport = record
  private
    FScale: Double;
    FPanX, FPanY: Double;
    FScreenWidth, FScreenHeight: Double;
  public
    property Scale: Double read FScale write FScale;
    property PanX: Double read FPanX write FPanX;
    property PanY: Double read FPanY write FPanY;
    property ScreenWidth: Double read FScreenWidth write FScreenWidth;
    property ScreenHeight: Double read FScreenHeight write FScreenHeight;

    /// <summary>Viewport'u varsayılan değerlere sıfırlar.</summary>
    procedure Reset;

    /// <summary>Dünya koordinatını ekran koordinatına çevirir (Y-flip dahil).</summary>
    function WorldToScreen(const P: TPoint2D): TPointF; overload;
    function WorldToScreen(AX, AY: Double): TPointF; overload; inline;

    /// <summary>Ekran koordinatını dünya koordinatına çevirir.</summary>
    function ScreenToWorld(const P: TPointF): TPoint2D; overload;
    function ScreenToWorld(AX, AY: Single): TPoint2D; overload; inline;

    /// <summary>Dünya birimindeki uzunluğu ekran piksellerine çevirir.</summary>
    function WorldLengthToScreen(ALength: Double): Single; inline;

    /// <summary>
    /// Tüm çizimi ekrana sığdıracak şekilde scale ve pan hesaplar.
    /// Kenar boşluğu (margin) yüzde olarak verilir (örn: 0.05 = %5).
    /// </summary>
    procedure FitToContent(const ABounds: TBoundingBox; AMarginFactor: Double = 0.05);
  end;

  // =========================================================================
  // CAD Katmanı (Layer)
  // =========================================================================

  /// <summary>
  /// DXF layer (katman) tanımı.
  /// </summary>
  TDxfLayerDef = record
    Name: string;
    Color: TDxfColor;
    LineType: string;       // Linetype adı (örn: 'CONTINUOUS', 'DASHED')
    LineWeight: Integer;    // Mils cinsinden (örn: 25 = 0.25mm)
    IsOff: Boolean;         // Kapalı (Off) durumu
    IsFrozen: Boolean;      // Donmuş (Frozen) durumu
    IsLocked: Boolean;      // Kilitli (Locked) durumu
    IsPlottable: Boolean;   // Çizim (plot) durumu
  end;

  // =========================================================================
  // Çizgi Kalınlığı Sabitleri
  // =========================================================================

  TDxfLineWeight = record
  public
    const ByLayer = -1;
    const ByBlock = -2;
    const Default = -3;
    // Standart değerler mils cinsinden (1 mil = 0.01 mm):
    // 0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80,
    // 90, 100, 106, 120, 140, 158, 200, 211
  end;

implementation

{ TPoint2D }

constructor TPoint2D.Create(AX, AY: Double);
begin
  X := AX;
  Y := AY;
end;

function TPoint2D.ToPointF: TPointF;
begin
  Result := TPointF.Create(X, Y);
end;

function TPoint2D.DistanceTo(const Other: TPoint2D): Double;
begin
  Result := Sqrt(Sqr(X - Other.X) + Sqr(Y - Other.Y));
end;

class operator TPoint2D.Add(const A, B: TPoint2D): TPoint2D;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
end;

class operator TPoint2D.Subtract(const A, B: TPoint2D): TPoint2D;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
end;

class operator TPoint2D.Multiply(const A: TPoint2D; Scalar: Double): TPoint2D;
begin
  Result.X := A.X * Scalar;
  Result.Y := A.Y * Scalar;
end;

class function TPoint2D.Zero: TPoint2D;
begin
  Result.X := 0;
  Result.Y := 0;
end;

{ TPoint3D }

constructor TPoint3D.Create(AX, AY, AZ: Double);
begin
  X := AX;
  Y := AY;
  Z := AZ;
end;

function TPoint3D.To2D: TPoint2D;
begin
  Result := TPoint2D.Create(X, Y);
end;

class function TPoint3D.Zero: TPoint3D;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Z := 0;
end;

{ TDxfColor }

class function TDxfColor.ByLayer: TDxfColor;
begin
  Result.FAciIndex := 256;
  Result.FIsByLayer := True;
  Result.FIsByBlock := False;
  Result.FIsRgb := False;
  Result.FRgbValue := TAlphaColors.White;
end;

class function TDxfColor.ByBlock: TDxfColor;
begin
  Result.FAciIndex := 0;
  Result.FIsByLayer := False;
  Result.FIsByBlock := True;
  Result.FIsRgb := False;
  Result.FRgbValue := TAlphaColors.White;
end;

class function TDxfColor.FromAci(AIndex: Integer): TDxfColor;
begin
  Result.FAciIndex := AIndex;
  Result.FIsByLayer := (AIndex = 256);
  Result.FIsByBlock := (AIndex = 0);
  Result.FIsRgb := False;
  Result.FRgbValue := TAlphaColors.White; // CADViewer.Utils içinde ACI→RGB çözümlenir
end;

class function TDxfColor.FromRgb(R, G, B: Byte): TDxfColor;
begin
  Result.FAciIndex := -1;
  Result.FIsByLayer := False;
  Result.FIsByBlock := False;
  Result.FIsRgb := True;
  Result.FRgbValue := (TAlphaColor($FF000000) or
    (TAlphaColor(R) shl 16) or
    (TAlphaColor(G) shl 8) or
    TAlphaColor(B));
end;

class function TDxfColor.FromAlphaColor(AColor: TAlphaColor): TDxfColor;
begin
  Result.FAciIndex := -1;
  Result.FIsByLayer := False;
  Result.FIsByBlock := False;
  Result.FIsRgb := True;
  Result.FRgbValue := AColor;
end;

{ TBoundingBox }

class function TBoundingBox.Empty: TBoundingBox;
begin
  Result.FMinX := MaxDouble;
  Result.FMinY := MaxDouble;
  Result.FMaxX := -MaxDouble;
  Result.FMaxY := -MaxDouble;
  Result.FIsEmpty := True;
end;

procedure TBoundingBox.Expand(AX, AY: Double);
begin
  if FIsEmpty then
  begin
    FMinX := AX; FMaxX := AX;
    FMinY := AY; FMaxY := AY;
    FIsEmpty := False;
  end
  else
  begin
    if AX < FMinX then FMinX := AX;
    if AX > FMaxX then FMaxX := AX;
    if AY < FMinY then FMinY := AY;
    if AY > FMaxY then FMaxY := AY;
  end;
end;

procedure TBoundingBox.Expand(const P: TPoint2D);
begin
  Expand(P.X, P.Y);
end;

procedure TBoundingBox.Merge(const Other: TBoundingBox);
begin
  if Other.FIsEmpty then Exit;
  Expand(Other.FMinX, Other.FMinY);
  Expand(Other.FMaxX, Other.FMaxY);
end;

function TBoundingBox.Width: Double;
begin
  Result := FMaxX - FMinX;
end;

function TBoundingBox.Height: Double;
begin
  Result := FMaxY - FMinY;
end;

function TBoundingBox.Center: TPoint2D;
begin
  Result := TPoint2D.Create((FMinX + FMaxX) / 2.0, (FMinY + FMaxY) / 2.0);
end;

function TBoundingBox.ToRectF: TRectF;
begin
  Result := TRectF.Create(FMinX, FMinY, FMaxX, FMaxY);
end;

function TBoundingBox.Contains(const P: TPoint2D): Boolean;
begin
  Result := not FIsEmpty and
            (P.X >= FMinX) and (P.X <= FMaxX) and
            (P.Y >= FMinY) and (P.Y <= FMaxY);
end;

function TBoundingBox.Contains(AX, AY: Double): Boolean;
begin
  Result := not FIsEmpty and
            (AX >= FMinX) and (AX <= FMaxX) and
            (AY >= FMinY) and (AY <= FMaxY);
end;

function TBoundingBox.Intersects(const Other: TBoundingBox): Boolean;
begin
  Result := not FIsEmpty and not Other.FIsEmpty and
            (FMinX <= Other.FMaxX) and (FMaxX >= Other.FMinX) and
            (FMinY <= Other.FMaxY) and (FMaxY >= Other.FMinY);
end;

{ TViewport }

procedure TViewport.Reset;
begin
  FScale := 1.0;
  FPanX  := 0.0;
  FPanY  := 0.0;
end;

function TViewport.WorldToScreen(const P: TPoint2D): TPointF;
begin
  // X: sola kaydır + scale + ekran ortası
  // Y: Y-eksenini çevir (DXF: Y-up, Ekran: Y-down)
  Result.X := (P.X + FPanX) * FScale + FScreenWidth  * 0.5;
  Result.Y := FScreenHeight * 0.5 - (P.Y + FPanY) * FScale;
end;

function TViewport.WorldToScreen(AX, AY: Double): TPointF;
begin
  Result := WorldToScreen(TPoint2D.Create(AX, AY));
end;

function TViewport.ScreenToWorld(const P: TPointF): TPoint2D;
begin
  Result.X := (P.X - FScreenWidth  * 0.5) / FScale - FPanX;
  Result.Y := (FScreenHeight * 0.5 - P.Y) / FScale - FPanY;
end;

function TViewport.ScreenToWorld(AX, AY: Single): TPoint2D;
begin
  Result := ScreenToWorld(TPointF.Create(AX, AY));
end;

function TViewport.WorldLengthToScreen(ALength: Double): Single;
begin
  Result := ALength * FScale;
end;

procedure TViewport.FitToContent(const ABounds: TBoundingBox;
  AMarginFactor: Double);
var
  LAvailW, LAvailH: Double;
  LScaleX, LScaleY: Double;
  LCenter: TPoint2D;
begin
  if ABounds.IsEmpty or (FScreenWidth <= 0) or (FScreenHeight <= 0) then
  begin
    Reset;
    Exit;
  end;

  // Kullanılabilir ekran alanını margin ile hesapla
  LAvailW := FScreenWidth  * (1.0 - AMarginFactor * 2.0);
  LAvailH := FScreenHeight * (1.0 - AMarginFactor * 2.0);

  // İçeriğin genişlik ve yüksekliği sıfırsa varsayılan scale kullan
  if ABounds.Width < 1e-10 then
    LScaleX := 1.0
  else
    LScaleX := LAvailW / ABounds.Width;

  if ABounds.Height < 1e-10 then
    LScaleY := 1.0
  else
    LScaleY := LAvailH / ABounds.Height;

  // En küçük scale'i kullanarak oranları koruyoruz
  FScale := Min(LScaleX, LScaleY);

  // İçeriğin merkezini ekran merkezine hizala
  LCenter := ABounds.Center;
  FPanX := -LCenter.X;
  FPanY := -LCenter.Y;
end;

end.
