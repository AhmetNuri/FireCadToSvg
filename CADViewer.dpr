/// <summary>
/// CADViewer.dpr — Delphi FireMonkey Proje Dosyası
/// DXF görüntüleyici ana uygulama girişi.
/// </summary>
program CADViewer;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  // --- Core ---
  CADViewer.Core.Types
    in 'Core\CADViewer.Core.Types.pas',
  CADViewer.Core.Interfaces
    in 'Core\CADViewer.Core.Interfaces.pas',
  CADViewer.Core.Entities
    in 'Core\Entities\CADViewer.Core.Entities.pas',
  CADViewer.Core.Models.DrawShapes
    in 'Core\Models\CADViewer.Core.Models.DrawShapes.pas',
  CADViewer.Core.Models.DxfDocument
    in 'Core\Models\CADViewer.Core.Models.DxfDocument.pas',
  // --- Utils ---
  CADViewer.Utils
    in 'Utils\CADViewer.Utils.pas',
  // --- Parsers ---
  CADViewer.Parsers.DXF.Reader
    in 'Parsers\DXF\CADViewer.Parsers.DXF.Reader.pas',
  CADViewer.Parsers.DXF.Parser
    in 'Parsers\DXF\CADViewer.Parsers.DXF.Parser.pas',
  // --- Services ---
  CADViewer.Services.FileServices
    in 'Services\FileServices\CADViewer.Services.FileServices.pas',
  CADViewer.Services.Transformation
    in 'Services\Transformation\CADViewer.Services.Transformation.pas',
  CADViewer.Services.Rendering.DxfRenderer
    in 'Services\Rendering\CADViewer.Services.Rendering.DxfRenderer.pas',
  // --- Controllers ---
  CADViewer.Controllers.DxfViewerController
    in 'Controllers\CADViewer.Controllers.DxfViewerController.pas',
  // --- Views ---
  uFrmDxfViewer
    in 'Views\DxfViewer\uFrmDxfViewer.pas' {FrmDxfViewer};

{$R *.res}

begin
  // Skia4Delphi başlatma
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TFrmDxfViewer, FrmDxfViewer);
  Application.Run;
end.
