import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/finance_icon_map.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:uuid/uuid.dart';

// Un solo tono por tipo (verde ingreso / rojo gasto) en vez de la gama de
// colores propia de cada categoría — a pedido explícito, para que el
// usuario lea el tipo de un vistazo sin que cada categoría compita con su
// propio color.
Color _colorPorTipo(String tipo) => switch (tipo) {
      'ingreso' => const Color(0xFF22C55E),
      'gasto' => const Color(0xFFEF4444),
      _ => const Color(0xFF3B82F6),
    };

/// Muestra el selector de categorías en un bottom sheet.
/// [tipoInicial] puede ser 'gasto' o 'ingreso'.
/// Retorna la [CatalogoCategoria] seleccionada o null si se descartó.
Future<CatalogoCategoria?> showCategoriaSelectorSheet(
  BuildContext context,
  String tipoInicial,
) {
  return showModalBottomSheet<CatalogoCategoria>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoriaSelectorSheet(tipoInicial: tipoInicial),
  );
}

/// Abre solo el sheet de creación de categoría (sin el selector completo)
/// — usado por el paso de categoría embebido en nueva_transaccion_sheet.dart
/// para no apilar un segundo sheet sobre el flujo de "nuevo registro".
Future<CatalogoCategoria?> showNuevaCategoriaSheet(
  BuildContext context,
  String tipoInicial, {
  String? parentIdInicial,
}) {
  return showModalBottomSheet<CatalogoCategoria?>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NuevaCategoriaSheet(tipoInicial: tipoInicial, parentIdInicial: parentIdInicial),
  );
}

class _CategoriaSelectorSheet extends ConsumerStatefulWidget {
  final String tipoInicial;

  const _CategoriaSelectorSheet({required this.tipoInicial});

  @override
  ConsumerState<_CategoriaSelectorSheet> createState() =>
      _CategoriaSelectorSheetState();
}

class _CategoriaSelectorSheetState
    extends ConsumerState<_CategoriaSelectorSheet> {
  late String _tipo;
  final Set<String> _expandidos = {};

  Future<void> _crearCategoria() async {
    final result = await showModalBottomSheet<CatalogoCategoria?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NuevaCategoriaSheet(tipoInicial: _tipo),
    );
    if (result != null && mounted) {
      ref.invalidate(allFinanceCategoriesProvider);
      Navigator.of(context).pop(result);
    }
  }

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoInicial;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final asyncCats = ref.watch(allFinanceCategoriesProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.bgCard,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // AppBar row
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.card, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Categoría',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _crearCategoria,
                    ),
                  ],
                ),
              ),
              // Segmented toggle
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.card, vertical: 8),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'gasto',
                      label: Text('Gasto'),
                      icon: Icon(Icons.arrow_upward, size: 16),
                    ),
                    ButtonSegment(
                      value: 'ingreso',
                      label: Text('Ingreso'),
                      icon: Icon(Icons.arrow_downward, size: 16),
                    ),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _tipo = selection.first;
                      _expandidos.clear();
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return _tipo == 'ingreso'
                            ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                            : const Color(0xFFEF4444).withValues(alpha: 0.2);
                      }
                      return null;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return _tipo == 'ingreso'
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444);
                      }
                      return null;
                    }),
                  ),
                ),
              ),
              const Divider(height: 1),
              // List
              Expanded(
                child: asyncCats.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (rawList) {
                    final all = rawList;
                    final padres = all.where((c) =>
                        c.parentId == null &&
                        (c.tipo == _tipo || c.tipo == 'ambos')).toList();

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: padres.length,
                      itemBuilder: (context, index) {
                        final padre = padres[index];
                        final hijos = all
                            .where((c) => c.parentId == padre.id)
                            .toList();
                        final isExpanded = _expandidos.contains(padre.id);

                        return Column(
                          children: [
                            // Fila padre
                            ListTile(
                              leading: Icon(
                                iconFromKey(padre.iconoKey),
                                size: AppIconSize.medium,
                                color: _colorPorTipo(padre.tipo),
                              ),
                              title: Text(
                                padre.nombre,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: hijos.isEmpty
                                  ? null
                                  : Icon(
                                      isExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandidos.remove(padre.id);
                                  } else {
                                    _expandidos.add(padre.id);
                                  }
                                });
                              },
                            ),
                            // Hijos expandibles
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: isExpanded
                                  ? Column(
                                      children: hijos.map((hijo) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(left: 32),
                                          child: ListTile(
                                            leading: Icon(
                                              iconFromKey(hijo.iconoKey),
                                              size: AppIconSize.medium,
                                              color: _colorPorTipo(hijo.tipo),
                                            ),
                                            title: Text(hijo.nombre),
                                            onTap: () {
                                              HapticFeedback.lightImpact();
                                              Navigator.of(context)
                                                  .pop(hijo);
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      ),
    );
  }
}

// ─── Sheet crear categoría personalizada ──────────────────────────────────────
// Sin selector de color: el color ya no es propio de cada categoría (se
// pintó con un solo tono por tipo en toda la app) — acá solo se eligen
// nombre, categoría padre (para que pueda ser una subcategoría real) e
// ícono, desde el mismo catálogo de íconos que ya usa el resto del catálogo.
class _NuevaCategoriaSheet extends ConsumerStatefulWidget {
  final String tipoInicial;
  final String? parentIdInicial;
  const _NuevaCategoriaSheet({required this.tipoInicial, this.parentIdInicial});

  @override
  ConsumerState<_NuevaCategoriaSheet> createState() => _NuevaCategoriaSheetState();
}

class _NuevaCategoriaSheetState extends ConsumerState<_NuevaCategoriaSheet> {
  final _nombreCtrl = TextEditingController();
  late String _tipo;
  String? _parentId;
  String _iconoKey = 'tag';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoInicial;
    _parentId = widget.parentIdInicial;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirIcono() async {
    final key = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IconoPickerSheet(iconoActual: _iconoKey),
    );
    if (key != null) setState(() => _iconoKey = key);
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _guardando = true);

    final db = ref.read(databaseProvider);
    final id = const Uuid().v4();
    final colorHex = _colorPorTipo(_tipo).toARGB32().toRadixString(16).substring(2).toUpperCase();
    await db.upsertFinanceCategory(FinanceCategoriesCompanion(
      id: Value(id),
      nombre: Value(nombre),
      icono: Value(_iconoKey),
      color: Value('#$colorHex'),
      tipo: Value(_tipo),
      archivada: const Value(false),
      parentId: Value(_parentId),
    ));

    // Retornar como CatalogoCategoria sintético para selección inmediata
    final cat = CatalogoCategoria(
      id: id,
      nombre: nombre,
      icono: iconFromKey(_iconoKey),
      color: _colorPorTipo(_tipo),
      tipo: _tipo,
      iconoKey: _iconoKey,
      parentId: _parentId,
    );
    if (mounted) Navigator.of(context).pop(cat);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tc = theme.extension<AppThemeColors>()!;
    final padresDisponibles = catalogoCategoriaPadres
        .where((p) => p.tipo == _tipo || p.tipo == 'ambos' || _tipo == 'ambos')
        .toList();
    final color = _colorPorTipo(_tipo);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: tc.borderCard, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Nueva categoría', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'gasto', label: Text('Gasto'), icon: Icon(Icons.arrow_upward, size: 14)),
              ButtonSegment(value: 'ingreso', label: Text('Ingreso'), icon: Icon(Icons.arrow_downward, size: 14)),
              ButtonSegment(value: 'ambos', label: Text('Ambos'), icon: Icon(Icons.swap_vert, size: 14)),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() {
              final nuevoTipo = s.first;
              // La categoría padre depende del tipo — si deja de ser
              // compatible, se limpia para no guardar una combinación rara.
              // OJO: hay que recalcular la lista de padres compatibles con
              // `nuevoTipo`, no reusar `padresDisponibles` (ese es el valor
              // de ANTES de este cambio, capturado en el build anterior) —
              // usarlo acá dejaba pasar un `_parentId` que ya no encajaba
              // con el nuevo tipo, y el DropdownButtonFormField explotaba
              // en el siguiente build al no encontrar ese valor en `items`.
              final padresCompatibles = catalogoCategoriaPadres.where(
                  (p) => p.tipo == nuevoTipo || p.tipo == 'ambos' || nuevoTipo == 'ambos');
              _tipo = nuevoTipo;
              if (_parentId != null && !padresCompatibles.any((p) => p.id == _parentId)) {
                _parentId = null;
              }
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nombreCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej: Mascotas',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _parentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoría padre (opcional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin categoría padre')),
              for (final p in padresDisponibles)
                DropdownMenuItem(value: p.id, child: Text(p.nombre)),
            ],
            onChanged: (v) => setState(() => _parentId = v),
          ),
          const SizedBox(height: 16),
          Text('Ícono', style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _elegirIcono,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tc.borderCard),
              ),
              child: Icon(iconFromKey(_iconoKey), color: color, size: AppIconSize.large),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : const Text('Crear categoría'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Selector de ícono ─────────────────────────────────────────────────────────
// Grilla buscable de todo `financeIconMap` — catálogo compartido que ya usan
// las categorías del sistema, en vez de dejar la categoría nueva siempre con
// el mismo ícono genérico.
class _IconoPickerSheet extends StatefulWidget {
  final String iconoActual;
  const _IconoPickerSheet({required this.iconoActual});

  @override
  State<_IconoPickerSheet> createState() => _IconoPickerSheetState();
}

class _IconoPickerSheetState extends State<_IconoPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final entradas = financeIconMap.entries
        .where((e) => e.key.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: tc.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: tc.borderCard, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: AppIconSize.small),
                    hintText: 'Buscar ícono…',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: entradas.length,
                  itemBuilder: (context, i) {
                    final entry = entradas[i];
                    final selected = entry.key == widget.iconoActual;
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(entry.key),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected ? tc.textTertiary.withValues(alpha: 0.2) : tc.textTertiary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: selected ? Border.all(color: tc.textPrimary, width: 2) : null,
                        ),
                        child: Icon(entry.value, color: tc.textPrimary, size: AppIconSize.medium),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
