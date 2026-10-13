import 'package:flutter/material.dart';

// Catálogo de íconos de Finanzas. Se intentó migrar a Phosphor Icons
// (phosphor_flutter) para tener una biblioteca más grande, pero ese paquete
// está abandonado desde 2024 y su `PhosphorIconData extends IconData` ya no
// compila en Flutter 3.44+ (IconData pasó a ser `final class`, no se puede
// extender fuera de su librería) — error real reproducido en dispositivo.
// En su lugar se amplió el catálogo con el propio set de Material Icons
// (miles de íconos disponibles), que no tiene ese problema.
const Map<String, IconData> financeIconMap = {
  // Ingresos
  'work': Icons.work_outline,
  'laptop': Icons.laptop_outlined,
  'store': Icons.store_outlined,
  'trending_up': Icons.trending_up,
  'account_balance': Icons.account_balance_outlined,
  'card_giftcard': Icons.card_giftcard_outlined,
  'attach_money': Icons.attach_money,
  // Gastos
  'restaurant': Icons.restaurant_outlined,
  'local_grocery_store': Icons.local_grocery_store_outlined,
  'directions_car': Icons.directions_car_outlined,
  'local_gas_station': Icons.local_gas_station_outlined,
  'home': Icons.home_outlined,
  'bolt': Icons.bolt_outlined,
  'water_drop': Icons.water_drop_outlined,
  'wifi': Icons.wifi_outlined,
  'phone': Icons.phone_outlined,
  'local_hospital': Icons.local_hospital_outlined,
  'medication': Icons.medication_outlined,
  'school': Icons.school_outlined,
  'menu_book': Icons.menu_book_outlined,
  'movie': Icons.movie_outlined,
  'sports_esports': Icons.sports_esports_outlined,
  'music_note': Icons.music_note_outlined,
  'checkroom': Icons.checkroom_outlined,
  'devices': Icons.devices_outlined,
  'flight': Icons.flight_outlined,
  'hotel': Icons.hotel_outlined,
  'pets': Icons.pets_outlined,
  'fitness_center': Icons.fitness_center_outlined,
  'savings': Icons.savings_outlined,
  'credit_card': Icons.credit_card_outlined,
  'swap_horiz': Icons.swap_horiz_outlined,
  'more_horiz': Icons.more_horiz,
  // Subcategorías de transporte/alimentación/salud/vivienda
  'delivery_dining': Icons.delivery_dining_outlined,
  'local_cafe': Icons.local_cafe_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'two_wheeler': Icons.two_wheeler_outlined,
  'local_taxi': Icons.local_taxi_outlined,
  'pedal_bike': Icons.pedal_bike_outlined,
  'health_and_safety': Icons.health_and_safety_outlined,
  'medical_services': Icons.medical_services_outlined,
  'handyman': Icons.handyman_outlined,
  'chair': Icons.chair_outlined,
  // ── Ampliación del catálogo (antes ~42 íconos, ahora bastante más) para
  // que crear una categoría propia no quede corto de opciones.
  'wallet': Icons.account_balance_wallet_outlined,
  'receipt': Icons.receipt_long_outlined,
  'baby': Icons.child_care_outlined,
  'baby_carriage': Icons.stroller_outlined,
  'heart': Icons.favorite_outline,
  'cake': Icons.cake_outlined,
  'beer': Icons.sports_bar_outlined,
  'wine': Icons.wine_bar_outlined,
  'pizza': Icons.local_pizza_outlined,
  'hamburger': Icons.lunch_dining_outlined,
  'train': Icons.train_outlined,
  'boat': Icons.directions_boat_outlined,
  'suitcase': Icons.luggage_outlined,
  'scissors': Icons.content_cut_outlined,
  'paint_brush': Icons.brush_outlined,
  'dog': Icons.pets_outlined,
  'cat': Icons.pets,
  'tree': Icons.park_outlined,
  'leaf': Icons.eco_outlined,
  'recycle': Icons.recycling_outlined,
  'lightbulb': Icons.lightbulb_outline,
  'television': Icons.tv_outlined,
  'camera': Icons.camera_alt_outlined,
  'headphones': Icons.headphones_outlined,
  'calculator': Icons.calculate_outlined,
  'coin': Icons.monetization_on_outlined,
  'hammer': Icons.construction_outlined,
  'broom': Icons.cleaning_services_outlined,
  'washing_machine': Icons.local_laundry_service_outlined,
  'umbrella': Icons.beach_access_outlined,
  'sun': Icons.wb_sunny_outlined,
  'moon': Icons.nightlight_outlined,
  'cloud': Icons.cloud_outlined,
  'toolbox': Icons.build_outlined,
  'syringe': Icons.vaccines_outlined,
  'tooth': Icons.medical_information_outlined,
  'eyeglasses': Icons.visibility_outlined,
  'soccer_ball': Icons.sports_soccer_outlined,
  'basketball': Icons.sports_basketball_outlined,
  'volleyball': Icons.sports_volleyball_outlined,
  'bed': Icons.bed_outlined,
  'shower': Icons.shower_outlined,
  'bathtub': Icons.bathtub_outlined,
  'key': Icons.vpn_key_outlined,
  'lock': Icons.lock_outline,
  'user_circle': Icons.account_circle_outlined,
  'users': Icons.groups_outlined,
  'church': Icons.church_outlined,
  'book_open_text': Icons.auto_stories_outlined,
  'newspaper': Icons.newspaper,
  'gas_can': Icons.propane_tank_outlined,
  'currency_dollar': Icons.attach_money,
  'ticket': Icons.confirmation_number_outlined,
  'popcorn': Icons.theaters_outlined,
  'pants': Icons.checkroom_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'tag': Icons.label_outline,

  // ── Comida y bebida ──────────────────────────────────────────────────────
  'icecream': Icons.icecream_outlined,
  'bakery': Icons.bakery_dining_outlined,
  'ramen': Icons.ramen_dining_outlined,
  'bar': Icons.local_bar_outlined,
  'seafood': Icons.set_meal_outlined,
  'cookie': Icons.cookie_outlined,
  'liquor': Icons.liquor_outlined,
  'fastfood': Icons.fastfood_outlined,
  'dinner': Icons.dinner_dining_outlined,
  'kebab': Icons.kebab_dining_outlined,
  'brunch': Icons.brunch_dining_outlined,

  // ── Transporte ───────────────────────────────────────────────────────────
  'subway': Icons.directions_subway_outlined,
  'tram': Icons.tram_outlined,
  'scooter': Icons.electric_scooter_outlined,
  'shipping': Icons.local_shipping_outlined,
  'shuttle': Icons.airport_shuttle_outlined,
  'car_rental': Icons.car_rental_outlined,
  'ev_station': Icons.ev_station_outlined,
  'parking': Icons.local_parking_outlined,

  // ── Hogar y mantenimiento ────────────────────────────────────────────────
  'plumbing': Icons.plumbing_outlined,
  'electrical': Icons.electrical_services_outlined,
  'yard': Icons.yard_outlined,
  'roofing': Icons.roofing_outlined,
  'countertop': Icons.countertops_outlined,
  'kitchen': Icons.kitchen_outlined,
  'door': Icons.door_front_door_outlined,
  'window': Icons.window_outlined,

  // ── Salud y bienestar ────────────────────────────────────────────────────
  'healing': Icons.healing_outlined,
  'masks': Icons.masks_outlined,
  'psychology': Icons.psychology_outlined,
  'spa': Icons.spa_outlined,
  'monitor_heart': Icons.monitor_heart_outlined,

  // ── Compras y moda ───────────────────────────────────────────────────────
  'mall': Icons.local_mall_outlined,
  'jewelry': Icons.diamond_outlined,
  'watch': Icons.watch_outlined,
  'dry_cleaning': Icons.dry_cleaning_outlined,

  // ── Entretenimiento y ocio ───────────────────────────────────────────────
  'casino': Icons.casino_outlined,
  'nightlife': Icons.nightlife_outlined,
  'theater': Icons.theater_comedy_outlined,
  'celebration': Icons.celebration_outlined,
  'festival': Icons.festival_outlined,
  'museum': Icons.museum_outlined,
  'stadium': Icons.stadium_outlined,

  // ── Tecnología ───────────────────────────────────────────────────────────
  'smartphone': Icons.smartphone_outlined,
  'computer': Icons.computer_outlined,
  'router': Icons.router_outlined,
  'printer': Icons.print_outlined,
  'keyboard': Icons.keyboard_outlined,

  // ── Trabajo y finanzas ───────────────────────────────────────────────────
  'business': Icons.business_center_outlined,
  'corporate': Icons.corporate_fare_outlined,
  'handshake': Icons.handshake_outlined,
  'paid': Icons.paid_outlined,
  'point_of_sale': Icons.point_of_sale_outlined,
  'invoice': Icons.request_quote_outlined,

  // ── Educación ────────────────────────────────────────────────────────────
  'science': Icons.science_outlined,
  'history_edu': Icons.history_edu_outlined,
  'language': Icons.language_outlined,

  // ── Familia y mascotas ───────────────────────────────────────────────────
  'family': Icons.family_restroom_outlined,
  'elderly': Icons.elderly_outlined,
  'child_friendly': Icons.child_friendly_outlined,
  'cruelty_free': Icons.cruelty_free_outlined,

  // ── Viajes y naturaleza ──────────────────────────────────────────────────
  'hiking': Icons.hiking_outlined,
  'forest': Icons.forest_outlined,
  'terrain': Icons.terrain_outlined,
  'map': Icons.map_outlined,
  'explore': Icons.explore_outlined,
  'public': Icons.public_outlined,

  // ── Deporte y fitness ────────────────────────────────────────────────────
  'tennis': Icons.sports_tennis_outlined,
  'golf': Icons.sports_golf_outlined,
  'handball': Icons.sports_handball_outlined,
  'pool': Icons.pool_outlined,
  'self_improvement': Icons.self_improvement_outlined,
  'running': Icons.directions_run_outlined,
  'walking': Icons.directions_walk_outlined,

  // ── Clima y naturaleza ───────────────────────────────────────────────────
  'ac_unit': Icons.ac_unit_outlined,
  'thunderstorm': Icons.thunderstorm_outlined,
  'water': Icons.water_outlined,
  'grass': Icons.grass_outlined,
  'florist': Icons.local_florist_outlined,

  // ── Otros / servicios ────────────────────────────────────────────────────
  'donation': Icons.volunteer_activism_outlined,
  'trophy': Icons.emoji_events_outlined,
  'medal': Icons.military_tech_outlined,
  'redeem': Icons.redeem_outlined,
  'membership': Icons.card_membership_outlined,
  'loyalty': Icons.loyalty_outlined,
  'qr_code': Icons.qr_code_outlined,
  'inventory': Icons.inventory_2_outlined,
  'warehouse': Icons.warehouse_outlined,
};

IconData iconFromKey(String? key) =>
    key != null ? (financeIconMap[key] ?? Icons.label_outline) : Icons.label_outline;
