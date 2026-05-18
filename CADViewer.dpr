program CADViewer;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMainFrm in 'Views\uMainFrm.pas' {Form6},
  CADViewer.Controllers.DxfViewerController in 'Controllers\CADViewer.Controllers.DxfViewerController.pas',
  CADViewer.Core.Interfaces in 'Core\CADViewer.Core.Interfaces.pas',
  CADViewer.Core.Entities in 'Core\Entities\CADViewer.Core.Entities.pas',
  CADViewer.Core.Models.DrawShapes in 'Core\Models\CADViewer.Core.Models.DrawShapes.pas',
  CADViewer.Core.Models.DxfDocument in 'Core\Models\CADViewer.Core.Models.DxfDocument.pas',
  CADViewer.Parsers.DXF.Parser in 'Parsers\DXF\CADViewer.Parsers.DXF.Parser.pas',
  CADViewer.Parsers.DXF.Reader in 'Parsers\DXF\CADViewer.Parsers.DXF.Reader.pas',
  CADViewer.Services.FileServices in 'Services\FileServices\CADViewer.Services.FileServices.pas',
  CADViewer.Services.Rendering.DxfRenderer in 'Services\Rendering\CADViewer.Services.Rendering.DxfRenderer.pas',
  CADViewer.Services.Transformation in 'Services\Transformation\CADViewer.Services.Transformation.pas',
  CADViewer.Utils in 'Utils\CADViewer.Utils.pas',
  uFrmDxfViewer in 'Views\DxfViewer\uFrmDxfViewer.pas',
  CADViewer.Core.Types in 'Core\CADViewer.Core.Types.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm6, Form6);
  Application.Run;
end.
