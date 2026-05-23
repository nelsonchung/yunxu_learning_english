import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/presentation/widgets/image_preview.dart';

void main() {
  testWidgets('tapping zoom-enabled preview opens adjustable image viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePreview(
            imageFile: null,
            imageBytes: _transparentPng,
            enableZoom: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ImagePreview));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pumpAndSettle();

    expect(find.text('1.5x'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final resettingScale = viewer.transformationController!.value
        .getMaxScaleOnAxis();
    expect(resettingScale, greaterThan(1));
    expect(resettingScale, lessThan(1.5));

    await tester.pumpAndSettle();
    expect(find.text('1.0x'), findsOneWidget);
  });

  testWidgets(
    'double tapping viewer zooms into tapped area and single tap resets',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImagePreview(
              imageFile: null,
              imageBytes: _transparentPng,
              enableZoom: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ImagePreview));
      await tester.pumpAndSettle();

      final viewerFinder = find.byType(InteractiveViewer);
      final tapPoint = tester.getCenter(viewerFinder) + const Offset(40, 24);

      await tester.tapAt(tapPoint);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tapPoint);
      await tester.pumpAndSettle();

      expect(find.text('2.5x'), findsOneWidget);

      final zoomedViewer = tester.widget<InteractiveViewer>(viewerFinder);
      final zoomedMatrix = zoomedViewer.transformationController!.value;
      expect(zoomedMatrix.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
      expect(zoomedMatrix.storage[12], isNonZero);
      expect(zoomedMatrix.storage[13], isNonZero);

      await tester.tap(viewerFinder);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('1.0x'), findsOneWidget);

      final resetViewer = tester.widget<InteractiveViewer>(viewerFinder);
      final resetMatrix = resetViewer.transformationController!.value;
      expect(resetMatrix.getMaxScaleOnAxis(), closeTo(1, 0.01));
      expect(resetMatrix.storage[12], closeTo(0, 0.01));
      expect(resetMatrix.storage[13], closeTo(0, 0.01));
    },
  );
}

final _transparentPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
