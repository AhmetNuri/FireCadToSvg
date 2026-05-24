/// <summary>
/// CADViewer.Services.Rendering.DxfRenderer
/// Skia4Delphi tabanlı yüksek kaliteli DXF renderer.
/// ICanvasRenderer arayüzünü implement eder.
/// TDrawShape hiyerarşisindeki tüm şekil türlerini çizer.
/// Anti-aliasing, visible entity optimizasyonu ve katman desteği içerir.
/// </summary>
unit CADViewer.Services.Rendering.DxfRenderer;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  Skia,
  fmx.Skia,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces,
  CADViewer.Core.Models.DrawShapes,
  CADViewer.Core.Models.DxfDocument,
  CADViewer.Utils;

type

  // =========================================================================
  // TSkiaRenderer — Ana Skia renderer
  // =========================================================================

  /// <summary>
  /// ICanvasRenderer implementasyonu. Skia canvas üzerinde çizim yapar.
  /// Renderer ISkCanvas'a bağımlıdır; her OnDraw çağrısında SetCanvas ile
  /// güncellenir.
  /// </summary>
  TSkiaRenderer = class(TInterfacedObject, ICanvasRenderer)
  private
    FCanvas: ISkCanvas;
    FShapes: TDrawShapeList;           // Sahiplik dışarıda
    FDocument: TDxfDocument;          // Katman bilgileri için (opsiyonel)
    FBackgroundColor: TAlphaColor;
    FAntiAlias: Boolean;
    FLayerVisibility: TDictionary<string, Boolean>;
    FLastViewport: TViewport;

    // --- Paint fabrikası ---
    function MakeStrokePaint(const AStyle: TDrawStyle;
      const AViewport: TViewport): ISkPaint;
    function MakeFillPaint(const AStyle: TDrawStyle): ISkPaint;

    // --- Çizgi tipi desteği ---
    procedure ApplyLineType(APaint: ISkPaint; const AStyle: TDrawStyle;
      const AViewport: TViewport);

    // --- Katman görünürlük kontrolü ---
    function IsShapeVisible(AShape: TDrawShape;
      const AViewport: TViewport): Boolean;

    // --- Şekil çizimleri (her tip için ayrı metod: Strategy) ---
    procedure RenderLine(AShape: TDrawLine;
      const AViewport: TViewport);
    procedure RenderCircle(AShape: TDrawCircle;
      const AViewport: TViewport);
    procedure RenderArc(AShape: TDrawArc;
      const AViewport: TViewport);
    procedure RenderEllipse(AShape: TDrawEllipse;
      const AViewport: TViewport);
    procedure RenderPolyline(AShape: TDrawPolyline;
      const AViewport: TViewport);
    procedure RenderText(AShape: TDrawText;
      const AViewport: TViewport);
    procedure RenderPath(AShape: TDrawPath;
      const AViewport: TViewport);
    procedure RenderPoint(AShape: TDrawPoint;
      const AViewport: TViewport);
    procedure RenderComposite(AShape: TDrawComposite;
      const AViewport: TViewport);

    /// <summary>Bulge'lu polyline segmentini yay olarak çizer.</summary>
    procedure DrawPolylineSegment(
      const P1, P2: TPoint2D; ABulge: Double;
      APaint: ISkPaint; const AViewport: TViewport);

    /// <summary>Yay çizimi için Skia path oluşturur.</summary>
    procedure DrawArcOnCanvas(
      const ACenter: TPoint2D; ARadius: Double;
      AStartDeg, AEndDeg: Double;
      APaint: ISkPaint; const AViewport: TViewport);

    /// <summary>Tek TDrawShape'i dispatch eder.</summary>
    procedure RenderShape(AShape: TDrawShape; const AViewport: TViewport);

    function GetLayerVisible(const ALayerName: string): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Mevcut Skia canvas'ını ayarlar. Her OnDraw çağrısında çağrılmalı.</summary>
    procedure SetCanvas(ACanvas: ISkCanvas);

    // ICanvasRenderer implementasyonu
    procedure SetShapes(AShapes: TDrawShapeList);
    procedure Render(const AViewport: TViewport);
    procedure SetLayerVisibility(const ALayerName: string; AVisible: Boolean);
    procedure SetBackgroundColor(AColor: TAlphaColor);
    procedure SetAntiAlias(AEnabled: Boolean);

    /// <summary>Renderer'ı belge ile ilişkilendirir (katman bilgileri için).</summary>
    procedure SetDocument(ADocument: TDxfDocument);
  end;

implementation

uses
  System.Types;

// Skia renk yardımcısı
function SkColorFromAlpha(AColor: TAlphaColor): TAlphaColor;
begin
  Result := AColor; // TAlphaColor ile TSkColor aynı ARGB formatı
end;

{ TSkiaRenderer }

constructor TSkiaRenderer.Create;
begin
  inherited Create;
  FBackgroundColor := $FF1E1E1E; // Koyu arkaplan (AutoCAD gibi)
  FAntiAlias := True;
  FLayerVisibility := TDictionary<string, Boolean>.Create;
end;

destructor TSkiaRenderer.Destroy;
begin
  FLayerVisibility.Free;
  inherited Destroy;
end;

procedure TSkiaRenderer.SetCanvas(ACanvas: ISkCanvas);
begin
  FCanvas := ACanvas;
end;

procedure TSkiaRenderer.SetShapes(AShapes: TDrawShapeList);
begin
  FShapes := AShapes; // Sahiplik dışarıda — sadece referans
end;

procedure TSkiaRenderer.SetDocument(ADocument: TDxfDocument);
begin
  FDocument := ADocument;
end;

procedure TSkiaRenderer.SetBackgroundColor(AColor: TAlphaColor);
begin
  FBackgroundColor := AColor;
end;

procedure TSkiaRenderer.SetAntiAlias(AEnabled: Boolean);
begin
  FAntiAlias := AEnabled;
end;

procedure TSkiaRenderer.SetLayerVisibility(const ALayerName: string;
  AVisible: Boolean);
begin
  FLayerVisibility.AddOrSetValue(UpperCase(ALayerName), AVisible);
end;

function TSkiaRenderer.GetLayerVisible(const ALayerName: string): Boolean;
var
  LVisible: Boolean;
begin
  // Önce manuel override kontrolü
  if FLayerVisibility.TryGetValue(UpperCase(ALayerName), LVisible) then
    Exit(LVisible);

  // Sonra belge layer tablosu kontrolü
  if FDocument <> nil then
  begin
    var LLayer := FDocument.FindLayer(ALayerName);
    if LLayer <> nil then
      Exit(LLayer.IsEffectivelyVisible);
  end;

  Result := True; // Varsayılan: görünür
end;

// -------------------------------------------------------------------------
// Paint fabrikası
// -------------------------------------------------------------------------

function TSkiaRenderer.MakeStrokePaint(const AStyle: TDrawStyle;
  const AViewport: TViewport): ISkPaint;
var
  LPaint: ISkPaint;
  LWidth: Single;
begin
  LPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  LPaint.Color := SkColorFromAlpha(AStyle.StrokeColor);
  LPaint.AntiAlias := FAntiAlias;
  LPaint.StrokeCap := TSkStrokeCap.Round;
  LPaint.StrokeJoin := TSkStrokeJoin.Round;

  // Çizgi kalınlığını viewport scale'e göre sınırla (çok ince veya kalın olmasın)
  LWidth := Max(0.5, AStyle.StrokeWidth);
  LPaint.StrokeWidth := LWidth;

  // Opacity
  if AStyle.Opacity < 1.0 then
    LPaint.AlphaF := AStyle.Opacity;

  ApplyLineType(LPaint, AStyle, AViewport);
  Result := LPaint;
end;

function TSkiaRenderer.MakeFillPaint(const AStyle: TDrawStyle): ISkPaint;
var
  LPaint: ISkPaint;
begin
  if not AStyle.HasFill then Exit(nil);

  LPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  LPaint.Color := SkColorFromAlpha(AStyle.FillColor);
  LPaint.AntiAlias := FAntiAlias;
  if AStyle.Opacity < 1.0 then
    LPaint.AlphaF := AStyle.Opacity;
  Result := LPaint;
end;

procedure TSkiaRenderer.ApplyLineType(APaint: ISkPaint;
  const AStyle: TDrawStyle; const AViewport: TViewport);
var
  LScale: Single;
  LDash: TArray<Single>;
begin
  if AStyle.LineType = TDxfLineType.ltContinuous then Exit;

  LScale := Max(1.0, AViewport.Scale * AStyle.LtScale);

  // DXF standart dash pattern'ları (birim: dünya koordinatı * scale)
  case AStyle.LineType of
    TDxfLineType.ltDashed:
      LDash := [12 * LScale, 6 * LScale];
    TDxfLineType.ltDotted:
      LDash := [1 * LScale, 4 * LScale];
    TDxfLineType.ltDashDot:
      LDash := [12 * LScale, 4 * LScale, 1 * LScale, 4 * LScale];
    TDxfLineType.ltCenter:
      LDash := [24 * LScale, 6 * LScale, 6 * LScale, 6 * LScale];
    TDxfLineType.ltHidden:
      LDash := [6 * LScale, 4 * LScale];
    TDxfLineType.ltPhantom:
      LDash := [24 * LScale, 4 * LScale, 6 * LScale, 4 * LScale,
                6 * LScale, 4 * LScale];
    else Exit;
  end;

  APaint.PathEffect := TSkPathEffect.MakeDash(LDash, 0);
end;

// -------------------------------------------------------------------------
// Görünürlük kontrolü + bounding box culling
// -------------------------------------------------------------------------

function TSkiaRenderer.IsShapeVisible(AShape: TDrawShape;
  const AViewport: TViewport): Boolean;
var
  LBounds: TBoundingBox;
  LScreenMin, LScreenMax: TPointF;
begin
  if not AShape.Visible then Exit(False);
  if not GetLayerVisible(AShape.LayerName) then Exit(False);

  // Bounding box ekran dışındaysa çizme (frustum culling)
  LBounds := AShape.GetBounds;
  if LBounds.IsEmpty then Exit(True); // Bounds hesaplanamıyorsa göster

  LScreenMin := AViewport.WorldToScreen(LBounds.MinX, LBounds.MinY);
  LScreenMax := AViewport.WorldToScreen(LBounds.MaxX, LBounds.MaxY);

  // Min/Max'ı düzelt (Y-flip nedeniyle min/max yer değiştirebilir)
  var LMinX := Min(LScreenMin.X, LScreenMax.X);
  var LMaxX := Max(LScreenMin.X, LScreenMax.X);
  var LMinY := Min(LScreenMin.Y, LScreenMax.Y);
  var LMaxY := Max(LScreenMin.Y, LScreenMax.Y);

  // Ekran sınırlarına biraz pay ekle (1 pixel)
  Result := (LMaxX >= -1) and (LMinX <= AViewport.ScreenWidth  + 1) and
            (LMaxY >= -1) and (LMinY <= AViewport.ScreenHeight + 1);
end;

// -------------------------------------------------------------------------
// Ana render metodu
// -------------------------------------------------------------------------

procedure TSkiaRenderer.Render(const AViewport: TViewport);
var
  LShape: TDrawShape;
begin
  if FCanvas = nil then Exit;

  FLastViewport := AViewport;

  // Arkaplan temizle
  FCanvas.Clear(FBackgroundColor);

  if FShapes = nil then Exit;

  // Tüm şekilleri sırası ile çiz (katman sırasına göre sıralama yapılabilir)
  for LShape in FShapes do
  begin
    if IsShapeVisible(LShape, AViewport) then
    try
      RenderShape(LShape, AViewport);
    except
      // Tek şeklin hatası diğerlerini durdurmamalı
    end;
  end;
end;

procedure TSkiaRenderer.RenderShape(AShape: TDrawShape;
  const AViewport: TViewport);
begin
  if AShape is TDrawLine then
    RenderLine(TDrawLine(AShape), AViewport)
  else if AShape is TDrawCircle then
    RenderCircle(TDrawCircle(AShape), AViewport)
  else if AShape is TDrawArc then
    RenderArc(TDrawArc(AShape), AViewport)
  else if AShape is TDrawEllipse then
    RenderEllipse(TDrawEllipse(AShape), AViewport)
  else if AShape is TDrawPolyline then
    RenderPolyline(TDrawPolyline(AShape), AViewport)
  else if AShape is TDrawText then
    RenderText(TDrawText(AShape), AViewport)
  else if AShape is TDrawPath then
    RenderPath(TDrawPath(AShape), AViewport)
  else if AShape is TDrawPoint then
    RenderPoint(TDrawPoint(AShape), AViewport)
  else if AShape is TDrawComposite then
    RenderComposite(TDrawComposite(AShape), AViewport);
end;

// -------------------------------------------------------------------------
// LINE
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderLine(AShape: TDrawLine;
  const AViewport: TViewport);
var
  LP1, LP2: TPointF;
  LPaint: ISkPaint;
begin
  LP1 := AViewport.WorldToScreen(AShape.StartPoint);
  LP2 := AViewport.WorldToScreen(AShape.EndPoint);
  LPaint := MakeStrokePaint(AShape.Style, AViewport);
  FCanvas.DrawLine(LP1, LP2, LPaint);
end;

// -------------------------------------------------------------------------
// CIRCLE
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderCircle(AShape: TDrawCircle;
  const AViewport: TViewport);
var
  LCenter: TPointF;
  LRadius: Single;
  LPaint: ISkPaint;
begin
  LCenter := AViewport.WorldToScreen(AShape.Center);
  LRadius := AViewport.WorldLengthToScreen(AShape.Radius);

  if LRadius < 0.5 then
  begin
    // Çok küçük daire → nokta olarak çiz
    LPaint := MakeStrokePaint(AShape.Style, AViewport);
    FCanvas.DrawCircle(LCenter.X, LCenter.Y, 0.5, LPaint);
    Exit;
  end;

  // Doldurma (varsa)
  var LFillPaint := MakeFillPaint(AShape.Style);
  if LFillPaint <> nil then
    FCanvas.DrawCircle(LCenter.X, LCenter.Y, LRadius, LFillPaint);

  // Kenar
  LPaint := MakeStrokePaint(AShape.Style, AViewport);
  FCanvas.DrawCircle(LCenter.X, LCenter.Y, LRadius, LPaint);
end;

// -------------------------------------------------------------------------
// ARC
// -------------------------------------------------------------------------

procedure TSkiaRenderer.DrawArcOnCanvas(
  const ACenter: TPoint2D; ARadius: Double;
  AStartDeg, AEndDeg: Double;
  APaint: ISkPaint; const AViewport: TViewport);
var
  LCenter: TPointF;
  LRadius: Single;
  LRect: TRectF;
  LSweep: Double;
  LPath: ISkPathBuilder;
begin
  LCenter := AViewport.WorldToScreen(ACenter);
  LRadius := AViewport.WorldLengthToScreen(ARadius);

  if LRadius < 0.5 then
  begin
    FCanvas.DrawCircle(LCenter.X, LCenter.Y, 0.5, APaint);
    Exit;
  end;

  LRect := TRectF.Create(
    LCenter.X - LRadius, LCenter.Y - LRadius,
    LCenter.X + LRadius, LCenter.Y + LRadius);

  // DXF CCW açıları → Skia CW dönüşümü (Y-flip nedeniyle)
  // Skia: startAngle 3 saat yönünde, sweepAngle pozitif = CW
  // DXF:  startAngle 3 saat yönünde, sweepAngle pozitif = CCW
  // Y-flip sonrasında CCW → CW dönüşür, bu yüzden negatif sweep kullanırız.
  var LStartSkia := -AStartDeg; // Y ekseni çevrildiğinden açıyı negatif yap
  LSweep := TDxfMathUtils.ArcSweepCCW(AStartDeg, AEndDeg);
  var LSweepSkia := -LSweep; // CCW → CW

  LPath := TSkPathBuilder.Create;
  LPath.ArcTo(LRect, LStartSkia, LSweepSkia, True);
  FCanvas.DrawPath(LPath.Detach, APaint);
end;

procedure TSkiaRenderer.RenderArc(AShape: TDrawArc;
  const AViewport: TViewport);
var
  LPaint: ISkPaint;
begin
  LPaint := MakeStrokePaint(AShape.Style, AViewport);
  DrawArcOnCanvas(AShape.Center, AShape.Radius,
    AShape.StartAngleDeg, AShape.EndAngleDeg,
    LPaint, AViewport);
end;

// -------------------------------------------------------------------------
// ELLIPSE
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderEllipse(AShape: TDrawEllipse;
  const AViewport: TViewport);
var
  LCenter: TPointF;
  LMajR, LMinR: Single;
  LRotDeg: Double;
  LRect: TRectF;
  LPaint: ISkPaint;
  LPath: ISkPathBuilder;
begin
  LCenter := AViewport.WorldToScreen(AShape.Center);
  LMajR := AViewport.WorldLengthToScreen(AShape.MajorRadius);
  LMinR := LMajR * AShape.MinorToMajorRatio;
  LRotDeg := AShape.RotationAngleDeg;

  LRect := TRectF.Create(
    LCenter.X - LMajR, LCenter.Y - LMinR,
    LCenter.X + LMajR, LCenter.Y + LMinR);

  // Döndürme için canvas save/restore
  FCanvas.Save;
  try
    FCanvas.Translate(LCenter.X, LCenter.Y);
    FCanvas.Rotate(-LRotDeg); // Y-flip nedeniyle negatif
    FCanvas.Translate(-LCenter.X, -LCenter.Y);

    LPaint := MakeStrokePaint(AShape.Style, AViewport);

    if AShape.IsFullEllipse then
    begin
      var LFillPaint := MakeFillPaint(AShape.Style);
      if LFillPaint <> nil then
        FCanvas.DrawOval(LRect, LFillPaint);
      FCanvas.DrawOval(LRect, LPaint);
    end
    else
    begin
      // Kısmi elips için arc
      var LStartDeg := RadToDeg(AShape.StartParam);
      var LEndDeg := RadToDeg(AShape.EndParam);
      var LSweep := -(LEndDeg - LStartDeg); // Y-flip

      LPath := TSkPathBuilder.Create;
      LPath.ArcTo(LRect, -LStartDeg, LSweep, True);
      FCanvas.DrawPath(LPath.Detach, LPaint);
    end;
  finally
    FCanvas.Restore;
  end;
end;

// -------------------------------------------------------------------------
// POLYLINE
// -------------------------------------------------------------------------

procedure TSkiaRenderer.DrawPolylineSegment(
  const P1, P2: TPoint2D; ABulge: Double;
  APaint: ISkPaint; const AViewport: TViewport);
var
  LArcCenter: TPoint2D;
  LArcRadius: Double;
  LStartAng, LEndAng: Double;
begin
  if Abs(ABulge) < 1e-10 then
  begin
    // Düz çizgi segmenti
    FCanvas.DrawLine(
      AViewport.WorldToScreen(P1),
      AViewport.WorldToScreen(P2),
      APaint);
  end
  else
  begin
    // Yaylı segment
    TDxfMathUtils.BulgeToArc(P1, P2, ABulge,
      LArcCenter, LArcRadius, LStartAng, LEndAng);
    DrawArcOnCanvas(LArcCenter, LArcRadius, LStartAng, LEndAng,
      APaint, AViewport);
  end;
end;

procedure TSkiaRenderer.RenderPolyline(AShape: TDrawPolyline;
  const AViewport: TViewport);
var
  I: Integer;
  LPoints: TArray<TPolylinePoint>;
  LPaint: ISkPaint;
  LCount: Integer;
begin
  LPoints := AShape.Points;
  LCount  := Length(LPoints);
  if LCount < 2 then
  begin
    // Tek nokta varsa nokta olarak çiz
    if LCount = 1 then
    begin
      var LPt := AViewport.WorldToScreen(LPoints[0].Position);
      LPaint := MakeStrokePaint(AShape.Style, AViewport);
      LPaint.StrokeWidth := Max(2.0, LPaint.StrokeWidth);
      FCanvas.DrawCircle(LPt.X, LPt.Y, 0.5, LPaint);
    end;
    Exit;
  end;

  LPaint := MakeStrokePaint(AShape.Style, AViewport);

  // Her segment ayrı ayrı çizilir (bulge desteği için)
  for I := 0 to LCount - 2 do
    DrawPolylineSegment(
      LPoints[I].Position,
      LPoints[I + 1].Position,
      LPoints[I].Bulge,
      LPaint, AViewport);

  // Kapalıysa son ve ilk noktayı bağla
  if AShape.IsClosed and (LCount >= 3) then
    DrawPolylineSegment(
      LPoints[LCount - 1].Position,
      LPoints[0].Position,
      LPoints[LCount - 1].Bulge,
      LPaint, AViewport);
end;

// -------------------------------------------------------------------------
// TEXT
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderText(AShape: TDrawText;
  const AViewport: TViewport);
var
  LPos: TPointF;
  LFontSize: Single;
  LFont: ISkFont;
  LPaint: ISkPaint;
  LContent: string;
  LTypeface: ISkTypeface;
begin
  LContent := AShape.Content;
  if LContent = '' then Exit;

  LPos := AViewport.WorldToScreen(AShape.Position);
  LFontSize := Max(4.0, AViewport.WorldLengthToScreen(AShape.FontHeight));

  // Çok küçük boyutlarda metin çizme (performans + okunaksızlık)
  if LFontSize < 3.0 then Exit;

  // Yazı tipi
  if AShape.FontName <> '' then
    LTypeface := TSkTypeface.MakeFromName(AShape.FontName, TSkFontStyle.Normal)
  else
    LTypeface := TSkTypeface.MakeDefault;

  LFont := TSkFont.Create(LTypeface, LFontSize);
  LFont.Edging := TSkFontEdging.SubpixelAntiAlias;

  LPaint := TSkPaint.Create;
  LPaint.Color := SkColorFromAlpha(AShape.Style.StrokeColor);
  LPaint.AntiAlias := FAntiAlias;

  // Döndürme ve ölçek dönüşümü
  FCanvas.Save;
  try
    FCanvas.Translate(LPos.X, LPos.Y);
    FCanvas.Rotate(-AShape.RotationDeg); // Y-flip nedeniyle negatif
    if AShape.WidthFactor <> 1.0 then
      FCanvas.Scale(AShape.WidthFactor, 1.0);

    // Hizalama için offset
    var LBounds: TRectF;
    LFont.MeasureText(LContent, LBounds, LPaint);

    var LOffsetX: Single := 0;
    var LOffsetY: Single := 0;

    case AShape.HAlign of
      TDxfTextHAlign.haCenter: LOffsetX := -LBounds.Width / 2;
      TDxfTextHAlign.haRight:  LOffsetX := -LBounds.Width;
    end;

    case AShape.VAlign of
      TDxfTextVAlign.vaMiddle: LOffsetY := LBounds.Height / 2;
      TDxfTextVAlign.vaTop:    LOffsetY := LBounds.Height;
      TDxfTextVAlign.vaBottom: LOffsetY := 0;
      else                     LOffsetY := 0; // Baseline
    end;

    // MText: çok satırlı metin için satır satır çiz
    if AShape.IsMText and (Pos(sLineBreak, LContent) > 0) then
    begin
      var LLines := LContent.Split([sLineBreak, '\n', '\P'], TStringSplitOptions.None);
      var LLineY := LOffsetY;
      for var LLine in LLines do
      begin
        FCanvas.DrawSimpleText(LLine, LOffsetX, LLineY, LFont, LPaint);
        LLineY := LLineY + LFontSize * 1.4; // Satır aralığı
      end;
    end
    else
      FCanvas.DrawSimpleText(LContent, LOffsetX, LOffsetY, LFont, LPaint);

  finally
    FCanvas.Restore;
  end;
end;

// -------------------------------------------------------------------------
// PATH (SPLINE ve diğer eğriler)
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderPath(AShape: TDrawPath;
  const AViewport: TViewport);
var
  LPath: ISkPathBuilder;
  LPoints: TArray<TPoint2D>;
  LPaint: ISkPaint;
  I: Integer;
  LPt: TPointF;
begin
  LPoints := AShape.Points;
  if Length(LPoints) < 2 then Exit;

  LPath := TSkPathBuilder.Create;
  LPt := AViewport.WorldToScreen(LPoints[0]);
  LPath.MoveTo(LPt);

  for I := 1 to High(LPoints) do
  begin
    LPt := AViewport.WorldToScreen(LPoints[I]);
    LPath.LineTo(LPt);
  end;

  if AShape.IsClosed then
    LPath.Close;

  LPaint := MakeStrokePaint(AShape.Style, AViewport);

  if AShape.IsClosed then
  begin
    var LFillPaint := MakeFillPaint(AShape.Style);
    if LFillPaint <> nil then
      FCanvas.DrawPath(LPath.Snapshot, LFillPaint);
  end;

  FCanvas.DrawPath(LPath.Detach, LPaint);
end;

// -------------------------------------------------------------------------
// POINT
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderPoint(AShape: TDrawPoint;
  const AViewport: TViewport);
var
  LPt: TPointF;
  LPaint: ISkPaint;
  LSize: Single;
begin
  LPt := AViewport.WorldToScreen(AShape.Position);
  LPaint := MakeStrokePaint(AShape.Style, AViewport);
  LSize := Max(2.0, AShape.Style.StrokeWidth + 1.0);

  // Nokta: küçük çapraz (+) olarak çiz
  FCanvas.DrawLine(
    TPointF.Create(LPt.X - LSize, LPt.Y),
    TPointF.Create(LPt.X + LSize, LPt.Y), LPaint);
  FCanvas.DrawLine(
    TPointF.Create(LPt.X, LPt.Y - LSize),
    TPointF.Create(LPt.X, LPt.Y + LSize), LPaint);
end;

// -------------------------------------------------------------------------
// COMPOSITE (INSERT / Block Reference)
// -------------------------------------------------------------------------

procedure TSkiaRenderer.RenderComposite(AShape: TDrawComposite;
  const AViewport: TViewport);
var
  LChild: TDrawShape;
  LInsertScreen: TPointF;
  LBaseScreen: TPointF;
begin
  // Blok içeriğini doküman üzerinden bul ve render et
  if (FDocument <> nil) and (AShape.BlockName <> '') then
  begin
    var LBlock := FDocument.FindBlock(AShape.BlockName);
    if LBlock <> nil then
    begin
      // Transform: INSERT noktasına taşı + döndür + ölçekle
      FCanvas.Save;
      try
        LInsertScreen := AViewport.WorldToScreen(AShape.InsertionPoint);
        LBaseScreen := AViewport.WorldToScreen(LBlock.BasePoint);

        // Önce blok taban noktasını insert noktasına taşı
        FCanvas.Translate(
          LInsertScreen.X - LBaseScreen.X,
          LInsertScreen.Y - LBaseScreen.Y);

        // Sonra insert noktası etrafında dönüşüm uygula
        FCanvas.Translate(LInsertScreen.X, LInsertScreen.Y);
        FCanvas.Rotate(-AShape.RotationDeg);
        FCanvas.Scale(AShape.ScaleX, AShape.ScaleY);
        FCanvas.Translate(-LInsertScreen.X, -LInsertScreen.Y);

        // Blok içindeki şekilleri çiz
        for LChild in LBlock.Shapes do
        begin
          if LChild.Visible and GetLayerVisible(LChild.LayerName) then
          try
            RenderShape(LChild, AViewport);
          except
            // Hata toleransı
          end;
        end;
      finally
        FCanvas.Restore;
      end;
      Exit;
    end;
  end;

  // Blok bulunamadıysa çocuk listesini doğrudan çiz
  for LChild in AShape.Children do
  begin
    if LChild.Visible then
    try
      RenderShape(LChild, AViewport);
    except
    end;
  end;
end;

end.
