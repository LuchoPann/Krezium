class FinanzasFiltros {
  // Agrupación visual del listado único de registros — ya no filtra datos,
  // solo decide el tipo de encabezado de sección ('diario'|'semanal'|'mensual').
  final String periodo;
  final bool ascending;
  final String tipoFiltro; // 'todos'|'ingreso'|'gasto'

  const FinanzasFiltros({
    this.periodo = 'mensual',
    this.ascending = false,
    this.tipoFiltro = 'todos',
  });

  FinanzasFiltros copyWith({
    String? periodo,
    bool? ascending,
    String? tipoFiltro,
  }) =>
      FinanzasFiltros(
        periodo: periodo ?? this.periodo,
        ascending: ascending ?? this.ascending,
        tipoFiltro: tipoFiltro ?? this.tipoFiltro,
      );
}
