// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class TicketImageService {
  static const String _templateAssetPath = 'assets/ticket_template.png';

  Future<Uint8List> createTicketImage({
    required int numero1,
    required int numero2,
    required int numero3,
    required int numero4,
    required String nome_comprador,
    required String numero_comprador,
    required String nome_vendedor,
    required String numero_vendedor,
    required String data_venda,
  }) async {
    final ByteData data = await rootBundle.load(_templateAssetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Image template = await _decodeImage(bytes);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    canvas.drawImage(template, Offset.zero, Paint());

    final String n1 = numero1.toString().padLeft(4, '0');
    final String n2 = numero2.toString().padLeft(4, '0');
    final String n3 = numero3.toString().padLeft(4, '0');
    final String n4 = numero4.toString().padLeft(4, '0');

    final TextStyle numberStyle = const TextStyle(
      color: Colors.black,
      fontSize: 28,
      fontWeight: FontWeight.w900,
      letterSpacing: 1,
    );

    // Number slots on template left side.
    await _drawText(canvas, n1, const Offset(52, 130), numberStyle);
    await _drawText(canvas, n2, const Offset(172, 130), numberStyle);
    await _drawText(canvas, n3, const Offset(52, 204), numberStyle);
    await _drawText(canvas, n4, const Offset(176, 204), numberStyle);

    final TextStyle infoStyle = const TextStyle(
      color: Colors.black,
      fontSize: 13,
      fontWeight: FontWeight.normal,
    );

    final String buyerName = _limit(nome_comprador, 20);
    final String buyerPhone = _digitsOnly(numero_comprador);
    final String sellerName = _limit(nome_vendedor, 20);
    final String sellerPhone = _digitsOnly(numero_vendedor);

    await _drawText(canvas, buyerName, const Offset(282, 98), infoStyle);
    await _drawText(canvas, buyerPhone, const Offset(282, 128), infoStyle);
    await _drawText(canvas, sellerName, const Offset(284, 190), infoStyle);
    await _drawText(canvas, sellerPhone, const Offset(284, 222), infoStyle);

    final List<String> soldAtParts = data_venda.trim().split(RegExp(r'\s+'));
    final String soldDate = soldAtParts.isNotEmpty ? soldAtParts.first : '';
    final String soldTime = soldAtParts.length > 1 ? soldAtParts[1] : '';
    final String soldAtText = soldTime.isEmpty
        ? soldDate
        : '$soldDate   $soldTime';
    await _drawRotatedText(
      canvas,
      soldAtText,
      const Offset(509, 141),
      -math.pi / 2,
      const TextStyle(
        color: Colors.black,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: 120,
    );

    final ui.Image resultImage = await recorder.endRecording().toImage(
      template.width,
      template.height,
    );

    final ByteData? png = await resultImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return png!.buffer.asUint8List();
  }

  Future<File> createTicketImageFile({
    required int numero1,
    required int numero2,
    required int numero3,
    required int numero4,
    required String nome_comprador,
    required String numero_comprador,
    required String nome_vendedor,
    required String numero_vendedor,
    required String data_venda,
    String? fileName,
  }) async {
    final Uint8List imageBytes = await createTicketImage(
      numero1: numero1,
      numero2: numero2,
      numero3: numero3,
      numero4: numero4,
      nome_comprador: nome_comprador,
      numero_comprador: numero_comprador,
      nome_vendedor: nome_vendedor,
      numero_vendedor: numero_vendedor,
      data_venda: data_venda,
    );

    final Directory tempDir = await getTemporaryDirectory();
    final String name =
        fileName ?? 'ticket_${DateTime.now().millisecondsSinceEpoch}.png';
    final File file = File('${tempDir.path}/$name');
    await file.writeAsBytes(imageBytes, flush: true);
    return file;
  }

  Future<void> shareTicketGeneric(File imageFile) async {
    await Share.shareXFiles(<XFile>[XFile(imageFile.path)]);
  }

  Future<void> shareTicketViaWhatsapp(File imageFile) async {
    await Share.shareXFiles(<XFile>[XFile(imageFile.path)]);
  }

  Future<void> shareTicketViaInstagram(File imageFile) async {
    await Share.shareXFiles(<XFile>[XFile(imageFile.path)]);
  }

  Future<void> shareManyGeneric(List<File> imageFiles) async {
    if (imageFiles.isEmpty) {
      return;
    }
    await Share.shareXFiles(imageFiles.map((File f) => XFile(f.path)).toList());
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double maxWidth = 220,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.left,
  }) async {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: maxLines,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);

    painter.paint(canvas, offset);
  }

  Future<void> _drawRotatedText(
    Canvas canvas,
    String text,
    Offset origin,
    double angle,
    TextStyle style, {
    double maxWidth = 220,
  }) async {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);
    await _drawText(
      canvas,
      text,
      Offset.zero,
      style,
      maxWidth: maxWidth,
      maxLines: 1,
      textAlign: TextAlign.left,
    );
    canvas.restore();
  }

  String _limit(String value, int maxLength) {
    final String trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return trimmed.substring(0, maxLength);
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
