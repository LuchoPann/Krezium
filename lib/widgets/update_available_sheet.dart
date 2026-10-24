import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';

/// Flag en memoria: evita mostrar dos veces el mismo chequeo si la pantalla
/// se reconstruye antes de que termine (mismo patrón que whats_new_sheet).
bool _updateSheetShowing = false;

/// Revisa si hay una versión nueva en GitHub Releases y, si la hay, muestra
/// el desplegable para descargarla. [avisarSiNoHay] muestra un SnackBar
/// "estás al día" cuando no hay actualización — se activa solo en la
/// revisión manual desde Cuenta; el chequeo silencioso de arranque no debe
/// interrumpir con un aviso de que no hay nada nuevo.
Future<void> checkAndShowUpdateSheet(BuildContext context, {bool avisarSiNoHay = false}) async {
  if (_updateSheetShowing) return;
  final update = await checkForUpdate();
  if (!context.mounted) return;
  if (update == null) {
    if (avisarSiNoHay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya tienes la última versión.')),
      );
    }
    return;
  }
  _updateSheetShowing = true;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _UpdateSheetContent(update: update),
  );
  _updateSheetShowing = false;
}

class _UpdateSheetContent extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateSheetContent({required this.update});

  @override
  State<_UpdateSheetContent> createState() => _UpdateSheetContentState();
}

enum _Estado { idle, descargando, listo, error }

class _UpdateSheetContentState extends State<_UpdateSheetContent> {
  _Estado _estado = _Estado.idle;
  double? _progreso;
  String? _rutaApk;

  Future<void> _descargar() async {
    setState(() {
      _estado = _Estado.descargando;
      _progreso = 0;
    });
    try {
      final ruta = await descargarApk(
        widget.update.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progreso = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _estado = _Estado.listo;
        _rutaApk = ruta;
      });
    } catch (_) {
      if (mounted) setState(() => _estado = _Estado.error);
    }
  }

  Future<void> _instalar() async {
    final ruta = _rutaApk;
    if (ruta == null) return;
    // Android muestra su propia pantalla de confirmación de instalación —
    // esto nunca se salta, solo la abre. Si el usuario no había permitido
    // "instalar apps desconocidas" para Krezium, Android lo pide acá mismo.
    await OpenFilex.open(ruta);
  }

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nueva versión disponible: v${widget.update.version}',
                    style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
                  ),
                ),
              ],
            ),
            if (widget.update.notas.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.tile),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                child: SingleChildScrollView(
                  child: Text(
                    widget.update.notas,
                    style: TextStyle(fontSize: AppTextSize.body, height: 1.5, color: tc.textSecondary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.section),
            if (_estado == _Estado.descargando) ...[
              LinearProgressIndicator(value: _progreso),
              const SizedBox(height: 8),
              Text(
                _progreso != null ? 'Descargando… ${(_progreso! * 100).round()}%' : 'Descargando…',
                style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary),
              ),
              const SizedBox(height: AppSpacing.tile),
            ],
            if (_estado == _Estado.error) ...[
              Text(
                'No se pudo descargar — revisa tu conexión e intenta de nuevo.',
                style: const TextStyle(color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: AppSpacing.tile),
            ],
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Más tarde'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _estado == _Estado.descargando
                        ? null
                        : (_estado == _Estado.listo ? _instalar : _descargar),
                    child: Text(_estado == _Estado.listo ? 'Instalar' : 'Descargar actualización'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
