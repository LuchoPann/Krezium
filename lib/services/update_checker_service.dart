import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Único punto de la app que habla con internet — consulta los GitHub
/// Releases del repo para saber si hay una versión más nueva que la
/// instalada, y descarga el APK si el usuario lo pide. Nunca se usa para
/// nada más: el resto de Krezium sigue siendo 100% local.
class UpdateInfo {
  final String version;
  final String apkUrl;
  final String notas;

  const UpdateInfo({required this.version, required this.apkUrl, required this.notas});
}

const _repoApiUrl = 'https://api.github.com/repos/LuchoPann/Krezium/releases/latest';

/// Compara dos versiones "X.Y.Z" (ignora cualquier sufijo tipo "+build" o
/// "-beta.1" — solo le importa el núcleo semver). true si [remoto] es
/// estrictamente más nuevo que [local].
bool esVersionMasNueva(String local, String remoto) {
  List<int> partes(String v) => v
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = partes(local);
  final b = partes(remoto);
  for (var i = 0; i < 3; i++) {
    final va = i < a.length ? a[i] : 0;
    final vb = i < b.length ? b[i] : 0;
    if (vb != va) return vb > va;
  }
  return false;
}

/// Revisa el último release publicado — devuelve null tanto si no hay
/// versión más nueva como si falla la consulta (sin internet, GitHub caído,
/// etc.): nunca debe romper el arranque de una app que es offline por
/// diseño salvo por esta única llamada opcional.
Future<UpdateInfo?> checkForUpdate() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final resp = await http
        .get(Uri.parse(_repoApiUrl), headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final remoto = tag.startsWith('v') ? tag.substring(1) : tag;
    if (remoto.isEmpty || !esVersionMasNueva(info.version, remoto)) return null;

    final assets = (json['assets'] as List?) ?? const [];
    final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          orElse: () => const {},
        );
    final apkUrl = apkAsset['browser_download_url'] as String?;
    if (apkUrl == null) return null;

    return UpdateInfo(
      version: remoto,
      apkUrl: apkUrl,
      notas: (json['body'] as String? ?? '').trim(),
    );
  } catch (_) {
    return null;
  }
}

/// Descarga [url] a un archivo temporal, reportando progreso 0.0–1.0 por
/// [onProgress] (null si el tamaño total no viene en la respuesta — se
/// sigue descargando igual, solo sin barra de progreso determinada).
/// Devuelve la ruta del archivo descargado.
Future<String> descargarApk(String url, {void Function(double?)? onProgress}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/krezium-update.apk');
  if (await file.exists()) await file.delete();

  final request = http.Request('GET', Uri.parse(url));
  final response = await http.Client().send(request);
  final total = response.contentLength;
  var recibido = 0;

  final sink = file.openWrite();
  await response.stream.listen((chunk) {
    recibido += chunk.length;
    sink.add(chunk);
    onProgress?.call(total != null && total > 0 ? recibido / total : null);
  }).asFuture<void>();
  await sink.close();

  return file.path;
}
