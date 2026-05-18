/// <summary>
/// CADViewer.Utils
/// Yardımcı araçlar: ACI renk tablosu, açı/koordinat dönüşümleri,
/// DXF string temizleme ve genel matematik fonksiyonları.
/// </summary>
unit CADViewer.Utils;

{$SCOPEDENUMS ON}

interface

uses
  System.UITypes,
  System.SysUtils,
  System.Math,
  CADViewer.Core.Types;

type

  // =========================================================================
  // TAciColorTable — AutoCAD Color Index → TAlphaColor dönüşümü
  // =========================================================================

  /// <summary>
  /// AutoCAD Color Index (ACI) 0–255 değerlerini TAlphaColor'a dönüştürür.
  /// DXF standart 256 renk paletini içerir.
  /// </summary>
  TAciColorTable = class
  private
    class var FAciTable: array[0..255] of TAlphaColor;
    class var FInitialized: Boolean;
    class procedure Initialize; static;
  public
    /// <summary>ACI indeksinden TAlphaColor döndürür.</summary>
    class function GetColor(AAciIndex: Integer): TAlphaColor; static;

    /// <summary>TDxfColor'u çözümlenmiş TAlphaColor'a çevirir.
    /// IsByLayer ise layer rengini, IsByBlock ise beyazı döndürür.</summary>
    class function ResolveColor(const AColor: TDxfColor;
      ALayerColor: TAlphaColor): TAlphaColor; static;
  end;

  // =========================================================================
  // TDxfMathUtils — Geometri yardımcıları
  // =========================================================================

  /// <summary>
  /// DXF geometri hesaplamalarında kullanılan matematik araçları.
  /// </summary>
  TDxfMathUtils = class
  public
    /// <summary>Bulge değerinden yay merkezi, yarıçap ve açıları hesaplar.
    /// Bulge = tan(θ/4), θ = yayın açısal genişliği (CCW pozitif).
    /// </summary>
    class procedure BulgeToArc(
      const P1, P2: TPoint2D; ABulge: Double;
      out ACenter: TPoint2D; out ARadius: Double;
      out AStartAngleDeg, AEndAngleDeg: Double); static;

    /// <summary>Açıyı 0–360 aralığına normalize eder.</summary>
    class function NormalizeAngle360(ADeg: Double): Double; static; inline;

    /// <summary>İki açı arasındaki CCW tarama açısını hesaplar.</summary>
    class function ArcSweepCCW(AStartDeg, AEndDeg: Double): Double; static;

    /// <summary>DXF metin kodlamasını (%%d, %%c, %%p vb.) çözer.</summary>
    class function DecodeDxfText(const AText: string): string; static;

    /// <summary>MTEXT format kodlarını temizleyerek düz metin döndürür.</summary>
    class function CleanMText(const AText: string): string; static;

    /// <summary>Noktayı verilen merkez etrafında döndürür (derece).</summary>
    class function RotatePoint(const P, ACenter: TPoint2D;
      AAngleDeg: Double): TPoint2D; static;

    /// <summary>DXF birim kodu (INSUNITS) değerini milimetreye dönüştürür.
    /// Sonucu 1.0 = 1mm, 25.4 = 1 inç vb. şeklindedir.</summary>
    class function InsUnitsToMmFactor(AInsUnits: Integer): Double; static;

    /// <summary>Spline kontrol noktalarından yaklaşık çizgi noktaları üretir
    /// (de Boor algoritması, BSpline).</summary>
    class function ApproximateSpline(
      const AControlPoints: TArray<TPoint2D>;
      const AKnots: TArray<Double>;
      ADegree: Integer;
      ASampleCount: Integer = 100): TArray<TPoint2D>; static;
  end;

  // =========================================================================
  // TDxfStringUtils — String yardımcıları
  // =========================================================================

  /// <summary>
  /// DXF dosya okuma ve metin işlemleri için string araçları.
  /// </summary>
  TDxfStringUtils = class
  public
    /// <summary>String'i güvenli şekilde Double'a çevirir.
    /// Geçersiz değerde ADefault döner.</summary>
    class function TryParseDouble(const AStr: string;
      ADefault: Double = 0.0): Double; static; inline;

    /// <summary>String'i güvenli şekilde Integer'a çevirir.</summary>
    class function TryParseInt(const AStr: string;
      ADefault: Integer = 0): Integer; static; inline;

    /// <summary>Baştaki/sondaki boşlukları ve null karakterleri temizler.</summary>
    class function CleanDxfString(const AStr: string): string; static;

    /// <summary>Encoding tespiti için dosyanın ilk baytlarını (BOM) kontrol eder.</summary>
    class function DetectBomEncoding(const ABytes: TBytes): TEncoding; static;
  end;

implementation

uses
  System.Character;

// =========================================================================
// TAciColorTable
// =========================================================================

// AutoCAD standart ACI renk paleti (256 renk).
// Kaynak: AutoCAD DXF Reference, Appendix A - Color Indices.
class procedure TAciColorTable.Initialize;
begin
  if FInitialized then Exit;

  // İndeks 0: ByBlock → beyaz
  FAciTable[0]   := TAlphaColors.White;
  // İndeks 1-9: temel renkler
  FAciTable[1]   := $FFFF0000; // Kırmızı
  FAciTable[2]   := $FFFFFF00; // Sarı
  FAciTable[3]   := $FF00FF00; // Yeşil
  FAciTable[4]   := $FF00FFFF; // Camgöbeği
  FAciTable[5]   := $FF0000FF; // Mavi
  FAciTable[6]   := $FFFF00FF; // Eflatun
  FAciTable[7]   := $FFFFFFFF; // Beyaz
  FAciTable[8]   := $FF808080; // Koyu gri
  FAciTable[9]   := $FFC0C0C0; // Açık gri
  // 10-19: kırmızı ton ailesi
  FAciTable[10]  := $FFFF0000;
  FAciTable[11]  := $FFFF7F7F;
  FAciTable[12]  := $FFCC0000;
  FAciTable[13]  := $FFCC6666;
  FAciTable[14]  := $FF990000;
  FAciTable[15]  := $FF994C4C;
  FAciTable[16]  := $FF7F0000;
  FAciTable[17]  := $FF7F4040;
  FAciTable[18]  := $FF4C0000;
  FAciTable[19]  := $FF4C2626;
  // 20-29: turuncu ton ailesi
  FAciTable[20]  := $FFFF4000;
  FAciTable[21]  := $FFFF9F7F;
  FAciTable[22]  := $FFCC3300;
  FAciTable[23]  := $FFCC7F66;
  FAciTable[24]  := $FF992600;
  FAciTable[25]  := $FF995F4C;
  FAciTable[26]  := $FF7F1F00;
  FAciTable[27]  := $FF7F4F3F;
  FAciTable[28]  := $FF4C1300;
  FAciTable[29]  := $FF4C2F26;
  // 30-39: sarı-turuncu ton ailesi
  FAciTable[30]  := $FFFF7F00;
  FAciTable[31]  := $FFFFBF7F;
  FAciTable[32]  := $FFCC6600;
  FAciTable[33]  := $FFCC9966;
  FAciTable[34]  := $FF994C00;
  FAciTable[35]  := $FF99724C;
  FAciTable[36]  := $FF7F3F00;
  FAciTable[37]  := $FF7F5F3F;
  FAciTable[38]  := $FF4C2600;
  FAciTable[39]  := $FF4C3926;
  // 40-49: sarı ton ailesi
  FAciTable[40]  := $FFFF9F00;
  FAciTable[41]  := $FFFFCF7F;
  FAciTable[42]  := $FFCC7F00;
  FAciTable[43]  := $FFCCA666;
  FAciTable[44]  := $FF995F00;
  FAciTable[45]  := $FF997A4C;
  FAciTable[46]  := $FF7F4F00;
  FAciTable[47]  := $FF7F663F;
  FAciTable[48]  := $FF4C2F00;
  FAciTable[49]  := $FF4C3D26;
  // 50-59: sarı ton
  FAciTable[50]  := $FFFFBF00;
  FAciTable[51]  := $FFFFDF7F;
  FAciTable[52]  := $FFCC9900;
  FAciTable[53]  := $FFCCB266;
  FAciTable[54]  := $FF997200;
  FAciTable[55]  := $FF99854C;
  FAciTable[56]  := $FF7F5F00;
  FAciTable[57]  := $FF7F6E3F;
  FAciTable[58]  := $FF4C3900;
  FAciTable[59]  := $FF4C4226;
  // 60-69: sarı ton
  FAciTable[60]  := $FFFFDF00;
  FAciTable[61]  := $FFFFEF7F;
  FAciTable[62]  := $FFCCB200;
  FAciTable[63]  := $FFCCBF66;
  FAciTable[64]  := $FF998600;
  FAciTable[65]  := $FF998F4C;
  FAciTable[66]  := $FF7F6F00;
  FAciTable[67]  := $FF7F773F;
  FAciTable[68]  := $FF4C4200;
  FAciTable[69]  := $FF4C4826;
  // 70-79: sarı-yeşil
  FAciTable[70]  := $FFFFFF00;
  FAciTable[71]  := $FFFF7F;
  FAciTable[72]  := $FFCC00;
  FAciTable[73]  := $FFCCCC66;
  FAciTable[74]  := $FF999900;
  FAciTable[75]  := $FF99994C;
  FAciTable[76]  := $FF7F7F00;
  FAciTable[77]  := $FF7F7F3F;
  FAciTable[78]  := $FF4C4C00;
  FAciTable[79]  := $FF4C4C26;
  // 80-89: sarı-yeşil
  FAciTable[80]  := $FFDFFF00;
  FAciTable[81]  := $FFEFFF7F;
  FAciTable[82]  := $FFB2CC00;
  FAciTable[83]  := $FFBFCC66;
  FAciTable[84]  := $FF869900;
  FAciTable[85]  := $FF8F994C;
  FAciTable[86]  := $FF6F7F00;
  FAciTable[87]  := $FF777F3F;
  FAciTable[88]  := $FF424C00;
  FAciTable[89]  := $FF484C26;
  // 90-99: sarı-yeşil
  FAciTable[90]  := $FFBFFF00;
  FAciTable[91]  := $FFDFFF7F;
  FAciTable[92]  := $FF99CC00;
  FAciTable[93]  := $FFB2CC66;
  FAciTable[94]  := $FF729900;
  FAciTable[95]  := $FF85994C;
  FAciTable[96]  := $FF5F7F00;
  FAciTable[97]  := $FF6E7F3F;
  FAciTable[98]  := $FF394C00;
  FAciTable[99]  := $FF424C26;
  // 100-109: yeşil ton ailesi
  FAciTable[100] := $FF9FFF00;
  FAciTable[101] := $FFCFFF7F;
  FAciTable[102] := $FF7FCC00;
  FAciTable[103] := $FFA6CC66;
  FAciTable[104] := $FF5F9900;
  FAciTable[105] := $FF7A994C;
  FAciTable[106] := $FF4F7F00;
  FAciTable[107] := $FF667F3F;
  FAciTable[108] := $FF2F4C00;
  FAciTable[109] := $FF3D4C26;
  // 110-119
  FAciTable[110] := $FF7FFF00;
  FAciTable[111] := $FFBFFF7F;
  FAciTable[112] := $FF66CC00;
  FAciTable[113] := $FF99CC66;
  FAciTable[114] := $FF4C9900;
  FAciTable[115] := $FF72994C;
  FAciTable[116] := $FF3F7F00;
  FAciTable[117] := $FF5E7F3F;
  FAciTable[118] := $FF264C00;
  FAciTable[119] := $FF394C26;
  // 120-129
  FAciTable[120] := $FF5FFF00;
  FAciTable[121] := $FFAFFF7F;
  FAciTable[122] := $FF4CCC00;
  FAciTable[123] := $FF8FCC66;
  FAciTable[124] := $FF399900;
  FAciTable[125] := $FF6A994C;
  FAciTable[126] := $FF2F7F00;
  FAciTable[127] := $FF577F3F;
  FAciTable[128] := $FF1C4C00;
  FAciTable[129] := $FF344C26;
  // 130-139: yeşil
  FAciTable[130] := $FF3FFF00;
  FAciTable[131] := $FF9FFF7F;
  FAciTable[132] := $FF33CC00;
  FAciTable[133] := $FF80CC66;
  FAciTable[134] := $FF269900;
  FAciTable[135] := $FF60994C;
  FAciTable[136] := $FF1F7F00;
  FAciTable[137] := $FF4F7F3F;
  FAciTable[138] := $FF134C00;
  FAciTable[139] := $FF2F4C26;
  // 140-149
  FAciTable[140] := $FF1FFF00;
  FAciTable[141] := $FF8FFF7F;
  FAciTable[142] := $FF19CC00;
  FAciTable[143] := $FF73CC66;
  FAciTable[144] := $FF139900;
  FAciTable[145] := $FF57994C;
  FAciTable[146] := $FF0F7F00;
  FAciTable[147] := $FF487F3F;
  FAciTable[148] := $FF094C00;
  FAciTable[149] := $FF2B4C26;
  // 150-159: yeşil-camgöbeği
  FAciTable[150] := $FF00FF00;
  FAciTable[151] := $FF7FFF7F;
  FAciTable[152] := $FF00CC00;
  FAciTable[153] := $FF66CC66;
  FAciTable[154] := $FF009900;
  FAciTable[155] := $FF4C994C;
  FAciTable[156] := $FF007F00;
  FAciTable[157] := $FF3F7F3F;
  FAciTable[158] := $FF004C00;
  FAciTable[159] := $FF264C26;
  // 160-169
  FAciTable[160] := $FF00FF1F;
  FAciTable[161] := $FF7FFF8F;
  FAciTable[162] := $FF00CC19;
  FAciTable[163] := $FF66CC73;
  FAciTable[164] := $FF009913;
  FAciTable[165] := $FF4C9957;
  FAciTable[166] := $FF007F0F;
  FAciTable[167] := $FF3F7F48;
  FAciTable[168] := $FF004C09;
  FAciTable[169] := $FF264C2B;
  // 170-179
  FAciTable[170] := $FF00FF3F;
  FAciTable[171] := $FF7FFF9F;
  FAciTable[172] := $FF00CC33;
  FAciTable[173] := $FF66CC80;
  FAciTable[174] := $FF009926;
  FAciTable[175] := $FF4C9960;
  FAciTable[176] := $FF007F1F;
  FAciTable[177] := $FF3F7F4F;
  FAciTable[178] := $FF004C13;
  FAciTable[179] := $FF264C2F;
  // 180-189
  FAciTable[180] := $FF00FF5F;
  FAciTable[181] := $FF7FFFAF;
  FAciTable[182] := $FF00CC4C;
  FAciTable[183] := $FF66CC8C;
  FAciTable[184] := $FF009939;
  FAciTable[185] := $FF4C9969;
  FAciTable[186] := $FF007F2F;
  FAciTable[187] := $FF3F7F57;
  FAciTable[188] := $FF004C1C;
  FAciTable[189] := $FF264C34;
  // 190-199: camgöbeği
  FAciTable[190] := $FF00FF7F;
  FAciTable[191] := $FF7FFFBF;
  FAciTable[192] := $FF00CC66;
  FAciTable[193] := $FF66CC99;
  FAciTable[194] := $FF00994C;
  FAciTable[195] := $FF4C9972;
  FAciTable[196] := $FF007F3F;
  FAciTable[197] := $FF3F7F5F;
  FAciTable[198] := $FF004C26;
  FAciTable[199] := $FF264C39;
  // 200-209: camgöbeği
  FAciTable[200] := $FF00FF9F;
  FAciTable[201] := $FF7FFFCF;
  FAciTable[202] := $FF00CC7F;
  FAciTable[203] := $FF66CCA6;
  FAciTable[204] := $FF00995F;
  FAciTable[205] := $FF4C997A;
  FAciTable[206] := $FF007F4F;
  FAciTable[207] := $FF3F7F66;
  FAciTable[208] := $FF004C2F;
  FAciTable[209] := $FF264C3D;
  // 210-219
  FAciTable[210] := $FF00FFBF;
  FAciTable[211] := $FF7FFFDF;
  FAciTable[212] := $FF00CC99;
  FAciTable[213] := $FF66CCB2;
  FAciTable[214] := $FF009972;
  FAciTable[215] := $FF4C9985;
  FAciTable[216] := $FF007F5F;
  FAciTable[217] := $FF3F7F6E;
  FAciTable[218] := $FF004C39;
  FAciTable[219] := $FF264C42;
  // 220-229: açık mavi
  FAciTable[220] := $FF00FFDF;
  FAciTable[221] := $FF7FFFEF;
  FAciTable[222] := $FF00CCB2;
  FAciTable[223] := $FF66CCBF;
  FAciTable[224] := $FF009986;
  FAciTable[225] := $FF4C998F;
  FAciTable[226] := $FF007F6F;
  FAciTable[227] := $FF3F7F77;
  FAciTable[228] := $FF004C42;
  FAciTable[229] := $FF264C48;
  // 230-239: camgöbeği-mavi
  FAciTable[230] := $FF00FFFF;
  FAciTable[231] := $FF7FFFFF;
  FAciTable[232] := $FF00CCCC;
  FAciTable[233] := $FF66CCCC;
  FAciTable[234] := $FF009999;
  FAciTable[235] := $FF4C9999;
  FAciTable[236] := $FF007F7F;
  FAciTable[237] := $FF3F7F7F;
  FAciTable[238] := $FF004C4C;
  FAciTable[239] := $FF264C4C;
  // 240-249: mavi
  FAciTable[240] := $FF0000FF;
  FAciTable[241] := $FF7F7FFF;
  FAciTable[242] := $FF0000CC;
  FAciTable[243] := $FF6666CC;
  FAciTable[244] := $FF000099;
  FAciTable[245] := $FF4C4C99;
  FAciTable[246] := $FF00007F;
  FAciTable[247] := $FF3F3F7F;
  FAciTable[248] := $FF00004C;
  FAciTable[249] := $FF26264C;
  // 250-255: gri tonları
  FAciTable[250] := $FF333333;
  FAciTable[251] := $FF555555;
  FAciTable[252] := $FF777777;
  FAciTable[253] := $FF999999;
  FAciTable[254] := $FFBBBBBB;
  FAciTable[255] := $FFFFFFFF;

  FInitialized := True;
end;

class function TAciColorTable.GetColor(AAciIndex: Integer): TAlphaColor;
begin
  if not FInitialized then Initialize;
  if (AAciIndex < 0) or (AAciIndex > 255) then
    Result := TAlphaColors.White
  else
    Result := FAciTable[AAciIndex];
end;

class function TAciColorTable.ResolveColor(const AColor: TDxfColor;
  ALayerColor: TAlphaColor): TAlphaColor;
begin
  if AColor.IsByLayer then
    Result := ALayerColor
  else if AColor.IsByBlock then
    Result := TAlphaColors.White  // Block rengi = beyaz (container tarafından ezilir)
  else if AColor.IsRgb then
    Result := AColor.RgbValue
  else
    Result := GetColor(AColor.AciIndex);
end;

// =========================================================================
// TDxfMathUtils
// =========================================================================

class procedure TDxfMathUtils.BulgeToArc(
  const P1, P2: TPoint2D; ABulge: Double;
  out ACenter: TPoint2D; out ARadius: Double;
  out AStartAngleDeg, AEndAngleDeg: Double);
var
  D, S: Double;
  Alpha, Mid: TPoint2D;
  Angle: Double;
begin
  // Bulge = tan(θ/4), θ = açısal genişlik
  // D = P1→P2 mesafesi, S = chord half-length
  D := P1.DistanceTo(P2);
  S := D / 2.0;

  // Yay yarıçapı: R = S / sin(θ/2) = S * (1 + bulge²) / (2 * |bulge|)
  ARadius := S * (Sqr(ABulge) + 1.0) / (2.0 * Abs(ABulge));

  // Merkez: orta noktadan dik yönde kaydır
  Mid.X := (P1.X + P2.X) / 2.0;
  Mid.Y := (P1.Y + P2.Y) / 2.0;

  // P1→P2 vektörüne dik yön
  Alpha.X := -(P2.Y - P1.Y);
  Alpha.Y :=  (P2.X - P1.X);

  // Normalize et
  if D > 1e-12 then
  begin
    Alpha.X := Alpha.X / D;
    Alpha.Y := Alpha.Y / D;
  end;

  // Merkeze olan uzaklık
  Angle := Sqrt(Max(0.0, Sqr(ARadius) - Sqr(S)));

  // Bulge negatif ise merkez tersi yönde
  if ABulge < 0 then
    Angle := -Angle;

  ACenter.X := Mid.X + Alpha.X * Angle;
  ACenter.Y := Mid.Y + Alpha.Y * Angle;

  AStartAngleDeg := NormalizeAngle360(
    RadToDeg(ArcTan2(P1.Y - ACenter.Y, P1.X - ACenter.X)));
  AEndAngleDeg := NormalizeAngle360(
    RadToDeg(ArcTan2(P2.Y - ACenter.Y, P2.X - ACenter.X)));

  // Negatif bulge = saat yönü; DXF gösterimi için uçları değiştir
  if ABulge < 0 then
  begin
    Angle := AStartAngleDeg;
    AStartAngleDeg := AEndAngleDeg;
    AEndAngleDeg := Angle;
  end;
end;

class function TDxfMathUtils.NormalizeAngle360(ADeg: Double): Double;
begin
  Result := ADeg - Floor(ADeg / 360.0) * 360.0;
end;

class function TDxfMathUtils.ArcSweepCCW(AStartDeg, AEndDeg: Double): Double;
begin
  AStartDeg := NormalizeAngle360(AStartDeg);
  AEndDeg   := NormalizeAngle360(AEndDeg);
  if AEndDeg <= AStartDeg then
    Result := AEndDeg - AStartDeg + 360.0
  else
    Result := AEndDeg - AStartDeg;
end;

class function TDxfMathUtils.DecodeDxfText(const AText: string): string;
var
  I: Integer;
  Buf: string;
begin
  Buf := AText;
  // %%d → °, %%c → ⌀ (çap), %%p → ± (artı-eksi), %%%% → %
  Buf := StringReplace(Buf, '%%d', '°',  [rfReplaceAll, rfIgnoreCase]);
  Buf := StringReplace(Buf, '%%D', '°',  [rfReplaceAll]);
  Buf := StringReplace(Buf, '%%c', '⌀',  [rfReplaceAll, rfIgnoreCase]);
  Buf := StringReplace(Buf, '%%C', '⌀',  [rfReplaceAll]);
  Buf := StringReplace(Buf, '%%p', '±',  [rfReplaceAll, rfIgnoreCase]);
  Buf := StringReplace(Buf, '%%P', '±',  [rfReplaceAll]);
  Buf := StringReplace(Buf, '%%%%', '%', [rfReplaceAll]);
  // %%nnn → ASCII(nnn)
  I := 1;
  Buf := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (I + 2 <= Length(AText)) and (AText[I] = '%') and (AText[I+1] = '%') then
    begin
      var Code := Copy(AText, I + 2, 3);
      var N: Integer;
      if (Length(Code) = 3) and TryStrToInt(Code, N) and (N >= 1) and (N <= 127) then
      begin
        Buf := Buf + Chr(N);
        Inc(I, 5);
        Continue;
      end;
    end;
    Buf := Buf + AText[I];
    Inc(I);
  end;
  Result := Buf;
  // Tekrar standart kodları uygula (yukarıdaki döngü sonrası)
  Result := StringReplace(Result, '%%d', '°',  [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%%c', '⌀',  [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%%p', '±',  [rfReplaceAll, rfIgnoreCase]);
end;

class function TDxfMathUtils.CleanMText(const AText: string): string;
var
  Buf: TStringBuilder;
  I: Integer;
  Ch: Char;
  InBrace: Boolean;
begin
  // MTEXT format kodlarını kaldır: \P=paragraf, \n=yeni satır,
  // {}, \f{font}, \H{height}, \W{width}, \C{color} vb.
  Buf := TStringBuilder.Create;
  try
    I := 1;
    InBrace := False;
    while I <= Length(AText) do
    begin
      Ch := AText[I];
      if Ch = '{' then
      begin
        Inc(I);
        Continue;
      end
      else if Ch = '}' then
      begin
        Inc(I);
        Continue;
      end
      else if Ch = '\' then
      begin
        Inc(I);
        if I > Length(AText) then Break;
        Ch := AText[I];
        case Ch of
          'P', 'p': Buf.Append(sLineBreak);
          'n', 'N': Buf.Append(sLineBreak);
          '~': Buf.Append(' ');  // Non-breaking space
          '\': Buf.Append('\');
          ';': ; // end of format code
          else
          begin
            // Format kodu: harften sonra '{' başlayana ya da ';'e kadar atla
            while (I <= Length(AText)) and (AText[I] <> ';') and (AText[I] <> ' ') do
              Inc(I);
          end;
        end;
        Inc(I);
        Continue;
      end
      else
      begin
        Buf.Append(Ch);
      end;
      Inc(I);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

class function TDxfMathUtils.RotatePoint(const P, ACenter: TPoint2D;
  AAngleDeg: Double): TPoint2D;
var
  Rad, CosA, SinA: Double;
  DX, DY: Double;
begin
  Rad := DegToRad(AAngleDeg);
  SinCos(Rad, SinA, CosA);
  DX := P.X - ACenter.X;
  DY := P.Y - ACenter.Y;
  Result.X := ACenter.X + DX * CosA - DY * SinA;
  Result.Y := ACenter.Y + DX * SinA + DY * CosA;
end;

class function TDxfMathUtils.InsUnitsToMmFactor(AInsUnits: Integer): Double;
begin
  // DXF $INSUNITS tablosu
  case AInsUnits of
    0:  Result := 1.0;    // Birimsiz
    1:  Result := 25.4;   // İnç → mm
    2:  Result := 304.8;  // Feet → mm
    3:  Result := 1609344.0; // Mile → mm
    4:  Result := 1.0;    // Milimetre
    5:  Result := 10.0;   // Santimetre
    6:  Result := 1000.0; // Metre
    7:  Result := 1000000.0; // Kilometre
    8:  Result := 0.0254; // Microinch
    9:  Result := 0.001;  // Mil (1/1000 inç aslında 0.0254)
    10: Result := 914.4;  // Yard
    11: Result := 1e-7;   // Angstrom
    12: Result := 1e-6;   // Nanometre
    13: Result := 1e-3;   // Mikrometre
    14: Result := 1e6;    // Desimetre
    else Result := 1.0;
  end;
end;

class function TDxfMathUtils.ApproximateSpline(
  const AControlPoints: TArray<TPoint2D>;
  const AKnots: TArray<Double>;
  ADegree: Integer;
  ASampleCount: Integer): TArray<TPoint2D>;
var
  I, J, K: Integer;
  T, TMin, TMax, Step: Double;
  N: Integer;
  BasisValues: TArray<Double>;

  // De Boor algoritması için B-spline baz fonksiyonu
  function BasisFunc(K, D: Integer; TVal: Double): Double;
  var
    Left, Right: Double;
    Denom1, Denom2: Double;
  begin
    if D = 0 then
    begin
      if (K < Length(AKnots) - 1) and
         (TVal >= AKnots[K]) and (TVal < AKnots[K+1]) then
        Result := 1.0
      else
        Result := 0.0;
      Exit;
    end;

    Denom1 := AKnots[K + D] - AKnots[K];
    if Abs(Denom1) > 1e-12 then
      Left := (TVal - AKnots[K]) / Denom1 * BasisFunc(K, D-1, TVal)
    else
      Left := 0.0;

    if (K + D + 1) < Length(AKnots) then
    begin
      Denom2 := AKnots[K + D + 1] - AKnots[K + 1];
      if Abs(Denom2) > 1e-12 then
        Right := (AKnots[K + D + 1] - TVal) / Denom2 * BasisFunc(K+1, D-1, TVal)
      else
        Right := 0.0;
    end
    else
      Right := 0.0;

    Result := Left + Right;
  end;

begin
  N := Length(AControlPoints);
  if (N < 2) or (Length(AKnots) < ADegree + 2) then
  begin
    Result := AControlPoints;
    Exit;
  end;

  SetLength(Result, ASampleCount);

  TMin := AKnots[ADegree];
  TMax := AKnots[N]; // Son kontrol noktasına karşılık gelen knot
  if TMax <= TMin then TMax := TMin + 1.0;

  Step := (TMax - TMin) / (ASampleCount - 1);

  for I := 0 to ASampleCount - 1 do
  begin
    T := TMin + Step * I;
    if I = ASampleCount - 1 then
      T := TMax - 1e-10; // Son nokta için epsilon azalt

    Result[I] := TPoint2D.Zero;
    for J := 0 to N - 1 do
    begin
      var B := BasisFunc(J, ADegree, T);
      Result[I].X := Result[I].X + AControlPoints[J].X * B;
      Result[I].Y := Result[I].Y + AControlPoints[J].Y * B;
    end;
  end;

  // Son nokta: son kontrol noktası
  Result[ASampleCount - 1] := AControlPoints[N - 1];
end;

// =========================================================================
// TDxfStringUtils
// =========================================================================

class function TDxfStringUtils.TryParseDouble(const AStr: string;
  ADefault: Double): Double;
var
  S: string;
begin
  S := Trim(AStr);
  if S = '' then
    Result := ADefault
  else if not TryStrToFloat(S, Result, TFormatSettings.Invariant) then
    Result := ADefault;
end;

class function TDxfStringUtils.TryParseInt(const AStr: string;
  ADefault: Integer): Integer;
var
  S: string;
begin
  S := Trim(AStr);
  if S = '' then
    Result := ADefault
  else if not TryStrToInt(S, Result) then
    Result := ADefault;
end;

class function TDxfStringUtils.CleanDxfString(const AStr: string): string;
begin
  Result := Trim(AStr);
  // Null karakterleri kaldır
  Result := StringReplace(Result, #0, '', [rfReplaceAll]);
end;

class function TDxfStringUtils.DetectBomEncoding(const ABytes: TBytes): TEncoding;
begin
  // UTF-8 BOM: EF BB BF
  if (Length(ABytes) >= 3) and
     (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Exit(TEncoding.UTF8);

  // UTF-16 LE BOM: FF FE
  if (Length(ABytes) >= 2) and
     (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    Exit(TEncoding.Unicode);

  // UTF-16 BE BOM: FE FF
  if (Length(ABytes) >= 2) and
     (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    Exit(TEncoding.BigEndianUnicode);

  Result := nil; // BOM yok
end;

initialization
  TAciColorTable.FInitialized := False;

end.
