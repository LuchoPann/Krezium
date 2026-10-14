class FinanzasFiltros {
  // Agrupación visual del listado único de registros — ya no filtra datos,
  // solo decide el tipo de encabezado de sección ('diario'|'semanal'|'mensual').
  final String periodo;
  final bool ascending;
  final String tipoFiltro; // 'todos'|'ingreso'|'gasto'
  // Fase 06: filtro por categoría exacta — permite navegar desde un
  // resultado de Estadísticas (una porción del donut, una categoría de la
  // leyenda) directo a los movimientos que lo originan. null = sin filtro.
  final String? categoriaId;

  const FinanzasFiltros({
    this.periodo = 'mensual',
    this.ascending = false,
    this.tipoFiltro = 'todos',
    this.categoriaId,
  });

  FinanzasFiltros copyWith({
    String? periodo,
    bool? ascending,
    String? tipoFiltro,
    String? categoriaId,
    // insertOnConflictUpdate-style sentinel: copyWith no puede distinguir
    // "no toques categoriaId" de "ponlo en null" solo con el parámetro
    // nombrado, así que limpiarlo es una acción explícita aparte.
    bool limpiarCategoria = false,
  }) =>
      FinanzasFiltros(
        periodo: periodo ?? this.periodo,
        ascending: ascending ?? this.ascending,
        tipoFiltro: tipoFiltro ?? this.tipoFiltro,
        categoriaId: limpiarCategoria ? null : (categoriaId ?? this.categoriaId),
      );
}
