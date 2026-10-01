import 'dart:typed_data';

/// Signed URL lifetime for chore photos (parent Approvals / Photo Assist).
const int kChorePhotoSignedUrlTtlSeconds = 300;

/// Strip JPEG APP1 (EXIF, including GPS). Non-JPEG bytes pass through.
///
/// ponytail: no extra image package. HEIC/PNG/WebP are unchanged; those
/// formats are not rewritten here. Camera JPEG from image_picker is the
/// upload path we actually use.
Uint8List stripJpegExif(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return Uint8List.fromList(bytes);
  }
  final out = <int>[0xFF, 0xD8];
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      out.addAll(bytes.sublist(i));
      return Uint8List.fromList(out);
    }
    final marker = bytes[i + 1];
    if (marker == 0xDA) {
      // Start of scan: remainder is compressed data.
      out.addAll(bytes.sublist(i));
      return Uint8List.fromList(out);
    }
    if (marker == 0xD9) {
      out.addAll([0xFF, 0xD9]);
      return Uint8List.fromList(out);
    }
    if (marker == 0x00 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      out.add(0xFF);
      out.add(marker);
      i += 2;
      continue;
    }
    if (i + 3 >= bytes.length) {
      out.addAll(bytes.sublist(i));
      return Uint8List.fromList(out);
    }
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    final segEnd = i + 2 + len;
    if (len < 2 || segEnd > bytes.length) {
      out.addAll(bytes.sublist(i));
      return Uint8List.fromList(out);
    }
    // APP1 = EXIF / XMP. GPS lives here on phone JPEGs.
    if (marker != 0xE1) {
      out.addAll(bytes.sublist(i, segEnd));
    }
    i = segEnd;
  }
  return Uint8List.fromList(out);
}

bool jpegHasApp1(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
  var i = 2;
  while (i + 3 < bytes.length) {
    if (bytes[i] != 0xFF) return false;
    final marker = bytes[i + 1];
    if (marker == 0xDA || marker == 0xD9) return false;
    if (marker == 0x00 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    final segEnd = i + 2 + len;
    if (len < 2 || segEnd > bytes.length) return false;
    if (marker == 0xE1) return true;
    i = segEnd;
  }
  return false;
}
