import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Local fixture artwork. No selected file, account, API or session is used.
Future<Uint8List> syntheticContractPng({required bool landscape}) async {
  final width = landscape ? 2200 : 1280;
  final height = landscape ? 1200 : 2480;
  const ink = Color(0xFF182C3F);
  const teal = Color(0xFF156966);
  const paper = Color(0xFFFAF8F0);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();

  void box(double x, double y, double w, double h, Color color) {
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint..color = color);
  }

  void line(
    String value,
    double x,
    double y,
    double maxWidth, {
    double size = 27,
    Color color = ink,
    bool bold = false,
    bool italic = false,
  }) {
    final text = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size))
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      );
    text.addText(value);
    final paragraph = text.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  final contentWidth = width - 160.0;
  box(0, 0, width.toDouble(), height.toDouble(), paper);
  box(0, 0, width.toDouble(), 20, teal);
  line('ALDER & LANTERN STUDIO', 80, 66, contentWidth, color: teal, bold: true);
  line(
    landscape ? 'Service Schedule & Rate Card' : 'Studio Services Agreement',
    80,
    127,
    contentWidth,
    size: 56,
    bold: true,
  );
  line(
    'FICTIONAL SAMPLE  /  AL-024  /  14 MAY 2041',
    80,
    209,
    contentWidth,
    size: 22,
    color: teal,
    bold: true,
  );
  box(80, 263, contentWidth, 4, teal);

  const titles = [
    'Parties and purpose',
    'Scope of services',
    'Delivery and acceptance',
    'Fees and payment',
    'Revisions and cancellation',
    'Records and correspondence',
  ];
  const paragraphs = [
    'This agreement records a fictional design commission between Alder & Lantern Studio and Sample Workshop. It is provided for document reading practice.',
    'The studio will prepare a concept sketch, two layout options, and one final proof. The workshop will provide consolidated feedback at each milestone.',
    'The workshop will review each proof within five business days. The studio will record written acceptance in the project log and retain the approved reference.',
    'The estimate assumes three review meetings and one round of revisions. Additional work requires written approval before the studio schedules it.',
    'Either party may request a schedule adjustment. The parties will record any change to the scope, dates, or fees in the next signed revision.',
    'Project messages will use reference AL-024. Each party will retain a copy of the signed agreement and the final schedule with its project records.',
  ];

  if (landscape) {
    final columnWidth = (contentWidth - 80) / 2;
    for (var i = 0; i < 3; i++) {
      final y = 311.0 + i * 161;
      line('0${i + 1}  ${titles[i]}', 80, y, columnWidth, size: 32, bold: true);
      line(paragraphs[i], 80, y + 49, columnWidth);
    }
    final x = 160 + columnWidth;
    box(x, 312, columnWidth, 50, teal);
    line(
      'MILESTONE                              ESTIMATE',
      x + 22,
      322,
      columnWidth - 44,
      color: Colors.white,
      bold: true,
    );
    for (final (index, task) in [
      'Concept sketch',
      'Layout options',
      'Review and revisions',
      'Final proof',
    ].indexed) {
      final y = 362.0 + index * 68;
      box(
        x,
        y,
        columnWidth,
        67,
        index.isEven ? const Color(0xFFE3ECE8) : const Color(0xFFF0F2EA),
      );
      line(task, x + 22, y + 17, columnWidth / 2);
      line(
        '${(index + 1) * 125}.00 credits',
        x + columnWidth * .62,
        y + 17,
        columnWidth * .35,
      );
    }
  } else {
    for (var i = 0; i < titles.length; i++) {
      final y = 310.0 + i * 300;
      line(
        '0${i + 1}  ${titles[i]}',
        80,
        y,
        contentWidth,
        size: 35,
        bold: true,
      );
      line(paragraphs[i], 80, y + 61, contentWidth, size: 30);
      line(
        'Record ${i + 1} of 6 · Initial each approved change in the project log.',
        80,
        y + 183,
        contentWidth,
        size: 23,
        color: teal,
      );
      box(80, y + 239, contentWidth, 2, const Color(0xFFBCCFC9));
    }
  }

  final signatureY = height - 270.0;
  line(
    'SAMPLE SIGNATURES',
    80,
    signatureY,
    contentWidth,
    size: 22,
    color: teal,
    bold: true,
  );
  line(
    'Rowan Example',
    80,
    signatureY + 46,
    contentWidth / 2,
    size: 42,
    italic: true,
  );
  line(
    'Quinn Fiction',
    100 + contentWidth / 2,
    signatureY + 46,
    contentWidth / 2,
    size: 42,
    italic: true,
  );
  box(80, signatureY + 112, contentWidth, 2, teal);
  line('Studio representative', 80, signatureY + 127, contentWidth / 2);
  line(
    'Workshop representative',
    100 + contentWidth / 2,
    signatureY + 127,
    contentWidth / 2,
  );
  line(
    'AL-024  ·  SYNTHETIC TRAINING DOCUMENT  ·  PAGE 1 OF 1',
    80,
    height - 62,
    contentWidth,
    size: 20,
    color: teal,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}
