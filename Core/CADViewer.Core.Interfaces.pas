/// <summary>
/// CADViewer.Core.Interfaces
/// Tüm servis, parser ve renderer arayüzleri.
/// Open-Closed Principle: Yeni format veya renderer eklemek için
/// sadece bu interface'leri implement eden yeni sınıflar yazılır,
/// mevcut kod değiştirilmez.
/// </summary>
unit CADViewer.Core.Interfaces;

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.Generics.Collections,
    system.SysUtils,
    System.UITypes,
  CADViewer.Core.Types,

  CADViewer.Core.Models.DrawShapes,
  CADViewer.Core.Models.DxfDocument;

type

  // =========================================================================
  // IDxfReader — Düşük seviye DXF okuyucu
  // =========================================================================

  /// <summary>
  /// DXF dosyasını group code / value çiftleri (token) olarak okur.
  /// Dosya veya ham string içeriğinden okuma yapabilir.
  /// Encoding tespiti bu katmanda gerçekleşir.
  /// </summary>
  IDxfReader = interface
    ['{3F8A1C2D-7E4B-4F9A-BC12-E5D8F3A69201}']

    /// <summary>Dosyadan okuma başlatır.</summary>
    procedure OpenFile(const AFilePath: string);

    /// <summary>Ham string içeriğinden okuma başlatır.</summary>
    procedure OpenContent(const AContent: string);

    /// <summary>Kaynağı kapatır ve belleği serbest bırakır.</summary>
    procedure Close;

    /// <summary>Sonraki group code / value çiftini okur. EOF'da False döner.</summary>
    function ReadNext(out AGroupCode: Integer; out AValue: string): Boolean;

    /// <summary>Dosyanın sonuna gelindi mi?</summary>
    function IsEof: Boolean;

    /// <summary>Geçerli satır numarası (hata raporlama için).</summary>
    function CurrentLine: Integer;
  end;

  // =========================================================================
  // IDxfParser — Yüksek seviye DXF ayrıştırıcı
  // =========================================================================

  /// <summary>
  /// DXF içeriğini ayrıştırarak TDxfDocument modeli oluşturur.
  /// Farklı DXF versiyonları bu interface üzerinden desteklenir.
  /// </summary>
  IDxfParser = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']

    /// <summary>Belirtilen dosyayı ayrıştırır.</summary>
    function ParseFile(const AFilePath: string): TDxfDocument;

    /// <summary>Ham DXF string içeriğini ayrıştırır.</summary>
    function ParseContent(const AContent: string): TDxfDocument;

    /// <summary>Ayrıştırma sırasında oluşan uyarı ve hata mesajları.</summary>
    function GetWarnings: TArray<string>;
  end;

  // =========================================================================
  // IParserFactory — Factory: doğru parser'ı seçer
  // =========================================================================

  /// <summary>
  /// Dosya uzantısı veya içerik analizi ile uygun parser'ı döndürür.
  /// Yeni format (DWG, IGES vb.) desteklendiğinde sadece bu factory
  /// güncellenir.
  /// </summary>
  IParserFactory = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']

    /// <summary>Dosya yolundan uygun parser'ı döndürür.</summary>
    function CreateParser(const AFilePath: string): IDxfParser;

    /// <summary>Format tipine göre parser döndürür.</summary>
    function CreateParserForFormat(AFormat: TCadFileFormat): IDxfParser;

    /// <summary>Dosya uzantısından format tipini tespit eder.</summary>
    function DetectFormat(const AFilePath: string): TCadFileFormat;
  end;

  // =========================================================================
  // IFileService — Dosya servis arayüzü
  // =========================================================================

  /// <summary>
  /// CAD dosyalarının yüklenmesi, encoding tespiti ve ön doğrulama
  /// işlemlerini yönetir.
  /// </summary>
  IFileService = interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']

    /// <summary>Dosyanın var olup olmadığını ve okunabilir olduğunu doğrular.</summary>
    function ValidateFile(const AFilePath: string): Boolean;

    /// <summary>Dosyanın encoding'ini otomatik tespit eder.</summary>
    function DetectEncoding(const AFilePath: string): TEncoding;

    /// <summary>Dosyayı tespit edilen encoding ile yükler.</summary>
    function LoadFileContent(const AFilePath: string): string;

    /// <summary>Desteklenen uzantıları döndürür.</summary>
    function GetSupportedExtensions: TArray<string>;

    /// <summary>Dosyanın boyutunu byte cinsinden döndürür.</summary>
    function GetFileSize(const AFilePath: string): Int64;
  end;

  // =========================================================================
  // ITransformService — Koordinat dönüşüm servisi
  // =========================================================================

  /// <summary>
  /// Viewport yönetimi ve koordinat dönüşüm işlemlerini sağlar.
  /// Zoom, Pan ve FitToScreen işlemleri bu servis üzerinden gerçekleşir.
  /// </summary>
  ITransformService = interface
    ['{D4E5F6A7-B8C9-0123-DEF0-234567890123}']

    function GetViewport: TViewport;
    procedure SetViewport(const AViewport: TViewport);

    /// <summary>Belirtilen merkez noktası ve faktör ile zoom yapar.</summary>
    procedure ZoomAt(AScreenX, AScreenY: Single; AFactor: Double);

    /// <summary>Ekran koordinatlarında pan yapar.</summary>
    procedure Pan(ADeltaX, ADeltaY: Single);

    /// <summary>Tüm içeriği ekrana sığdırır.</summary>
    procedure FitToContent(const ABounds: TBoundingBox);

    /// <summary>Viewport'u başlangıç değerlerine sıfırlar.</summary>
    procedure ResetView;

    /// <summary>Ekran boyutunu günceller (form boyutu değiştiğinde).</summary>
    procedure SetScreenSize(AWidth, AHeight: Single);

    property Viewport: TViewport read GetViewport write SetViewport;
  end;

  // =========================================================================
  // IShapeRenderer — Tek tip şekil render arayüzü (Strategy Pattern)
  // =========================================================================

  /// <summary>
  /// Belirli bir TDrawShape türünü Skia canvas'ına çizen strateji arayüzü.
  /// Her şekil türü için ayrı IShapeRenderer implementasyonu oluşturulur.
  /// </summary>
  IShapeRenderer = interface
    ['{E5F6A7B8-C9D0-1234-EF01-345678901234}']

    /// <summary>Bu renderer'ın hangi shape sınıfını işlediğini döndürür.</summary>
    function GetShapeClass: TClass;

    /// <summary>Verilen şekli canvas'a çizer.</summary>
    procedure Render(AShape: TDrawShape; const AViewport: TViewport);
  end;

  // =========================================================================
  // ICanvasRenderer — Genel renderer arayüzü
  // =========================================================================

  /// <summary>
  /// Bir TDxfDocument'i veya TDrawShape listesini canvas'a çizen
  /// üst seviye renderer arayüzü.
  /// </summary>
  ICanvasRenderer = interface
    ['{F6A7B8C9-D0E1-2345-F012-456789012345}']

    /// <summary>Render edilecek şekil listesini ayarlar.</summary>
    procedure SetShapes(AShapes: TDrawShapeList);

    /// <summary>Tüm şekilleri mevcut viewport ile canvas'a çizer.</summary>
    procedure Render(const AViewport: TViewport);

    /// <summary>Katman görünürlük durumunu ayarlar.</summary>
    procedure SetLayerVisibility(const ALayerName: string; AVisible: Boolean);

    /// <summary>Arkaplan rengini ayarlar.</summary>
    procedure SetBackgroundColor(AColor: TAlphaColor);

    /// <summary>Anti-aliasing etkinleştirilsin mi?</summary>
    procedure SetAntiAlias(AEnabled: Boolean);
  end;

  // =========================================================================
  // ISvgExporter — DrawShape listesini SVG'ye dönüştürür
  // =========================================================================

  /// <summary>
  /// Ortak şekil modelini SVG çıktısına çevirir.
  /// DXF ve STEP parser'larından bağımsız çalışır.
  /// </summary>
  ISvgExporter = interface
    ['{2D911D7B-7C12-4B49-9552-20FE960DC4AD}']
    function ExportShapesToSvg(AShapes: TDrawShapeList;
      const ABounds: TBoundingBox): string;
  end;

  // =========================================================================
  // IViewerController — MVC Controller arayüzü
  // =========================================================================

  /// <summary>
  /// View (UI) ile Model (TDxfDocument) arasındaki koordinasyonu sağlar.
  /// UI sadece bu interface üzerinden controller ile konuşur.
  /// </summary>
  IViewerController = interface
    ['{A7B8C9D0-E1F2-3456-0123-567890123456}']

    /// <summary>Dosyayı yükler, parse eder ve render hazırlar.</summary>
    procedure LoadFile(const AFilePath: string);

    /// <summary>İçeriği ekrana sığdırır.</summary>
    procedure FitToScreen;

    /// <summary>Görünümü sıfırlar (scale=1, pan=0,0).</summary>
    procedure ResetView;

    /// <summary>Mouse wheel zoom olayını işler.</summary>
    procedure OnZoom(AScreenX, AScreenY: Single; AWheelDelta: Integer);

    /// <summary>Mouse pan başlangıç noktasını kaydeder.</summary>
    procedure OnPanStart(AScreenX, AScreenY: Single);

    /// <summary>Mouse ile pan hareketini işler.</summary>
    procedure OnPanMove(AScreenX, AScreenY: Single);

    /// <summary>Pan bitiş olayını işler.</summary>
    procedure OnPanEnd;

    /// <summary>Klavye yön tuşu ile kaydırma.</summary>
    procedure OnKeyMove(ADeltaX, ADeltaY: Single);

    /// <summary>Ekran boyutu değiştiğinde çağrılır.</summary>
    procedure OnResize(AWidth, AHeight: Single);

    /// <summary>Mevcut zoom seviyesini döndürür (yüzde, 100 = 1:1).</summary>
    function GetZoomPercent: Integer;

    /// <summary>Yüklü belge başlığı (dosya adı).</summary>
    function GetDocumentTitle: string;

    /// <summary>Bir sonraki OnDraw çağrısında render istek bayrağı.</summary>
    function NeedsRedraw: Boolean;

    /// <summary>Redraw bayrağını temizler.</summary>
    procedure ClearRedrawFlag;

    /// <summary>Katman listesini döndürür.</summary>
    function GetLayerNames: TArray<string>;

    /// <summary>Katman görünürlüğünü değiştirir.</summary>
    procedure SetLayerVisible(const AName: string; AVisible: Boolean);
  end;

  // =========================================================================
  // IDocumentObserver — Observer: belge değişiklik bildirimleri
  // =========================================================================

  /// <summary>
  /// Belge yükleme ve güncelleme olaylarını dinleyen gözlemci arayüzü.
  /// View bu arayüzü implement ederek Controller'dan bildirim alır.
  /// </summary>
  IDocumentObserver = interface
    ['{B8C9D0E1-F2A3-4567-1234-678901234567}']

    /// <summary>Yeni belge başarıyla yüklendi.</summary>
    procedure OnDocumentLoaded(const ATitle: string);

    /// <summary>Yükleme hatası oluştu.</summary>
    procedure OnDocumentError(const AMessage: string);

    /// <summary>Render güncellemesi gerekiyor (invalidate).</summary>
    procedure OnRenderRequested;

    /// <summary>Durum çubuğu metni güncellendi.</summary>
    procedure OnStatusChanged(const AMessage: string);
  end;

  // =========================================================================
  // Hata Sınıfları
  // =========================================================================

  /// <summary>
  /// CADViewer temel hata sınıfı.
  /// </summary>
  ECadViewerError = class(Exception);

  /// <summary>
  /// Geçersiz veya bozuk DXF dosyası.
  /// </summary>
  EDxfParseError = class(ECadViewerError)
  private
    FLineNumber: Integer;
  public
    constructor Create(const AMsg: string; ALine: Integer = 0);
    property LineNumber: Integer read FLineNumber;
  end;

  /// <summary>
  /// Dosya okuma/yükleme hatası.
  /// </summary>
  EFileServiceError = class(ECadViewerError);

  /// <summary>
  /// Desteklenmeyen CAD formatı.
  /// </summary>
  EUnsupportedFormatError = class(ECadViewerError);

  /// <summary>
  /// Geçersiz veya bozuk STEP dosyası.
  /// </summary>
  EStepParseError = class(ECadViewerError);

implementation

{ EDxfParseError }

constructor EDxfParseError.Create(const AMsg: string; ALine: Integer);
begin
  if ALine > 0 then
    inherited CreateFmt('%s (Satır: %d)', [AMsg, ALine])
  else
    inherited Create(AMsg);
  FLineNumber := ALine;
end;

end.
