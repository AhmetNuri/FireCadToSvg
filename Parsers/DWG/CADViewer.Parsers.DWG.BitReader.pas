/// <summary>
/// CADViewer.Parsers.DWG.BitReader
/// DWG ikili (binary) dosyası için bit-düzeyli okuyucu.
/// ODA (Open Design Alliance) DWG R2000+ spesifikasyonunda tanımlı
/// tüm bit-kodlu veri tiplerini destekler.
///
/// Okuma sırası: her byte içinde MSB önce (bit 7 → bit 0).
/// Tüm okumalar geçerli bit konumundan ilerler.
///
/// Desteklenen tipler:
///   B (1-bit), BB (2-bit), BBBB (4-bit)
///   RC (raw byte), RS (raw int16 LE), RL (raw int32 LE), RD (raw double LE)
///   BS (bit-coded short), BL (bit-coded long), BD (bit-coded double)
///   BT (bit thickness), BE (bit extrusion)
///   MC (modular char - değişken işaretli), MS (modular short - değişken işaretsiz)
///   TV (text variable - RS uzunluk + char dizisi)
///   H  (nesne tanıtıcısı / handle)
///   P2RD (2D ham double nokta), P3BD (3D bit-double nokta)
/// </summary>
unit CADViewer.Parsers.DWG.BitReader;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  CADViewer.Core.Types;

type

  // =========================================================================
  // EDwgBitReaderError
  // =========================================================================

  /// <summary>
  /// BitReader okuma hatası (beklenmeyen EOF veya geçersiz veri).
  /// </summary>
  EDwgBitReaderError = class(Exception);

  // =========================================================================
  // TDwgBitReader
  // =========================================================================

  /// <summary>
  /// DWG bit-kodlu veri okuyucu.
  /// Bir TBytes tamponu üzerinde çalışır; bit konumunu takip eder.
  /// Her byte içinde bitler MSB (yüksek bit) önce okunur.
  /// </summary>
  TDwgBitReader = class
  private
    FData: TBytes;
    FBitPos: Int64;   // 0-tabanlı global bit konumu
    FDataBits: Int64; // Toplam bit sayısı

    procedure CheckAvail(ACount: Integer); inline;

    /// <summary>Geçerli bit konumundan ACount bit okur, MSB önce.
    /// Sonuç [0 .. 2^ACount - 1] aralığındadır.</summary>
    function ReadBitsN(ACount: Integer): Cardinal;

    /// <summary>8 bit (1 byte) okur; ham byte değerini döndürür.</summary>
    function ReadByte: Byte; inline;

  public
    /// <summary>AData tamponu üzerinde çalışan reader oluşturur.
    /// AByteOffset: okumaya başlanacak byte konumu.</summary>
    constructor Create(const AData: TBytes; AByteOffset: Integer = 0);

    // -----------------------------------------------------------------------
    // Konum yönetimi
    // -----------------------------------------------------------------------

    procedure SeekByte(AByteOffset: Integer);
    procedure SeekBit(ABitOffset: Int64);
    procedure SkipBytes(ACount: Integer); inline;
    procedure SkipBits(ACount: Integer); inline;

    function BytePos: Integer; inline;
    function BitPos: Int64; inline;
    function AtEnd: Boolean; inline;
    function BytesLeft: Integer; inline;
    function DataSize: Integer; inline;

    // -----------------------------------------------------------------------
    // Ham okuma (any-bit-aligned, little-endian for multi-byte)
    // -----------------------------------------------------------------------

    /// <summary>8-bit ham byte okur.</summary>
    function RC: Byte;

    /// <summary>16-bit ham kısa (little-endian) okur.</summary>
    function RS: SmallInt;

    /// <summary>32-bit ham uzun (little-endian) okur.</summary>
    function RL: Integer;

    /// <summary>64-bit ham double (IEEE 754 little-endian) okur.</summary>
    function RD: Double;

    // -----------------------------------------------------------------------
    // Bit okuma
    // -----------------------------------------------------------------------

    function B: Byte;     // 1 bit
    function BB: Byte;    // 2 bit
    function BBBB: Byte;  // 4 bit

    // -----------------------------------------------------------------------
    // Bit-kodlu tipler (DWG spesifikasyonu)
    // -----------------------------------------------------------------------

    /// <summary>
    /// Bit Short (BS). 2-bit kod okur:
    ///   00 → sonraki 16-bit ham int16 LE
    ///   01 → sonraki 8-bit, sıfır-uzatılmış
    ///   10 → 0
    ///   11 → 256
    /// </summary>
    function BS: SmallInt;

    /// <summary>
    /// Bit Long (BL). 2-bit kod:
    ///   00 → sonraki 32-bit ham int32 LE
    ///   01 → sonraki 8-bit, sıfır-uzatılmış
    ///   10 → 0
    ///   11 → 0 (tanımsız, sıfır döndürülür)
    /// </summary>
    function BL: Integer;

    /// <summary>
    /// Bit Double (BD). 2-bit kod:
    ///   00 → sonraki 64-bit ham double LE
    ///   01 → 1.0
    ///   10 → 0.0
    ///   11 → 0.0 (tanımsız, sıfır döndürülür)
    /// </summary>
    function BD: Double;

    /// <summary>
    /// Bit Thickness (BT).
    /// Önceki B=1 ise 0.0, değilse BD okur.
    /// </summary>
    function BT: Double;

    /// <summary>
    /// Modular Char (MC): değişken uzunluklu işaretli tamsayı.
    /// Her byte: bit7=devam, bit6=işaret(sadece ilk), bit0-5=veri.
    /// </summary>
    function MC: Integer;

    /// <summary>
    /// Modular Short (MS): değişken uzunluklu işaretsiz tamsayı.
    /// 1 veya 2 byte; bit7 devam bayrağı.
    /// </summary>
    function MS: Cardinal;

    /// <summary>
    /// Text Variable (TV): RS uzunluk + ham byte dizisi.
    /// Windows-1252 ile string'e dönüştürülür.
    /// </summary>
    function TV: string;

    /// <summary>
    /// Object Handle (H).
    /// 1 meta-byte: (kod[7:4], uzunluk[3:0]); sonra uzunluk kadar byte.
    /// Mutlak veya referans handle değeri döndürülür.
    /// </summary>
    function H: Int64;

    /// <summary>
    /// Bit Extrusion (BE).
    /// B=1 → (0,0,1); B=0 → üç BD okur.
    /// </summary>
    function BE: TPoint3D;

    /// <summary>Ham 2D nokta: RD, RD.</summary>
    function P2RD: TPoint2D;

    /// <summary>2D bit-double nokta: BD, BD.</summary>
    function P2BD: TPoint2D;

    /// <summary>3D bit-double nokta: BD, BD, BD.</summary>
    function P3BD: TPoint3D;

    /// <summary>
    /// Color (CMC). 1 byte okur:
    ///   bit7=0 → ACI index döndürür
    ///   bit7=1 → bit0=TrueColor (3 byte RGB), bit1=renk adı (iki TV)
    /// ACI index veya 256 (ByLayer) döndürür.
    /// </summary>
    function CMC: Integer;
  end;

implementation

{ TDwgBitReader }

constructor TDwgBitReader.Create(const AData: TBytes; AByteOffset: Integer);
begin
  inherited Create;
  FData := AData;
  FBitPos := Int64(AByteOffset) * 8;
  FDataBits := Int64(Length(AData)) * 8;
end;

procedure TDwgBitReader.CheckAvail(ACount: Integer);
begin
  if FBitPos + ACount > FDataBits then
    raise EDwgBitReaderError.CreateFmt(
      'DWG okuma hatası: yeterli veri yok (bit=%d, istek=%d, toplam=%d)',
      [FBitPos, ACount, FDataBits]);
end;

function TDwgBitReader.ReadBitsN(ACount: Integer): Cardinal;
var
  I, ByteIdx, BitIdx: Integer;
begin
  CheckAvail(ACount);
  Result := 0;
  for I := 0 to ACount - 1 do
  begin
    ByteIdx := FBitPos shr 3;
    BitIdx  := FBitPos and 7;                       // 0=MSB .. 7=LSB
    Result  := (Result shl 1) or ((FData[ByteIdx] shr (7 - BitIdx)) and 1);
    Inc(FBitPos);
  end;
end;

function TDwgBitReader.ReadByte: Byte;
begin
  Result := Byte(ReadBitsN(8));
end;

// --- Konum ---

procedure TDwgBitReader.SeekByte(AByteOffset: Integer);
begin
  FBitPos := Int64(AByteOffset) * 8;
end;

procedure TDwgBitReader.SeekBit(ABitOffset: Int64);
begin
  FBitPos := ABitOffset;
end;

procedure TDwgBitReader.SkipBytes(ACount: Integer);
begin
  Inc(FBitPos, Int64(ACount) * 8);
end;

procedure TDwgBitReader.SkipBits(ACount: Integer);
begin
  Inc(FBitPos, ACount);
end;

function TDwgBitReader.BytePos: Integer;
begin
  Result := FBitPos shr 3;
end;

function TDwgBitReader.BitPos: Int64;
begin
  Result := FBitPos;
end;

function TDwgBitReader.AtEnd: Boolean;
begin
  Result := FBitPos >= FDataBits;
end;

function TDwgBitReader.BytesLeft: Integer;
begin
  Result := (FDataBits - FBitPos + 7) shr 3;
end;

function TDwgBitReader.DataSize: Integer;
begin
  Result := Length(FData);
end;

// --- Ham okuma ---

function TDwgBitReader.RC: Byte;
begin
  Result := ReadByte;
end;

function TDwgBitReader.RS: SmallInt;
var
  LLo, LHi: Byte;
begin
  LLo := ReadByte;
  LHi := ReadByte;
  Result := SmallInt(Word(LLo) or (Word(LHi) shl 8));
end;

function TDwgBitReader.RL: Integer;
var
  B0, B1, B2, B3: Byte;
begin
  B0 := ReadByte;
  B1 := ReadByte;
  B2 := ReadByte;
  B3 := ReadByte;
  Result := Integer(Cardinal(B0) or (Cardinal(B1) shl 8)
                 or (Cardinal(B2) shl 16) or (Cardinal(B3) shl 24));
end;

function TDwgBitReader.RD: Double;
var
  Buf: array[0..7] of Byte;
  I: Integer;
begin
  for I := 0 to 7 do
    Buf[I] := ReadByte;
  Move(Buf[0], Result, SizeOf(Double));
end;

// --- Bit okuma ---

function TDwgBitReader.B: Byte;
begin
  Result := Byte(ReadBitsN(1));
end;

function TDwgBitReader.BB: Byte;
begin
  Result := Byte(ReadBitsN(2));
end;

function TDwgBitReader.BBBB: Byte;
begin
  Result := Byte(ReadBitsN(4));
end;

// --- Bit-kodlu tipler ---

function TDwgBitReader.BS: SmallInt;
var
  LCode: Byte;
begin
  LCode := BB;
  case LCode of
    0: Result := RS;
    1: Result := SmallInt(ReadByte);
    2: Result := 0;
    3: Result := 256;
  else
    Result := 0;
  end;
end;

function TDwgBitReader.BL: Integer;
var
  LCode: Byte;
begin
  LCode := BB;
  case LCode of
    0: Result := RL;
    1: Result := Integer(ReadByte);
    2: Result := 0;
  else
    Result := 0;
  end;
end;

function TDwgBitReader.BD: Double;
var
  LCode: Byte;
begin
  LCode := BB;
  case LCode of
    0: Result := RD;
    1: Result := 1.0;
    2: Result := 0.0;
  else
    Result := 0.0;
  end;
end;

function TDwgBitReader.BT: Double;
begin
  if B = 1 then
    Result := 0.0
  else
    Result := BD;
end;

function TDwgBitReader.MC: Integer;
var
  LByte: Byte;
  LResult: Cardinal;
  LShift: Integer;
  LNeg: Boolean;
begin
  LResult := 0;
  LShift  := 0;
  LNeg    := False;
  repeat
    LByte  := ReadByte;
    if LShift = 0 then
      LNeg := (LByte and $40) <> 0;  // bit 6 = işaret
    LResult := LResult or (Cardinal(LByte and $3F) shl LShift);
    Inc(LShift, 6);
  until (LByte and $80) = 0;         // bit 7 = devam

  Result := Integer(LResult);
  if LNeg then
    Result := -Result;
end;

function TDwgBitReader.MS: Cardinal;
var
  LB0, LB1: Byte;
begin
  LB0 := ReadByte;
  if (LB0 and $80) <> 0 then
  begin
    LB1 := ReadByte;
    Result := Cardinal(LB0 and $7F) or (Cardinal(LB1) shl 7);
  end
  else
    Result := LB0;
end;

function TDwgBitReader.TV: string;
var
  LLen: SmallInt;
  LBytes: TBytes;
  I: Integer;
begin
  LLen := RS;
  if LLen <= 0 then
    Exit('');
  SetLength(LBytes, LLen);
  for I := 0 to LLen - 1 do
    LBytes[I] := ReadByte;
  try
    Result := TEncoding.GetEncoding(1252).GetString(LBytes);
  except
    Result := TEncoding.ASCII.GetString(LBytes);
  end;
end;

function TDwgBitReader.H: Int64;
var
  LMeta: Byte;
  LLen: Integer;
  I: Integer;
  LVal: Int64;
begin
  LMeta := ReadByte;
  LLen  := LMeta and $0F;
  LVal  := 0;
  for I := 0 to LLen - 1 do
    LVal := (LVal shl 8) or ReadByte;
  Result := LVal;
end;

function TDwgBitReader.BE: TPoint3D;
begin
  if B = 1 then
    Result := TPoint3D.Create(0, 0, 1)
  else
  begin
    Result.X := BD;
    Result.Y := BD;
    Result.Z := BD;
  end;
end;

function TDwgBitReader.P2RD: TPoint2D;
begin
  Result.X := RD;
  Result.Y := RD;
end;

function TDwgBitReader.P2BD: TPoint2D;
begin
  Result.X := BD;
  Result.Y := BD;
end;

function TDwgBitReader.P3BD: TPoint3D;
begin
  Result.X := BD;
  Result.Y := BD;
  Result.Z := BD;
end;

function TDwgBitReader.CMC: Integer;
var
  LByte: Byte;
  LFlags: Byte;
  LR, LG, LB: Byte;
begin
  LByte := ReadByte;
  if (LByte and $80) = 0 then
    // ACI index (0..127)
    Result := LByte
  else
  begin
    LFlags := LByte and $7F;
    Result := 256; // ByLayer varsayılan
    if (LFlags and $01) <> 0 then
    begin
      // Gerçek RGB — 3 byte (sıra: Blue, Green, Red per DWG spec)
      LB := ReadByte;
      LG := ReadByte;
      LR := ReadByte;
      // TrueColor → sonuçta yalnızca ByLayer döndürüyoruz (entity stil
      // çözümlemesi layer tablosundan yapılır)
      Result := Integer($FF000000 or (Cardinal(LR) shl 16)
                       or (Cardinal(LG) shl 8) or Cardinal(LB));
    end;
    if (LFlags and $02) <> 0 then
    begin
      TV; // renk kitabı adı — atla
      TV; // renk adı      — atla
    end;
  end;
end;

end.
