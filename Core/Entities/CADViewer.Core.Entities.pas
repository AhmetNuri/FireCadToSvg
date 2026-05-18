/// <summary>
/// CADViewer.Core.Entities
/// DXF ham varlık (entity) veri yapıları.
/// Bu kayıtlar parser tarafından doldurulan ham DXF verisidir.
/// DrawShapes katmanına dönüştürülmeden önce burada tutulur.
/// Her struct, DXF spesifikasyonundaki group code'lara karşılık gelir.
/// </summary>
unit CADViewer.Core.Entities;

{$SCOPEDENUMS ON}

interface

uses
  System.Generics.Collections,
  CADViewer.Core.Types;

type

  // =========================================================================
  // Temel varlık ortak alanları (SOLID: temel sınıf yerine composition)
  // =========================================================================

  /// <summary>
  /// Tüm DXF varlıklarında ortak olan alanlar (group code 5, 8, 62 vb.).
  /// Record composition ile kullanılır.
  /// </summary>
  TDxfEntityCommon = record
    Handle: string;           // Grup 5: benzersiz tanımlayıcı
    LayerName: string;        // Grup 8: katman adı
    ColorNumber: Integer;     // Grup 62: ACI renk kodu (-1 = ByLayer, 0 = ByBlock)
    TrueColorRgb: Integer;    // Grup 420: TrueColor (0xRRGGBB)
    LineTypeName: string;     // Grup 6: çizgi tipi adı
    LineWeight: Integer;      // Grup 370: çizgi kalınlığı
    LtScale: Double;          // Grup 48: çizgi tipi scale
    Transparency: Double;     // Grup 440: saydamlık (0.0–1.0)
    Visible: Boolean;         // Grup 60: görünürlük (0=görünür, 1=gizli)
    SpaceFlag: Integer;       // Grup 67: model(0)/paper(1) space
  end;

  // =========================================================================
  // LINE varlığı
  // =========================================================================

  /// <summary>
  /// DXF LINE varlığı. Başlangıç ve bitiş noktası ile tanımlı doğru parçası.
  /// </summary>
  TDxfLineEntity = record
    Common: TDxfEntityCommon;
    StartPoint: TPoint3D;  // Grup 10, 20, 30
    EndPoint: TPoint3D;    // Grup 11, 21, 31
    Thickness: Double;     // Grup 39
  end;

  // =========================================================================
  // CIRCLE varlığı
  // =========================================================================

  /// <summary>
  /// DXF CIRCLE varlığı.
  /// </summary>
  TDxfCircleEntity = record
    Common: TDxfEntityCommon;
    Center: TPoint3D;      // Grup 10, 20, 30
    Radius: Double;        // Grup 40
    Thickness: Double;     // Grup 39
  end;

  // =========================================================================
  // ARC varlığı
  // =========================================================================

  /// <summary>
  /// DXF ARC varlığı. Belirtilen merkez, yarıçap, başlangıç/bitiş açıları
  /// ile tanımlı yay. Açılar derece cinsindendir, CCW (saat yönü tersi) pozitif.
  /// </summary>
  TDxfArcEntity = record
    Common: TDxfEntityCommon;
    Center: TPoint3D;       // Grup 10, 20, 30
    Radius: Double;         // Grup 40
    StartAngle: Double;     // Grup 50 (derece, CCW)
    EndAngle: Double;       // Grup 51 (derece, CCW)
    Thickness: Double;      // Grup 39
  end;

  // =========================================================================
  // ELLIPSE varlığı
  // =========================================================================

  /// <summary>
  /// DXF ELLIPSE varlığı.
  /// Merkez noktası, büyük eksen uç noktası ve küçük/büyük eksen oranı ile tanımlı.
  /// Parametre açıları (41, 42) radyan cinsindendir.
  /// </summary>
  TDxfEllipseEntity = record
    Common: TDxfEntityCommon;
    Center: TPoint3D;         // Grup 10, 20, 30
    MajorAxisEnd: TPoint3D;   // Grup 11, 21, 31 (merkeze göre relatif)
    MinorToMajorRatio: Double;// Grup 40 (küçük eksen / büyük eksen)
    StartParam: Double;       // Grup 41 (radyan, 0 = büyük eksen yönü)
    EndParam: Double;         // Grup 42 (radyan, 2π = tam elips)
  end;

  // =========================================================================
  // LWPOLYLINE varlığı (Lightweight Polyline)
  // =========================================================================

  /// <summary>
  /// LWPOLYLINE köşe noktası.
  /// </summary>
  TLwPolylineVertex = record
    X, Y: Double;       // Grup 10, 20
    StartWidth: Double; // Grup 40
    EndWidth: Double;   // Grup 41
    Bulge: Double;      // Grup 42 (0 = düz, ±1 = yarım daire)
  end;

  /// <summary>
  /// DXF LWPOLYLINE varlığı. Yeni DXF versiyonlarındaki optimize polyline.
  /// </summary>
  TDxfLwPolylineEntity = record
    Common: TDxfEntityCommon;
    Flags: Integer;                               // Grup 70 (bit 1 = kapalı)
    ConstantWidth: Double;                        // Grup 43
    Elevation: Double;                            // Grup 38
    Thickness: Double;                            // Grup 39
    Vertices: TArray<TLwPolylineVertex>;          // Köşe noktaları listesi
    IsClosed: Boolean;                            // Flags bit 1 yorumlanmış
  end;

  // =========================================================================
  // POLYLINE varlığı (eski format)
  // =========================================================================

  /// <summary>
  /// Eski POLYLINE format köşe noktası.
  /// </summary>
  TPolylineVertex = record
    X, Y, Z: Double;    // Grup 10, 20, 30
    Bulge: Double;      // Grup 42
    StartWidth: Double; // Grup 40
    EndWidth: Double;   // Grup 41
  end;

  /// <summary>
  /// DXF POLYLINE varlığı (eski R12 format).
  /// </summary>
  TDxfPolylineEntity = record
    Common: TDxfEntityCommon;
    Flags: Integer;
    DefaultStartWidth: Double;
    DefaultEndWidth: Double;
    Elevation: Double;
    Thickness: Double;
    Vertices: TArray<TPolylineVertex>;
    IsClosed: Boolean;
  end;

  // =========================================================================
  // TEXT varlığı
  // =========================================================================

  /// <summary>
  /// DXF TEXT varlığı. Tek satır metin.
  /// </summary>
  TDxfTextEntity = record
    Common: TDxfEntityCommon;
    InsertionPoint: TPoint3D;  // Grup 10, 20, 30
    AlignmentPoint: TPoint3D;  // Grup 11, 21, 31 (hizalama için)
    Height: Double;            // Grup 40 (metin yüksekliği)
    WidthFactor: Double;       // Grup 41 (genişlik faktörü, 1.0 = normal)
    ObliqueAngle: Double;      // Grup 51 (eğim açısı, derece)
    Rotation: Double;          // Grup 50 (döndürme açısı, derece)
    Content: string;           // Grup 1 (metin içeriği)
    StyleName: string;         // Grup 7 (metin stili adı)
    HAlign: Integer;           // Grup 72 (yatay hizalama)
    VAlign: Integer;           // Grup 73 (dikey hizalama)
    Flags: Integer;            // Grup 71
  end;

  // =========================================================================
  // MTEXT varlığı (Multiline Text)
  // =========================================================================

  /// <summary>
  /// DXF MTEXT varlığı. Çok satırlı metin.
  /// </summary>
  TDxfMTextEntity = record
    Common: TDxfEntityCommon;
    InsertionPoint: TPoint3D;  // Grup 10, 20, 30
    XAxisDirection: TPoint3D;  // Grup 11, 21, 31
    Height: Double;            // Grup 40
    RectWidth: Double;         // Grup 41 (metin kutusu genişliği)
    Rotation: Double;          // Grup 50 (radyan)
    Content: string;           // Grup 1 (ve 3: ek satırlar)
    StyleName: string;         // Grup 7
    AttachmentPoint: Integer;  // Grup 71 (1-9: konumlandırma)
    DrawingDirection: Integer; // Grup 72
    LineSpacing: Double;       // Grup 44
  end;

  // =========================================================================
  // INSERT varlığı (Block Reference)
  // =========================================================================

  /// <summary>
  /// INSERT (blok referansı) için attribute değeri.
  /// </summary>
  TInsertAttribute = record
    Tag: string;      // Grup 2
    Value: string;    // Grup 1
    Position: TPoint3D;
    Height: Double;
    Rotation: Double;
  end;

  /// <summary>
  /// DXF INSERT varlığı. Bir bloğu referans gösterir.
  /// </summary>
  TDxfInsertEntity = record
    Common: TDxfEntityCommon;
    BlockName: string;         // Grup 2
    InsertionPoint: TPoint3D;  // Grup 10, 20, 30
    ScaleX: Double;            // Grup 41 (X scale faktörü)
    ScaleY: Double;            // Grup 42 (Y scale faktörü)
    ScaleZ: Double;            // Grup 43 (Z scale faktörü)
    Rotation: Double;          // Grup 50 (derece)
    ColCount: Integer;         // Grup 70 (sütun sayısı)
    RowCount: Integer;         // Grup 71 (satır sayısı)
    ColSpacing: Double;        // Grup 44
    RowSpacing: Double;        // Grup 45
    Attributes: TArray<TInsertAttribute>;
  end;

  // =========================================================================
  // DIMENSION varlığı
  // =========================================================================

  /// <summary>
  /// DXF DIMENSION varlığı (temel seviye desteği).
  /// </summary>
  TDxfDimensionEntity = record
    Common: TDxfEntityCommon;
    BlockName: string;          // Grup 2 (çizim bloğu adı)
    DefinitionPoint: TPoint3D;  // Grup 10, 20, 30
    TextMidPoint: TPoint3D;     // Grup 11, 21, 31
    DimType: Integer;           // Grup 70 (0=linear, 1=aligned, 2=angular, vb.)
    DimStyleName: string;       // Grup 3
    TextOverride: string;       // Grup 1 (boş = otomatik)
    Measurement: Double;        // Grup 42
    Point1: TPoint3D;           // Grup 13, 23, 33
    Point2: TPoint3D;           // Grup 14, 24, 34
    Point3: TPoint3D;           // Grup 15, 25, 35
    Point4: TPoint3D;           // Grup 16, 26, 36
    LeaderLength: Double;       // Grup 40
    Rotation: Double;           // Grup 50
  end;

  // =========================================================================
  // SPLINE varlığı
  // =========================================================================

  /// <summary>
  /// DXF SPLINE varlığı.
  /// </summary>
  TDxfSplineEntity = record
    Common: TDxfEntityCommon;
    Flags: Integer;                         // Grup 70
    Degree: Integer;                        // Grup 71
    KnotCount: Integer;                     // Grup 72
    ControlPointCount: Integer;             // Grup 73
    FitPointCount: Integer;                 // Grup 74
    KnotTolerance: Double;                  // Grup 42
    ControlPointTolerance: Double;          // Grup 43
    FitTolerance: Double;                   // Grup 44
    StartTangent: TPoint3D;                 // Grup 12, 22, 32
    EndTangent: TPoint3D;                   // Grup 13, 23, 33
    Knots: TArray<Double>;                  // Grup 40 (tekrar)
    ControlPoints: TArray<TPoint3D>;        // Grup 10, 20, 30 (tekrar)
    FitPoints: TArray<TPoint3D>;            // Grup 11, 21, 31 (tekrar)
    Weights: TArray<Double>;                // Grup 41 (tekrar)
    IsClosed: Boolean;
    IsPeriodic: Boolean;
    IsRational: Boolean;
  end;

  // =========================================================================
  // POINT varlığı
  // =========================================================================

  /// <summary>
  /// DXF POINT varlığı.
  /// </summary>
  TDxfPointEntity = record
    Common: TDxfEntityCommon;
    Position: TPoint3D;    // Grup 10, 20, 30
    Thickness: Double;     // Grup 39
  end;

  // =========================================================================
  // Blok Tanımı
  // =========================================================================

  /// <summary>
  /// DXF BLOCK tanımı. INSERT varlıkları bu blokları referans alır.
  /// </summary>
  TDxfBlockDef = record
    Name: string;           // Grup 2 (blok adı)
    LayerName: string;      // Grup 8
    BasePoint: TPoint3D;    // Grup 10, 20, 30 (orijin noktası)
    Flags: Integer;         // Grup 70
    Description: string;    // Grup 4
    // Blok içindeki varlıklar ayrı bir entity list olarak saklanır
    // (TDxfDocument.Blocks sözlüğünde)
  end;

  // =========================================================================
  // HEADER değişken türü
  // =========================================================================

  /// <summary>
  /// DXF HEADER bölümündeki sistem değişkenlerini saklar.
  /// $ACADVER, $LIMMIN, $LIMMAX, $EXTMIN, $EXTMAX vb.
  /// </summary>
  TDxfHeaderVars = record
    AcadVersion: string;      // $ACADVER
    InsUnits: Integer;         // $INSUNITS (birim tipi)
    ExtMin: TPoint3D;          // $EXTMIN (çizim sınırı minimum)
    ExtMax: TPoint3D;          // $EXTMAX (çizim sınırı maksimum)
    LimMin: TPoint2D;          // $LIMMIN
    LimMax: TPoint2D;          // $LIMMAX
    CurrentLayer: string;      // $CLAYER
    TextSize: Double;           // $TEXTSIZE
    LtScale: Double;            // $LTSCALE
    AttMode: Integer;           // $ATTMODE
    HasExtents: Boolean;        // EXTMIN/EXTMAX set edildi mi?
  end;

implementation

end.
