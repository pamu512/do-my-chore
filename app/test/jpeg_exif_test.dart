import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/jpeg_exif.dart';

List<int> _jpegWithApp1() {
  return <int>[
    0xFF, 0xD8,
    0xFF, 0xE1, 0x00, 0x10,
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // Exif
    0x47, 0x50, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, // GPS-ish payload
    0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x7F,
    0xFF, 0xD9,
  ];
}

void main() {
  test('strips JPEG APP1 EXIF/GPS and keeps the scan', () {
    final raw = _jpegWithApp1();
    expect(jpegHasApp1(raw), isTrue);
    expect(String.fromCharCodes(raw), contains('Exif'));
    expect(String.fromCharCodes(raw), contains('GPS'));

    final cleaned = stripJpegExif(raw);
    expect(cleaned[0], 0xFF);
    expect(cleaned[1], 0xD8);
    expect(jpegHasApp1(cleaned), isFalse);
    expect(String.fromCharCodes(cleaned), isNot(contains('Exif')));
    expect(String.fromCharCodes(cleaned), isNot(contains('GPS')));
    expect(cleaned.last, 0xD9);
  });

  test('JPEG without APP1 is unchanged', () {
    final raw = <int>[
      0xFF, 0xD8,
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x7F,
      0xFF, 0xD9,
    ];
    expect(stripJpegExif(raw), raw);
  });

  test('non-JPEG bytes pass through', () {
    final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];
    expect(stripJpegExif(png), png);
  });

  test('signed URL TTL is short-lived (5 minutes)', () {
    expect(kChorePhotoSignedUrlTtlSeconds, 300);
  });
}
