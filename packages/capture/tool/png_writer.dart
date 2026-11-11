// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// #31 — minimal PNG writer for the benchmark corpus.
//
// The corpus must render byte-identically on any machine running the tool
// (mini-PC, laptop, CI), so there is no image package and no platform font:
// we emit 8-bit greyscale PNGs straight from a pixel buffer with dart:io's
// zlib. Grayscale is what an OCR pipeline receives from a screenshot of a
// black-and-white receipt anyway; dark mode is just an inverted buffer.
import 'dart:io';
import 'dart:typed_data';

/// Row-major [width]x[height] greyscale buffer, 0 = black, 255 = white.
class Pixmap {
  Pixmap(this.width, this.height)
      : pixels = Uint8List(width * height * 3); // RGB, gray triplicated

  final int width;
  final int height;
  final Uint8List pixels;

  void fillGray(int gray) => pixels.fillRange(0, pixels.length, gray);

  void setPixel(int x, int y, int gray) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = (y * width + x) * 3;
    pixels[i] = gray;
    pixels[i + 1] = gray;
    pixels[i + 2] = gray;
  }

  void fillRect(int x0, int y0, int w, int h, int gray) {
    for (var y = y0; y < y0 + h; y++) {
      for (var x = x0; x < x0 + w; x++) {
        setPixel(x, y, gray);
      }
    }
  }

  /// In-place photometric inversion (light receipts -> dark-mode ones).
  void invert() {
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] = 255 - pixels[i];
    }
  }
}

/// Encode [pixmap] as an RGB8 PNG.
Uint8List encodePng(Pixmap pixmap) {
  final raw = BytesBuilder();
  final stride = pixmap.width * 3;
  for (var y = 0; y < pixmap.height; y++) {
    raw.addByte(0); // filter: None
    raw.add(pixmap.pixels.sublist(y * stride, (y + 1) * stride));
  }
  final idat = ZLibEncoder(level: 6).convert(raw.takeBytes());

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final body = BytesBuilder()
      ..add(type.codeUnits)
      ..add(data);
    out.add(body.takeBytes());
    final crc = ByteData(4)..setUint32(0, _crc32(type.codeUnits + data));
    out.add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, pixmap.width)
    ..setUint32(4, pixmap.height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: truecolour RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.takeBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
