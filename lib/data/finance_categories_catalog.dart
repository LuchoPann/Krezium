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
  // --- Ampliación del catálogo (propuesta en
  // docs/superpowers/specs/2026-10-14-catalogo-categorias-propuesta.md,
  // aprobada por el usuario) — de 7 a 17 padres de gasto, consolidando
  // subcategorías en vez de fragmentar una por cada matiz. ──────────────
  CatalogoCategoria(id: 'cat_tecnologia_padre', nombre: 'Tecnología', icono: iconFromKey('devices'), color: Color(0xFF6366F1), tipo: 'gasto', iconoKey: 'devices'),
  CatalogoCategoria(id: 'cat_suscripciones_padre', nombre: 'Suscripciones', icono: iconFromKey('credit_card'), color: Color(0xFFD946EF), tipo: 'gasto', iconoKey: 'credit_card'),
  CatalogoCategoria(id: 'cat_ropa_padre', nombre: 'Ropa', icono: iconFromKey('checkroom'), color: Color(0xFFEC4899), tipo: 'gasto', iconoKey: 'checkroom'),
  CatalogoCategoria(id: 'cat_belleza_padre', nombre: 'Belleza y cuidado personal', icono: iconFromKey('spa'), color: Color(0xFFF43F5E), tipo: 'gasto', iconoKey: 'spa'),
  CatalogoCategoria(id: 'cat_viajes_padre', nombre: 'Viajes', icono: iconFromKey('flight'), color: Color(0xFF0EA5E9), tipo: 'gasto', iconoKey: 'flight'),
  CatalogoCategoria(id: 'cat_familia_padre', nombre: 'Familia y mascotas', icono: iconFromKey('family'), color: Color(0xFFD97706), tipo: 'gasto', iconoKey: 'family'),
  CatalogoCategoria(id: 'cat_finanzas_padre', nombre: 'Finanzas y ahorro', icono: iconFromKey('account_balance'), color: Color(0xFF0D9488), tipo: 'gasto', iconoKey: 'account_balance'),
  CatalogoCategoria(id: 'cat_compras_padre', nombre: 'Compras y regalos', icono: iconFromKey('shopping_bag'), color: Color(0xFFE879F9), tipo: 'gasto', iconoKey: 'shopping_bag'),
  CatalogoCategoria(id: 'cat_trabajo_padre', nombre: 'Trabajo y negocio', icono: iconFromKey('business'), color: Color(0xFF4338CA), tipo: 'gasto', iconoKey: 'business'),
  CatalogoCategoria(id: 'cat_imprevistos_padre', nombre: 'Imprevistos', icono: iconFromKey('warning_amber'), color: Color(0xFFF59E0B), tipo: 'gasto', iconoKey: 'warning_amber'),
  CatalogoCategoria(id: 'cat_otros_padre', nombre: 'Otros', icono: iconFromKey('more_horiz'), color: Color(0xFF6B7280), tipo: 'ambos', iconoKey: 'more_horiz'),
];

final List<CatalogoCategoria> catalogoFinanzas = [
  // --- Ingresos — padre: cat_ingresos_padre — un solo padre con más
  // subcategorías, en vez de los ~10 padres de ingreso que proponía el
  // texto original (ver propuesta del 2026-10-14): la mayoría de usuarios
  // tiene 1-3 fuentes de ingreso reales, fragmentar en padres no ayuda.
  CatalogoCategoria(id: 'salario', nombre: 'Salario', icono: iconFromKey('work'), color: Color(0xFF22C55E), tipo: 'ingreso', iconoKey: 'work', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'freelance', nombre: 'Freelance', icono: iconFromKey('laptop'), color: Color(0xFF10B981), tipo: 'ingreso', iconoKey: 'laptop', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'negocio', nombre: 'Negocio', icono: iconFromKey('store'), color: Color(0xFF059669), tipo: 'ingreso', iconoKey: 'store', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'arriendo_recibido', nombre: 'Arriendo recibido', icono: iconFromKey('home'), color: Color(0xFF16A34A), tipo: 'ingreso', iconoKey: 'home', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'intereses', nombre: 'Intereses / Rendimientos', icono: iconFromKey('trending_up'), color: Color(0xFF15803D), tipo: 'ingreso', iconoKey: 'trending_up', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'regalo_ingreso', nombre: 'Regalo / Apoyo recibido', icono: iconFromKey('card_giftcard'), color: Color(0xFF4ADE80), tipo: 'ingreso', iconoKey: 'card_giftcard', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'devolucion', nombre: 'Devolución / Reembolso', icono: iconFromKey('swap_horiz'), color: Color(0xFF86EFAC), tipo: 'ingreso', iconoKey: 'swap_horiz', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'venta_bienes', nombre: 'Venta de bienes personales', icono: iconFromKey('shopping_bag'), color: Color(0xFF65A30D), tipo: 'ingreso', iconoKey: 'shopping_bag', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'ingreso_extraordinario', nombre: 'Ingreso extraordinario', icono: iconFromKey('redeem'), color: Color(0xFF84CC16), tipo: 'ingreso', iconoKey: 'redeem', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'bonificaciones', nombre: 'Bonificaciones y comisiones', icono: iconFromKey('badge'), color: Color(0xFF4D7C0F), tipo: 'ingreso', iconoKey: 'badge', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'liquidacion_laboral', nombre: 'Liquidación laboral', icono: iconFromKey('work_history'), color: Color(0xFF3F6212), tipo: 'ingreso', iconoKey: 'work_history', parentId: 'cat_ingresos_padre'),
  CatalogoCategoria(id: 'otro_ingreso', nombre: 'Otro ingreso', icono: iconFromKey('attach_money'), color: Color(0xFF6EE7B7), tipo: 'ingreso', iconoKey: 'attach_money', parentId: 'cat_ingresos_padre'),
  // --- Alimentación — padre: cat_alimentacion_padre ---
  CatalogoCategoria(id: 'restaurantes', nombre: 'Restaurantes', icono: iconFromKey('restaurant'), color: Color(0xFFEA580C), tipo: 'gasto', iconoKey: 'restaurant', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'supermercado', nombre: 'Supermercado', icono: iconFromKey('local_grocery_store'), color: Color(0xFFFB923C), tipo: 'gasto', iconoKey: 'local_grocery_store', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'domicilios', nombre: 'Domicilios', icono: iconFromKey('delivery_dining'), color: Color(0xFFF59E0B), tipo: 'gasto', iconoKey: 'delivery_dining', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'cafe_snacks', nombre: 'Bebidas', icono: iconFromKey('local_cafe'), color: Color(0xFFC2410C), tipo: 'gasto', iconoKey: 'local_cafe', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'frutas_verduras', nombre: 'Frutas y verduras', icono: iconFromKey('leaf'), color: Color(0xFF16A34A), tipo: 'gasto', iconoKey: 'leaf', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'carnes_pescados', nombre: 'Carnes y pescados', icono: iconFromKey('seafood'), color: Color(0xFFB91C1C), tipo: 'gasto', iconoKey: 'seafood', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'panaderia', nombre: 'Panadería', icono: iconFromKey('bakery'), color: Color(0xFFD97706), tipo: 'gasto', iconoKey: 'bakery', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'desayunos', nombre: 'Desayunos', icono: iconFromKey('breakfast'), color: Color(0xFFCA8A04), tipo: 'gasto', iconoKey: 'breakfast', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'comida_rapida', nombre: 'Comida rápida', icono: iconFromKey('fastfood'), color: Color(0xFFDC2626), tipo: 'gasto', iconoKey: 'fastfood', parentId: 'cat_alimentacion_padre'),
  CatalogoCategoria(id: 'alimentacion_trabajo', nombre: 'Alimentación en el trabajo', icono: iconFromKey('dining'), color: Color(0xFF9A3412), tipo: 'gasto', iconoKey: 'dining', parentId: 'cat_alimentacion_padre'),
  // --- Transporte — padre: cat_transporte_padre — una categoría engloba,
  // la subcategoría es cada MEDIO de transporte distinto (no un duplicado
  // del nombre del padre).
  CatalogoCategoria(id: 'transporte_publico', nombre: 'Bus / Transporte público', icono: iconFromKey('directions_bus'), color: Color(0xFF3B82F6), tipo: 'gasto', iconoKey: 'directions_bus', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'carro', nombre: 'Carro', icono: iconFromKey('directions_car'), color: Color(0xFF2563EB), tipo: 'gasto', iconoKey: 'directions_car', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'moto', nombre: 'Moto', icono: iconFromKey('two_wheeler'), color: Color(0xFF1D4ED8), tipo: 'gasto', iconoKey: 'two_wheeler', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'taxi_app', nombre: 'Taxi / App', icono: iconFromKey('local_taxi'), color: Color(0xFF60A5FA), tipo: 'gasto', iconoKey: 'local_taxi', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'bicicleta', nombre: 'Bicicleta', icono: iconFromKey('pedal_bike'), color: Color(0xFF93C5FD), tipo: 'gasto', iconoKey: 'pedal_bike', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'avion', nombre: 'Avión', icono: iconFromKey('flight'), color: Color(0xFF1E40AF), tipo: 'gasto', iconoKey: 'flight', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'transporte_intermunicipal', nombre: 'Transporte intermunicipal', icono: iconFromKey('directions_bus'), color: Color(0xFF1E3A8A), tipo: 'gasto', iconoKey: 'directions_bus', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'parqueadero', nombre: 'Parqueadero', icono: iconFromKey('parking'), color: Color(0xFF1D4ED8), tipo: 'gasto', iconoKey: 'parking', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'peajes', nombre: 'Peajes', icono: iconFromKey('receipt'), color: Color(0xFF2563EB), tipo: 'gasto', iconoKey: 'receipt', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'lavado_vehiculo', nombre: 'Lavado de vehículo', icono: iconFromKey('car_wash'), color: Color(0xFF3B82F6), tipo: 'gasto', iconoKey: 'car_wash', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'seguro_vehicular', nombre: 'Seguro vehicular / SOAT', icono: iconFromKey('shield'), color: Color(0xFF1E40AF), tipo: 'gasto', iconoKey: 'shield', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'revision_tecnico', nombre: 'Revisión técnico-mecánica', icono: iconFromKey('assignment'), color: Color(0xFF1E3A8A), tipo: 'gasto', iconoKey: 'assignment', parentId: 'cat_transporte_padre'),
  CatalogoCategoria(id: 'impuestos_vehiculares', nombre: 'Impuestos vehiculares', icono: iconFromKey('invoice'), color: Color(0xFF172554), tipo: 'gasto', iconoKey: 'invoice', parentId: 'cat_transporte_padre'),
  // --- Salud — padre: cat_salud_padre ---
  CatalogoCategoria(id: 'consulta_medica', nombre: 'Consulta médica', icono: iconFromKey('local_hospital'), color: Color(0xFFEF4444), tipo: 'gasto', iconoKey: 'local_hospital', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'medicamentos', nombre: 'Medicamentos', icono: iconFromKey('medication'), color: Color(0xFFDC2626), tipo: 'gasto', iconoKey: 'medication', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'seguro_salud', nombre: 'Seguro de salud', icono: iconFromKey('health_and_safety'), color: Color(0xFFB91C1C), tipo: 'gasto', iconoKey: 'health_and_safety', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'odontologia', nombre: 'Odontología', icono: iconFromKey('medical_services'), color: Color(0xFFF87171), tipo: 'gasto', iconoKey: 'medical_services', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'salud_mental', nombre: 'Salud mental', icono: iconFromKey('psychology'), color: Color(0xFFFCA5A5), tipo: 'gasto', iconoKey: 'psychology', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'higiene_personal', nombre: 'Higiene personal', icono: iconFromKey('healing'), color: Color(0xFF991B1B), tipo: 'gasto', iconoKey: 'healing', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'examenes_medicos', nombre: 'Exámenes médicos', icono: iconFromKey('monitor_heart'), color: Color(0xFFEF4444), tipo: 'gasto', iconoKey: 'monitor_heart', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'hospitalizacion', nombre: 'Hospitalización', icono: iconFromKey('local_hospital'), color: Color(0xFF7F1D1D), tipo: 'gasto', iconoKey: 'local_hospital', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'terapias', nombre: 'Terapias', icono: iconFromKey('psychology'), color: Color(0xFFFECACA), tipo: 'gasto', iconoKey: 'psychology', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'optica_gafas', nombre: 'Óptica y gafas', icono: iconFromKey('eyeglasses'), color: Color(0xFFF43F5E), tipo: 'gasto', iconoKey: 'eyeglasses', parentId: 'cat_salud_padre'),
  CatalogoCategoria(id: 'farmacia', nombre: 'Farmacia', icono: iconFromKey('pharmacy'), color: Color(0xFFBE123C), tipo: 'gasto', iconoKey: 'pharmacy', parentId: 'cat_salud_padre'),
  // --- Vivienda — padre: cat_vivienda_padre ---
  CatalogoCategoria(id: 'arriendo_hipoteca', nombre: 'Arriendo / Hipoteca', icono: iconFromKey('home'), color: Color(0xFF8B5CF6), tipo: 'gasto', iconoKey: 'home', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'servicios_publicos', nombre: 'Servicios públicos', icono: iconFromKey('bolt'), color: Color(0xFFF59E0B), tipo: 'gasto', iconoKey: 'bolt', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'administracion', nombre: 'Administración', icono: iconFromKey('business'), color: Color(0xFF6D28D9), tipo: 'gasto', iconoKey: 'business', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'mantenimiento_hogar', nombre: 'Mantenimiento del hogar', icono: iconFromKey('handyman'), color: Color(0xFF7C3AED), tipo: 'gasto', iconoKey: 'handyman', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'muebles_hogar', nombre: 'Muebles y hogar', icono: iconFromKey('chair'), color: Color(0xFFA78BFA), tipo: 'gasto', iconoKey: 'chair', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'mudanza', nombre: 'Mudanza', icono: iconFromKey('shipping'), color: Color(0xFF9333EA), tipo: 'gasto', iconoKey: 'shipping', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'electrodomesticos', nombre: 'Electrodomésticos', icono: iconFromKey('kitchen'), color: Color(0xFF6D28D9), tipo: 'gasto', iconoKey: 'kitchen', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'decoracion_hogar', nombre: 'Decoración', icono: iconFromKey('paint_brush'), color: Color(0xFF7C3AED), tipo: 'gasto', iconoKey: 'paint_brush', parentId: 'cat_vivienda_padre'),
  CatalogoCategoria(id: 'articulos_limpieza', nombre: 'Artículos de limpieza', icono: iconFromKey('broom'), color: Color(0xFF9061F9), tipo: 'gasto', iconoKey: 'broom', parentId: 'cat_vivienda_padre'),
  // --- Educación — padre: cat_educacion_padre ---
  CatalogoCategoria(id: 'matricula_pension', nombre: 'Matrícula / Pensión', icono: iconFromKey('school'), color: Color(0xFF06B6D4), tipo: 'gasto', iconoKey: 'school', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'cursos_online', nombre: 'Cursos online', icono: iconFromKey('laptop'), color: Color(0xFF0891B2), tipo: 'gasto', iconoKey: 'laptop', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'libros_material', nombre: 'Libros y material', icono: iconFromKey('menu_book'), color: Color(0xFF0E7490), tipo: 'gasto', iconoKey: 'menu_book', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'derechos_grado', nombre: 'Derechos de grado', icono: iconFromKey('history_edu'), color: Color(0xFF155E75), tipo: 'gasto', iconoKey: 'history_edu', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'papeleria', nombre: 'Papelería', icono: iconFromKey('description'), color: Color(0xFF0E7490), tipo: 'gasto', iconoKey: 'description', parentId: 'cat_educacion_padre'),
  CatalogoCategoria(id: 'fotocopias_impresiones', nombre: 'Fotocopias e impresiones', icono: iconFromKey('folder'), color: Color(0xFF164E63), tipo: 'gasto', iconoKey: 'folder', parentId: 'cat_educacion_padre'),
  // --- Tecnología — padre: cat_tecnologia_padre (nuevo) ---
  CatalogoCategoria(id: 'tecnologia', nombre: 'Dispositivos', icono: iconFromKey('devices'), color: Color(0xFF6366F1), tipo: 'gasto', iconoKey: 'devices', parentId: 'cat_tecnologia_padre'),
  CatalogoCategoria(id: 'reparaciones_tecnologia', nombre: 'Reparaciones', icono: iconFromKey('toolbox'), color: Color(0xFF4F46E5), tipo: 'gasto', iconoKey: 'toolbox', parentId: 'cat_tecnologia_padre'),
  CatalogoCategoria(id: 'software_apps', nombre: 'Software y apps', icono: iconFromKey('computer'), color: Color(0xFF818CF8), tipo: 'gasto', iconoKey: 'computer', parentId: 'cat_tecnologia_padre'),
  CatalogoCategoria(id: 'videojuegos', nombre: 'Videojuegos', icono: iconFromKey('sports_esports'), color: Color(0xFF4338CA), tipo: 'gasto', iconoKey: 'sports_esports', parentId: 'cat_tecnologia_padre'),
  CatalogoCategoria(id: 'accesorios_electronicos', nombre: 'Accesorios electrónicos', icono: iconFromKey('headphones'), color: Color(0xFF6D28D9), tipo: 'gasto', iconoKey: 'headphones', parentId: 'cat_tecnologia_padre'),
  CatalogoCategoria(id: 'almacenamiento_nube', nombre: 'Almacenamiento en la nube', icono: iconFromKey('cloud'), color: Color(0xFF4F46E5), tipo: 'gasto', iconoKey: 'cloud', parentId: 'cat_tecnologia_padre'),
  // --- Suscripciones — padre: cat_suscripciones_padre (nuevo) ---
  CatalogoCategoria(id: 'suscripciones', nombre: 'Streaming y música', icono: iconFromKey('credit_card'), color: Color(0xFFD946EF), tipo: 'gasto', iconoKey: 'credit_card', parentId: 'cat_suscripciones_padre'),
  CatalogoCategoria(id: 'telefonia_internet', nombre: 'Telefonía / Internet', icono: iconFromKey('router'), color: Color(0xFFC026D3), tipo: 'gasto', iconoKey: 'router', parentId: 'cat_suscripciones_padre'),
  CatalogoCategoria(id: 'otras_suscripciones', nombre: 'Otras suscripciones', icono: iconFromKey('membership'), color: Color(0xFFA21CAF), tipo: 'gasto', iconoKey: 'membership', parentId: 'cat_suscripciones_padre'),
  CatalogoCategoria(id: 'datos_moviles', nombre: 'Datos móviles / Recargas', icono: iconFromKey('sim_card'), color: Color(0xFF86198F), tipo: 'gasto', iconoKey: 'sim_card', parentId: 'cat_suscripciones_padre'),
  CatalogoCategoria(id: 'noticias_revistas', nombre: 'Noticias y revistas', icono: iconFromKey('newspaper'), color: Color(0xFF701A75), tipo: 'gasto', iconoKey: 'newspaper', parentId: 'cat_suscripciones_padre'),
  // --- Ropa — padre: cat_ropa_padre (nuevo) ---
  CatalogoCategoria(id: 'ropa', nombre: 'Ropa y calzado', icono: iconFromKey('checkroom'), color: Color(0xFFEC4899), tipo: 'gasto', iconoKey: 'checkroom', parentId: 'cat_ropa_padre'),
  CatalogoCategoria(id: 'accesorios_ropa', nombre: 'Accesorios', icono: iconFromKey('watch'), color: Color(0xFFDB2777), tipo: 'gasto', iconoKey: 'watch', parentId: 'cat_ropa_padre'),
  CatalogoCategoria(id: 'lavanderia', nombre: 'Lavandería / Arreglos', icono: iconFromKey('dry_cleaning'), color: Color(0xFFBE185D), tipo: 'gasto', iconoKey: 'dry_cleaning', parentId: 'cat_ropa_padre'),
  CatalogoCategoria(id: 'joyeria', nombre: 'Joyería y relojes', icono: iconFromKey('jewelry'), color: Color(0xFF9D174D), tipo: 'gasto', iconoKey: 'jewelry', parentId: 'cat_ropa_padre'),
  // --- Belleza y cuidado personal — padre: cat_belleza_padre (nuevo) ---
  CatalogoCategoria(id: 'belleza', nombre: 'Peluquería y cuidado', icono: iconFromKey('spa'), color: Color(0xFFF43F5E), tipo: 'gasto', iconoKey: 'spa', parentId: 'cat_belleza_padre'),
  CatalogoCategoria(id: 'tratamientos_esteticos', nombre: 'Tratamientos estéticos', icono: iconFromKey('healing'), color: Color(0xFFE11D48), tipo: 'gasto', iconoKey: 'healing', parentId: 'cat_belleza_padre'),
  CatalogoCategoria(id: 'cosmeticos_maquillaje', nombre: 'Cosméticos y maquillaje', icono: iconFromKey('spa'), color: Color(0xFFBE123C), tipo: 'gasto', iconoKey: 'spa', parentId: 'cat_belleza_padre'),
  CatalogoCategoria(id: 'manicura_pedicura', nombre: 'Manicura y pedicura', icono: iconFromKey('scissors'), color: Color(0xFF9F1239), tipo: 'gasto', iconoKey: 'scissors', parentId: 'cat_belleza_padre'),
  // --- Ocio — padre: cat_ocio_padre ---
  CatalogoCategoria(id: 'entretenimiento', nombre: 'Entretenimiento', icono: iconFromKey('movie'), color: Color(0xFFA855F7), tipo: 'gasto', iconoKey: 'movie', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'deporte', nombre: 'Deporte', icono: iconFromKey('fitness_center'), color: Color(0xFF10B981), tipo: 'gasto', iconoKey: 'fitness_center', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'salidas_eventos', nombre: 'Salidas y eventos', icono: iconFromKey('festival'), color: Color(0xFF9333EA), tipo: 'gasto', iconoKey: 'festival', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'hobbies', nombre: 'Hobbies', icono: iconFromKey('celebration'), color: Color(0xFF7E22CE), tipo: 'gasto', iconoKey: 'celebration', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'cine', nombre: 'Cine', icono: iconFromKey('theater'), color: Color(0xFF8B5CF6), tipo: 'gasto', iconoKey: 'theater', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'conciertos', nombre: 'Conciertos', icono: iconFromKey('music_note'), color: Color(0xFF7C3AED), tipo: 'gasto', iconoKey: 'music_note', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'discotecas_bares', nombre: 'Discotecas y bares', icono: iconFromKey('nightlife'), color: Color(0xFF6D28D9), tipo: 'gasto', iconoKey: 'nightlife', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'parques_atracciones', nombre: 'Parques y atracciones', icono: iconFromKey('public'), color: Color(0xFFC084FC), tipo: 'gasto', iconoKey: 'public', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'juegos_azar', nombre: 'Juegos de azar', icono: iconFromKey('casino'), color: Color(0xFF5B21B6), tipo: 'gasto', iconoKey: 'casino', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'gimnasio', nombre: 'Gimnasio', icono: iconFromKey('fitness_center'), color: Color(0xFF059669), tipo: 'gasto', iconoKey: 'fitness_center', parentId: 'cat_ocio_padre'),
  CatalogoCategoria(id: 'equipamiento_deportivo', nombre: 'Equipamiento deportivo', icono: iconFromKey('soccer_ball'), color: Color(0xFF047857), tipo: 'gasto', iconoKey: 'soccer_ball', parentId: 'cat_ocio_padre'),
  // --- Viajes — padre: cat_viajes_padre (nuevo) — separado de Transporte
  // cotidiano porque es un gasto ocasional y agrupado, no un medio de
  // movilidad del día a día. ------------------------------------------
  CatalogoCategoria(id: 'viajes', nombre: 'Alojamiento y vuelos', icono: iconFromKey('flight'), color: Color(0xFF0EA5E9), tipo: 'gasto', iconoKey: 'flight', parentId: 'cat_viajes_padre'),
  CatalogoCategoria(id: 'transporte_viaje', nombre: 'Transporte en el viaje', icono: iconFromKey('explore'), color: Color(0xFF0284C7), tipo: 'gasto', iconoKey: 'explore', parentId: 'cat_viajes_padre'),
  CatalogoCategoria(id: 'actividades_turisticas', nombre: 'Actividades turísticas', icono: iconFromKey('map'), color: Color(0xFF0369A1), tipo: 'gasto', iconoKey: 'map', parentId: 'cat_viajes_padre'),
  CatalogoCategoria(id: 'seguro_viaje', nombre: 'Seguro de viaje', icono: iconFromKey('health_and_safety'), color: Color(0xFF075985), tipo: 'gasto', iconoKey: 'health_and_safety', parentId: 'cat_viajes_padre'),
  CatalogoCategoria(id: 'equipaje', nombre: 'Equipaje', icono: iconFromKey('suitcase'), color: Color(0xFF0C4A6E), tipo: 'gasto', iconoKey: 'suitcase', parentId: 'cat_viajes_padre'),
  CatalogoCategoria(id: 'documentacion_viaje', nombre: 'Documentación de viaje', icono: iconFromKey('badge'), color: Color(0xFF155E75), tipo: 'gasto', iconoKey: 'badge', parentId: 'cat_viajes_padre'),
  // --- Familia y mascotas — padre: cat_familia_padre (nuevo) ---
  CatalogoCategoria(id: 'mascotas', nombre: 'Mascotas', icono: iconFromKey('pets'), color: Color(0xFFD97706), tipo: 'gasto', iconoKey: 'pets', parentId: 'cat_familia_padre'),
  CatalogoCategoria(id: 'hijos', nombre: 'Hijos', icono: iconFromKey('child_friendly'), color: Color(0xFFB45309), tipo: 'gasto', iconoKey: 'child_friendly', parentId: 'cat_familia_padre'),
  CatalogoCategoria(id: 'cuidado_adultos_mayores', nombre: 'Cuidado de adultos mayores', icono: iconFromKey('elderly'), color: Color(0xFF92400E), tipo: 'gasto', iconoKey: 'elderly', parentId: 'cat_familia_padre'),
  CatalogoCategoria(id: 'veterinario', nombre: 'Veterinario', icono: iconFromKey('medical_services'), color: Color(0xFF78350F), tipo: 'gasto', iconoKey: 'medical_services', parentId: 'cat_familia_padre'),
  CatalogoCategoria(id: 'juguetes', nombre: 'Juguetes', icono: iconFromKey('redeem'), color: Color(0xFFC2650C), tipo: 'gasto', iconoKey: 'redeem', parentId: 'cat_familia_padre'),
  // --- Finanzas y ahorro — padre: cat_finanzas_padre (nuevo) — incluye lo
  // que antes vivía suelto bajo "Otros" (ahorros/inversión) más las
  // obligaciones financieras del texto original. -----------------------
  CatalogoCategoria(id: 'comisiones_bancarias', nombre: 'Comisiones bancarias', icono: iconFromKey('point_of_sale'), color: Color(0xFF0D9488), tipo: 'gasto', iconoKey: 'point_of_sale', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'impuestos', nombre: 'Impuestos', icono: iconFromKey('invoice'), color: Color(0xFF0F766E), tipo: 'gasto', iconoKey: 'invoice', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'seguros_generales', nombre: 'Seguros', icono: iconFromKey('health_and_safety'), color: Color(0xFF115E59), tipo: 'gasto', iconoKey: 'health_and_safety', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'cuotas_prestamos', nombre: 'Cuotas de préstamos', icono: iconFromKey('account_balance'), color: Color(0xFF134E4A), tipo: 'gasto', iconoKey: 'account_balance', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'ahorros', nombre: 'Ahorros', icono: iconFromKey('savings'), color: Color(0xFF14B8A6), tipo: 'gasto', iconoKey: 'savings', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'inversion', nombre: 'Inversión', icono: iconFromKey('trending_up'), color: Color(0xFF2DD4BF), tipo: 'gasto', iconoKey: 'trending_up', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'declaraciones_tributarias', nombre: 'Declaraciones tributarias', icono: iconFromKey('assignment'), color: Color(0xFF0E7490), tipo: 'gasto', iconoKey: 'assignment', parentId: 'cat_finanzas_padre'),
  CatalogoCategoria(id: 'penalizaciones_financieras', nombre: 'Penalizaciones financieras', icono: iconFromKey('money_off'), color: Color(0xFF155E75), tipo: 'gasto', iconoKey: 'money_off', parentId: 'cat_finanzas_padre'),
  // --- Compras y regalos — padre: cat_compras_padre (nuevo) ---
  CatalogoCategoria(id: 'regalos_gasto', nombre: 'Regalos y donaciones', icono: iconFromKey('card_giftcard'), color: Color(0xFFE879F9), tipo: 'gasto', iconoKey: 'card_giftcard', parentId: 'cat_compras_padre'),
  CatalogoCategoria(id: 'compras_generales', nombre: 'Compras generales', icono: iconFromKey('mall'), color: Color(0xFFD946EF), tipo: 'gasto', iconoKey: 'mall', parentId: 'cat_compras_padre'),
  CatalogoCategoria(id: 'envios', nombre: 'Envíos y mensajería', icono: iconFromKey('shipping'), color: Color(0xFFC026D3), tipo: 'gasto', iconoKey: 'shipping', parentId: 'cat_compras_padre'),
  CatalogoCategoria(id: 'compras_online', nombre: 'Compras en línea', icono: iconFromKey('offer'), color: Color(0xFFA21CAF), tipo: 'gasto', iconoKey: 'offer', parentId: 'cat_compras_padre'),
  CatalogoCategoria(id: 'garantias_extendidas', nombre: 'Garantías extendidas', icono: iconFromKey('shield'), color: Color(0xFF86198F), tipo: 'gasto', iconoKey: 'shield', parentId: 'cat_compras_padre'),
  // --- Trabajo y negocio — padre: cat_trabajo_padre (nuevo) — gastos de
  // quien tiene un negocio o trabaja de forma independiente; el INGRESO
  // correspondiente ya vive en cat_ingresos_padre (freelance/negocio). --
  CatalogoCategoria(id: 'herramientas_trabajo', nombre: 'Herramientas y equipos', icono: iconFromKey('toolbox'), color: Color(0xFF4338CA), tipo: 'gasto', iconoKey: 'toolbox', parentId: 'cat_trabajo_padre'),
  CatalogoCategoria(id: 'software_profesional', nombre: 'Software profesional', icono: iconFromKey('computer'), color: Color(0xFF3730A3), tipo: 'gasto', iconoKey: 'computer', parentId: 'cat_trabajo_padre'),
  CatalogoCategoria(id: 'publicidad_marketing', nombre: 'Publicidad y marketing', icono: iconFromKey('qr_code'), color: Color(0xFF312E81), tipo: 'gasto', iconoKey: 'qr_code', parentId: 'cat_trabajo_padre'),
  CatalogoCategoria(id: 'formacion_profesional', nombre: 'Formación profesional', icono: iconFromKey('school'), color: Color(0xFF1E1B4B), tipo: 'gasto', iconoKey: 'school', parentId: 'cat_trabajo_padre'),
  CatalogoCategoria(id: 'materiales_insumos', nombre: 'Materiales e insumos', icono: iconFromKey('inventory'), color: Color(0xFF4F46E5), tipo: 'gasto', iconoKey: 'inventory', parentId: 'cat_trabajo_padre'),
  CatalogoCategoria(id: 'dominio_hosting', nombre: 'Dominio y hosting', icono: iconFromKey('router'), color: Color(0xFF3730A3), tipo: 'gasto', iconoKey: 'router', parentId: 'cat_trabajo_padre'),
  // --- Imprevistos — padre: cat_imprevistos_padre (nuevo) ---
  CatalogoCategoria(id: 'emergencias', nombre: 'Emergencias', icono: iconFromKey('warning_amber'), color: Color(0xFFF59E0B), tipo: 'gasto', iconoKey: 'warning_amber', parentId: 'cat_imprevistos_padre'),
  CatalogoCategoria(id: 'reparaciones_urgentes', nombre: 'Reparaciones urgentes', icono: iconFromKey('toolbox'), color: Color(0xFFD97706), tipo: 'gasto', iconoKey: 'toolbox', parentId: 'cat_imprevistos_padre'),
  CatalogoCategoria(id: 'imprevisto_sin_clasificar', nombre: 'Imprevisto sin clasificar', icono: iconFromKey('more_horiz'), color: Color(0xFFB45309), tipo: 'gasto', iconoKey: 'more_horiz', parentId: 'cat_imprevistos_padre'),
  // --- Otros — padre: cat_otros_padre — ya no carga Ropa/Mascotas/
  // Tecnología/Belleza/Regalos, que ahora tienen padre propio. ----------
  CatalogoCategoria(id: 'otro_gasto', nombre: 'Otro gasto sin clasificar', icono: iconFromKey('more_horiz'), color: Color(0xFF6B7280), tipo: 'gasto', iconoKey: 'more_horiz', parentId: 'cat_otros_padre'),
];

/// Todas las categorías: padres + hijas
List<CatalogoCategoria> get todoCatalogo => [...catalogoCategoriaPadres, ...catalogoFinanzas];
