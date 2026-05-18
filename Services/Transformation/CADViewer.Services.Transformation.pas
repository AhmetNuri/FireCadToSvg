/// <summary>
/// CADViewer.Services.Transformation
/// Viewport/transform servisi implementasyonu.
/// ITransformService arayüzünü implement eder.
/// Zoom, Pan, FitToContent ve ekran boyutu değişikliği işlemlerini yönetir.
/// </summary>
unit CADViewer.Services.Transformation;

{$SCOPEDENUMS ON}

interface

uses
  System.Math,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces;

type

  /// <summary>
  /// ITransformService implementasyonu.
  /// Tüm koordinat dönüşümleri bu servis üzerinden yapılır.
  /// </summary>
  TTransformService = class(TInterfacedObject, ITransformService)
  private
    FViewport: TViewport;

    function GetViewport: TViewport;
    procedure SetViewport(const AViewport: TViewport);
  public
    constructor Create;

    // ITransformService implementasyonu
    procedure ZoomAt(AScreenX, AScreenY: Single; AFactor: Double);
    procedure Pan(ADeltaX, ADeltaY: Single);
    procedure FitToContent(const ABounds: TBoundingBox);
    procedure ResetView;
    procedure SetScreenSize(AWidth, AHeight: Single);

    property Viewport: TViewport read GetViewport write SetViewport;

    // Kısıtlamalar
    const MinScale = 1e-6;
    const MaxScale = 1e6;
  end;

implementation

{ TTransformService }

constructor TTransformService.Create;
begin
  inherited Create;
  FViewport.Reset;
  FViewport.ScreenWidth  := 800;
  FViewport.ScreenHeight := 600;
end;

function TTransformService.GetViewport: TViewport;
begin
  Result := FViewport;
end;

procedure TTransformService.SetViewport(const AViewport: TViewport);
begin
  FViewport := AViewport;
end;

procedure TTransformService.ZoomAt(AScreenX, AScreenY: Single;
  AFactor: Double);
var
  LWorldBefore: TPoint2D;
  LNewScale: Double;
  LWorldAfter: TPoint2D;
begin
  // Zoom merkezi noktanın dünya koordinatını hesapla (zoom öncesi)
  LWorldBefore := FViewport.ScreenToWorld(AScreenX, AScreenY);

  // Yeni scale hesapla (sınırlar içinde kal)
  LNewScale := FViewport.Scale * AFactor;
  LNewScale := Max(MinScale, Min(MaxScale, LNewScale));
  FViewport.Scale := LNewScale;

  // Zoom sonrası aynı ekran noktasının dünya koordinatı
  // Pan'ı ayarlayarak zoom merkezi noktasının yerinde kalmasını sağla
  LWorldAfter := FViewport.ScreenToWorld(AScreenX, AScreenY);

  // Pan farkı ekle: zoom öncesi dünya konumu - zoom sonrası dünya konumu
  FViewport.PanX := FViewport.PanX + (LWorldBefore.X - LWorldAfter.X);
  FViewport.PanY := FViewport.PanY + (LWorldBefore.Y - LWorldAfter.Y);
end;

procedure TTransformService.Pan(ADeltaX, ADeltaY: Single);
begin
  // Ekran pikseli farkını dünya koordinatına çevir
  // Y ekseni çevrildiğinden Y delta de çevrilir
  FViewport.PanX := FViewport.PanX + ADeltaX / FViewport.Scale;
  FViewport.PanY := FViewport.PanY - ADeltaY / FViewport.Scale;
end;

procedure TTransformService.FitToContent(const ABounds: TBoundingBox);
begin
  FViewport.FitToContent(ABounds);
end;

procedure TTransformService.ResetView;
begin
  FViewport.Reset;
end;

procedure TTransformService.SetScreenSize(AWidth, AHeight: Single);
begin
  FViewport.ScreenWidth  := AWidth;
  FViewport.ScreenHeight := AHeight;
end;

end.
