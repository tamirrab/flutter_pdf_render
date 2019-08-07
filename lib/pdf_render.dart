import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PdfDocument {
  static const MethodChannel _channel = const MethodChannel('pdf_render');

  final String sourceName;
  final int docId;
  final int verMajor;
  final int verMinor;
  final bool isEncrypted;
  int _pageCount;
  bool _isUnlocked;
  bool _allowsCopying;
  bool _allowsPrinting;
  List<PdfPage> _pages;

  int get pageCount => _pageCount;
  bool get isUnlocked => _isUnlocked;
  bool get allowsCopying => _allowsCopying;
  bool get allowsPrinting => _allowsPrinting;

  PdfDocument._({
    @required this.sourceName,
    @required this.docId,
    @required this.verMajor, @required this.verMinor,
    @required this.isEncrypted,
    @required int pageCount,
    @required bool isUnlocked,
    @required bool allowsCopying,
    @required bool allowsPrinting
  }) :
    _pageCount = pageCount,
    _isUnlocked = isUnlocked,
    _allowsCopying = allowsCopying,
    _allowsPrinting = allowsPrinting,
    _pages = List<PdfPage>(pageCount);

  void dispose() {
    _close();
  }

  void _close() {
    _channel.invokeMethod('close', docId);
  }

  static PdfDocument _open(Object obj, String sourceName) {
    if (obj is Map<dynamic, dynamic>) {
      return PdfDocument._(
        sourceName: sourceName,
        docId: obj['docId'] as int,
        pageCount: obj['pageCount'] as int,
        verMajor: obj['verMajor'] as int,
        verMinor: obj['verMinor'] as int,
        isEncrypted: obj['isEncrypted'] as bool,
        allowsCopying: obj['allowsCopying'] as bool,
        allowsPrinting: obj['allowsPrinting'] as bool,
        isUnlocked: obj['isUnlocked'] as bool
      );
    } else {
      return null;
    }
  }

  static Future<PdfDocument> openFile(String filePath, {String password}) async {
    return _open(await _channel.invokeMethod('file', {'filePath': filePath, 'password': password}), filePath);
  }

  static Future<PdfDocument> openAsset(String name, {String password}) async {
    return _open(await _channel.invokeMethod('asset', {'assetName': name, 'password': password}), 'asset:' + name);
  }

  static Future<PdfDocument> openData(Uint8List data, {String password}) async {
    return _open(await _channel.invokeMethod('data', {'data': data, 'password': password}), 'memory');
  }

  Future<bool> unlockWithPassword(String password) async {
    if (_isUnlocked) {
      return true;
    }
    _isUnlocked = await _channel.invokeMethod<bool>('unlock', {
        "docId": docId,
        "password": password
      });
    if (_isUnlocked) {
      final obj = await _channel.invokeMethod('info', docId);
      if (obj is Map<dynamic, dynamic>) {
        _pageCount = obj['pageCount'] as int;
        _allowsCopying = obj['allowsCopying'] as bool;
        _allowsPrinting = obj['allowsPrinting'] as bool;
        _isUnlocked = obj['isUnlocked'] as bool;
        _pages = List<PdfPage>(pageCount);
      }
    }
    return _isUnlocked;
  }

  /// Get page object. The first page is 1.
  Future<PdfPage> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pageCount || !isUnlocked)
      return null;
    var page = _pages[pageNumber - 1];
    if (page == null) {
      var obj = await _channel.invokeMethod('page', {
        "docId": docId,
        "pageNumber": pageNumber
      });
      if (obj is Map<dynamic, dynamic>) {
        page = _pages[pageNumber - 1] = PdfPage(
          document: this,
          pageNumber: pageNumber,
          rotationAngle: obj['rotationAngle'] as int,
          width: obj['width'] as double,
          height: obj['height'] as double,
        );
      }
    }
    return page;
  }

  @override
  bool operator ==(dynamic other) => other is PdfDocument &&
    other.docId == docId;

  @override
  int get hashCode => docId;

  @override
  String toString() => sourceName;
}

class PdfPage {
  final PdfDocument document;
  final int pageNumber;
  final int rotationAngle;
  final double width;
  final double height;

  PdfPage({this.document, this.pageNumber, this.rotationAngle, this.width, this.height});

  /// Render a sub-area or full image of specified PDF file.
  /// [pdfFilePath] specifies PDF file to open.
  /// [pageNumber] specifies page to render in page number (1 is the first page).
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels. If they're not specified, [width] and [height] are used to specify the full size.
  /// If [dpi] is set, [fullWidth] and [fullHeight] are ignored and the page is rendered in the specified dpi.
  /// If [boxFit] is set, the page image is rendered in a size, that fits into the box specified by [fullWidth], [fullHeight].
  /// If [width], [height], [fullWidth], [fullHeight], and [dpi] are all 0, the page is rendered at 72 dpi.
  /// By default, [backgroundFill] is true and the page background is once filled with white before rendering page image but you can turn it off if needed.
  Future<PdfPageImage> render({int x = 0, int y = 0, int width = 0, int height = 0, double fullWidth = 0.0, double fullHeight = 0.0, bool backgroundFill = true}) async {
    return PdfPageImage._render(
      document, pageNumber,
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundFill: backgroundFill
    );
  }

  @override
  bool operator ==(dynamic other) => other is PdfPage &&
    other.document == document &&
    other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;

  @override
  String toString() => '$document:page=$pageNumber';
}

class PdfPageImage {
  static const MethodChannel _channel = const MethodChannel('pdf_render');

  /// Page number. The first page is 1.
  final int pageNumber;
  /// Left X coordinate of the rendered area in pixels.
  final int x;
  /// Top Y coordinate of the rendered area in pixels.
  final int y;
  /// Width of the rendered area in pixels.
  final int width;
  /// Height of the rendered area in pixels.
  final int height;
  /// Full width of the rendered page image in pixels.
  final double fullWidth;
  /// Full height of the rendered page image in pixels.
  final double fullHeight;
  /// PDF page width in points (width in pixels at 72 dpi).
  final double pageWidth;
  /// PDF page height in points (height in pixels at 72 dpi).
  final double pageHeight;
  /// Rendered image.
  final Image image;

  PdfPageImage({this.pageNumber, this.x, this.y, this.width, this.height, this.fullWidth, this.fullHeight, this.pageWidth, this.pageHeight, this.image});

  void dispose() {
    image?.dispose();
  }

  static Future<PdfPageImage> _render(
    PdfDocument document, int pageNumber,
    { int x = 0, int y = 0, int width = 0, int height = 0,
      double fullWidth = 0.0, double fullHeight = 0.0,
      bool backgroundFill = true,
    }) async {
    var obj = await _channel.invokeMethod(
      'render',
      {
        'docId': document.docId, 'pageNumber': pageNumber,
        'x': x, 'y': y, 'width': width, 'height': height,
        'fullWidth': fullWidth, 'fullHeight': fullHeight,
        'backgroundFill': backgroundFill
      });

    if (obj is Map<dynamic, dynamic>) {
      final retWidth = obj['width'] as int;
      final retHeight = obj['height'] as int;
      final pixels = obj['data'] as Uint8List;
      var image = await _decodeRgba(retWidth, retHeight, pixels);

      return PdfPageImage(
        pageNumber: obj['pageNumber'] as int,
        x: obj['x'] as int,
        y: obj['y'] as int,
        width: retWidth,
        height: retHeight,
        fullWidth: obj['fullWidth'] as double,
        fullHeight: obj['fullHeight'] as double,
        pageWidth: obj['pageWidth'] as double,
        pageHeight: obj['pageHeight'] as double,
        image: image
      );
    }
    return null;
  }

  static Future<PdfPageImage> render(String filePath, int pageNumber,
    { int x = 0, int y = 0, int width = 0, int height = 0,
      double fullWidth = 0.0, double fullHeight = 0.0}) async {
    final doc = await PdfDocument.openFile(filePath);
    if (doc == null) return null;
    final page = await doc.getPage(pageNumber);
    final image = await page.render(
      x: x, y: y,
      width: width,
      height: height,
      fullWidth: fullWidth, fullHeight: fullHeight);
    doc.dispose();
    return image;
  }

  /// Decode RGBA raw image from native code.
  static Future<Image> _decodeRgba(
    int width, int height, Uint8List pixels) {
    final comp = Completer<Image>();
    decodeImageFromPixels(pixels, width, height, PixelFormat.rgba8888,
      (image) => comp.complete(image));
    return comp.future;
  }
}
