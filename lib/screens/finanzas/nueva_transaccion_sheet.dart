import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:krezium/data/db/database.dart';
import 'package:krezium/data/finance_categories_catalog.dart';
import 'package:krezium/data/finance_icon_map.dart';
import 'package:krezium/data/models/finance_models.dart';
import 'package:krezium/domain/finance_ledger.dart';
import 'package:krezium/providers/database_provider.dart';
import 'package:krezium/providers/finance_provider.dart';
import 'package:krezium/screens/finanzas/categoria_selector_sheet.dart';
import 'package:krezium/theme/app_theme.dart';
import 'package:krezium/widgets/app_pill_selector.dart';
import 'package:krezium/widgets/krezium_section_card.dart';
import 'package:uuid/uuid.dart';

// ─── Color tokens por tipo ────────────────────────────────────────────────────
Color _colorFromHex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

const _colorIngreso = Color(0xFF22C55E);
const _colorGasto = Color(0xFFEF4444);
const _colorTransfer = Color(0xFF3B82F6);

Color _tipoColor(String tipo) => switch (tipo) {
      'ingreso' => _colorIngreso,
      'gasto' => _colorGasto,
      _ => _colorTransfer,
    };

// ─── Public API ───────────────────────────────────────────────────────────────
Future<void> showNuevaTransaccionSheet(
  BuildContext context, {
  String? libroId,
  CatalogoCategoria? categoriaInicial,
  FinanceTemplate? template,
  FinanceTransaction? editar,
  String? tipoInicial,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NuevaTransaccionSheet(
      libroIdInicial: libroId,
      categoriaInicial: categoriaInicial,
      template: template,
      editar: editar,
      tipoInicial: tipoInicial,
    ),
  );
}

// ─── Widget principal ─────────────────────────────────────────────────────────
class _NuevaTransaccionSheet extends ConsumerStatefulWidget {
  final String? libroIdInicial;
  final CatalogoCategoria? categoriaInicial;
  final FinanceTemplate? template;
  final FinanceTransaction? editar;
  final String? tipoInicial;

  const _NuevaTransaccionSheet({
    this.libroIdInicial,
    this.categoriaInicial,
    this.template,
    this.editar,
    this.tipoInicial,
  });

  @override
  ConsumerState<_NuevaTransaccionSheet> createState() =>
      _NuevaTransaccionSheetState();
}

class _NuevaTransaccionSheetState
    extends ConsumerState<_NuevaTransaccionSheet> {
  // ── estado ────────────────────────────────────────────────────────────────
  late int _paso;
  String _tipo = 'gasto';
  String? _libroId;
  String? _libroDestinoId; // solo transferencia
  CatalogoCategoria? _categoriaSeleccionada;
  late DateTime _fecha;
  late TimeOfDay _hora;
  final _montoCtrl = TextEditingController();
  final _ordenanteCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _montoFocus = FocusNode();
  bool _guardando = false;
  bool _montoValido = false;

  @override
  void initState() {
    super.initState();
    _montoCtrl.addListener(_onMontoChanged);
    _fecha = DateTime.now();
    _hora = TimeOfDay.now();
    _libroId = widget.libroIdInicial;
    // El selector de registro ahora vive dentro del propio formulario (paso
    // 2) cuando hace falta elegirlo — ya no existe un paso previo separado
    // solo para eso. Si venía preseleccionado (caso normal, desde el FAB de
    // un registro específico), el formulario ni siquiera lo muestra.
    _paso = 2;
    _categoriaSeleccionada = widget.categoriaInicial;
    if (widget.tipoInicial != null) _tipo = widget.tipoInicial!;

    final t = widget.template;
    if (t != null) {
      _tipo = t.tipo;
      _libroId = t.libroId ?? widget.libroIdInicial;
      _ordenanteCtrl.text = t.personaSitio ?? '';
      _notaCtrl.text = t.nota ?? '';
      if (t.monto != null) {
        _montoCtrl.text = agruparMiles(t.monto!.round());
      }
      // Buscar categoría del template en el catálogo
      try {
        _categoriaSeleccionada = catalogoFinanzas.firstWhere(
          (c) => c.id == t.categoryId,
        );
      } catch (_) {}
      // Ir directo al paso 2 si hay template
      _paso = 2;
    }

    final e = widget.editar;
    if (e != null) {
      _tipo = e.tipo;
      _libroId = e.accountId;
      _libroDestinoId = e.transferToAccountId;
      _ordenanteCtrl.text = e.personaSitio ?? '';
      _notaCtrl.text = e.nota;
      _montoCtrl.text = agruparMiles(e.monto.round());
      final fParts = e.fecha.split('-');
      _fecha = DateTime(int.parse(fParts[0]), int.parse(fParts[1]), int.parse(fParts[2]));
      final hParts = (e.hora ?? '00:00').split(':');
      _hora = TimeOfDay(hour: int.parse(hParts[0]), minute: int.parse(hParts[1]));
      try {
        _categoriaSeleccionada = catalogoFinanzas.firstWhere((c) => c.id == e.categoryId);
      } catch (_) {}
      _paso = 2;
    }
  }

  void _onMontoChanged() {
    final v = double.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final valid = v != null && v > 0;
    if (valid != _montoValido) setState(() => _montoValido = valid);
  }

  @override
  void dispose() {
    _montoCtrl.removeListener(_onMontoChanged);
    _montoCtrl.dispose();
    _ordenanteCtrl.dispose();
    _notaCtrl.dispose();
    _montoFocus.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  String _formatFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatHora(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _pickHora() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _hora,
    );
    if (picked != null) setState(() => _hora = picked);
  }

  // La categoría se elige como un paso más de este mismo sheet (_paso = 3)
  // en vez de abrir un segundo sheet encima — evita el sheet-sobre-sheet.
  void _seleccionarCategoria() => setState(() => _paso = 3);

  // Selección directa desde los chips rápidos del Paso 2 (sin pasar por el
  // paso de categoría completo).
  void _elegirCategoriaChip(CatalogoCategoria cat) =>
      setState(() => _categoriaSeleccionada = cat);

  Future<void> _guardar(List<FinanceAccount> libros) async {
    if (_guardando) return;
    final monto = double.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (monto == null || monto <= 0) return;
    if (_libroId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige un registro')),
      );
      return;
    }
    if (_tipo == 'transferencia' &&
        !esTransferenciaValida(origenId: _libroId, destinoId: _libroDestinoId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige un registro destino distinto al de origen')),
      );
      return;
    }
    if (_categoriaSeleccionada == null && _tipo != 'transferencia') return;

    setState(() => _guardando = true);
    try {
      final db = ref.read(databaseProvider);
      final id = widget.editar?.id ?? const Uuid().v4();
      final fechaStr =
          '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}';
      final horaStr = _formatHora(_hora);
      final ordenante = _ordenanteCtrl.text.trim();

      // Upsert lugar si hay texto
      if (ordenante.isNotEmpty) {
        // Buscar si ya existe para incrementar usados
        final places = await db.getFinancePlaces();
        final existing = places.where((p) => p.nombre.toLowerCase() == ordenante.toLowerCase()).firstOrNull;
        if (existing != null) {
          await db.upsertFinancePlace(FinancePlacesCompanion(
            id: Value(existing.id),
            nombre: Value(existing.nombre),
            usados: Value(existing.usados + 1),
          ));
        } else {
          await db.upsertFinancePlace(FinancePlacesCompanion(
            id: Value(const Uuid().v4()),
            nombre: Value(ordenante),
            usados: const Value(1),
          ));
        }
      }

      // Guardar transacción
      await db.upsertFinanceTransaction(FinanceTransactionsCompanion(
        id: Value(id),
        accountId: Value(_libroId!),
        categoryId: Value(_categoriaSeleccionada?.id ?? 'transferencia'),
        tipo: Value(_tipo),
        monto: Value(monto),
        fecha: Value(fechaStr),
        nota: Value(_notaCtrl.text.trim()),
        hora: Value(horaStr),
        personaSitio: Value(ordenante.isEmpty ? null : ordenante),
        transferToAccountId: Value(_tipo == 'transferencia' ? _libroDestinoId : null),
        // Si la transacción pasa a ser una transferencia válida (o deja de
        // serlo) tras una edición, cualquier aviso de "transferencia dudosa"
        // que tuviera de antes queda obsoleto — insertOnConflictUpdate deja
        // intactos los campos no mencionados en el companion, así que hay
        // que limpiarlo explícitamente o el badge histórico queda pegado
        // para siempre aunque el usuario ya corrigió el dato.
        revisionNota: const Value(null),
      ));

      // finanzasLibroTxProvider/financeAccountBalanceProvider son
      // FutureProvider: no son reactivos a escrituras en la DB, solo
      // vuelven a correr si algo que watchean cambia o si se invalidan a
      // mano — sin esto, la lista y los totales/saldo quedaban
      // desactualizados hasta un pull-to-refresh manual o reinicio.
      final cuentasTocadas = <String>{
        _libroId!,
        if (_tipo == 'transferencia' && _libroDestinoId != null) _libroDestinoId!,
        // Al editar, si se cambió de libro u origen/destino, las cuentas
        // viejas también quedan con listas/saldos desactualizados.
        if (widget.editar != null) widget.editar!.accountId,
        if (widget.editar?.transferToAccountId != null)
          widget.editar!.transferToAccountId!,
      };
      for (final cuentaId in cuentasTocadas) {
        ref.invalidate(finanzasLibroTxProvider(cuentaId));
        ref.invalidate(financeAccountBalanceProvider(cuentaId));
      }
      if (ordenante.isNotEmpty) ref.invalidate(financePlacesProvider);

      await HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final librosAsync = ref.watch(financeAccountsProvider);
    final libros = librosAsync.valueOrNull?.map(FinanceAccount.fromRow).toList() ?? [];

    // Padding(bottom: viewInsets): un DraggableScrollableSheet no se
    // reacomoda solo con el teclado (a diferencia de un Scaffold con
    // resizeToAvoidBottomInset) — sin esto, el teclado tapaba los campos
    // de más abajo (categoría, notas, guardar).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Material(
        // Material (no un Container con color propio): los ListTile de
        // categoría (Paso 3) pintan su fondo/ripple en el Material más
        // cercano — con un Container de por medio, Flutter los dejaba sin
        // efecto visual (warning real visto en vivo, "ListTile background
        // color or ink splashes may be invisible").
        // scaffoldBackgroundColor (no tc.bgCard): mismo fondo de sheet que
        // usa Créditos (add_credit_sheet.dart, edit_credit_sheet.dart,
        // card_movement_sheet.dart) — bgCard es un tono más claro pensado
        // para tarjetas dentro de una pantalla, no para el fondo del sheet
        // completo; usarlo aquí hacía que todo Finanzas se viera más claro
        // que Créditos, reportado explícitamente por el usuario.
        color: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tc.borderCard,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) {
                  final offset = child.key == const ValueKey(1)
                      ? const Offset(-1, 0)
                      : const Offset(1, 0);
                  return SlideTransition(
                    position: Tween(begin: offset, end: Offset.zero)
                        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                    child: child,
                  );
                },
                child: switch (_paso) {
                  3 => _Paso3Categoria(
                      key: const ValueKey(3),
                      tipo: _tipo == 'transferencia' ? 'gasto' : _tipo,
                      scrollCtrl: scrollCtrl,
                      onVolver: () => setState(() => _paso = 2),
                      onSeleccionar: (cat) => setState(() {
                        _categoriaSeleccionada = cat;
                        _paso = 2;
                      }),
                    ),
                  _ => _Paso2(
                        key: const ValueKey(2),
                        tipo: _tipo,
                        isEditing: widget.editar != null,
                        libros: libros,
                        libroId: _libroId,
                        libroDestinoId: _libroDestinoId,
                        onLibroChanged: (v) => setState(() {
                          _libroId = v;
                          if (v != null && v == _libroDestinoId) {
                            _libroDestinoId = null;
                          }
                        }),
                        onLibroDestinoChanged: (v) =>
                            setState(() => _libroDestinoId = v),
                        // Cambiar entre ingreso/gasto desde el paso 2 — antes
                        // solo era posible en el paso 1, que se salta cuando
                        // el sheet se abre con un libro ya preseleccionado
                        // (el caso normal, desde el FAB de la pantalla del
                        // libro), dejando el tipo fijo en 'gasto' para
                        // siempre. La categoría se limpia al cambiar porque
                        // el catálogo de categorías depende del tipo.
                        onTipoChanged: (v) => setState(() {
                          _tipo = v;
                          _categoriaSeleccionada = null;
                        }),
                        categoriaSeleccionada: _categoriaSeleccionada,
                        fecha: _fecha,
                        hora: _hora,
                        montoCtrl: _montoCtrl,
                        ordenanteCtrl: _ordenanteCtrl,
                        notaCtrl: _notaCtrl,
                        montoFocus: _montoFocus,
                        guardando: _guardando,
                        montoValido: _montoValido,
                        scrollCtrl: scrollCtrl,
                        onSeleccionarCategoria: _seleccionarCategoria,
                        onCategoriaChip: _elegirCategoriaChip,
                        onPickFecha: _pickFecha,
                        onPickHora: _pickHora,
                        onVolver: () => Navigator.of(context).pop(),
                        onGuardar: () => _guardar(libros),
                        formatFecha: _formatFecha,
                        formatHora: _formatHora,
                      ),
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

// ─── Selector de libro ────────────────────────────────────────────────────────
class _LibroSelector extends StatelessWidget {
  final String label;
  final List<FinanceAccount> libros;
  final String? libroId;
  final ValueChanged<String?> onChanged;
  final AppThemeColors tc;
  final String? excludeId;

  const _LibroSelector({
    required this.label,
    required this.libros,
    required this.libroId,
    required this.onChanged,
    required this.tc,
    this.excludeId,
  });

  @override
  Widget build(BuildContext context) {
    final available = excludeId != null
        ? libros.where((l) => l.id != excludeId).toList()
        : libros;

    if (available.isEmpty) {
      return Text(
        'No hay registros disponibles',
        style: TextStyle(color: tc.textSecondary, fontSize: AppTextSize.body),
      );
    }

    final seleccionado = available.where((l) => l.id == libroId).firstOrNull;

    // Fila táctil que abre un sheet de selección, en vez de un
    // DropdownButtonFormField nativo — más rápido de escanear con pocas
    // opciones y más "de app móvil" que un <select> de formulario web
    // (boceto aprobado en el artifact de diseño).
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      onTap: () async {
        final picked = await _elegirRegistro(context, available, tc, seleccionado?.id);
        if (picked != null) onChanged(picked);
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: AppTextSize.caption, color: tc.textTertiary)),
                const SizedBox(height: 2),
                Text(
                  seleccionado?.nombre ?? 'Elegir registro',
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w700,
                    color: seleccionado != null ? tc.textPrimary : tc.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: AppIconSize.small, color: tc.textTertiary),
        ],
      ),
    );
  }

  Future<String?> _elegirRegistro(
    BuildContext context,
    List<FinanceAccount> opciones,
    AppThemeColors tc,
    String? actual,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: tc.borderCard, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: AppTextSize.heading, fontWeight: FontWeight.w700, color: tc.textPrimary),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final libro in opciones)
                      ListTile(
                        leading: Icon(iconFromKey(libro.icono), color: _colorFromHex(libro.color)),
                        title: Text(libro.nombre),
                        trailing: libro.id == actual
                            ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                            : null,
                        onTap: () => Navigator.of(ctx).pop(libro.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Paso 2: detalle ──────────────────────────────────────────────────────────
class _Paso2 extends ConsumerWidget {
  final String tipo;
  final bool isEditing;
  final List<FinanceAccount> libros;
  final String? libroId;
  final String? libroDestinoId;
  final ValueChanged<String?> onLibroChanged;
  final ValueChanged<String?> onLibroDestinoChanged;
  final ValueChanged<String> onTipoChanged;
  final CatalogoCategoria? categoriaSeleccionada;
  final DateTime fecha;
  final TimeOfDay hora;
  final TextEditingController montoCtrl;
  final TextEditingController ordenanteCtrl;
  final TextEditingController notaCtrl;
  final FocusNode montoFocus;
  final bool guardando;
  final bool montoValido;
  final ScrollController scrollCtrl;
  final VoidCallback onSeleccionarCategoria;
  final ValueChanged<CatalogoCategoria> onCategoriaChip;
  final Future<void> Function() onPickFecha;
  final Future<void> Function() onPickHora;
  final VoidCallback onVolver;
  final VoidCallback onGuardar;
  final String Function(DateTime) formatFecha;
  final String Function(TimeOfDay) formatHora;

  const _Paso2({
    super.key,
    required this.tipo,
    required this.isEditing,
    required this.libros,
    required this.libroId,
    required this.libroDestinoId,
    required this.onLibroChanged,
    required this.onLibroDestinoChanged,
    required this.onTipoChanged,
    required this.categoriaSeleccionada,
    required this.fecha,
    required this.hora,
    required this.montoCtrl,
    required this.ordenanteCtrl,
    required this.notaCtrl,
    required this.montoFocus,
    required this.guardando,
    required this.montoValido,
    required this.scrollCtrl,
    required this.onSeleccionarCategoria,
    required this.onCategoriaChip,
    required this.onPickFecha,
    required this.onPickHora,
    required this.onVolver,
    required this.onGuardar,
    required this.formatFecha,
    required this.formatHora,
  });

  String _fechaCorta() {
    final now = DateTime.now();
    final hoy = fecha.year == now.year && fecha.month == now.month && fecha.day == now.day;
    return hoy ? 'Hoy' : formatFecha(fecha);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final color = _tipoColor(tipo);
    final placesAsync = ref.watch(financePlacesProvider);
    final places = placesAsync.valueOrNull ?? [];
    // Sort by usados DESC
    final placesSorted = [...places]..sort((a, b) => b.usados.compareTo(a.usados));
    final asyncCats = ref.watch(allFinanceCategoriesProvider);
    final tipoCat = tipo == 'transferencia' ? 'gasto' : tipo;
    final categoriasRapidas = (asyncCats.valueOrNull ?? [])
        .where((c) => c.parentId != null && (c.tipo == tipoCat || c.tipo == 'ambos'))
        .take(4)
        .toList();

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // Encabezado con botón volver
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onVolver,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Text(
              isEditing
                  ? 'Editar transacción'
                  : switch (tipo) {
                      'ingreso' => 'Nuevo Ingreso',
                      'gasto' => 'Nuevo Gasto',
                      _ => 'Transferencia',
                    },
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: AppTextSize.heading,
                fontWeight: FontWeight.w700,
                color: tc.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Ingreso/Gasto/Transferencia primero — ya no existe un paso previo
        // aparte solo para elegir el tipo. Píldora compacta en vez de
        // SegmentedButton grande — más cerca del mockup aprobado.
        AppPillSelector<String>(
          value: tipo,
          onChanged: onTipoChanged,
          options: [
            PillOption(value: 'ingreso', label: 'Ingreso', color: _tipoColor('ingreso')),
            PillOption(value: 'gasto', label: 'Gasto', color: _tipoColor('gasto')),
            PillOption(value: 'transferencia', label: 'Transferir', color: _tipoColor('transferencia')),
          ],
        ),
        const SizedBox(height: 16),

        // Registro (origen) y, si aplica, Destino — agrupados en una tarjeta
        // con borde, igual que el resto del detalle (Fecha/Hora/Lugar/Nota)
        // en vez de quedar sueltos con un subrayado propio: dos lenguajes
        // visuales distintos en la misma pantalla se sentía como dos
        // formularios pegados, no uno solo.
        AppSectionCard(
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: AppIconSize.small, color: tc.textSecondary),
                const SizedBox(width: 12),
                // Siempre visible, nunca desaparece al elegir uno. Si el
                // formulario se abrió desde un registro específico (el
                // flujo normal, vía el FAB de ese registro), ya viene
                // preseleccionado acá — el usuario puede cambiarlo igual.
                Expanded(
                  child: _LibroSelector(
                    label: 'Registro',
                    libros: libros,
                    libroId: libroId,
                    onChanged: onLibroChanged,
                    tc: tc,
                  ),
                ),
              ],
            ),
            // Destino: solo para transferencia. Sin esto tampoco había forma
            // de corregir el destino de una transferencia dudosa al
            // editarla.
            if (tipo == 'transferencia') ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.swap_horiz, size: AppIconSize.small, color: tc.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LibroSelector(
                      label: 'Destino',
                      libros: libros,
                      libroId: libroDestinoId,
                      onChanged: onLibroDestinoChanged,
                      tc: tc,
                      excludeId: libroId,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Monto: mismo lenguaje visual que Créditos (card_movement_sheet.dart)
        // — etiqueta "MONTO" chica arriba, campo normal alineado a la
        // izquierda con "$" como prefijo, tamaño de texto moderado. Antes
        // era un número gigante centrado con subrayado propio, inconsistente
        // con el resto de la app.
        Text(
          'MONTO',
          style: TextStyle(
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tc.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: montoCtrl,
          focusNode: montoFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_MontoFormatter()],
          style: TextStyle(
            fontSize: AppTextSize.emphasis,
            fontWeight: FontWeight.w700,
            color: color,
          ),
          decoration: const InputDecoration(
            prefixText: '\$ ',
            hintText: 'Ej. 80.000',
          ),
        ),
        const SizedBox(height: 16),

        // ── Categoría: chips rápidos en vez de un botón plano que esconde
        // todo detrás de un tap — el paso completo con buscador sigue
        // disponible tras el chip "Más".
        if (tipo != 'transferencia') ...[
          _SectionLabel('Categoría', tc),
          const SizedBox(height: 10),
          SizedBox(
            height: 74,
            // Center + SingleChildScrollView (no ListView): con pocos chips
            // quedan centrados visualmente; si no caben, igual se puede
            // deslizar — un ListView siempre arranca pegado a la izquierda.
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final cat in categoriasRapidas) ...[
                      _CategoriaChip(
                        categoria: cat,
                        seleccionada: categoriaSeleccionada?.id == cat.id,
                        onTap: () => onCategoriaChip(cat),
                        tc: tc,
                      ),
                      const SizedBox(width: 10),
                    ],
                    // Si lo elegido no está entre los rápidos (vino del paso
                    // completo), se agrega para que quede visible/resaltado.
                    if (categoriaSeleccionada != null &&
                        !categoriasRapidas.any((c) => c.id == categoriaSeleccionada!.id)) ...[
                      _CategoriaChip(
                        categoria: categoriaSeleccionada!,
                        seleccionada: true,
                        onTap: () {},
                        tc: tc,
                      ),
                      const SizedBox(width: 10),
                    ],
                    _CategoriaMasChip(onTap: onSeleccionarCategoria, tc: tc),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Detalle: fecha y hora independientes (cada una abre su propio
        // selector), lugar y nota — agrupados en una sola tarjeta neutra.
        AppSectionCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: _FechaHoraTap(
                    icono: Icons.event_outlined,
                    texto: _fechaCorta(),
                    onTap: onPickFecha,
                    tc: tc,
                  ),
                ),
                Container(width: 1, height: 32, color: tc.borderCard),
                Expanded(
                  child: _FechaHoraTap(
                    icono: Icons.schedule_outlined,
                    texto: formatHora(hora),
                    onTap: onPickHora,
                    tc: tc,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Sin caption propia arriba: el labelText del campo ya hace de
            // título flotante al enfocarlo — ponerle un texto fijo encima
            // además del label repetía la misma palabra dos veces.
            Row(
              children: [
                // Un solo ícono para "lugar o persona" (ni solo mapa ni
                // solo gente) — un comercio cubre ambos sentidos mejor que
                // un pin de ubicación.
                Icon(Icons.storefront_outlined, size: AppIconSize.small, color: tc.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: _OrdenanteField(
                    ordenanteCtrl: ordenanteCtrl,
                    placesSorted: placesSorted,
                    tc: tc,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Nota: sin maxLines fijo — crece hacia abajo si el usuario
            // escribe más de una línea, en vez de recortar el texto.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Icon(Icons.edit_note_outlined, size: AppIconSize.small, color: tc.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: notaCtrl,
                    minLines: 1,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      hintText: 'Descripción adicional…',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Botón Guardar
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: guardando || !montoValido ? null : onGuardar,
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: legibleForegroundOn(color)),
            child: guardando
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: legibleForegroundOn(color)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check, size: AppIconSize.small),
                      const SizedBox(width: 8),
                      Text(
                        isEditing ? 'Guardar cambios' : 'Guardar',
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontWeight: FontWeight.w700,
                          fontSize: AppTextSize.body,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────
// ─── Chip de categoría rápida ─────────────────────────────────────────────────
class _CategoriaChip extends StatelessWidget {
  final CatalogoCategoria categoria;
  final bool seleccionada;
  final VoidCallback onTap;
  final AppThemeColors tc;

  const _CategoriaChip({
    required this.categoria,
    required this.seleccionada,
    required this.onTap,
    required this.tc,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _tipoColor(categoria.tipo).withValues(alpha: seleccionada ? 0.18 : 0.1),
                borderRadius: BorderRadius.circular(15),
                border: seleccionada ? Border.all(color: _tipoColor(categoria.tipo), width: 2) : null,
              ),
              child: Icon(categoria.icono, size: AppIconSize.medium, color: _tipoColor(categoria.tipo)),
            ),
            const SizedBox(height: 6),
            Text(
              categoria.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500,
                color: seleccionada ? tc.textPrimary : tc.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriaMasChip extends StatelessWidget {
  final VoidCallback onTap;
  final AppThemeColors tc;

  const _CategoriaMasChip({required this.onTap, required this.tc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: tc.borderCard, style: BorderStyle.solid),
              ),
              child: Icon(Icons.add, size: AppIconSize.small, color: tc.textSecondary),
            ),
            const SizedBox(height: 6),
            Text('Más', style: TextStyle(fontSize: AppTextSize.caption, color: tc.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── Fecha u hora, cada una tocable por separado ──────────────────────────────
// Antes una sola fila abría los dos diálogos en secuencia (fecha, luego
// hora); el usuario pidió volver a poder elegir cuál de los dos cambiar sin
// tener que pasar por el otro.
class _FechaHoraTap extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Future<void> Function() onTap;
  final AppThemeColors tc;

  const _FechaHoraTap({
    required this.icono,
    required this.texto,
    required this.onTap,
    required this.tc,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: AppIconSize.small, color: tc.textSecondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                texto,
                style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600, color: tc.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppThemeColors tc;

  const _SectionLabel(this.text, this.tc);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w600,
          color: tc.textSecondary,
          letterSpacing: 0.8,
        ),
      );
}

// ─── Ordenante autocomplete ───────────────────────────────────────────────────
// Stateless: el Autocomplete mantiene su propio controller; el valor inicial
// se siembra con initialValue y los cambios se propagan a ordenanteCtrl.
class _OrdenanteField extends StatelessWidget {
  final TextEditingController ordenanteCtrl;
  final List<FinancePlace> placesSorted;
  final AppThemeColors tc;

  const _OrdenanteField({
    required this.ordenanteCtrl,
    required this.placesSorted,
    required this.tc,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<FinancePlace>(
      initialValue: TextEditingValue(text: ordenanteCtrl.text),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return placesSorted;
        return placesSorted.where((p) => p.nombre
            .toLowerCase()
            .contains(textEditingValue.text.toLowerCase()));
      },
      displayStringForOption: (p) => p.nombre,
      fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          onEditingComplete: onSubmit,
          onChanged: (val) => ordenanteCtrl.text = val,
          decoration: const InputDecoration(
            labelText: 'Lugar / Ordenante',
            hintText: 'Tienda, persona, lugar…',
          ),
        );
      },
      onSelected: (p) => ordenanteCtrl.text = p.nombre,
      // Solo el nombre — el conteo de usos no le aporta nada al usuario
      // viendo su propia lista de lugares/personas, solo ruido.
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: tc.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final p = options.elementAt(i);
                return ListTile(
                  dense: true,
                  title: Text(p.nombre, style: TextStyle(color: tc.textPrimary, fontSize: AppTextSize.body)),
                  onTap: () => onSelected(p),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// Mismo NumberFormat (es_CO, sin decimales) que usa `formatCOP` en todo el
// proyecto para mostrar montos ya guardados.
final _milesFormat = NumberFormat.decimalPattern('es_CO');

// Agrupa un entero en miles con '.' — "45000" → "45.000" — para que lo que
// el usuario digita se vea igual a como luego aparece en el histórico.
String agruparMiles(int value) => _milesFormat.format(value);

// ─── Formatter: separa miles con "." mientras se digita (estilo peso
// colombiano) y antepone "$ " al propio texto editable — así, con
// textAlign.center, el "$" y el monto quedan centrados como un solo bloque
// en vez de que el monto se centre solo en el espacio que deja un
// prefixText fijo a la izquierda.
class _MontoFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final soloDigitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = agruparMiles(int.parse(soloDigitos));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─── Paso 3: categoría — embebido en el mismo sheet (no un segundo sheet
// encima) con buscador, porque el catálogo es grande y bajar por un
// acordeón completo cada vez no escala. ────────────────────────────────────
class _Paso3Categoria extends ConsumerStatefulWidget {
  final String tipo;
  final ScrollController scrollCtrl;
  final VoidCallback onVolver;
  final ValueChanged<CatalogoCategoria> onSeleccionar;

  const _Paso3Categoria({
    super.key,
    required this.tipo,
    required this.scrollCtrl,
    required this.onVolver,
    required this.onSeleccionar,
  });

  @override
  ConsumerState<_Paso3Categoria> createState() => _Paso3CategoriaState();
}

class _Paso3CategoriaState extends ConsumerState<_Paso3Categoria> {
  final _buscarCtrl = TextEditingController();
  final Set<String> _expandidos = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _buscarCtrl.addListener(
      () => setState(() => _query = _buscarCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _crearCategoria() async {
    final result = await showNuevaCategoriaSheet(context, widget.tipo);
    if (result != null) {
      ref.invalidate(allFinanceCategoriesProvider);
      widget.onSeleccionar(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = Theme.of(context).extension<AppThemeColors>()!;
    final asyncCats = ref.watch(allFinanceCategoriesProvider);

    return Column(
      children: [
        // Encabezado con flecha "volver" — deja claro que es un paso del
        // mismo flujo, no una ventana nueva.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVolver,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Text(
                'Categoría',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: AppTextSize.heading,
                  fontWeight: FontWeight.w700,
                  color: tc.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _buscarCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: AppIconSize.small),
              hintText: 'Buscar categoría…',
            ),
          ),
        ),
        Expanded(
          child: asyncCats.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (all) {
              final delTipo =
                  all.where((c) => c.tipo == widget.tipo || c.tipo == 'ambos').toList();

              if (_query.isNotEmpty) {
                final resultados = delTipo
                    .where((c) => c.nombre.toLowerCase().contains(_query))
                    .toList();
                if (resultados.isEmpty) {
                  return Center(
                    child: Text(
                      'Sin resultados para "$_query"',
                      style: TextStyle(color: tc.textSecondary, fontSize: AppTextSize.body),
                    ),
                  );
                }
                final padresPorId = {for (final p in delTipo) p.id: p};
                return ListView.builder(
                  controller: widget.scrollCtrl,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: resultados.length,
                  itemBuilder: (context, i) {
                    final c = resultados[i];
                    final padre = c.parentId != null ? padresPorId[c.parentId] : null;
                    return ListTile(
                      leading: Icon(c.icono, size: AppIconSize.medium, color: _tipoColor(c.tipo)),
                      title: Text(c.nombre),
                      subtitle: padre != null ? Text(padre.nombre) : null,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onSeleccionar(c);
                      },
                    );
                  },
                );
              }

              final padres = delTipo.where((c) => c.parentId == null).toList();
              if (padres.isEmpty) {
                return Center(
                  child: TextButton.icon(
                    onPressed: _crearCategoria,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear categoría nueva'),
                  ),
                );
              }
              // Acordeón padre→hijo (vuelta al diseño original, pedido
              // explícito del usuario tras comparar en el artifact: le
              // gustaba más el acordeón, el problema era que la versión en
              // la app se veía plana/sin pulir frente al boceto — esta
              // versión usa _CategoriaPadreTile/_CategoriaHijoTile con el
              // mismo chip de ícono con fondo de color que el mockup, en
              // vez de ListTile por defecto).
              return ListView.builder(
                controller: widget.scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: padres.length + 1,
                itemBuilder: (context, index) {
                  if (index == padres.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _CategoriaPadreTile(
                        nombre: 'Crear categoría nueva',
                        icono: Icons.add,
                        color: tc.textSecondary,
                        tc: tc,
                        dashed: true,
                        onTap: _crearCategoria,
                      ),
                    );
                  }

                  final padre = padres[index];
                  final hijos = delTipo.where((c) => c.parentId == padre.id).toList();
                  final isExpanded = _expandidos.contains(padre.id);
                  final color = _tipoColor(padre.tipo);

                  return Column(
                    children: [
                      _CategoriaPadreTile(
                        nombre: padre.nombre,
                        icono: padre.icono,
                        color: color,
                        tc: tc,
                        trailingExtra: IconButton(
                          icon: Icon(Icons.add, size: AppIconSize.small, color: tc.textTertiary),
                          tooltip: 'Agregar subcategoría',
                          onPressed: () async {
                            final result = await showNuevaCategoriaSheet(
                              context,
                              widget.tipo,
                              parentIdInicial: padre.id,
                            );
                            if (result != null) {
                              ref.invalidate(allFinanceCategoriesProvider);
                              widget.onSeleccionar(result);
                            }
                          },
                        ),
                        chevron: hijos.isEmpty
                            ? null
                            : (isExpanded ? Icons.expand_less : Icons.expand_more),
                        onTap: () => setState(() {
                          if (isExpanded) {
                            _expandidos.remove(padre.id);
                          } else {
                            _expandidos.add(padre.id);
                          }
                        }),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: isExpanded
                            ? Padding(
                                padding: const EdgeInsets.only(left: 20),
                                child: Column(
                                  children: hijos.map((hijo) {
                                    return _CategoriaHijoTile(
                                      nombre: hijo.nombre,
                                      icono: hijo.icono,
                                      color: _tipoColor(hijo.tipo),
                                      tc: tc,
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        widget.onSeleccionar(hijo);
                                      },
                                    );
                                  }).toList(),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (index < padres.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Divider(height: 1, color: tc.borderCard),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Fila de categoría padre: ícono en chip redondeado con fondo tenue de su
/// color (mismo lenguaje que el boceto original del artifact), nombre, y
/// opcionalmente un control extra (el "+" de agregar subcategoría) y una
/// flecha de expandir/colapsar.
class _CategoriaPadreTile extends StatelessWidget {
  final String nombre;
  final IconData icono;
  final Color color;
  final AppThemeColors tc;
  final VoidCallback onTap;
  final Widget? trailingExtra;
  final IconData? chevron;
  final bool dashed;

  const _CategoriaPadreTile({
    required this.nombre,
    required this.icono,
    required this.color,
    required this.tc,
    required this.onTap,
    this.trailingExtra,
    this.chevron,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: dashed ? Border.all(color: tc.borderCard, width: 1.2) : null,
                ),
                alignment: Alignment.center,
                child: Icon(icono, size: AppIconSize.medium, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nombre,
                  style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w700, color: tc.textPrimary),
                ),
              ),
              ?trailingExtra,
              if (chevron != null) Icon(chevron, color: tc.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de subcategoría (hijo), indentada bajo su padre expandido — mismo
/// chip de ícono que el padre pero un poco más chico, sin flecha.
class _CategoriaHijoTile extends StatelessWidget {
  final String nombre;
  final IconData icono;
  final Color color;
  final AppThemeColors tc;
  final VoidCallback onTap;

  const _CategoriaHijoTile({
    required this.nombre,
    required this.icono,
    required this.color,
    required this.tc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icono, size: AppIconSize.small, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nombre,
                  style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600, color: tc.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
