/// <summary>
/// CADViewer.Controllers.DxfViewerController
/// MVC Controller: View ile Model arasındaki koordinasyonu sağlar.
/// View sadece bu controller üzerinden işlem yapar; hiçbir iş mantığı
/// View katmanında yer almaz.
/// </summary>
unit CADViewer.Controllers.DxfViewerController;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.IOUtils,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces,
  CADViewer.Core.Models.DxfDocument,
  CADViewer.Parsers.DXF.Parser,
  CADViewer.Services.FileServices,
  CADViewer.Services.Transformation,
  CADViewer.Services.Rendering.DxfRenderer,
  CADViewer.Services.Export.SvgExporter;

type

  /// <summary>
  /// IViewerController implementasyonu.
  /// Tek sorumluluk: View olaylarını model/servis işlemlerine köprüler.
  /// Tüm UI bağımsız iş mantığı burada kalır.
  /// </summary>
  TDxfViewerController = class(TInterfacedObject, IViewerController)
  private
    // --- Bağımlılıklar (Dependency Injection friendly) ---
    FParserFactory: IParserFactory;
    FFileService: IFileService;
    FTransformService: ITransformService;
    FRenderer: TSkiaRenderer;
    FSvgExporter: ISvgExporter;

    // --- Durum ---
    FDocument: TDxfDocument;
    FDocumentTitle: string;
    FLastGeneratedSvg: string;
    FNeedsRedraw: Boolean;
    FIsPanning: Boolean;
    FPanStartX, FPanStartY: Single;

    // --- Gözlemciler ---
    FObservers: TInterfaceList;

    procedure NotifyDocumentLoaded(const ATitle: string);
    procedure NotifyDocumentError(const AMessage: string);
    procedure NotifyRenderRequested;
    procedure NotifyStatusChanged(const AMessage: string);

    procedure RequestRedraw; inline;

  public
    constructor Create(
      AParserFactory: IParserFactory;
      AFileService: IFileService;
      ATransformService: ITransformService;
      ARenderer: TSkiaRenderer;
      ASvgExporter: ISvgExporter);
    destructor Destroy; override;

    // IViewerController implementasyonu
    procedure LoadFile(const AFilePath: string);
    procedure FitToScreen;
    procedure ResetView;
    procedure OnZoom(AScreenX, AScreenY: Single; AWheelDelta: Integer);
    procedure OnPanStart(AScreenX, AScreenY: Single);
    procedure OnPanMove(AScreenX, AScreenY: Single);
    procedure OnPanEnd;
    procedure OnKeyMove(ADeltaX, ADeltaY: Single);
    procedure OnResize(AWidth, AHeight: Single);
    function GetZoomPercent: Integer;
    function GetDocumentTitle: string;
    function NeedsRedraw: Boolean;
    procedure ClearRedrawFlag;
    function GetLayerNames: TArray<string>;
    procedure SetLayerVisible(const AName: string; AVisible: Boolean);

    // --- Observer yönetimi ---
    procedure AddObserver(AObserver: IDocumentObserver);
    procedure RemoveObserver(AObserver: IDocumentObserver);

    // --- Renderer erişimi (View için) ---
    property Renderer: TSkiaRenderer read FRenderer;
    property TransformService: ITransformService read FTransformService;
    property Document: TDxfDocument read FDocument;
    property LastGeneratedSvg: string read FLastGeneratedSvg;
  end;

  /// <summary>
  /// Controller ve tüm bağımlılıklarını oluşturan fabrika metodu.
  /// Dışarıdan sadece bu çağrılarak controller elde edilir.
  /// </summary>
  TDxfViewerControllerFactory = class
  public
    /// <summary>Varsayılan bağımlılıklarla tam bir controller oluşturur.</summary>
    class function Create: TDxfViewerController; static;
  end;

implementation

uses
  CADViewer.Core.Entities;

{ TDxfViewerController }

constructor TDxfViewerController.Create(
  AParserFactory: IParserFactory;
  AFileService: IFileService;
  ATransformService: ITransformService;
  ARenderer: TSkiaRenderer;
  ASvgExporter: ISvgExporter);
begin
  inherited Create;
  FParserFactory   := AParserFactory;
  FFileService     := AFileService;
  FTransformService := ATransformService;
  FRenderer        := ARenderer;
  FSvgExporter     := ASvgExporter;
  FObservers       := TInterfaceList.Create;
  FNeedsRedraw     := False;
  FIsPanning       := False;
  FLastGeneratedSvg := '';
end;

destructor TDxfViewerController.Destroy;
begin
  FObservers.Free;
  FDocument.Free;
  FRenderer.Free;
  inherited Destroy;
end;

// -------------------------------------------------------------------------
// Observer yönetimi
// -------------------------------------------------------------------------

procedure TDxfViewerController.AddObserver(AObserver: IDocumentObserver);
begin
  if FObservers.IndexOf(AObserver) < 0 then
    FObservers.Add(AObserver);
end;

procedure TDxfViewerController.RemoveObserver(AObserver: IDocumentObserver);
begin
  FObservers.Remove(AObserver);
end;

procedure TDxfViewerController.NotifyDocumentLoaded(const ATitle: string);
var
  I: Integer;
begin
  for I := 0 to FObservers.Count - 1 do
    (FObservers[I] as IDocumentObserver).OnDocumentLoaded(ATitle);
end;

procedure TDxfViewerController.NotifyDocumentError(const AMessage: string);
var
  I: Integer;
begin
  for I := 0 to FObservers.Count - 1 do
    (FObservers[I] as IDocumentObserver).OnDocumentError(AMessage);
end;

procedure TDxfViewerController.NotifyRenderRequested;
var
  I: Integer;
begin
  for I := 0 to FObservers.Count - 1 do
    (FObservers[I] as IDocumentObserver).OnRenderRequested;
end;

procedure TDxfViewerController.NotifyStatusChanged(const AMessage: string);
var
  I: Integer;
begin
  for I := 0 to FObservers.Count - 1 do
    (FObservers[I] as IDocumentObserver).OnStatusChanged(AMessage);
end;

procedure TDxfViewerController.RequestRedraw;
begin
  FNeedsRedraw := True;
  NotifyRenderRequested;
end;

// -------------------------------------------------------------------------
// Dosya yükleme
// -------------------------------------------------------------------------

procedure TDxfViewerController.LoadFile(const AFilePath: string);
var
  LParser: IDxfParser;
  LFallbackParser: IDxfParser;
  LNewDoc: TDxfDocument;
  LFallbackDoc: TDxfDocument;
  LFallbackDxfPath: string;
  LFileSize: Int64;
  LFormat: TCadFileFormat;
begin
  NotifyStatusChanged('Dosya yükleniyor: ' + TPath.GetFileName(AFilePath));

  try
    // 1. Doğrulama
    FFileService.ValidateFile(AFilePath);

    LFileSize := FFileService.GetFileSize(AFilePath);
    NotifyStatusChanged(Format('Dosya boyutu: %.1f KB', [LFileSize / 1024.0]));

    // 2. Parser seç ve ayrıştır
    LFormat := FParserFactory.DetectFormat(AFilePath);
    LParser := FParserFactory.CreateParserForFormat(LFormat);
    LNewDoc := LParser.ParseFile(AFilePath);

    if (LFormat = TCadFileFormat.ffDwg) and
       ((LNewDoc = nil) or (LNewDoc.Shapes.Count = 0)) then
    begin
      LFallbackDxfPath := ChangeFileExt(AFilePath, '.dxf');
      if TFile.Exists(LFallbackDxfPath) then
      begin
        NotifyStatusChanged('DWG geometri boş; eşleşen DXF referansı deneniyor...');
        LFallbackParser := FParserFactory.CreateParserForFormat(TCadFileFormat.ffDxf);
        LFallbackDoc := LFallbackParser.ParseFile(LFallbackDxfPath);
        if (LFallbackDoc <> nil) and (LFallbackDoc.Shapes.Count > 0) then
        begin
          LNewDoc.Free;
          LNewDoc := LFallbackDoc;
          LFallbackDoc := nil;
          LNewDoc.ParseWarnings.Add(
            'DWG object stream bu sürümde çözümlenemedi; aynı isimli DXF referansı kullanıldı.');
          NotifyStatusChanged('DWG fallback aktif: geometri DXF referansından yüklendi.');
        end;
        LFallbackDoc.Free;
      end;
    end;

    if LNewDoc = nil then
      raise EDwgParseError.Create('DWG belgesi oluşturulamadı.');

    // 3. Eski belgeyi serbest bırak
    FreeAndNil(FDocument);
    FDocument := LNewDoc;

    FDocumentTitle := TPath.GetFileName(AFilePath);

    if Assigned(FSvgExporter) then
    begin
      if LFormat in [TCadFileFormat.ffStep, TCadFileFormat.ffIges,
                     TCadFileFormat.ffDwg] then
        FLastGeneratedSvg := FSvgExporter.ExportShapesToSvg(
          FDocument.Shapes, FDocument.GetBounds)
      else
        FLastGeneratedSvg := '';
    end;

    // 4. Renderer'ı güncelle
    FRenderer.SetShapes(FDocument.Shapes);
    FRenderer.SetDocument(FDocument);

    // 5. Ekrana sığdır
    var LBounds := FDocument.GetBounds;
    FTransformService.FitToContent(LBounds);

    // 6. Uyarıları logla
    if FDocument.ParseWarnings.Count > 0 then
      NotifyStatusChanged(Format('Yükleme tamamlandı (%d varlık, %d uyarı) — %s',
        [FDocument.EntityCount, FDocument.ParseWarnings.Count, FDocumentTitle]))
    else
      NotifyStatusChanged(Format('Yükleme tamamlandı (%d varlık) — %s',
        [FDocument.EntityCount, FDocumentTitle]));

    NotifyDocumentLoaded(FDocumentTitle);
    RequestRedraw;

  except
    on E: EFileServiceError do
    begin
      NotifyDocumentError('Dosya hatası: ' + E.Message);
      NotifyStatusChanged('Hata: ' + E.Message);
    end;
    on E: EDxfParseError do
    begin
      NotifyDocumentError('DXF ayrıştırma hatası: ' + E.Message);
      NotifyStatusChanged('Ayrıştırma hatası: ' + E.Message);
    end;
    on E: EStepParseError do
    begin
      NotifyDocumentError('STEP ayrıştırma hatası: ' + E.Message);
      NotifyStatusChanged('Ayrıştırma hatası: ' + E.Message);
    end;
    on E: EDwgParseError do
    begin
      NotifyDocumentError('DWG ayrıştırma hatası: ' + E.Message);
      NotifyStatusChanged('Ayrıştırma hatası: ' + E.Message);
    end;
    on E: EUnsupportedFormatError do
    begin
      NotifyDocumentError('Desteklenmeyen format: ' + E.Message);
      NotifyStatusChanged('Format hatası: ' + E.Message);
    end;
    on E: Exception do
    begin
      NotifyDocumentError('Beklenmeyen hata: ' + E.Message);
      NotifyStatusChanged('Hata: ' + E.Message);
    end;
  end;
end;

// -------------------------------------------------------------------------
// Görünüm işlemleri
// -------------------------------------------------------------------------

procedure TDxfViewerController.FitToScreen;
begin
  if FDocument <> nil then
  begin
    FTransformService.FitToContent(FDocument.GetBounds);
    NotifyStatusChanged(Format('Ekrana sığdırıldı — Zoom: %%%d',
      [GetZoomPercent]));
    RequestRedraw;
  end;
end;

procedure TDxfViewerController.ResetView;
begin
  FTransformService.ResetView;
  NotifyStatusChanged('Görünüm sıfırlandı');
  RequestRedraw;
end;

procedure TDxfViewerController.OnZoom(AScreenX, AScreenY: Single;
  AWheelDelta: Integer);
const
  ZoomStep = 1.15; // %15 adım
var
  LFactor: Double;
begin
  if AWheelDelta > 0 then
    LFactor := ZoomStep
  else
    LFactor := 1.0 / ZoomStep;

  FTransformService.ZoomAt(AScreenX, AScreenY, LFactor);
  NotifyStatusChanged(Format('Zoom: %%%d', [GetZoomPercent]));
  RequestRedraw;
end;

procedure TDxfViewerController.OnPanStart(AScreenX, AScreenY: Single);
begin
  FIsPanning  := True;
  FPanStartX  := AScreenX;
  FPanStartY  := AScreenY;
end;

procedure TDxfViewerController.OnPanMove(AScreenX, AScreenY: Single);
begin
  if not FIsPanning then Exit;

  FTransformService.Pan(
    AScreenX - FPanStartX,
    AScreenY - FPanStartY);

  FPanStartX := AScreenX;
  FPanStartY := AScreenY;

  RequestRedraw;
end;

procedure TDxfViewerController.OnPanEnd;
begin
  FIsPanning := False;
end;

procedure TDxfViewerController.OnKeyMove(ADeltaX, ADeltaY: Single);
const
  KeyPanStep = 20; // Piksel
begin
  FTransformService.Pan(ADeltaX * KeyPanStep, ADeltaY * KeyPanStep);
  RequestRedraw;
end;

procedure TDxfViewerController.OnResize(AWidth, AHeight: Single);
begin
  FTransformService.SetScreenSize(AWidth, AHeight);
  // Boyut değişince da sığdır (opsiyonel: sadece redraw da yapılabilir)
  RequestRedraw;
end;

// -------------------------------------------------------------------------
// Durum sorgulama
// -------------------------------------------------------------------------

function TDxfViewerController.GetZoomPercent: Integer;
begin
  Result := Round(FTransformService.Viewport.Scale * 100);
end;

function TDxfViewerController.GetDocumentTitle: string;
begin
  Result := FDocumentTitle;
end;

function TDxfViewerController.NeedsRedraw: Boolean;
begin
  Result := FNeedsRedraw;
end;

procedure TDxfViewerController.ClearRedrawFlag;
begin
  FNeedsRedraw := False;
end;

function TDxfViewerController.GetLayerNames: TArray<string>;
begin
  if FDocument <> nil then
    Result := FDocument.GetLayerNames
  else
    Result := [];
end;

procedure TDxfViewerController.SetLayerVisible(const AName: string;
  AVisible: Boolean);
begin
  if FDocument <> nil then
  begin
    var LLayer := FDocument.FindLayer(AName);
    if LLayer <> nil then
      LLayer.Visible := AVisible;
  end;
  FRenderer.SetLayerVisibility(AName, AVisible);
  RequestRedraw;
end;

// =========================================================================
// TDxfViewerControllerFactory
// =========================================================================

class function TDxfViewerControllerFactory.Create: TDxfViewerController;
var
  LParserFactory: IParserFactory;
  LFileService: IFileService;
  LTransformService: ITransformService;
  LRenderer: TSkiaRenderer;
  LSvgExporter: ISvgExporter;
begin
  LParserFactory   := TParserFactory.Create;
  LFileService     := TFileService.Create;
  LTransformService := TTransformService.Create;
  LRenderer        := TSkiaRenderer.Create;
  LSvgExporter     := TSvgExporter.Create;

  Result := TDxfViewerController.Create(
    LParserFactory,
    LFileService,
    LTransformService,
    LRenderer,
    LSvgExporter);
end;

end.
