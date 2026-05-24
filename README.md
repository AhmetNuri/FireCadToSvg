# CADViewer — Delphi FireMonkey DXF Görüntüleyici

Delphi **FireMonkey** + **Skia4Delphi** kullanan, kurumsal standartlarda, tam **MVC** mimarisiyle yazılmış DXF/STEP/IGES dosyası görüntüleyici.

---

## 📁 Proje Yapısı

```
CADViewer/
├── Core/
│   ├── CADViewer.Core.Types.pas          ← Temel tipler (TPoint2D, TViewport, TBoundingBox…)
│   ├── CADViewer.Core.Interfaces.pas     ← Tüm servis interface'leri (IDxfParser, ICanvasRenderer…)
│   ├── Entities/
│   │   └── CADViewer.Core.Entities.pas  ← Ham DXF varlık kayıtları (TDxfLineEntity, TDxfArcEntity…)
│   └── Models/
│       ├── CADViewer.Core.Models.DrawShapes.pas   ← Soyut çizim hiyerarşisi (TDrawShape…)
│       └── CADViewer.Core.Models.DxfDocument.pas  ← Belge modeli (katmanlar, bloklar, varlıklar)
│
├── Parsers/
│   ├── DXF/
│   │   ├── CADViewer.Parsers.DXF.Reader.pas  ← Düşük seviye DXF token okuyucu
│   │   └── CADViewer.Parsers.DXF.Parser.pas  ← Yüksek seviye DXF ayrıştırıcı + TParserFactory
│   └── STEP/
│       └── CADViewer.Parsers.STEP.Parser.pas ← STEP/IGES parser
│
├── Services/
│   ├── FileServices/
│   │   └── CADViewer.Services.FileServices.pas        ← Dosya yükleme + encoding tespiti
│   ├── Transformation/
│   │   └── CADViewer.Services.Transformation.pas      ← Viewport / Zoom / Pan servisi
│   ├── Rendering/
│   │   └── CADViewer.Services.Rendering.DxfRenderer.pas ← Skia4Delphi tabanlı renderer
│   └── Export/
│       └── CADViewer.Services.Export.SvgExporter.pas    ← Ortak modelden SVG export
│
├── Controllers/
│   └── CADViewer.Controllers.DxfViewerController.pas  ← MVC Controller
│
├── Views/
│   └── DxfViewer/
│       ├── uFrmDxfViewer.pas   ← Ana form (TSkPaintBox, araç çubuğu, katman paneli)
│       └── uFrmDxfViewer.fmx   ← FMX tasarım dosyası
│
├── Utils/
│   └── CADViewer.Utils.pas     ← ACI renk tablosu, matematik, string araçları
│
├── CADViewer.dpr               ← Delphi proje dosyası
└── CADViewer.dproj             ← MSBuild proje dosyası
```

---

## 🏗️ Mimari Kararlar

### MVC Katmanları

| Katman | Sorumluluk | Dışa Bağımlılık |
|--------|-----------|-----------------|
| **Model** | `TDxfDocument`, `TDrawShape` hiyerarşisi | Yok |
| **View** | `TFrmDxfViewer` — Sadece UI ve olaylar | `IViewerController` |
| **Controller** | `TDxfViewerController` — İş mantığı koordinasyonu | Model + Servisler |

### Tasarım Desenleri

- **Factory Pattern** — `TParserFactory`: Dosya uzantısına göre doğru parser'ı döndürür. DWG/IGES/STEP desteği sadece factory güncellenerek eklenir.
- **Strategy Pattern** — `TSkiaRenderer.RenderShape()`: Her şekil türü için ayrı render metodu.
- **Composite Pattern** — `TDrawComposite`: INSERT/blok referansı içinde iç içe şekiller.
- **Template Method** — `TDrawShape.GetBounds()`: Lazy bounds hesaplama, alt sınıflar `CalcBoundsInternal` override eder.
- **Observer Pattern** — `IDocumentObserver`: Controller → View bildirim mekanizması.

### SOLID Uyumu

- **S**ingle Responsibility: Her sınıf tek iş yapar (parser yalnızca ayrıştırır, renderer yalnızca çizer)
- **O**pen/Closed: Yeni entity tipi eklemek için sadece parser'a yeni `ParseXxx` metodu eklenir
- **L**iskov Substitution: `TDrawLine`, `TDrawCircle` vb. `TDrawShape` yerine kullanılabilir
- **I**nterface Segregation: `IDxfReader`, `IDxfParser`, `ICanvasRenderer` küçük tutulmuş
- **D**ependency Inversion: Controller somut sınıflara değil, interface'lere bağımlı

---

## 🎯 Desteklenen Formatlar ve Entity'ler

### DXF

| Entity | Durum |
|--------|-------|
| LINE | ✅ Tam destek |
| CIRCLE | ✅ Tam destek |
| ARC | ✅ Tam destek |
| ELLIPSE | ✅ Tam destek (kısmi elips dahil) |
| LWPOLYLINE | ✅ Bulge (yay segmenti) dahil |
| POLYLINE + VERTEX | ✅ Eski format |
| TEXT | ✅ Hizalama, döndürme, genişlik faktörü |
| MTEXT | ✅ Çok satırlı, format kodu temizleme |
| INSERT (Block Ref) | ✅ Transform, scale, döndürme |
| DIMENSION | ✅ Temel (blok referansı çözümü) |
| SPLINE | ✅ B-spline yaklaşımı (de Boor) |
| POINT | ✅ Çapraz sembol |

---

### STEP / IGES (ASCII STEP yapısı)

| Entity | Durum |
|--------|-------|
| LINE | ✅ |
| CIRCLE | ✅ |
| ARC (TRIMMED_CURVE) | ✅ |
| POLYLINE | ✅ |
| SURFACE / EDGE (basitleştirilmiş wireframe) | ✅ |

---

## ⚡ Performans Özellikleri

- **Bounding Box Culling**: Viewport dışındaki şekiller render edilmez
- **Lazy Bounds Hesaplama**: `TDrawShape.GetBounds()` ilk çağrıda hesaplar, önbelleğe alır
- **Encoding Tespiti**: BOM → UTF-8 doğrulama → Windows-1252 fallback
- **Büyük Dosya Desteği**: Tüm satırlar belleğe alınır (streaming geliştirmesi için `IDxfReader` hazır)

---

## 🖥️ Kullanım

### Fare
| Eylem | Sonuç |
|-------|-------|
| Sol tuş sürükle | Pan (kaydır) |
| Tekerlek yukarı/aşağı | Zoom In/Out |
| Çift tıkla | Ekrana Sığdır |

### Klavye
| Tuş | Eylem |
|-----|-------|
| `←` `→` `↑` `↓` | Pan |
| `+` / `-` | Zoom |
| `F` | Fit to Screen |
| `R` | Reset View |

---

## 🔧 Gereksinimler

- **Delphi** 12.x veya üzeri (inline var, record operator overload)
- **Skia4Delphi** paketi kurulu
- **FMX** (FireMonkey) framework
- **Platform**: Win32, Win64, macOS, iOS, Android (FMX cross-platform)

---

## 🚀 Gelecek Geliştirmeler

- [ ] DWG format desteği (`TDwgParser` eklenecek, factory hazır)
- [x] IGES / STEP format desteği
- [ ] Hatch (tarama) render desteği
- [ ] Streaming parsing (çok büyük dosyalar için)
- [ ] Yazdırma / PDF export
- [ ] Snap / osnap araçları
- [ ] Undo/Redo (Command Pattern altyapısı)
