import 'package:flutter/material.dart';

import 'finance_icon_map.dart';

class CatalogoCategoria {
  final String id;
  final String nombre;
  final IconData icono;
  final Color color;
  final String tipo; // 'ingreso'|'gasto'|'ambos'
  final String iconoKey; // clave para financeIconMap
  final String? parentId; // null = categoría padre

  const CatalogoCategoria({
    required this.id,
    required this.nombre,
    required this.icono,
    required this.color,
    required this.tipo,
    required this.iconoKey,
    this.parentId,
  });

  /// Convierte una categoría creada por el usuario (guardada en
  /// FinanceCategories) al mismo tipo que el catálogo estático — sin esto,
  /// `allFinanceCategoriesProvider` mezclaba dos tipos distintos en una
  /// lista y cualquier `whereType<CatalogoCategoria>()` descartaba en
  /// silencio TODAS las categorías creadas por el usuario (nunca aparecían
  /// en ningún selector).
  factory CatalogoCategoria.fromCustomRow({
    required String id,
    required String nombre,
    required String iconoKey,
    required String colorHex,
    required String tipo,
    String? parentId,
  }) {
    final hex = colorHex.replaceAll('#', '');
    return CatalogoCategoria(
      id: id,
      nombre: nombre,
      icono: iconFromKey(iconoKey),
      color: Color(int.parse('FF$hex', radix: 16)),
      tipo: tipo,
      iconoKey: iconoKey,
      parentId: parentId,
    );
  }
}

// Categorías padre (agrupadores)
// No son `const`: `icono` se deriva de `iconFromKey(iconoKey)` para que el
// ícono mostrado nunca pueda desincronizarse del que vive en
// finance_icon_map.dart — una llamada de función no es una expresión const.
final List<CatalogoCategoria> catalogoCategoriaPadres = [
  CatalogoCategoria(id: 'cat_ingresos_padre', nombre: 'Ingresos', icono: iconFromKey('attach_money'), color: Color(0xFF22C55E), tipo: 'ingreso', iconoKey: 'attach_money'),
  CatalogoCategoria(id: 'cat_alimentacion_padre', nombre: 'Alimentación', icono: iconFromKey('restaurant'), color: Color(0xFFF97316), tipo: 'gasto', iconoKey: 'restaurant'),
  CatalogoCategoria(id: 'cat_transporte_padre', nombre: 'Transporte', icono: iconFromKey('directions_car'), color: Color(0xFF3B82F6), tipo: 'gasto', iconoKey: 'directions_car'),
  CatalogoCategoria(id: 'cat_salud_padre', nombre: 'Salud', icono: iconFromKey('local_hospital'), color: Color(0xFFEF4444), tipo: 'gasto', iconoKey: 'local_hospital'),
  CatalogoCategoria(id: 'cat_vivienda_padre', nombre: 'Vivienda', icono: iconFromKey('home'), color: Color(0xFF8B5CF6), tipo: 'gasto', iconoKey: 'home'),
  CatalogoCategoria(id: 'cat_educacion_padre', nombre: 'Educación', icono: iconFromKey('school'), color: Color(0xFF06B6D4), tipo: 'gasto', iconoKey: 'school'),
  CatalogoCategoria(id: 'cat_ocio_padre', nombre: 'Ocio', icono: iconFromKey('movie'), color: Color(0xFFA855F7), tipo: 'gasto', iconoKey: 'movie'),
  CatalogoCategoria(id: 'cat_otros_padre', nombre: 'Otros', icono: iconFromKey('more_horiz'), color: Color(0xFF6B7280), tipo: 'ambos', iconoKey: 'more_horiz'),
];

final List<CatalogoCategoria> catalogoFinanzas = [
  // --- Ingresos (8) — padre: cat_ingresos_padre ---
  CatalogoCategoria(id: 'salario', nombre: 'Salario', icono: iconFromKey('work'), color: Color(0xFF22C55E), tipo: 'ingreso', iconoKey: 'work', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'freelance', nombre: 'Freelance', icono: iconFromKey('laptop'), color: Color(0xFF10B981), tipo: 'ingreso', iconoKey: 'laptop', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'negocio', nombre: 'Negocio', icono: iconFromKey('store'), color: Color(0xFF059669), tipo: 'ingreso', iconoKey: 'store', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'arriendo_recibido', nombre: 'Arriendo recibido', icono: iconFromKey('home'), color: Color(0xFF16A34A), tipo: 'ingreso', iconoKey: 'home', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'intereses', nombre: 'Intereses', icono: iconFromKey('trending_up'), color: Color(0xFF15803D), tipo: 'ingreso', iconoKey: 'trending_up', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'regalo_ingreso', nombre: 'Regalo', icono: iconFromKey('card_giftcard'), color: Color(0xFF4ADE80), tipo: 'ingreso', iconoKey: 'card_giftcard', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'devolucion', nombre: 'Devolución', icono: iconFromKey('swap_horiz'), color: Color(0xFF86EFAC), tipo: 'ingreso', iconoKey: 'swap_horiz', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'otro_ingreso', nombre: 'Otro ingreso', icono: iconFromKey('attach_money'), color: Color(0xFF6EE7B7), tipo: 'ingreso', iconoKey: 'attach_money', parentId: 'cat_ingresos_padre'),
  // --- Alimentación — padre: cat_alimentacion_padre ---
  CatalogoCategoria(id: 'restaurantes', nombre: 'Restaurantes', icono: iconFromKey('restaurant'), color: Color(0xFFEA580C), tipo: 'gasto', iconoKey: 'restaurant', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'supermercado', nombre: 'Supermercado', icono: iconFromKey('local_grocery_store'), color: Color(0xFFFB923C), tipo: 'gasto', iconoKey: 'local_grocery_store', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'domicilios', nombre: 'Domicilios', icono: iconFromKey('delivery_dining'), color: Color(0xFFF59E0B), tipo: 'gasto', iconoKey: 'delivery_dining', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'cafe_snacks', nombre: 'Bebidas', icono: iconFromKey('local_cafe'), color: Color(0xFFC2410C), tipo: 'gasto', iconoKey: 'local_cafe', parentId: 'cat_alimentacion_padre'),
  // --- Transporte — padre: cat_transporte_padre — una categoría engloba,
  // la subcategoría es cada MEDIO de transporte distinto (no un duplicado
  // del nombre del padre).
  CatalogoCategoria(id: 'transporte_publico', nombre: 'Bus / Transporte público', icono: iconFromKey('directions_bus'), color: Color(0xFF3B82F6), tipo: 'gasto', iconoKey: 'directions_bus', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'carro', nombre: 'Carro', icono: iconFromKey('directions_car'), color: Color(0xFF2563EB), tipo: 'gasto', iconoKey: 'directions_car', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'moto', nombre: 'Moto', icono: iconFromKey('two_wheeler'), color: Color(0xFF1D4ED8), tipo: 'gasto', iconoKey: 'two_wheeler', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'taxi_app', nombre: 'Taxi / App', icono: iconFromKey('local_taxi'), color: Color(0xFF60A5FA), tipo: 'gasto', iconoKey: 'local_taxi', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'bicicleta', nombre: 'Bicicleta', icono: iconFromKey('pedal_bike'), color: Color(0xFF93C5FD), tipo: 'gasto', iconoKey: 'pedal_bike', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'avion', nombre: 'Avión', icono: iconFromKey('flight'), color: Color(0xFF1E40AF), tipo: 'gasto', iconoKey: 'flight', parentId: 'cat_transporte_padre'),
  // --- Salud — padre: cat_salud_padre ---
  CatalogoCategoria(id: 'consulta_medica', nombre: 'Consulta médica', icono: iconFromKey('local_hospital'), color: Color(0xFFEF4444), tipo: 'gasto', iconoKey: 'local_hospital', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'medicamentos', nombre: 'Medicamentos', icono: iconFromKey('medication'), color: Color(0xFFDC2626), tipo: 'gasto', iconoKey: 'medication', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'seguro_salud', nombre: 'Seguro de salud', icono: iconFromKey('health_and_safety'), color: Color(0xFFB91C1C), tipo: 'gasto', iconoKey: 'health_and_safety', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'odontologia', nombre: 'Odontología', icono: iconFromKey('medical_services'), color: Color(0xFFF87171), tipo: 'gasto', iconoKey: 'medical_services', parentId: 'cat_salud_padre'),
  // --- Vivienda — padre: cat_vivienda_padre ---
  CatalogoCategoria(id: 'arriendo_hipoteca', nombre: 'Arriendo / Hipoteca', icono: iconFromKey('home'), color: Color(0xFF8B5CF6), tipo: 'gasto', iconoKey: 'home', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'servicios_publicos', nombre: 'Servicios públicos', icono: iconFromKey('bolt'), color: Color(0xFFF59E0B), tipo: 'gasto', iconoKey: 'bolt', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'mantenimiento_hogar', nombre: 'Mantenimiento del hogar', icono: iconFromKey('handyman'), color: Color(0xFF7C3AED), tipo: 'gasto', iconoKey: 'handyman', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'muebles_hogar', nombre: 'Muebles y hogar', icono: iconFromKey('chair'), color: Color(0xFFA78BFA), tipo: 'gasto', iconoKey: 'chair', parentId: 'cat_vivienda_padre'),
  // --- Educación — padre: cat_educacion_padre ---
  CatalogoCategoria(id: 'matricula_pension', nombre: 'Matrícula / Pensión', icono: iconFromKey('school'), color: Color(0xFF06B6D4), tipo: 'gasto', iconoKey: 'school', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'cursos_online', nombre: 'Cursos online', icono: iconFromKey('laptop'), color: Color(0xFF0891B2), tipo: 'gasto', iconoKey: 'laptop', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'libros_material', nombre: 'Libros y material', icono: iconFromKey('menu_book'), color: Color(0xFF0E7490), tipo: 'gasto', iconoKey: 'menu_book', parentId: 'cat_educacion_padre'),
  // --- Ocio — padre: cat_ocio_padre ---
  CatalogoCategoria(id: 'entretenimiento', nombre: 'Entretenimiento', icono: iconFromKey('movie'), color: Color(0xFFA855F7), tipo: 'gasto', iconoKey: 'movie', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'viajes', nombre: 'Viajes', icono: iconFromKey('flight'), color: Color(0xFF0EA5E9), tipo: 'gasto', iconoKey: 'flight', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'deporte', nombre: 'Deporte', icono: iconFromKey('fitness_center'), color: Color(0xFF10B981), tipo: 'gasto', iconoKey: 'fitness_center', parentId: 'cat_ocio_padre'),
  // --- Otros — padre: cat_otros_padre ---
  CatalogoCategoria(id: 'ropa', nombre: 'Ropa', icono: iconFromKey('checkroom'), color: Color(0xFFEC4899), tipo: 'gasto', iconoKey: 'checkroom', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'mascotas', nombre: 'Mascotas', icono: iconFromKey('pets'), color: Color(0xFFD97706), tipo: 'gasto', iconoKey: 'pets', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'tecnologia', nombre: 'Tecnología', icono: iconFromKey('devices'), color: Color(0xFF6366F1), tipo: 'gasto', iconoKey: 'devices', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'belleza', nombre: 'Belleza', icono: iconFromKey('fitness_center'), color: Color(0xFFF43F5E), tipo: 'gasto', iconoKey: 'fitness_center', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'regalos_gasto', nombre: 'Regalos', icono: iconFromKey('card_giftcard'), color: Color(0xFFE879F9), tipo: 'gasto', iconoKey: 'card_giftcard', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'ahorros', nombre: 'Ahorros', icono: iconFromKey('savings'), color: Color(0xFF14B8A6), tipo: 'gasto', iconoKey: 'savings', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'inversion', nombre: 'Inversión', icono: iconFromKey('trending_up'), color: Color(0xFF0D9488), tipo: 'gasto', iconoKey: 'trending_up', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'suscripciones', nombre: 'Suscripciones', icono: iconFromKey('credit_card'), color: Color(0xFF7C3AED), tipo: 'gasto', iconoKey: 'credit_card', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'cuidado_personal', nombre: 'Cuidado personal', icono: iconFromKey('fitness_center'), color: Color(0xFFDB2777), tipo: 'gasto', iconoKey: 'fitness_center', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'hogar', nombre: 'Hogar', icono: iconFromKey('home'), color: Color(0xFF92400E), tipo: 'gasto', iconoKey: 'home', parentId: 'cat_otros_padre'),
  CatalogoCategoria(id: 'otro_gasto', nombre: 'Otro gasto', icono: iconFromKey('more_horiz'), color: Color(0xFF6B7280), tipo: 'gasto', iconoKey: 'more_horiz', parentId: 'cat_otros_padre'),
];

/// Todas las categorías: padres + hijas
List<CatalogoCategoria> get todoCatalogo => [...catalogoCategoriaPadres, ...catalogoFinanzas];
