import 'dart:io';
import 'dart:typed_data';

/// Length of the silent file that pauses are cut from.
const silenceLength = Duration(seconds: 60);

const _sampleRate = 44100;

/// Returns a WAV file containing [silenceLength] of silence, creating it the
/// first time. Pauses are played as clips of this file: phones only keep an
/// app running in the background while it is actually playing audio, so
/// waiting silently with a timer would get the session cut off.
Future<File> silenceFile(Directory dir) async {
  final file = File('${dir.path}${Platform.pathSeparator}silence_${silenceLength.inSeconds}s.wav');
  final dataBytes = _sampleRate * 2 * silenceLength.inSeconds;
  if (await file.exists() && await file.length() == 44 + dataBytes) return file;

  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // "RIFF"
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x57415645) // "WAVE"
    ..setUint32(12, 0x666d7420) // "fmt "
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, _sampleRate, Endian.little)
    ..setUint32(28, _sampleRate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per frame
    ..setUint16(34, 16, Endian.little) // bits per sample
    ..setUint32(36, 0x64617461) // "data"
    ..setUint32(40, dataBytes, Endian.little);

  await dir.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  final sink = tmp.openWrite()..add(header.buffer.asUint8List());
  final zeros = Uint8List(64 * 1024);
  for (var written = 0; written < dataBytes; written += zeros.length) {
    final n = dataBytes - written < zeros.length ? dataBytes - written : zeros.length;
    sink.add(n == zeros.length ? zeros : Uint8List(n));
  }
  await sink.close();
  return tmp.rename(file.path);
}
