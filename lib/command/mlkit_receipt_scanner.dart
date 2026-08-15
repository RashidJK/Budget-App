import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_scanner.dart';

/// Real on-device receipt OCR via Google ML Kit (free, no network, no API key).
///
/// Deliberately thin: ML Kit reads the text off the image, and the tested,
/// pure [ReceiptTextParser] does all the interpreting. The native part has no
/// heuristics of its own, so there's nothing here that a unit test can't reach
/// through the parser. Isolated in its own file so nothing else imports the
/// native plugin — tests and non-mobile builds use the mock.
class MlKitReceiptScanner implements ReceiptScanner {
  MlKitReceiptScanner({this.now});

  final DateTime Function()? now;
  final ReceiptTextParser _parser = const ReceiptTextParser();

  @override
  Future<ScannedReceipt?> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      if (recognized.text.trim().isEmpty) return null;
      return _parser.parse(recognized.text, now: now?.call());
    } finally {
      // Always release the native recognizer.
      await recognizer.close();
    }
  }
}
