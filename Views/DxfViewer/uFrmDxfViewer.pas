/// <summary>
/// uFrmDxfViewer
/// DXF görüntüleyici ana formu. Saf UI katmanı.
/// Tüm işlemler IViewerController üzerinden yapılır.
/// Bu formda: TSkPaintBox, araç çubuğu, durum çubuğu,
/// zoom/pan/klavye olayları ve sürükle-bırak desteği bulunur.
/// </summary>
unit uFrmDxfViewer;

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.IOUtils,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Dialogs,
  FMX.StdCtrls,
  FMX.ListBox,
  FMX.Layouts,
  FMX.Controls.Presentation,
  FMX.Objects,
  FMX.Skia,
  Skia,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces,
  CADViewer.Controllers.DxfViewerController;

type

  /// <summary>
  /// Ana DXF görüntüleyici formu.
  /// MVC'nin View katmanı. Sadece UI ve kullanıcı etkileşimi kodu içerir.
  /// IDocumentObserver: controller'dan gelen bildirimleri alır.
  /// </summary>
  TFrmDxfViewer = class(TForm, IDocumentObserver)
    // --- Layout ---
    LayMain: TLayout;
    ToolBar1: TToolBar;
    StatusBar1: TStatusBar;

    // --- Araç çubuğu düğmeleri ---
    BtnOpen: TButton;
    BtnFitToScreen: TButton;
    BtnResetView: TButton;
    BtnZoomIn: TButton;
    BtnZoomOut: TButton;
    BtnLayerPanel: TButton;

    // --- Durum çubuğu ---
    LblStatus: TLabel;
    LblZoom: TLabel;

    // --- Canvas ---
    SkPaintBox: TSkPaintBox;

    // --- Katman paneli ---
    PanelLayers: TPanel;
    LayerListBox: TListBox;
    LblLayers: TLabel;
    BtnCloseLayerPanel: TButton;

    // --- Open dialog ---
    OpenDialog1: TOpenDialog;

    // --- Olaylar ---
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState);
    procedure FormResize(Sender: TObject);

    procedure BtnOpenClick(Sender: TObject);
    procedure BtnFitToScreenClick(Sender: TObject);
    procedure BtnResetViewClick(Sender: TObject);
    procedure BtnZoomInClick(Sender: TObject);
    procedure BtnZoomOutClick(Sender: TObject);
    procedure BtnLayerPanelClick(Sender: TObject);
    procedure BtnCloseLayerPanelClick(Sender: TObject);
    procedure LayerListBoxChange(Sender: TObject);

    procedure SkPaintBoxDraw(ASender: TObject; const ACanvas: ISkCanvas;
      const ADest: TRectF; const AOpacity: Single);
    procedure SkPaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure SkPaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure SkPaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Single);
    procedure SkPaintBoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure SkPaintBoxDblClick(Sender: TObject);

  private
    FController: TDxfViewerController;
    FDragging: Boolean;

    // IDocumentObserver implementasyonu
    procedure OnDocumentLoaded(const ATitle: string);
    procedure OnDocumentError(const AMessage: string);
    procedure OnRenderRequested;
    procedure OnStatusChanged(const AMessage: string);

    procedure UpdateZoomLabel;
    procedure UpdateLayerPanel;
    procedure InvalidateCanvas;

    // Sürükle-bırak desteği
    procedure DoDropFile(const AFilePath: string);

  public
    /// <summary>
    /// Dışarıdan varolan bir controller ile formu başlatır.
    /// Opsiyonel: FormCreate'de varsayılan controller oluşturulur.
    /// </summary>
    procedure InitWithController(AController: TDxfViewerController);
  end;

var
  FrmDxfViewer: TFrmDxfViewer;

implementation

{$R *.fmx}

uses
  CADViewer.Services.Rendering.DxfRenderer;

{ TFrmDxfViewer }

procedure TFrmDxfViewer.FormCreate(Sender: TObject);
begin
  // Controller oluştur (dependency injection)
  FController := TDxfViewerControllerFactory.Create;
  FController.AddObserver(Self);

  // Ekran boyutunu controller'a bildir
  FController.OnResize(SkPaintBox.Width, SkPaintBox.Height);

  FDragging := False;

  // Arkaplan rengi
  SkPaintBox.HitTest := True;

  // Durum
  LblStatus.Text := 'CAD dosyası açmak için "Aç" düğmesine tıklayın (DXF, DWG, STEP, IGES).';
  LblZoom.Text := 'Zoom: %100';

  // Katman panelini gizle
  PanelLayers.Visible := False;

  // OpenDialog filtresi
  OpenDialog1.Filter :=
    'Desteklenen CAD Dosyaları (*.dxf;*.dwg;*.step;*.stp;*.iges;*.igs;*.IGES;*.IGS)|' +
    '*.dxf;*.dwg;*.step;*.stp;*.iges;*.igs;*.IGES;*.IGS|' +
    'DXF Dosyaları (*.dxf)|*.dxf|' +
    'DWG Dosyaları (*.dwg)|*.dwg|' +
    'STEP/IGES Dosyaları (*.step;*.stp;*.iges;*.igs;*.IGES;*.IGS)|*.step;*.stp;*.iges;*.igs;*.IGES;*.IGS|' +
    'Tüm Dosyalar (*.*)|*.*';
  OpenDialog1.Title := 'CAD Dosyası Aç';

  // Klavye alabilmek için
//  Self.KeyPreview := True;
end;

procedure TFrmDxfViewer.FormDestroy(Sender: TObject);
begin
  if FController <> nil then
  begin
    FController.RemoveObserver(Self);
    FController.Free;
    FController := nil;
  end;
end;

procedure TFrmDxfViewer.InitWithController(AController: TDxfViewerController);
begin
  if FController <> nil then
  begin
    FController.RemoveObserver(Self);
    FController.Free;
  end;
  FController := AController;
  FController.AddObserver(Self);
end;

// =========================================================================
// IDocumentObserver implementasyonu
// =========================================================================

procedure TFrmDxfViewer.OnDocumentLoaded(const ATitle: string);
begin
  // Ana thread'de çalışması gerekiyor (TThread.Queue ile gelebilir)
  Caption := 'CAD Viewer — ' + ATitle;
  UpdateLayerPanel;
  UpdateZoomLabel;
  InvalidateCanvas;
end;

procedure TFrmDxfViewer.OnDocumentError(const AMessage: string);
begin
  ShowMessage('Hata: ' + AMessage);
end;

procedure TFrmDxfViewer.OnRenderRequested;
begin
  InvalidateCanvas;
end;

procedure TFrmDxfViewer.OnStatusChanged(const AMessage: string);
begin
  LblStatus.Text := AMessage;
end;

// =========================================================================
// Canvas yönetimi
// =========================================================================

procedure TFrmDxfViewer.InvalidateCanvas;
begin
  SkPaintBox.Redraw;
end;

procedure TFrmDxfViewer.SkPaintBoxDraw(ASender: TObject;
  const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
begin
  if FController = nil then Exit;

  // Canvas'ı renderer'a ilet
  FController.Renderer.SetCanvas(ACanvas);

  // Render
  FController.Renderer.Render(FController.TransformService.Viewport);

  FController.ClearRedrawFlag;
end;

// =========================================================================
// Mouse olayları
// =========================================================================

procedure TFrmDxfViewer.SkPaintBoxMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
var
  LPos: TPointF;
begin
  if FController = nil then Exit;

  // Zoom imleç konumunda yapılır
  LPos := SkPaintBox.AbsoluteToLocal(Screen.MousePos);

  FController.OnZoom(LPos.X, LPos.Y, WheelDelta);
  UpdateZoomLabel;
  Handled := True;
end;

procedure TFrmDxfViewer.SkPaintBoxMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if FController = nil then Exit;

  if Button = TMouseButton.mbLeft then
  begin
    FDragging := True;
    FController.OnPanStart(X, Y);
    // El imleci efekti (FMX'te cursor değişimi)
    SkPaintBox.Cursor := crSizeAll;
  end;
end;

procedure TFrmDxfViewer.SkPaintBoxMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Single);
begin
  if FController = nil then Exit;

  if FDragging and (ssLeft in Shift) then
    FController.OnPanMove(X, Y);
end;

procedure TFrmDxfViewer.SkPaintBoxMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if FController = nil then Exit;

  if Button = TMouseButton.mbLeft then
  begin
    FDragging := False;
    FController.OnPanEnd;
    SkPaintBox.Cursor := crDefault;
  end;
end;

procedure TFrmDxfViewer.SkPaintBoxDblClick(Sender: TObject);
begin
  // Çift tıkla ekrana sığdır
  if FController <> nil then
  begin
    FController.FitToScreen;
    UpdateZoomLabel;
  end;
end;

// =========================================================================
// Klavye olayları
// =========================================================================

procedure TFrmDxfViewer.FormKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
const
  KeyPanAmount = 1.0; // Controller'daki adım sayısı ile çarpılır
begin
  if FController = nil then Exit;

  case Key of
    // Yön tuşları: pan
    vkLeft:  FController.OnKeyMove(-KeyPanAmount, 0);
    vkRight: FController.OnKeyMove( KeyPanAmount, 0);
    vkUp:    FController.OnKeyMove(0,  KeyPanAmount);
    vkDown:  FController.OnKeyMove(0, -KeyPanAmount);

    // + / - : zoom
    vkAdd, Ord('+'): FController.OnZoom(
      SkPaintBox.Width / 2, SkPaintBox.Height / 2, 120);
    vkSubtract, Ord('-'): FController.OnZoom(
      SkPaintBox.Width / 2, SkPaintBox.Height / 2, -120);

    // F: fit to screen
    Ord('F'), Ord('f'): FController.FitToScreen;

    // R: reset
    Ord('R'), Ord('r'): FController.ResetView;

    // Escape
    vkEscape:
    begin
      FDragging := False;
      FController.OnPanEnd;
    end;
  end;

  UpdateZoomLabel;
  Key := 0; // İşlendi
end;

// =========================================================================
// Form boyutu değişimi
// =========================================================================

procedure TFrmDxfViewer.FormResize(Sender: TObject);
begin
  if FController <> nil then
    FController.OnResize(SkPaintBox.Width, SkPaintBox.Height);
end;

// =========================================================================
// Araç çubuğu düğmeleri
// =========================================================================

procedure TFrmDxfViewer.BtnOpenClick(Sender: TObject);
begin
  if OpenDialog1.Execute then
    FController.LoadFile(OpenDialog1.FileName);
end;

procedure TFrmDxfViewer.BtnFitToScreenClick(Sender: TObject);
begin
  if FController <> nil then
  begin
    FController.FitToScreen;
    UpdateZoomLabel;
  end;
end;

procedure TFrmDxfViewer.BtnResetViewClick(Sender: TObject);
begin
  if FController <> nil then
  begin
    FController.ResetView;
    UpdateZoomLabel;
  end;
end;

procedure TFrmDxfViewer.BtnZoomInClick(Sender: TObject);
begin
  if FController <> nil then
  begin
    FController.OnZoom(SkPaintBox.Width / 2, SkPaintBox.Height / 2, 120);
    UpdateZoomLabel;
  end;
end;

procedure TFrmDxfViewer.BtnZoomOutClick(Sender: TObject);
begin
  if FController <> nil then
  begin
    FController.OnZoom(SkPaintBox.Width / 2, SkPaintBox.Height / 2, -120);
    UpdateZoomLabel;
  end;
end;

procedure TFrmDxfViewer.BtnLayerPanelClick(Sender: TObject);
begin
  PanelLayers.Visible := not PanelLayers.Visible;
end;

procedure TFrmDxfViewer.BtnCloseLayerPanelClick(Sender: TObject);
begin
  PanelLayers.Visible := False;
end;

// =========================================================================
// Katman paneli
// =========================================================================

procedure TFrmDxfViewer.UpdateLayerPanel;
var
  LNames: TArray<string>;
  LItem: TListBoxItem;
  I: Integer;
begin
  if FController = nil then Exit;

  LayerListBox.BeginUpdate;
  try
    LayerListBox.Clear;
    LNames := FController.GetLayerNames;
    for I := 0 to High(LNames) do
    begin
      LItem := TListBoxItem.Create(LayerListBox);
      LItem.Text := LNames[I];
      LItem.IsChecked := True; // Varsayılan: görünür
      LayerListBox.AddObject(LItem);
    end;
  finally
    LayerListBox.EndUpdate;
  end;
end;

procedure TFrmDxfViewer.LayerListBoxChange(Sender: TObject);
var
  LItem: TListBoxItem;
begin
  if FController = nil then Exit;

  if LayerListBox.ItemIndex < 0 then
    Exit;

  LItem := LayerListBox.ListItems[LayerListBox.ItemIndex];
  if LItem <> nil then
    FController.SetLayerVisible(LItem.Text, LItem.IsChecked);
end;

// =========================================================================
// Yardımcılar
// =========================================================================

procedure TFrmDxfViewer.UpdateZoomLabel;
begin
  if FController <> nil then
    LblZoom.Text := Format('Zoom: %%%d', [FController.GetZoomPercent]);
end;

procedure TFrmDxfViewer.DoDropFile(const AFilePath: string);
begin
  if FController <> nil then
    FController.LoadFile(AFilePath);
end;

end.
