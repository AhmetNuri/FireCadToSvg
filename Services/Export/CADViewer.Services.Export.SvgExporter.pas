/// <summary>
/// CADViewer.Services.Export.SvgExporter
/// Ortak çizim modelini SVG string çıktısına dönüştürür.
/// STEP2SVG ve DXF2SVG için aynı standardı kullanır.
/// </summary>
unit CADViewer.Services.Export.SvgExporter;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  CADViewer.Core.Types,
  CADViewer.Core.Interfaces,
  CADViewer.Core.Models.DrawShapes;

type
  TSvgExporter = class(TInterfacedObject, ISvgExporter)
  private
    class function FmtNum(const V: Double): string; static;
    class procedure AppendShapeXml(ABuilder: TStringBuilder; AShape: TDrawShape); static;
    class procedure AppendStyle(ABuilder: TStringBuilder; const AStyle: TDrawStyle); static;
    class function ArcSweepCCW(AStartDeg, AEndDeg: Double): Double; static;
  public
    function ExportShapesToSvg(AShapes: TDrawShapeList;
      const ABounds: TBoundingBox): string;
  end;

implementation

uses
  System.UITypes;

class function TSvgExporter.FmtNum(const V: Double): string;
begin
  Result := FloatToStr(V, TFormatSettings.Invariant);
end;

class procedure TSvgExporter.AppendStyle(ABuilder: TStringBuilder;
  const AStyle: TDrawStyle);
begin
  var R := (AStyle.StrokeColor shr 16) and $FF;
  var G := (AStyle.StrokeColor shr 8) and $FF;
  var B := AStyle.StrokeColor and $FF;
  ABuilder.Append(' stroke="rgb(').Append(R).Append(',').Append(G).Append(',').Append(B).Append(')"');
  ABuilder.Append(' stroke-width="').Append(FmtNum(Max(0.1, AStyle.StrokeWidth))).Append('"');
  ABuilder.Append(' fill="none"');
  if AStyle.Opacity < 1.0 then
    ABuilder.Append(' stroke-opacity="').Append(FmtNum(Max(0.0, Min(1.0, AStyle.Opacity)))).Append('"');
end;

class function TSvgExporter.ArcSweepCCW(AStartDeg, AEndDeg: Double): Double;
begin
  Result := AEndDeg - AStartDeg;
  while Result < 0 do
    Result := Result + 360.0;
  while Result >= 360.0 do
    Result := Result - 360.0;
end;

class procedure TSvgExporter.AppendShapeXml(ABuilder: TStringBuilder; AShape: TDrawShape);
var
  I: Integer;
  P: TPoint2D;
  Sweep: Double;
  EndX, EndY: Double;
begin
  if AShape is TDrawLine then
  begin
    var L := TDrawLine(AShape);
    ABuilder.Append('<line x1="').Append(FmtNum(L.StartPoint.X))
      .Append('" y1="').Append(FmtNum(-L.StartPoint.Y))
      .Append('" x2="').Append(FmtNum(L.EndPoint.X))
      .Append('" y2="').Append(FmtNum(-L.EndPoint.Y)).Append('"');
    AppendStyle(ABuilder, L.Style);
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawCircle then
  begin
    var C := TDrawCircle(AShape);
    ABuilder.Append('<circle cx="').Append(FmtNum(C.Center.X))
      .Append('" cy="').Append(FmtNum(-C.Center.Y))
      .Append('" r="').Append(FmtNum(C.Radius)).Append('"');
    AppendStyle(ABuilder, C.Style);
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawArc then
  begin
    var A := TDrawArc(AShape);
    EndX := A.Center.X + A.Radius * Cos(DegToRad(A.EndAngleDeg));
    EndY := A.Center.Y + A.Radius * Sin(DegToRad(A.EndAngleDeg));
    var StartX := A.Center.X + A.Radius * Cos(DegToRad(A.StartAngleDeg));
    var StartY := A.Center.Y + A.Radius * Sin(DegToRad(A.StartAngleDeg));
    Sweep := ArcSweepCCW(A.StartAngleDeg, A.EndAngleDeg);
    var LargeArc := Ord(Sweep > 180.0);

    ABuilder.Append('<path d="M ')
      .Append(FmtNum(StartX)).Append(' ').Append(FmtNum(-StartY))
      .Append(' A ').Append(FmtNum(A.Radius)).Append(' ').Append(FmtNum(A.Radius))
      .Append(' 0 ').Append(LargeArc).Append(' 0 ')
      .Append(FmtNum(EndX)).Append(' ').Append(FmtNum(-EndY)).Append('"');
    AppendStyle(ABuilder, A.Style);
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawPolyline then
  begin
    var PL := TDrawPolyline(AShape);
    if PL.PointCount < 2 then Exit;
    ABuilder.Append('<polyline points="');
    for I := 0 to High(PL.Points) do
    begin
      P := PL.Points[I].Position;
      if I > 0 then ABuilder.Append(' ');
      ABuilder.Append(FmtNum(P.X)).Append(',').Append(FmtNum(-P.Y));
    end;
    ABuilder.Append('"');
    AppendStyle(ABuilder, PL.Style);
    if PL.IsClosed then
      ABuilder.Append(' fill="rgba(0,0,0,0)"');
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawPath then
  begin
    var Path := TDrawPath(AShape);
    if Path.PointCount < 2 then Exit;
    ABuilder.Append('<polyline points="');
    for I := 0 to High(Path.Points) do
    begin
      P := Path.Points[I];
      if I > 0 then ABuilder.Append(' ');
      ABuilder.Append(FmtNum(P.X)).Append(',').Append(FmtNum(-P.Y));
    end;
    ABuilder.Append('"');
    AppendStyle(ABuilder, Path.Style);
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawEllipse then
  begin
    var E := TDrawEllipse(AShape);
    ABuilder.Append('<ellipse cx="').Append(FmtNum(E.Center.X))
      .Append('" cy="').Append(FmtNum(-E.Center.Y))
      .Append('" rx="').Append(FmtNum(E.MajorRadius))
      .Append('" ry="').Append(FmtNum(E.MajorRadius * E.MinorToMajorRatio))
      .Append('" transform="rotate(').Append(FmtNum(-E.RotationAngleDeg)).Append(' ')
      .Append(FmtNum(E.Center.X)).Append(' ').Append(FmtNum(-E.Center.Y)).Append(')"');
    AppendStyle(ABuilder, E.Style);
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawPoint then
  begin
    var Pt := TDrawPoint(AShape);
    ABuilder.Append('<circle cx="').Append(FmtNum(Pt.Position.X))
      .Append('" cy="').Append(FmtNum(-Pt.Position.Y))
      .Append('" r="1"');
    AppendStyle(ABuilder, Pt.Style);
    ABuilder.Append('/>').AppendLine;
  end
  else if AShape is TDrawComposite then
  begin
    var Comp := TDrawComposite(AShape);
    for var Child in Comp.Children do
      AppendShapeXml(ABuilder, Child);
  end;
end;

function TSvgExporter.ExportShapesToSvg(AShapes: TDrawShapeList;
  const ABounds: TBoundingBox): string;
var
  B: TStringBuilder;
  W, H: Double;
begin
  if (AShapes = nil) or ABounds.IsEmpty then
    Exit('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>');

  W := Max(1e-9, ABounds.Width);
  H := Max(1e-9, ABounds.Height);

  B := TStringBuilder.Create(4096);
  try
    B.Append('<?xml version="1.0" encoding="UTF-8"?>').AppendLine;
    B.Append('<svg xmlns="http://www.w3.org/2000/svg" version="1.1" ')
      .Append('viewBox="')
      .Append(FmtNum(ABounds.MinX)).Append(' ')
      .Append(FmtNum(-ABounds.MaxY)).Append(' ')
      .Append(FmtNum(W)).Append(' ')
      .Append(FmtNum(H))
      .Append('">').AppendLine;

    for var Shape in AShapes do
      if Shape.Visible then
        AppendShapeXml(B, Shape);

    B.Append('</svg>');
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

end.
